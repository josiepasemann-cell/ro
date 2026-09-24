--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: TravelUIController (LocalScript)
	Zuständigkeit:
		Optionales Schnellreise-Panel ("Reisen") über `TravelRemotes`
		(`docs/server-features.md` Abschnitt 3.4): Hub, eigener Plot und die
		4 Zonenportale. Die physischen `ProximityPrompt`s am Hub funktionieren
		bereits unabhängig von diesem Panel (siehe dort) - dieses UI ist der
		zusätzliche Komfort-Zugang ohne Laufweg.

		Level-Sperre/"Bald verfügbar" werden HIER nur zur Anzeige vorab
		gezeigt (RequiredLevel-Werte 1/10/25/45 aus
		`assets/models/README.md` Abschnitt "hub", ZoneComingSoon-Status laut
		`docs/server-features.md` Abschnitt 7 aktuell für MidnightZone/
		HadalDepths) - reine Komfort-Hinweise, KEINE Autorität. Ein Klick
		fragt IMMER den Server neu an; jeder mögliche `TravelResult.Reason`
		wird als freundlicher Toast angezeigt, auch wenn die Anzeige vorher
		schon eine Sperre vermuten ließ (z. B. falls sich der Serverstand
		zwischenzeitlich geändert hat).

		Kurzer Bildschirm-Übergang (Fade) bei erfolgreichem Teleport.

		HARTE UIKit-REGEL (docs/ui-kit.md): jeder Button ausschließlich über
		UIKit.Button.new(...).

		Öffnen: Bridge-BindableEvent "OpenTravel" (MainMenuController-Eintrag
		"Reisen").

	Rojo-Einhängepunkt:
		src/client/TravelUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.TravelUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local TravelRemotes = require(ReplicatedStorage:WaitForChild("TravelRemotes"))
local HUDRemotes = require(ReplicatedStorage:WaitForChild("HUDRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Panel = UIKit.Panel
local Button = UIKit.Button
local Toast = UIKit.Toast

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

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

local openTravelEvent = getOrCreateBridgeEvent("OpenTravel")

-- // Zonen-Anzeige-Metadaten (rein UI, siehe Kopfkommentar) -------------------------

type ZoneMeta = {
	Id: string,
	Label: string,
	Glyph: string,
	RequiredLevel: number,
	ComingSoon: boolean,
	Color: Color3,
}

local ZONES: { ZoneMeta } = {
	{ Id = "SunZone", Label = "Sun Zone", Glyph = "☀️", RequiredLevel = 1, ComingSoon = false, Color = Theme.Neon.Yellow },
	{ Id = "TwilightZone", Label = "Twilight Zone", Glyph = "🌅", RequiredLevel = 10, ComingSoon = false, Color = Theme.Neon.Orange },
	{ Id = "MidnightZone", Label = "Midnight Zone", Glyph = "🌑", RequiredLevel = 25, ComingSoon = true, Color = Theme.Neon.Violet },
	{ Id = "HadalDepths", Label = "Hadal Depths", Glyph = "🕳️", RequiredLevel = 45, ComingSoon = true, Color = Theme.Neon.Magenta },
}

local REASON_MESSAGES: { [string]: string } = {
	OnCooldown = "Travel still on cooldown - try again in a moment.",
	NoPlot = "You have not been assigned a reef plot yet.",
	UnknownZone = "This zone is unknown.",
	LevelTooLow = "You need a higher level for that.",
	ZoneComingSoon = "This zone opens its gates soon - stay tuned!",
	NoCharacter = "Character not ready - please wait a moment.",
	NoHub = "The hub could not be found right now.",
}

local function friendlyReason(payload: { Reason: string?, RequiredLevel: number?, CurrentLevel: number? }): string
	local reason = payload.Reason
	if not reason then
		return "Travel failed. Please try again."
	end
	if reason == "LevelTooLow" and payload.RequiredLevel then
		return ("You need level %d for that (you are level %d)."):format(
			payload.RequiredLevel,
			payload.CurrentLevel or 0
		)
	end
	return REASON_MESSAGES[reason] or ("Travel failed (" .. reason .. ").")
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
	Wrapped: boolean?,
}): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = props.Size
	label.Position = props.Position or UDim2.fromOffset(0, 0)
	label.Font = props.Font or Theme.Font.Body
	label.TextColor3 = props.Color or Theme.Text.Primary
	label.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
	label.TextScaled = true
	label.TextWrapped = props.Wrapped or false
	label.Text = props.Text
	label.Parent = props.Parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = props.MinSize or 10
	constraint.MaxTextSize = props.MaxSize or 16
	constraint.Parent = label
	return label
