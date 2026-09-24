--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: LeaderboardUIController (LocalScript)
	Zuständigkeit:
		UI für das globale Ranglisten-System (`docs/server-features.md`
		Abschnitt 3.3, `LeaderboardRemotes.GetLeaderboard`). Drei Kategorie-
		Tabs (Level, Tide Coins, Seltenste Sammlung), Top-50 scrollbar, eigene
		Position hervorgehoben, sofern in Top 50 vertreten. Avatar-Thumbnails
		über `Players:GetUserThumbnailAsync` (immer in `pcall`, Ergebnis pro
		UserId gecacht, damit ein erneuter Tab-Wechsel nicht dieselben Bilder
		nochmal anfragt).

		WICHTIG: reine Anzeige. Rang/Score kommen 1:1 vom Server (bereits
		periodisch aktualisierte Momentaufnahme, siehe `LeaderboardService`
		Kopfkommentar - kein Live-DataStore-Read pro Anfrage nötig, daher
		unbedenklich bei jedem Tab-Wechsel neu abzufragen).

		HARTE UIKit-REGEL (docs/ui-kit.md): jeder Button ausschließlich über
		UIKit.Button.new(...).

		Öffnen: Bridge-BindableEvent "OpenLeaderboard" unter
		ReplicatedStorage.AbyssaraUIBridge (siehe MainMenuController-Eintrag
		"Rangliste"). Zusätzlich existiert bereits eine serverseitig befüllte
		SurfaceGui am Hub-Objekt LeaderboardBoard/DisplayPanel (siehe
		docs/server-features.md 3.3) - dieses Panel hier ist das optionale,
		vollständige Top-50-UI dazu, kein Duplikat (die SurfaceGui zeigt nur
		eine zyklische Kurzansicht am Hub-Objekt selbst).

	Rojo-Einhängepunkt:
		src/client/LeaderboardUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.LeaderboardUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LeaderboardRemotes = require(ReplicatedStorage:WaitForChild("LeaderboardRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Panel = UIKit.Panel
local Tabs = UIKit.Tabs
local Button = UIKit.Button
local Toast = UIKit.Toast
local CountUp = UIKit.CountUp

local localPlayer = Players.LocalPlayer

-- // Bridge ------------------------------------------------------------------------

local function getOrCreateBridgeEvent(eventName: string): BindableEvent
	local bridge = ReplicatedStorage:FindFirstChild("AbyssaraUIBridge")
	if not bridge then
		bridge = Instance.new("Folder")
		bridge.Name = "AbyssaraUIBridge"
		bridge.Parent = ReplicatedStorage
	end
	local event = bridge:FindFirstChild(eventName)
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = eventName
		event.Parent = bridge
	end
	return event :: BindableEvent
end

local openLeaderboardEvent = getOrCreateBridgeEvent("OpenLeaderboard")

-- // Kategorien ---------------------------------------------------------------------

type CategoryId = "Level" | "TideCoins" | "RarestCollection"

local CATEGORY_GLYPH: { [CategoryId]: string } = {
	Level = "⭐",
	TideCoins = "🪙",
	RarestCollection = "🐚",
}

local CATEGORY_COLOR: { [CategoryId]: Color3 } = {
	Level = Theme.Neon.Cyan,
	TideCoins = Theme.Neon.Yellow,
	RarestCollection = Theme.Neon.Magenta,
}

local CATEGORY_ORDER: { CategoryId } = { "Level", "TideCoins", "RarestCollection" }

-- // Avatar-Thumbnail-Cache (pro Session, pro UserId) --------------------------------

local thumbnailCache: { [number]: string } = {}
local thumbnailInFlight: { [number]: boolean } = {}

local function fetchThumbnail(userId: number, onReady: (content: string) -> ())
	local cached = thumbnailCache[userId]
	if cached then
		onReady(cached)
		return
	end
	if thumbnailInFlight[userId] then
		return
	end
	thumbnailInFlight[userId] = true
	task.spawn(function()
		local ok, content = pcall(function()
			local image = Players:GetUserThumbnailAsync(
				userId,
				Enum.ThumbnailType.HeadShot,
				Enum.ThumbnailSize.Size100x100
			)
			return image
		end)
		thumbnailInFlight[userId] = false
		if ok and type(content) == "string" then
			thumbnailCache[userId] = content
			onReady(content)
		end
	end)
end

-- // Kleine Label-Fabrik -----------------------------------------------------------

local function makeLabel(props: {
	Parent: Instance,
	Text: string,
	Size: UDim2,
	Position: UDim2?,
	Font: Enum.Font?,
	Color: Color3?,
	MinSize: number?,
	MaxSize: number?,
	XAlign: Enum.TextXAlignment?,
}): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = props.Size
	label.Position = props.Position or UDim2.fromOffset(0, 0)
	label.Font = props.Font or Theme.Font.Body
	label.TextColor3 = props.Color or Theme.Text.Primary
	label.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
	label.TextScaled = true
	label.Text = props.Text
	label.Parent = props.Parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = props.MinSize or 11
	constraint.MaxTextSize = props.MaxSize or 18
	constraint.Parent = label
	return label
end

-- // Zeilen-Aufbau -------------------------------------------------------------------

type LeaderboardEntry = { Rank: number, UserId: number, Name: string, Score: number }

local function buildRow(parent: Instance, entry: LeaderboardEntry, categoryColor: Color3, isSelf: boolean): Frame
	local row = Instance.new("Frame")
	row.Name = "Row_" .. tostring(entry.Rank)
	row.BackgroundColor3 = if isSelf then Theme.Background.PanelLight else Theme.Background.Panel
	row.Size = UDim2.new(1, 0, 0, 52)
	row.LayoutOrder = entry.Rank
	Theme.ApplyCorner(row, UDim.new(0, 12))
	local strokeColor = if isSelf then categoryColor else Theme.Background.Divider
	local strokeThickness = if isSelf then 2.5 else 1
	local stroke = Theme.ApplyStroke(row, strokeColor, strokeThickness)
	stroke.Transparency = if isSelf then 0 else 0.5
	row.Parent = parent

	local rankColor = Theme.Text.Secondary
	if entry.Rank == 1 then
		rankColor = Theme.Neon.Yellow
	elseif entry.Rank == 2 then
		rankColor = Theme.Text.Primary
	elseif entry.Rank == 3 then
		rankColor = Theme.Neon.Orange
	end
	local rankLabel = makeLabel({
		Parent = row,
		Text = "#" .. entry.Rank,
		Size = UDim2.fromOffset(44, 52),
		Position = UDim2.fromOffset(6, 0),
		Font = Theme.Font.Header,
		Color = rankColor,
		MinSize = 12,
		MaxSize = 18,
		XAlign = Enum.TextXAlignment.Center,
	})
	rankLabel.Name = "Rank"

	local avatar = Instance.new("ImageLabel")
	avatar.Name = "Avatar"
	avatar.BackgroundColor3 = Theme.Background.Deepest
	avatar.Size = UDim2.fromOffset(40, 40)
	avatar.Position = UDim2.fromOffset(54, 6)
	avatar.Image = ""
	avatar.Parent = row
	Theme.ApplyCorner(avatar, UDim.new(1, 0))
	Theme.ApplyStroke(avatar, categoryColor, 1.5)
	fetchThumbnail(entry.UserId, function(content: string)
		if avatar.Parent then
			avatar.Image = content
		end
	end)

	local nameLabel = makeLabel({
		Parent = row,
		Text = entry.Name .. (isSelf and "  (Du)" or ""),
		Size = UDim2.new(1, -240, 0, 24),
		Position = UDim2.fromOffset(102, 6),
		Font = Theme.Font.BodyBold,
		Color = if isSelf then categoryColor else Theme.Text.Primary,
		MinSize = 12,
		MaxSize = 16,
	})
	nameLabel.Name = "Name"

	local scoreLabel = makeLabel({
		Parent = row,
		Text = CountUp.DefaultFormat(entry.Score),
		Size = UDim2.new(0, 100, 0, 40),
		Position = UDim2.new(1, -106, 0, 6),
		Font = Theme.Font.Header,
		Color = categoryColor,
		MinSize = 13,
		MaxSize = 20,
		XAlign = Enum.TextXAlignment.Right,
	})
	scoreLabel.Name = "Score"

	return row
end

-- // Panel-Aufbau ---------------------------------------------------------------

local panelHandle: any = nil
local tabsHandle: any = nil
local currentCategory: CategoryId = "Level"
local loadedCategories: { [CategoryId]: boolean } = {}
local categoryHosts: { [CategoryId]: Frame } = {}
local statusLabels: { [CategoryId]: TextLabel } = {}

local function clearCategoryHost(category: CategoryId)
	local host = categoryHosts[category]
	if not host then
		return
	end
	-- `host` (die "Rows"-Frame) enthält ausschließlich Zeilen (Frame) und
	-- ggf. den "Noch nicht in Top 50"-Hinweis (TextLabel) - beide sollen bei
	-- jedem Neuladen restlos verschwinden, daher unbedingt alle Kinder
	-- entfernen (kein UIListLayout o.ä. als Geschwister vorhanden, das
	-- erhalten bleiben müsste).
	for _, child in ipairs(host:GetChildren()) do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
end

local function loadCategory(category: CategoryId, forceRefresh: boolean)
	if not forceRefresh and loadedCategories[category] then
		return
	end
	local status = statusLabels[category]
	if status then
		status.Text = "Lädt Rangliste…"
		status.Visible = true
	end

	task.spawn(function()
		local ok, result = pcall(function()
			return LeaderboardRemotes.GetLeaderboard:InvokeServer(category)
		end)

		if not ok or type(result) ~= "table" or type(result.Entries) ~= "table" then
			if status then
				status.Text = "Rangliste noch nicht verfügbar – bitte später erneut versuchen."
				status.Visible = true
			end
			Toast.Show({ Text = "Rangliste konnte nicht geladen werden.", Type = "Warning", Duration = 3 })
			return
		end

		loadedCategories[category] = true
		clearCategoryHost(category)
		local host = categoryHosts[category]
		if not host then
			return
		end

		local entries = result.Entries :: { LeaderboardEntry }
		if #entries == 0 then
			if status then
				status.Text = "Noch keine Einträge – sei der/die Erste!"
				status.Visible = true
			end
			return
		end

		if status then
			status.Visible = false
		end

		local color = CATEGORY_COLOR[category]
		local foundSelf = false
		for _, entry in ipairs(entries) do
			local isSelf = entry.UserId == localPlayer.UserId
			if isSelf then
				foundSelf = true
			end
			buildRow(host, entry, color, isSelf)
		end

		if not foundSelf then
			local hint = makeLabel({
				Parent = host,
				Text = "Du bist noch nicht in den Top 50 dieser Kategorie – weiter sammeln!",
				Size = UDim2.new(1, 0, 0, 28),
				Color = Theme.Text.Muted,
				MinSize = 10,
				MaxSize = 14,
			})
			hint.LayoutOrder = 999
		end
	end)
end

local function buildPanel()
	if panelHandle then
		return
	end

	panelHandle = Panel.new({
		Title = "Rangliste",
		Closable = true,
		CenteredSize = UDim2.fromOffset(680, 700),
	})

	tabsHandle = Tabs.new({
		Parent = panelHandle.Content,
		Tabs = {
			{ Id = "Level", Label = CATEGORY_GLYPH.Level .. " Level" },
			{ Id = "TideCoins", Label = CATEGORY_GLYPH.TideCoins .. " Tide Coins" },
			{ Id = "RarestCollection", Label = CATEGORY_GLYPH.RarestCollection .. " Sammlung" },
		},
		DefaultTabId = "Level",
	})

	for _, category in ipairs(CATEGORY_ORDER) do
		local content = tabsHandle:GetContentFrame(category)

		local host = Instance.new("Frame")
		host.Name = "Rows"
		host.BackgroundTransparency = 1
		host.AutomaticSize = Enum.AutomaticSize.Y
		host.Size = UDim2.new(1, 0, 0, 0)
		host.Parent = content
		local hostList = Instance.new("UIListLayout")
		hostList.SortOrder = Enum.SortOrder.LayoutOrder
		hostList.Padding = UDim.new(0, 6)
		hostList.Parent = host
		categoryHosts[category] = host

		local status = makeLabel({
			Parent = content,
			Text = "Lädt Rangliste…",
			Size = UDim2.new(1, 0, 0, 30),
			Color = Theme.Text.Muted,
			MinSize = 11,
			MaxSize = 15,
		})
		status.LayoutOrder = -1
		statusLabels[category] = status
	end

	tabsHandle.Selected:Connect(function(id: string)
		currentCategory = id :: CategoryId
		loadCategory(currentCategory, false)
	end)

	loadCategory("Level", false)
end

-- Beim (Wieder-)Öffnen des Panels die aktuell sichtbare Kategorie zwangs-
-- weise neu laden (der Server-Cache selbst ist bereits gedrosselt, siehe
-- Kopfkommentar - ein erneuter Client-Aufruf pro Öffnen ist unbedenklich).
local function openLeaderboard()
	buildPanel()
	panelHandle:Open()
	if tabsHandle then
		loadCategory(currentCategory, true)
	end
end

local bridgeConnection = openLeaderboardEvent.Event:Connect(openLeaderboard)

-- // Aufräumen ------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	bridgeConnection:Disconnect()
	if tabsHandle then
		tabsHandle:Destroy()
	end
	if panelHandle then
		panelHandle:Destroy()
	end
end)
