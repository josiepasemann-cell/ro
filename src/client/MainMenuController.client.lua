--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: MainMenuController (LocalScript)
	Zuständigkeit:
		Zentrale, dauerhaft sichtbare Menüleiste. Früher 12 Buttons in einer
		Reihe (auf Phones unbenutzbar), jetzt KOMPAKT: 4 Haupt-Aktionen
		immer sichtbar + ein "More"-Button, der eine Raster-Schublade (Drawer)
		mit den übrigen 8 Einträgen öffnet.

			Immer sichtbar:   Build · Shop · Quests (Badge) · Travel · More
			Schublade "More": Brood Pool · Mystery Egg · Abducted · Leaderboard
			                  · Codex · Achievements (Badge) · Event · Settings

		Kommunikation mit den anderen Controllern läuft bewusst NICHT über
		direkte Requires (Kreis-Abhängigkeiten zwischen gleichrangigen
		LocalScripts), sondern über BindableEvents unter
		ReplicatedStorage.AbyssaraUIBridge (getOrCreateBridgeEvent unten).
		Das verändert KEINE Datei unter src/shared, es werden nur zur Laufzeit
		Instanzen angelegt (kein Rojo-Mapping nötig).

		Geräte-Layout (Position aus UIKit.Layout.GetHudLayout().Menu):
			- Phone/Tablet hochkant: Leiste unter dem HUD, volle Breite.
			- Phone/Tablet quer: Leiste oben RECHTS. In beiden Touch-Fällen
			  bleibt der untere Bildschirmrand frei für Roblox' Daumenstick
			  und Sprungknopf; die Schublade klappt nach unten auf.
			- PC/Konsole: Leiste unten mittig, Schublade klappt nach oben auf.
			- Mindestgröße der Buttons 44 px (Touch) / 52 px (Konsole), Text
			  mindestens 11 px.

		Eingabe:
			- Tastatur/Maus: Kürzel B Build · Z Shop · Q Quests · T Travel ·
			  H More · U Brood Pool · M Mystery Egg · N Abducted · L Leaderboard
			  · C Codex · K Achievements · J Event · Y Settings. Das Kürzel
			  erscheint als Tasten-Chip am Button, solange zuletzt Tastatur/Maus
			  benutzt wurde. Dasselbe Kürzel nochmal schließt das Panel wieder.
			  (E/O/I/G/F/V/R/X sind absichtlich frei: Interaktion, Kamera-Zoom,
			  Ablegen, Depth Charge, Buddy-Namen, Drehen/Verkaufen.)
			- Gamepad: Y (oder View/Select) holt den Fokus in die Leiste, D-Pad/
			  Stick wählen, A bestätigt, B gibt den Fokus an die Spielfigur
			  zurück bzw. schließt die Schublade. Auto-Selektion von Roblox
			  ist aus (GuiService.AutoSelectGuiEnabled), damit D-Pad/Stick die
			  Figur nicht ungewollt in der UI festhalten.
			- Touch: Tippen; Tippen neben die Schublade schließt sie.

	Rojo-Einhängepunkt:
		src/client/MainMenuController.client.lua ->
		StarterPlayer.StarterPlayerScripts.MainMenuController
		(".client.lua"-Suffix signalisiert Rojo, hieraus ein `LocalScript`
		zu machen.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local SoundService = game:GetService("SoundService")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Device = UIKit.Device
local InputMode = UIKit.InputMode
local Theme = UIKit.Theme
local Layout = UIKit.Layout
local Button = UIKit.Button
local Panel = UIKit.Panel
local ProgressBar = UIKit.ProgressBar
local Settings = UIKit.Settings

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- Roblox' automatische GUI-Auswahl (D-Pad/Stick wählt irgendein Element) ist
-- aus: Die Fokus-Steuerung übernimmt dieses Skript (Y) und UIKit.Panel.
pcall(function()
	GuiService.AutoSelectGuiEnabled = false
end)

-- // Bridge zu den anderen Controllern (siehe Kopfkommentar) -------------------

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

local toggleBuildModeEvent = getOrCreateBridgeEvent("ToggleBuildMode")
local openBreedingOverviewEvent = getOrCreateBridgeEvent("OpenBreedingOverview")
local openMysteryEggEvent = getOrCreateBridgeEvent("OpenMysteryEgg")
local openAbductedCreaturesEvent = getOrCreateBridgeEvent("OpenAbductedCreatures")
local openShopEvent = getOrCreateBridgeEvent("OpenShop")
local openQuestsEvent = getOrCreateBridgeEvent("OpenQuests")
local openLeaderboardEvent = getOrCreateBridgeEvent("OpenLeaderboard")
local openTravelEvent = getOrCreateBridgeEvent("OpenTravel")
local openCodexEvent = getOrCreateBridgeEvent("OpenCodex")
local openEventEvent = getOrCreateBridgeEvent("OpenEvent")
local openAchievementsEvent = getOrCreateBridgeEvent("OpenAchievements")
local questBadgeCountEvent = getOrCreateBridgeEvent("QuestBadgeCountChanged")
local achievementBadgeCountEvent = getOrCreateBridgeEvent("AchievementBadgeCountChanged")

-- // Root-ScreenGui --------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainMenuBar"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 20
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Device.ApplySafeArea(screenGui)
screenGui.Parent = playerGui

local scaledRoot, unbindScale = Device.CreateScaledRoot(screenGui)

-- Z-Ebenen (Sibling): Backdrop 3 < Leiste 6 < Schublade 8, damit die Leiste
-- (inkl. "More") auch bei offener Schublade bedienbar bleibt.
local Z_BACKDROP = 3
local Z_BAR = 6
local Z_DRAWER = 8

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.BackgroundColor3 = Theme.Background.Panel
bar.BackgroundTransparency = 0.08
bar.BorderSizePixel = 0
bar.ZIndex = Z_BAR
bar.Parent = scaledRoot
Theme.ApplyCorner(bar, UDim.new(0, 18))
local barStroke = Theme.ApplyStroke(bar, Theme.Neon.Cyan, 2)
barStroke.Transparency = 0.3
Theme.ApplyGradient(bar, { Theme.Background.Panel, Theme.Background.Deepest }, 90)

local rowHost = Instance.new("Frame")
rowHost.Name = "RowHost"
rowHost.BackgroundTransparency = 1
rowHost.Size = UDim2.fromScale(1, 1)
rowHost.ZIndex = Z_BAR
rowHost.Parent = bar

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = rowHost

-- Gamepad-Hinweis "Y Menu" an der Leiste (nur im Gamepad-Modus sichtbar).
local gamepadFocusHint = InputMode.CreateHint({
	Parent = bar,
	Gamepad = Enum.KeyCode.ButtonY,
	Label = "Menu",
	ZIndex = 20,
})

-- // Menü-Einträge -------------------------------------------------------------------

type MenuEntry = {
	Id: string,
	Icon: string,
	Text: string,
	OnClick: () -> (),
	Key: Enum.KeyCode?,
	IsPanel: boolean, -- false: schaltet einen Modus (Build) statt ein Panel zu öffnen
	BadgeKey: string?, -- "Quest" | "Achievement" - siehe badgeFrames/badgeLabels unten
}

type BuiltButton = {
	Handle: any,
	Entry: MenuEntry,
	Hint: any,
}

local primaryButtons: { BuiltButton } = {}
local drawerButtons: { BuiltButton } = {}
local moreHandle: any = nil
local moreHint: any = nil

local badgeFrames: { [string]: { Frame } } = {}
local badgeLabels: { [string]: { TextLabel } } = {}
local badgeCounts: { [string]: number } = {}
local DRAWER_BADGE_KEYS = { "Achievement" } -- Zähler dieser Einträge erscheinen auch am "More"-Button
local moreBadgeFrame: Frame? = nil
local moreBadgeLabel: TextLabel? = nil

local function makeBadge(parent: GuiObject): (Frame, TextLabel)
	-- Kleines, grelles Zähler-Abzeichen oben rechts am Button (offene
	-- Belohnung zum Abholen). Die UI-Controller melden den Zähler über ihre
	-- eigene Bridge ("QuestBadgeCountChanged"/"AchievementBadgeCountChanged").
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(1, 0)
	badge.Position = UDim2.new(1, 6, 0, -6)
	badge.Size = UDim2.fromOffset(22, 22)
	badge.BackgroundColor3 = Theme.Semantic.Danger
	badge.ZIndex = 10
	badge.Visible = false
	Theme.ApplyCorner(badge, UDim.new(1, 0))
	Theme.ApplyStroke(badge, Theme.Text.Stroke, 1.5)
	badge.Parent = parent

	local badgeLabel = Instance.new("TextLabel")
	badgeLabel.BackgroundTransparency = 1
	badgeLabel.Size = UDim2.fromScale(1, 1)
	badgeLabel.Font = Theme.Font.BodyBold
	badgeLabel.TextColor3 = Theme.Text.OnNeon
	badgeLabel.TextScaled = true
	badgeLabel.Text = "0"
	badgeLabel.ZIndex = 11
	badgeLabel.Parent = badge
	local badgeConstraint = Instance.new("UITextSizeConstraint")
	badgeConstraint.MinTextSize = 12
	badgeConstraint.MaxTextSize = 14
	badgeConstraint.Parent = badgeLabel
	return badge, badgeLabel
end

local function setBadgeVisual(frame: Frame, label: TextLabel, count: number)
	local clamped = math.clamp(count, 0, 99)
	frame.Visible = clamped > 0
	label.Text = if clamped > 9 then "9+" else tostring(clamped)
end

local function updateBadge(key: string, count: number)
	badgeCounts[key] = count
	local frames = badgeFrames[key]
	local labels = badgeLabels[key]
	if frames and labels then
		for index, frame in frames do
			setBadgeVisual(frame, labels[index], count)
		end
	end
	if moreBadgeFrame and moreBadgeLabel then
		local total = 0
		for _, drawerKey in DRAWER_BADGE_KEYS do
			total += badgeCounts[drawerKey] or 0
		end
		setBadgeVisual(moreBadgeFrame, moreBadgeLabel, total)
	end
end

local function registerBadge(key: string, frame: Frame, label: TextLabel)
	badgeFrames[key] = badgeFrames[key] or {}
	badgeLabels[key] = badgeLabels[key] or {}
	table.insert(badgeFrames[key], frame)
	table.insert(badgeLabels[key], label)
	updateBadge(key, badgeCounts[key] or 0)
end

local questBadgeConnection = questBadgeCountEvent.Event:Connect(function(count: number)
	if type(count) == "number" then
		updateBadge("Quest", count)
	end
end)
local achievementBadgeConnection = achievementBadgeCountEvent.Event:Connect(function(count: number)
	if type(count) == "number" then
		updateBadge("Achievement", count)
	end
end)

-- Beschriftung enger setzen als im Standard-Button: kleine Menü-Kacheln
-- (Icon + Name in zwei Zeilen) brauchen Mindesttext 11 statt 14.
local function styleMenuLabel(handle: any)
	local label = handle.Instance:FindFirstChild("Label") :: TextLabel?
	if not label then
		return
	end
	label.TextWrapped = true
	label.Position = UDim2.fromOffset(2, 2)
	label.Size = UDim2.new(1, -4, 1, -4)
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		constraint.MinTextSize = 12
		constraint.MaxTextSize = 15
	end
end

local function buildButton(entry: MenuEntry, parent: Instance, order: number, size: UDim2): BuiltButton
	local handle = Button.new({
		Parent = parent,
		Text = entry.Icon .. "\n" .. entry.Text,
		Variant = "Secondary",
		Size = size,
		LayoutOrder = order,
	})
	handle.Instance.ZIndex = Z_BAR
	styleMenuLabel(handle)

	-- Tastatur-Kürzel als Tasten-Chip (nur sichtbar bei Tastatur/Maus).
	local hint: any = nil
	if entry.Key then
		hint = InputMode.CreateHint({
			Parent = handle.Instance,
			Keyboard = InputMode.GetGlyph(entry.Key),
			AnchorPoint = Vector2.new(0, 0),
			Position = UDim2.fromOffset(-4, -9),
			ZIndex = 20,
		})
	end

	if entry.BadgeKey then
		local badge, badgeLabel = makeBadge(handle.Instance)
		registerBadge(entry.BadgeKey, badge, badgeLabel)
	end

	return { Handle = handle, Entry = entry, Hint = hint }
end

-- // Aktionen -------------------------------------------------------------------------

local drawerOpen = false
local closeDrawer: (refocusMore: boolean?) -> ()
local lastShortcutId: string? = nil

local function runEntry(entry: MenuEntry, fromShortcut: boolean)
	if drawerOpen then
		closeDrawer(false)
	end
	if not entry.IsPanel then
		lastShortcutId = nil
		entry.OnClick()
		return
	end
	-- Tastenkürzel schalten um: dasselbe Kürzel nochmal schließt das Panel,
	-- ein anderes ersetzt es.
	if fromShortcut then
		if Panel.IsAnyOpen() and lastShortcutId == entry.Id then
			Panel.CloseAll()
			lastShortcutId = nil
			return
		end
		Panel.CloseAll()
		lastShortcutId = entry.Id
	else
		lastShortcutId = nil
	end
	entry.OnClick()
end

local settingsPanel: any = nil

local sfxVolume = SoundService.Volume
local musicVolume = Workspace:GetAttribute("MusicVolume")
if type(musicVolume) ~= "number" then
	musicVolume = 0.6
	Workspace:SetAttribute("MusicVolume", musicVolume)
end

local function makeSettingsLabel(parent: Instance, text: string, y: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 24)
	label.Position = UDim2.fromOffset(0, y)
	label.Font = Theme.Font.BodyBold
	label.TextColor3 = Theme.Text.Primary
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextScaled = true
	label.Text = text
	label.Parent = parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 12
	constraint.MaxTextSize = 18
	constraint.Parent = label
	return label
end

local function buildSettingsPanel()
	if settingsPanel then
		return settingsPanel
	end

	settingsPanel = Panel.new({
		Title = "Settings",
		Closable = true,
		CenteredSize = UDim2.fromOffset(460, 430),
	})

	local content = settingsPanel.Content

	-- // Reduzierte Effekte -----------------------------------------------------
	makeSettingsLabel(content, "Reduced Effects (particles/screen shake off)", 0)

	local reducedToggle = Button.new({
		Parent = content,
		Text = if Settings.GetReducedEffects() then "ON" else "OFF",
		Variant = if Settings.GetReducedEffects() then "Success" else "Ghost",
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 1,
	})
	reducedToggle.Instance.Position = UDim2.fromOffset(0, 30)
	reducedToggle.Clicked:Connect(function()
		local newValue = not Settings.GetReducedEffects()
		Settings.SetReducedEffects(newValue)
		reducedToggle:SetText(if newValue then "ON" else "OFF")
	end)

	-- // Sound-Lautstärke (44 px große +/- Knöpfe: Touch- und Gamepad-tauglich) -----
	makeSettingsLabel(content, "Sound Volume", 92)

	local sfxBarHost = Instance.new("Frame")
	sfxBarHost.BackgroundTransparency = 1
	sfxBarHost.Position = UDim2.fromOffset(0, 130)
	sfxBarHost.Size = UDim2.new(1, -104, 0, 22)
	sfxBarHost.Parent = content
	local sfxBar = ProgressBar.new({
		Parent = sfxBarHost,
		Size = UDim2.new(1, 0, 1, 0),
		Value = sfxVolume,
		Colors = { Theme.Neon.Cyan, Theme.Neon.ToxicGreen },
	})

	local sfxMinus = Button.new({
		Parent = content,
		Text = "-",
		Variant = "Ghost",
		Size = UDim2.fromOffset(44, 44),
		LayoutOrder = 2,
	})
	sfxMinus.Instance.Position = UDim2.new(1, -96, 0, 119)
	local sfxPlus = Button.new({
		Parent = content,
		Text = "+",
		Variant = "Ghost",
		Size = UDim2.fromOffset(44, 44),
		LayoutOrder = 3,
	})
	sfxPlus.Instance.Position = UDim2.new(1, -48, 0, 119)

	local function applySfxVolume()
		sfxVolume = math.clamp(sfxVolume, 0, 1)
		SoundService.Volume = sfxVolume
		sfxBar:SetProgress(sfxVolume)
	end
	sfxMinus.Clicked:Connect(function()
		sfxVolume -= 0.1
		applySfxVolume()
	end)
	sfxPlus.Clicked:Connect(function()
		sfxVolume += 0.1
		applySfxVolume()
	end)

	-- // Musik-Lautstärke ---------------------------------------------------------
	-- Steuert AudioController.client.lua über das Workspace-Attribut
	-- "MusicVolume" (wird dort live per GetAttributeChangedSignal gelesen).
	makeSettingsLabel(content, "Music Volume", 176)

	local musicBarHost = Instance.new("Frame")
	musicBarHost.BackgroundTransparency = 1
	musicBarHost.Position = UDim2.fromOffset(0, 214)
	musicBarHost.Size = UDim2.new(1, -104, 0, 22)
	musicBarHost.Parent = content
	local musicBar = ProgressBar.new({
		Parent = musicBarHost,
		Size = UDim2.new(1, 0, 1, 0),
		Value = musicVolume,
		Colors = { Theme.Neon.Violet, Theme.Neon.Magenta },
	})

	local musicMinus = Button.new({
		Parent = content,
		Text = "-",
		Variant = "Ghost",
		Size = UDim2.fromOffset(44, 44),
		LayoutOrder = 4,
	})
	musicMinus.Instance.Position = UDim2.new(1, -96, 0, 203)
	local musicPlus = Button.new({
		Parent = content,
		Text = "+",
		Variant = "Ghost",
		Size = UDim2.fromOffset(44, 44),
		LayoutOrder = 5,
	})
	musicPlus.Instance.Position = UDim2.new(1, -48, 0, 203)

	local function applyMusicVolume()
		musicVolume = math.clamp(musicVolume, 0, 1)
		Workspace:SetAttribute("MusicVolume", musicVolume)
		musicBar:SetProgress(musicVolume)
	end
	musicMinus.Clicked:Connect(function()
		musicVolume -= 0.1
		applyMusicVolume()
	end)
	musicPlus.Clicked:Connect(function()
		musicVolume += 0.1
		applyMusicVolume()
	end)

	-- // Steuerungs-Hilfe (folgt der zuletzt benutzten Eingabe) --------------------
	local controlsLabel = Instance.new("TextLabel")
	controlsLabel.Name = "ControlsHelp"
	controlsLabel.BackgroundTransparency = 1
	controlsLabel.Position = UDim2.fromOffset(0, 256)
	controlsLabel.Size = UDim2.new(1, 0, 0, 80)
	controlsLabel.Font = Theme.Font.Body
	controlsLabel.TextColor3 = Theme.Text.Secondary
	controlsLabel.TextXAlignment = Enum.TextXAlignment.Left
	controlsLabel.TextYAlignment = Enum.TextYAlignment.Top
	controlsLabel.TextWrapped = true
	controlsLabel.TextScaled = true
	controlsLabel.Parent = content
	local controlsConstraint = Instance.new("UITextSizeConstraint")
	controlsConstraint.MinTextSize = 12
	controlsConstraint.MaxTextSize = 14
	controlsConstraint.Parent = controlsLabel
	InputMode.Bind(function(mode)
		if mode == "Gamepad" then
			controlsLabel.Text =
				"Controller: Y opens the menu · D-Pad/Stick choose · A confirms · B goes back · X picks up/deposits · B drops an item you hold."
		elseif mode == "KeyboardMouse" then
			controlsLabel.Text =
				"Keyboard: B Build · Z Shop · Q Quests · T Travel · H More · U Brood Pool · M Mystery Egg · L Leaderboard · C Codex · K Achievements · Y Settings · E interact."
		else
			controlsLabel.Text = "Tap the buttons at the top to open menus. Use the jump and sprint buttons on the right to move."
		end
	end)

	return settingsPanel
end

-- // Eintrags-Tabelle -----------------------------------------------------------------

local primaryEntries: { MenuEntry } = {
	{ Id = "Build", Icon = "🛠️", Text = "Build", IsPanel = false, Key = Enum.KeyCode.B, OnClick = function() toggleBuildModeEvent:Fire() end },
	{ Id = "Shop", Icon = "🛒", Text = "Shop", IsPanel = true, Key = Enum.KeyCode.Z, OnClick = function() openShopEvent:Fire() end },
	{ Id = "Quests", Icon = "📜", Text = "Quests", IsPanel = true, Key = Enum.KeyCode.Q, BadgeKey = "Quest", OnClick = function() openQuestsEvent:Fire() end },
	{ Id = "Travel", Icon = "🧭", Text = "Travel", IsPanel = true, Key = Enum.KeyCode.T, OnClick = function() openTravelEvent:Fire() end },
}

local drawerEntries: { MenuEntry } = {
	{ Id = "BroodPool", Icon = "🥚", Text = "Brood Pool", IsPanel = true, Key = Enum.KeyCode.U, OnClick = function() openBreedingOverviewEvent:Fire() end },
	{ Id = "MysteryEgg", Icon = "🎁", Text = "Mystery Egg", IsPanel = true, Key = Enum.KeyCode.M, OnClick = function() openMysteryEggEvent:Fire() end },
	{ Id = "Abducted", Icon = "🆘", Text = "Abducted", IsPanel = true, Key = Enum.KeyCode.N, OnClick = function() openAbductedCreaturesEvent:Fire() end },
	{ Id = "Leaderboard", Icon = "🏆", Text = "Leaderboard", IsPanel = true, Key = Enum.KeyCode.L, OnClick = function() openLeaderboardEvent:Fire() end },
	{ Id = "Codex", Icon = "📖", Text = "Codex", IsPanel = true, Key = Enum.KeyCode.C, OnClick = function() openCodexEvent:Fire() end },
	{ Id = "Achievements", Icon = "🏅", Text = "Achievements", IsPanel = true, Key = Enum.KeyCode.K, BadgeKey = "Achievement", OnClick = function() openAchievementsEvent:Fire() end },
	{ Id = "Event", Icon = "🌊", Text = "Event", IsPanel = true, Key = Enum.KeyCode.J, OnClick = function() openEventEvent:Fire() end },
	{ Id = "Settings", Icon = "⚙️", Text = "Settings", IsPanel = true, Key = Enum.KeyCode.Y, OnClick = function()
		buildSettingsPanel()
		settingsPanel:Open()
	end },
}

-- // Schublade ("More") ---------------------------------------------------------------

local DRAWER_CELL = Vector2.new(100, 76)
local DRAWER_GAP = 8
local DRAWER_PADDING = 12
local DRAWER_TITLE_HEIGHT = 28

local backdrop = Instance.new("Frame")
backdrop.Name = "DrawerBackdrop"
backdrop.BackgroundTransparency = 1
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.ZIndex = Z_BACKDROP
backdrop.Active = true -- fängt Tippen neben der Schublade ab
backdrop.Selectable = false
backdrop.Visible = false
backdrop.Parent = scaledRoot

local drawer = Instance.new("Frame")
drawer.Name = "Drawer"
drawer.BackgroundColor3 = Theme.Background.Panel
drawer.BackgroundTransparency = 0.04
drawer.BorderSizePixel = 0
drawer.ZIndex = Z_DRAWER
drawer.Active = true
drawer.Visible = false
drawer.Parent = scaledRoot
Theme.ApplyCorner(drawer, UDim.new(0, 18))
local drawerStroke = Theme.ApplyStroke(drawer, Theme.Neon.Violet, 2)
drawerStroke.Transparency = 0.2
Theme.ApplyGradient(drawer, { Theme.Background.Panel, Theme.Background.Deepest }, 90)

local drawerTitle = Instance.new("TextLabel")
drawerTitle.Name = "Title"
drawerTitle.BackgroundTransparency = 1
drawerTitle.Position = UDim2.fromOffset(DRAWER_PADDING + 4, 6)
drawerTitle.Size = UDim2.new(1, -(DRAWER_PADDING * 2 + 100), 0, DRAWER_TITLE_HEIGHT)
drawerTitle.Font = Theme.Font.Header
drawerTitle.TextColor3 = Theme.Text.Primary
drawerTitle.TextXAlignment = Enum.TextXAlignment.Left
drawerTitle.TextScaled = true
drawerTitle.Text = "More"
drawerTitle.ZIndex = Z_DRAWER
drawerTitle.Parent = drawer
local drawerTitleConstraint = Instance.new("UITextSizeConstraint")
drawerTitleConstraint.MinTextSize = 16
drawerTitleConstraint.MaxTextSize = 22
drawerTitleConstraint.Parent = drawerTitle

local drawerCloseHint = InputMode.CreateHint({
	Parent = drawer,
	Gamepad = Enum.KeyCode.ButtonB,
	Label = "Close",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -DRAWER_PADDING, 0, 10),
	ZIndex = Z_DRAWER + 2,
})

