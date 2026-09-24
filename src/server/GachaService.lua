--[[
	Abyssara – Deep Tide Tycoon
	Modul: GachaService
	Zuständigkeit:
		Kernlogik des Mystery-Egg-Gacha-Systems: gewichteter Zufalls-Roll auf
		Basis von GachaConfig.DROP_TABLE, Pity-Tracking pro Spieler,
		Duplikat-Erkennung + Ausgleichs-Konvertierung, sowie eine saubere,
		exportierte API, an die spätere Systeme (RemoteEvent-Handler,
		Persistenz, Economy) andocken.

		Dies ist der erste Gameplay-Code-Baustein im Projekt - es existiert
		bewusst noch KEIN echtes Inventar-, Economy- oder Persistenz-System.
		Alle drei Stellen, an denen dieses Modul später an solche Systeme
		andocken muss, sind unten klar als PLATZHALTER-Abschnitte markiert
		(WARUM sie Platzhalter sind, nicht WAS ihre grobe Aufgabe ist - die
		grobe Aufgabe ist bereits real/lauffähig implementiert).

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

export type OpenEggFailure = "OnCooldown"

local GachaService = {}

-- // Pro-Spieler-Zustand (Pity-Zähler + Anti-Spam-Timestamp) -----------------
type PlayerGachaState = {
	pityCounter: number,
	lastRollAt: number,
}

local playerStates: { [number]: PlayerGachaState } = {}

-- ============================================================
-- PLATZHALTER-SCHNITTSTELLE: Persistenz (Pity-Zähler pro Spieler)
-- Es existiert im Projekt noch KEIN DataStore-/ProfileService-System.
-- playerStates ist deshalb rein In-Memory (UserId-indiziert) und geht bei
-- jedem Serverneustart/-crash verloren - für den Pity-Mechanismus ist das
-- akzeptabel-suboptimal (Spieler verliert im Worst Case Pity-Fortschritt),
-- aber NICHT für einen produktiven Release ausreichend.
-- LoadPityState()/SavePityState() sind bewusst als eigene, schmale
-- Funktionen geschnitten (statt DataStore-Aufrufe verstreut in
-- PlayerAdded/PlayerRemoving zu verteilen), damit ein späteres
-- Persistenz-Modul sie 1:1 ersetzen kann, ohne den Rest von GachaService
-- anzufassen: einfach den Funktionskörper austauschen (DataStore GetAsync/
-- UpdateAsync statt Table-Zugriff), Signatur bleibt gleich.
-- ============================================================
local function loadPityState(player: Player): PlayerGachaState
	-- TODO(Persistenz): hier künftig DataStore/ProfileService laden statt
	-- immer bei 0 zu starten.
	return { pityCounter = 0, lastRollAt = 0 }
end

local function savePityState(player: Player, state: PlayerGachaState)
	-- TODO(Persistenz): hier künftig DataStore/ProfileService schreiben.
	-- Aktuell no-op, da der State ohnehin nur In-Memory existiert.
end

local function getOrCreatePlayerState(player: Player): PlayerGachaState
	local state = playerStates[player.UserId]
	if not state then
		state = loadPityState(player)
		playerStates[player.UserId] = state
	end
	return state
end

--- Wird von GachaServer.server.lua an Players.PlayerRemoving gehängt.
--- Räumt den In-Memory-Zustand auf und stößt (Platzhalter-)Persistenz an.
function GachaService.HandlePlayerRemoving(player: Player)
	local state = playerStates[player.UserId]
	if state then
		savePityState(player, state)
	end
	playerStates[player.UserId] = nil
end

-- ============================================================
-- PLATZHALTER-SCHNITTSTELLE: Inventar-System (Duplikatsschutz)
-- Es existiert im Projekt noch KEIN echtes Inventar-/Sammlungs-System für
-- Kreaturen. Die beiden Funktionen unten simulieren ein Inventar rein
-- In-Memory (Set aus CreatureId je UserId) und sind bewusst so
-- geschnitten, dass ein späteres echtes Inventar-Modul (vermutlich
-- DataStore-/ProfileService-gestützt, evtl. Teil des Kreaturen-Kodex aus
-- Konzept 1.5) sie 1:1 ersetzen kann:
--   PlayerOwnsCreature(player, creatureId) -> boolean
--   AddCreatureToInventory(player, creatureId) -> ()
-- GachaService.OpenEgg() ruft ausschließlich diese beiden Funktionen auf,
-- nie den internen Table direkt - der Austausch bleibt also lokal auf
-- diesen Block begrenzt.
-- ============================================================
local placeholderInventory: { [number]: { [string]: boolean } } = {}

local function PlayerOwnsCreature(player: Player, creatureId: string): boolean
	local owned = placeholderInventory[player.UserId]
	return owned ~= nil and owned[creatureId] == true
end

local function AddCreatureToInventory(player: Player, creatureId: string)
	local owned = placeholderInventory[player.UserId]
	if not owned then
		owned = {}
		placeholderInventory[player.UserId] = owned
	end
	owned[creatureId] = true
end

-- ============================================================
-- PLATZHALTER-SCHNITTSTELLE: Economy-System (Tide Coins)
-- Es existiert im Projekt noch KEIN echtes Economy-/Währungssystem
-- (Kontostände, serverseitig abgesicherte Transaktionen, DataStore-
-- Persistenz). GrantTideCoins() simuliert eine Gutschrift rein In-Memory
-- und ist der einzige Andockpunkt, den GachaService für den
-- Duplikat-Ausgleich verwendet. Ein späteres EconomyService-Modul kann
-- diese Funktion 1:1 ersetzen (z. B. EconomyService:AddCurrency(player,
-- "TideCoins", amount)), ohne dass OpenEgg() geändert werden muss.
-- ============================================================
local placeholderTideCoinBalances: { [number]: number } = {}

local function GrantTideCoins(player: Player, amount: number)
	placeholderTideCoinBalances[player.UserId] = (placeholderTideCoinBalances[player.UserId] or 0) + amount
end

--- Rein informativ / für Debug-Zwecke; kein Teil des eigentlichen
--- Gacha-Flows. Späteres EconomyService liefert die echten Kontostände.
function GachaService.GetPlaceholderTideCoinBalance(player: Player): number
	return placeholderTideCoinBalances[player.UserId] or 0
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
--- Gibt (finalRarity, wurdePityErzwungen) zurück.
local function applyPity(state: PlayerGachaState, naturalRarity: Rarity): (Rarity, boolean)
	if GachaConfig.IsRarityAtLeast(naturalRarity, GachaConfig.PITY_MIN_RARITY) then
		-- Natürlicher Epic-oder-besser-Treffer: Zähler zurücksetzen.
		state.pityCounter = 0
		return naturalRarity, false
	end

	state.pityCounter += 1

	if state.pityCounter >= GachaConfig.PITY_THRESHOLD then
		state.pityCounter = 0

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

		return rollWeightedRarity(qualifyingRarities), true
	end

	return naturalRarity, false
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
local function pickCreatureForRarity(rarity: Rarity): (string, Rarity)
	local order = GachaConfig.RARITY_ORDER
	local startIndex = GachaConfig.GetRarityIndex(rarity)

	for index = startIndex, 1, -1 do
		local candidateRarity = order[index]
		local pool = GachaConfig.CREATURE_POOL[candidateRarity]
		if pool and #pool > 0 then
			if candidateRarity ~= rarity then
				warn(
					("[GachaService] Kein Kreaturen-Asset für Rarity '%s' vorhanden, weiche auf Pool von '%s' aus."):format(
						rarity,
						candidateRarity
					)
				)
			end
			local creatureId = pool[rng:NextInteger(1, #pool)]
			return creatureId, candidateRarity
		end
	end

	error("[GachaService] Kein Kreaturen-Pool verfügbar - GachaConfig.CREATURE_POOL ist vollständig leer.")
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

--- Kernfunktion: verarbeitet EINE Mystery-Egg-Öffnungs-Anfrage für einen
--- Spieler vollständig serverseitig (Roll, Pity, Duplikat-Check,
--- Ausgleich, Logging). Gibt entweder (result, nil) oder (nil, failure)
--- zurück (z. B. bei zu schneller Wiederholungs-Anfrage).
function GachaService.OpenEgg(player: Player): (OpenEggResult?, OpenEggFailure?)
	local state = getOrCreatePlayerState(player)

	local now = os.clock()
	if now - state.lastRollAt < GachaConfig.MIN_SECONDS_BETWEEN_ROLLS then
		return nil, "OnCooldown"
	end
	state.lastRollAt = now

	-- 1) Gewichteter Roll + Pity ------------------------------------------------
	local naturalRarity = rollWeightedRarity()
	local finalRarity, pityForced = applyPity(state, naturalRarity)

	-- 2) Kreatur innerhalb der Rarity auswählen ---------------------------------
	local creatureId, resolvedRarity = pickCreatureForRarity(finalRarity)
	local creatureName = getCreatureDisplayName(creatureId)

	-- 3) Duplikatsschutz: bereits im (Platzhalter-)Inventar? --------------------
	local resultType: "New" | "Duplicate"
	local compensation = 0

	if PlayerOwnsCreature(player, creatureId) then
		resultType = "Duplicate"
		compensation = GachaConfig.DUPLICATE_COMPENSATION_TIDE_COINS[resolvedRarity] or 0
		GrantTideCoins(player, compensation)
	else
		resultType = "New"
		AddCreatureToInventory(player, creatureId)
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

	local result: OpenEggResult = {
		Rarity = resolvedRarity,
		CreatureId = creatureId,
		CreatureName = creatureName,
		ResultType = resultType,
		CompensationTideCoins = compensation,
		PityForced = pityForced,
		PityCounter = state.pityCounter,
	}

	return result, nil
end

Players.PlayerRemoving:Connect(GachaService.HandlePlayerRemoving)

return GachaService
