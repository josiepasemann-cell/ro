--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.InputMode
	Zuständigkeit:
		Zentrale "Zuletzt benutzte Eingabe"-Erkennung: Touch, Gamepad oder
		Tastatur/Maus. Alle UIs, die Tastenhinweise ("B", "Y", "A" ...)
		zeigen oder Fokus-/Cursor-Verhalten umschalten, fragen hier ab statt
		eigene UserInputService-Listener zu bauen.

		- InputMode.Get()          -> "Touch" | "Gamepad" | "KeyboardMouse"
		- InputMode.Changed        -> Signal, feuert (mode) bei jedem Wechsel
		- InputMode.Bind(fn)       -> ruft fn sofort UND bei jedem Wechsel auf
		- InputMode.Pick(k, g, t)  -> liefert den zum Modus passenden Wert
		- InputMode.GetGlyph(key)  -> Beschriftung für eine Taste ("A", "LB", "Enter")
		- InputMode.CreateHint()   -> kleiner Tasten-Chip, der nur bei
		                              passendem Modus sichtbar ist (auf Touch
		                              immer unsichtbar)

		Start-Wert: Konsole/10-Foot-UI -> Gamepad, reines Touch-Gerät ->
		Touch, sonst Tastatur/Maus (PreferredInput als zusätzlicher Hinweis).
		Danach folgt der Modus live UserInputService.LastInputTypeChanged.

	Rojo-Einhängepunkt:
		src/shared/UIKit/InputMode.lua -> ReplicatedStorage.UIKit.InputMode
		(nur clientseitig sinnvoll)
]]

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent:WaitForChild("Signal"))
local Theme = require(script.Parent:WaitForChild("Theme"))

export type Mode = "Touch" | "Gamepad" | "KeyboardMouse"

export type HintProps = {
	Parent: Instance,
	Keyboard: string?, -- z. B. "B" (nur sichtbar im Tastatur/Maus-Modus)
	Gamepad: Enum.KeyCode?, -- z. B. Enum.KeyCode.ButtonY (nur sichtbar im Gamepad-Modus)
	Label: string?, -- optionaler Text hinter der Taste, z. B. "Close"
	AnchorPoint: Vector2?,
	Position: UDim2?,
	ZIndex: number?,
	LayoutOrder: number?,
}

export type HintHandle = {
	Instance: TextLabel,
	Refresh: (self: HintHandle) -> (),
	Destroy: (self: HintHandle) -> (),
}

-- Typisierte Konstanten (vermeiden das Aufweiten von String-Literalen zu `string`).
local MODE_TOUCH: Mode = "Touch"
local MODE_GAMEPAD: Mode = "Gamepad"
local MODE_KEYBOARD_MOUSE: Mode = "KeyboardMouse"

local InputMode = {}
InputMode.Changed = Signal.new() :: any -- fires (mode: Mode)

local function isPlayStation(): boolean
	local ok, platform = pcall(function()
		return UserInputService:GetPlatform()
	end)
	return ok and (platform == Enum.Platform.PS4 or platform == Enum.Platform.PS5)
end

local function modeFromInputType(inputType: Enum.UserInputType): Mode?
	if inputType == Enum.UserInputType.Touch then
		return MODE_TOUCH
	end
	if
		inputType == Enum.UserInputType.Keyboard
		or inputType == Enum.UserInputType.MouseButton1
		or inputType == Enum.UserInputType.MouseButton2
		or inputType == Enum.UserInputType.MouseButton3
		or inputType == Enum.UserInputType.MouseWheel
		or inputType == Enum.UserInputType.MouseMovement
	then
		return MODE_KEYBOARD_MOUSE
	end
	if string.sub(inputType.Name, 1, 7) == "Gamepad" then
		return MODE_GAMEPAD
	end
	return nil
end

local function initialMode(): Mode
	if GuiService:IsTenFootInterface() then
		return MODE_GAMEPAD
	end
	local fromLast = modeFromInputType(UserInputService:GetLastInputType())
	if fromLast then
		return fromLast :: Mode
	end
	local okPref, preferred = pcall(function()
		return UserInputService.PreferredInput
	end)
	if okPref then
		if preferred == Enum.PreferredInput.Gamepad then
			return MODE_GAMEPAD
		elseif preferred == Enum.PreferredInput.Touch then
			return MODE_TOUCH
		end
	end
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		return MODE_TOUCH
	end
	if UserInputService.GamepadEnabled and not UserInputService.KeyboardEnabled then
		return MODE_GAMEPAD
	end
	return MODE_KEYBOARD_MOUSE
end

local currentMode: Mode = initialMode()

function InputMode.Get(): Mode
	return currentMode
end

function InputMode.IsGamepad(): boolean
	return currentMode == "Gamepad"
end

function InputMode.IsTouch(): boolean
	return currentMode == "Touch"
end

function InputMode.IsKeyboardMouse(): boolean
	return currentMode == "KeyboardMouse"
end

