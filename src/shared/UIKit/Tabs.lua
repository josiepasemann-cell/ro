--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Modul: UIKit.Tabs
	Zuständigkeit:
		Tab-Leiste für Panels (z. B. "Kreaturen" / "Gebäude" / "Zucht").
		Tab-Köpfe werden über die Button-Factory gebaut (also automatisch
		FX/Responsiv/Gamepad-fähig), Inhalt darunter wird per Sichtbarkeit
		umgeschaltet.

	Rojo-Einhängepunkt:
		src/shared/UIKit/Tabs.lua -> ReplicatedStorage.UIKit.Tabs
]]

local Theme = require(script.Parent:WaitForChild("Theme"))
local Button = require(script.Parent:WaitForChild("Button"))
local Layout = require(script.Parent:WaitForChild("Layout"))
local Signal = require(script.Parent:WaitForChild("Signal"))

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
	headerFrame.Size = UDim2.new(1, 0, 0, 44)
	headerFrame.Parent = wrapper

	local row = Layout.ResponsiveRow({
		Parent = headerFrame,
		Padding = 6,
		HorizontalAlignment = Enum.HorizontalAlignment.Left,
	})
	row.Frame.Size = UDim2.fromScale(1, 1)

	local contentFrame = Instance.new("Frame")
	contentFrame.Name = "TabContent"
	contentFrame.BackgroundTransparency = 1
	contentFrame.Size = UDim2.new(1, 0, 1, -52)
	contentFrame.Position = UDim2.fromOffset(0, 52)
	contentFrame.Parent = wrapper

	local contentFrames: { [string]: ScrollingFrame } = {}
	local buttons: { [string]: any } = {}
	local selected = Signal.new()
	local currentTabId: string? = nil

	for _, tabDef in props.Tabs do
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

		local tabList = Instance.new("UIListLayout")
		tabList.SortOrder = Enum.SortOrder.LayoutOrder
		tabList.Padding = UDim.new(0, 10)
		tabList.Parent = tabContent

		contentFrames[tabDef.Id] = tabContent

		local tabButton = Button.new({
			Parent = row.Frame,
			Text = tabDef.Label,
			Variant = "Ghost",
			Size = UDim2.new(0, 140, 1, 0),
		})
		buttons[tabDef.Id] = tabButton
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
		end
		if buttons[currentTabId :: any] then
			(buttons[currentTabId :: any] :: any).Instance.BackgroundColor3 = Theme.Background.PanelLight
		end
		currentTabId = id
		if contentFrames[id] then
			contentFrames[id].Visible = true
		end
		if buttons[id] then
			(buttons[id] :: any).Instance.BackgroundColor3 = Theme.Neon.Cyan
		end
		selected:Fire(id)
	end

	for id, tabButton in buttons do
		tabButton.Clicked:Connect(function()
			handle:SelectTab(id)
		end)
	end

	handle:SelectTab(props.DefaultTabId or (props.Tabs[1] and props.Tabs[1].Id) or "")

	handle.Destroy = function(_self)
		selected:DisconnectAll()
		for _, tabButton in buttons do
			tabButton:Destroy()
		end
		row:Destroy()
		wrapper:Destroy()
	end

	return handle
end

return Tabs
