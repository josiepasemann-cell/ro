--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Panel
	Zuständigkeit:
		Fenster/Panel-Baustein mit Einblend-Animation, Schließen-Button
		(aus der Button-Factory) und geräte-abhängigem Layout: Vollbild auf
		Phone, zentriertes Fenster auf Tablet/PC/Konsole (via
		UIKit.Layout.FullscreenOrCentered). Bindet außerdem den zentralen
		Device-Skalierungsfaktor EINMAL pro Panel (statt pro Kind-Widget)
		über Device.CreateScaledRoot, sodass alle Kinder (Buttons, Labels,
		...) automatisch mitskalieren und das Abdunkeln den ganzen
		Bildschirm füllt.

		Gamepad/Konsole:
			- Beim Öffnen (und beim Wechsel auf Gamepad) bekommt das erste
			  bedienbare Element den Fokus (GuiService.SelectedObject), beim
			  Schließen wird die vorherige Auswahl wiederhergestellt.
			- Der Fokus bleibt im obersten offenen Panel (kein Wegnavigieren
			  in Menüleiste/HUD hinter dem Dialog).
			- B (ButtonB) schließt das oberste Panel (ContextActionService,
			  hohe Priorität); neben dem X-Button erscheint dann der Hinweis "B".
		Panel.CloseAll() / Panel.IsAnyOpen() erlauben Tastenkürzeln
		(MainMenuController) das Umschalten, ohne die Panels zu kennen.

	Rojo-Einhängepunkt:
		src/shared/UIKit/Panel.lua -> ReplicatedStorage.UIKit.Panel
]]

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local GuiService = game:GetService("GuiService")
local ContextActionService = game:GetService("ContextActionService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Device = require(script.Parent:WaitForChild("Device"))
local InputMode = require(script.Parent:WaitForChild("InputMode"))
local Layout = require(script.Parent:WaitForChild("Layout"))
local Button = require(script.Parent:WaitForChild("Button"))
local Signal = require(script.Parent:WaitForChild("Signal"))

export type PanelProps = {
	Title: string,
	ScreenGuiName: string?,
	Closable: boolean?,
	CenteredSize: UDim2?,
	FullscreenOnPhone: boolean?, -- false: auch auf Phone zentriert (kleine Dialoge)
	OnClose: (() -> ())?,
	DisplayOrder: number?,
}

export type PanelHandle = {
	ScreenGui: ScreenGui,
	Root: Frame,
	Content: Frame,
	Closed: any,
	Closable: boolean,
	Open: (self: PanelHandle) -> (),
	Close: (self: PanelHandle) -> (),
	SetTitle: (self: PanelHandle, title: string) -> (),
	SetInitialFocus: (self: PanelHandle, target: GuiObject?) -> (),
	Destroy: (self: PanelHandle) -> (),
}

local Panel = {}

-- // Modaler Panel-Stapel (Gamepad-Fokus + B-Taste) ------------------------------

local CLOSE_ACTION_NAME = "UIKitPanelClose"
local FOCUS_DELAY = 0.12
local FOCUS_RETRY_DELAY = 0.7

local openStack: { PanelHandle } = {}
local previousSelections: { [PanelHandle]: GuiObject? } = {}
local initialFocusTargets: { [PanelHandle]: GuiObject? } = {}
local closeActionBound = false
local focusGuardConnection: RBXScriptConnection? = nil
local lastValidSelection: GuiObject? = nil

local function isEffectivelyVisible(gui: GuiObject, stopAt: Instance): boolean
	local current: Instance? = gui
	while current and current ~= stopAt do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return true
end

local function findFocusTarget(panelHandle: PanelHandle): GuiObject?
	local explicit = initialFocusTargets[panelHandle]
	if explicit and explicit.Parent and explicit:IsDescendantOf(panelHandle.ScreenGui) then
		return explicit
	end
	local searchRoots: { Instance } = { panelHandle.Content, panelHandle.Root }
	for _, searchRoot in searchRoots do
		for _, descendant in searchRoot:GetDescendants() do
			if
				descendant:IsA("GuiButton")
				and descendant.Selectable
				and descendant.Active
				and descendant.AbsoluteSize.X > 0
				and isEffectivelyVisible(descendant, panelHandle.ScreenGui)
			then
				return descendant
			end
		end
	end
	return nil
end

local function shouldDriveSelection(): boolean
	return InputMode.IsGamepad() or Device.IsConsole()
end

local function focusTop(onlyIfLost: boolean)
	local top = openStack[#openStack]
	if not top or not shouldDriveSelection() then
		return
	end
	local current = GuiService.SelectedObject
	if onlyIfLost and current and current:IsDescendantOf(top.ScreenGui) then
		return
	end
	local target = findFocusTarget(top)
	if target then
		GuiService.SelectedObject = target
	end
end

local function onSelectionChanged()
	local top = openStack[#openStack]
	local selected = GuiService.SelectedObject
	if not top or not selected then
		return
	end
	if selected:IsDescendantOf(top.ScreenGui) then
		lastValidSelection = selected
		return
	end
	-- Fokus ist aus dem obersten Panel herausgewandert (Menüleiste/HUD dahinter):
	-- im nächsten Frame zurückholen.
	task.defer(function()
		local topNow = openStack[#openStack]
		local currentNow = GuiService.SelectedObject
		if topNow and currentNow and not currentNow:IsDescendantOf(topNow.ScreenGui) then
			if lastValidSelection and lastValidSelection.Parent and lastValidSelection:IsDescendantOf(topNow.ScreenGui) then
				GuiService.SelectedObject = lastValidSelection
			else
				GuiService.SelectedObject = findFocusTarget(topNow)
			end
		end
	end)
end

local function onCloseAction(
	_actionName: string,
	inputState: Enum.UserInputState,
	_inputObject: InputObject
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local top = openStack[#openStack]
	if not top then
		return Enum.ContextActionResult.Pass
	end
	if top.Closable then
		top:Close()
	end
	return Enum.ContextActionResult.Sink
end

local function pushOpen(panelHandle: PanelHandle)
	if table.find(openStack, panelHandle) then
		return
	end
	local selected = GuiService.SelectedObject
	if selected and not selected:IsDescendantOf(panelHandle.ScreenGui) then
		previousSelections[panelHandle] = selected
	else
		previousSelections[panelHandle] = nil
	end
	table.insert(openStack, panelHandle)
	if not closeActionBound then
		closeActionBound = true
		ContextActionService:BindActionAtPriority(
			CLOSE_ACTION_NAME,
			onCloseAction,
			false,
			Enum.ContextActionPriority.High.Value,
			Enum.KeyCode.ButtonB
		)
	end
	if not focusGuardConnection then
		focusGuardConnection = GuiService:GetPropertyChangedSignal("SelectedObject"):Connect(onSelectionChanged)
	end
end

local function popOpen(panelHandle: PanelHandle)
	local index = table.find(openStack, panelHandle)
	if not index then
		return
	end
	table.remove(openStack, index)
	local restore = previousSelections[panelHandle]
	previousSelections[panelHandle] = nil

	if #openStack == 0 then
		if closeActionBound then
			closeActionBound = false
			ContextActionService:UnbindAction(CLOSE_ACTION_NAME)
		end
		if focusGuardConnection then
			focusGuardConnection:Disconnect()
			focusGuardConnection = nil
		end
		lastValidSelection = nil
		if shouldDriveSelection() then
			if restore and restore.Parent and restore:IsDescendantOf(game) and restore.Visible then
				GuiService.SelectedObject = restore
			else
				GuiService.SelectedObject = nil
			end
		end
	else
		lastValidSelection = nil
		local top = openStack[#openStack]
		if restore and top and restore.Parent and restore:IsDescendantOf(top.ScreenGui) and shouldDriveSelection() then
			-- Verschachtelter Dialog (z. B. Bestätigen im Shop) geschlossen:
			-- Fokus kehrt auf das auslösende Element zurück.
			GuiService.SelectedObject = restore
		else
			focusTop(false)
		end
	end
end

InputMode.Changed:Connect(function(mode)
	if mode == "Gamepad" then
		focusTop(true)
	end
end)

-- Schließt alle offenen Panels (z. B. beim Umschalten per Tastenkürzel).
function Panel.CloseAll()
	local snapshot = table.clone(openStack)
	for index = #snapshot, 1, -1 do
		local panelHandle = snapshot[index]
		if panelHandle.Closable then
			panelHandle:Close()
		end
	end
end

function Panel.IsAnyOpen(): boolean
	return #openStack > 0
end

function Panel.GetTopScreenGui(): ScreenGui?
	local top = openStack[#openStack]
	return if top then top.ScreenGui else nil
end

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
	-- Standardmäßig ÜBER der persistenten Menüleiste (MainMenuController,
	-- DisplayOrder 20) und HUD-Elementen (HUD/HeldItem/IdleIncome, 15-18),
	-- damit geöffnete Panels (Shop/Quest/Breeding/Rangliste/Raid/...) nicht
	-- von der Menüleiste verdeckt werden bzw. deren Buttons durchklickbar
	-- bleiben - siehe Code-Review-Bericht (Überlappung Menüleiste/Panels).
	screenGui.DisplayOrder = props.DisplayOrder or 30
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- CoreUISafeInsets: Fenster/Schließen-Button liegen nie unter der
	-- Roblox-Topbar oder einer Notch.
	Device.ApplySafeArea(screenGui)
	screenGui.Parent = getPlayerGui()

	-- Ein zentraler Skalierungs-Root pro Panel - alle Kinder skalieren
	-- automatisch mit der erkannten Geräteklasse/Viewportgröße mit (und das
	-- Abdunkeln füllt trotz UIScale den ganzen Bildschirm).
	local scaledRoot, unbindScale = Device.CreateScaledRoot(screenGui)

	local dim = Instance.new("Frame")
	dim.Name = "Dim"
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 1
	dim.Size = UDim2.fromScale(1, 1)
	dim.ZIndex = 1
	-- Aktiv setzen, damit dieses Dim-Overlay tatsächlich Klicks/Touches auf
	-- darunterliegende Elemente (Menüleiste, Workspace-ClickDetectors an
	-- Eiern/Gebäuden, andere HUD-Buttons) blockiert, solange das Panel
	-- geöffnet ist - ein reines Frame mit Active=false lässt Eingaben sonst
	-- unbemerkt durch (Modal-Leak).
	dim.Active = true
	dim.Selectable = false
	dim.Parent = scaledRoot

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundColor3 = Theme.Background.Panel
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.ZIndex = 2
	root.Parent = scaledRoot
	Theme.ApplyCorner(root, UDim.new(0, 18))
	local stroke = Theme.ApplyStroke(root, Theme.Neon.Cyan, 2)
	stroke.Transparency = 0.35
	Theme.ApplyGradient(root, { Theme.Background.Panel, Theme.Background.Deepest }, 90)

	local unbindLayout = Layout.FullscreenOrCentered(root, {
		CenteredSize = props.CenteredSize,
		FullscreenOnPhone = props.FullscreenOnPhone,
	})

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, 0, 0, 56)
	header.ZIndex = 3
	header.Parent = root

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.BackgroundTransparency = 1
	titleLabel.Size = UDim2.new(1, -118, 1, 0)
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
	content.Size = UDim2.new(1, -32, 1, -80)
	content.Position = UDim2.fromOffset(16, 64)
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
			Size = UDim2.fromOffset(44, 44),
			LayoutOrder = 1,
		})
		closeHandle.Instance.AnchorPoint = Vector2.new(1, 0.5)
		closeHandle.Instance.Position = UDim2.new(1, -8, 0.5, 0)
	end

	-- Gamepad-Hinweis "B" links neben dem X-Button (nur im Gamepad-Modus sichtbar).
	local closeHint: any = nil
	if closable then
		closeHint = InputMode.CreateHint({
			Parent = header,
			Gamepad = Enum.KeyCode.ButtonB,
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -60, 0.5, 0),
			ZIndex = 4,
		})
	end

	local handle = {} :: PanelHandle
	handle.ScreenGui = screenGui
	handle.Root = root
	handle.Content = content
	handle.Closed = closed
	handle.Closable = closable ~= false

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

	local isClosing = false
	local closeTween: Tween? = nil
	local closeScale: UIScale? = nil

	handle.Open = function(_self)
		local wasClosing = closeTween ~= nil
		if closeTween then
			-- Wieder geöffnet, während die Schließ-Animation noch läuft.
			closeTween:Cancel()
			closeTween = nil
		end
		if closeScale then
			closeScale:Destroy()
			closeScale = nil
		end
		isClosing = false
		local alreadyOpen = screenGui.Enabled and not wasClosing
		screenGui.Enabled = true
		if not alreadyOpen then
			playOpenAnimation()
		end
		pushOpen(handle)
		task.delay(FOCUS_DELAY, function()
			if table.find(openStack, handle) and openStack[#openStack] == handle then
				focusTop(false)
			end
		end)
		task.delay(FOCUS_RETRY_DELAY, function()
			-- Inhalte, die erst per Remote/Rebuild nach dem Öffnen entstehen.
			if table.find(openStack, handle) and openStack[#openStack] == handle then
				focusTop(true)
			end
		end)
	end

	handle.Close = function(_self)
		if isClosing or not screenGui.Enabled then
			return
		end
		isClosing = true
		popOpen(handle)
		local outScale = Instance.new("UIScale")
		outScale.Scale = 1
		outScale.Parent = root
		closeScale = outScale
		TweenService:Create(dim, TweenInfo.new(0.15), { BackgroundTransparency = 1 }):Play()
		local tween = TweenService:Create(outScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Scale = 0.85,
		})
		closeTween = tween
		tween.Completed:Connect(function(playbackState: Enum.PlaybackState)
			if playbackState ~= Enum.PlaybackState.Completed then
				return
			end
			closeTween = nil
			closeScale = nil
			outScale:Destroy()
			screenGui.Enabled = false
			isClosing = false
			if props.OnClose then
				props.OnClose()
			end
			closed:Fire()
		end)
		tween:Play()
	end

	handle.SetInitialFocus = function(_self, target: GuiObject?)
		initialFocusTargets[handle] = target
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
		popOpen(handle)
		initialFocusTargets[handle] = nil
		unbindScale()
		unbindLayout()
		if closeHint then
			closeHint:Destroy()
		end
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
