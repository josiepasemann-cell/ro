--[[
	Abyssara – Deep Tide Tycoon
	Modul: MonetizationService
	Zuständigkeit:
		Kompletter MarketplaceService-Integrationskern (GDD Abschnitt 5
		"Monetarisierung" + Abschnitt 9, Punkt 9 "Monetarisierungs-
		Integration"): robuster ProcessReceipt-Handler für Entwicklerprodukte
		(idempotent, niemals doppelt gutschreibend), ein gecachter Gamepass-
		Besitz-Status (UserOwnsGamePassAsync + PromptGamePassPurchaseFinished),
		die tatsächliche Anwendung der Gamepass-EFFEKTE (2x Coins, Auto-
		Collector, VIP-Taucher, Trench Runner, Extra-Plot-Platzhalter) sowie
		eine Roblox-Policy-Prüfung (PolicyService, "Paid Random Items") fürs
		Mystery-Egg-Entwicklerprodukt.

		ShopService (Katalog, Soft-Currency-Kosmetik) baut auf diesem Modul
		auf, nicht umgekehrt - MonetizationService kennt ShopService NICHT
		(keine Requires in diese Richtung, siehe ProgressionService-Konvention
		"reine Einbahnstraße" im selben Projekt).

	Sicherheitsprinzip (kein Client-Trust):
		Jeder Gamepass-/Entwicklerprodukt-Besitzstatus kommt AUSSCHLIESSLICH
		von Roblox selbst (UserOwnsGamePassAsync, ProcessReceipt-Callback,
		PromptGamePassPurchaseFinished-Event) - niemals von einem Client-
		Remote-Payload. Alle Ziel-Kontexte für "auf welche Kreatur/welches
		Brutbecken bezieht sich dieser Kauf" werden VOR dem Prompt serverseitig
		validiert (Eigentümerschaft, Existenz) und danach unveränderlich für
		den ProcessReceipt-Handler hinterlegt (siehe PendingPurchaseTargets) -
		der Client kann diesen Kontext nicht nachträglich manipulieren.

	============================================================================
	IDEMPOTENZ-DESIGN (ProcessReceipt darf NIE doppelt gutschreiben):
	============================================================================
	1. Kein Spieler im Server (schon geleavt)  -> NotProcessedYet (Roblox
	   ruft ProcessReceipt automatisch erneut auf, u. a. beim nächsten Login).
	2. Spielerdaten noch nicht geladen         -> NotProcessedYet.
	3. PurchaseId bereits in PlayerDataService.HasProcessedPurchase          -> SOFORT
	   PurchaseGranted (idempotenter Kurzschluss, KEINE erneute Gutschrift).
	4. Unbekannte ProductId (z. B. Konfigurationsfehler/ID noch nicht in
	   ShopConfig eingetragen) -> NotProcessedYet + lautes warn() (Roblox
	   wiederholt automatisch über mehrere Tage - genug Zeit, den Fehler zu
	   beheben, statt Spielergeld kommentarlos verfallen zu lassen).
	5. Effekt anwenden (z. B. Coins gutschreiben, Mystery Egg rollen). Zwei
	   Ausgänge:
	     a) technischer Fehlschlag (retryable = true, z. B. DataNotLoaded
	        mitten im Kauf) -> NotProcessedYet, NICHTS wird als verarbeitet
	        markiert - Roblox versucht später erneut, dann greift Schritt 3
	        NICHT (weil noch nicht markiert) und der Effekt wird sauber
	        nachgeholt.
	     b) inhaltlicher Fehlschlag (retryable = false, z. B. Rettungs-Token
	        ohne mehr entführte Kreatur) -> NIEMALS unbegrenzt retryen (würde
	        nie erfolgreich werden) - stattdessen sofortige Tide-Coins-
	        Fallback-Kompensation (ShopConfig.DevProductDefinition.
	        FallbackCompensationTideCoins), damit ein bezahlter Kauf nie
	        spurlos verpufft.
	6. ERST NACHDEM der Effekt (oder die Fallback-Kompensation) im In-Memory-
	   Cache von PlayerDataService angewendet wurde: PurchaseId als
	   verarbeitet markieren UND SOFORT synchron speichern
	   (PlayerDataService.ForceSave, blockierend mit Retries). Schlägt dieses
	   Speichern fehl -> NotProcessedYet zurückgeben (die im Speicher bereits
	   angewendete Änderung geht dann nur verloren, falls der Server
	   *zusätzlich* abstürzt, BEVOR ein regulärer Auto-Save greift - in
	   diesem Fall ist auch der "verarbeitet"-Marker weg, ein Retry würde den
	   Effekt sauber ein zweites Mal anwenden, OHNE doppelt zu wirken, weil
	   beides gemeinsam verloren ging). Erst NACH erfolgreichem Speichern wird
	   PurchaseGranted zurückgegeben - das ist der Punkt, an dem Roblox
	   aufhört, den Kauf erneut zuzustellen.
	============================================================================

	Rojo-Einhängepunkt:
		src/server/MonetizationService.lua -> ServerScriptService.MonetizationService
		(reines Server-Modul; verdrahtet MarketplaceService.ProcessReceipt,
		PromptGamePassPurchaseFinished sowie Players.PlayerAdded/
		CharacterAdded/PlayerRemoving selbst beim ersten require() - gleiche
		Konvention wie PlayerDataService/GachaService/RaidService. Ein
		einfaches require(...) aus ShopServer.server.lua genügt.)
]]

