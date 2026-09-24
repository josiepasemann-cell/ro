--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: MainMenuController (LocalScript)
	Zuständigkeit:
		Zentrale, dauerhaft sichtbare Menüleiste - ersetzt die vorher über
		den Bildschirm verstreuten Einzel-Buttons (Rettungs-Button aus
		RaidUIController, Baumodus nur über Tastatur usw.) durch EINE
		konsistente Leiste mit den Einstiegspunkten:
			- Bauen (schaltet den Baumodus in PlacementPreviewController um)
			- Brutbecken-Übersicht (BreedingUIController)
			- Mystery Egg / Drop-Chancen (GachaOddsUIController)
			- Entführte Kreaturen (RaidUIController)
			- Einstellungen (Reduzierte Effekte, Sound-/Musik-Lautstärke -
			  rein lokale Client-Einstellungen, siehe UIKit.Settings)
			- Shop (öffnet ShopUIController.client.lua über die
			  Bridge-BindableEvent "OpenShop", identisches Muster wie
			  "OpenMysteryEgg"/"OpenBreedingOverview" unten)

		Kommunikation mit den anderen Controllern läuft bewusst NICHT über
		direkte Requires (das wären Kreis-Abhängigkeiten zwischen
		gleichrangigen LocalScripts), sondern über eine winzige, zur
		Laufzeit angelegte Bridge aus BindableEvents unter
		ReplicatedStorage.AbyssaraUIBridge (siehe getOrCreateBridgeEvent
		unten - dasselbe Muster wird in PlacementPreviewController,
		BreedingUIController, GachaOddsUIController und RaidUIController
		verwendet). Das verändert KEINE Datei unter src/shared, es werden
		nur zur Laufzeit Instanzen angelegt (kein Rojo-Mapping nötig).

		Geräte-Layout (UIKit.Device):
			- Phone: volle Breite, unten angedockt, große Icon-Buttons,
			  eine Spalte->Reihe via Layout.ResponsiveRow (auf Phone
			  eigentlich Spalte, hier bewusst erzwungene Reihe mit
			  Wrap, siehe buildBar()).
			- Tablet/PC: unten mittig angedockte, kompakte Reihe.
			- PC zusätzlich: Tastaturkürzel (B/U/M/N/O), nur als Hinweis
			  sichtbar, wenn Device.ShouldShowKeyboardHints() true ist.
			- Konsole: gleiche Leiste, Buttons sind über die native
			  Gamepad-Selektion (UIKit.Button macht das automatisch)
			  erreichbar; GuiService.SelectedObject wird beim Start auf
			  den ersten Button gesetzt, damit Gamepad-Navigation sofort
			  einen Fokus hat.

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
local Workspace = game:GetService("Workspace")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Device = UIKit.Device
local Theme = UIKit.Theme
local Layout = UIKit.Layout
local Button = UIKit.Button
local Panel = UIKit.Panel
local ProgressBar = UIKit.ProgressBar
local Settings = UIKit.Settings

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

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

-- // Root-ScreenGui --------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "MainMenuBar"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 20
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
Device.ApplySafeArea(screenGui)
screenGui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = screenGui
local unbindScale = Device.BindUIScale(uiScale)

local bar = Instance.new("Frame")
bar.Name = "Bar"
bar.BackgroundColor3 = Theme.Background.Panel
bar.BackgroundTransparency = 0.08
bar.BorderSizePixel = 0
bar.Parent = screenGui
Theme.ApplyCorner(bar, UDim.new(0, 18))
local barStroke = Theme.ApplyStroke(bar, Theme.Neon.Cyan, 2)
barStroke.Transparency = 0.3
Theme.ApplyGradient(bar, { Theme.Background.Panel, Theme.Background.Deepest }, 90)

