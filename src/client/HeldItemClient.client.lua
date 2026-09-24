--[[
	Abyssara – Deep Tide Tycoon
	Skript: HeldItemClient (LocalScript)
	Zuständigkeit:
		Rein kosmetisches Client-Feedback zum "Items in der Hand"-System:
			1) Minimales, isoliertes HUD (kein UI-Kit! - siehe Auftrag, ein
			   paralleles UI-Kit-System entsteht gerade in src/shared/UIKit
			   und wird dieses Mini-HUD später ersetzen können, ohne dass
			   Server-Logik angefasst werden muss), zeigt den Namen des
			   aktuell gehaltenen Items.
			2) "Ablegen"-Aktion über ContextActionService: Taste G auf PC,
			   automatischer Touch-Button auf Mobile, Gamepad-Button X -
			   alle drei automatisch durch EINE BindAction-Registrierung
			   (createTouchButton = true), kein plattformspezifischer
			   Sondercode nötig.
			3) Dezenter Glow-Effekt (PointLight + ParticleEmitter) an JEDEM
			   sichtbar gehaltenen Item (auch von anderen Spielern, nicht
			   nur dem lokalen) - erkannt über den `CollectionService`-Tag
			   "HeldItem", den HeldItemService serverseitig setzt.

		Enthält KEINE Gameplay-Logik/Validierung - alles Serverseitig
		autoritativ (HeldItemService/PickupSpawner). Dieses Skript kann im
		schlimmsten Fall nur die eigene Anzeige verfälschen, nie den
		tatsächlichen Spielzustand.

		GEÄNDERT (UIKit-Umstellung): Nutzt jetzt UIKit.Theme für Farben/
		Schrift (konsistent mit dem restlichen UIKit) und dockt
		geräteabhängig knapp ÜBER der MainMenuController-Menüleiste an,
		damit sich beide auf keinem Gerät überlappen. Der "Ablegen"-Button
		selbst bleibt bewusst ein nativer, von ContextActionService via
		createTouchButton=true erzeugter Touch-Button (kein
		TextButton/ImageButton, das wir selbst instanziieren - die
		UIKit-Button-Pflicht gilt für selbst gebaute klickbare UI-Elemente,
		nicht für dieses Roblox-Systemwidget).

	Rojo-Einhängepunkt:
		src/client/HeldItemClient.client.lua -> StarterPlayer.StarterPlayerScripts.HeldItemClient
		(".client.lua"-Suffix signalisiert Rojo, hieraus ein LocalScript zu
		machen)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")

