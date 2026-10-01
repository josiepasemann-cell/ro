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
local InputMode = require(script.Parent:WaitForChild("InputMode"))

export type DeviceClass = "Phone" | "Tablet" | "Console" | "PC"

export type DeviceState = {
	Class: DeviceClass,
	HasTouch: boolean,
	HasKeyboard: boolean,
	HasGamepad: boolean,
	IsTenFoot: boolean,
	IsPortrait: boolean,
	Scale: number,
	ViewportSize: Vector2,
}

-- Referenz-Kurzseite für PC/Tablet/Konsole (klassisches 16:9-Laptop-Fenster,
-- 720 px Kurzseite).
local REFERENCE_SHORT_SIDE = 720
-- Phones: echte Kurzseiten liegen bei ~360-430 px. Teiler 400 ergibt ~0.9-1.1,
-- d. h. Text mit MinTextSize 12-14 bleibt auch auf einem 360x640-Handy lesbar
-- (vorher 0.62 -> 14er Text wurde auf ~9 px geschrumpft).
local PHONE_REFERENCE_SHORT_SIDE = 400
local PHONE_MIN_SCALE = 0.9
local PHONE_MAX_SCALE = 1.15
local TABLET_MIN_SCALE = 0.95
local TABLET_MAX_SCALE = 1.3
local PC_MIN_SCALE = 0.8
local PC_MAX_SCALE = 1.5
-- Konsole/TV (10-Foot): deutlich größer, damit Text aus 3 m lesbar bleibt.
local CONSOLE_FACTOR = 1.15
local CONSOLE_MIN_SCALE = 1.15
local CONSOLE_MAX_SCALE = 1.7
-- Zusätzlicher Skalierungs-Boost auf Tablets (Mindest-Touch-Zielgröße).
local TOUCH_SCALE_BOOST = 1.12

-- Platz (reale px), den Roblox' Standard-Touch-Steuerung (Daumenstick links,
-- Sprungknopf rechts) unten belegt.
local TOUCH_CONTROLS_CLEARANCE = 190

local MIN_TOUCH_SIZE = 44
local MIN_CONSOLE_TARGET_SIZE = 52

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
	if class == "Phone" then
		return math.clamp(shortSide / PHONE_REFERENCE_SHORT_SIDE, PHONE_MIN_SCALE, PHONE_MAX_SCALE)
	elseif class == "Tablet" then
		return math.clamp(
			shortSide / REFERENCE_SHORT_SIDE * TOUCH_SCALE_BOOST,
			TABLET_MIN_SCALE,
			TABLET_MAX_SCALE
		)
	elseif class == "Console" then
		return math.clamp(shortSide / REFERENCE_SHORT_SIDE * CONSOLE_FACTOR, CONSOLE_MIN_SCALE, CONSOLE_MAX_SCALE)
	end
	return math.clamp(shortSide / REFERENCE_SHORT_SIDE, PC_MIN_SCALE, PC_MAX_SCALE)
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
		IsPortrait = viewport.Y > viewport.X,
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

function Device.IsPortrait(): boolean
	return currentState.IsPortrait
end

-- true auf Phone/Tablet (Touch ist die Haupteingabe): dort belegt Roblox
-- unten links/rechts den Daumenstick und den Sprungknopf.
function Device.IsTouchPrimary(): boolean
	return currentState.HasTouch and (currentState.Class == "Phone" or currentState.Class == "Tablet")
end

-- Sichtbarer Bereich in "virtuellen" Pixeln (also nach Abzug des UIScale);
-- das ist die Größe, die ein CreateScaledRoot-Frame tatsächlich bietet.
function Device.GetVirtualViewport(): Vector2
	return currentState.ViewportSize / currentState.Scale
end