local rowHost = Instance.new("Frame")
rowHost.Name = "RowHost"
rowHost.BackgroundTransparency = 1
rowHost.AnchorPoint = Vector2.new(0.5, 0.5)
rowHost.Position = UDim2.fromScale(0.5, 0.5)
rowHost.Size = UDim2.new(1, -16, 1, -16)
rowHost.Parent = bar

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Horizontal
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
listLayout.Padding = UDim.new(0, 8)
listLayout.Wraps = true
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = rowHost

local hintLabel = Instance.new("TextLabel")
hintLabel.Name = "KeyboardHints"
hintLabel.BackgroundTransparency = 1
hintLabel.AnchorPoint = Vector2.new(0.5, 1)
hintLabel.Position = UDim2.new(0.5, 0, 0, -6)
hintLabel.Size = UDim2.new(1, 0, 0, 18)
hintLabel.Font = Theme.Font.Body
hintLabel.TextColor3 = Theme.Text.Muted
hintLabel.TextScaled = true
hintLabel.Text = "B Bauen · U Brutbecken · M Mystery Egg · N Entführte · O Einstellungen"
hintLabel.Visible = false
hintLabel.Parent = bar
local hintConstraint = Instance.new("UITextSizeConstraint")
hintConstraint.MinTextSize = 10
hintConstraint.MaxTextSize = 14
hintConstraint.Parent = hintLabel

-- // Geräteabhängiges Andocken ---------------------------------------------------

local function applyBarLayout()
	local state = Device.GetState()
	if state.Class == "Phone" then
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -8)
		bar.AutomaticSize = Enum.AutomaticSize.None
		bar.Size = UDim2.new(1, -16, 0, 84)
		hintLabel.Visible = false
	else
		bar.AnchorPoint = Vector2.new(0.5, 1)
		bar.Position = UDim2.new(0.5, 0, 1, -18)
		bar.AutomaticSize = Enum.AutomaticSize.None
		bar.Size = UDim2.fromOffset(6 * 56 + 5 * 8 + 32, 68)
		hintLabel.Visible = Device.ShouldShowKeyboardHints()
	end
end

applyBarLayout()
local deviceConnection = Device.Changed:Connect(applyBarLayout)

-- // Menü-Buttons -----------------------------------------------------------------

type MenuEntry = {
	Icon: string,
	Text: string,
	OnClick: () -> (),
}

local buttonHandles: { any } = {}

local function buildButton(entry: MenuEntry, order: number)
	local buttonSize = if Device.IsPhone() then UDim2.fromOffset(64, 64) else UDim2.fromOffset(56, 56)
	local handle = Button.new({
		Parent = rowHost,
		Text = entry.Icon .. "\n" .. entry.Text,
		Variant = "Secondary",
		Size = buttonSize,
		LayoutOrder = order,
	})
	local label = handle.Instance:FindFirstChild("Label") :: TextLabel?
	if label then
		label.TextWrapped = true
	end
	handle.Clicked:Connect(entry.OnClick)
	table.insert(buttonHandles, handle)
	return handle
end

-- // Baumodus ----------------------------------------------------------------------

local function onBuildClicked()
	toggleBuildModeEvent:Fire()
end

-- // Brutbecken-Übersicht -----------------------------------------------------------

local function onBreedingClicked()
	openBreedingOverviewEvent:Fire()
end

-- // Mystery Egg -------------------------------------------------------------------

local function onMysteryEggClicked()
	openMysteryEggEvent:Fire()
end

-- // Entführte Kreaturen -------------------------------------------------------------

local function onAbductedClicked()
	openAbductedCreaturesEvent:Fire()
end

-- // Shop --------------------------------------------------------------------------
-- Öffnet das vollständige Shop-Panel aus ShopUIController.client.lua über die
-- Bridge (siehe Kopfkommentar) - dieser Controller baut keine eigene Shop-UI
-- mehr, um Dateibesitz/Verantwortung sauber getrennt zu halten.

local function onShopClicked()
	openShopEvent:Fire()
end

-- // Einstellungen -------------------------------------------------------------------

local settingsPanel: any = nil

