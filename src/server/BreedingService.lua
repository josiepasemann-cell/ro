--[[
	Abyssara – Deep Tide Tycoon
	Modul: BreedingService
	Zuständigkeit:
		Kernlogik des Zucht-/Ei-Systems (GDD Abschnitt 3 "Füttert & züchtet
		Kreaturen in Brutbecken, Timer-basiert, wie Ei-Schlüpfen" + Abschnitt
		9, Punkt 4): Start einer Zucht an einem platzierten BroodPool-Gebäude
		(Kosten prüfen/abziehen, Rarity-Roll, Timer persistieren) und Abholen
		einer fertigen Zucht (Kreatur ins Inventar buchen, Brutbecken wieder
		freigeben). Unabhängig vom bereits fertigen Mystery-Egg-Gacha-System
		(GachaService) - beide teilen sich nur dasselbe Kreaturen-Inventar-
		Format über PlayerDataService.AddCreatureToInventory.

		Nutzt für JEDE Persistenz-Operation ausschließlich die bestehende
		PlayerDataService-API (GetHabitatLayout, Get/Add/RemoveIncubation,
		GetCurrency/AddCurrency, AddCreatureToInventory) - erfindet keine
		eigene Persistenz.

		Reine Logik, keine Remote-Verdrahtung - die übernimmt
		BreedingServer.server.lua (analog zu GachaService/GachaServer.
		server.lua bzw. PlacementService/PlacementServer.server.lua), damit
		dieses Modul unabhängig von RemoteEvents testbar bleibt.

	Sicherheitsprinzip (kein Client-Trust):
		Jede öffentliche Funktion hier nimmt zwar eine rohe, vom Client
		behauptete `placementId` entgegen, validiert sie aber IMMER gegen das
		EIGENE, bereits serverseitig persistente HabitatLayout des
		anfragenden Spielers (PlayerDataService.GetHabitatLayout) - ein
		Spieler kann dadurch grundsätzlich weder eine fremde PlacementId
		noch ein Nicht-BroodPool-Gebäude ansprechen. Rarity/Kreatur werden
		AUSSCHLIESSLICH hier serverseitig gewürfelt (rollWeightedRarity),
		niemals vom Client übernommen.

	Design-Entscheidung "Roll beim Start statt beim Abholen":
		Das Zucht-ERGEBNIS (CreatureId/Rarity) wird bereits beim Start der
		Inkubation gewürfelt und in PlayerDataService.BreedingState
		persistiert (siehe PlayerDataService.AddIncubation) - NICHT erst beim
		Abholen. Das macht das System robust gegen Serverneustarts (kein
		erneutes Würfeln nötig, das Ergebnis steht schon fest, sobald der
		Timer läuft) und verhindert einen theoretischen Exploit-Vektor
		("Server-Reroll" durch wiederholtes Abholen-Anfragen). Das Ergebnis
		bleibt dem Client trotzdem bis zum tatsächlichen Abholen verborgen -
		StartBreedingResult enthält bewusst NUR den Zeitstempel, niemals
		CreatureId/Rarity (siehe BreedingRemotes).

	Rojo-Einhängepunkt:
		src/server/BreedingService.lua -> ServerScriptService.BreedingService
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local ProgressionService = require(script.Parent:WaitForChild("ProgressionService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local HeldItemService = require(script.Parent:WaitForChild("HeldItemService"))
local BreedingConfig = require(ReplicatedStorage:WaitForChild("BreedingConfig"))

type Rarity = BreedingConfig.Rarity
type BreedingIncubation = PlayerDataService.BreedingIncubation

export type StartFailureReason =
	"DataNotLoaded"
	| "InvalidPlacement"
	| "NotOwned"
	| "NotABroodPool"
	| "AlreadyIncubating"
	| "InsufficientFunds"
	| "ChargeFailed"
	| "PersistenceFailed"

export type ClaimFailureReason = "DataNotLoaded" | "InvalidPlacement" | "NoActiveIncubation" | "NotReadyYet"

export type StartResult = {
	Success: boolean,
	Reason: StartFailureReason?,
	PlacementId: string?,
	StartedAt: number?,
	ReadyAt: number?,
	FeedCost: number?,
	NewBalance: number?,
}

export type ClaimResult = {
	Success: boolean,
	Reason: ClaimFailureReason?,
	PlacementId: string?,
	CreatureId: string?,
	CreatureName: string?,
	Rarity: string?,
	RemainingSeconds: number?,
}

export type BroodPoolStatus = {
	PlacementId: string,
	State: "Empty" | "Incubating" | "Ready",
	StartedAt: number?,
	ReadyAt: number?,
	RemainingSeconds: number?,
}

local BreedingService = {}

local rng = Random.new()

-- // Hilfsfunktionen ------------------------------------------------------

--- Sucht die HabitatPlacement des anfragenden Spielers mit `placementId`,
--- die ZUSÄTZLICH ein BroodPool-Gebäude sein muss. Da GetHabitatLayout
--- ausschließlich die Daten DES anfragenden Spielers zurückliefert, ist
--- Eigentümerschaft hier implizit bereits sichergestellt - ein Spieler kann
--- technisch keine fremde PlacementId "erraten" und damit etwas an einem
--- fremden Brutbecken auslösen.
local function findOwnBroodPoolPlacement(player: Player, placementId: string): PlayerDataService.HabitatPlacement?
	for _, placement in ipairs(PlayerDataService.GetHabitatLayout(player)) do
		if placement.PlacementId == placementId then
			if placement.BuildingId ~= "BroodPool" then
				return nil
			end
			return placement
		end
	end
	return nil
end

--- Gewichteter Zufalls-Roll einer Rarity über die RarityWeights einer
--- BreedingConfig-Stufe (identisches Prinzip zu GachaService.
--- rollWeightedRarity, aber mit den bewusst niedrigeren Zucht-Gewichten).
local function rollWeightedRarity(tier: BreedingConfig.BreedingTier): Rarity
	local totalWeight = BreedingConfig.GetTotalWeight(tier)
	local roll = rng:NextNumber() * totalWeight
	local cumulative = 0
	for _, rarity in ipairs(BreedingConfig.RARITY_ORDER) do
		cumulative += tier.RarityWeights[rarity] or 0
		if roll <= cumulative then
			return rarity
		end
	end
	-- Numerischer Sicherheitsfallback (Floating-Point-Rundung).
	return BreedingConfig.RARITY_ORDER[#BreedingConfig.RARITY_ORDER]
end

--- Wählt zufällig eine Kreatur aus dem Zucht-Pool der übergebenen Rarity.
local function pickCreatureForRarity(rarity: Rarity): string
	local pool = BreedingConfig.CREATURE_POOL[rarity]
	if not pool or #pool == 0 then
		error(("[BreedingService] Kein Zucht-Kreaturen-Pool für Rarity '%s' vorhanden."):format(rarity))
	end
	return pool[rng:NextInteger(1, #pool)]
end

--- Liest den Anzeigenamen einer Kreatur: bevorzugt LIVE vom bereits in
--- Workspace.Assets.Creatures platzierten Modell (Attribut "CreatureName"),
--- sonst Fallback aus BreedingConfig - identisches Prinzip zu GachaService.
local function getCreatureDisplayName(creatureId: string): string
	local creaturesFolder = Workspace:FindFirstChild("Assets")
	creaturesFolder = creaturesFolder and creaturesFolder:FindFirstChild("Creatures")
	if creaturesFolder then
		local model = creaturesFolder:FindFirstChild(creatureId)
		if model and model:IsA("Model") then
			local liveName = model:GetAttribute("CreatureName")
			if typeof(liveName) == "string" and liveName ~= "" then
				return liveName
			end
		end
	end
	return BreedingConfig.CREATURE_DISPLAY_NAME_FALLBACK[creatureId] or creatureId
end

-- // Hand-Übergabe (docs/held-items.md, Abschnitt 7 "Künftige Aufrufer") ---
-- HeldItemConfig kennt "Creature" bereits als ItemKind - dieser Abschnitt
-- setzt GENAU den dort skizzierten Aufruf um: nach erfolgreichem Abholen
-- wandert die geschlüpfte Kreatur kurz sichtbar in die Hand. Legt automatisch
-- nach HAND_OFF_AUTO_DROP_SECONDS wieder ab (Auftrag Punkt 5) - OHNE
-- HeldItemService selbst anzufassen (nicht Teil der erlaubten Änderungen),
-- daher als einfacher, hier lokaler task.delay-Timer umgesetzt, der defensiv
-- prüft, ob der Spieler zwischenzeitlich bereits ein ANDERES Item aufgenommen
-- hat (dann NICHT ablegen - HeldItem legt Vorgänger-Items beim Aufnehmen
-- eines neuen Items ohnehin bereits selbst automatisch ab, siehe
-- HeldItemService.HoldItem-Kopfkommentar "Hält der Spieler bereits ein
-- anderes Item...").
local HAND_OFF_AUTO_DROP_SECONDS = 6

local function holdHatchedCreatureInHand(player: Player, creatureId: string, creatureName: string)
	local creaturesFolder = Workspace:FindFirstChild("Assets")
	creaturesFolder = creaturesFolder and creaturesFolder:FindFirstChild("Creatures")
	local template = creaturesFolder and creaturesFolder:FindFirstChild(creatureId)
	if not template or not template:IsA("Model") then
		-- Kreaturen-Modell (noch) nicht in der Welt vorhanden (Buildscript nie
		-- in Studio ausgeführt, siehe assets/models/README.md) - kein
		-- Fehlerzustand fürs eigentliche Zucht-Ergebnis, einfach überspringen.
		return
	end

	local ok, heldModel = HeldItemService.HoldItem(player, "Creature", template, {
		DisplayName = creatureName,
	})
	if not ok or not heldModel then
		return
	end

	task.delay(HAND_OFF_AUTO_DROP_SECONDS, function()
		local held = HeldItemService.GetHeld(player)
		if held and held.Model == heldModel then
			HeldItemService.DropHeld(player)
		end
	end)
end

--- Baut den öffentlichen Status EINER Inkubation (oder eines leeren
--- Brutbeckens) für den Client auf - enthält absichtlich niemals
--- CreatureId/Rarity vor dem Abholen (siehe Design-Entscheidung oben).
local function buildStatus(placementId: string, incubation: BreedingIncubation?): BroodPoolStatus
	if not incubation then
		return { PlacementId = placementId, State = "Empty" }
	end

	local now = os.time()
	if now >= incubation.ReadyAt then
		return {
			PlacementId = placementId,
			State = "Ready",
			StartedAt = incubation.StartedAt,
			ReadyAt = incubation.ReadyAt,
			RemainingSeconds = 0,
		}
	end

	return {
		PlacementId = placementId,
		State = "Incubating",
		StartedAt = incubation.StartedAt,
		ReadyAt = incubation.ReadyAt,
		RemainingSeconds = incubation.ReadyAt - now,
	}
end

-- // Öffentliche API ------------------------------------------------------

--- Validiert und startet eine Zucht an einem eigenen, freien BroodPool-
--- Gebäude vollständig serverseitig. `placementId` ist ein unvertrauter,
--- angeblicher Client-Wert - wird komplett neu gegen das eigene
--- HabitatLayout geprüft, bevor irgendetwas verändert wird.
function BreedingService.RequestStartBreeding(player: Player, placementId: any): StartResult
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if type(placementId) ~= "string" then
		return { Success = false, Reason = "InvalidPlacement" }
	end

	local placement = findOwnBroodPoolPlacement(player, placementId)
	if not placement then
		-- Entweder existiert die PlacementId gar nicht im eigenen Layout
		-- (weder eigenes noch fremdes Gebäude erreichbar - siehe
		-- findOwnBroodPoolPlacement), oder sie referenziert ein Gebäude,
		-- das kein BroodPool ist. Beides wird hier bewusst NICHT
		-- unterschieden ("NotOwned" vs. "NotABroodPool"), um Angreifern
		-- keine Information über fremde Layouts preiszugeben.
		return { Success = false, Reason = "NotABroodPool" }
	end

	if PlayerDataService.GetIncubationForPlacement(player, placementId) then
		return { Success = false, Reason = "AlreadyIncubating" }
	end

	local tier = BreedingConfig.GetTier(placement.Level)

	local balance = PlayerDataService.GetCurrency(player, "TideCoins")
	if balance < tier.FeedCostTideCoins then
		return { Success = false, Reason = "InsufficientFunds" }
	end

	-- Ergebnis JETZT würfeln (siehe Design-Entscheidung im Kopfkommentar),
	-- BEVOR Kosten abgezogen werden - ein Fehler danach (Persistenz) kann so
	-- risikofrei ohne Rollback des Rolls abgebrochen werden.
	local rarity = rollWeightedRarity(tier)
	local creatureId = pickCreatureForRarity(rarity)

	local chargeOk, newBalance = PlayerDataService.AddCurrency(player, "TideCoins", -tier.FeedCostTideCoins)
	if not chargeOk then
		return { Success = false, Reason = "ChargeFailed" }
	end

	-- GDD Abschnitt 5: VIP-Taucher-Gamepass gewährt "1,5x Zucht-
	-- Geschwindigkeit" - Inkubationsminuten werden entsprechend verkürzt.
	-- BEWUSST ein LAZY require() (erst hier im Funktionskörper, nicht am
	-- Modul-Kopf) statt eines normalen Top-Level-requires: MonetizationService
	-- selbst benötigt BreedingService (für das InstantBreeding-Entwickler-
	-- produkt, siehe dort), ein Top-Level-require hier würde also einen
	-- zirkulären require-Zyklus erzeugen (Roblox/Luau liefert in diesem Fall
	-- ein noch unvollständiges Modul-Table zurück). Ein lazy require im
	-- Funktionskörper wird erst zur Laufzeit ausgeführt (lange nachdem beide
	-- Module vollständig geladen sind) und liefert dann zuverlässig das
	-- fertige, gecachte Modul-Table - kein Zyklus beim Server-Start.
	local MonetizationService = require(script.Parent:WaitForChild("MonetizationService"))
	local incubationMinutes = tier.IncubationMinutes
	if MonetizationService.PlayerOwnsGamepass(player, "VIPDiver") then
		incubationMinutes = incubationMinutes / MonetizationService.GetVipBreedingSpeedMultiplier()
	end

	local now = os.time()
	local readyAt = now + (incubationMinutes * 60)

	local incubation = PlayerDataService.AddIncubation(player, {
		PlacementId = placementId,
		StartedAt = now,
		ReadyAt = readyAt,
		CreatureId = creatureId,
		Rarity = rarity,
	})

	if not incubation then
		-- Persistenz fehlgeschlagen (z. B. Daten zwischen Prüfung und
		-- Schreiben entladen, oder - defensiv - eine zwischenzeitlich
		-- doch schon existierende Inkubation) - bereits abgezogene Kosten
		-- zurückerstatten.
		PlayerDataService.AddCurrency(player, "TideCoins", tier.FeedCostTideCoins)
		return { Success = false, Reason = "PersistenceFailed" }
	end

	return {
		Success = true,
		PlacementId = placementId,
		StartedAt = incubation.StartedAt,
		ReadyAt = incubation.ReadyAt,
		FeedCost = tier.FeedCostTideCoins,
		NewBalance = newBalance,
	}
end

--- Validiert und schließt eine fertige Zucht vollständig serverseitig ab:
--- prüft erneut (unabhängig davon, was der Client zu wissen glaubt), ob die
--- Inkubation wirklich bereits abgelaufen ist (absoluter Zeitstempel-
--- Vergleich, funktioniert identisch direkt nach Timer-Ende UND nach einem
--- Reconnect Stunden später), bucht die Kreatur ins Inventar und gibt das
--- Brutbecken wieder frei.
function BreedingService.RequestClaimBreeding(player: Player, placementId: any): ClaimResult
	if not PlayerDataService.IsDataLoaded(player) then
		return { Success = false, Reason = "DataNotLoaded" }
	end

	if type(placementId) ~= "string" then
		return { Success = false, Reason = "InvalidPlacement" }
	end

	-- Auch hier: nur über das eigene HabitatLayout erreichbar, siehe
	-- findOwnBroodPoolPlacement - fremde/ungültige PlacementIds scheitern
	-- bereits an der fehlenden Inkubation weiter unten.
	if not findOwnBroodPoolPlacement(player, placementId) then
		return { Success = false, Reason = "InvalidPlacement" }
	end

	local incubation = PlayerDataService.GetIncubationForPlacement(player, placementId)
	if not incubation then
		return { Success = false, Reason = "NoActiveIncubation" }
	end

	local now = os.time()
	if now < incubation.ReadyAt then
		return {
			Success = false,
			Reason = "NotReadyYet",
			PlacementId = placementId,
			RemainingSeconds = incubation.ReadyAt - now,
		}
	end

	PlayerDataService.AddCreatureToInventory(player, {
		CreatureId = incubation.CreatureId,
		Rarity = incubation.Rarity,
	})
	PlayerDataService.RemoveIncubation(player, placementId)

	local creatureName = getCreatureDisplayName(incubation.CreatureId)

	-- Progression-Einhängepunkt: NACH erfolgreichem Abschluss (nicht beim
	-- Request), siehe ProgressionService-Kopfkommentar.
	ProgressionService.AwardXP(player, "BreedingCompleted")

	-- GameEvents-Einhängepunkt (Auftrag Punkt 1) + Hand-Übergabe (Auftrag
	-- Punkt 5, siehe holdHatchedCreatureInHand oben).
	GameEvents.Fire(GameEvents.Events.BreedingCompleted, player, {
		CreatureId = incubation.CreatureId,
		Rarity = incubation.Rarity,
		PlacementId = placementId,
	})
	holdHatchedCreatureInHand(player, incubation.CreatureId, creatureName)

	return {
		Success = true,
		PlacementId = placementId,
		CreatureId = incubation.CreatureId,
		CreatureName = creatureName,
		Rarity = incubation.Rarity,
	}
end

--- Liefert den Status EINES Brutbeckens (Empty/Incubating/Ready) für den
--- Client, ohne etwas zu verändern.
function BreedingService.GetStatus(player: Player, placementId: string): BroodPoolStatus
	local incubation = PlayerDataService.GetIncubationForPlacement(player, placementId)
	return buildStatus(placementId, incubation)
end

--- Liefert den Status ALLER eigenen BroodPool-Gebäude (für den initialen
--- UI-Sync beim Plot-Laden, siehe BreedingRemotes.GetBreedingStatuses) -
--- rein lesend, kein Server-Loop nötig, da ausschließlich mit absoluten
--- Zeitstempeln gearbeitet wird (siehe Kopfkommentar dieses Moduls).
function BreedingService.GetAllStatuses(player: Player): { BroodPoolStatus }
	local statuses: { BroodPoolStatus } = {}
	if not PlayerDataService.IsDataLoaded(player) then
		return statuses
	end

	for _, placement in ipairs(PlayerDataService.GetHabitatLayout(player)) do
		if placement.BuildingId == "BroodPool" then
			local incubation = PlayerDataService.GetIncubationForPlacement(player, placement.PlacementId)
			table.insert(statuses, buildStatus(placement.PlacementId, incubation))
		end
	end

	return statuses
end

-- // EINHÄNGEPUNKT: Robux-"Zucht sofort abschließen"-Entwicklerprodukt --------
-- GDD-Ergänzung (siehe ShopConfig.DEV_PRODUCTS.InstantBreeding-Kommentar für
-- die ausführliche Begründung, warum dieses Produkt nicht wörtlich im GDD
-- steht, aber vom Auftrag explizit verlangt wird). Aufgerufen ausschließlich
-- von MonetizationService.ProcessReceipt NACH erfolgreich verifiziertem Kauf
-- (Robux bereits abgebucht) - schließt die laufende Inkubation an
-- `placementId` exakt wie RequestClaimBreeding ab, aber OHNE die ReadyAt-
-- Prüfung (das "sofort" ist der ganze Sinn des Produkts). Gibt (true, nil)
-- bei Erfolg zurück, sonst (false, reason) - "NoActiveIncubation"/
-- "InvalidPlacement" sind für MonetizationService NICHT retry-würdig (siehe
-- dortige Fallback-Kompensationslogik: der Spieler bekommt in diesem Fall
-- stattdessen ShopConfig.DEV_PRODUCTS.InstantBreeding.FallbackCompensationTideCoins).
function BreedingService.RequestInstantComplete(player: Player, placementId: any): (boolean, string?)
	if not PlayerDataService.IsDataLoaded(player) then
		return false, "DataNotLoaded"
	end
	if type(placementId) ~= "string" then
		return false, "InvalidPlacement"
	end
	if not findOwnBroodPoolPlacement(player, placementId) then
		return false, "InvalidPlacement"
	end

	local incubation = PlayerDataService.GetIncubationForPlacement(player, placementId)
	if not incubation then
		return false, "NoActiveIncubation"
	end

	PlayerDataService.AddCreatureToInventory(player, {
		CreatureId = incubation.CreatureId,
		Rarity = incubation.Rarity,
	})
	PlayerDataService.RemoveIncubation(player, placementId)

	-- Identischer Progression-Einhängepunkt wie beim regulären Abholen -
	-- "sofort abgeschlossen" ist spielerisch weiterhin ein abgeschlossener
	-- Zuchterfolg.
	ProgressionService.AwardXP(player, "BreedingCompleted")

	GameEvents.Fire(GameEvents.Events.BreedingCompleted, player, {
		CreatureId = incubation.CreatureId,
		Rarity = incubation.Rarity,
		PlacementId = placementId,
		Instant = true,
	})
	holdHatchedCreatureInHand(player, incubation.CreatureId, getCreatureDisplayName(incubation.CreatureId))

	return true, nil
end

return BreedingService