local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GachaService = require(script.Parent:WaitForChild("GachaService"))
local BreedingService = require(script.Parent:WaitForChild("BreedingService"))
local RaidService = require(script.Parent:WaitForChild("RaidService"))
local ShopConfig = require(ReplicatedStorage:WaitForChild("ShopConfig"))

type GamepassKey = ShopConfig.GamepassKey
type DevProductDefinition = ShopConfig.DevProductDefinition

local MonetizationService = {}

--- Feuert (player: Player, devProductKey: string) NACH jeder erfolgreich
--- verarbeiteten (oder mit Fallback-Kompensation abgeschlossenen)
--- Entwicklerprodukt-Gutschrift - rein server-internes Signal (analog zu
--- PlayerDataService.DataChanged), damit ShopServer.server.lua dem
--- betroffenen Client einen aktualisierten Katalog-Snapshot nachschicken
--- kann, ohne dass MonetizationService selbst ShopRemotes/ShopService
--- kennen müsste (Einbahnstraßen-Prinzip, siehe ProgressionService).
local purchaseGrantedBindable = Instance.new("BindableEvent")
MonetizationService.PurchaseGranted = purchaseGrantedBindable.Event

-- // Konfiguration ------------------------------------------------------------

local GAMEPASS_OWNERSHIP_RETRY_ATTEMPTS = 3
local GAMEPASS_OWNERSHIP_RETRY_BASE_DELAY_SECONDS = 2

local PENDING_TARGET_TTL_SECONDS = 600 -- 10 Min. - genug Zeit für den Robux-Kaufdialog, verhindert aber einen "uralten" Pending-Kontext bei einem Tage später erneut zugestellten Receipt

local VIP_CHEST_CHECK_INTERVAL_SECONDS = 15 * 60

-- // Laufzeit-Zustand (In-Memory, NICHT persistent - siehe jeweilige Kommentare) --

--- Gecachter Gamepass-Besitz je Spieler (nur echte, konfigurierte IDs -
--- siehe PlayerOwnsGamepass). Wird bei Kaufabschluss (PromptGamePassPurchase
--- Finished) sofort aktualisiert, sonst per Cache-Miss synchron nachgeladen.
local ownershipCache: { [number]: { [string]: boolean } } = {}

--- NUR in Studio befüllt (siehe RequestSimulateStudioPurchase) - komplett
--- getrennt von ownershipCache, damit ein versehentlicher Studio-Test-Flag
--- niemals mit echten Robux-Käufen vermischt werden kann.
local simulatedOwnership: { [number]: { [string]: boolean } } = {}

--- Roblox-Policy-Ergebnis je Spieler (siehe PlayerMayPurchasePaidRandomItems).
local policyCache: { [number]: { ArePaidRandomItemsRestricted: boolean } } = {}

--- Serverseitig VOR dem Prompt hinterlegter Ziel-Kontext für Entwickler-
--- produkte mit RequiresTarget == true (RescueToken -> InstanceId,
--- InstantBreeding -> PlacementId). Struktur: [userId][DevProductKey] =
--- { TargetId: string, SetAt: number }.
local pendingPurchaseTargets: { [number]: { [string]: { TargetId: string, SetAt: number } } } = {}

