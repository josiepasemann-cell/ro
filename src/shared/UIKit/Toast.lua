--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Toast
	Zuständigkeit:
		Gestapeltes Toast-/Benachrichtigungssystem. Position ist geräte-
		abhängig (oben-rechts auf PC/Konsole für wenig Ablenkung von
		Gamepad-Fokus, unten-zentriert auf Phone/Tablet für Daumenreich-
		weite) und reagiert live auf Device.Changed. Mehrere Toasts stapeln
		sich automatisch über UIListLayout.

	Rojo-Einhängepunkt:
		src/shared/UIKit/Toast.lua -> ReplicatedStorage.UIKit.Toast

	Nutzung: UIKit.Toast.Show({ Text = "...", Type = "Success" })
	(Init passiert automatisch beim ersten Show()-Aufruf.)
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Device = require(script.Parent:WaitForChild("Device"))
local SoundConfig = require(script.Parent:WaitForChild("SoundConfig"))
local SoundService = game:GetService("SoundService")

export type ToastType = "Info" | "Success" | "Warning" | "Error"

export type ToastProps = {
	Text: string,
	Type: ToastType?,
	Duration: number?,
}

local Toast = {}

local TYPE_COLORS: { [ToastType]: Color3 } = {
	Info = Theme.Neon.Cyan,
	Success = Theme.Neon.ToxicGreen,
	Warning = Theme.Neon.Orange,
	Error = Theme.Semantic.Danger,
}

local screenGui: ScreenGui? = nil
local stackFrame: Frame? = nil
local toastCounter = 0

local function getPlayerGui(): PlayerGui
	local player = Players.LocalPlayer
	assert(player, "UIKit.Toast kann nur clientseitig verwendet werden")
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

local function applyPosition(frame: Frame)
	if Device.ShouldUseFullscreenPanels() then
		frame.AnchorPoint = Vector2.new(0.5, 1)
		frame.Position = UDim2.new(0.5, 0, 1, -20)
		frame.Size = UDim2.new(1, -24, 0, 0)
	else
		frame.AnchorPoint = Vector2.new(1, 0)
		frame.Position = UDim2.new(1, -20, 0, 60)
		frame.Size = UDim2.new(0, 340, 0, 0)
	end
end

local function ensureInit()
	if screenGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UIKitToasts"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.IgnoreGuiInset = false
	Device.ApplySafeArea(gui)
	gui.Parent = getPlayerGui()

	local scale = Instance.new("UIScale")
	scale.Parent = gui
	Device.BindUIScale(scale)

	local stack = Instance.new("Frame")
	stack.Name = "Stack"
	stack.BackgroundTransparency = 1
	stack.AutomaticSize = Enum.AutomaticSize.Y
	applyPosition(stack)
	stack.Parent = gui

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.VerticalAlignment = Device.ShouldUseFullscreenPanels() and Enum.VerticalAlignment.Bottom
		or Enum.VerticalAlignment.Top
	list.Parent = stack

	Device.Changed:Connect(function()
		applyPosition(stack)
	end)

	screenGui = gui
	stackFrame = stack
end

function Toast.Show(props: ToastProps)
	ensureInit()
	local stack = stackFrame :: Frame
	local toastType: ToastType = props.Type or "Info"
	local color = TYPE_COLORS[toastType]

	local entry = Instance.new("Frame")
	entry.Name = "Toast"
	entry.BackgroundColor3 = Theme.Background.Panel
	entry.BackgroundTransparency = 0.05
	entry.Size = UDim2.new(1, 0, 0, 0)
	entry.AutomaticSize = Enum.AutomaticSize.Y
	toastCounter += 1
	entry.LayoutOrder = toastCounter
	entry.Parent = stack
	Theme.ApplyCorner(entry)
	local stroke = Theme.ApplyStroke(entry, color, 2)

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -24, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Position = UDim2.fromOffset(12, 8)
	label.Font = Theme.Font.Body
	label.TextColor3 = Theme.Text.Primary
	label.TextWrapped = true
	label.TextSize = 18
	label.Text = props.Text
	label.Parent = entry
	local textConstraint = Instance.new("UITextSizeConstraint")
	textConstraint.MinTextSize = 14
	textConstraint.MaxTextSize = 20
	textConstraint.Parent = label
	Theme.ApplyStroke(label, Theme.Text.Stroke, 1)

	local padding = Instance.new("UIPadding")
	padding.PaddingBottom = UDim.new(0, 8)
	padding.Parent = entry

	entry.BackgroundTransparency = 1
	stroke.Transparency = 1
	label.TextTransparency = 1
	local offsetIn = Device.ShouldUseFullscreenPanels() and UDim2.new(0, 0, 0, 20) or UDim2.new(0.15, 0, 0, 0)
	entry.Position = offsetIn

	if SoundConfig.Toast.Id ~= "" then
		local playSound = Instance.new("Sound")
		playSound.SoundId = SoundConfig.Toast.Id
		playSound.Volume = SoundConfig.Toast.Volume
		playSound.Parent = SoundService
		playSound:Play()
		game:GetService("Debris"):AddItem(playSound, 3)
	end

	TweenService:Create(entry, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		BackgroundTransparency = 0.05,
		Position = UDim2.new(0, 0, 0, 0),
	}):Play()
	TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 0.1 }):Play()
	TweenService:Create(label, TweenInfo.new(0.25), { TextTransparency = 0 }):Play()

	local duration = props.Duration or 3.5
	task.delay(duration, function()
		if not entry.Parent then
			return
		end
		local outTween = TweenService:Create(entry, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = 1,
		})
		TweenService:Create(stroke, TweenInfo.new(0.2), { Transparency = 1 }):Play()
		TweenService:Create(label, TweenInfo.new(0.2), { TextTransparency = 1 }):Play()
		outTween:Play()
		outTween.Completed:Connect(function()
			entry:Destroy()
		end)
	end)
end

return Toast
