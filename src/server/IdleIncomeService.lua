--[[
	Abyssara – Deep Tide Tycoon
	Modul: IdleIncomeService
	Zuständigkeit:
		Kernlogik des Idle-Einkommen-/Produktionssystems (GDD Abschnitt 3
		"Minute-zu-Minute" + Abschnitt 9, Punkt 3): berechnet serverseitig,
		wie viele Tide Coins pro Minute ein Spieler anhand seines aktuellen
		Habitat-Layouts (PlayerDataService.GetHabitatLayout, Produktionsraten
		aus BuildingConfig.IncomeRate) verdient, und schreibt dieses
		Einkommen über zwei Wege gut:

			1. Online-Tick-Loop: läuft periodisch (IDLE_TICK_INTERVAL_SECONDS)
			   für jeden aktuell verbundenen, geladenen Spieler.
			2. Offline-Progress: einmalig beim Login, anhand der seit der
			   letzten Gutschrift vergangenen Zeit, gedeckelt auf maximal
			   OFFLINE_INCOME_CAP_SECONDS (GDD-Vorgabe: max. 4h).

		Beide Wege schreiben denselben Zeitstempel fort
		(PlayerDataService.Get/SetLastIncomeAt) - dadurch können sie sich
		NIE überschneiden/doppelt auszahlen: der Online-Tick verbraucht die
		Zeit seit der letzten Gutschrift (die zuletzt gesetzte Offline-
		Gutschrift beim Login zählt als "letzte Gutschrift"), und die
		Offline-Berechnung beim nächsten Login verbraucht wiederum die Zeit
		seit der letzten Online-Tick-Gutschrift.

		Reine Logik + eigener Tick-Loop/PlayerAdded-Hook, keine
		Remote-Verdrahtung außer dem direkten Feuern der reinen Feedback-
		Events aus IdleIncomeRemotes (kein Client-Request-Handler nötig, da
		der Client hier nichts anfordert - siehe IdleIncomeRemotes.lua).

	Sicherheitsprinzip (kein Client-Trust):
		Der Client liefert NICHTS in dieses System ein. Jede Gutschrift wird
		ausschließlich aus serverseitig bereits validierten/persistenten
		Daten berechnet (HabitatLayout kommt aus PlayerDataService, das
		wiederum nur über PlacementService/PlayerDataService-Setter verändert
		wird - beide bereits serverseitig abgesichert). Der Client bekommt
		über IdleIncomeRemotes ausschließlich fertige Ergebnisse zur Anzeige.

	Performance:
		- Online-Tick-Intervall bewusst mit 20s eher grob gewählt (siehe
		  IDLE_TICK_INTERVAL_SECONDS) - kein "while true do wait() end" pro
		  Spieler, sondern EIN gemeinsamer Loop, der über alle Online-
		  Spieler iteriert. Die Produktionsberechnung pro Spieler ist eine
		  simple Summe über eine kleine Liste (Habitat-Layout, MVP: wenige
		  Gebäude) - keine teure Pro-Frame-Arbeit.
		- Jede Spieler-Gutschrift läuft in einem eigenen task.spawn, damit
		  ein langsamer/fehlerhafter Einzelfall (z. B. AddCurrency-Edge-Case)
		  nicht den Tick für alle anderen Spieler blockiert.

	Rojo-Einhängepunkt:
		src/server/IdleIncomeService.lua -> ServerScriptService.IdleIncomeService
		(reines Server-Modul; verdrahtet PlayerAdded und den Tick-Loop selbst
		beim ersten require() - gleiche Konvention wie PlayerDataService/
		GachaService. Ein einfaches require(...) aus einem zentralen
		Server-Startskript genügt.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local BuildingConfig = require(ReplicatedStorage:WaitForChild("BuildingConfig"))
local IdleIncomeRemotes = require(ReplicatedStorage:WaitForChild("IdleIncomeRemotes"))
local ZoneEconomyConfig = require(ReplicatedStorage:WaitForChild("ZoneEconomyConfig"))

local IdleIncomeService = {}

-- // Konfiguration ------------------------------------------------------------

local IDLE_TICK_INTERVAL_SECONDS = 20 -- Online-Tick-Frequenz: grob genug für Performance, fein genug fürs Gefühl von "passivem" Einkommen
local SECONDS_PER_MINUTE = 60

-- Schutz gegen ungewöhnlich große Lücken im Online-Tick selbst (z. B. Server
-- unter Last, ein einzelner Tick verzögert sich stark): pro Online-Tick wird
-- höchstens das 3-fache des regulären Intervalls gutgeschrieben. Größere
-- Lücken (z. B. echtes Offline-Sein) werden NICHT hier, sondern beim
-- nächsten Login über den Offline-Progress-Pfad abgerechnet.
local ONLINE_TICK_MAX_ELAPSED_SECONDS = IDLE_TICK_INTERVAL_SECONDS * 3

-- GDD Abschnitt 9, Punkt 3: "Cap z. B. max. 4h Offline-Gewinn".
local OFFLINE_INCOME_CAP_SECONDS = 4 * 60 * 60

-- Unterhalb dieser Lücke wird keine Offline-Progress-Zusammenfassung an den
-- Client gesendet (vermeidet ein "Während du weg warst: +0 Tide Coins"-
-- Popup bei jedem kurzen Reconnect/Teleport). Der Zeitstempel wird trotzdem
-- IMMER aktualisiert, damit sich Kleinstlücken nicht aufsummieren.
local MIN_OFFLINE_SECONDS_TO_NOTIFY = 60

local JOIN_DATA_TIMEOUT_SECONDS = 15

-- // Produktionsberechnung ----------------------------------------------------

--- Summiert die Tide-Coin-Produktion/Minute aller aktuell platzierten
--- Gebäude eines Spielers (nur Gebäude mit BuildingConfig.IncomeRate > 0
--- zählen - BroodPool/AnglerfishTower liefern laut BuildingConfig 0), und
--- wendet den Prestige-Einkommensmultiplikator, den Content-Update-1-
--- Zonen-Multiplikator (siehe ZoneEconomyConfig-Kopfkommentar: "Zone des
--- Spielers" = tiefste per Level freigeschaltete Zone) sowie (falls
--- vorhanden) den "2x Tide Coins"-Gamepass-Multiplikator an (GDD Abschnitt 5
--- + 6). Unbekannte BuildingIds (z. B. aus künftig entfernten Gebäudetypen)
--- werden übersprungen statt den Server abstürzen zu lassen.
---
--- BEWUSST ein LAZY require() von MonetizationService (Funktionskörper statt
--- Modul-Kopf) - identische Begründung wie in BreedingService.
--- RequestStartBreeding/RaidService.applyDoubleCoinsGamepass: bricht einen
--- potenziellen zirkulären require-Zyklus, falls MonetizationService
--- irgendwann IdleIncomeService referenziert.
local function computeIncomePerMinute(player: Player): number
	local layout = PlayerDataService.GetHabitatLayout(player)

	-- Live-Event-Einhängepunkt (docs/content-update-1.md Abschnitt 1.3 + 7b):
	-- BEWUSST ein LAZY require() (Funktionskörper statt Modul-Kopf), analog
	-- zum bereits bestehenden MonetizationService-Lazy-require unten - bricht
	-- einen potenziellen zirkulären require-Zyklus, falls LiveEventService
	-- irgendwann (z. B. über ein künftiges Modul) IdleIncomeService
	-- referenziert. Je-Gebäude-Multiplikator statt eines pauschalen Faktors,
	-- da einzelne Events (Toxic Tide/Bloom) nur EINEN Gebäudetyp verstärken,
	-- andere (Frozen Current/Treasure Tide) ALLE Gebäude gleichermaßen
	-- beeinflussen - siehe LiveEventService.GetBuildingIncomeMultiplier.
	local LiveEventService = require(script.Parent:WaitForChild("LiveEventService"))

	local totalPerMinute = 0
	for _, placement in ipairs(layout) do
		local definition = BuildingConfig.Get(placement.BuildingId)
		if definition and definition.IncomeRate and definition.IncomeRate > 0 then
			-- Gebäude-Upgrade-System (siehe docs/building-upgrades.md):
			-- HabitatPlacement.Level (1-3) skaliert die Basis-IncomeRate via
			-- BuildingConfig.GetIncomeMultiplier - liefert 1 (neutral) für
			-- Nicht-Produktionsgebäude/unbekannte Stufen, siehe dortige
			-- Kopfkommentar.
			local stageMultiplier = BuildingConfig.GetIncomeMultiplier(placement.BuildingId, placement.Level)
			totalPerMinute += definition.IncomeRate * stageMultiplier * LiveEventService.GetBuildingIncomeMultiplier(placement.BuildingId)
		end
	end

	local multiplier = PlayerDataService.GetIncomeMultiplier(player)

	-- Content Update 1, Abschnitt 6: "tiefere Zonen zahlen sich besser aus" -
	-- siehe ZoneEconomyConfig-Kopfkommentar für die volle Begründung, warum
	-- "Zone des Spielers" hier rein aus dem Level abgeleitet wird statt aus
	-- einer physischen Position.
	local zone = ZoneEconomyConfig.GetZoneForLevel(PlayerDataService.GetLevel(player))
	multiplier *= ZoneEconomyConfig.GetIncomeMultiplier(zone)

	local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
	if MonetizationService.PlayerOwnsGamepass(player, "DoubleCoins") then
		multiplier *= MonetizationService.GetDoubleCoinsMultiplier()
	end

	return totalPerMinute * multiplier
end

--- Liefert das für `player` geltende Offline-Einkommens-Cap in Sekunden -
--- Standard GDD-Cap (4h), ODER das verlängerte Auto-Collector-Cap (siehe
--- ShopConfig.AUTO_COLLECTOR_OFFLINE_CAP_SECONDS-Kommentar zur Abweichung
--- vom wörtlichen GDD-Effekt "ohne Klicken" - dieses System hat ohnehin nie
--- Klicken gebraucht).
local function computeOfflineIncomeCapSeconds(player: Player): number
	local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
	if MonetizationService.PlayerOwnsGamepass(player, "AutoCollector") then
		return MonetizationService.GetAutoCollectorOfflineCapSeconds()
	end
	return OFFLINE_INCOME_CAP_SECONDS
end

-- // Online-Tick ---------------------------------------------------------------

--- Schreibt einem einzelnen Online-Spieler das seit seiner letzten
--- Gutschrift verdiente Einkommen gut (geklemmt auf
--- ONLINE_TICK_MAX_ELAPSED_SECONDS) und aktualisiert LastIncomeAt. Feuert
--- IncomeGranted NUR bei tatsächlich positivem Betrag - kein Spam für
--- Spieler ohne Produktionsgebäude.
local function grantOnlineTick(player: Player)
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end

	local now = os.time()
	local lastIncomeAt = PlayerDataService.GetLastIncomeAt(player)
	local elapsedSeconds = math.clamp(now - lastIncomeAt, 0, ONLINE_TICK_MAX_ELAPSED_SECONDS)

	local perMinute = computeIncomePerMinute(player)

	if perMinute <= 0 or elapsedSeconds <= 0 then
		-- Kein Produktionsgebäude platziert oder keine Zeit vergangen: nur
		-- den Zeitstempel nachziehen, damit sich keine "geschuldete" Zeit
		-- unbegrenzt aufstaut, bis der Spieler doch noch baut.
		PlayerDataService.SetLastIncomeAt(player, now)
		return
	end

	local amount = math.floor((perMinute * (elapsedSeconds / SECONDS_PER_MINUTE)) + 0.5)
	PlayerDataService.SetLastIncomeAt(player, now)

	if amount <= 0 then
		return
	end

	local ok, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", amount)
	if not ok then
		return
	end

	IdleIncomeRemotes.IncomeGranted:FireClient(player, {
		Amount = amount,
		NewBalance = newBalance,
	})
end

local function runOnlineTickLoop()
	while true do
		task.wait(IDLE_TICK_INTERVAL_SECONDS)

		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(grantOnlineTick, player)
		end
	end
end

-- // Offline-Progress -----------------------------------------------------------

--- Berechnet und schreibt einmalig das Offline-Einkommen seit der letzten
--- Gutschrift gut (gedeckelt auf OFFLINE_INCOME_CAP_SECONDS), unabhängig
--- davon, ob der Betrag positiv ist - der Zeitstempel wird IMMER auf `now`
--- gesetzt, damit der nachfolgende Online-Tick-Loop nicht dieselbe Zeit ein
--- zweites Mal abrechnet.
local function grantOfflineProgress(player: Player)
	local now = os.time()
	local lastIncomeAt = PlayerDataService.GetLastIncomeAt(player)
	local elapsedSeconds = math.max(0, now - lastIncomeAt)
	local offlineCapSeconds = computeOfflineIncomeCapSeconds(player)
	local cappedSeconds = math.min(elapsedSeconds, offlineCapSeconds)

	local perMinute = computeIncomePerMinute(player)
	local amount = 0
	if perMinute > 0 and cappedSeconds > 0 then
		amount = math.floor((perMinute * (cappedSeconds / SECONDS_PER_MINUTE)) + 0.5)
	end

	-- Zeitstempel IMMER fortschreiben (auch bei amount == 0) - schließt die
	-- Lücke zum Online-Tick-Loop sauber, siehe Kopfkommentar.
	PlayerDataService.SetLastIncomeAt(player, now)

	if amount > 0 then
		PlayerDataService.AddCurrency(player, "TideCoins", amount)
	end

	if elapsedSeconds < MIN_OFFLINE_SECONDS_TO_NOTIFY then
		return
	end

	IdleIncomeRemotes.OfflineProgressSummary:FireClient(player, {
		Amount = amount,
		NewBalance = PlayerDataService.GetCurrency(player, "TideCoins"),
		ElapsedSeconds = elapsedSeconds,
		CappedSeconds = cappedSeconds,
		WasCapped = elapsedSeconds > offlineCapSeconds,
	})
end

local function onPlayerAdded(player: Player)
	local data = PlayerDataService.WaitForData(player, JOIN_DATA_TIMEOUT_SECONDS)
	if not data then
		-- Laden fehlgeschlagen/Timeout: PlayerDataService kickt den Spieler
		-- in diesem Fall bereits selbst - hier nur sauber abbrechen.
		return
	end

	if not Players:GetPlayerByUserId(player.UserId) then
		-- Spieler während des Ladens bereits wieder disconnected.
		return
	end

	grantOfflineProgress(player)
end

-- // Bootstrap ------------------------------------------------------------------

Players.PlayerAdded:Connect(onPlayerAdded)

-- Falls dieses Modul erst nach PlayerAdded-Events requiret wird (z. B.
-- Studio-Playtest-Timing), bereits verbundene Spieler nachträglich einbuchen
-- - gleiche Absicherung wie PlayerDataService/PlacementServer.
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

task.spawn(runOnlineTickLoop)

-- // Öffentliche API (v. a. für Tests/zukünftige Systeme, z. B. ein HUD-Panel,
-- das die aktuelle Produktionsrate live anzeigen will) ------------------------

--- Liefert die aktuelle Tide-Coin-Produktion/Minute eines Spielers (bereits
--- inkl. Prestige-Multiplikator). Rein lesend, keine Gutschrift.
function IdleIncomeService.GetIncomePerMinute(player: Player): number
	return computeIncomePerMinute(player)
end

return IdleIncomeService
