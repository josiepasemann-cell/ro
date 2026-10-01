--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Script: TradeUIController (LocalScript)
	Responsibility:
		Client UI for the secure 2-player creature trade (server: TradeService,
		docs/trading.md). Display and intent only - every click is validated
		again by the server, the revision number guards against last-second swaps.

		Screens:
			1. Picker   - players in the server (opened by the trade dock prompt
			              via TradeRemotes.OpenTradePicker or the "Trade" entry in
			              the More drawer, bridge event "OpenTrade").
			2. Request  - UIKit.ConfirmDialog when somebody asks you to trade.
			3. Window   - "You offer" / "Partner offers" slots, your creature grid,
			              Ready -> Confirm (with countdown) -> Cancel.

		All buttons come from UIKit.Button (touch / gamepad / keyboard ready).
		Closing the trade window (X, B, another menu shortcut) cancels the trade.

	Rojo mount point:
		src/client/TradeUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.TradeUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TradeRemotes = require(ReplicatedStorage:WaitForChild("TradeRemotes"))
local TradeConfig = require(ReplicatedStorage:WaitForChild("TradeConfig"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Panel = UIKit.Panel
local Button = UIKit.Button
local Toast = UIKit.Toast
local ConfirmDialog = UIKit.ConfirmDialog

local localPlayer = Players.LocalPlayer

-- // Bridge -----------------------------------------------------------------------------

local function getOrCreateBridgeEvent(eventName: string): BindableEvent
	local bridge = ReplicatedStorage:FindFirstChild("AbyssaraUIBridge")
	if not bridge then
		bridge = Instance.new("Folder")
		bridge.Name = "AbyssaraUIBridge"
		bridge.Parent = ReplicatedStorage
	end
	local event = bridge:FindFirstChild(eventName)
	if not event then
		event = Instance.new("BindableEvent")
		event.Name = eventName
		event.Parent = bridge
	end
	return event :: BindableEvent
end

local openTradeEvent = getOrCreateBridgeEvent("OpenTrade")

-- // Types --------------------------------------------------------------------------------

type OfferEntry = { InstanceId: string, CreatureId: string, Rarity: string }

type Snapshot = {
	TradeId: string,
	Revision: number,
	Phase: string,
	PartnerUserId: number,
	PartnerName: string,
	MyOffer: { OfferEntry },
	PartnerOffer: { OfferEntry },
	MyReady: boolean,
	PartnerReady: boolean,
	MyConfirmed: boolean,
	PartnerConfirmed: boolean,
	ConfirmUnlockIn: number,
	MaxOffer: number,
}

type InventoryEntry = {
	InstanceId: string,
	CreatureId: string,
	Rarity: string,
	Locked: string?,
	Guardian: boolean?,
}

-- // Helpers ---------------------------------------------------------------------------------

local function makeLabel(props: {
	Parent: Instance,
	Text: string,
	Size: UDim2,
	Font: Enum.Font?,
	Color: Color3?,
	MinSize: number?,
	MaxSize: number?,
	XAlign: Enum.TextXAlignment?,
	Wrapped: boolean?,
	LayoutOrder: number?,
}): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = props.Size
	label.Font = props.Font or Theme.Font.Body
	label.TextColor3 = props.Color or Theme.Text.Primary
	label.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
	label.TextScaled = true
	label.TextWrapped = props.Wrapped or false
	label.Text = props.Text
	label.LayoutOrder = props.LayoutOrder or 0
	label.Parent = props.Parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = math.max(props.MinSize or 12, 12)
	constraint.MaxTextSize = props.MaxSize or 16
	constraint.Parent = label
	return label
end

local function creatureName(creatureId: string): string
	local spaced = creatureId:gsub("(%l)(%u)", "%1 %2")
	return spaced
end

local function rarityColor(rarity: string): Color3
	local colors: any = Theme.Rarity
	return colors[rarity] or Theme.Text.Secondary
end

local function entryText(entry: { CreatureId: string, Rarity: string }): string
	return creatureName(entry.CreatureId) .. "\n" .. entry.Rarity
end

--- Thin rarity-colored bar at the bottom of a card/button.
local function addRarityBar(parent: GuiObject, color: Color3): Frame
	local bar = Instance.new("Frame")
	bar.Name = "RarityBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -3)
	bar.Size = UDim2.new(1, -16, 0, 4)
	bar.BackgroundColor3 = color
	bar.BorderSizePixel = 0
	bar.ZIndex = parent.ZIndex + 5
	Theme.ApplyCorner(bar, UDim.new(1, 0))
	bar.Parent = parent
	return bar
end

local function makeSectionHeader(parent: Instance, text: string, order: number): TextLabel
	return makeLabel({
		Parent = parent,
		Text = text,
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.Font.Header,
		MinSize = 14,
		MaxSize = 20,
		LayoutOrder = order,
	})
end

local function makeGrid(parent: Instance, order: number, cellHeight: number): Frame
	local host = Instance.new("Frame")
	host.BackgroundTransparency = 1
	host.AutomaticSize = Enum.AutomaticSize.Y
	host.Size = UDim2.new(1, 0, 0, 0)
	host.LayoutOrder = order
	host.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0.5, -4, 0, cellHeight)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = host
	return host
end

local function makeScroller(parent: Instance, size: UDim2): ScrollingFrame
	local scroller = Instance.new("ScrollingFrame")
	scroller.BackgroundTransparency = 1
	scroller.Size = size
	scroller.CanvasSize = UDim2.new()
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = Theme.Neon.Cyan
	scroller.BorderSizePixel = 0
	scroller.Parent = parent
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = scroller
	return scroller
end

local function showToast(text: string, kind: string?)
	local toastType: any = kind or "Info"
	Toast.Show({ Text = text, Type = toastType, Duration = 4 })
end

-- // Trade window ---------------------------------------------------------------------------------

type SlotButton = { Handle: any, Bar: Frame, InstanceId: string? }
type PartnerSlot = { Frame: Frame, Label: TextLabel, Stroke: UIStroke, Bar: Frame }
type InventoryCard = { Handle: any, Entry: InventoryEntry, Stroke: UIStroke, BaseText: string }

type Window = {
	Panel: any,
	Status: TextLabel,
	MySlots: { SlotButton },
	PartnerSlots: { PartnerSlot },
	PartnerHeader: TextLabel,
	Cards: { [string]: InventoryCard },
	ReadyButton: any,
	ConfirmButton: any,
	CancelButton: any,
	Snapshot: Snapshot?,
	SnapshotAt: number,
	Closing: boolean,
	Destroyed: boolean,
}

local window: Window? = nil

local function currentOfferIds(snapshot: Snapshot): { string }
	local ids = {}
	for _, entry in ipairs(snapshot.MyOffer) do
		table.insert(ids, entry.InstanceId)
	end
	return ids
end

local function sendOffer(win: Window, ids: { string })
	local snapshot = win.Snapshot
	if not snapshot then
		return
	end
	TradeRemotes.SetTradeOffer:FireServer(snapshot.TradeId, ids)
end

local function summarize(list: { OfferEntry }): string
	if #list == 0 then
		return "nothing"
	end
	local names = {}
	for _, entry in ipairs(list) do
		table.insert(names, creatureName(entry.CreatureId))
	end
	return table.concat(names, ", ")
end

local function refreshWindow(win: Window)
	local snapshot = win.Snapshot
	if not snapshot or win.Destroyed then
		return
	end
	local confirmPhase = snapshot.Phase == "Confirm"

	win.PartnerHeader.Text = snapshot.PartnerName .. " offers"

	-- Own offer slots
	local offered: { [string]: boolean } = {}
	for index, slot in ipairs(win.MySlots) do
		local entry = snapshot.MyOffer[index]
		if entry then
			offered[entry.InstanceId] = true
			slot.InstanceId = entry.InstanceId
			slot.Handle:SetText(entryText(entry))
			slot.Handle:SetDisabled(confirmPhase)
			slot.Bar.BackgroundColor3 = rarityColor(entry.Rarity)
			slot.Bar.Visible = true
		else
			slot.InstanceId = nil
			slot.Handle:SetText("Empty slot")
			slot.Handle:SetDisabled(true)
			slot.Bar.Visible = false
		end
	end

	-- Partner slots
	for index, slot in ipairs(win.PartnerSlots) do
		local entry = snapshot.PartnerOffer[index]
		if entry then
			slot.Label.Text = entryText(entry)
			slot.Label.TextColor3 = Theme.Text.Primary
			slot.Stroke.Color = rarityColor(entry.Rarity)
			slot.Bar.BackgroundColor3 = rarityColor(entry.Rarity)
			slot.Bar.Visible = true
		else
			slot.Label.Text = "Empty slot"
			slot.Label.TextColor3 = Theme.Text.Muted
			slot.Stroke.Color = Theme.Background.Divider
			slot.Bar.Visible = false
		end
	end

	-- Inventory cards
	for instanceId, card in pairs(win.Cards) do
		local selected = offered[instanceId] == true
		local text = card.BaseText
		if card.Entry.Locked then
			text ..= "\n(" .. (if string.find(card.Entry.Locked, "buddy", 1, true) then "Buddy" else "Locked") .. ")"
		elseif card.Entry.Guardian then
			text ..= " - Guardian"
		end
		card.Handle:SetText((if selected then "[x] " else "") .. text)
		card.Handle:SetDisabled(card.Entry.Locked ~= nil or confirmPhase)
		card.Stroke.Thickness = if selected then 4 else 1
	end

	-- Ready button
	win.ReadyButton:SetText(if snapshot.MyReady then "Not ready" else "Ready")
	win.ConfirmButton:SetDisabled(true)
	win.ConfirmButton:SetText("Confirm")

	-- Status line
	if confirmPhase then
		local gaveNothing = #snapshot.MyOffer == 0
		local text = ("FINAL CHECK  -  You give: %s.  You get: %s."):format(
			summarize(snapshot.MyOffer),
			summarize(snapshot.PartnerOffer)
		)
		if gaveNothing or #snapshot.PartnerOffer == 0 then
			text ..= "  (One side is empty - this is a gift!)"
		end
		if snapshot.MyConfirmed then
			text ..= "  Waiting for " .. snapshot.PartnerName .. " to confirm..."
		elseif snapshot.PartnerConfirmed then
			text ..= "  " .. snapshot.PartnerName .. " already confirmed."
		end
		win.Status.Text = text
	else
		local mine = if snapshot.MyReady then "ready" else "not ready"
		local theirs = if snapshot.PartnerReady then "ready" else "not ready"
		win.Status.Text = ("Offer up to %d creatures. Any change resets Ready.  You: %s  -  %s: %s"):format(
			snapshot.MaxOffer,
			mine,
			snapshot.PartnerName,
			theirs
		)
	end
end

--- Countdown on the Confirm button (runs only while a window exists).
local function runCountdown(win: Window)
	task.spawn(function()
		while not win.Destroyed do
			task.wait(0.1)
			local snapshot = win.Snapshot
			if snapshot and snapshot.Phase == "Confirm" and not snapshot.MyConfirmed then
				local remaining = snapshot.ConfirmUnlockIn - (os.clock() - win.SnapshotAt)
				if remaining > 0 then
					win.ConfirmButton:SetDisabled(true)
					win.ConfirmButton:SetText(("Confirm (%d)"):format(math.ceil(remaining)))
				else
					win.ConfirmButton:SetDisabled(false)
					win.ConfirmButton:SetText("Confirm")
				end
			end
		end
	end)
end

local function destroyWindow(win: Window)
	if win.Destroyed then
		return
	end
	win.Destroyed = true
	if window == win then
		window = nil
	end
	task.delay(0.6, function()
		for _, slot in ipairs(win.MySlots) do
			slot.Handle:Destroy()
		end
		for _, card in pairs(win.Cards) do
			card.Handle:Destroy()
		end
		win.ReadyButton:Destroy()
		win.ConfirmButton:Destroy()
		win.CancelButton:Destroy()
		win.Panel:Destroy()
	end)
end

local function populateInventory(win: Window, container: Frame)
	local info: any = nil
	for _ = 1, 3 do
		local ok, result = pcall(function()
			return TradeRemotes.GetTradeInfo:InvokeServer()
		end)
		if ok and type(result) == "table" then
			info = result
			break
		end
		task.wait(0.7) -- server rate limit / data not ready yet
	end
	if win.Destroyed then
		return
	end
	if not info then
		showToast("Could not load your creatures. Close and reopen the trade.", "Warning")
		return
	end

	local list: { InventoryEntry } = info.Inventory
	table.sort(list, function(a, b)
		local order: { string } = Theme.RarityOrder :: any
		local ia = table.find(order, a.Rarity) or 0
		local ib = table.find(order, b.Rarity) or 0
		if ia ~= ib then
			return ia > ib
		end
		return a.CreatureId < b.CreatureId
	end)

	if #list == 0 then
		makeLabel({
			Parent = container,
			Text = "You have no creatures to trade yet.",
			Size = UDim2.new(1, 0, 0, 24),
			Color = Theme.Text.Secondary,
		})
	end

	for index, entry in ipairs(list) do
		local handle = Button.new({
			Parent = container,
			Text = entryText(entry),
			Variant = "Ghost",
			Size = UDim2.new(0.5, -4, 0, 56),
			LayoutOrder = index,
		})
		local stroke = Theme.ApplyStroke(handle.Instance, rarityColor(entry.Rarity), 1)
		addRarityBar(handle.Instance, rarityColor(entry.Rarity))
		win.Cards[entry.InstanceId] = {
			Handle = handle,
			Entry = entry,
			Stroke = stroke,
			BaseText = entryText(entry),
		}
		handle.Clicked:Connect(function()
			local snapshot = win.Snapshot
			if not snapshot or snapshot.Phase ~= "Editing" then
				return
			end
			local ids = currentOfferIds(snapshot)
			local at = table.find(ids, entry.InstanceId)
			if at then
				table.remove(ids, at)
			else
				if #ids >= snapshot.MaxOffer then
					showToast(("You can offer up to %d creatures."):format(snapshot.MaxOffer), "Warning")
					return
				end
				table.insert(ids, entry.InstanceId)
			end
			sendOffer(win, ids)
		end)
	end
	refreshWindow(win)
end

local function buildWindow(): Window
	local panel = Panel.new({
		Title = "Trade",
		Closable = true,
		CenteredSize = UDim2.fromOffset(700, 720),
	})

	local content: Frame = panel.Content
	local scroller = makeScroller(content, UDim2.new(1, 0, 1, -64))

	local status = makeLabel({
		Parent = scroller,
		Text = "Waiting for the trade to start...",
		Size = UDim2.new(1, 0, 0, 56),
		Color = Theme.Neon.Yellow,
		MinSize = 12,
		MaxSize = 15,
		Wrapped = true,
		LayoutOrder = 1,
	})

	makeSectionHeader(scroller, "You offer (tap a creature to take it back)", 2)
	local myGrid = makeGrid(scroller, 3, 56)
	local partnerHeader = makeSectionHeader(scroller, "Partner offers", 4)
	local partnerGrid = makeGrid(scroller, 5, 56)
	makeSectionHeader(scroller, "Your creatures (tap to offer)", 6)
	local inventoryGrid = makeGrid(scroller, 7, 56)

	local win: Window = {
		Panel = panel,
		Status = status,
		MySlots = {},
		PartnerSlots = {},
		PartnerHeader = partnerHeader,
		Cards = {},
		ReadyButton = nil,
		ConfirmButton = nil,
		CancelButton = nil,
		Snapshot = nil,
		SnapshotAt = 0,
		Closing = false,
		Destroyed = false,
	}

	for index = 1, TradeConfig.MAX_OFFER do
		local handle = Button.new({
			Parent = myGrid,
			Text = "Empty slot",
			Variant = "Secondary",
			Size = UDim2.new(0.5, -4, 0, 56),
			LayoutOrder = index,
			Disabled = true,
		})
		local bar = addRarityBar(handle.Instance, Theme.Text.Secondary)
		bar.Visible = false
		table.insert(win.MySlots, { Handle = handle, Bar = bar, InstanceId = nil })
		handle.Clicked:Connect(function()
			local snapshot = win.Snapshot
			local slot = win.MySlots[index]
			if not snapshot or snapshot.Phase ~= "Editing" or not slot.InstanceId then
				return
			end
			local ids = currentOfferIds(snapshot)
			local at = table.find(ids, slot.InstanceId)
			if at then
				table.remove(ids, at)
				sendOffer(win, ids)
			end
		end)

		local frame = Instance.new("Frame")
		frame.BackgroundColor3 = Theme.Background.PanelLight
		frame.LayoutOrder = index
		frame.Parent = partnerGrid
		Theme.ApplyCorner(frame, UDim.new(0, 10))
		local stroke = Theme.ApplyStroke(frame, Theme.Background.Divider, 2)
		local label = makeLabel({
			Parent = frame,
			Text = "Empty slot",
			Size = UDim2.new(1, -12, 1, -12),
			Color = Theme.Text.Muted,
			XAlign = Enum.TextXAlignment.Center,
			Wrapped = true,
			MinSize = 12,
			MaxSize = 16,
		})
		label.Position = UDim2.fromOffset(6, 4)
		local partnerBar = addRarityBar(frame, Theme.Text.Secondary)
		partnerBar.Visible = false
		table.insert(win.PartnerSlots, { Frame = frame, Label = label, Stroke = stroke, Bar = partnerBar })
	end

	-- Footer: Ready / Confirm / Cancel
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, 56)
	footer.Parent = content
	local footerLayout = Instance.new("UIListLayout")
	footerLayout.FillDirection = Enum.FillDirection.Horizontal
	footerLayout.Padding = UDim.new(0, 8)
	footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	footerLayout.SortOrder = Enum.SortOrder.LayoutOrder
	footerLayout.Parent = footer

	local function footerSize(): UDim2
		return UDim2.new(1 / 3, -6, 1, 0)
	end
	win.ReadyButton = Button.new({
		Parent = footer,
		Text = "Ready",
		Variant = "Primary",
		Size = footerSize(),
		LayoutOrder = 1,
	})
	win.ConfirmButton = Button.new({
		Parent = footer,
		Text = "Confirm",
		Variant = "Success",
		Size = footerSize(),
		LayoutOrder = 2,
		Disabled = true,
	})
	win.CancelButton = Button.new({
		Parent = footer,
		Text = "Cancel trade",
		Variant = "Danger",
		Size = footerSize(),
		LayoutOrder = 3,
	})

	win.ReadyButton.Clicked:Connect(function()
		local snapshot = win.Snapshot
		if snapshot then
			TradeRemotes.SetTradeReady:FireServer(snapshot.TradeId, not snapshot.MyReady, snapshot.Revision)
		end
	end)
	win.ConfirmButton.Clicked:Connect(function()
		local snapshot = win.Snapshot
		if snapshot and snapshot.Phase == "Confirm" and not snapshot.MyConfirmed then
			TradeRemotes.ConfirmTrade:FireServer(snapshot.TradeId, snapshot.Revision)
			win.ConfirmButton:SetDisabled(true) -- re-enabled by the next server snapshot if needed
		end
	end)
	win.CancelButton.Clicked:Connect(function()
		panel:Close() -- Closed handler below sends the cancel
	end)

	panel.Closed:Connect(function()
		local snapshot = win.Snapshot
		if snapshot and not win.Closing then
			TradeRemotes.CancelTrade:FireServer(snapshot.TradeId)
		end
		win.Closing = true
		destroyWindow(win)
	end)

	task.spawn(populateInventory, win, inventoryGrid)
	runCountdown(win)
	panel:Open()
	return win