-- // Kleine Hilfsfunktionen ----------------------------------------------------

local function withSimpleRetry(attempts: number, baseDelaySeconds: number, fn: () -> (boolean, any)): (boolean, any)
	local lastResult: any = nil
	for attempt = 1, attempts do
		local ok, result = fn()
		if ok then
			return true, result
		end
		lastResult = result
		if attempt < attempts then
			task.wait(baseDelaySeconds * attempt)
		end
	end
	return false, lastResult
end

-- // Gamepass-Besitz-Cache ------------------------------------------------------

--- Öffentliche API: true, wenn `player` den Gamepass `key` besitzt. Prüft in
--- Studio ZUERST den Simulations-Flag (siehe RequestSimulateStudioPurchase),
--- danach den echten, gecachten Roblox-Besitzstatus. Liefert IMMER `false`
--- für einen (noch) nicht konfigurierten Gamepass (Id == 0) - siehe
--- ShopConfig-Kopfkommentar "Code muss mit ID 0 sicher sein".
function MonetizationService.PlayerOwnsGamepass(player: Player, key: string): boolean
	if RunService:IsStudio() then
		local simulated = simulatedOwnership[player.UserId]
		if simulated and simulated[key] then
			return true
		end
	end

	local definition = ShopConfig.GetGamepass(key)
	if not definition or definition.Id == 0 then
		return false
	end

	local cache = ownershipCache[player.UserId]
	if cache and cache[key] ~= nil then
		return cache[key]
	end

	-- Cache-Miss (z. B. sehr früher Aufruf vor Abschluss des Warmups beim
	-- Join): synchroner Nachlade-Versuch, EINMALIG (kein Retry hier - der
	-- eigentliche robuste Vorlade-Pfad ist warmupPlayerGamepassCache beim
	-- PlayerAdded; ein Cache-Miss hier ist der seltene Ausnahmefall).
	local ok, owns = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, definition.Id)
	end)

	local result = ok and owns == true
	ownershipCache[player.UserId] = ownershipCache[player.UserId] or {}
	ownershipCache[player.UserId][key] = result
	return result
end

--- Lädt den Besitzstatus ALLER konfigurierten Gamepasses für `player` robust
--- vor (Retries mit Backoff, analog zum PlayerDataService-Muster) und wendet
--- danach sofort die "Join-Effekte" an (Trench-Runner-WalkSpeed, VIP-Chat-
--- Tag/Truhe) - siehe applyJoinEffects unten.
local function warmupPlayerGamepassCache(player: Player)
	local cache = {}
	ownershipCache[player.UserId] = cache

	for _, key in ipairs(ShopConfig.GAMEPASS_ORDER) do
		local definition = ShopConfig.GAMEPASSES[key]
		if definition.Id ~= 0 then
			local ok, owns = withSimpleRetry(GAMEPASS_OWNERSHIP_RETRY_ATTEMPTS, GAMEPASS_OWNERSHIP_RETRY_BASE_DELAY_SECONDS, function()
				local success, result = pcall(function()
					return MarketplaceService:UserOwnsGamePassAsync(player.UserId, definition.Id)
				end)
				return success, result
			end)
			cache[key] = ok and owns == true
			if not ok then
				warn(("[MonetizationService] Gamepass-Besitzprüfung für %s (%s) fehlgeschlagen - gilt vorerst als nicht besessen."):format(player.Name, key))
			end
		else
			cache[key] = false
		end
	end

	if Players:GetPlayerByUserId(player.UserId) == player then
		MonetizationService.ApplyJoinEffects(player)
	end
end

--- Roblox meldet hierüber den Abschluss EINES Gamepass-Kaufdialogs - bei
--- Erfolg wird der Cache sofort aktualisiert (kein Warten auf den nächsten
--- Cache-Miss) UND die zugehörigen Effekte sofort angewendet (z. B.
--- WalkSpeed direkt nach Kauf, ohne Respawn).
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, gamePassId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end

	local definition = ShopConfig.FindGamepassById(gamePassId)
	if not definition then
		return
	end

	ownershipCache[player.UserId] = ownershipCache[player.UserId] or {}
	ownershipCache[player.UserId][definition.Key] = true

	MonetizationService.ApplyJoinEffects(player)
end)

-- // Roblox-Policy (Paid Random Items - Mystery Egg) ----------------------------

