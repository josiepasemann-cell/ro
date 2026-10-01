--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Script: ClusterUIController (LocalScript)
	Responsibility:
		Client UI for the Reef Cluster co-op groups (server: ClusterService,
		docs/coop.md): shows your cluster (members, leader, income bonus),
		lets you create / leave a cluster, invite players from the server
		(nearby ones first), kick members (leader) and teleport to a member's
		reef. Incoming invites open a UIKit.ConfirmDialog.

		Display and intent only - the server validates every action. All
		buttons come from UIKit.Button (touch / gamepad / keyboard ready).

		Open: bridge event "OpenCluster" (More drawer entry "Cluster").

	Rojo mount point:
		src/client/ClusterUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.ClusterUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClusterRemotes = require(ReplicatedStorage:WaitForChild("ClusterRemotes"))
local ClusterConfig = require(ReplicatedStorage:WaitForChild("ClusterConfig"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Panel = UIKit.Panel
local Button = UIKit.Button
local Toast = UIKit.Toast
local ConfirmDialog = UIKit.ConfirmDialog
local Device = UIKit.Device

local localPlayer = Players.LocalPlayer

-- // Bridge ---------------------------------------------------------------------------------

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

local openClusterEvent = getOrCreateBridgeEvent("OpenCluster")

-- // Types / state ---------------------------------------------------------------------------

type MemberRow = { UserId: number, Name: string, Level: number, IsLeader: boolean, IsSelf: boolean }

type ClusterState = {
	InCluster: boolean,
	ClusterId: string?,
	LeaderUserId: number?,
	Members: { MemberRow },
	MaxMembers: number,
	BonusPercent: number,
}

type Candidate = {
	UserId: number,
	Name: string,
	Level: number,
	Nearby: boolean,
	Available: boolean,
	Text: string?,
}

local panel: any = nil
local scroller: ScrollingFrame? = nil
local statusLabel: TextLabel? = nil
local dynamicRows: { Instance } = {}
local dynamicHandles: { any } = {}
local lastState: ClusterState = { InCluster = false, Members = {}, MaxMembers = ClusterConfig.MAX_MEMBERS, BonusPercent = 0 }
local lastCandidates: { Candidate } = {}
local panelOpen = false

-- // Helpers -----------------------------------------------------------------------------------

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

local function showToast(text: string, kind: string?)
	local toastType: any = kind or "Info"
	Toast.Show({ Text = text, Type = toastType, Duration = 4 })
end

local function isNarrow(): boolean
	return Device.GetVirtualViewport().X < 560
end

local function clearDynamic()
	for _, handle in ipairs(dynamicHandles) do
		handle:Destroy()
	end
	table.clear(dynamicHandles)
	for _, instance in ipairs(dynamicRows) do
		instance:Destroy()
	end
	table.clear(dynamicRows)
end

local function addRow(parent: Instance, order: number, height: number, accent: Color3): Frame
	local row = Instance.new("Frame")
	row.BackgroundColor3 = Theme.Background.PanelLight
	row.Size = UDim2.new(1, 0, 0, height)
	row.LayoutOrder = order
	row.Parent = parent
	Theme.ApplyCorner(row, UDim.new(0, 12))
	local stroke = Theme.ApplyStroke(row, accent, 2)
	stroke.Transparency = 0.35
	table.insert(dynamicRows, row)
	return row
end

local function addRowButton(row: Frame, text: string, variant: string, width: number, offsetFromRight: number, yScale: number, disabled: boolean?): any
	local handle = Button.new({
		Parent = row,
		Text = text,
		Variant = variant :: any,
		Size = UDim2.fromOffset(width, 44),
		Disabled = disabled,
	})
	handle.Instance.AnchorPoint = Vector2.new(1, 0.5)
	handle.Instance.Position = UDim2.new(1, -offsetFromRight, yScale, 0)
	table.insert(dynamicHandles, handle)
	return handle
end

-- // Rendering --------------------------------------------------------------------------------------

local function render()
	local host = scroller
	local status = statusLabel
	if not host or not status then
		return
	end
	clearDynamic()
	local state = lastState
	local narrow = isNarrow()
	local buttonWidth = if narrow then 76 else 100

	local order = 10
	if state.InCluster then
		status.Text = ("Your Reef Cluster: %d/%d members  -  shared income bonus +%d%% (5%% per other member online, max +15%%)"):format(
			#state.Members,
			state.MaxMembers,
			state.BonusPercent
		)
		status.TextColor3 = Theme.Neon.ToxicGreen
	else
		status.Text = "You are not in a Reef Cluster. Create one and invite up to 3 friends: members earn bonus income and can visit each other's reefs."
		status.TextColor3 = Theme.Text.Secondary
	end

	local amLeader = state.LeaderUserId == localPlayer.UserId

	-- Members
	if state.InCluster then
		local header = makeLabel({
			Parent = host,
			Text = "Members",
			Size = UDim2.new(1, 0, 0, 24),
			Font = Theme.Font.Header,
			MinSize = 14,
			MaxSize = 20,
			LayoutOrder = order,
		})
		table.insert(dynamicRows, header)
		order += 1

		for _, member in ipairs(state.Members) do
			local row = addRow(host, order, 72, if member.IsLeader then Theme.Neon.Yellow else Theme.Neon.Cyan)
			order += 1
			local reserve = if member.IsSelf then 12 else (buttonWidth * (if amLeader then 2 else 1) + 28)
			makeLabel({
				Parent = row,
				Text = (if member.IsLeader then "[Leader] " else "") .. member.Name .. (if member.IsSelf then " (you)" else ""),
				Size = UDim2.new(1, -reserve, 0, 26),
				Font = Theme.Font.BodyBold,
				MinSize = 13,
				MaxSize = 18,
			}).Position = UDim2.fromOffset(12, 10)
			makeLabel({
				Parent = row,
				Text = "Level " .. member.Level,
				Size = UDim2.new(1, -reserve, 0, 22),
				Color = Theme.Text.Secondary,
				MinSize = 12,
				MaxSize = 14,
			}).Position = UDim2.fromOffset(12, 38)

			if not member.IsSelf then
				local visit = addRowButton(row, "Visit", "Primary", buttonWidth, 10, 0.5)
				visit.Clicked:Connect(function()
					ClusterRemotes.RequestTeleportToMember:FireServer(member.UserId)
				end)
				if amLeader then
					local kick = addRowButton(row, "Kick", "Danger", buttonWidth, 10 + buttonWidth + 8, 0.5)
					kick.Clicked:Connect(function()
						ConfirmDialog.Show({
							Title = "Remove member?",
							Message = ("Remove %s from your cluster?"):format(member.Name),
							ConfirmText = "Remove",
							CancelText = "Keep",
							Danger = true,
							OnConfirm = function()
								ClusterRemotes.RequestKickFromCluster:FireServer(member.UserId)
							end,
						})
					end)
				end
			end
		end
	end

	-- Create / leave
	local actionRow = Instance.new("Frame")
	actionRow.BackgroundTransparency = 1
	actionRow.Size = UDim2.new(1, 0, 0, 52)
	actionRow.LayoutOrder = order
	actionRow.Parent = host
	table.insert(dynamicRows, actionRow)
	order += 1
	local action = Button.new({
		Parent = actionRow,
		Text = if state.InCluster then "Leave cluster" else "Create cluster",
		Variant = if state.InCluster then "Danger" else "Success",
		Size = UDim2.new(1, 0, 1, 0),
	})
	table.insert(dynamicHandles, action)
	action.Clicked:Connect(function()
		if lastState.InCluster then
			ClusterRemotes.RequestLeaveCluster:FireServer()
		else
			ClusterRemotes.RequestCreateCluster:FireServer()
		end
	end)

	-- Invite list
	local inviteHeader = makeLabel({
		Parent = host,
		Text = "Invite players (nearby first)",
		Size = UDim2.new(1, 0, 0, 24),
		Font = Theme.Font.Header,
		MinSize = 14,
		MaxSize = 20,
		LayoutOrder = order,
	})
	table.insert(dynamicRows, inviteHeader)
	order += 1

	if #lastCandidates == 0 then
		local empty = makeLabel({
			Parent = host,
			Text = "Nobody else to invite right now.",
			Size = UDim2.new(1, 0, 0, 26),
			Color = Theme.Text.Secondary,
			LayoutOrder = order,
		})
		table.insert(dynamicRows, empty)
		order += 1
	end
	for _, candidate in ipairs(lastCandidates) do
		local row = addRow(host, order, 72, if candidate.Available then Theme.Neon.ToxicGreen else Theme.Background.Divider)
		order += 1
		makeLabel({
			Parent = row,
			Text = ("%s  (Lv %d)%s"):format(candidate.Name, candidate.Level, if candidate.Nearby then "  - nearby" else ""),
			Size = UDim2.new(1, -(buttonWidth + 28), 0, 26),
			Font = Theme.Font.BodyBold,
			MinSize = 13,
			MaxSize = 18,
		}).Position = UDim2.fromOffset(12, 8)
		makeLabel({
			Parent = row,
			Text = if candidate.Available then "Can be invited" else (candidate.Text or "Not available"),
			Size = UDim2.new(1, -(buttonWidth + 28), 0, 24),
			Color = if candidate.Available then Theme.Neon.ToxicGreen else Theme.Semantic.Warning,
			MinSize = 12,
			MaxSize = 14,
			Wrapped = true,
		}).Position = UDim2.fromOffset(12, 38)
		local invite = addRowButton(row, "Invite", "Primary", buttonWidth, 10, 0.5, not candidate.Available)
		invite.Clicked:Connect(function()
			ClusterRemotes.RequestInviteToCluster:FireServer(candidate.UserId)
		end)
	end
end

local lastFetchAt = 0

local function fetchInfo()
	local now = os.clock()
	if now - lastFetchAt < 0.6 then
		return -- server rate limit
	end
	lastFetchAt = now
	local ok, info = pcall(function()
		return ClusterRemotes.GetClusterInfo:InvokeServer()
	end)
	if ok and type(info) == "table" and type(info.State) == "table" then
		lastState = info.State
		lastCandidates = info.Candidates or {}
		if panelOpen then
			render()
		end
	end
end

local function buildPanel()
	if panel then
		return
	end
	panel = Panel.new({
		Title = "Reef Cluster",
		Closable = true,
		CenteredSize = UDim2.fromOffset(600, 700),
		OnClose = function()
			panelOpen = false
		end,
	})
	local content: Frame = panel.Content

	local host = Instance.new("ScrollingFrame")
	host.BackgroundTransparency = 1
	host.Size = UDim2.new(1, 0, 1, -56)
	host.CanvasSize = UDim2.new()
	host.AutomaticCanvasSize = Enum.AutomaticSize.Y
	host.ScrollBarThickness = 6
	host.ScrollBarImageColor3 = Theme.Neon.Cyan
	host.BorderSizePixel = 0
	host.Parent = content
	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = host
	scroller = host

	statusLabel = makeLabel({
		Parent = host,
		Text = "",
		Size = UDim2.new(1, 0, 0, 56),
		Wrapped = true,
		MinSize = 12,
		MaxSize = 15,
		LayoutOrder = 1,
	})

	local footer = Instance.new("Frame")
	footer.BackgroundTransparency = 1
	footer.AnchorPoint = Vector2.new(0, 1)
	footer.Position = UDim2.fromScale(0, 1)
	footer.Size = UDim2.new(1, 0, 0, 48)
	footer.Parent = content
	local refresh = Button.new({
		Parent = footer,
		Text = "Refresh",
		Variant = "Secondary",
		Size = UDim2.new(1, 0, 1, 0),
	})
	refresh.Clicked:Connect(fetchInfo)
end

local function openPanel()
	buildPanel()
	panelOpen = true
	panel:Open()
	render()
	task.spawn(function()
		lastFetchAt = 0
		fetchInfo()
	end)
end

-- // Remote wiring ---------------------------------------------------------------------------------------

openClusterEvent.Event:Connect(openPanel)

ClusterRemotes.ClusterState.OnClientEvent:Connect(function(state: ClusterState)
	if type(state) ~= "table" or type(state.InCluster) ~= "boolean" then
		return
	end
	lastState = state
	if panelOpen then
		render()
		task.delay(0.7, function()
			if panelOpen then
				fetchInfo() -- refresh the invite list (candidates changed)
			end
		end)
	end
end)

ClusterRemotes.ClusterNotice.OnClientEvent:Connect(function(payload: { Text: string?, Kind: string? })
	if type(payload) == "table" and type(payload.Text) == "string" then
		showToast(payload.Text, payload.Kind)
	end
end)

ClusterRemotes.ClusterInviteReceived.OnClientEvent:Connect(function(payload: { InviteId: string, FromName: string })
	if type(payload) ~= "table" or type(payload.InviteId) ~= "string" then
		return
	end
	local inviteId = payload.InviteId
	ConfirmDialog.Show({
		Title = "Reef Cluster invite",
		Message = ("%s invites you to join their Reef Cluster. Members earn bonus income and can visit each other's reefs."):format(
			tostring(payload.FromName)
		),
		ConfirmText = "Join",
		CancelText = "No thanks",
		OnConfirm = function()
			ClusterRemotes.RespondClusterInvite:FireServer(inviteId, true)
		end,
		OnCancel = function()
			ClusterRemotes.RespondClusterInvite:FireServer(inviteId, false)
		end,
	})
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	clearDynamic()
	if panel then
		panel:Destroy()
	end
end)