end

-- // Picker --------------------------------------------------------------------------------------------

type PickerState = {
	Panel: any,
	Info: TextLabel,
	List: ScrollingFrame,
	Handles: { any },
	Rows: { Instance },
}

local picker: PickerState? = nil

local function clearPickerRows(state: PickerState)
	for _, handle in ipairs(state.Handles) do
		handle:Destroy()
	end
	table.clear(state.Handles)
	for _, row in ipairs(state.Rows) do
		row:Destroy()
	end
	table.clear(state.Rows)
end

local function refreshPicker(state: PickerState)
	local ok, info = pcall(function()
		return TradeRemotes.GetTradeInfo:InvokeServer()
	end)
	if not ok or type(info) ~= "table" then
		state.Info.Text = "Could not load players. Press Refresh."
		return
	end
	clearPickerRows(state)

	if info.BlockedText then
		state.Info.Text = info.BlockedText
		state.Info.TextColor3 = Theme.Semantic.Warning
	else
		state.Info.Text = ("Pick a player standing close to you. Trading unlocks at level %d (you are level %d)."):format(
			info.MinLevel,
			info.Level
		)
		state.Info.TextColor3 = Theme.Text.Secondary
	end

	local players: { any } = info.Players
	if #players == 0 then
		local empty = makeLabel({
			Parent = state.List,
			Text = "Nobody else is in this server right now.",
			Size = UDim2.new(1, 0, 0, 28),
			Color = Theme.Text.Secondary,
		})
		table.insert(state.Rows, empty)
		return
	end

	for index, entry in ipairs(players) do
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Theme.Background.PanelLight
		row.Size = UDim2.new(1, 0, 0, 72)
		row.LayoutOrder = index
		row.Parent = state.List
		Theme.ApplyCorner(row, UDim.new(0, 12))
		Theme.ApplyStroke(row, if entry.Available then Theme.Neon.ToxicGreen else Theme.Background.Divider, 2)
		table.insert(state.Rows, row)

		makeLabel({
			Parent = row,
			Text = ("%s  (Lv %d)"):format(entry.Name, entry.Level),
			Size = UDim2.new(1, -150, 0, 26),
			Font = Theme.Font.BodyBold,
			MinSize = 13,
			MaxSize = 18,
		}).Position = UDim2.fromOffset(12, 8)
		makeLabel({
			Parent = row,
			Text = if entry.Available then "Ready to trade" else (entry.Text or "Not available"),
			Size = UDim2.new(1, -150, 0, 28),
			Color = if entry.Available then Theme.Neon.ToxicGreen else Theme.Semantic.Warning,
			MinSize = 12,
			MaxSize = 14,
			Wrapped = true,
		}).Position = UDim2.fromOffset(12, 36)

		local request = Button.new({
			Parent = row,
			Text = "Request",
			Variant = "Primary",
			Size = UDim2.fromOffset(120, 48),
			Disabled = not entry.Available,
		})
		request.Instance.AnchorPoint = Vector2.new(1, 0.5)
		request.Instance.Position = UDim2.new(1, -10, 0.5, 0)
		table.insert(state.Handles, request)
		request.Clicked:Connect(function()
			TradeRemotes.RequestTrade:FireServer(entry.UserId)
			state.Panel:Close()
		end)
	end