local function fetchPolicyInfo(player: Player)
	local ok, info = pcall(function()
		return PolicyService:GetPolicyInfoForPlayerAsync(player)
	end)

	if ok and info then
		policyCache[player.UserId] = { ArePaidRandomItemsRestricted = info.ArePaidRandomItemsRestricted == true }
	else
		warn(("[MonetizationService] PolicyService-Abfrage für %s fehlgeschlagen - Mystery-Egg-Robux-Kauf bleibt sicherheitshalber gesperrt."):format(player.Name))
	end
end

--- true, wenn `player` laut Roblox-Policy Mystery-Egg-artige "Paid Random
--- Items" per Robux kaufen darf. Liefert `false` (restriktiv/sicher), falls
--- die Policy noch nicht geladen ist ODER die Abfrage fehlgeschlagen ist -
--- Compliance geht hier vor Umsatz (siehe Auftrag Punkt 6).
function MonetizationService.PlayerMayPurchasePaidRandomItems(player: Player): boolean
	local cached = policyCache[player.UserId]
	if not cached then
		return false
	end
	return not cached.ArePaidRandomItemsRestricted
end

-- // Gamepass-Effekte: Bewegungstempo, VIP-Truhe/Tag, Extra-Plot-Platzhalter ----

--- Trench-Runner-WalkSpeed (GDD Abschnitt 5: "Schnellere Bewegung/Tauch-
--- geschwindigkeit"). Roblox' eingebautes Schwimmen skaliert automatisch mit
--- Humanoid.WalkSpeed - ein separates "SwimSpeed"-Property existiert nicht,
--- daher genügt das Setzen von WalkSpeed für beide Bewegungsarten.
local function applyTrenchRunnerEffect(player: Player)
	local character = player.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	humanoid.WalkSpeed = if MonetizationService.PlayerOwnsGamepass(player, "TrenchRunner")
		then ShopConfig.TRENCH_RUNNER_WALKSPEED
		else ShopConfig.DEFAULT_WALKSPEED
end

--- VIP-Taucher (GDD Abschnitt 5: "Exklusiver Skin, tägliche Bonus-Truhe, 1,5x
--- Zucht-Geschwindigkeit"). Der Skin selbst ist ein reines Kosmetik-/
--- Charakter-Asset-Thema (Auftrag Dateibesitz deckt das nicht ab) - dieses
--- Modul setzt stattdessen ein Attribut, das ein künftiges Charakter-/Chat-
--- System (oder ein TextChatService-SpeakerDisplayName-Hook) auslesen kann,
--- plus die tägliche Bonus-Truhe. Die 1,5x-Zucht-Geschwindigkeit wirkt
--- direkt in BreedingService.RequestStartBreeding (siehe dortigen
--- Kommentar), NICHT hier.
local function applyVipEffect(player: Player)
	local owns = MonetizationService.PlayerOwnsGamepass(player, "VIPDiver")
	player:SetAttribute("ChatTag", if owns then ShopConfig.VIP_CHAT_TAG else nil)

	if not owns then
		return
	end
	if not PlayerDataService.IsDataLoaded(player) then
		return
	end

	local today = PlayerDataService.GetUtcDateString()
	if PlayerDataService.GetLastVipChestClaimedDate(player) == today then
		return
	end

	PlayerDataService.SetLastVipChestClaimedDate(player, today)
	PlayerDataService.AddCurrency(player, "TideCoins", ShopConfig.VIP_DAILY_CHEST_TIDE_COINS)
end

--- ABWEICHUNG VOM GDD: siehe ShopConfig.EXTRA_PLOT_PLACEHOLDER-Kommentar -
--- PlotRegistry unterstützt aktuell nur ein Plot je Spieler. Dieses Modul
--- erkennt den Gamepass-Besitz zuverlässig und setzt ein Attribut zur
--- späteren Weiterverwendung, löst aber bewusst KEINE zweite Plot-Zuweisung
--- aus (kein Absturz, keine stille Fehlfunktion - einfach (noch) kein
--- Gameplay-Effekt).
local function applyExtraPlotPlaceholder(player: Player)
	player:SetAttribute("OwnsExtraPlotGamepassPlaceholder", MonetizationService.PlayerOwnsGamepass(player, "ExtraPlot"))
end

--- Wendet ALLE unmittelbar (ohne Respawn) sichtbaren Gamepass-Effekte für
--- `player` an - aufgerufen nach jedem Cache-Update (Warmup, PromptGamePass
--- PurchaseFinished, Studio-Simulation).
function MonetizationService.ApplyJoinEffects(player: Player)
	applyTrenchRunnerEffect(player)
	applyVipEffect(player)
	applyExtraPlotPlaceholder(player)
end

-- // Öffentliche Balancing-Konstanten (für BreedingService/RaidService/
-- IdleIncomeService-Konsumenten, siehe deren lazy-require-Kommentare) --------

function MonetizationService.GetDoubleCoinsMultiplier(): number
	return ShopConfig.DOUBLE_COINS_MULTIPLIER
end

function MonetizationService.GetVipBreedingSpeedMultiplier(): number
	return ShopConfig.VIP_BREEDING_SPEED_MULTIPLIER
end

function MonetizationService.GetAutoCollectorOfflineCapSeconds(): number
	return ShopConfig.AUTO_COLLECTOR_OFFLINE_CAP_SECONDS
end

-- // Gamepass-/Entwicklerprodukt-Prompts (vom Client über ShopService/
-- ShopRemotes angestoßen, hier vollständig serverseitig validiert) -----------