local drawerScroll = Instance.new("ScrollingFrame")
drawerScroll.Name = "Grid"
drawerScroll.BackgroundTransparency = 1
drawerScroll.BorderSizePixel = 0
drawerScroll.Position = UDim2.fromOffset(DRAWER_PADDING, DRAWER_TITLE_HEIGHT + 12)
drawerScroll.Size = UDim2.new(1, -DRAWER_PADDING * 2, 1, -(DRAWER_TITLE_HEIGHT + 12 + DRAWER_PADDING))
drawerScroll.CanvasSize = UDim2.new()
drawerScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
drawerScroll.ScrollingDirection = Enum.ScrollingDirection.Y
drawerScroll.ScrollBarThickness = 4
drawerScroll.ScrollBarImageColor3 = Theme.Neon.Cyan
drawerScroll.ZIndex = Z_DRAWER
drawerScroll.Parent = drawer

local drawerGrid = Instance.new("UIGridLayout")
drawerGrid.CellSize = UDim2.fromOffset(DRAWER_CELL.X, DRAWER_CELL.Y)
drawerGrid.CellPadding = UDim2.fromOffset(DRAWER_GAP, DRAWER_GAP)
drawerGrid.HorizontalAlignment = Enum.HorizontalAlignment.Center
drawerGrid.SortOrder = Enum.SortOrder.LayoutOrder
drawerGrid.Parent = drawerScroll