local sfxVolume = SoundService.Volume
local musicVolume = Workspace:GetAttribute("MusicVolume")
if type(musicVolume) ~= "number" then
	musicVolume = 0.6
	Workspace:SetAttribute("MusicVolume", musicVolume)
end

local function buildSettingsPanel()
	if settingsPanel then
		return settingsPanel
	end

	settingsPanel = Panel.new({
		Title = "Einstellungen",
		Closable = true,
		CenteredSize = UDim2.fromOffset(460, 380),
	})

	local content = settingsPanel.Content

	-- // Reduzierte Effekte -----------------------------------------------------
	local reducedLabel = Instance.new("TextLabel")
	reducedLabel.BackgroundTransparency = 1
	reducedLabel.Size = UDim2.new(1, 0, 0, 24)
	reducedLabel.Font = Theme.Font.BodyBold
	reducedLabel.TextColor3 = Theme.Text.Primary
	reducedLabel.TextXAlignment = Enum.TextXAlignment.Left
	reducedLabel.TextScaled = true
	reducedLabel.Text = "Reduzierte Effekte (Partikel/Screen-Shake aus)"
	reducedLabel.Position = UDim2.fromOffset(0, 0)
	reducedLabel.Parent = content
	local reducedLabelConstraint = Instance.new("UITextSizeConstraint")
	reducedLabelConstraint.MinTextSize = 12
	reducedLabelConstraint.MaxTextSize = 18
	reducedLabelConstraint.Parent = reducedLabel

	local reducedToggle = Button.new({
		Parent = content,
		Text = if Settings.GetReducedEffects() then "AN" else "AUS",
		Variant = if Settings.GetReducedEffects() then "Success" else "Ghost",
		Size = UDim2.new(1, 0, 0, 44),
		LayoutOrder = 1,
	})
	reducedToggle.Instance.Position = UDim2.fromOffset(0, 30)
	reducedToggle.Clicked:Connect(function()
		local newValue = not Settings.GetReducedEffects()
		Settings.SetReducedEffects(newValue)
		reducedToggle:SetText(if newValue then "AN" else "AUS")
	end)

	-- // Sound-Lautstärke --------------------------------------------------------
	local sfxLabel = Instance.new("TextLabel")
	sfxLabel.BackgroundTransparency = 1
	sfxLabel.Size = UDim2.new(1, 0, 0, 24)
	sfxLabel.Position = UDim2.fromOffset(0, 92)
	sfxLabel.Font = Theme.Font.BodyBold
	sfxLabel.TextColor3 = Theme.Text.Primary
	sfxLabel.TextXAlignment = Enum.TextXAlignment.Left
	sfxLabel.TextScaled = true
	sfxLabel.Text = "Sound-Lautstärke"
	sfxLabel.Parent = content
	local sfxLabelConstraint = Instance.new("UITextSizeConstraint")
	sfxLabelConstraint.MinTextSize = 12
	sfxLabelConstraint.MaxTextSize = 18
	sfxLabelConstraint.Parent = sfxLabel

	local sfxBarHost = Instance.new("Frame")
	sfxBarHost.BackgroundTransparency = 1
	sfxBarHost.Position = UDim2.fromOffset(0, 122)
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
		Size = UDim2.fromOffset(44, 32),
		LayoutOrder = 2,
	})
	sfxMinus.Instance.Position = UDim2.new(1, -96, 0, 116)
	local sfxPlus = Button.new({
		Parent = content,
		Text = "+",
		Variant = "Ghost",
		Size = UDim2.fromOffset(44, 32),
		LayoutOrder = 3,
	})
	sfxPlus.Instance.Position = UDim2.new(1, -48, 0, 116)

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
	-- HINWEIS: Es gibt aktuell noch kein Hintergrundmusik-System im Spiel.
	-- Dieser Regler speichert den Wert bereits als Attribut auf Workspace
	-- ("MusicVolume"), damit ein künftiges Musik-Modul ihn sofort nutzen
	-- kann, ohne dass dieses Einstellungsmenü nochmal angefasst werden muss.
	local musicLabel = Instance.new("TextLabel")
	musicLabel.BackgroundTransparency = 1
	musicLabel.Size = UDim2.new(1, 0, 0, 24)
	musicLabel.Position = UDim2.fromOffset(0, 168)
	musicLabel.Font = Theme.Font.BodyBold
	musicLabel.TextColor3 = Theme.Text.Primary
	musicLabel.TextXAlignment = Enum.TextXAlignment.Left
	musicLabel.TextScaled = true
	musicLabel.Text = "Musik-Lautstärke (folgt bald)"
	musicLabel.Parent = content
	local musicLabelConstraint = Instance.new("UITextSizeConstraint")
	musicLabelConstraint.MinTextSize = 12
	musicLabelConstraint.MaxTextSize = 18
	musicLabelConstraint.Parent = musicLabel

	local musicBarHost = Instance.new("Frame")
	musicBarHost.BackgroundTransparency = 1
	musicBarHost.Position = UDim2.fromOffset(0, 198)
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
		Size = UDim2.fromOffset(44, 32),
		LayoutOrder = 4,
	})
	musicMinus.Instance.Position = UDim2.new(1, -96, 0, 192)
	local musicPlus = Button.new({
		Parent = content,
		Text = "+",
		Variant = "Ghost",
		Size = UDim2.fromOffset(44, 32),
		LayoutOrder = 5,
	})
	musicPlus.Instance.Position = UDim2.new(1, -48, 0, 192)

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

	return settingsPanel
