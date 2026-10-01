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

		3. Layout.GetHudLayout() - ZENTRALE Positionstabelle für die
		   permanenten Bildschirm-Elemente (HUD, Raid-Leiste, Fähigkeiten-
		   Leiste, Menüleiste). Alle Controller lesen ihre Position von hier,
		   damit sich auf KEINEM Gerät etwas überlappt:
			Portrait  (Phone/Tablet hochkant): HUD oben, Menü darunter (volle
			          Breite), dann Raid-, Event- und Fähigkeiten-Leiste. Unten bleibt
			          für Daumenstick/Sprungknopf frei.
			Landscape (Phone/Tablet quer): HUD oben links, darunter Raid- und
			          Event-Leiste, Menü oben rechts, Fähigkeiten darunter.
			          Unten links/rechts bleibt für Stick/Sprungknopf frei.
			Desktop   (PC/Konsole): HUD oben MITTIG (der Standard-Chat von
			          Roblox sitzt oben links), darunter Raid- und Event-Leiste, Fähigkeiten oben
			          rechts, Menüleiste unten mittig.

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
	MaxWidth: number?, -- Obergrenze der Fensterbreite (virtuelle px), Default 1100 (Ultrawide)
	Margin: number?, -- Mindestabstand zum Bildschirmrand im zentrierten Modus, Default 24
	FullscreenOnPhone: boolean?, -- false: auch auf Phone zentriertes Fenster (kleine Dialoge), Default true
}

-- Bindet Size/Position eines Panel-Root-Frames an die Geräteklasse:
-- Vollbild (mit kleinem Rand) auf Phone, zentriertes Fenster sonst. Das
-- zentrierte Fenster wird auf den sichtbaren Bereich geklemmt (kleine
-- Fenster/Tablets im Hochformat) und auf MaxWidth begrenzt (Ultrawide).
-- Der Frame muss unter einem Device.CreateScaledRoot-Frame hängen.
-- Gibt eine Disconnect-Funktion zurück.
function Layout.FullscreenOrCentered(frame: Frame, sizing: WindowSizing?): () -> ()
	local inset = (sizing and sizing.FullscreenInset) or 12
	local centeredSize = (sizing and sizing.CenteredSize) or UDim2.fromOffset(560, 420)
	local maxWidth = (sizing and sizing.MaxWidth) or 1100
	local margin = (sizing and sizing.Margin) or 24
	local fullscreenOnPhone = not (sizing and sizing.FullscreenOnPhone == false)

	local hookedGui: ScreenGui? = nil
	local guiConnection: RBXScriptConnection? = nil

	local function availableSize(): Vector2
		local gui = frame:FindFirstAncestorWhichIsA("ScreenGui")
		local absolute = Device.GetState().ViewportSize
		if gui and gui.AbsoluteSize.X > 0 and gui.AbsoluteSize.Y > 0 then
			absolute = gui.AbsoluteSize
		end
		return absolute / Device.GetScale()
	end

	local apply: () -> ()

	local function hookGui()
		local gui = frame:FindFirstAncestorWhichIsA("ScreenGui")
		if gui == hookedGui then
			return
		end
		if guiConnection then
			guiConnection:Disconnect()
			guiConnection = nil
		end
		hookedGui = gui
		if gui then
			-- ScreenInsets/Notch ändern die nutzbare Fläche erst nach dem ersten Layout.
			guiConnection = gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
				apply()
			end)
		end
	end

	apply = function()
		hookGui()
		frame.AnchorPoint = Vector2.new(0.5, 0.5)
		frame.Position = UDim2.fromScale(0.5, 0.5)
		if fullscreenOnPhone and Device.ShouldUseFullscreenPanels() then
			frame.Size = UDim2.new(1, -inset * 2, 1, -inset * 2)
		else
			local available = availableSize()
			local width = centeredSize.X.Scale * available.X + centeredSize.X.Offset
			local height = centeredSize.Y.Scale * available.Y + centeredSize.Y.Offset
			width = math.max(math.min(width, available.X - margin * 2, maxWidth), 240)
			height = math.max(math.min(height, available.Y - margin * 2), 200)
			frame.Size = UDim2.fromOffset(width, height)
		end
	end

	apply()
	local connection = Device.Changed:Connect(apply)
	local ancestryConnection = frame.AncestryChanged:Connect(function()
		apply()
	end)
	return function()
		connection:Disconnect()
		ancestryConnection:Disconnect()
		if guiConnection then
			guiConnection:Disconnect()
		end
	end
