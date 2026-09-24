--[[
	Abyssara – Deep Tide Tycoon
	Skript: HUDController (LocalScript)
	Zuständigkeit:
		Zentrales HUD des MVP (GDD Abschnitt 9, Punkt 13: "HUD (Währung,
		XP-Leiste)"): eine einzelne, dauerhaft sichtbare Leiste oben links mit
			- Tide Coins, Abyssal Shards (aktueller Kontostand),
			- Level + XP-Leiste (Fortschritt zum nächsten Level),
			- Einkommen/Minute (aktuelle Tide-Coin-Produktion, siehe
			  IdleIncomeService.GetIncomePerMinute).
		Zusätzlich ein kurzes Level-Up-Banner (zentriert, wenige Sekunden
		sichtbar), das die durch den Level-Up neu freigeschalteten Dinge
		auflistet (ProgressionConfig.UNLOCKS).

		WICHTIG: Dieses Skript berechnet NIEMALS selbst einen Währungs-,
		Level- oder XP-Wert - es zeigt ausschließlich an, was der Server über
		HUDRemotes.GetHUDState (initialer Sync) bzw. HUDRemotes.
		HUDStateChanged (Live-Push bei jeder Änderung) bereits fertig
		berechnet mitschickt (kein Client-Trust: PlayerDataService/
		ProgressionService/IdleIncomeService bleiben alleinige Autorität).

		Layout-Hinweis (Überlappungsvermeidung mit bestehenden Client-UIs):
		RaidUIController belegt bereits oben MITTIG (StatusBar, x zentriert,
		y=16..72) und oben RECHTS (RescueButtonFrame, y=16..)
		IdleIncomeClient belegt UNTEN mittig (Popups) und BILDSCHIRMMITTE
		(Offline-Summary). Dieses HUD platziert sich deshalb bewusst oben
		LINKS (x=16, y=16, Breite 380px) - überschneidungsfrei zu allen
		bestehenden Panels.

	Rojo-Einhängepunkt:
		src/client/HUDController.client.lua ->
		StarterPlayer.StarterPlayerScripts.HUDController
		(".client.lua"-Suffix signalisiert Rojo, hieraus ein `LocalScript`
		zu machen.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local HUDRemotes = require(ReplicatedStorage:WaitForChild("HUDRemotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- // Lokaler, rein kosmetischer Anzeige-Zustand (Server bleibt Autorität) -----

type HUDState = {
	TideCoins: number,
	AbyssalShards: number,
	Level: number,
	XP: number,
	XPIntoLevel: number,
	XPToNextLevel: number,
	IncomePerMinute: number,
	MaxLevel: number,
}

local state: HUDState = {
	TideCoins = 0,
	AbyssalShards = 0,
	Level = 1,
	XP = 0,
	XPIntoLevel = 0,
	XPToNextLevel = ProgressionConfig.GetXPToNextLevel(1) or 1,
	IncomePerMinute = 0,
	MaxLevel = ProgressionConfig.MAX_LEVEL,
}

-- // Root-ScreenGui ------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = playerGui

-- // Haupt-Leiste (oben links) --------------------------------------------------

local bar = Instance.new("Frame")
bar.Name = "HUDBar"
bar.AnchorPoint = Vector2.new(0, 0)
bar.Position = UDim2.new(0, 16, 0, 16)
bar.Size = UDim2.fromOffset(380, 96)
bar.BackgroundColor3 = Color3.fromRGB(10, 22, 30)
bar.BackgroundTransparency = 0.1
bar.Parent = screenGui

local barCorner = Instance.new("UICorner")
barCorner.CornerRadius = UDim.new(0, 14)
barCorner.Parent = bar

local barStroke = Instance.new("UIStroke")
barStroke.Color = Color3.fromRGB(70, 210, 235)
barStroke.Thickness = 1.5
barStroke.Parent = bar

-- // Zeile 1: Währungen ----------------------------------------------------------

local tideCoinsLabel = Instance.new("TextLabel")
tideCoinsLabel.Name = "TideCoinsLabel"
tideCoinsLabel.Size = UDim2.new(0.5, -6, 0, 26)
tideCoinsLabel.Position = UDim2.new(0, 12, 0, 8)
tideCoinsLabel.BackgroundTransparency = 1
tideCoinsLabel.Font = Enum.Font.GothamBold
tideCoinsLabel.TextSize = 17
tideCoinsLabel.TextXAlignment = Enum.TextXAlignment.Left
tideCoinsLabel.TextColor3 = Color3.fromRGB(120, 235, 210)
tideCoinsLabel.Text = "🌊 0"
tideCoinsLabel.Parent = bar

local abyssalShardsLabel = Instance.new("TextLabel")
abyssalShardsLabel.Name = "AbyssalShardsLabel"
abyssalShardsLabel.Size = UDim2.new(0.5, -6, 0, 26)
abyssalShardsLabel.Position = UDim2.new(0.5, -6, 0, 8)
abyssalShardsLabel.BackgroundTransparency = 1
abyssalShardsLabel.Font = Enum.Font.GothamBold
abyssalShardsLabel.TextSize = 17
abyssalShardsLabel.TextXAlignment = Enum.TextXAlignment.Left
abyssalShardsLabel.TextColor3 = Color3.fromRGB(200, 170, 255)
abyssalShardsLabel.Text = "💎 0"
abyssalShardsLabel.Parent = bar

-- // Zeile 2: Einkommen/Minute ----------------------------------------------------

local incomeLabel = Instance.new("TextLabel")
incomeLabel.Name = "IncomeLabel"
incomeLabel.Size = UDim2.new(1, -24, 0, 18)
incomeLabel.Position = UDim2.new(0, 12, 0, 34)
incomeLabel.BackgroundTransparency = 1
incomeLabel.Font = Enum.Font.GothamMedium
incomeLabel.TextSize = 13
incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
incomeLabel.TextColor3 = Color3.fromRGB(170, 200, 205)
incomeLabel.Text = "+0 Tide Coins / Min"
incomeLabel.Parent = bar

-- // Zeile 3: Level + XP-Leiste ----------------------------------------------------

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelLabel"
levelLabel.Size = UDim2.new(1, -24, 0, 16)
levelLabel.Position = UDim2.new(0, 12, 0, 56)
levelLabel.BackgroundTransparency = 1
levelLabel.Font = Enum.Font.GothamBold
levelLabel.TextSize = 13
levelLabel.TextXAlignment = Enum.TextXAlignment.Left
levelLabel.TextColor3 = Color3.fromRGB(230, 245, 250)
levelLabel.Text = "Level 1"
levelLabel.Parent = bar

local xpBarBackground = Instance.new("Frame")
xpBarBackground.Name = "XPBarBackground"
xpBarBackground.Size = UDim2.new(1, -24, 0, 12)
xpBarBackground.Position = UDim2.new(0, 12, 1, -22)
xpBarBackground.BackgroundColor3 = Color3.fromRGB(6, 14, 20)
xpBarBackground.BorderSizePixel = 0
xpBarBackground.Parent = bar

local xpBarBackgroundCorner = Instance.new("UICorner")
xpBarBackgroundCorner.CornerRadius = UDim.new(1, 0)
xpBarBackgroundCorner.Parent = xpBarBackground

local xpBarFill = Instance.new("Frame")
xpBarFill.Name = "XPBarFill"
xpBarFill.Size = UDim2.new(0, 0, 1, 0)
xpBarFill.BackgroundColor3 = Color3.fromRGB(255, 210, 90)
xpBarFill.BorderSizePixel = 0
xpBarFill.Parent = xpBarBackground

local xpBarFillCorner = Instance.new("UICorner")
xpBarFillCorner.CornerRadius = UDim.new(1, 0)
xpBarFillCorner.Parent = xpBarFill

-- // Anzeige-Refresh (rein kosmetisch, rechnet nichts selbst) ---------------------

local function formatNumber(value: number): string
	return tostring(math.floor(value + 0.5))
end

local function refreshDisplay()
	tideCoinsLabel.Text = ("🌊 %s"):format(formatNumber(state.TideCoins))
	abyssalShardsLabel.Text = ("💎 %s"):format(formatNumber(state.AbyssalShards))
	incomeLabel.Text = ("+%s Tide Coins / Min"):format(formatNumber(state.IncomePerMinute))

	if state.Level >= state.MaxLevel then
		levelLabel.Text = ("Level %d (Max)"):format(state.Level)
		xpBarFill.Size = UDim2.new(1, 0, 1, 0)
		return
	end

	levelLabel.Text = ("Level %d"):format(state.Level)

	local ratio = 0
	if state.XPToNextLevel > 0 then
		ratio = math.clamp(state.XPIntoLevel / state.XPToNextLevel, 0, 1)
	end

	local targetSize = UDim2.new(ratio, 0, 1, 0)
	local tween = TweenService:Create(xpBarFill, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = targetSize })
	tween:Play()
end

--- Merged einen partiellen HUDStateChanged-Push additiv in den lokalen
--- Zustand (nur tatsächlich mitgesendete Felder werden überschrieben) und
--- aktualisiert danach die Anzeige.
local function applyPartialState(payload: { [string]: any })
	for key, value in pairs(payload) do
		if state[key] ~= nil and type(value) == typeof(state[key]) then
			state[key] = value
		end
	end
	refreshDisplay()
end

-- // Level-Up-Banner (zentriert, wenige Sekunden sichtbar) -----------------------

local bannerGui = Instance.new("ScreenGui")
bannerGui.Name = "LevelUpBanner"
bannerGui.ResetOnSpawn = false
bannerGui.IgnoreGuiInset = true
bannerGui.Parent = playerGui

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.16, 0)
banner.Size = UDim2.fromOffset(420, 0) -- Höhe wird dynamisch je nach Anzahl Unlocks gesetzt
banner.AutomaticSize = Enum.AutomaticSize.Y
banner.BackgroundColor3 = Color3.fromRGB(8, 20, 16)
banner.BackgroundTransparency = 0.05
banner.Visible = false
banner.Parent = bannerGui

local bannerCorner = Instance.new("UICorner")
bannerCorner.CornerRadius = UDim.new(0, 16)
bannerCorner.Parent = banner

local bannerStroke = Instance.new("UIStroke")
bannerStroke.Color = Color3.fromRGB(255, 210, 90)
bannerStroke.Thickness = 2
bannerStroke.Parent = banner

local bannerLayout = Instance.new("UIListLayout")
bannerLayout.FillDirection = Enum.FillDirection.Vertical
bannerLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
bannerLayout.SortOrder = Enum.SortOrder.LayoutOrder
bannerLayout.Padding = UDim.new(0, 4)
bannerLayout.Parent = banner

local bannerPadding = Instance.new("UIPadding")
bannerPadding.PaddingTop = UDim.new(0, 14)
bannerPadding.PaddingBottom = UDim.new(0, 14)
bannerPadding.PaddingLeft = UDim.new(0, 16)
bannerPadding.PaddingRight = UDim.new(0, 16)
bannerPadding.Parent = banner

local bannerTitle = Instance.new("TextLabel")
bannerTitle.Name = "Title"
bannerTitle.Size = UDim2.new(1, 0, 0, 30)
bannerTitle.BackgroundTransparency = 1
bannerTitle.Font = Enum.Font.GothamBold
bannerTitle.TextSize = 24
bannerTitle.TextColor3 = Color3.fromRGB(255, 210, 90)
bannerTitle.LayoutOrder = 1
bannerTitle.Text = "Level Up!"
bannerTitle.Parent = banner

local BANNER_VISIBLE_SECONDS = 4.5
local bannerHideThread: thread? = nil

local function clearUnlockLabels()
	for _, child in ipairs(banner:GetChildren()) do
		if child:IsA("TextLabel") and child.Name == "UnlockLine" then
			child:Destroy()
		end
	end
end

local function showLevelUpBanner(newLevel: number, unlocks: { { Label: string, Implemented: boolean } })
	clearUnlockLabels()

	bannerTitle.Text = ("Level Up! Jetzt Level %d"):format(newLevel)

	if #unlocks == 0 then
		local line = Instance.new("TextLabel")
		line.Name = "UnlockLine"
		line.Size = UDim2.new(1, 0, 0, 22)
		line.BackgroundTransparency = 1
		line.Font = Enum.Font.GothamMedium
		line.TextSize = 15
		line.TextColor3 = Color3.fromRGB(210, 235, 240)
		line.LayoutOrder = 2
		line.Text = "Weiter so!"
		line.Parent = banner
	else
		for index, unlock in ipairs(unlocks) do
			local line = Instance.new("TextLabel")
			line.Name = "UnlockLine"
			line.Size = UDim2.new(1, 0, 0, 22)
			line.BackgroundTransparency = 1
			line.Font = Enum.Font.GothamMedium
			line.TextSize = 15
			line.TextColor3 = if unlock.Implemented
				then Color3.fromRGB(210, 235, 240)
				else Color3.fromRGB(150, 170, 175) -- gedämpft: Ankündigung, System folgt noch (z. B. Zonenportal)
			line.LayoutOrder = index + 1
			line.Text = ("✓ %s"):format(unlock.Label)
			line.Parent = banner
		end
	end

	banner.Visible = true
	banner.BackgroundTransparency = 0.05
	bannerStroke.Transparency = 0

	if bannerHideThread then
		task.cancel(bannerHideThread)
	end
	bannerHideThread = task.delay(BANNER_VISIBLE_SECONDS, function()
		banner.Visible = false
	end)
end

-- // Server-Events (Push) ---------------------------------------------------------

HUDRemotes.HUDStateChanged.OnClientEvent:Connect(applyPartialState)

HUDRemotes.LevelUp.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.NewLevel) ~= "number" then
		return
	end
	showLevelUpBanner(payload.NewLevel, payload.Unlocks or {})
end)

-- // Initialer Sync -----------------------------------------------------------------

task.spawn(function()
	local ok, initialState = pcall(function()
		return HUDRemotes.GetHUDState:InvokeServer()
	end)
	if ok and type(initialState) == "table" then
		applyPartialState(initialState)
	else
		warn("[HUDController] Initialer HUD-Sync fehlgeschlagen.")
		refreshDisplay()
	end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		screenGui:Destroy()
		bannerGui:Destroy()
	end
end)
