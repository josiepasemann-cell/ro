--[[
	Abyssara – Deep Tide Tycoon
	Modul: GachaService
	Zuständigkeit:
		Kernlogik des Mystery-Egg-Gacha-Systems: gewichteter Zufalls-Roll auf
		Basis von GachaConfig.DROP_TABLE, Pity-Tracking pro Spieler,
		Duplikat-Erkennung + Ausgleichs-Konvertierung, sowie eine saubere,
		exportierte API, an die spätere Systeme (RemoteEvent-Handler,
		Persistenz, Economy) andocken.

		Pity-Zähler, Kreaturen-Inventar (Duplikatsschutz) und Tide-Coins-
		Gutschrift (Duplikat-Ausgleich) laufen vollständig über
		PlayerDataService (src/server/PlayerDataService.lua) - dieses Modul
		hält dafür selbst keinen persistenten Zustand mehr, sondern nur noch
		den rein transienten Anti-Spam-Cooldown pro Spieler (siehe
		`playerStates`/`lastRollAt` unten).

	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)".

	Rojo-Einhängepunkt:
		src/server/  ->  ServerScriptService
		(reines Server-Modul; wird von GachaServer.server.lua verdrahtet)

	Sicherheitsprinzip (kein Client-Trust):
		JEDE Funktion hier, die eine Roll-Entscheidung trifft oder Inventar/
		Economy verändert, läuft ausschließlich serverseitig und nimmt
		niemals ein Ergebnis (Rarity, Kreatur, ...) vom Client entgegen.
		GachaServer.server.lua übergibt dieser API ausschließlich das
		`Player`-Objekt aus RemoteEvent:OnServerEvent (das von der Roblox-
		Engine selbst gesetzt wird, nicht vom Client fälschbar).
]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local GachaConfig = require(script.Parent.GachaConfig)
local GachaHistoryLogger = require(script.Parent.GachaHistoryLogger)
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local GameEvents = require(script.Parent.GameEvents)
local HeldItemService = require(script.Parent.HeldItemService)

type Rarity = GachaConfig.Rarity

export type OpenEggResult = {
	Rarity: Rarity,
	CreatureId: string,
	CreatureName: string,
	ResultType: "New" | "Duplicate",
	CompensationTideCoins: number,
	PityForced: boolean,
	PityCounter: number,
}

export type OpenEggFailure = "OnCooldown" | "DataNotLoaded" | "NotEnoughCoins"

local GachaService = {}

-- // Pro-Spieler-Zustand (nur noch Anti-Spam-Timestamp) ----------------------
-- Der Pity-Zähler selbst ist KEIN In-Memory-Zustand mehr - er lebt
-- persistent in PlayerDataService (GetPityCounter/SetPityCounter, siehe
-- applyPity() unten). `playerStates` hält ausschließlich den rein
-- transienten Anti-Spam-Cooldown (`lastRollAt`, os.clock()-basiert), der
-- bewusst NICHT persistiert wird (GDD/Task verlangen das auch nicht - ein
-- Serverneustart darf den Cooldown ruhig zurücksetzen).
type PlayerGachaState = {
	lastRollAt: number,
}

local playerStates: { [number]: PlayerGachaState } = {}

local function getOrCreatePlayerState(player: Player): PlayerGachaState
	local state = playerStates[player.UserId]
	if not state then
		state = { lastRollAt = 0 }
		playerStates[player.UserId] = state
	end
	return state
end

--- Wird von GachaServer.server.lua an Players.PlayerRemoving gehängt.
--- Räumt nur noch den rein transienten Anti-Spam-Zustand auf - das
--- eigentliche Speichern des Spielstands (inkl. Pity-Zähler, Inventar,
--- Tide Coins) übernimmt PlayerDataService selbst über seinen eigenen
--- PlayerRemoving-Handler.
function GachaService.HandlePlayerRemoving(player: Player)
	playerStates[player.UserId] = nil
end

-- // Gewichteter Zufalls-Roll ------------------------------------------------

local rng = Random.new()

