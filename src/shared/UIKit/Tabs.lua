--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Tabs
	Zuständigkeit:
		Tab-Leiste für Panels (z. B. "Kreaturen" / "Gebäude" / "Zucht").
		Tab-Köpfe werden über die Button-Factory gebaut (also automatisch
		FX/Responsiv/Gamepad-fähig), Inhalt darunter wird per Sichtbarkeit
		umgeschaltet.

		Kopfleiste: IMMER eine einzelne, horizontal scrollbare Reihe (Wisch-/
		Mausrad-Scroll, der gewählte Tab wird ins Bild gescrollt) - auf
		schmalen Phones passen 5 Tabs nie nebeneinander, und eine Spalte würde
		aus der festen Kopfhöhe herauslaufen. Gamepad: LB/RB wechseln den Tab
		(nur wenn das Panel dieser Tab-Leiste das oberste offene ist), die
		Hinweise "LB"/"RB" erscheinen nur im Gamepad-Modus.

	Rojo-Einhängepunkt:
		src/shared/UIKit/Tabs.lua -> ReplicatedStorage.UIKit.Tabs
]]

local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")

local Theme = require(script.Parent:WaitForChild("Theme"))
local Button = require(script.Parent:WaitForChild("Button"))
local InputMode = require(script.Parent:WaitForChild("InputMode"))
local Panel = require(script.Parent:WaitForChild("Panel"))
local Signal = require(script.Parent:WaitForChild("Signal"))

local HEADER_HEIGHT = 48
local BUMPER_CHIP_WIDTH = 34

export type TabDefinition = {
	Id: string,
	Label: string,
}

export type TabsProps = {
	Parent: Instance,
	Tabs: { TabDefinition },
	DefaultTabId: string?,
}

export type TabsHandle = {
	HeaderFrame: Frame,
	ContentFrame: Frame,
	Selected: any,
	GetContentFrame: (self: TabsHandle, id: string) -> ScrollingFrame,
	SelectTab: (self: TabsHandle, id: string) -> (),
	Destroy: (self: TabsHandle) -> (),
}

local Tabs = {}