-- Liefert (seitlicher Abstand, Abstand unten) in virtuellen Pixeln, die
-- unten angedockte UI auf Touch-Geräten freihalten muss, damit sie weder
-- Daumenstick noch Sprungknopf verdeckt: Hochformat = Abstand unten,
-- Querformat = Abstand links/rechts. Auf PC/Konsole (0, 0).
function Device.GetBottomDockInsets(): (number, number)
	if not Device.IsTouchPrimary() then
		return 0, 0
	end
	local clearance = TOUCH_CONTROLS_CLEARANCE / currentState.Scale
	if currentState.IsPortrait then
		return 0, clearance
	end
	return clearance, 0
end

-- Kleinste sinnvolle Zielgröße (reale px) für bedienbare Elemente: 44 px auf
-- Touch, 52 px auf Konsole (Gamepad-Fokus aus der Distanz).
function Device.GetMinTargetSize(): number
	if currentState.Class == "Console" then
		return MIN_CONSOLE_TARGET_SIZE
	end
	if currentState.HasTouch then
		return MIN_TOUCH_SIZE
	end
	return 0
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

-- Erzeugt unter `screenGui` einen vollflächigen Root-Frame, der den
-- zentralen Skalierungsfaktor korrekt anwendet: Size = 1/Scale, das UIScale
-- sitzt als Kind des Frames. Dadurch füllt der Frame das ScreenGui exakt
-- aus, Kinder arbeiten in "virtuellen" Pixeln (ViewportSize / Scale) und
-- zentrierte (0.5) bzw. unten/rechts angedockte (1) Elemente liegen
-- tatsächlich dort. Alle Kinder des ScreenGui sollen unter diesen Frame.
-- Gibt (root, unbind) zurück.
function Device.CreateScaledRoot(screenGui: ScreenGui, multiplier: number?): (Frame, () -> ())
	local mult = multiplier or 1
	local root = Instance.new("Frame")
	root.Name = "ScaledRoot"
	root.BackgroundTransparency = 1
	root.BorderSizePixel = 0
	root.Active = false
	root.Selectable = false

	local uiScale = Instance.new("UIScale")
	uiScale.Parent = root

	local function apply(scale: number)
		local effective = scale * mult
		uiScale.Scale = effective
		root.Size = UDim2.fromScale(1 / effective, 1 / effective)
	end
	apply(currentState.Scale)
	local connection = Device.Changed:Connect(function(state: DeviceState)
		apply(state.Scale)
	end)
	root.Parent = screenGui

	return root, function()
		connection:Disconnect()
	end
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

-- Setzt Safe-Area/Notch-Aussparung auf einem ScreenGui. Standard ist
-- CoreUISafeInsets: hält Abstand zu Notch/Punch-Hole/Home-Indikator UND zur
-- Roblox-Topbar/den Core-Buttons (Menü, Chat), sodass HUD-Elemente dort nicht
-- überlappen. Für bewusst randlose Overlays (Abdunkeln, Flash) None übergeben.
-- Liefert zusätzlich GuiService:GetGuiInset() (links-oben, rechts-unten).
function Device.ApplySafeArea(screenGui: ScreenGui, insets: Enum.ScreenInsets?): (Vector2, Vector2)
	screenGui.ScreenInsets = insets or Enum.ScreenInsets.CoreUISafeInsets
	return GuiService:GetGuiInset()
end

-- Liefert true, wenn Tastatur-Shortcuts angezeigt werden sollen: nur wenn
-- eine Tastatur vorhanden ist UND zuletzt Tastatur/Maus benutzt wurde.
function Device.ShouldShowKeyboardHints(): boolean
	return currentState.HasKeyboard and InputMode.Get() == "KeyboardMouse"
end

-- Liefert true, wenn Gamepad-Tastenhinweise (A/B/Y ...) gezeigt werden
-- sollen: Konsole oder zuletzt ein Gamepad benutzt.
function Device.ShouldShowGamepadHints(): boolean
	return currentState.Class == "Console" or InputMode.Get() == "Gamepad"
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