--- Validiert + stößt einen Gamepass-Kaufdialog an. Gibt (true, nil) bei
--- erfolgreich angestoßenem Prompt zurück (KEIN Kaufabschluss - der kommt
--- asynchron über PromptGamePassPurchaseFinished), sonst (false, reason).
function MonetizationService.RequestPromptGamepassPurchase(player: Player, key: any): (boolean, string?)
	if type(key) ~= "string" then
		return false, "InvalidKey"
	end
	local definition = ShopConfig.GetGamepass(key)
	if not definition then
		return false, "UnknownGamepass"
	end
	if definition.Id == 0 then
		return false, "NotConfigured"
	end
	if MonetizationService.PlayerOwnsGamepass(player, key) then
		return false, "AlreadyOwned"
	end

	MarketplaceService:PromptGamePassPurchase(player, definition.Id)
	return true, nil
end

local function setPendingPurchaseTarget(player: Player, key: string, targetId: string)
	local map = pendingPurchaseTargets[player.UserId]
	if not map then
		map = {}
		pendingPurchaseTargets[player.UserId] = map
	end
	map[key] = { TargetId = targetId, SetAt = os.time() }
end

local function consumePendingPurchaseTarget(player: Player, key: string): string?
	local map = pendingPurchaseTargets[player.UserId]
	if not map then
		return nil
	end
	local entry = map[key]
	map[key] = nil
	if not entry then
		return nil
	end
	if os.time() - entry.SetAt > PENDING_TARGET_TTL_SECONDS then
		return nil
	end
	return entry.TargetId
end

--- Serverseitige Ziel-Validierung je Entwicklerprodukt mit RequiresTarget ==
--- true - läuft VOR dem Prompt, damit ein ProcessReceipt-Handler niemals ein
--- fremdes/ungültiges Ziel zu Gesicht bekommt (siehe Kopfkommentar).
local function validatePurchaseTarget(player: Player, definition: DevProductDefinition, targetId: string): boolean
	if definition.Key == "RescueToken" then
		for _, abducted in ipairs(PlayerDataService.GetAbductedCreatures(player)) do
			if abducted.InstanceId == targetId then
				return true
			end
		end
		return false
	elseif definition.Key == "InstantBreeding" then
		return PlayerDataService.GetIncubationForPlacement(player, targetId) ~= nil
	end
	return true
end