function Tabs.new(props: TabsProps): TabsHandle
	local wrapper = Instance.new("Frame")
	wrapper.Name = "Tabs"
	wrapper.BackgroundTransparency = 1
	wrapper.Size = UDim2.fromScale(1, 1)
	wrapper.Parent = props.Parent

	local headerFrame = Instance.new("Frame")
	headerFrame.Name = "TabHeader"
	headerFrame.BackgroundTransparency = 1
	headerFrame.Size = UDim2.new(1, 0, 0, HEADER_HEIGHT)
	headerFrame.Parent = wrapper

	local tabScroller = Instance.new("ScrollingFrame")
	tabScroller.Name = "TabScroller"
	tabScroller.BackgroundTransparency = 1
	tabScroller.BorderSizePixel = 0
	tabScroller.Size = UDim2.fromScale(1, 1)
	tabScroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabScroller.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabScroller.ScrollingDirection = Enum.ScrollingDirection.X
	tabScroller.ScrollBarThickness = 0
	tabScroller.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
	tabScroller.Parent = headerFrame

	local tabList = Instance.new("UIListLayout")
	tabList.FillDirection = Enum.FillDirection.Horizontal
	tabList.SortOrder = Enum.SortOrder.LayoutOrder
	tabList.Padding = UDim.new(0, 6)
	tabList.VerticalAlignment = Enum.VerticalAlignment.Center
	tabList.Parent = tabScroller

	local leftHint = InputMode.CreateHint({
		Parent = headerFrame,
		Gamepad = Enum.KeyCode.ButtonL1,
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 0, 0.5, 0),
	})
	local rightHint = InputMode.CreateHint({
		Parent = headerFrame,
		Gamepad = Enum.KeyCode.ButtonR1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, 0, 0.5, 0),
	})
	local unbindInputMode = InputMode.Bind(function(mode)
		-- Platz für die LB/RB-Chips nur im Gamepad-Modus reservieren.
		local reserve = if mode == "Gamepad" then BUMPER_CHIP_WIDTH + 4 else 0
		tabScroller.Position = UDim2.fromOffset(reserve, 0)
		tabScroller.Size = UDim2.new(1, -reserve * 2, 1, 0)
	end)

	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "TabContent"
	contentFrame.BackgroundTransparency = 1
	contentFrame.Size = UDim2.new(1, 0, 1, -(HEADER_HEIGHT + 8))
	contentFrame.Position = UDim2.fromOffset(0, HEADER_HEIGHT + 8)
	contentFrame.Parent = wrapper

	local contentFrames: { [string]: ScrollingFrame } = {}
	local buttons: { [string]: any } = {}
	local selected = Signal.new()
	local currentTabId: string? = nil

	local tabOrder: { string } = {}
	for tabIndex, tabDef in props.Tabs do
		local tabContent = Instance.new("ScrollingFrame")
		tabContent.Name = "Content_" .. tabDef.Id
		tabContent.BackgroundTransparency = 1
		tabContent.Size = UDim2.fromScale(1, 1)
		tabContent.CanvasSize = UDim2.new(0, 0, 0, 0)
		tabContent.AutomaticCanvasSize = Enum.AutomaticSize.Y
		tabContent.ScrollBarThickness = 6
		tabContent.ScrollBarImageColor3 = Theme.Neon.Cyan
		tabContent.BorderSizePixel = 0
		tabContent.Visible = false
		tabContent.Parent = contentFrame

		local contentList = Instance.new("UIListLayout")
		contentList.SortOrder = Enum.SortOrder.LayoutOrder
		contentList.Padding = UDim.new(0, 10)
		contentList.Parent = tabContent

		contentFrames[tabDef.Id] = tabContent

		local tabButton = Button.new({
			Parent = tabScroller,
			Text = tabDef.Label,
			Variant = "Ghost",
			Size = UDim2.new(0, 128, 1, -4),
			LayoutOrder = tabIndex,
		})
		buttons[tabDef.Id] = tabButton
		tabOrder[tabIndex] = tabDef.Id
	end

	local handle = {} :: TabsHandle
	handle.HeaderFrame = headerFrame
	handle.ContentFrame = contentFrame
	handle.Selected = selected

	handle.GetContentFrame = function(_self, id: string)
		return contentFrames[id]
	end

	handle.SelectTab = function(_self, id: string)
		if currentTabId == id then
			return
		end
		if currentTabId and contentFrames[currentTabId] then
			contentFrames[currentTabId].Visible = false
			-- Gamepad: Fokus lag auf einem Element des jetzt versteckten Tabs.
			local focused = GuiService.SelectedObject
			if focused and focused:IsDescendantOf(contentFrames[currentTabId]) and buttons[id] then
				GuiService.SelectedObject = (buttons[id] :: any).Instance
			end
		end
		if buttons[currentTabId :: any] then
			(buttons[currentTabId :: any] :: any).Instance.BackgroundColor3 = Theme.Background.PanelLight
		end
		currentTabId = id
		if contentFrames[id] then
			contentFrames[id].Visible = true
		end
		if buttons[id] then
			local selectedButton = (buttons[id] :: any).Instance :: TextButton
			selectedButton.BackgroundColor3 = Theme.Neon.Cyan
			-- Gewählten Tab in der scrollbaren Leiste ins Bild holen.
			task.defer(function()
				if not selectedButton.Parent then
					return
				end
				local buttonCenter = selectedButton.AbsolutePosition.X
					- tabScroller.AbsolutePosition.X
					+ tabScroller.CanvasPosition.X
					+ selectedButton.AbsoluteSize.X / 2
				local target = math.max(buttonCenter - tabScroller.AbsoluteSize.X / 2, 0)
				tabScroller.CanvasPosition = Vector2.new(target, 0)
			end)
		end
		selected:Fire(id)
	end

	for id, tabButton in buttons do
		tabButton.Clicked:Connect(function()
			handle:SelectTab(id)
		end)
	end

	handle:SelectTab(props.DefaultTabId or (props.Tabs[1] and props.Tabs[1].Id) or "")

	-- Gamepad: LB/RB wechseln den Tab, solange das Panel dieser Leiste oben liegt.
	local bumperConnection = UserInputService.InputBegan:Connect(function(input: InputObject, _processed: boolean)
		local direction = 0
		if input.KeyCode == Enum.KeyCode.ButtonR1 then
			direction = 1
		elseif input.KeyCode == Enum.KeyCode.ButtonL1 then
			direction = -1
		else
			return
		end
		local gui = wrapper:FindFirstAncestorWhichIsA("ScreenGui")
		if not gui or not gui.Enabled or Panel.GetTopScreenGui() ~= gui then
			return
		end
		local currentIndex = table.find(tabOrder, currentTabId :: string) or 1
		local nextIndex = math.clamp(currentIndex + direction, 1, #tabOrder)
		if tabOrder[nextIndex] then
			handle:SelectTab(tabOrder[nextIndex])
		end
	end)

	handle.Destroy = function(_self)
		bumperConnection:Disconnect()
		unbindInputMode()
		leftHint:Destroy()
		rightHint:Destroy()
		selected:DisconnectAll()
		for _, tabButton in buttons do
			tabButton:Destroy()
		end
		wrapper:Destroy()
	end

	return handle
end

return Tabs