local drawerGridPadding = Instance.new("UIPadding")
drawerGridPadding.PaddingTop = UDim.new(0, 10) -- Platz für Tasten-Chips/Badges, die über den Rand ragen
drawerGridPadding.PaddingRight = UDim.new(0, 8)
drawerGridPadding.Parent = drawerScroll

local function applyDrawerLayout()
	local layout = Layout.GetHudLayout()
	local viewport = Device.GetVirtualViewport()
	local availableWidth = math.min(viewport.X - 16, 480)
	local columns = math.clamp(math.floor((availableWidth - DRAWER_PADDING * 2 + DRAWER_GAP) / (DRAWER_CELL.X + DRAWER_GAP)), 2, 4)
	local rows = math.ceil(#drawerEntries / columns)
	local width = columns * DRAWER_CELL.X + (columns - 1) * DRAWER_GAP + DRAWER_PADDING * 2 + 8
	local desiredHeight = DRAWER_TITLE_HEIGHT + 12 + 10 + rows * DRAWER_CELL.Y + (rows - 1) * DRAWER_GAP + DRAWER_PADDING

	local menu = layout.Menu
	local menuTop = menu.Position.Y.Offset
	local menuHeight = menu.Size.Y.Offset
	-- ~48 px Reserve für Topbar/Safe-Area, die der virtuelle Viewport nicht abzieht.
	local reserved = 48 + 8
	if layout.MenuAtBottom then
		-- Schublade klappt nach OBEN auf (Leiste unten mittig).
		local bottomOffset = -menu.Position.Y.Offset -- Position.Y.Offset ist negativ (z. B. -18)
		local gap = bottomOffset + menuHeight + 8
		local maxHeight = viewport.Y - reserved - gap
		drawer.AnchorPoint = Vector2.new(0.5, 1)
		drawer.Position = UDim2.new(0.5, 0, 1, -gap)
		drawer.Size = UDim2.fromOffset(width, math.min(desiredHeight, maxHeight))
	else
		-- Schublade klappt nach UNTEN auf (Leiste oben).
		local top = menuTop + menuHeight + 6
		local maxHeight = viewport.Y - reserved - top
		drawer.AnchorPoint = Vector2.new(menu.AnchorPoint.X, 0)
		drawer.Position = UDim2.new(menu.Position.X.Scale, menu.Position.X.Offset, 0, top)
		drawer.Size = UDim2.fromOffset(width, math.min(desiredHeight, maxHeight))
	end
end

local function focusFirstDrawerButton()
	local first = drawerButtons[1]
	if first and InputMode.IsGamepad() then
		GuiService.SelectedObject = first.Handle.Instance
	end
end

local function openDrawer()
	if drawerOpen then
		return
	end
	drawerOpen = true
	applyDrawerLayout()
	backdrop.Visible = true
	drawer.Visible = true
	focusFirstDrawerButton()
end

closeDrawer = function(refocusMore: boolean?)
	if not drawerOpen then
		return
	end
	drawerOpen = false
	backdrop.Visible = false
	drawer.Visible = false
	local selected = GuiService.SelectedObject
	if selected and selected:IsDescendantOf(drawer) then
		GuiService.SelectedObject = if refocusMore and moreHandle then moreHandle.Instance else nil
	end
end

local backdropConnection = backdrop.InputBegan:Connect(function(input: InputObject)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		closeDrawer(false)
	end
end)

local function toggleDrawer()
	if drawerOpen then
		closeDrawer(true)
	else
		openDrawer()
	end
end

-- // Leiste aufbauen --------------------------------------------------------------------

local initialLayout = Layout.GetHudLayout()
local initialSize = UDim2.fromOffset(initialLayout.MenuButtonSize.X, initialLayout.MenuButtonSize.Y)

for index, entry in ipairs(primaryEntries) do
	local built = buildButton(entry, rowHost, index, initialSize)
	built.Handle.Clicked:Connect(function()
		runEntry(entry, false)
	end)
	table.insert(primaryButtons, built)
end

local moreEntry: MenuEntry = {
	Id = "More",
	Icon = "☰",
	Text = "More",
	IsPanel = false,
	Key = Enum.KeyCode.H,
	OnClick = function() end,
}
do
	local built = buildButton(moreEntry, rowHost, #primaryEntries + 1, initialSize)
	moreHandle = built.Handle
	moreHint = built.Hint
	built.Handle.Clicked:Connect(toggleDrawer)
	local badge, badgeLabel = makeBadge(built.Handle.Instance)
	moreBadgeFrame = badge
	moreBadgeLabel = badgeLabel
end

for index, entry in ipairs(drawerEntries) do
	-- Zellgröße setzt UIGridLayout; die Button-Größe hier ist nur ein Platzhalter.
	local built = buildButton(entry, drawerScroll, index, UDim2.fromOffset(DRAWER_CELL.X, DRAWER_CELL.Y))
	built.Handle.Instance.ZIndex = Z_DRAWER
	built.Handle.Clicked:Connect(function()
		runEntry(entry, false)
	end)
	table.insert(drawerButtons, built)
end

-- Badges am "More"-Button einmal initial setzen (falls Zähler schon gemeldet).
updateBadge("Achievement", badgeCounts["Achievement"] or 0)

local function applyBarLayout()
	local layout = Layout.GetHudLayout()
	local dock = layout.Menu
	bar.AnchorPoint = dock.AnchorPoint
	bar.Position = dock.Position
	bar.Size = dock.Size

	local count = #primaryEntries + 1
	local buttonWidth = layout.MenuButtonSize.X
	if layout.Mode == "Portrait" then
		-- Fünf gleich breite Kacheln über die volle Breite (Leiste = Viewport - 16).
		local viewportWidth = Device.GetVirtualViewport().X
		buttonWidth = math.clamp(math.floor((viewportWidth - 16 - 20 - (count - 1) * 6) / count), 54, 84)
	end
	local size = UDim2.fromOffset(buttonWidth, layout.MenuButtonSize.Y)
	listLayout.Padding = UDim.new(0, if layout.Mode == "Desktop" then 8 else 6)
	for _, built in primaryButtons do
		built.Handle.Instance.Size = size
	end
	if moreHandle then
		moreHandle.Instance.Size = size
	end

	-- "Y Menu"-Chip: bei unten liegender Leiste darüber, sonst darunter.
	if layout.MenuAtBottom then
		gamepadFocusHint.Instance.AnchorPoint = Vector2.new(0, 1)
		gamepadFocusHint.Instance.Position = UDim2.new(0, 6, 0, -4)
	else
		gamepadFocusHint.Instance.AnchorPoint = Vector2.new(0, 0)
		gamepadFocusHint.Instance.Position = UDim2.new(0, 6, 1, 4)
	end

	if drawerOpen then
		applyDrawerLayout()
	end
end

applyBarLayout()
local deviceConnection = Device.Changed:Connect(applyBarLayout)

-- // Tastaturkürzel (Hinweis-Chips nur bei Tastatur/Maus; funktionieren auf jedem
-- Gerät mit angeschlossener Tastatur) ----------------------------------------------

local shortcutEntries: { [Enum.KeyCode]: MenuEntry } = {}
for _, entry in primaryEntries do
	if entry.Key then
		shortcutEntries[entry.Key] = entry
	end
end
for _, entry in drawerEntries do
	if entry.Key then
		shortcutEntries[entry.Key] = entry
	end
end

local inputConnection = UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
	if gameProcessed or input.UserInputType ~= Enum.UserInputType.Keyboard then
		return
	end
	if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl) then
		return
	end
	if input.KeyCode == Enum.KeyCode.H then
		toggleDrawer()
		return
	end
	local entry = shortcutEntries[input.KeyCode]
	if entry then
		runEntry(entry, true)
	end
