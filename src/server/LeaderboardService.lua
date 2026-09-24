--[[
	Abyssara – Deep Tide Tycoon
	Modul: LeaderboardService
	Zuständigkeit:
		Kernlogik des globalen Ranglisten-Systems (GDD Abschnitt 7
		"Leaderboards" + Abschnitt 9, Punkt 10): drei OrderedDataStore-
		Ranglisten ("Level" als MVP-Proxy für "Tiefste erreichte Zone" - siehe
		Begründung unten -, "TideCoins" für "Gesamt verdiente Tide Coins",
		"RarestCollection" für "Seltenste Kreaturensammlung"), gedrosseltes
		Schreiben (kein Write pro Event, siehe writeLoop), periodisches Lesen
		der Top 50 (siehe readLoop), ein RemoteFunction-Kanal für den Client
		UND eine direkte serverseitige SurfaceGui-Befüllung am Hub-Objekt
		"LeaderboardBoard"/"DisplayPanel" (siehe assets/models/README.md,
		Abschnitt "hub").

		MVP-PROXY-ENTSCHEIDUNG "Level" statt "Tiefste Zone":
			Das GDD nennt "Tiefste erreichte Zone" als Leaderboard-Kategorie
			(Abschnitt 7). Ein Zonen-/Tiefen-Fortschrittssystem existiert im
			MVP laut ProgressionConfig-Kopfkommentar aber noch nicht (siehe
			dortiger UNLOCKS-Eintrag "ZonePortal_Daemmerzone", Implemented =
			false) - TravelService (dieser Auftrag) fügt zwar Zonen-TELEPORTS
			hinzu, aber KEINEN persistenten "höchste erreichte Zone"-Zähler
			(das wäre ein eigenständiges Datenmodell-Feature, nicht Teil
			dieses Auftrags). Spieler-Level korreliert im GDD aber direkt mit
			Zonen-Freischaltung (Abschnitt 6: "Zonenportal Dämmerzone Level
			10", Portale bei Level 1/10/25/45) - Level ist daher der
			nächstliegende, bereits vollständig vorhandene MVP-Proxy für
			"Spielfortschritt/Tiefe". Ein künftiges dediziertes
			Zonen-Tiefen-Feld kann diese Kategorie später 1:1 ersetzen, ohne
			den Rest dieses Moduls zu verändern (nur computeScores().Level
			müsste angepasst werden).

		"Seltenste Kreaturensammlung" (RarestCollection): Punktwert = Summe
		der Rarity-Indizes (Common=1..Mythic=6, siehe GachaConfig.RARITY_ORDER)
		über das komplette CreatureInventory eines Spielers - eine Sammlung
		mit vielen SELTENEN Kreaturen wertet dadurch höher als eine mit vielen
		häufigen, unabhängig von der reinen Stückzahl.

	Performance/Budget (Auftrag: "Gedrosseltes Schreiben ... nicht bei jedem
	Event", "Fehler/Budget robust behandeln"):
		- KEIN Write pro GameEvents-Ereignis. Stattdessen markiert jedes
		  potenziell score-relevante Ereignis den betroffenen Spieler nur als
		  "dirty" (siehe dirtyPlayers) - ein periodischer writeLoop
		  (WRITE_INTERVAL_SECONDS) verarbeitet ALLE aktuell als dirty
		  markierten, ONLINE Spieler in einem Rutsch, mit einer kleinen Pause
		  zwischen einzelnen SetAsync-Aufrufen (WRITE_STAGGER_SECONDS), um das
		  OrderedDataStore-Schreibbudget nicht in einer Spitze zu erschöpfen.
		- Jeder Store-Zugriff läuft in pcall (siehe withRetry) mit
		  Wiederholungsversuchen + Backoff, identisches Prinzip zu
		  PlayerDataService.withRetry - ein einzelner fehlgeschlagener Write
		  wird NICHT retried bis zum bitteren Ende (das würde den Loop
		  blockieren), sondern beim nächsten regulären writeLoop-Tick erneut
		  versucht (der Spieler bleibt bis dahin "dirty").
		- readLoop (Top 50 je Kategorie) läuft deutlich seltener
		  (READ_INTERVAL_SECONDS) und dient ausschließlich dem
		  Remote-/Board-Display - ein einzelner fehlgeschlagener Read
		  behält einfach die zuletzt erfolgreich gelesene Momentaufnahme bei
		  (kein Absturz, kein leeres Board).

	Rojo-Einhängepunkt:
		src/server/LeaderboardService.lua -> ServerScriptService.LeaderboardService
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlayerDataService = require(script.Parent:WaitForChild("PlayerDataService"))
local GameEvents = require(script.Parent:WaitForChild("GameEvents"))
local GachaConfig = require(script.Parent:WaitForChild("GachaConfig"))

export type Category = "Level" | "TideCoins" | "RarestCollection"

local LeaderboardService = {}

-- // Konfiguration ------------------------------------------------------------

local CATEGORIES: { Category } = { "Level", "TideCoins", "RarestCollection" }

local STORE_NAMES: { [Category]: string } = {
	Level = "Abyssara_LB_Level_v1",
	TideCoins = "Abyssara_LB_TideCoins_v1",
	RarestCollection = "Abyssara_LB_Rarest_v1",
}

local WRITE_INTERVAL_SECONDS = 90
local WRITE_STAGGER_SECONDS = 0.25 -- Pause zwischen einzelnen SetAsync-Aufrufen innerhalb eines writeLoop-Ticks
local READ_INTERVAL_SECONDS = 5 * 60
local TOP_N = 50
local BOARD_TOP_N = 10 -- nur die Top 10 passen sinnvoll auf ein SurfaceGui-Panel
local BOARD_CYCLE_SECONDS = 10 -- Kategorie-Wechsel-Takt am Hub-Anzeigepanel

local STORE_RETRY_ATTEMPTS = 3
local STORE_RETRY_BASE_DELAY_SECONDS = 1.5

-- // Laufzeit-Zustand ----------------------------------------------------------

local orderedStores: { [Category]: OrderedDataStore } = {}
for _, category in ipairs(CATEGORIES) do
	orderedStores[category] = DataStoreService:GetOrderedDataStore(STORE_NAMES[category])
end

local dirtyPlayers: { [number]: boolean } = {}
local lastWrittenScore: { [number]: { [Category]: number } } = {}

type LeaderboardEntry = { Rank: number, UserId: number, Name: string, Score: number }
local cachedTop: { [Category]: { LeaderboardEntry } } = { Level = {}, TideCoins = {}, RarestCollection = {} }
local cachedUpdatedAt: { [Category]: number } = { Level = 0, TideCoins = 0, RarestCollection = 0 }

local nameCache: { [number]: string } = {}

-- // Hilfsfunktionen ------------------------------------------------------------

local function withRetry(description: string, fn: () -> any): (boolean, any)
	local lastErr: any = nil
	for attempt = 1, STORE_RETRY_ATTEMPTS do
		local ok, resultOrErr = pcall(fn)
		if ok then
			return true, resultOrErr
		end
		lastErr = resultOrErr
		if attempt < STORE_RETRY_ATTEMPTS then
			task.wait(STORE_RETRY_BASE_DELAY_SECONDS * attempt)
		end
	end
	warn(("[LeaderboardService] %s endgültig fehlgeschlagen: %s"):format(description, tostring(lastErr)))
	return false, nil
end

--- Punktwert "Seltenste Sammlung": Summe der Rarity-Indizes (siehe
--- Kopfkommentar) über das komplette Kreaturen-Inventar. Unbekannte
--- Rarity-Strings (z. B. künftige, hier noch nicht gelistete Stufen) zählen
--- defensiv mit Index 1 statt den Server abstürzen zu lassen.
local function computeRarestCollectionScore(player: Player): number
	local score = 0
	for _, creature in ipairs(PlayerDataService.GetCreatureInventory(player)) do
		local ok, index = pcall(GachaConfig.GetRarityIndex, creature.Rarity :: any)
		score += if ok then index else 1
	end
	return score
end

local function computeScores(player: Player): { [Category]: number }
	return {
		Level = PlayerDataService.GetLevel(player),
		TideCoins = PlayerDataService.GetLifetimeTideCoinsEarned(player),
		RarestCollection = computeRarestCollectionScore(player),
	}
end

local function resolveName(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and type(name) == "string" then name else ("Spieler_" .. tostring(userId))
	nameCache[userId] = resolved
	return resolved
end

-- // GameEvents-Abonnements (nur "dirty" markieren, siehe Kopfkommentar) ------

local function markDirty(player: Player)
	dirtyPlayers[player.UserId] = true
end

GameEvents.Connect(GameEvents.Events.CoinsEarned, function(player: Player) markDirty(player) end)
GameEvents.Connect(GameEvents.Events.EggOpened, function(player: Player) markDirty(player) end)
GameEvents.Connect(GameEvents.Events.BreedingCompleted, function(player: Player) markDirty(player) end)
GameEvents.Connect(GameEvents.Events.RaidWon, function(player: Player) markDirty(player) end)
GameEvents.Connect(GameEvents.Events.BuildingPlaced, function(player: Player) markDirty(player) end)

-- // Write-Loop (gedrosselt, siehe Kopfkommentar) ------------------------------

--- Schreibt `score` für `category`, ABER NUR falls er sich seit dem letzten
--- erfolgreichen Write geändert hat (Budget sparen). Gibt true zurück, wenn
--- der Datensatz danach garantiert aktuell ist (entweder weil ohnehin
--- unverändert, oder weil der Write erfolgreich war) - false, falls ein Write
--- NÖTIG war, aber fehlgeschlagen ist (Aufrufer sollte den Spieler dann
--- weiterhin als "dirty" führen, siehe runWriteLoop).
local function writeScoreIfChanged(player: Player, category: Category, score: number): boolean
	local userId = player.UserId
	lastWrittenScore[userId] = lastWrittenScore[userId] or {}
	if lastWrittenScore[userId][category] == score then
		return true -- unverändert seit letztem erfolgreichen Write - Budget sparen
	end

	local ok = withRetry(
		("Write %s für UserId %d"):format(category, userId),
		function()
			orderedStores[category]:SetAsync(tostring(userId), score)
			return true
		end
	)

	if ok then
		lastWrittenScore[userId][category] = score
	end

	task.wait(WRITE_STAGGER_SECONDS)
	return ok
end

local function runWriteLoop()
	while true do
		task.wait(WRITE_INTERVAL_SECONDS)

		for userId in pairs(dirtyPlayers) do
			local player = Players:GetPlayerByUserId(userId)
			if not player or not PlayerDataService.IsDataLoaded(player) then
				-- Nicht mehr online/geladen - Dirty-Flag verwerfen (beim
				-- nächsten Login/Ereignis wird er ohnehin erneut markiert).
				dirtyPlayers[userId] = nil
				continue
			end

			local scores = computeScores(player)
			local allOk = true
			for _, category in ipairs(CATEGORIES) do
				local ok = writeScoreIfChanged(player, category, scores[category])
				allOk = allOk and ok
			end

			-- Dirty-Flag NUR löschen, wenn ALLE 3 Kategorien garantiert aktuell
			-- sind - ein fehlgeschlagener Write hält den Spieler bis zum
			-- nächsten Tick weiterhin "dirty" (siehe Funktionskommentar oben).
			if allOk then
				dirtyPlayers[userId] = nil
			end
		end
	end
end

-- // Read-Loop (Top 50, siehe Kopfkommentar) -----------------------------------

local function readCategoryTop(category: Category)
	local ok, pages = withRetry(("Read Top-%d %s"):format(TOP_N, category), function()
		return orderedStores[category]:GetSortedAsync(false, TOP_N)
	end)

	if not ok or not pages then
		return
	end

	local okPage, page = pcall(function()
		return (pages :: DataStorePages):GetCurrentPage()
	end)
	if not okPage then
		warn(("[LeaderboardService] GetCurrentPage() für %s fehlgeschlagen."):format(category))
		return
	end

	local entries: { LeaderboardEntry } = {}
	for rank, item in ipairs(page) do
		local userId = tonumber(item.key)
		if userId then
			table.insert(entries, {
				Rank = rank,
				UserId = userId,
				Name = resolveName(userId),
				Score = item.value,
			})
		end
	end

	cachedTop[category] = entries
	cachedUpdatedAt[category] = os.time()
end

local function runReadLoop()
	while true do
		for _, category in ipairs(CATEGORIES) do
			readCategoryTop(category)
			task.wait(1) -- kleine Pause zwischen den 3 Kategorien-Reads (Lesebudget)
		end
		task.wait(READ_INTERVAL_SECONDS)
	end
end

-- // Hub-SurfaceGui-Befüllung (LeaderboardBoard/DisplayPanel) -----------------

local CATEGORY_LABELS: { [Category]: string } = {
	Level = "Höchstes Level",
	TideCoins = "Gesamt verdiente Tide Coins",
	RarestCollection = "Seltenste Sammlung",
}

local function findLeaderboardDisplayPanel(): BasePart?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local hubFolder = assetsFolder and assetsFolder:FindFirstChild("Hub")
	local hubModel = hubFolder and hubFolder:FindFirstChild("TidalMarketHub")
	if not hubModel then
		return nil
	end

	local board = hubModel:FindFirstChild("LeaderboardBoard", true)
	if not board then
		return nil
	end

	local panel = board:FindFirstChild("DisplayPanel")
	if panel and panel:IsA("BasePart") then
		return panel
	end
	return nil
end

local function buildBoardGui(panel: BasePart): (ScreenGui | SurfaceGui, TextLabel, Frame)
	local existing = panel:FindFirstChild("LeaderboardSurfaceGui")
	if existing then
		existing:Destroy()
	end

	local gui = Instance.new("SurfaceGui")
	gui.Name = "LeaderboardSurfaceGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 36
	gui.LightInfluence = 0
	gui.Parent = panel

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0.12, 0)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBold
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(210, 245, 255)
	title.Text = "Rangliste"
	title.Parent = gui

	local list = Instance.new("Frame")
	list.Name = "EntryList"
	list.Size = UDim2.new(1, 0, 0.88, 0)
	list.Position = UDim2.new(0, 0, 0.12, 0)
	list.BackgroundTransparency = 1
	list.Parent = gui

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	return gui, title, list
end

local function renderBoard(title: TextLabel, list: Frame, category: Category)
	title.Text = ("Rangliste: %s"):format(CATEGORY_LABELS[category])

	list:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	local entries = cachedTop[category]
	if #entries == 0 then
		local placeholder = Instance.new("TextLabel")
		placeholder.Size = UDim2.new(1, 0, 0, 40)
		placeholder.BackgroundTransparency = 1
		placeholder.Font = Enum.Font.Gotham
		placeholder.TextScaled = true
		placeholder.TextColor3 = Color3.fromRGB(180, 200, 210)
		placeholder.Text = "Noch keine Daten..."
		placeholder.Parent = list
		return
	end

	for i = 1, math.min(BOARD_TOP_N, #entries) do
		local entry = entries[i]
		local row = Instance.new("TextLabel")
		row.Name = "Row" .. i
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 34)
		row.BackgroundTransparency = 1
		row.Font = Enum.Font.Gotham
		row.TextScaled = true
		row.TextXAlignment = Enum.TextXAlignment.Left
		row.TextColor3 = if i <= 3 then Color3.fromRGB(255, 225, 130) else Color3.fromRGB(220, 235, 240)
		row.Text = ("#%d  %s  -  %s"):format(entry.Rank, entry.Name, tostring(entry.Score))
		row.Parent = list
	end
end

local function runBoardLoop()
	local waited = 0
	local panel: BasePart? = nil
	while waited < 30 do
		panel = findLeaderboardDisplayPanel()
		if panel then
			break
		end
		task.wait(2)
		waited += 2
	end

	if not panel then
		warn(
			"[LeaderboardService] Workspace...Hub.TidalMarketHub.LeaderboardBoard.DisplayPanel nicht gefunden - "
				.. "Welt-Anzeigepanel wird übersprungen (siehe assets/models/hub/TidalMarketHub.lua, muss einmal "
				.. "in Studio ausgeführt worden sein)."
		)
		return
	end

	local _, title, list = buildBoardGui(panel)

	local categoryIndex = 1
	while true do
		renderBoard(title, list, CATEGORIES[categoryIndex])
		task.wait(BOARD_CYCLE_SECONDS)
		categoryIndex = (categoryIndex % #CATEGORIES) + 1
	end
end

-- // Öffentliche API --------------------------------------------------------

--- Liefert die zuletzt gelesene Top-50-Momentaufnahme (siehe
--- LeaderboardRemotes.GetLeaderboard) - KEIN Live-Read pro Anfrage.
function LeaderboardService.GetLeaderboard(category: any): { [string]: any }?
	if type(category) ~= "string" or not cachedTop[category :: Category] then
		return nil
	end
	local cat = category :: Category
	return {
		Category = cat,
		Entries = cachedTop[cat],
		UpdatedAt = cachedUpdatedAt[cat],
	}
end

-- // Bootstrap ------------------------------------------------------------------

local function onPlayerRemoving(player: Player)
	dirtyPlayers[player.UserId] = nil
	lastWrittenScore[player.UserId] = nil
end
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Ein frisch geladener Spieler ist grundsätzlich sofort relevant (erster
-- Write im nächsten regulären Tick, kein Sofort-Write nötig).
local function onPlayerAdded(player: Player)
	local data = PlayerDataService.WaitForData(player, 15)
	if not data then
		return
	end
	if not Players:GetPlayerByUserId(player.UserId) then
		return
	end
	markDirty(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
for _, existingPlayer in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, existingPlayer)
end

task.spawn(runWriteLoop)
task.spawn(runReadLoop)
task.spawn(runBoardLoop)

return LeaderboardService
