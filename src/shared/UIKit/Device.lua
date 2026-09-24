--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Device
	Zuständigkeit:
		Zentrale Geräte-Erkennung (Handy/Tablet/Laptop/PC/Konsole) und
		zentraler Skalierungs-Mechanismus für das gesamte UIKit. Andere
		UIKit-Module (Button, Panel, Toast, ...) fragen hier ab, welche
		Geräteklasse aktiv ist und binden ihre Skalierung/Layout darüber,
		statt eigene Heuristiken zu bauen.

	Erkennung basiert auf:
		- UserInputService.TouchEnabled / KeyboardEnabled / GamepadEnabled
		- GuiService:IsTenFootInterface() (Konsole/TV-Fernbedienung)
		- Camera.ViewportSize (Kurzseite entscheidet Phone vs. Tablet und
		  treibt den UIScale-Faktor)
		- GuiService:GetGuiInset() für Topbar-Aussparung, ScreenInsets für
		  Notch/Safe-Area auf mobilen Geräten

	Reagiert live auf Rotation/Fenstergröße über
	Camera:GetPropertyChangedSignal("ViewportSize").

	Rojo-Einhängepunkt:
		src/shared/UIKit/Device.lua -> ReplicatedStorage.UIKit.Device
		(nur clientseitig sinnvoll nutzbar - UserInputService/GuiService
		existieren serverseitig nicht mit echten Werten; ein require aus
		Server-Code ist zwar technisch möglich, liefert aber keine
		sinnvollen Geräteinformationen.)
]]

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Signal = require(script.Parent:WaitForChild("Signal"))

export type DeviceClass = "Phone" | "Tablet" | "Console" | "PC"

export type DeviceState = {
	Class: DeviceClass,
	HasTouch: boolean,
	HasKeyboard: boolean,
	HasGamepad: boolean,
	IsTenFoot: boolean,
	Scale: number,
	ViewportSize: Vector2,
}

local MIN_SCALE = 0.62
local MAX_SCALE = 1.35
-- Referenz-Kurzseite, auf die das gesamte UIKit optisch abgestimmt ist
-- (klassisches 16:9-Laptop-Fenster, 720 px Kurzseite).
local REFERENCE_SHORT_SIDE = 720
-- Zusätzlicher Skalierungs-Boost auf reinen Touch-Geräten, damit die
-- Mindest-Touch-Zielgröße (~44px, Apple/Google HIG) auch bei kleinen
-- Phones sicher erreicht wird.
local TOUCH_SCALE_BOOST = 1.12

local MIN_TOUCH_SIZE = 44

local Device = {}
Device.MinTouchSize = MIN_TOUCH_SIZE
Device.Changed = Signal.new() :: any -- fires (state: DeviceState)

local camera = Workspace.CurrentCamera

local function getViewportSize(): Vector2
	camera = Workspace.CurrentCamera
	if camera then
		return camera.ViewportSize
	end
	return Vector2.new(1280, 720)
end

local function classify(viewport: Vector2): DeviceClass
	local hasTouch = UserInputService.TouchEnabled
	local hasKeyboard = UserInputService.KeyboardEnabled
	local hasGamepad = UserInputService.GamepadEnabled
	local isTenFoot = GuiService:IsTenFootInterface()

	if isTenFoot then
		return "Console"
	end

	if hasTouch and not hasKeyboard then
		local shortSide = math.min(viewport.X, viewport.Y)
		if shortSide >= 600 then
			return "Tablet"
		end
		return "Phone"
	end

	if hasGamepad and not hasKeyboard and not hasTouch then
		return "Console"
	end

	return "PC"
end

local function computeScale(viewport: Vector2, class: DeviceClass): number
	local shortSide = math.min(viewport.X, viewport.Y)
	local scale = shortSide / REFERENCE_SHORT_SIDE
	if class == "Phone" or class == "Tablet" then
		scale *= TOUCH_SCALE_BOOST
	end
	return math.clamp(scale, MIN_SCALE, MAX_SCALE)
end