--- Rollt eine Rarity gewichtet über GachaConfig.DROP_TABLE (bzw. über eine
--- übergebene Teilmenge `candidateRarities`, siehe Pity-Erzwingung unten).
local function rollWeightedRarity(candidateRarities: { Rarity }?): Rarity
	local rarities = candidateRarities or GachaConfig.RARITY_ORDER

	local totalWeight = 0
	for _, rarity in ipairs(rarities) do
		totalWeight += GachaConfig.DROP_TABLE[rarity].Weight
	end

	local roll = rng:NextNumber() * totalWeight
	local cumulative = 0
	for _, rarity in ipairs(rarities) do
		cumulative += GachaConfig.DROP_TABLE[rarity].Weight
		if roll <= cumulative then
			return rarity
		end
	end

	-- Numerischer Sicherheitsfallback (Floating-Point-Rundung): letzte
	-- Rarity der Kandidatenliste.
	return rarities[#rarities]
end

--- Wendet den Pity-Mechanismus auf ein natürlich gerolltes Ergebnis an.
--- Liest/schreibt den Pity-Zähler ausschließlich über PlayerDataService
--- (persistent, überlebt Serverneustarts) statt über lokalen In-Memory-
--- Zustand. Gibt (finalRarity, wurdePityErzwungen, pityZählerNachDemRoll)
--- zurück.
local function applyPity(player: Player, naturalRarity: Rarity): (Rarity, boolean, number)
	if GachaConfig.IsRarityAtLeast(naturalRarity, GachaConfig.PITY_MIN_RARITY) then
		-- Natürlicher Epic-oder-besser-Treffer: Zähler zurücksetzen.
		PlayerDataService.SetPityCounter(player, 0)
		return naturalRarity, false, 0
	end

	local pityCounter = PlayerDataService.GetPityCounter(player) + 1

	if pityCounter >= GachaConfig.PITY_THRESHOLD then
		PlayerDataService.SetPityCounter(player, 0)

		-- Pity erzwingt Epic-oder-besser, aber weiterhin GEWICHTET unter
		-- den qualifizierenden Rarities (Epic/Legendary/Mythic bleiben
		-- relativ zueinander so selten wie konfiguriert) statt immer
		-- exakt "Epic" zu vergeben.
		local qualifyingRarities: { Rarity } = {}
		local minIndex = GachaConfig.GetRarityIndex(GachaConfig.PITY_MIN_RARITY)
		for _, rarity in ipairs(GachaConfig.RARITY_ORDER) do
			if GachaConfig.GetRarityIndex(rarity) >= minIndex then
				table.insert(qualifyingRarities, rarity)
			end
		end

		return rollWeightedRarity(qualifyingRarities), true, 0
	end

	PlayerDataService.SetPityCounter(player, pityCounter)
	return naturalRarity, false, pityCounter
end

-- // Kreaturenauswahl ---------------------------------------------------------

--- Liefert den Anzeigenamen einer Kreatur: bevorzugt LIVE vom bereits in
--- Workspace.Assets.Creatures platzierten Modell (Attribut "CreatureName",
--- siehe assets/models/README.md), sonst Fallback aus GachaConfig.
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
	return GachaConfig.CREATURE_DISPLAY_NAME_FALLBACK[creatureId] or creatureId
end

--- Wählt zufällig eine Kreatur aus dem Pool der übergebenen Rarity. Fällt
--- auf den nächstniedrigeren, nicht-leeren Pool zurück, falls die Rarity
--- (aktuell nur "Mythic") noch kein zugeordnetes Kreaturen-Asset hat -
--- siehe Hinweis in GachaConfig.CREATURE_POOL.
-- // Hand-Übergabe (docs/held-items.md, Abschnitt 7 "Künftige Aufrufer") ---
-- Identisches Prinzip zu BreedingService.holdHatchedCreatureInHand - siehe
-- dortigen Kopfkommentar für die ausführliche Begründung (auto-drop nach
-- HAND_OFF_AUTO_DROP_SECONDS, ohne HeldItemService selbst anzufassen).
local HAND_OFF_AUTO_DROP_SECONDS = 6

local function holdRolledCreatureInHand(player: Player, creatureId: string, creatureName: string)
	local creaturesFolder = Workspace:FindFirstChild("Assets")
	creaturesFolder = creaturesFolder and creaturesFolder:FindFirstChild("Creatures")
	local template = creaturesFolder and creaturesFolder:FindFirstChild(creatureId)
	if not template or not template:IsA("Model") then
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

local function pickCreatureForRarity(rarity: Rarity): (string, Rarity)
	local order = GachaConfig.RARITY_ORDER
	local startIndex = GachaConfig.GetRarityIndex(rarity)

	for index = startIndex, 1, -1 do
		local candidateRarity = order[index]
		local pool = GachaConfig.CREATURE_POOL[candidateRarity]
		if pool and #pool > 0 then
			if candidateRarity ~= rarity then
				warn(
					("[GachaService] No creature asset for rarity '%s', falling back to the pool of '%s'."):format(
						rarity,
						candidateRarity
					)
				)
			end
			local creatureId = pool[rng:NextInteger(1, #pool)]
			return creatureId, candidateRarity
		end
	end

	error("[GachaService] No creature pool available - GachaConfig.CREATURE_POOL is completely empty.")
end

-- // Öffentliche API ----------------------------------------------------------

--- Liefert die öffentliche, compliance-relevante Odds-Tabelle für die
--- Odds-UI (GachaOddsPanel). Enthält bewusst NUR Anzeige-relevante Felder,
--- keine internen Balancing-Daten (Pity-Schwelle, Duplikat-Ausgleich,
--- Kreaturen-Pools) - diese bleiben rein serverseitig.
function GachaService.GetOddsTable(): { { Tier: Rarity, Label: string, Percent: number, Color: Color3 } }
	local rows = {}
	for _, rarity in ipairs(GachaConfig.RARITY_ORDER) do
		local definition = GachaConfig.DROP_TABLE[rarity]
		table.insert(rows, {
			Tier = rarity,
			Label = definition.DisplayLabel,
			Percent = definition.Weight, -- Weight == Prozentwert, Summe der Tabelle ist 100
			Color = definition.Color,
		})
	end
	return rows
end

--- Interne Kernlogik EINES Rolls (Roll, Pity, Duplikat-Check, Ausgleich,
--- Logging, Progression) - OHNE Anti-Spam-Cooldown-Prüfung. Von OpenEgg
--- (Cooldown VOR dem Aufruf geprüft) UND OpenPurchasedEgg (siehe unten,
--- bewusst OHNE Cooldown - eine bezahlte Robux-Transaktion darf niemals an
--- einem reinen Anti-Spam-Timer scheitern) gemeinsam genutzt.
local function performRoll(player: Player, purchased: boolean): OpenEggResult
	-- 1) Gewichteter Roll + Pity (persistent über PlayerDataService) -----------
	local naturalRarity = rollWeightedRarity()
	local finalRarity, pityForced, pityCounterAfter = applyPity(player, naturalRarity)

	-- 2) Kreatur innerhalb der Rarity auswählen ---------------------------------
	local creatureId, resolvedRarity = pickCreatureForRarity(finalRarity)
	local creatureName = getCreatureDisplayName(creatureId)

	-- 3) Duplikatsschutz: bereits im Inventar (PlayerDataService)? -------------
	local resultType: "New" | "Duplicate"
	local compensation = 0

	if PlayerDataService.PlayerHasCreature(player, creatureId) then
		resultType = "Duplicate"
		compensation = GachaConfig.DUPLICATE_COMPENSATION_TIDE_COINS[resolvedRarity] or 0
		PlayerDataService.AddCurrency(player, "TideCoins", compensation)
	else
		resultType = "New"
		PlayerDataService.AddCreatureToInventory(player, { CreatureId = creatureId, Rarity = resolvedRarity })
	end

	-- 4) Historie/Audit-Log -------------------------------------------------------
	GachaHistoryLogger.LogRoll(player, {
		Rarity = resolvedRarity,
		CreatureId = creatureId,
		CreatureName = creatureName,
		ResultType = resultType,
		CompensationTideCoins = compensation,
		PityForced = pityForced,
	})

	-- Progression-Einhängepunkt: NACH erfolgreichem Öffnen (nicht beim
	-- Request), siehe ProgressionService-Kopfkommentar. Zählt unabhängig
	-- davon, ob das Ergebnis "New" oder "Duplicate" war - das eigentliche
	-- Ereignis ("ein Mystery Egg wurde geöffnet") ist bereits abgeschlossen.
	ProgressionService.AwardXP(player, "MysteryEggOpened")

	-- GameEvents-Einhängepunkt (Auftrag Punkt 1) + Hand-Übergabe (Auftrag
	-- Punkt 5): die geschlüpfte Kreatur wandert kurz sichtbar in die Hand,
	-- siehe holdRolledCreatureInHand oben / docs/held-items.md.
	GameEvents.Fire(GameEvents.Events.EggOpened, player, {
		Rarity = resolvedRarity,
		CreatureId = creatureId,
		ResultType = resultType,
		Purchased = purchased,
	})
	holdRolledCreatureInHand(player, creatureId, creatureName)

	local result: OpenEggResult = {
		Rarity = resolvedRarity,
		CreatureId = creatureId,
		CreatureName = creatureName,
		ResultType = resultType,
		CompensationTideCoins = compensation,
		PityForced = pityForced,
		PityCounter = pityCounterAfter,
	}

	return result