--- Validiert + stößt einen Entwicklerprodukt-Kaufdialog an. `targetId` ist
--- bei RequiresTarget-Produkten Pflicht (InstanceId/PlacementId, siehe
--- ShopRemotes-Kopfkommentar) und wird HIER serverseitig validiert +
--- vorgemerkt (siehe setPendingPurchaseTarget), NIEMALS ungeprüft an den
--- späteren ProcessReceipt-Handler durchgereicht.
function MonetizationService.RequestPromptDevProductPurchase(player: Player, key: any, targetId: any): (boolean, string?)
	if type(key) ~= "string" then
		return false, "InvalidKey"
	end
	local definition = ShopConfig.GetDevProduct(key)
	if not definition then
		return false, "UnknownProduct"
	end
	if definition.Id == 0 then
		return false, "NotConfigured"
	end

	if definition.IsPaidRandomItem and not MonetizationService.PlayerMayPurchasePaidRandomItems(player) then
		return false, "PaidRandomItemsRestricted"
	end

	if definition.Key == "RaidSkip" then
		local today = PlayerDataService.GetUtcDateString()
		if PlayerDataService.GetLastRaidSkipDate(player) == today then
			return false, "AlreadyUsedToday"
		end
	end

	if definition.RequiresTarget then
		if type(targetId) ~= "string" or targetId == "" then
			return false, "MissingTarget"
		end
		if not validatePurchaseTarget(player, definition, targetId) then
			return false, "InvalidTarget"
		end
		setPendingPurchaseTarget(player, key, targetId)
	end

	MarketplaceService:PromptProductPurchase(player, definition.Id)
	return true, nil
end

-- // Entwicklerprodukt-Effekt-Registry (von ProcessReceipt aufgerufen) --------

--- Wendet den Effekt eines Entwicklerprodukts an. Gibt (success: boolean,
--- retryable: boolean) zurück - siehe Idempotenz-Design im Kopfkommentar für
--- die genaue Bedeutung von `retryable`.
local function applyDevProductEffect(player: Player, definition: DevProductDefinition): (boolean, boolean)
	if definition.EffectKey == "GrantCoins" then
		local amount = definition.GrantAmount or definition.FallbackCompensationTideCoins
		local ok = PlayerDataService.AddCurrency(player, "TideCoins", amount)
		return ok, true

	elseif definition.EffectKey == "MysteryEgg" then
		local result, failure = GachaService.OpenPurchasedEgg(player)
		if result then
			return true, true
		end
		-- Einzig möglicher Fehlschlag hier ist "DataNotLoaded" (siehe
		-- GachaService.OpenPurchasedEgg) - technisch, also retryable.
		return false, failure ~= "DataNotLoaded"

	elseif definition.EffectKey == "RescueToken" then
		local targetId = consumePendingPurchaseTarget(player, definition.Key)
		if not targetId then
			-- Kein (mehr gültiger) vorgemerkter Kontext - freundlicher
			-- Fallback: die ÄLTESTE aktuell entführte Kreatur automatisch
			-- retten, falls vorhanden, statt den Kauf ins Leere laufen zu
			-- lassen.
			local abductedList = PlayerDataService.GetAbductedCreatures(player)
			if #abductedList > 0 then
				targetId = abductedList[1].InstanceId
			end
		end
		if not targetId then
			return false, false -- nichts (mehr) zu retten -> Fallback-Kompensation
		end
		local ok, reason = RaidService.RequestRescueWithToken(player, targetId)
		if ok then
			return true, true
		end
		return false, reason == "DataNotLoaded"

	elseif definition.EffectKey == "InstantBreeding" then
		local targetId = consumePendingPurchaseTarget(player, definition.Key)
		if not targetId then
			return false, false -- kein vorgemerktes Brutbecken mehr auffindbar -> Fallback-Kompensation
		end
		local ok, reason = BreedingService.RequestInstantComplete(player, targetId)
		if ok then
			return true, true
		end
		return false, reason == "DataNotLoaded"

	elseif definition.EffectKey == "RaidSkip" then
		local ok, reason = RaidService.RequestRaidSkip(player)
		if ok then
			return true, true
		end
		return false, reason == "DataNotLoaded"
	end

	warn(("[MonetizationService] Unbekannter EffectKey '%s' für Produkt '%s'."):format(definition.EffectKey, definition.Key))
	return false, false
end

-- // ProcessReceipt (Kernstück, siehe Idempotenz-Design im Kopfkommentar) -----