end

-- // Bildschirm-Fade beim Teleport --------------------------------------------------

local fadeGui: ScreenGui? = nil
local fadeFrame: Frame? = nil

local function ensureFadeGui()
	if fadeGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TravelFade"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 95
	gui.Parent = playerGui

	local frame = Instance.new("Frame")
	frame.Name = "Fade"
	frame.BackgroundColor3 = Color3.new(0, 0, 0)
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.ZIndex = 500
	frame.Parent = gui

	fadeGui = gui
	fadeFrame = frame
end

local function playTravelFade()
	ensureFadeGui()
	local frame = fadeFrame :: Frame
	local fadeIn = TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0,
	})
	fadeIn:Play()
	fadeIn.Completed:Connect(function()
		task.delay(0.22, function()
			TweenService:Create(frame, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				BackgroundTransparency = 1,
			}):Play()
		end)
	end)
end

-- // Level-Anzeige (nur Komfort-Vorschau, siehe Kopfkommentar) -----------------------

local currentLevel = 1
local levelListeners: { () -> () } = {}

local function refreshLevelListeners()
	for _, fn in levelListeners do
		fn()
	end
end

task.spawn(function()
	local ok, hudState = pcall(function()
		return HUDRemotes.GetHUDState:InvokeServer()
	end)
	if ok and type(hudState) == "table" and type(hudState.Level) == "number" then
		currentLevel = hudState.Level
		refreshLevelListeners()
	end
end)

HUDRemotes.HUDStateChanged.OnClientEvent:Connect(function(payload: { Level: number? })
	if type(payload) == "table" and type(payload.Level) == "number" then
		currentLevel = payload.Level
		refreshLevelListeners()
	end
end)

-- // Panel -----------------------------------------------------------------------

local panelHandle: any = nil

local function buildDestinationCard(parent: Instance, layoutOrder: number, label: string, glyph: string, description: string, color: Color3, onTravel: () -> ()): Frame
	local card = Instance.new("Frame")
	card.Name = "Card_" .. label
	card.BackgroundColor3 = Theme.Background.PanelLight
	card.Size = UDim2.new(1, 0, 0, 88)
	card.LayoutOrder = layoutOrder
	Theme.ApplyCorner(card, UDim.new(0, 14))
	local stroke = Theme.ApplyStroke(card, color, 2)
	stroke.Transparency = 0.35
	Theme.ApplyGradient(card, { Theme.Background.PanelLight, Theme.Background.Panel }, 100)
	card.Parent = parent

	makeLabel({
		Parent = card,
		Text = glyph,
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.fromOffset(10, 10),
		Font = Theme.Font.Header,
		MinSize = 22,
		MaxSize = 34,
		XAlign = Enum.TextXAlignment.Center,
	})

	makeLabel({
		Parent = card,
		Text = label,
		Size = UDim2.new(1, -220, 0, 26),
		Position = UDim2.fromOffset(66, 10),
		Font = Theme.Font.BodyBold,
		MinSize = 14,
		MaxSize = 19,
	})

	makeLabel({
		Parent = card,
		Text = description,
		Size = UDim2.new(1, -220, 0, 40),
		Position = UDim2.fromOffset(66, 36),
		Color = Theme.Text.Secondary,
		MinSize = 10,
		MaxSize = 13,
		Wrapped = true,
	})

	local travelButton = Button.new({
		Parent = card,
		Text = "Travel",
		Variant = "Primary",
		Important = true,
		Size = UDim2.fromOffset(140, 44),
	})
	travelButton.Instance.AnchorPoint = Vector2.new(1, 0.5)
	travelButton.Instance.Position = UDim2.new(1, -12, 0.5, 0)
	travelButton.Clicked:Connect(onTravel)

	return card
end