end

--- Öffentliche API: verarbeitet EINE Mystery-Egg-Öffnungs-Anfrage für einen
--- Spieler vollständig serverseitig (Roll, Pity, Duplikat-Check, Ausgleich,
--- Logging), inkl. Anti-Spam-Cooldown. Gibt entweder (result, nil) oder
--- (nil, failure) zurück (z. B. bei zu schneller Wiederholungs-Anfrage).
--- Für den Tide-Coins-Kanal (RequestOpenEgg an der Station, kostet
--- GachaConfig.EGG_COST_TIDE_COINS) - Robux-Käufe laufen über
--- OpenPurchasedEgg (siehe unten).
function GachaService.OpenEgg(player: Player): (OpenEggResult?, OpenEggFailure?)
	-- 0) Persistenz-Voraussetzung: ohne geladene Spielerdaten kein Roll -
	-- sonst könnten Pity-Zähler/Inventar/Tide-Coins-Gutschrift verloren
	-- gehen (z. B. bei einer Anfrage, die ungewöhnlich schnell nach dem
	-- Join eintrifft, noch bevor PlayerDataService fertig geladen hat).
	if not PlayerDataService.IsDataLoaded(player) then
		return nil, "DataNotLoaded"
	end

	local state = getOrCreatePlayerState(player)

	local now = os.clock()
	if now - state.lastRollAt < GachaConfig.MIN_SECONDS_BETWEEN_ROLLS then
		return nil, "OnCooldown"
	end
	state.lastRollAt = now

	local cost = GachaConfig.EGG_COST_TIDE_COINS
	if PlayerDataService.GetCurrency(player, "TideCoins") < cost then
		return nil, "NotEnoughCoins"
	end
	PlayerDataService.AddCurrency(player, "TideCoins", -cost)

	return performRoll(player, false), nil
