--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Button
	Zuständigkeit:
		Einzige Fabrik für ALLE klickbaren Buttons im Spiel. Jeder über
		Button.new() erzeugte Button bekommt automatisch:
			- Hover-Vergrößerung + Glow (nur auf Geräten mit echtem Hover,
			  d. h. Maus; auf Touch übernimmt stattdessen der Press-FX
			  dieselbe Rolle)
			- Press-Squash (TweenService, funktioniert für Maus/Touch/
			  Gamepad-Bestätigung gleichermaßen)
			- Klick-Partikel-Burst (gepoolt über UIKit.ParticlePool)
			- Ripple-Effekt vom Klickpunkt aus
			- Klick-Sound (SoundConfig.Click)
			- optionales Idle-Pulsieren für wichtige Buttons (z. B. "Kaufen")
			- Disabled-Zustand
			- Gamepad-Navigation (Selectable + sichtbares SelectionImageObject)
			- GARANTIERTE Responsivität: TextScaled mit Min/Max
			  (UITextSizeConstraint), Mindest-Touch-Zielgröße ~44px als
			  ECHTE Pixel-Untergrenze (UISizeConstraint auf AbsoluteSize,
			  wirkt unabhängig von UIScale-Vorfahren), volle Breite über
			  relative UDim2-Größen statt harter Pixelwerte.
		Respektiert UIKit.Settings.ShouldSkipFX() ("Reduzierte Effekte").

		HARTE REGEL (siehe docs/ui-kit.md): Es dürfen im gesamten Projekt
		KEINE TextButton/ImageButton-Instanzen außerhalb dieser Fabrik für
		interaktive Buttons gebaut werden - nur so ist FX/Responsivität/
		Gamepad-Support garantiert konsistent.

	Rojo-Einhängepunkt:
		src/shared/UIKit/Button.lua -> ReplicatedStorage.UIKit.Button
]]

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Device = require(script.Parent:WaitForChild("Device"))
local Settings = require(script.Parent:WaitForChild("Settings"))
local SoundConfig = require(script.Parent:WaitForChild("SoundConfig"))
local ParticlePool = require(script.Parent:WaitForChild("ParticlePool"))
local Signal = require(script.Parent:WaitForChild("Signal"))

export type ButtonVariant = "Primary" | "Secondary" | "Success" | "Danger" | "Ghost"

export type ButtonProps = {
	Parent: Instance?,
	Text: string,
	Icon: string?,
	Variant: ButtonVariant?,
	Size: UDim2?,
	LayoutOrder: number?,
	Important: boolean?,
	Disabled: boolean?,
	OnClick: ((handle: any) -> ())?,
}

export type ButtonHandle = {
	Instance: TextButton,
	Clicked: any,
	SetDisabled: (self: ButtonHandle, disabled: boolean) -> (),
	SetText: (self: ButtonHandle, text: string) -> (),
	Destroy: (self: ButtonHandle) -> (),
}

local Button = {}

-- // Mindesttextgrößen für TextScaled + UITextSizeConstraint -----------------
local MIN_TEXT_SIZE = 14
local MAX_TEXT_SIZE = 30
local DEFAULT_HEIGHT = 44

local variantColors: { [ButtonVariant]: { Color3 } } = {
	Primary = { Theme.Neon.Cyan, Theme.Neon.Violet },
	Secondary = { Theme.Neon.Violet, Theme.Neon.Magenta },
	Success = { Theme.Neon.ToxicGreen, Theme.Neon.Cyan },
	Danger = { Theme.Semantic.Danger, Theme.Neon.Magenta },
	Ghost = { Theme.Background.PanelLight, Theme.Background.Panel },
}

local function pickTextColor(variant: ButtonVariant): Color3
	if variant == "Ghost" then
		return Theme.Text.Primary
	end
	return Theme.Text.OnNeon
end

local function playSound(definition: { Id: string, Volume: number, PitchRange: NumberRange? })
	local sound = Instance.new("Sound")
	sound.SoundId = definition.Id
	sound.Volume = definition.Volume
	if definition.PitchRange then
		sound.PlaybackSpeed = definition.PitchRange.Min
			+ math.random() * (definition.PitchRange.Max - definition.PitchRange.Min)
	end
	sound.Parent = SoundService
	sound:Play()
	game:GetService("Debris"):AddItem(sound, 3)
