--[[
	Abyssara – Deep Tide Tycoon
	Modul: GachaHistoryLogger
	Zuständigkeit:
		Einfaches, klar geschnittenes Logging-Interface für jede Mystery-Egg-
		Öffnung, als Grundlage für spätere Audit-/Support-Fähigkeit
		("Kauf-/Roll-Historie-Logging", expansion-concepts.md Abschnitt 1.7).

	Rojo-Einhängepunkt:
		src/server/  ->  ServerScriptService
		(reines Server-Modul, wird ausschließlich von GachaService verwendet)

	============================================================
	PLATZHALTER-HINWEIS (Persistenz):
	Dieses Modul hält die Historie aktuell NUR in einem In-Memory-
	Ringpuffer (siehe HISTORY_CAPACITY). Das Projekt hat noch kein
	DataStore-/ProfileService- oder externes Logging-/Analytics-System.
	Die Historie geht daher bei jedem Server-Neustart verloren und ist
	NICHT für echte Compliance-Audits geeignet - sie dient hier nur als
	lauffähiges Gerüst mit stabiler API.
	Sobald ein Persistenz-/Analytics-System existiert, genügt es, den
	Körper von LogRoll() zu erweitern (z. B. zusätzlich an einen
	OrderedDataStore, eine externe Logging-API oder ein Analytics-Event
	zu senden) - die Funktionssignatur und alle Aufrufstellen in
	GachaService bleiben unverändert.
	============================================================
]]

local GachaHistoryLogger = {}

export type RollLogEntry = {
	UserId: number,
	Username: string,
	Timestamp: number, -- os.time(), Unix-Sekunden
	Rarity: string,
	CreatureId: string,
	CreatureName: string,
	ResultType: "New" | "Duplicate",
	CompensationTideCoins: number,
	PityForced: boolean,
}

-- Ringpuffer über alle Spieler hinweg (jüngster Eintrag zuletzt).
local HISTORY_CAPACITY = 500
local history: { RollLogEntry } = {}

--- Protokolliert eine einzelne Ei-Öffnung. Wird von GachaService.OpenEgg()
--- direkt nach dem Roll aufgerufen (immer serverseitig, nie vom Client
--- getriggert).
function GachaHistoryLogger.LogRoll(player: Player, entryData: {
	Rarity: string,
	CreatureId: string,
	CreatureName: string,
	ResultType: "New" | "Duplicate",
	CompensationTideCoins: number,
	PityForced: boolean,
}): RollLogEntry
	local entry: RollLogEntry = {
		UserId = player.UserId,
		Username = player.Name,
		Timestamp = os.time(),
		Rarity = entryData.Rarity,
		CreatureId = entryData.CreatureId,
		CreatureName = entryData.CreatureName,
		ResultType = entryData.ResultType,
		CompensationTideCoins = entryData.CompensationTideCoins,
		PityForced = entryData.PityForced,
	}

	table.insert(history, entry)
	if #history > HISTORY_CAPACITY then
		table.remove(history, 1)
	end

	print(
		("[GachaAudit] %s (UserId %d) -> %s/%s (%s%s) | Ausgleich: %d Tide Coins"):format(
			entry.Username,
			entry.UserId,
			entry.Rarity,
			entry.CreatureName,
			entry.ResultType,
			entry.PityForced and ", Pity" or "",
			entry.CompensationTideCoins
		)
	)

	return entry
end

--- Liefert die letzten `count` Einträge über alle Spieler (neueste zuerst).
--- Gedacht für ein späteres Admin-/Support-Tool.
function GachaHistoryLogger.GetRecentHistory(count: number): { RollLogEntry }
	local result = {}
	local startIndex = math.max(1, #history - count + 1)
	for i = #history, startIndex, -1 do
		table.insert(result, history[i])
	end
	return result
end

--- Liefert die komplette (im Speicher gehaltene) Historie eines einzelnen
--- Spielers, neueste zuerst. Gedacht für Support-Anfragen ("was hat Spieler
--- X in den letzten Ei-Öffnungen erhalten?").
function GachaHistoryLogger.GetPlayerHistory(userId: number): { RollLogEntry }
	local result = {}
	for i = #history, 1, -1 do
		local entry = history[i]
		if entry.UserId == userId then
			table.insert(result, entry)
		end
	end
	return result
end

return GachaHistoryLogger
