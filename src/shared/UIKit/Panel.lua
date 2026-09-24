--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Panel
	Zuständigkeit:
		Fenster/Panel-Baustein mit Einblend-Animation, Schließen-Button
		(aus der Button-Factory) und geräte-abhängigem Layout: Vollbild auf
		Phone, zentriertes Fenster auf Tablet/PC/Konsole (via
		UIKit.Layout.FullscreenOrCentered). Bindet außerdem den zentralen
		Device-UIScale-Skalierungsfaktor EINMAL pro Panel (statt pro
		Kind-Widget), sodass alle Kinder (Buttons, Labels, ...) automatisch
		mitskalieren.

	Rojo-Einhängepunkt:
		src/shared/UIKit/Panel.lua -> ReplicatedStorage.UIKit.Panel
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Device = require(script.Parent:WaitForChild("Device"))
local Layout = require(script.Parent:WaitForChild("Layout"))
local Button = require(script.Parent:WaitForChild("Button"))
local Signal = require(script.Parent:WaitForChild("Signal"))

export type PanelProps = {
	Title: string,
	ScreenGuiName: string?,
	Closable: boolean?,
	CenteredSize: UDim2?,
	OnClose: (() -> ())?,
	DisplayOrder: number?,
}

export type PanelHandle = {
	ScreenGui: ScreenGui,
	Root: Frame,
	Content: Frame,
	Closed: any,
	Open: (self: PanelHandle) -> (),
	Close: (self: PanelHandle) -> (),
	SetTitle: (self: PanelHandle, title: string) -> (),
	Destroy: (self: PanelHandle) -> (),
}

local Panel = {}

local function getPlayerGui(): PlayerGui
	local player = Players.LocalPlayer
	assert(player, "UIKit.Panel kann nur clientseitig verwendet werden")
	return player:WaitForChild("PlayerGui") :: PlayerGui
end

function Panel.new(props: PanelProps): PanelHandle
	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = props.ScreenGuiName or ("UIKitPanel_" .. props.Title:gsub("%s+", ""))
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = false
	screenGui.DisplayOrder = props.DisplayOrder or 10
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	Device.ApplySafeArea(screenGui)
	screenGui.Parent = getPlayerGui()

	-- Ein zentraler UIScale-Bindepunkt pro Panel - alle Kinder skalieren
	-- automatisch mit der erkannten Geräteklasse/Viewportgröße mit.
	local deviceScale = Instance.new("UIScale")
	deviceScale.Parent = screenGui
	local unbindScale = Device.BindUIScale(deviceScale)

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 1
	dim.Parent = screenGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = Theme.Background.Panel
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = 2
	root.Parent = screenGui
	Theme.ApplyCorner(root, UDim.new(0, 18))
	local stroke = Theme.ApplyStroke(root, Theme.Neon.Cyan, 2)
	stroke.Transparency = 0.35
	Theme.ApplyGradient(root, { Theme.Background.Panel, Theme.Background.Deepest }, 90)

	local unbindLayout = Layout.FullscreenOrCentered(root, {
		CenteredSize = props.CenteredSize,
	})

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 52)
	header.ZIndex = 3
	header.Parent = root

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -64, 1, 0)
	titleLabel.Position = UDim2.fromOffset(20, 0)
	titleLabel.Font = Theme.Font.Header
	titleLabel.Text = props.Title
	titleLabel.TextColor3 = Theme.Text.Primary
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.TextScaled = true
	titleLabel.ZIndex = 3
	titleLabel.Parent = header
	local titleConstraint = Instance.new("UITextSizeConstraint")
	titleConstraint.MinTextSize = 18
	titleConstraint.MaxTextSize = 30
	titleConstraint.Parent = titleLabel
	Theme.ApplyStroke(titleLabel, Theme.Text.Stroke, 1.5)

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Size = UDim2.new(1, -32, 1, -68)
	content.Position = UDim2.fromOffset(16, 60)
	content.ZIndex = 2
	content.ClipsDescendants = true
	content.Parent = root

	local closed = Signal.new()
	local closeHandle: any = nil
	local closable = props.Closable
	if closable == nil then
		closable = true
	end

	if closable then
		closeHandle = Button.new({
			Parent = header,
			Text = "X",
			Variant = "Danger",
			Size = UDim2.fromOffset(40, 40),
			LayoutOrder = 1,
		})
		closeHandle.Instance.AnchorPoint = Vector2.new(1, 0.5)
		closeHandle.Instance.Position = UDim2.new(1, -8, 0.5, 0)
	end

	local handle = {} :: PanelHandle
	handle.ScreenGui = screenGui
	handle.Root = root
	handle.Content = content
	handle.Closed = closed

	local function playOpenAnimation()
		root.BackgroundTransparency = 0.05
		local uiScaleIn = Instance.new("UIScale")
		uiScaleIn.Scale = 0.85
		uiScaleIn.Parent = root
		TweenService:Create(dim, TweenInfo.new(0.2), { BackgroundTransparency = 0.45 }):Play()
		TweenService:Create(uiScaleIn, TweenInfo.new(0.22, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Scale = 1,
		}):Play()
		TweenService:Create(stroke, TweenInfo.new(0.25), { Transparency = 0.1 }):Play()
		task.delay(0.3, function()
			if uiScaleIn.Parent then
				uiScaleIn:Destroy()
			end
		end)
	end

	handle.Open = function(_self)
		screenGui.Enabled = true
		playOpenAnimation()
	end

	local isClosing = false
	handle.Close = function(_self)
		if isClosing then
			return
		end
		isClosing = true
		local outScale = Instance.new("UIScale")
		outScale.Scale = 1
		outScale.Parent = root
		TweenService:Create(dim, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		local tween = TweenService:Create(outScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = 0.85,
		})
		tween:Play()
		tween.Completed:Connect(function()
			screenGui.Enabled = false
			isClosing = false
			if props.OnClose then
				props.OnClose()
			end
			closed:Fire()
		end)
	end

	if closeHandle then
		closeHandle.Clicked:Connect(function()
			handle:Close()
		end)
	end

	handle.SetTitle = function(_self, title: string)
		titleLabel.Text = title
	end

	handle.Destroy = function(_self)
		unbindScale()
		unbindLayout()
		if closeHandle then
			closeHandle:Destroy()
		end
		closed:DisconnectAll()
		screenGui:Destroy()
	end

	screenGui.Enabled = false

	return handle
end

return Panel