local function buildZoneCard(parent: Instance, layoutOrder: number, zone: ZoneMeta): Frame
	local card = Instance.new("Frame")
	card.Name = "Zone_" .. zone.Id
	card.BackgroundColor3 = Theme.Background.PanelLight
	card.Size = UDim2.new(1, 0, 0, 96)
	card.LayoutOrder = layoutOrder
	Theme.ApplyCorner(card, UDim.new(0, 14))
	local stroke = Theme.ApplyStroke(card, zone.Color, 2)
	stroke.Transparency = 0.35
	Theme.ApplyGradient(card, { Theme.Background.PanelLight, Theme.Background.Panel }, 100)
	card.Parent = parent

	makeLabel({
		Parent = card,
		Text = zone.Glyph,
		Size = UDim2.fromOffset(48, 48),
		Position = UDim2.fromOffset(10, 10),
		Font = Theme.Font.Header,
		MinSize = 22,
		MaxSize = 34,
		XAlign = Enum.TextXAlignment.Center,
	})

	makeLabel({
		Parent = card,
		Text = zone.Label,
		Size = UDim2.new(1, -220, 0, 24),
		Position = UDim2.fromOffset(66, 8),
		Font = Theme.Font.BodyBold,
		MinSize = 13,
		MaxSize = 18,
	})

	local statusLabel = makeLabel({
		Parent = card,
		Text = "",
		Size = UDim2.new(1, -220, 0, 20),
		Position = UDim2.fromOffset(66, 32),
		Color = Theme.Semantic.Warning,
		MinSize = 9,
		MaxSize = 13,
	})

	local requirementLabel = makeLabel({
		Parent = card,
		Text = "Requires Level " .. zone.RequiredLevel,
		Size = UDim2.new(1, -220, 0, 20),
		Position = UDim2.fromOffset(66, 54),
		Color = Theme.Text.Secondary,
		MinSize = 9,
		MaxSize = 13,
	})

	local travelButton = Button.new({
		Parent = card,
		Text = "Travel",
		Variant = "Primary",
		Size = UDim2.fromOffset(120, 44),
	})
	travelButton.Instance.AnchorPoint = Vector2.new(1, 0.5)
	travelButton.Instance.Position = UDim2.new(1, -12, 0.5, 0)
	travelButton.Clicked:Connect(function()
		TravelRemotes.RequestTravelToZone:FireServer(zone.Id)
	end)

	local function refreshStatus()
		if zone.ComingSoon then
			statusLabel.Text = "🔒 Coming soon"
			statusLabel.TextColor3 = Theme.Semantic.Warning
		elseif currentLevel < zone.RequiredLevel then
			statusLabel.Text = "🔒 Requires level " .. zone.RequiredLevel
			statusLabel.TextColor3 = Theme.Semantic.Danger
		else
			statusLabel.Text = "✅ Unlocked"
			statusLabel.TextColor3 = Theme.Neon.ToxicGreen
		end
	end
	refreshStatus()
	table.insert(levelListeners, refreshStatus)

	return card
end

local function buildPanel()
	if panelHandle then
		return
	end

	panelHandle = Panel.new({
		Title = "Travel",
		Closable = true,
		CenteredSize = UDim2.fromOffset(620, 680),
	})

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroller"
	scroller.BackgroundTransparency = 1
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = Theme.Neon.Cyan
	scroller.BorderSizePixel = 0
	scroller.Parent = panelHandle.Content

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 10)
	list.Parent = scroller

	buildDestinationCard(scroller, 1, "Tidal Market (Hub)", "🏝️", "Back to the central market.", Theme.Neon.Cyan, function()
		TravelRemotes.RequestTravelToHub:FireServer()
	end)

	buildDestinationCard(scroller, 2, "My Reef Plot", "🪸", "Straight to your own habitat.", Theme.Neon.ToxicGreen, function()
		TravelRemotes.RequestTravelToPlot:FireServer()
	end)

	local sectionLabel = makeLabel({
		Parent = scroller,
		Text = "Zone Portals",
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Font.Header,
		Color = Theme.Text.Primary,
		MinSize = 14,
		MaxSize = 20,
	})
	sectionLabel.LayoutOrder = 3

	for index, zone in ipairs(ZONES) do
		buildZoneCard(scroller, 3 + index, zone)
	end
end

local function openTravel()
	buildPanel()
	panelHandle:Open()
end

-- // Remote-Verdrahtung --------------------------------------------------------

TravelRemotes.TravelResult.OnClientEvent:Connect(function(payload: {
	Success: boolean,
	Reason: string?,
	Destination: string?,
	RequiredLevel: number?,
	CurrentLevel: number?,
})
	if payload.Success then
		playTravelFade()
		Toast.Show({ Text = "Arrived!", Type = "Success", Duration = 2.5 })
	else
		Toast.Show({ Text = friendlyReason(payload), Type = "Warning", Duration = 4 })
	end
end)

local bridgeConnection = openTravelEvent.Event:Connect(openTravel)

-- // Aufräumen ------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	bridgeConnection:Disconnect()
	table.clear(levelListeners)
	if panelHandle then
		panelHandle:Destroy()
	end
	if fadeGui then
		fadeGui:Destroy()
	end
end)