end

-- // EINHÄNGEPUNKT: Robux-"Mystery Egg"-Entwicklerprodukt -----------------------
-- GDD Abschnitt 5: "Mystery Egg (zufällige Kreatur, Rarity-Chance), 89 Robux -
-- Gacha-artiges Sammelelement (mit klar kommunizierten Drop-Chancen)".
-- Aufgerufen ausschließlich von MonetizationService.ProcessReceipt NACH
-- erfolgreich verifiziertem Kauf (Robux bereits abgebucht) - deshalb bewusst
-- OHNE den Anti-Spam-Cooldown von OpenEgg (siehe performRoll-Kommentar) und
-- OHNE eigene Idempotenz-Prüfung (die übernimmt MonetizationService zentral
-- über PlayerDataService.HasProcessedPurchase/MarkPurchaseProcessed - jeder
-- Aufruf hier führt IMMER zu genau einem Roll). Teilt sich die komplette
-- Roll-/Pity-/Duplikat-/Logging-Logik 1:1 mit OpenEgg über performRoll.
function GachaService.OpenPurchasedEgg(player: Player): (OpenEggResult?, OpenEggFailure?)
	if not PlayerDataService.IsDataLoaded(player) then
		return nil, "DataNotLoaded"
	end
	return performRoll(player, true), nil
end

Players.PlayerRemoving:Connect(GachaService.HandlePlayerRemoving)

return GachaService