local function processReceipt(receiptInfo: { [string]: any }): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(receiptInfo.PlayerId)
	if not player then
		-- Spieler nicht (mehr) im Server - Roblox stellt den Receipt später
		-- erneut zu (z. B. beim nächsten Login).
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not PlayerDataService.IsDataLoaded(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if PlayerDataService.HasProcessedPurchase(player, receiptInfo.PurchaseId) then
		-- Bereits verarbeitet (z. B. erneute Zustellung nach einem Server-
		-- Crash zwischen Gutschrift und Speichern) - idempotenter Kurzschluss,
		-- KEINE zweite Gutschrift.
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local definition = ShopConfig.FindDevProductById(receiptInfo.ProductId)
	if not definition then
		warn(("[MonetizationService] Unbekannte ProductId %d in ProcessReceipt (PurchaseId %s) - ShopConfig vermutlich noch nicht mit der echten Id befüllt."):format(
			receiptInfo.ProductId,
			tostring(receiptInfo.PurchaseId)
		))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local success, retryable = applyDevProductEffect(player, definition)

	if not success then
		if retryable then
			return Enum.ProductPurchaseDecision.NotProcessedYet
		end

		-- Inhaltlicher (nicht-technischer) Fehlschlag: Fallback-Kompensation
		-- statt unbegrenzter Retries, siehe Kopfkommentar.
		PlayerDataService.AddCurrency(player, "TideCoins", definition.FallbackCompensationTideCoins)
		warn(("[MonetizationService] Fallback-Kompensation (%d Tide Coins) für %s, Produkt '%s' (PurchaseId %s) gewährt - Effekt inhaltlich nicht mehr anwendbar."):format(
			definition.FallbackCompensationTideCoins,
			player.Name,
			definition.Key,
			tostring(receiptInfo.PurchaseId)
		))
	end

	if not PlayerDataService.MarkPurchaseProcessed(player, receiptInfo.PurchaseId) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	if not PlayerDataService.ForceSave(player) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	purchaseGrantedBindable:Fire(player, definition.Key)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

MarketplaceService.ProcessReceipt = processReceipt

-- // Studio-Testmodus (siehe ShopConfig/ShopRemotes-Kopfkommentar) ------------
-- STRIKT von echten Käufen getrennt (eigene Tabelle `simulatedOwnership`)
-- und HART an RunService:IsStudio() gebunden - diese Prüfung läuft HIER,
-- serverseitig, als zusätzliche Absicherung (nicht nur im UI ausgeblendet),
-- sodass ein manipulierter/gepatchter Client im Live-Spiel diesen Kanal
-- niemals wirksam auslösen kann.

function MonetizationService.RequestSimulateStudioPurchase(player: Player, kind: any, key: any): (boolean, string?)
	if not RunService:IsStudio() then
		return false, "StudioOnly"
	end
	if type(kind) ~= "string" or type(key) ~= "string" then
		return false, "InvalidArguments"
	end

	if kind == "Gamepass" then
		local definition = ShopConfig.GetGamepass(key)
		if not definition then
			return false, "UnknownGamepass"
		end
		simulatedOwnership[player.UserId] = simulatedOwnership[player.UserId] or {}
		simulatedOwnership[player.UserId][key] = true
		MonetizationService.ApplyJoinEffects(player)
		return true, nil
	elseif kind == "DevProduct" then
		local definition = ShopConfig.GetDevProduct(key)
		if not definition then
			return false, "UnknownProduct"
		end
		local success, retryable = applyDevProductEffect(player, definition)
		if not success and not retryable then
			PlayerDataService.AddCurrency(player, "TideCoins", definition.FallbackCompensationTideCoins)
		end
		purchaseGrantedBindable:Fire(player, definition.Key)
		return true, nil
	end

	return false, "UnknownKind"
end

-- // Bootstrap ------------------------------------------------------------------

local function onPlayerAdded(player: Player)
	task.spawn(fetchPolicyInfo, player)
	task.spawn(warmupPlayerGamepassCache, player)

	player.CharacterAdded:Connect(function()
		applyTrenchRunnerEffect(player)
	end)
	if player.Character then
		applyTrenchRunnerEffect(player)
	end
end

local function onPlayerRemoving(player: Player)
	ownershipCache[player.UserId] = nil
	simulatedOwnership[player.UserId] = nil
	policyCache[player.UserId] = nil
	pendingPurchaseTargets[player.UserId] = nil
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

-- Wiederkehrende VIP-Truhen-Prüfung für Spieler, die über einen UTC-
-- Tageswechsel hinweg online bleiben (ApplyJoinEffects läuft sonst nur beim
-- Join/Kaufabschluss).
task.spawn(function()
	while true do
		task.wait(VIP_CHEST_CHECK_INTERVAL_SECONDS)
		for _, player in ipairs(Players:GetPlayers()) do
			if MonetizationService.PlayerOwnsGamepass(player, "VIPDiver") then
				task.spawn(applyVipEffect, player)
			end
		end
	end
end)

return MonetizationService
