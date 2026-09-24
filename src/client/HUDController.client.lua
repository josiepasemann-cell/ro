--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: HUDController (LocalScript)
	Zuständigkeit:
		Zentrales HUD (GDD Abschnitt 9, Punkt 13: "HUD (Währung,
		XP-Leiste)"): eine einzelne, dauerhaft sichtbare Leiste mit
			- Tide Coins, Abyssal Shards (aktueller Kontostand, per
			  UIKit.CountUp animiert hoch-/runtergezählt),
			- Level + XP-Leiste (UIKit.ProgressBar, Fortschritt zum
			  nächsten Level),
			- Einkommen/Minute (aktuelle Tide-Coin-Produktion).
		Zusätzlich ein Level-Up-Banner (zentriert, wenige Sekunden
		sichtbar, mit UIKit.ScreenFX.BigMoment) mit den durch den Level-Up
		neu freigeschalteten Dingen (ProgressionConfig.UNLOCKS).

		WICHTIG: Dieses Skript berechnet NIEMALS selbst einen Währungs-,
		Level- oder XP-Wert - es zeigt ausschließlich an, was der Server über
		HUDRemotes.GetHUDState (initialer Sync) bzw. HUDRemotes.
		HUDStateChanged (Live-Push bei jeder Änderung) bereits fertig
		berechnet mitschickt (kein Client-Trust: PlayerDataService/
		ProgressionService/IdleIncomeService bleiben alleinige Autorität).

		LAYOUT (Gesamt-Übersicht, geprüft gegen alle Client-UIs):
			- Phone (Hochkant/Querformat): Diese HUD-Leiste ist eine volle
			  Breite als dünner Streifen ganz oben (Safe-Area-sicher über
			  UIKit.Device.ApplySafeArea). RaidUIController dockt seine
			  Status-Leiste direkt DARUNTER an (ebenfalls volle Breite,
			  siehe dort). MainMenuController dockt UNTEN an (volle
			  Breite). HeldItemClient/IdleIncomeClient-Popups docken
			  UNTEN-MITTIG an, aber deutlich über der Menüleiste (siehe
			  dort für die genauen Offsets). Damit gibt es auf Phone KEINE
			  horizontale Überlappung mehr (die alte Version hatte HUD
			  oben-links + RaidUI oben-mittig nebeneinander, was auf
			  schmalen Phones kollidieren konnte).
			- Tablet/PC/Konsole: HUD bleibt oben LINKS (kompakte Box,
			  x=16, y=16), RaidUIController bleibt oben MITTIG, genug
			  horizontaler Abstand vorhanden. MainMenuController dockt
			  unten mittig an.

	Rojo-Einhängepunkt:
		src/client/HUDController.client.lua ->
		StarterPlayer.StarterPlayerScripts.HUDController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local HUDRemotes = require(ReplicatedStorage:WaitForChild("HUDRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local ProgressBar = UIKit.ProgressBar
local CountUp = UIKit.CountUp
local ScreenFX = UIKit.ScreenFX

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
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 15
Device.ApplySafeArea(screenGui)
screenGui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = screenGui
local unbindScale = Device.BindUIScale(uiScale)

-- // Haupt-Leiste ---------------------------------------------------------------

local bar = Instance.new("Frame")
bar.Name = "HUDBar"
bar.BackgroundColor3 = Theme.Background.Panel
bar.BackgroundTransparency = 0.1
bar.Parent = screenGui
Theme.ApplyCorner(bar, UDim.new(0, 14))
local barStroke = Theme.ApplyStroke(bar, Theme.Neon.Cyan, 1.5)
barStroke.Transparency = 0.25

local function applyBarLayout()
	if Device.ShouldUseFullscreenPanels() then
		bar.AnchorPoint = Vector2.new(0.5, 0)
		bar.Position = UDim2.new(0.5, 0, 0, 8)
		bar.Size = UDim2.new(1, -16, 0, 96)
	else
		bar.AnchorPoint = Vector2.new(0, 0)
		bar.Position = UDim2.new(0, 16, 0, 16)
		bar.Size = UDim2.fromOffset(380, 96)
	end
end
applyBarLayout()
local barDeviceConnection = Device.Changed:Connect(applyBarLayout)

-- // Zeile 1: Währungen ----------------------------------------------------------

local tideCoinsLabel = Instance.new("TextLabel")
tideCoinsLabel.Name = "TideCoinsLabel"
tideCoinsLabel.Size = UDim2.new(0.5, -6, 0, 26)
tideCoinsLabel.Position = UDim2.new(0, 12, 0, 8)
tideCoinsLabel.BackgroundTransparency = 1
tideCoinsLabel.Font = Theme.Font.BodyBold
tideCoinsLabel.TextScaled = true
tideCoinsLabel.TextXAlignment = Enum.TextXAlignment.Left
tideCoinsLabel.TextColor3 = Theme.Neon.ToxicGreen
tideCoinsLabel.Text = "🌊 0"
tideCoinsLabel.Parent = bar
Theme.ApplyStroke(tideCoinsLabel, Theme.Text.Stroke, 1)
local tideConstraint = Instance.new("UITextSizeConstraint")
tideConstraint.MinTextSize = 13
tideConstraint.MaxTextSize = 18
tideConstraint.Parent = tideCoinsLabel

local abyssalShardsLabel = Instance.new("TextLabel")
abyssalShardsLabel.Name = "AbyssalShardsLabel"
abyssalShardsLabel.Size = UDim2.new(0.5, -6, 0, 26)
abyssalShardsLabel.Position = UDim2.new(0.5, -6, 0, 8)
abyssalShardsLabel.BackgroundTransparency = 1
abyssalShardsLabel.Font = Theme.Font.BodyBold
abyssalShardsLabel.TextScaled = true
abyssalShardsLabel.TextXAlignment = Enum.TextXAlignment.Left
abyssalShardsLabel.TextColor3 = Theme.Neon.Violet
abyssalShardsLabel.Text = "💎 0"
abyssalShardsLabel.Parent = bar
Theme.ApplyStroke(abyssalShardsLabel, Theme.Text.Stroke, 1)
local shardConstraint = Instance.new("UITextSizeConstraint")
shardConstraint.MinTextSize = 13
shardConstraint.MaxTextSize = 18
shardConstraint.Parent = abyssalShardsLabel

-- // Zeile 2: Einkommen/Minute ----------------------------------------------------

local incomeLabel = Instance.new("TextLabel")
incomeLabel.Name = "IncomeLabel"
incomeLabel.Size = UDim2.new(1, -24, 0, 18)
incomeLabel.Position = UDim2.new(0, 12, 0, 34)
incomeLabel.BackgroundTransparency = 1
incomeLabel.Font = Theme.Font.Body
incomeLabel.TextScaled = true
incomeLabel.TextXAlignment = Enum.TextXAlignment.Left
incomeLabel.TextColor3 = Theme.Text.Secondary
incomeLabel.Text = "+0 Tide Coins / Min"
incomeLabel.Parent = bar
local incomeConstraint = Instance.new("UITextSizeConstraint")
incomeConstraint.MinTextSize = 10
incomeConstraint.MaxTextSize = 14
incomeConstraint.Parent = incomeLabel

-- // Zeile 3: Level + XP-Leiste ----------------------------------------------------

local levelLabel = Instance.new("TextLabel")
levelLabel.Name = "LevelLabel"
levelLabel.Size = UDim2.new(1, -24, 0, 16)
levelLabel.Position = UDim2.new(0, 12, 0, 56)
levelLabel.BackgroundTransparency = 1
levelLabel.Font = Theme.Font.BodyBold
levelLabel.TextScaled = true
levelLabel.TextXAlignment = Enum.TextXAlignment.Left
levelLabel.TextColor3 = Theme.Text.Primary
levelLabel.Text = "Level 1"
levelLabel.Parent = bar
local levelConstraint = Instance.new("UITextSizeConstraint")
levelConstraint.MinTextSize = 10
levelConstraint.MaxTextSize = 14
levelConstraint.Parent = levelLabel

local xpBarHost = Instance.new("Frame")
xpBarHost.Name = "XPBarHost"
xpBarHost.BackgroundTransparency = 1
xpBarHost.Position = UDim2.new(0, 12, 1, -22)
xpBarHost.Size = UDim2.new(1, -24, 0, 12)
xpBarHost.Parent = bar
local xpBar = ProgressBar.new({
	Parent = xpBarHost,
	Size = UDim2.new(1, 0, 1, 0),
	Colors = { Theme.Neon.Yellow, Theme.Neon.Orange },
})

-- // Anzeige-Refresh (rein kosmetisch, rechnet nichts selbst) ---------------------

local function formatNumber(value: number): string
	return CountUp.DefaultFormat(value)
end

local lastTideCoins = 0
local lastAbyssalShards = 0

local function refreshDisplay()
	if state.TideCoins ~= lastTideCoins then
		CountUp.Animate(tideCoinsLabel, lastTideCoins, state.TideCoins, 0.6, function(value)
			return ("🌊 %s"):format(formatNumber(value))
		end)
		lastTideCoins = state.TideCoins
	end
	if state.AbyssalShards ~= lastAbyssalShards then
		CountUp.Animate(abyssalShardsLabel, lastAbyssalShards, state.AbyssalShards, 0.6, function(value)
			return ("💎 %s"):format(formatNumber(value))
		end)
		lastAbyssalShards = state.AbyssalShards
	end
	incomeLabel.Text = ("+%s Tide Coins / Min"):format(formatNumber(state.IncomePerMinute))

	if state.Level >= state.MaxLevel then
		levelLabel.Text = ("Level %d (Max)"):format(state.Level)
		xpBar:SetProgress(1)
		return
	end

	levelLabel.Text = ("Level %d"):format(state.Level)

	local ratio = 0
	if state.XPToNextLevel > 0 then
		ratio = math.clamp(state.XPIntoLevel / state.XPToNextLevel, 0, 1)
	end
	xpBar:SetProgress(ratio)
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
bannerGui.IgnoreGuiInset = false
bannerGui.DisplayOrder = 60
bannerGui.Parent = playerGui

local bannerUiScale = Instance.new("UIScale")
bannerUiScale.Parent = bannerGui
local unbindBannerScale = Device.BindUIScale(bannerUiScale)

local banner = Instance.new("Frame")
banner.Name = "Banner"
banner.AnchorPoint = Vector2.new(0.5, 0)
banner.Position = UDim2.new(0.5, 0, 0.16, 0)
banner.Size = UDim2.fromOffset(420, 0) -- Höhe wird dynamisch je nach Anzahl Unlocks gesetzt
banner.AutomaticSize = Enum.AutomaticSize.Y
banner.BackgroundColor3 = Theme.Background.Panel
banner.BackgroundTransparency = 0.05
banner.Visible = false
banner.Parent = bannerGui
Theme.ApplyCorner(banner, UDim.new(0, 16))
local bannerStroke = Theme.ApplyStroke(banner, Theme.Neon.Yellow, 2)
Theme.ApplyGradient(banner, { Theme.Background.Panel, Theme.Background.Deepest }, 90)

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
bannerTitle.Font = Theme.Font.Header
bannerTitle.TextScaled = true
bannerTitle.TextColor3 = Theme.Neon.Yellow
bannerTitle.LayoutOrder = 1
bannerTitle.Text = "Level Up!"
bannerTitle.Parent = banner
local bannerTitleConstraint = Instance.new("UITextSizeConstraint")
bannerTitleConstraint.MinTextSize = 18
bannerTitleConstraint.MaxTextSize = 28
bannerTitleConstraint.Parent = bannerTitle

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

	bannerTitle.Text = ("Level Up! Now Level %d"):format(newLevel)

	if #unlocks == 0 then
		local line = Instance.new("TextLabel")
		line.Name = "UnlockLine"
		line.Size = UDim2.new(1, 0, 0, 22)
		line.BackgroundTransparency = 1
		line.Font = Theme.Font.Body
		line.TextScaled = true
		line.TextColor3 = Theme.Text.Primary
		line.LayoutOrder = 2
		line.Text = "Keep it up!"
		line.Parent = banner
	else
		for index, unlock in ipairs(unlocks) do
			local line = Instance.new("TextLabel")
			line.Name = "UnlockLine"
			line.Size = UDim2.new(1, 0, 0, 22)
			line.BackgroundTransparency = 1
			line.Font = Theme.Font.Body
			line.TextScaled = true
			line.TextColor3 = if unlock.Implemented then Theme.Text.Primary else Theme.Text.Muted
			line.LayoutOrder = index + 1
			line.Text = ("✓ %s"):format(unlock.Label)
			line.Parent = banner
		end
	end

	banner.Visible = true
	banner.BackgroundTransparency = 0.05
	bannerStroke.Transparency = 0

	ScreenFX.BigMoment(Theme.Neon.Yellow)

	if bannerHideThread then
		task.cancel(bannerHideThread)
	end
	bannerHideThread = task.delay(BANNER_VISIBLE_SECONDS, function()
		bannerHideThread = nil
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
		warn("[HUDController] Initial HUD sync failed.")
		refreshDisplay()
	end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	barDeviceConnection:Disconnect()
	unbindScale()
	unbindBannerScale()
	if bannerHideThread then
		task.cancel(bannerHideThread)
	end
	screenGui:Destroy()
	bannerGui:Destroy()
end)