end

-- // Zentrale HUD-Positionstabelle -------------------------------------------

export type Dock = {
	AnchorPoint: Vector2,
	Position: UDim2,
	Size: UDim2,
}

export type HudLayout = {
	Mode: string, -- "Portrait" | "Landscape" | "Desktop"
	Hud: Dock,
	Raid: Dock,
	Event: Dock, -- Live-Event-Banner (EventUIController)
	Menu: Dock,
	Ability: Dock,
	MenuAtBottom: boolean, -- true: Menüleiste unten (Desktop), Drawer öffnet nach oben
	MenuButtonSize: Vector2, -- Größe eines Menü-Buttons (virtuelle px)
}

local MENU_BUTTON_COUNT = 5
Layout.MenuButtonCount = MENU_BUTTON_COUNT

function Layout.GetHudLayout(): HudLayout
	local state = Device.GetState()
	if Device.IsTouchPrimary() then
		if state.IsPortrait then
			return {
				Mode = "Portrait",
				Hud = {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 8),
					Size = UDim2.new(1, -16, 0, 92),
				},
				Menu = {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 108),
					Size = UDim2.new(1, -16, 0, 64),
				},
				Raid = {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 180),
					Size = UDim2.new(1, -16, 0, 44),
				},
				Event = {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 232),
					Size = UDim2.new(1, -16, 0, 46),
				},
				Ability = {
					AnchorPoint = Vector2.new(0.5, 0),
					Position = UDim2.new(0.5, 0, 0, 286),
					Size = UDim2.new(1, -16, 0, 0),
				},
				MenuAtBottom = false,
				MenuButtonSize = Vector2.new(62, 52),
			}
		end
		return {
			Mode = "Landscape",
			Hud = {
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.new(0, 8, 0, 8),
				Size = UDim2.new(0, 264, 0, 92),
			},
			Raid = {
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.new(0, 8, 0, 100),
				Size = UDim2.new(0, 264, 0, 40),
			},
			Event = {
				AnchorPoint = Vector2.new(0, 0),
				Position = UDim2.new(0, 8, 0, 146),
				Size = UDim2.new(0, 264, 0, 46),
			},
			Menu = {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 8),
				Size = UDim2.new(0, MENU_BUTTON_COUNT * 56 + (MENU_BUTTON_COUNT - 1) * 6 + 16, 0, 64),
			},
			Ability = {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, -8, 0, 80),
				Size = UDim2.new(0, 232, 0, 0),
			},
			MenuAtBottom = false,
			MenuButtonSize = Vector2.new(56, 52),
		}
	end

	-- PC / Konsole
	local buttonWidth = if state.Class == "Console" then 84 else 76
	return {
		Mode = "Desktop",
		Hud = {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 16),
			Size = UDim2.new(0, 380, 0, 96),
		},
		Raid = {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 120),
			Size = UDim2.new(0, 380, 0, 52),
		},
		Event = {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0, 180),
			Size = UDim2.new(0, 280, 0, 46),
		},
		Menu = {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.new(0.5, 0, 1, -18),
			Size = UDim2.new(0, MENU_BUTTON_COUNT * buttonWidth + (MENU_BUTTON_COUNT - 1) * 8 + 24, 0, 76),
		},
		Ability = {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.new(1, -16, 0, 16),
			Size = UDim2.new(0, 230, 0, 0),
		},
		MenuAtBottom = true,
		MenuButtonSize = Vector2.new(buttonWidth, 60),
	}
end

return Layout