end

local function openPicker()
	if window then
		return -- already trading
	end
	if not picker then
		local panel = Panel.new({
			Title = "Trade Dock",
			Closable = true,
			CenteredSize = UDim2.fromOffset(560, 640),
		})
		local content: Frame = panel.Content
		local info = makeLabel({
			Parent = content,
			Text = "Loading...",
			Size = UDim2.new(1, 0, 0, 44),
			Color = Theme.Text.Secondary,
			MinSize = 12,
			MaxSize = 15,
			Wrapped = true,
		})
		local list = makeScroller(content, UDim2.new(1, 0, 1, -116))
		list.Position = UDim2.fromOffset(0, 50)

		local footer = Instance.new("Frame")
		footer.BackgroundTransparency = 1
		footer.AnchorPoint = Vector2.new(0, 1)
		footer.Position = UDim2.fromScale(0, 1)
		footer.Size = UDim2.new(1, 0, 0, 56)
		footer.Parent = content
		local footerLayout = Instance.new("UIListLayout")
		footerLayout.FillDirection = Enum.FillDirection.Horizontal
		footerLayout.Padding = UDim.new(0, 8)
		footerLayout.VerticalAlignment = Enum.VerticalAlignment.Center
		footerLayout.Parent = footer

		local state: PickerState = { Panel = panel, Info = info, List = list, Handles = {}, Rows = {} }
		local refresh = Button.new({
			Parent = footer,
			Text = "Refresh",
			Variant = "Secondary",
			Size = UDim2.new(0.5, -4, 1, 0),
		})
		refresh.Clicked:Connect(function()
			refreshPicker(state)
		end)
		local cancelRequest = Button.new({
			Parent = footer,
			Text = "Cancel my request",
			Variant = "Ghost",
			Size = UDim2.new(0.5, -4, 1, 0),
		})
		cancelRequest.Clicked:Connect(function()
			TradeRemotes.CancelTrade:FireServer("request")
			showToast("Request cancelled.", "Info")
		end)
		picker = state
	end
	local state = picker :: PickerState
	state.Panel:Open()
	task.spawn(refreshPicker, state)