local HeldItemRemotes = require(ReplicatedStorage:WaitForChild("HeldItemRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local DROP_ACTION_NAME = "Abyssara_DropHeldItem"
local HELD_TAG = "HeldItem"

-- // Minimales HUD (Theme-gestylt, geräteabhängig positioniert) --------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HeldItemHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 16
screenGui.Enabled = false
Device.ApplySafeArea(screenGui)
screenGui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = screenGui
local unbindScale = Device.BindUIScale(uiScale)

local frame = Instance.new("Frame")
frame.Name = "HeldItemFrame"
frame.AnchorPoint = Vector2.new(0.5, 1)
frame.Size = UDim2.new(0, 300, 0, 48)
frame.BackgroundColor3 = Theme.Background.Panel
frame.BackgroundTransparency = 0.15
frame.BorderSizePixel = 0
frame.Parent = screenGui
Theme.ApplyCorner(frame, UDim.new(0, 10))
local stroke = Theme.ApplyStroke(frame, Theme.Neon.Cyan, 1.5)
stroke.Transparency = 0.4

-- Knapp über der MainMenuController-Menüleiste andocken (siehe dort für die
-- genauen Höhen: ~84px Phone-Leiste, ~68px Desktop/Konsolen-Leiste).
local function applyFramePosition()
	if Device.ShouldUseFullscreenPanels() then
		frame.Position = UDim2.new(0.5, 0, 1, -118)
	else
		frame.Position = UDim2.new(0.5, 0, 1, -108)
	end
end
applyFramePosition()
local frameDeviceConnection = Device.Changed:Connect(applyFramePosition)

local label = Instance.new("TextLabel")
label.Name = "HeldItemLabel"
label.BackgroundTransparency = 1
label.Size = UDim2.new(1, -16, 1, 0)
label.Position = UDim2.new(0, 8, 0, 0)
label.Font = Theme.Font.Body
label.TextColor3 = Theme.Text.Primary
label.TextScaled = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Center
label.Text = ""
label.Parent = frame
local labelConstraint = Instance.new("UITextSizeConstraint")
labelConstraint.MinTextSize = 12
labelConstraint.MaxTextSize = 18
labelConstraint.Parent = label

local function setHudVisible(visible: boolean, displayName: string?)
	screenGui.Enabled = visible
	if visible then
		label.Text = ("Holding: %s   (G to drop)"):format(displayName or "Item")
	end
end

-- // "Ablegen"-Aktion: G / Touch-Button / Gamepad -----------------------------

local function onDropAction(_actionName: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	HeldItemRemotes.RequestDropHeld:FireServer()
	return Enum.ContextActionResult.Sink
end

local function bindDropAction()
	-- `createTouchButton = true` lässt Roblox automatisch einen Touch-Button
	-- auf Mobile-Geräten einblenden - kein separater Mobile-Sondercode nötig
	-- (siehe Auftrag: "funktioniert auf Handy, PC, Konsole gleich gut").
	ContextActionService:BindAction(DROP_ACTION_NAME, onDropAction, true, Enum.KeyCode.G, Enum.KeyCode.ButtonX)
	ContextActionService:SetTitle(DROP_ACTION_NAME, "Drop")
end

local function unbindDropAction()
	ContextActionService:UnbindAction(DROP_ACTION_NAME)
end

HeldItemRemotes.HeldItemChanged.OnClientEvent:Connect(function(state: { Holding: boolean, DisplayName: string? })
	if state and state.Holding then
		setHudVisible(true, state.DisplayName)
		bindDropAction()
	else
		setHudVisible(false)
		unbindDropAction()
	end
end)

-- // Glow-Effekt an jedem sichtbar gehaltenen Item -----------------------------
-- Rein dekorativ, läuft für JEDEN CollectionService-"HeldItem"-Tag (auch bei
-- anderen Spielern) - HeldItemService setzt/entfernt diesen Tag serverseitig
-- bei HoldItem/DropHeld/ConsumeHeld, dieses Skript muss dafür keine eigene
-- Zustandslogik führen.

local GLOW_PARTICLE_COLOR = ColorSequence.new(Color3.fromRGB(150, 235, 255))
local GLOW_TRANSPARENCY = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.2),
	NumberSequenceKeypoint.new(1, 1),
})

local function applyGlow(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not part or part:FindFirstChild("HeldItemGlowLight") then
		return
	end

	local light = Instance.new("PointLight")
	light.Name = "HeldItemGlowLight"
	light.Color = Color3.fromRGB(150, 235, 255)
	light.Range = 8
	light.Brightness = 2
	light.Parent = part

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "HeldItemGlowParticles"
	emitter.Color = GLOW_PARTICLE_COLOR
	emitter.Size = NumberSequence.new(0.18)
	emitter.Lifetime = NumberRange.new(0.6, 1.1)
	emitter.Rate = 6
	emitter.Speed = NumberRange.new(0.4, 0.9)
	emitter.Transparency = GLOW_TRANSPARENCY
	emitter.Parent = part
end

local function removeGlow(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local part = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not part then
		return
	end
	local light = part:FindFirstChild("HeldItemGlowLight")
	if light then
		light:Destroy()
	end
	local emitter = part:FindFirstChild("HeldItemGlowParticles")
	if emitter then
		emitter:Destroy()
	end
end

for _, existing in ipairs(CollectionService:GetTagged(HELD_TAG)) do
	applyGlow(existing)
end

CollectionService:GetInstanceAddedSignal(HELD_TAG):Connect(applyGlow)
CollectionService:GetInstanceRemovedSignal(HELD_TAG):Connect(removeGlow)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= LocalPlayer then
		return
	end
	frameDeviceConnection:Disconnect()
	unbindScale()
	unbindDropAction()
	screenGui:Destroy()
end)

print("[Abyssara] HeldItemClient ready.")