-- Ruft `fn` sofort mit dem aktuellen Modus und danach bei jedem Wechsel auf.
-- Gibt eine Disconnect-Funktion zurück.
function InputMode.Bind(fn: (mode: Mode) -> ()): () -> ()
	fn(currentMode)
	local connection = InputMode.Changed:Connect(fn)
	return function()
		connection:Disconnect()
	end
end

-- Wählt je nach aktuellem Modus einen der drei Werte (Touch fällt auf
-- `keyboard` zurück, wenn kein eigener Touch-Wert angegeben wurde).
function InputMode.Pick<T>(keyboard: T, gamepad: T, touch: T?): T
	if currentMode == "Gamepad" then
		return gamepad
	elseif currentMode == "Touch" and touch ~= nil then
		return touch :: T
	end
	return keyboard
end

local GAMEPAD_GLYPHS: { [string]: string } = {
	ButtonA = "A",
	ButtonB = "B",
	ButtonX = "X",
	ButtonY = "Y",
	ButtonL1 = "LB",
	ButtonR1 = "RB",
	ButtonL2 = "LT",
	ButtonR2 = "RT",
	ButtonL3 = "L3",
	ButtonR3 = "R3",
	ButtonStart = "Menu",
	ButtonSelect = "View",
	DPadUp = "D-Pad Up",
	DPadDown = "D-Pad Down",
	DPadLeft = "D-Pad Left",
	DPadRight = "D-Pad Right",
}

local PLAYSTATION_GLYPHS: { [string]: string } = {
	ButtonA = "✕",
	ButtonB = "○",
	ButtonX = "□",
	ButtonY = "△",
	ButtonL1 = "L1",
	ButtonR1 = "R1",
	ButtonL2 = "L2",
	ButtonR2 = "R2",
	ButtonStart = "Options",
	ButtonSelect = "Share",
}

local KEY_GLYPHS: { [string]: string } = {
	One = "1",
	Two = "2",
	Three = "3",
	Four = "4",
	Return = "Enter",
	Backspace = "Backspace",
	Escape = "Esc",
	LeftShift = "Shift",
}

local playStation = isPlayStation()

function InputMode.GetGlyph(keyCode: Enum.KeyCode): string
	local name = keyCode.Name
	if GAMEPAD_GLYPHS[name] then
		if playStation and PLAYSTATION_GLYPHS[name] then
			return PLAYSTATION_GLYPHS[name]
		end
		return GAMEPAD_GLYPHS[name]
	end
	return KEY_GLYPHS[name] or name
end

local function hintText(props: HintProps): string?
	local text: string? = nil
	if currentMode == "Gamepad" and props.Gamepad then
		text = InputMode.GetGlyph(props.Gamepad)
	elseif currentMode == "KeyboardMouse" and props.Keyboard then
		text = props.Keyboard
	end
	if text and props.Label then
		text = text .. "  " .. props.Label
	end
	return text
end

-- Kleiner Tasten-Chip ("Y", "B Close", ...). Unsichtbar auf Touch und
-- wenn für den aktuellen Modus keine Taste angegeben wurde.
function InputMode.CreateHint(props: HintProps): HintHandle
	local chip = Instance.new("TextLabel")
	chip.Name = "InputHint"
	chip.BackgroundColor3 = Theme.Background.Deepest
	chip.BackgroundTransparency = 0.1
	chip.BorderSizePixel = 0
	chip.AutomaticSize = Enum.AutomaticSize.X
	chip.Size = UDim2.fromOffset(0, 22)
	chip.AnchorPoint = props.AnchorPoint or Vector2.zero
	chip.Position = props.Position or UDim2.fromOffset(0, 0)
	chip.ZIndex = props.ZIndex or 20
	chip.LayoutOrder = props.LayoutOrder or 0
	chip.Font = Theme.Font.BodyBold
	chip.TextColor3 = Theme.Neon.Yellow
	chip.TextSize = 14
	chip.Text = ""
	chip.Active = false
	chip.Visible = false
	chip.Parent = props.Parent
	Theme.ApplyCorner(chip, UDim.new(0, 6))
	local stroke = Theme.ApplyStroke(chip, Theme.Neon.Yellow, 1)
	stroke.Transparency = 0.4
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 7)
	padding.PaddingRight = UDim.new(0, 7)
	padding.Parent = chip

	local handle = {} :: HintHandle
	handle.Instance = chip

	local function refresh()
		local text = hintText(props)
		chip.Visible = text ~= nil
		if text then
			chip.Text = text
		end
	end
	handle.Refresh = function(_self)
		refresh()
	end
	refresh()

	local connection = InputMode.Changed:Connect(refresh)
	handle.Destroy = function(_self)
		connection:Disconnect()
		chip:Destroy()
	end
	return handle
end

if RunService:IsClient() then
	UserInputService.LastInputTypeChanged:Connect(function(inputType: Enum.UserInputType)
		local newMode = modeFromInputType(inputType)
		if newMode and newMode ~= currentMode then
			currentMode = newMode :: Mode
			InputMode.Changed:Fire(currentMode)
		end
	end)
end

return InputMode