end

local function spawnBurst(button: TextButton, originPosition: Vector2)
	if Settings.ShouldSkipFX() then
		return
	end
	local burstHost = button:FindFirstChild("FXHost") :: Frame?
	if not burstHost then
		return
	end
	local absPos = button.AbsolutePosition
	local localOrigin = originPosition - absPos

	local particleCount = 8
	for index = 1, particleCount do
		local particle = ParticlePool.Acquire(burstHost)
		particle.Position = UDim2.fromOffset(localOrigin.X, localOrigin.Y)
		particle.Size = UDim2.fromOffset(6, 6)
		particle.ImageColor3 = variantColors.Primary[1]
		particle.ImageTransparency = 0

		local angle = (index / particleCount) * math.pi * 2 + math.random() * 0.4
		local distance = 26 + math.random() * 18
		local targetOffset = Vector2.new(math.cos(angle), math.sin(angle)) * distance

		local tween = TweenService:Create(
			particle,
			TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{
				Position = UDim2.fromOffset(localOrigin.X + targetOffset.X, localOrigin.Y + targetOffset.Y),
				ImageTransparency = 1,
				Rotation = math.random(-90, 90),
			}
		)
		tween:Play()
		tween.Completed:Connect(function()
			ParticlePool.Release(particle)
		end)
	end
end

local function spawnRipple(button: TextButton, originPosition: Vector2)
	if Settings.ShouldSkipFX() then
		return
	end
	local burstHost = button:FindFirstChild("FXHost") :: Frame?
	if not burstHost then
		return
	end
	local absPos = button.AbsolutePosition
	local localOrigin = originPosition - absPos

	local ripple = Instance.new("Frame")
	ripple.Name = "Ripple"
	ripple.AnchorPoint = Vector2.new(0.5, 0.5)
	ripple.Position = UDim2.fromOffset(localOrigin.X, localOrigin.Y)
	ripple.Size = UDim2.fromOffset(0, 0)
	ripple.BackgroundColor3 = Color3.new(1, 1, 1)
	ripple.BackgroundTransparency = 0.55
	ripple.BorderSizePixel = 0
	ripple.ZIndex = 40
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = ripple
	ripple.Parent = burstHost

	local maxDiameter = math.max(button.AbsoluteSize.X, button.AbsoluteSize.Y) * 1.8
	local tween = TweenService:Create(
		ripple,
		TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = UDim2.fromOffset(maxDiameter, maxDiameter), BackgroundTransparency = 1 }
	)
	tween:Play()
	tween.Completed:Connect(function()
		ripple:Destroy()
	end)
end