end

-- // Remote wiring ---------------------------------------------------------------------------------------

TradeRemotes.OpenTradePicker.OnClientEvent:Connect(openPicker)
openTradeEvent.Event:Connect(openPicker)

TradeRemotes.TradeNotice.OnClientEvent:Connect(function(payload: { Text: string?, Kind: string? })
	if type(payload) == "table" and type(payload.Text) == "string" then
		showToast(payload.Text, payload.Kind)
	end
end)

TradeRemotes.TradeRequestReceived.OnClientEvent:Connect(function(payload: {
	RequestId: string,
	FromName: string,
	ExpiresIn: number,
})
	if type(payload) ~= "table" or type(payload.RequestId) ~= "string" then
		return
	end
	local requestId = payload.RequestId
	ConfirmDialog.Show({
		Title = "Trade request",
		Message = ("%s wants to trade creatures with you. Accept?"):format(tostring(payload.FromName)),
		ConfirmText = "Accept",
		CancelText = "Decline",
		OnConfirm = function()
			TradeRemotes.RespondTradeRequest:FireServer(requestId, true)
		end,
		OnCancel = function()
			TradeRemotes.RespondTradeRequest:FireServer(requestId, false)
		end,
	})
end)

TradeRemotes.TradeState.OnClientEvent:Connect(function(snapshot: Snapshot)
	if type(snapshot) ~= "table" or type(snapshot.TradeId) ~= "string" then
		return
	end
	if not window then
		if picker then
			picker.Panel:Close()
		end
		window = buildWindow()
	end
	local win = window :: Window
	win.Snapshot = snapshot
	win.SnapshotAt = os.clock()
	refreshWindow(win)
end)

TradeRemotes.TradeClosed.OnClientEvent:Connect(function(payload: { Completed: boolean?, Text: string? })
	if type(payload) == "table" then
		showToast(payload.Text or "Trade closed.", if payload.Completed then "Success" else "Warning")
	end
	local win = window
	if win then
		win.Closing = true -- server already closed it, do not send a cancel
		win.Panel:Close()
		destroyWindow(win)
	end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	if picker then
		picker.Panel:Destroy()
	end
end)
