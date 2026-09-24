--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Layout
	Zuständigkeit:
		Geräte-abhängige Layout-Helfer. Zwei Bausteine:

		1. Layout.ResponsiveRow(parent, props) - eine Reihe von Kindern
		   (typischerweise Buttons aus UIKit.Button), die auf PC/Tablet/
		   Konsole horizontal nebeneinander läuft, auf Phone jedoch zu
		   einer vollen Spalte umbricht (jedes Kind volle Breite). Reagiert
		   live auf Device.Changed (Rotation/Fenstergrößenänderung), ohne
		   dass der aufrufende Code sich selbst um Viewport-Events kümmern
		   muss.

		2. Layout.FullscreenOrCentered(frame, props) - positioniert ein
		   Panel/Fenster: Vollbild auf Phone, zentriertes Fenster mit
		   fester Maximalgröße auf Tablet/PC/Konsole.

		Diese Helfer sind die einzige unterstützte Art, wie UIKit-Widgets
		(Button, Panel, Toast, ...) auf Geräteklassen reagieren - sie
		implementieren NICHT selbst eigene Viewport-Heuristiken.

	Rojo-Einhängepunkt:
		src/shared/UIKit/Layout.lua -> ReplicatedStorage.UIKit.Layout
]]

local Device = require(script.Parent:WaitForChild("Device"))

local Layout = {}

export type ResponsiveRowProps = {
	Parent: Instance,
	Padding: number?, -- Abstand zwischen Elementen, in Pixeln (Design-Referenzgröße)
	HorizontalAlignment: Enum.HorizontalAlignment?,
	VerticalAlignment: Enum.VerticalAlignment?,
}

export type ResponsiveRowHandle = {
	Frame: Frame,
	Destroy: (self: ResponsiveRowHandle) -> (),
}

-- Erzeugt eine Frame mit UIListLayout, die auf Phone vertikal (eine Spalte,
-- Kinder erhalten volle Breite) und auf allen anderen Geräteklassen
-- horizontal (nebeneinander) läuft. Kinder sollten Size = {1,0},{0,H} auf
-- Phone-freundliche Weise mit UDim2 relativer X-Achse definieren, damit der
-- Spaltenmodus sinnvoll aussieht (die Button-Factory tut das automatisch).
function Layout.ResponsiveRow(props: ResponsiveRowProps): ResponsiveRowHandle
	local frame = Instance.new("Frame")
	frame.Name = "ResponsiveRow"
	frame.BackgroundTransparency = 1
	frame.AutomaticSize = Enum.AutomaticSize.Y
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.Parent = props.Parent

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, props.Padding or 10)
	listLayout.HorizontalAlignment = props.HorizontalAlignment or Enum.HorizontalAlignment.Center
	listLayout.VerticalAlignment = props.VerticalAlignment or Enum.VerticalAlignment.Center
	listLayout.Parent = frame

	local function applyForClass()
		local isPhone = Device.ShouldUseFullscreenPanels()
		if isPhone then
			listLayout.FillDirection = Enum.FillDirection.Vertical
		else
			listLayout.FillDirection = Enum.FillDirection.Horizontal
			listLayout.Wraps = true
		end
	end

	applyForClass()
	local connection = Device.Changed:Connect(applyForClass)

	local handle = {} :: ResponsiveRowHandle
	handle.Frame = frame
	handle.Destroy = function(_self)
		connection:Disconnect()
		frame:Destroy()
	end
	return handle
end

export type WindowSizing = {
	FullscreenInset: number?, -- Rand in Pixeln bei Vollbild (Phone), Default 12
	CenteredSize: UDim2?, -- gewünschte Größe im zentrierten Modus (Tablet/PC/Konsole)
}

-- Bindet Size/Position eines Panel-Root-Frames an die Geräteklasse:
-- Vollbild (mit kleinem Rand) auf Phone, zentriertes Fenster sonst.
-- Gibt eine Disconnect-Funktion zurück.
function Layout.FullscreenOrCentered(frame: Frame, sizing: WindowSizing?): () -> ()
	local inset = (sizing and sizing.FullscreenInset) or 12
	local centeredSize = (sizing and sizing.CenteredSize) or UDim2.fromOffset(560, 420)

	local function apply()
		if Device.ShouldUseFullscreenPanels() then
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
		else
			frame.AnchorPoint = Vector2.new(0.5, 0.5)
			frame.Position = UDim2.fromScale(0.5, 0.5)
			frame.Size = centeredSize
		end
	end

	apply()
	local connection = Device.Changed:Connect(apply)
	return function()
		connection:Disconnect()
	end
end

return Layout