function Button.new(props: ButtonProps): ButtonHandle
	local variant: ButtonVariant = props.Variant or "Primary"
	local colors = variantColors[variant]

	local root = Instance.new("TextButton")
	root.Name = "UIKitButton"
	root.AutoButtonColor = false
	root.Text = ""
	root.BackgroundColor3 = colors[1]
	root.Size = props.Size or UDim2.new(1, 0, 0, DEFAULT_HEIGHT)
	root.LayoutOrder = props.LayoutOrder or 0
	root.ClipsDescendants = false
	root.Active = not (props.Disabled or false)
	root.Selectable = true
	root.AutoLocalize = false
	root.Parent = props.Parent

	Theme.ApplyCorner(root)
	local gradient = Theme.ApplyGradient(root, colors, 100)
	local stroke = Theme.ApplyStroke(root, colors[#colors], 2)

	-- Robuste Mindestgröße: UISizeConstraint arbeitet auf AbsoluteSize,
	-- wirkt also als ECHTE Pixel-Untergrenze unabhängig davon, was
	-- UIScale-Vorfahren mit der nominalen Size machen.
	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MinSize = Vector2.new(0, 0)
	sizeConstraint.MaxSize = Vector2.new(math.huge, math.huge)
	sizeConstraint.Parent = root

	local function applyTouchConstraint()
		if Device.IsTouch() then
			sizeConstraint.MinSize = Vector2.new(Device.MinTouchSize, Device.MinTouchSize)
		else
			sizeConstraint.MinSize = Vector2.new(0, 0)
		end
	end
	applyTouchConstraint()

	-- FX-Host: separater Frame über dem Inhalt für Partikel/Ripple, damit
	-- diese nicht die TextButton-Textausrichtung stören.
	local fxHost = Instance.new("Frame")
	fxHost.Name = "FXHost"
	fxHost.BackgroundTransparency = 1
	fxHost.Size = UDim2.fromScale(1, 1)
	fxHost.ZIndex = 5
	fxHost.ClipsDescendants = false
	fxHost.Parent = root

	local label = Instance.new("TextLabel")
	label.Name = "Label"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -16, 1, -8)
	label.Position = UDim2.fromOffset(8, 4)
	label.Font = Theme.Font.BodyBold
	label.Text = props.Text
	label.TextColor3 = pickTextColor(variant)
	label.TextScaled = true
	label.RichText = false
	label.ZIndex = 6
	label.Parent = root

	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = MIN_TEXT_SIZE
	textConstraint.MaxTextSize = MAX_TEXT_SIZE
	textConstraint.Parent = label

	Theme.ApplyStroke(label, Theme.Text.Stroke, 1.25)

	if props.Icon then
		local icon = Instance.new("ImageLabel")
		icon.Name = "Icon"
		icon.BackgroundTransparency = 1
		icon.Image = props.Icon :: string
		icon.Size = UDim2.new(0, 22, 0, 22)
		icon.Position = UDim2.new(0, 8, 0.5, -11)
		icon.ZIndex = 6
		icon.Parent = root
		label.Position = UDim2.fromOffset(36, 4)
		label.Size = UDim2.new(1, -44, 1, -8)
	end

	-- Sichtbare Gamepad-Auswahl-Markierung.
	local selectionFrame = Instance.new("Frame")
	selectionFrame.Name = "SelectionGlow"
	selectionFrame.BackgroundTransparency = 1
	selectionFrame.Size = UDim2.fromScale(1, 1)
	Theme.ApplyCorner(selectionFrame)
	local selectionStroke = Theme.ApplyStroke(selectionFrame, Theme.Neon.Yellow, 3)
	selectionStroke.Transparency = 0.1
	selectionFrame.Parent = root
	root.SelectionImageObject = selectionFrame

	local connections: { RBXScriptConnection } = {}
	local disabled = props.Disabled or false
	local isImportant = props.Important or false
	local pulseThread: thread? = nil

	local baseScale = 1
	local hoverScale = 1.06
	local pressScale = 0.93

	local uiScale = Instance.new("UIScale")
	uiScale.Scale = baseScale
	uiScale.Parent = root

	local function tweenScale(target: number, duration: number?)
		local tween = TweenService:Create(
			uiScale,
			TweenInfo.new(duration or 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ Scale = target }
		)
		tween:Play()
	end

	local function tweenStroke(brighten: boolean)
		local target = brighten and 0 or 0.15
		local tween = TweenService:Create(stroke, TweenInfo.new(0.15), { Transparency = target })
		tween:Play()
	end

	local function stopPulse()
		if pulseThread then
			task.cancel(pulseThread)
			pulseThread = nil
			tweenScale(baseScale, 0.15)
		end
	end

	local function startPulse()
		if pulseThread or Settings.ShouldSkipFX() or not isImportant or disabled then
			return
		end
		pulseThread = task.spawn(function()
			while true do
				tweenScale(1.045, 0.6)
				task.wait(0.6)
				tweenScale(1.0, 0.6)
				task.wait(0.6)
			end
		end)
	end

	local function refreshPulseState()
		if isImportant and not disabled and not Settings.ShouldSkipFX() then
			startPulse()
		else
			stopPulse()
		end
	end

	local clicked = Signal.new()

	local function doPress(inputPosition: Vector2?)
		if disabled then
			return
		end
		stopPulse()
		tweenScale(pressScale, 0.06)
		task.delay(0.06, function()
			if root.Parent then
				tweenScale(baseScale, 0.12)
				refreshPulseState()
			end
		end)
		local origin = inputPosition or (root.AbsolutePosition + root.AbsoluteSize / 2)
		spawnBurst(root, origin)
		spawnRipple(root, origin)
		playSound(SoundConfig.Click)
	end

	table.insert(
		connections,
		root.Activated:Connect(function(inputObject: InputObject)
			if disabled then
				return
			end
			local position = Vector2.new(inputObject.Position.X, inputObject.Position.Y)
			doPress(if position.X == 0 and position.Y == 0 then nil else position)
			if props.OnClick then
				props.OnClick(nil)
			end
			clicked:Fire()
		end)
	)

	-- Hover-FX nur dort, wo tatsächlich ein Hover-Konzept existiert (Maus).
	table.insert(
		connections,
		root.MouseEnter:Connect(function()
			if disabled or Device.IsTouch() then
				return
			end
			stopPulse()
			tweenScale(hoverScale, 0.14)
			tweenStroke(true)
			playSound(SoundConfig.Hover)
		end)
	)
	table.insert(
		connections,
		root.MouseLeave:Connect(function()
			if disabled then
				return
			end
			tweenScale(baseScale, 0.14)
			tweenStroke(false)
			refreshPulseState()
		end)
	)

	-- Press-FX für Maus-Down/Touch (funktioniert auch ohne Hover-Phase).
	table.insert(
		connections,
		root.InputBegan:Connect(function(input: InputObject)
			if disabled then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				tweenScale(pressScale, 0.06)
				tweenStroke(true)
			end
		end)
	)
	table.insert(
		connections,
		root.InputEnded:Connect(function(input: InputObject)
			if disabled then
				return
			end
			if
				input.UserInputType == Enum.UserInputType.MouseButton1
				or input.UserInputType == Enum.UserInputType.Touch
			then
				local hoverActive = not Device.IsTouch() and input.UserInputType == Enum.UserInputType.MouseButton1
				tweenScale(hoverActive and hoverScale or baseScale, 0.12)
				tweenStroke(hoverActive)
				refreshPulseState()
			end
		end)
	)

	-- Gamepad-Auswahl-Feedback.
	table.insert(
		connections,
		root.SelectionGained:Connect(function()
			if disabled then
				return
			end
			stopPulse()
			tweenScale(hoverScale, 0.14)
			tweenStroke(true)
		end)
	)
	table.insert(
		connections,
		root.SelectionLost:Connect(function()
			tweenScale(baseScale, 0.14)
			tweenStroke(false)
			refreshPulseState()
		end)
	)

	local deviceConnection = Device.Changed:Connect(applyTouchConstraint)
	local settingsConnection = Settings.Changed:Connect(function(key: string)
		if key == "ReducedEffects" then
			refreshPulseState()
		end
	end)

	local function applyDisabledVisual()
		root.AutoButtonColor = false
		if disabled then
			root.Active = false
			root.Selectable = false
			gradient.Color = ColorSequence.new(Theme.Background.PanelLight, Theme.Background.Panel)
			label.TextTransparency = 0.45
			stroke.Transparency = 0.7
			stopPulse()
		else
			root.Active = true
			root.Selectable = true
			gradient.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, colors[1]),
				ColorSequenceKeypoint.new(1, colors[#colors]),
			})
			label.TextTransparency = 0
			stroke.Transparency = 0.15
			refreshPulseState()
		end
	end
	applyDisabledVisual()
	refreshPulseState()

	local handle = {} :: ButtonHandle
	handle.Instance = root
	handle.Clicked = clicked

	handle.SetDisabled = function(_self, value: boolean)
		disabled = value
		applyDisabledVisual()
	end

	handle.SetText = function(_self, text: string)
		label.Text = text
	end

	handle.Destroy = function(_self)
		stopPulse()
		deviceConnection:Disconnect()
		settingsConnection:Disconnect()
		for _, connection in connections do
			connection:Disconnect()
		end
		clicked:DisconnectAll()
		root:Destroy()
	end

	return handle
end

return Button