end)

-- // Gamepad: Fokus in die Leiste holen / zurückgeben ------------------------------------
-- Y (oder View/Select) wechselt zwischen "Figur steuern" und "Menü steuern".
-- Solange der Fokus in Leiste/Schublade liegt, gibt B ihn zurück (bzw. schließt
-- die Schublade). Panels (UIKit.Panel) haben mit ihrem eigenen B Vorrang.

local MENU_FOCUS_ACTION = "AbyssaraMenuFocus"
local MENU_BACK_ACTION = "AbyssaraMenuBack"
local menuBackBound = false

local function isInMenu(target: Instance?): boolean
	return target ~= nil and (target:IsDescendantOf(bar) or target:IsDescendantOf(drawer))
end

local function onMenuFocusAction(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if Panel.IsAnyOpen() then
		return Enum.ContextActionResult.Pass
	end
	if isInMenu(GuiService.SelectedObject) then
		closeDrawer(false)
		GuiService.SelectedObject = nil
	else
		local first = primaryButtons[1]
		if first then
			GuiService.SelectedObject = first.Handle.Instance
		end
	end
	return Enum.ContextActionResult.Sink
end

local function onMenuBackAction(_name: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if drawerOpen then
		closeDrawer(true)
	else
		GuiService.SelectedObject = nil
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction(MENU_FOCUS_ACTION, onMenuFocusAction, false, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonSelect)

local selectionConnection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(function()
	local inMenu = isInMenu(GuiService.SelectedObject)
	if inMenu and not menuBackBound then
		menuBackBound = true
		ContextActionService:BindActionAtPriority(
			MENU_BACK_ACTION,
			onMenuBackAction,
			false,
			Enum.ContextActionPriority.High.Value - 1,
			Enum.KeyCode.ButtonB
		)
	elseif not inMenu and menuBackBound then
		menuBackBound = false
		ContextActionService:UnbindAction(MENU_BACK_ACTION)
	end
end)

-- // Aufräumen -------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	deviceConnection:Disconnect()
	inputConnection:Disconnect()
	selectionConnection:Disconnect()
	backdropConnection:Disconnect()
	questBadgeConnection:Disconnect()
	achievementBadgeConnection:Disconnect()
	ContextActionService:UnbindAction(MENU_FOCUS_ACTION)
	if menuBackBound then
		menuBackBound = false
		ContextActionService:UnbindAction(MENU_BACK_ACTION)
	end
	unbindScale()
	gamepadFocusHint:Destroy()
	drawerCloseHint:Destroy()
	for _, built in primaryButtons do
		if built.Hint then
			built.Hint:Destroy()
		end
		built.Handle:Destroy()
	end
	for _, built in drawerButtons do
		if built.Hint then
			built.Hint:Destroy()
		end
		built.Handle:Destroy()
	end
	if moreHint then
		moreHint:Destroy()
	end
	if moreHandle then
		moreHandle:Destroy()
	end
	if settingsPanel then
		settingsPanel:Destroy()
	end
	screenGui:Destroy()
end)
