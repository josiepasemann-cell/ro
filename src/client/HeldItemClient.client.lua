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

local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

local DROP_ACTION_NAME = "Abyssara_DropHeldItem"
local HELD_TAG = "HeldItem"

-- // Minimales, isoliertes HUD -------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HeldItemHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = playerGui

local frame = Instance.new("Frame")
frame.Name = "HeldItemFrame"
frame.AnchorPoint = Vector2.new(0.5, 1)
frame.Position = UDim2.new(0.5, 0, 1, -150)
frame.Size = UDim2.new(0, 280, 0, 44)
frame.BackgroundColor3 = Color3.fromRGB(8, 28, 38)
frame.BackgroundTransparency = 0.2
frame.BorderSizePixel = 0
frame.Parent = screenGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = frame

local stroke = Instance.new("UIStroke")
stroke.Color = Color3.fromRGB(120, 220, 235)
stroke.Transparency = 0.5
stroke.Thickness = 1
stroke.Parent = frame

local label = Instance.new("TextLabel")
label.Name = "HeldItemLabel"
label.BackgroundTransparency = 1
label.Size = UDim2.new(1, -16, 1, 0)
label.Position = UDim2.new(0, 8, 0, 0)
label.Font = Enum.Font.GothamMedium
label.TextColor3 = Color3.fromRGB(190, 245, 255)
label.TextScaled = true
label.TextXAlignment = Enum.TextXAlignment.Left
label.TextYAlignment = Enum.TextYAlignment.Center
label.Text = ""
label.Parent = frame

local function setHudVisible(visible: boolean, displayName: string?)
	screenGui.Enabled = visible
	if visible then
		label.Text = ("Hältst: %s   (G zum Ablegen)"):format(displayName or "Item")
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
	ContextActionService:SetTitle(DROP_ACTION_NAME, "Ablegen")
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

print("[Abyssara] HeldItemClient bereit.")
