--[[
	Abyssara – Deep Tide Tycoon
	Modul: PlayerDataService
	Zuständigkeit:
		Zentrales Spieler-Daten-Persistenz-System - das Fundament, auf dem
		alle anderen Gameplay-Systeme aufbauen (Gacha, Bauplatzierung,
		Idle-Einkommen, Zucht, Progression, Prestige, ...).

		Verantwortet:
			- Laden der Spielerdaten bei Players.PlayerAdded (mit Session-
			  Lock gegen Doppel-Join-Dateninkonsistenz).
			- Speichern bei Players.PlayerRemoving, periodisch (Auto-Save)
			  und bei game:BindToClose (Server-Shutdown).
			- Ein versioniertes, generisches Daten-Schema (`PlayerData`) für
			  Level/XP, Währungen, Kreaturen-Inventar, Habitat-Layout,
			  Prestige-Stand und Gacha-Pity-Zähler.
			- Eine öffentliche, server-interne API, über die andere Systeme
			  (z. B. GachaService) Spielerdaten lesen/verändern, ohne selbst
			  DataStoreService anzufassen.

		Bezug: docs/game-design-doc.md, Abschnitt 6 ("Fortschrittssystem")
		und Abschnitt 9, Punkt 1 ("Plot-/Datenpersistenz-System").

	Rojo-Einhängepunkt:
		src/server/PlayerDataService.lua  ->  ServerScriptService.PlayerDataService
		(reines Server-Modul; verdrahtet PlayerAdded/PlayerRemoving/
		BindToClose selbst beim ersten require() - siehe unten, gleiche
		Konvention wie GachaService, das sich ebenfalls selbst an
		Players.PlayerRemoving hängt. Es ist daher KEIN separates
		Bootstrap-Script nötig; ein einfaches `require(...)` z. B. aus einem
		zentralen Server-Startskript genügt, um das System zu aktivieren.)

	Sicherheitsprinzip (kein Client-Trust):
		Dieses Modul exponiert absichtlich KEINE RemoteEvents/RemoteFunctions
		selbst - jede Datenänderung läuft ausschließlich über Aufrufe
		anderer, server-interner Module (z. B. GachaService.OpenEgg, das
		selbst nur von der Roblox-Engine gesetzte `Player`-Objekte aus
		OnServerEvent entgegennimmt). Der Client kann diese API nicht
		erreichen.

	DataStore-Robustheit:
		- JEDER DataStoreService-Aufruf läuft in pcall (siehe `withRetry`).
		- Exponentielles Backoff + Jitter zwischen Wiederholungsversuchen.
		- Session-Locking via UpdateAsync: jeder Datensatz trägt ein
		  `ActiveSession`-Feld (SessionId = game.JobId, LockedAt = Zeit-
		  stempel). Ein zweiter Server, der denselben Spieler gleichzeitig
		  laden will, erkennt eine noch aktive, nicht-abgelaufene Session
		  eines anderen Servers und wartet/bricht ab, statt den Datensatz
		  zu überschreiben ("Stale"-Timeout nach SESSION_LOCK_STALE_SECONDS
		  federt Server-Crashes ab, bei denen der Lock nie sauber
		  freigegeben wurde).
		- Schlägt das initiale Laden vollständig fehl (alle Retries
		  ausgeschöpft) oder bleibt der Datensatz von einem anderen Server
		  gesperrt, wird der Spieler mit einer klaren Meldung gekickt statt
		  mit Default-Daten weiterspielen zu lassen (das würde bei einem
		  späteren Save den echten Spielstand überschreiben) - im Zweifel
		  lieber nicht speichern/spielen lassen als Daten zu korrumpieren.
		- Ein Save überschreibt einen Datensatz nie, wenn zwischenzeitlich
		  ein anderer Server den Lock übernommen hat (siehe `pushSave`).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local PlayerDataService = {}

-- // Daten-Schema ------------------------------------------------------------

export type CurrencyType = "TideCoins" | "AbyssalShards"

export type CreatureInstance = {
	InstanceId: string, -- eindeutig je Roll (HttpService:GenerateGUID), NICHT die Kreaturen-Art
	CreatureId: string, -- Kreaturen-Art, entspricht GachaConfig.CREATURE_POOL-Einträgen
	Rarity: string,
	AcquiredAt: number, -- os.time(), Unix-Sekunden
}

export type HabitatPlacement = {
	PlacementId: string, -- eindeutig (HttpService:GenerateGUID)
	BuildingId: string, -- referenziert künftig assets/models/buildings/*
	Position: { X: number, Y: number, Z: number },
	RotationY: number, -- Grad um die Y-Achse (Snap-Rotation eines künftigen Placement-Systems)
	Level: number, -- Ausbaustufe des Gebäudes (Upgrade-Logik folgt mit dem Bausystem)
	PlacedAt: number,
}

export type SessionLock = {
	SessionId: string, -- game.JobId des haltenden Servers
	LockedAt: number, -- os.time() der letzten Lock-Erneuerung
}

--- Versioniertes Spieler-Datenschema. SchemaVersion erlaubt künftigen
--- Migrationen (siehe MIGRATIONS unten), alte DataStore-Einträge sicher auf
--- neue Strukturen zu heben, statt sie zu verwerfen.
export type PlayerData = {
	SchemaVersion: number,
	UserId: number,

	Level: number,
	XP: number,

	Currencies: {
		TideCoins: number,
		AbyssalShards: number,
	},

	CreatureInventory: { CreatureInstance },
	HabitatLayout: { HabitatPlacement },

	Prestige: {
		AscendCount: number,
		IncomeMultiplier: number, -- vgl. GDD Abschnitt 6: +10%/Ascend mit Diminishing Returns ab Ascend 10
	},

	GachaState: {
		PityCounter: number, -- Pity-Zähler fürs Mystery-Egg-Gacha-System (GachaConfig.PITY_THRESHOLD)
	},

	Timestamps: {
		CreatedAt: number,
		LastLoginAt: number,
		LastSavedAt: number,
	},

	ActiveSession: SessionLock?, -- Session-Lock-Metadaten; niemals von Gameplay-Code lesen/schreiben
}

-- // Konfiguration ------------------------------------------------------------

local SCHEMA_VERSION = 1
local DATASTORE_NAME = "Abyssara_PlayerData_v1"

local SESSION_LOCK_STALE_SECONDS = 90 -- ab wann ein fremder Lock als "verwaist" (Server-Crash) gilt
local JOIN_LOCK_RETRY_ATTEMPTS = 3
local JOIN_LOCK_RETRY_DELAY_SECONDS = 4

local DATASTORE_RETRY_ATTEMPTS = 5
local DATASTORE_RETRY_BASE_DELAY_SECONDS = 1

local AUTO_SAVE_INTERVAL_SECONDS = 180 -- alle 3 Minuten, Absicherung gegen Serverabstürze
local BIND_TO_CLOSE_MAX_WAIT_SECONDS = 25 -- unter Robloxs ~30s BindToClose-Budget bleiben

local VALID_CURRENCIES: { [string]: boolean } = { TideCoins = true, AbyssalShards = true }

local playerDataStore = DataStoreService:GetDataStore(DATASTORE_NAME)

-- game.JobId ist in Studio-Playtests "" - Fallback auf eine GUID, damit
-- Session-Locking auch dort (rein logisch, DataStore läuft in Studio ggf.
-- gegen den lokalen Emulator) konsistent funktioniert.
local SESSION_ID: string = (game.JobId ~= "" and game.JobId) or HttpService:GenerateGUID(false)

local rng = Random.new()

-- // Pro-Spieler-Laufzeitzustand -----------------------------------------------

local dataCache: { [number]: PlayerData } = {}
local loadedFlags: { [number]: boolean } = {}
local loadFailedFlags: { [number]: boolean } = {}
local loadSignals: { [number]: BindableEvent } = {}

-- // Kleine Hilfsfunktionen ----------------------------------------------------

local function dataKey(userId: number): string
	return "Player_" .. tostring(userId)
end

--- Führt `fn` mit Wiederholungsversuchen + exponentiellem Backoff (+Jitter)
--- aus. Fängt JEDEN Fehler per pcall ab - nichts, was DataStoreService
--- wirft, darf den Server hart crashen oder einen Spieler-Datensatz
--- korrumpieren. Gibt (true, ergebnis) bei Erfolg zurück, sonst (false, nil).
local function withRetry(description: string, fn: () -> any): (boolean, any)
	local lastErr: any = nil
	for attempt = 1, DATASTORE_RETRY_ATTEMPTS do
		local ok, resultOrErr = pcall(fn)
		if ok then
			return true, resultOrErr
		end

		lastErr = resultOrErr
		warn(
			("[PlayerDataService] %s fehlgeschlagen (Versuch %d/%d): %s"):format(
				description,
				attempt,
				DATASTORE_RETRY_ATTEMPTS,
				tostring(resultOrErr)
			)
		)

		if attempt < DATASTORE_RETRY_ATTEMPTS then
			local backoff = DATASTORE_RETRY_BASE_DELAY_SECONDS * (2 ^ (attempt - 1))
			local jitter = rng:NextNumber() * DATASTORE_RETRY_BASE_DELAY_SECONDS
			task.wait(backoff + jitter)
		end
	end
	warn(("[PlayerDataService] %s endgültig fehlgeschlagen nach %d Versuchen: %s"):format(description, DATASTORE_RETRY_ATTEMPTS, tostring(lastErr)))
	return false, nil
end

--- Erzeugt frische Startdaten für einen neuen Spieler (GDD Abschnitt 6:
--- Level 1, 0 Währungen, leeres Inventar/Layout, kein Prestige, Pity 0).
local function createDefaultData(userId: number): PlayerData
	local now = os.time()
	return {
		SchemaVersion = SCHEMA_VERSION,
		UserId = userId,

		Level = 1,
		XP = 0,

		Currencies = {
			TideCoins = 0,
			AbyssalShards = 0,
		},

		CreatureInventory = {},
		HabitatLayout = {},

		Prestige = {
			AscendCount = 0,
			IncomeMultiplier = 1.0,
		},

		GachaState = {
			PityCounter = 0,
		},

		Timestamps = {
			CreatedAt = now,
			LastLoginAt = now,
			LastSavedAt = 0,
		},

		ActiveSession = nil,
	}
end

-- // Migrationen ---------------------------------------------------------------
-- Je künftiger Schema-Version N ein Eintrag [N] = function(oldData) -> newData,
-- der einen Datensatz mit SchemaVersion == N auf N+1 hebt. Aktuell leer, da
-- SCHEMA_VERSION == 1 die erste Version ist - das Gerüst steht bereit, sobald
-- sich das Schema ändert (z. B. Umbenennung/Aufspaltung eines Feldes).
local MIGRATIONS: { [number]: (PlayerData) -> PlayerData } = {}

--- Hebt einen rohen (ggf. alten/unvollständigen oder nil) DataStore-Wert auf
--- die aktuelle Struktur: wendet fehlende Migrationsschritte an und füllt
--- danach defensiv alle fehlenden Top-Level-/Sub-Felder mit Default-Werten
--- auf (schützt z. B. vor manueller DataStore-Bearbeitung oder künftigen,
--- noch nicht migrierten Zwischenständen), OHNE bestehende Werte zu
--- überschreiben.
local function migrateData(raw: any, userId: number): PlayerData
	if type(raw) ~= "table" then
		return createDefaultData(userId)
	end

	local data = (raw :: any) :: PlayerData
	local version = data.SchemaVersion or 0

	while version < SCHEMA_VERSION do
		local migrate = MIGRATIONS[version]
		if not migrate then
			-- Keine explizite Migration für diese Version hinterlegt: statt
			-- den Datensatz zu verwerfen, unten defensiv auf die aktuelle
			-- Struktur auffüllen und die Version direkt hochsetzen.
			break
		end
		data = migrate(data)
		version += 1
		data.SchemaVersion = version
	end

	local default = createDefaultData(userId)

	local function fillMissing(target: any, defaults: any)
		for key, value in pairs(defaults) do
			if target[key] == nil then
				target[key] = value
			elseif type(value) == "table" and type(target[key]) == "table" then
				fillMissing(target[key], value)
			end
		end
	end

	fillMissing(data, default)

	data.SchemaVersion = SCHEMA_VERSION
	data.UserId = userId
	return data
end

-- // Laden + Session-Lock (UpdateAsync) ----------------------------------------

--- Genau EIN atomarer Lade-/Lock-Versuch über UpdateAsync. Gibt
--- (ok, data?, lockedByOtherServer) zurück. `ok = false` bedeutet: der
--- DataStore-Aufruf selbst ist nach allen internen Retries fehlgeschlagen
--- (transienter Fehler). `lockedByOtherServer = true` bedeutet: der Aufruf
--- war technisch erfolgreich, aber ein anderer Server hält aktuell einen
--- nicht-abgelaufenen Lock auf diesen Datensatz.
local function tryClaimSession(userId: number): (boolean, PlayerData?, boolean)
	local key = dataKey(userId)
	local lockedByOther = false
	local claimed: PlayerData? = nil

	local ok = withRetry(("Laden/Sperren UserId %d"):format(userId), function()
		playerDataStore:UpdateAsync(key, function(oldValue)
			local now = os.time()
			local existingSession = oldValue and (oldValue :: any).ActiveSession

			if
				existingSession
				and existingSession.SessionId ~= SESSION_ID
				and (now - (existingSession.LockedAt or 0)) < SESSION_LOCK_STALE_SECONDS
			then
				-- Noch aktiver Lock eines anderen Servers: Datensatz
				-- unverändert zurückgeben (kein Überschreiben!), Abbruch
				-- wird über `lockedByOther` an den Aufrufer signalisiert.
				lockedByOther = true
				return oldValue
			end

			lockedByOther = false
			local migrated = migrateData(oldValue, userId)
			migrated.Timestamps.LastLoginAt = now
			migrated.ActiveSession = { SessionId = SESSION_ID, LockedAt = now }
			claimed = migrated
			return migrated
		end)
		return true
	end)

	if not ok then
		return false, nil, false
	end

	return true, claimed, lockedByOther
end

--- Lädt die Daten eines Spielers und beansprucht dabei den Session-Lock.
--- Wiederholt bei "von anderem Server gesperrt" (JOIN_LOCK_RETRY_*), damit
--- ein schneller Server-Wechsel (z. B. Teleport) nicht sofort scheitert.
--- Gibt (data, nil) bei Erfolg oder (nil, failureReason) zurück.
local function loadPlayerData(userId: number): (PlayerData?, string?)
	for attempt = 1, JOIN_LOCK_RETRY_ATTEMPTS do
		local ok, data, lockedByOther = tryClaimSession(userId)

		if not ok then
			return nil, "DataStoreError"
		end

		if not lockedByOther then
			return data, nil
		end

		if attempt < JOIN_LOCK_RETRY_ATTEMPTS then
			task.wait(JOIN_LOCK_RETRY_DELAY_SECONDS)
		end
	end

	return nil, "SessionLocked"
end

-- // Speichern -----------------------------------------------------------------

--- Schreibt `data` für `userId` atomar zurück. `releaseLock == true` gibt
--- den Session-Lock frei (PlayerRemoving/BindToClose), sonst wird er mit
--- neuem Zeitstempel erneuert (periodischer Auto-Save, Spieler bleibt
--- online). Überschreibt NIE einen Datensatz, dessen Lock zwischenzeitlich
--- (nach Stale-Timeout) von einem anderen Server übernommen wurde - dann
--- lieber unseren Save verwerfen als den Stand des anderen Servers
--- zerstören.
local function pushSave(userId: number, data: PlayerData, releaseLock: boolean): boolean
	local key = dataKey(userId)

	local ok = withRetry(("Speichern UserId %d"):format(userId), function()
		playerDataStore:UpdateAsync(key, function(oldValue)
			local existingSession = oldValue and (oldValue :: any).ActiveSession
			if existingSession and existingSession.SessionId ~= SESSION_ID then
				-- Lock wurde von einem anderen Server übernommen (Stale-
				-- Timeout nach Crash dieses Servers) - unsere Kopie ist
				-- veraltet, NICHT speichern.
				return oldValue
			end

			local now = os.time()
			local toSave = table.clone(data) :: PlayerData
			toSave.Timestamps = table.clone(data.Timestamps)
			toSave.Timestamps.LastSavedAt = now
			toSave.ActiveSession = if releaseLock then nil else { SessionId = SESSION_ID, LockedAt = now }
			return toSave
		end)
		return true
	end)

	return ok
end

-- // PlayerAdded / PlayerRemoving / Auto-Save / BindToClose --------------------

local function onPlayerAdded(player: Player)
	local userId = player.UserId
	loadSignals[userId] = Instance.new("BindableEvent")

	local data, failureReason = loadPlayerData(userId)

	-- Spieler kann während des (potenziell mehrsekündigen, retry-behafteten)
	-- Ladevorgangs bereits wieder disconnected sein.
	local stillHere = Players:GetPlayerByUserId(userId) == player

	if not data then
		loadFailedFlags[userId] = true
		local signal = loadSignals[userId]
		if signal then
			signal:Fire(false)
		end

		warn(("[PlayerDataService] Laden für %s (UserId %d) fehlgeschlagen: %s"):format(player.Name, userId, tostring(failureReason)))

		if stillHere then
			local message = if failureReason == "SessionLocked"
				then "Deine Daten werden noch auf einem anderen Server verarbeitet. Bitte versuche es in ein paar Sekunden erneut."
				else "Deine Spielerdaten konnten nicht geladen werden. Bitte versuche es erneut."
			player:Kick(message)
		end
		return
	end

	if not stillHere then
		-- Lock wurde erfolgreich beansprucht, aber der Spieler ist schon
		-- weg: sofort wieder freigeben/speichern statt den Lock bis zum
		-- Stale-Timeout blockiert zu lassen.
		pushSave(userId, data, true)
		local signal = loadSignals[userId]
		if signal then
			signal:Fire(false)
			signal:Destroy()
		end
		loadSignals[userId] = nil
		return
	end

	dataCache[userId] = data
	loadedFlags[userId] = true

	local signal = loadSignals[userId]
	if signal then
		signal:Fire(true)
	end

	print(("[PlayerDataService] Daten für %s (UserId %d) geladen (Level %d, %d Tide Coins)."):format(
		player.Name,
		userId,
		data.Level,
		data.Currencies.TideCoins
	))
end

local function onPlayerRemoving(player: Player)
	local userId = player.UserId
	local data = dataCache[userId]

	if data and loadedFlags[userId] then
		pushSave(userId, data, true)
	end

	dataCache[userId] = nil
	loadedFlags[userId] = nil
	loadFailedFlags[userId] = nil

	local signal = loadSignals[userId]
	if signal then
		signal:Destroy()
		loadSignals[userId] = nil
	end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Falls dieses Modul erst nach PlayerAdded-Events requiret wird (z. B.
-- Studio-Playtest-Timing), bereits verbundene Spieler nachträglich laden.
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

-- Auto-Save: Absicherung gegen Serverabstürze, damit im Worst Case nur die
-- letzten paar Minuten Fortschritt verloren gehen statt der ganzen Session.
task.spawn(function()
	while true do
		task.wait(AUTO_SAVE_INTERVAL_SECONDS)
		for userId, data in pairs(dataCache) do
			if Players:GetPlayerByUserId(userId) then
				task.spawn(function()
					pushSave(userId, data, false)
				end)
			end
		end
	end
end)

-- Sauberes Speichern bei Server-Shutdown (Deploy, Roblox-Wartung, Crash-
-- Handling durch die Engine selbst). Läuft parallel über alle Spieler,
-- wartet aber bounded (BIND_TO_CLOSE_MAX_WAIT_SECONDS) auf Abschluss, um
-- innerhalb von Robloxs BindToClose-Zeitbudget (~30s) zu bleiben.
game:BindToClose(function()
	local pending = 0
	for userId, data in pairs(dataCache) do
		pending += 1
		task.spawn(function()
			pushSave(userId, data, true)
			pending -= 1
		end)
	end

	local waited = 0
	while pending > 0 and waited < BIND_TO_CLOSE_MAX_WAIT_SECONDS do
		task.wait(0.5)
		waited += 0.5
	end
end)

-- // Öffentliche API ----------------------------------------------------------

--- true, sobald die Daten eines (noch verbundenen) Spielers vollständig
--- geladen und einsatzbereit im Cache liegen.
function PlayerDataService.IsDataLoaded(player: Player): boolean
	return loadedFlags[player.UserId] == true
end

--- Blockierender Zugriff auf die Spielerdaten: liefert sie sofort, falls
--- schon geladen, wartet sonst bis zu `timeoutSeconds` (Default 10s) auf
--- den Abschluss des Ladevorgangs. Gedacht für Systeme, deren allererster
--- Aufruf knapp nach PlayerAdded passieren könnte (z. B. ein Client-
--- Request, der ungewöhnlich schnell nach dem Join eintrifft). Für den
--- Gacha-Flow selbst reicht `IsDataLoaded` + Ablehnung, siehe GachaService.
function PlayerDataService.WaitForData(player: Player, timeoutSeconds: number?): PlayerData?
	local userId = player.UserId

	if loadedFlags[userId] then
		return dataCache[userId]
	end
	if loadFailedFlags[userId] then
		return nil
	end

	local signal = loadSignals[userId]
	if not signal then
		return dataCache[userId]
	end

	local timeout = timeoutSeconds or 10
	local finished, success = false, false
	local connection: RBXScriptConnection
	connection = signal.Event:Connect(function(ok: boolean)
		finished = true
		success = ok
	end)

	local waited = 0
	while not finished and waited < timeout do
		task.wait(0.1)
		waited += 0.1
	end
	connection:Disconnect()

	if success then
		return dataCache[userId]
	end
	return nil
end

--- Liefert die live gecachte Datenstruktur eines Spielers (oder nil, falls
--- noch nicht/nicht mehr geladen). ACHTUNG: liefert eine Live-Referenz aus
--- Performance-/Einfachheitsgründen (server-interne API, kein Client-
--- Zugriff möglich) - bitte für Änderungen bevorzugt die Setter-Funktionen
--- unten verwenden statt das Ergebnis direkt zu mutieren, damit Validierung
--- (z. B. Untergrenzen bei Währungen) an einer Stelle bleibt.
function PlayerDataService.GetData(player: Player): PlayerData?
	return dataCache[player.UserId]
end

--- Stößt sofort einen Speichervorgang an (z. B. vor einer riskanten
--- Operation), ohne den Session-Lock freizugeben. Blockiert den
--- aufrufenden Thread bis zum Abschluss (inkl. Retries).
function PlayerDataService.ForceSave(player: Player): boolean
	local userId = player.UserId
	local data = dataCache[userId]
	if not data then
		return false
	end
	return pushSave(userId, data, false)
end

-- // Währungen -----------------------------------------------------------------

function PlayerDataService.GetCurrency(player: Player, currencyType: CurrencyType): number
	local data = dataCache[player.UserId]
	if not data or not VALID_CURRENCIES[currencyType] then
		return 0
	end
	return data.Currencies[currencyType] or 0
end

--- Addiert `amount` (kann negativ sein, um Kosten abzuziehen) auf die
--- angegebene Währung. Klemmt das Ergebnis auf minimal 0 (kein negatives
--- Guthaben). Gibt (success, neuerKontostand) zurück; success = false bei
--- ungeladenen Daten, unbekanntem CurrencyType oder ungültigem `amount`
--- (NaN/nicht-Zahl) - in keinem dieser Fälle wird etwas verändert.
function PlayerDataService.AddCurrency(player: Player, currencyType: CurrencyType, amount: number): (boolean, number)
	local userId = player.UserId
	local data = dataCache[userId]

	if not data then
		warn(("[PlayerDataService] AddCurrency für UserId %d ohne geladene Daten aufgerufen."):format(userId))
		return false, 0
	end

	if not VALID_CURRENCIES[currencyType] then
		warn(("[PlayerDataService] Unbekannter CurrencyType '%s'."):format(tostring(currencyType)))
		return false, data.Currencies.TideCoins
	end

	if type(amount) ~= "number" or amount ~= amount then -- amount ~= amount erkennt NaN
		return false, data.Currencies[currencyType] or 0
	end

	local newBalance = math.max(0, (data.Currencies[currencyType] or 0) + amount)
	data.Currencies[currencyType] = newBalance
	return true, newBalance
end

-- // Kreaturen-Inventar ---------------------------------------------------------

--- true, wenn der Spieler mindestens eine Instanz der angegebenen
--- Kreaturen-Art (CreatureId, z. B. "GlowJelly") besitzt. Ersetzt
--- GachaServices vormaligen Platzhalter `PlayerOwnsCreature`.
function PlayerDataService.PlayerHasCreature(player: Player, creatureId: string): boolean
	local data = dataCache[player.UserId]
	if not data then
		return false
	end
	for _, creature in ipairs(data.CreatureInventory) do
		if creature.CreatureId == creatureId then
			return true
		end
	end
	return false
end

--- Fügt eine neue Kreaturen-Instanz zum Inventar hinzu (z. B. nach einem
--- neuen Gacha-Roll). Vergibt automatisch InstanceId + AcquiredAt. Gibt die
--- erzeugte Instanz zurück, oder nil, falls die Daten des Spielers nicht
--- geladen sind.
function PlayerDataService.AddCreatureToInventory(
	player: Player,
	creatureData: { CreatureId: string, Rarity: string }
): CreatureInstance?
	local data = dataCache[player.UserId]
	if not data then
		warn(("[PlayerDataService] AddCreatureToInventory für UserId %d ohne geladene Daten aufgerufen."):format(player.UserId))
		return nil
	end

	local instance: CreatureInstance = {
		InstanceId = HttpService:GenerateGUID(false),
		CreatureId = creatureData.CreatureId,
		Rarity = creatureData.Rarity,
		AcquiredAt = os.time(),
	}

	table.insert(data.CreatureInventory, instance)
	return instance
end

--- Liefert das komplette Kreaturen-Inventar eines Spielers (leere Liste,
--- falls nicht geladen).
function PlayerDataService.GetCreatureInventory(player: Player): { CreatureInstance }
	local data = dataCache[player.UserId]
	return data and data.CreatureInventory or {}
end

-- // Gacha-Pity-Zähler -----------------------------------------------------------

function PlayerDataService.GetPityCounter(player: Player): number
	local data = dataCache[player.UserId]
	return data and data.GachaState.PityCounter or 0
end

function PlayerDataService.SetPityCounter(player: Player, value: number): boolean
	local data = dataCache[player.UserId]
	if not data then
		return false
	end
	data.GachaState.PityCounter = math.max(0, math.floor(value))
	return true
end

-- // Level / XP ------------------------------------------------------------------
-- Speichert nur die Rohwerte; die eigentliche XP->Level-Kurve (GDD
-- Abschnitt 6) gehört zum künftigen Progression-/Level-System (GDD
-- Abschnitt 9, Punkt 7) und wird bewusst NICHT hier vorweggenommen.

function PlayerDataService.GetLevel(player: Player): number
	local data = dataCache[player.UserId]
	return data and data.Level or 1
end

function PlayerDataService.GetXP(player: Player): number
	local data = dataCache[player.UserId]
	return data and data.XP or 0
end

function PlayerDataService.AddXP(player: Player, amount: number): number?
	local data = dataCache[player.UserId]
	if not data or type(amount) ~= "number" or amount ~= amount then
		return nil
	end
	data.XP = math.max(0, data.XP + amount)
	return data.XP
end

function PlayerDataService.SetLevel(player: Player, level: number): boolean
	local data = dataCache[player.UserId]
	if not data or type(level) ~= "number" then
		return false
	end
	data.Level = math.max(1, math.floor(level))
	return true
end

-- // Habitat-Layout ---------------------------------------------------------------
-- Reine Datenhaltung - Grid-/Kollisions-/Snap-Logik gehört zum künftigen
-- Bauplatzierungs-System (GDD Abschnitt 9, Punkt 2) und lebt NICHT hier.

function PlayerDataService.GetHabitatLayout(player: Player): { HabitatPlacement }
	local data = dataCache[player.UserId]
	return data and data.HabitatLayout or {}
end

function PlayerDataService.AddHabitatPlacement(
	player: Player,
	placementData: { BuildingId: string, Position: { X: number, Y: number, Z: number }, RotationY: number? }
): HabitatPlacement?
	local data = dataCache[player.UserId]
	if not data then
		return nil
	end

	local placement: HabitatPlacement = {
		PlacementId = HttpService:GenerateGUID(false),
		BuildingId = placementData.BuildingId,
		Position = placementData.Position,
		RotationY = placementData.RotationY or 0,
		Level = 1,
		PlacedAt = os.time(),
	}

	table.insert(data.HabitatLayout, placement)
	return placement
end

function PlayerDataService.RemoveHabitatPlacement(player: Player, placementId: string): boolean
	local data = dataCache[player.UserId]
	if not data then
		return false
	end
	for index, placement in ipairs(data.HabitatLayout) do
		if placement.PlacementId == placementId then
			table.remove(data.HabitatLayout, index)
			return true
		end
	end
	return false
end

-- // Prestige / Ascend ------------------------------------------------------------

function PlayerDataService.GetAscendCount(player: Player): number
	local data = dataCache[player.UserId]
	return data and data.Prestige.AscendCount or 0
end

function PlayerDataService.GetIncomeMultiplier(player: Player): number
	local data = dataCache[player.UserId]
	return data and data.Prestige.IncomeMultiplier or 1.0
end

return PlayerDataService