end

local function onSettingsClicked()
	local panel = buildSettingsPanel()
	panel:Open()
end

-- // Leiste aufbauen -----------------------------------------------------------------

local entries: { MenuEntry } = {
	{ Icon = "🛠️", Text = "Bauen", OnClick = onBuildClicked },
	{ Icon = "🥚", Text = "Brutbecken", OnClick = onBreedingClicked },
	{ Icon = "🎁", Text = "Mystery Egg", OnClick = onMysteryEggClicked },
	{ Icon = "🆘", Text = "Entführt", OnClick = onAbductedClicked },
	{ Icon = "⚙️", Text = "Optionen", OnClick = onSettingsClicked },
	{ Icon = "🛒", Text = "Shop", OnClick = onShopClicked },
}

for index, entry in ipairs(entries) do
	buildButton(entry, index)
end

-- // Tastaturkürzel (nur Hinweis-sichtbar auf echter PC-Tastatur, funktionieren
-- aber technisch auf jedem Gerät mit angeschlossener Tastatur) -------------------

local inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end
	if input.KeyCode == Enum.KeyCode.B then
		onBuildClicked()
	elseif input.KeyCode == Enum.KeyCode.U then
		onBreedingClicked()
	elseif input.KeyCode == Enum.KeyCode.M then
		onMysteryEggClicked()
	elseif input.KeyCode == Enum.KeyCode.N then
		onAbductedClicked()
	elseif input.KeyCode == Enum.KeyCode.O then
		onSettingsClicked()
	end
end)

-- // Gamepad: initialen Fokus setzen, damit Konsole sofort navigieren kann ---------

if Device.IsConsole() and buttonHandles[1] then
	GuiService.SelectedObject = buttonHandles[1].Instance
end

local deviceForGamepadConnection = Device.Changed:Connect(function(state)
	if state.Class == "Console" and buttonHandles[1] and not GuiService.SelectedObject then
		GuiService.SelectedObject = buttonHandles[1].Instance
	end
end)

-- // Aufräumen -------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	deviceConnection:Disconnect()
	deviceForGamepadConnection:Disconnect()
	inputConnection:Disconnect()
	unbindScale()
	for _, handle in buttonHandles do
		handle:Destroy()
	end
	if settingsPanel then
		settingsPanel:Destroy()
	end
	screenGui:Destroy()
end)