local function buildState(): DeviceState
	local viewport = getViewportSize()
	local class = classify(viewport)
	return {
		Class = class,
		HasTouch = UserInputService.TouchEnabled,
		HasKeyboard = UserInputService.KeyboardEnabled,
		HasGamepad = UserInputService.GamepadEnabled,
		IsTenFoot = GuiService:IsTenFootInterface(),
		Scale = computeScale(viewport, class),
		ViewportSize = viewport,
	}
end

local currentState: DeviceState = buildState()

function Device.GetState(): DeviceState
	return currentState
end

function Device.GetClass(): DeviceClass
	return currentState.Class
end

function Device.GetScale(): number
	return currentState.Scale
end

function Device.IsTouch(): boolean
	return currentState.HasTouch
end

function Device.IsPhone(): boolean
	return currentState.Class == "Phone"
end

function Device.IsConsole(): boolean
	return currentState.Class == "Console"
end

function Device.HasPhysicalKeyboard(): boolean
	return currentState.HasKeyboard
end

-- Klemmt eine gewünschte Pixelgröße auf die Mindest-Touch-Zielgröße, wenn
-- das aktuelle Gerät Touch-Eingabe nutzt. Für Buttons/Interaktionsflächen
-- gedacht, NICHT für reinen Dekor-Text.
function Device.ClampTouchSize(pixelSize: number): number
	if currentState.HasTouch then
		return math.max(pixelSize, MIN_TOUCH_SIZE)
	end
	return pixelSize
end

-- Bindet ein UIScale-Objekt dauerhaft an den zentralen Skalierungswert und
-- hält es bei ViewportSize-Änderungen aktuell. Gibt eine Disconnect-
-- Funktion zurück, die beim Aufräumen des jeweiligen UI-Widgets aufgerufen
-- werden sollte.
function Device.BindUIScale(uiScale: UIScale, multiplier: number?): () -> ()
	local mult = multiplier or 1
	uiScale.Scale = currentState.Scale * mult
	local connection = Device.Changed:Connect(function(state: DeviceState)
		uiScale.Scale = state.Scale * mult
	end)
	return function()
		connection:Disconnect()
	end
end

-- Setzt Safe-Area/Notch-Aussparung auf einem ScreenGui (mobile Geräte mit
-- Notch/Punch-Hole) und liefert zusätzlich den aktuellen TopBar-Inset
-- (GuiService:GetGuiInset()) für Layouts, die bewusst darunter beginnen
-- wollen.
function Device.ApplySafeArea(screenGui: ScreenGui): (Vector2, Vector2)
	screenGui.ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets
	local inset, _ = GuiService:GetGuiInset()
	return inset, GuiService:GetGuiInset()
end

-- Liefert true, wenn Tastatur-Shortcuts angezeigt werden sollen (nur wenn
-- tatsächlich eine physische Tastatur erkannt wurde, also NICHT auf
-- reinen Touch-/Konsole-Geräten).
function Device.ShouldShowKeyboardHints(): boolean
	return currentState.HasKeyboard and currentState.Class == "PC"
end

-- Liefert true, wenn Gamepad-Navigation (Selectable/SelectionImageObject)
-- aktiv beworben werden soll.
function Device.ShouldShowGamepadHints(): boolean
	return currentState.HasGamepad and (currentState.Class == "Console" or not currentState.HasKeyboard)
end

-- Layout-Helfer: liefert, ob Panels auf diesem Gerät als Vollbild
-- dargestellt werden sollen (Phone) oder als zentriertes Fenster
-- (Tablet/PC/Konsole).
function Device.ShouldUseFullscreenPanels(): boolean
	return currentState.Class == "Phone"
end

local function refresh()
	local newState = buildState()
	local changed = newState.Class ~= currentState.Class
		or newState.Scale ~= currentState.Scale
		or newState.ViewportSize ~= currentState.ViewportSize
	currentState = newState
	if changed then
		Device.Changed:Fire(currentState)
	end
end

if RunService:IsClient() then
	local cam = Workspace.CurrentCamera
	if cam then
		cam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
	end
	Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
		local newCam = Workspace.CurrentCamera
		if newCam then
			newCam:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		end
		refresh()
	end)
	UserInputService.LastInputTypeChanged:Connect(refresh)
end

return Device
