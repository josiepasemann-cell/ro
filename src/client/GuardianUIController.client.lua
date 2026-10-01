--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Script: GuardianUIController (LocalScript)
	Responsibility:
		Client UI for raid guardians and co-op raids (docs/guardians-and-coop.md):
			1) Loadout panel (More drawer -> "Guardians", bridge event
			   "OpenGuardians"): pick the creatures that defend your plot, up to the
			   number of slots your level unlocks (RaidConfig.GUARDIAN_SLOT_UNLOCK_LEVELS).
			   Every change is only a request (RequestSetGuardianLoadout); the
			   server validates ownership/abduction/slot count and answers with
			   the stored loadout.
			2) Raid HUD: guardian cards with portrait and HP (own and cluster
			   mates' guardians), a "Deploy Guardians" button and, for co-op
			   helpers, a "Leave raid" button. The loadout is deployed
			   automatically at raid start / join (RequestDeployGuardian carries no
			   ids - the server deploys the saved loadout); the button is the
			   manual fallback.
			3) Guardian attack effects (coloured beam guardian -> enemy).
			4) Co-op: prompt when a Reef Cluster mate's plot is raided ("Join &
			   Defend" teleports you there, the server checks cluster membership).

		Display only. Damage, HP, knock-outs, rewards and membership are all
		decided by RaidService; nothing here is trusted by the server.

		Layout: the card strip docks at the left edge below the raid bar on
		landscape/desktop and below the ability bar in portrait; all buttons are
		UIKit buttons (touch, gamepad, keyboard).

	Rojo mount point:
		src/client/GuardianUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.GuardianUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local RaidRemotes = require(ReplicatedStorage:WaitForChild("RaidRemotes"))
local RaidConfig = require(ReplicatedStorage:WaitForChild("RaidConfig"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Layout = UIKit.Layout
local Panel = UIKit.Panel
local Button = UIKit.Button
local Toast = UIKit.Toast
local ConfirmDialog = UIKit.ConfirmDialog
local Settings = UIKit.Settings

local player = Players.LocalPlayer

-- // Bridge (see MainMenuController.client.lua header) ---------------------------------
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

local openGuardiansEvent = getOrCreateBridgeEvent("OpenGuardians")

-- // Helpers -----------------------------------------------------------------------------

local MAX_CARDS = 6

local function rarityColor(rarity: string): Color3
	local key = rarity :: any
	if table.find(Theme.RarityOrder, key) then
		return Theme.Rarity[key]
	end
	return Theme.Neon.Orange -- e.g. Abyssal
end

local function prettyName(creatureId: string): string
	return (creatureId:gsub("(%l)(%u)", "%1 %2"))
end

local function findCreatureTemplate(creatureId: string): Model?
	local assetsFolder = Workspace:FindFirstChild("Assets")
	local creaturesFolder = assetsFolder and assetsFolder:FindFirstChild("Creatures")
	local template = creaturesFolder and creaturesFolder:FindFirstChild(creatureId)
	if template and template:IsA("Model") then
		return template
	end
	return nil
end

--- Fills `parent` with a small ViewportFrame portrait of the creature, or a
--- coloured letter tile when the model is not available on this client.
local function buildPortrait(parent: Instance, creatureId: string, rarity: string, size: UDim2): GuiObject
	local color = rarityColor(rarity)
	local template = findCreatureTemplate(creatureId)
	if template then
		local viewport = Instance.new("ViewportFrame")
		viewport.Name = "Portrait"
		viewport.Size = size
		viewport.BackgroundColor3 = Theme.Background.Deep
		viewport.BorderSizePixel = 0
		viewport.Ambient = Color3.fromRGB(190, 200, 215)
		viewport.LightColor = Color3.fromRGB(255, 255, 255)
		Theme.ApplyCorner(viewport, UDim.new(0, 8))
		Theme.ApplyStroke(viewport, color, 1.5)

		local clone = template:Clone()
		clone.Parent = viewport
		local cframe, extents = clone:GetBoundingBox()
		local radius = math.max(extents.X, extents.Y, extents.Z)
		local camera = Instance.new("Camera")
		camera.FieldOfView = 40
		camera.CFrame = CFrame.lookAt(cframe.Position + Vector3.new(0.6, 0.4, 1).Unit * radius * 1.9, cframe.Position)
		camera.Parent = viewport
		viewport.CurrentCamera = camera
		viewport.Parent = parent
		return viewport
	end

	local tile = Instance.new("TextLabel")
	tile.Name = "Portrait"
	tile.Size = size
	tile.BackgroundColor3 = Theme.Background.Deep
	tile.Font = Theme.Font.Header
	tile.TextScaled = true
	tile.TextColor3 = color
	tile.Text = string.upper(string.sub(creatureId, 1, 1))
	Theme.ApplyCorner(tile, UDim.new(0, 8))
	Theme.ApplyStroke(tile, color, 1.5)
	tile.Parent = parent
	return tile
end

local function makeLabel(parent: Instance, text: string, font: Enum.Font, color: Color3, minSize: number, maxSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = font
	label.TextColor3 = color
	label.TextScaled = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = text
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
	label.Parent = parent
	return label
end

-- // State -------------------------------------------------------------------------------

type CandidateInfo = {
	InstanceId: string,
	CreatureId: string,
	Rarity: string,
	Damage: number,
	MaxHP: number,
	Eligible: boolean,
	Reason: string?,
}

type GuardianCardInfo = {
	OwnerUserId: number,
	InstanceId: string,
	CreatureId: string,
	Rarity: string,
	HP: number,
	MaxHP: number,
	KnockedOut: boolean,
}

local loadout: { string } = {}
local slots = 1
local slotUnlockLevels: { number } = RaidConfig.GUARDIAN_SLOT_UNLOCK_LEVELS
local candidates: { CandidateInfo } = {}
local inRaid = false
local isHelper = false
local deployed = false
local warnedEmptyLoadout = false

-- // Raid HUD (guardian cards + action buttons) ---------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "GuardianHUD"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 14
Device.ApplySafeArea(screenGui)
screenGui.Parent = player:WaitForChild("PlayerGui")
local hudRoot, unbindHudScale = Device.CreateScaledRoot(screenGui)

local strip = Instance.new("Frame")
strip.Name = "GuardianStrip"
strip.BackgroundTransparency = 1
strip.AutomaticSize = Enum.AutomaticSize.Y
strip.Visible = false
strip.Parent = hudRoot
local stripLayout = Instance.new("UIListLayout")
stripLayout.Padding = UDim.new(0, 6)
stripLayout.SortOrder = Enum.SortOrder.LayoutOrder
stripLayout.Parent = strip

local function applyStripLayout()
	local mode = Layout.GetHudLayout().Mode
	if mode == "Portrait" then
		strip.AnchorPoint = Vector2.new(0.5, 0)
		strip.Position = UDim2.new(0.5, 0, 0, 340)
		strip.Size = UDim2.new(1, -16, 0, 0)
	elseif mode == "Landscape" then
		strip.AnchorPoint = Vector2.new(0, 0)
		strip.Position = UDim2.new(0, 8, 0, 198)
		strip.Size = UDim2.new(0, 168, 0, 0)
	else
		strip.AnchorPoint = Vector2.new(0, 0.5)
		strip.Position = UDim2.new(0, 16, 0.5, -60)
		strip.Size = UDim2.new(0, 176, 0, 0)
	end
end
applyStripLayout()
local stripLayoutConnection = Device.Changed:Connect(applyStripLayout)

local deployButton = Button.new({
	Parent = strip,
	Text = "Deploy Guardians",
	Variant = "Success",
	Size = UDim2.new(1, 0, 0, 44),
	LayoutOrder = 1,
})
deployButton.Instance.Visible = false

local leaveButton = Button.new({
	Parent = strip,
	Text = "Leave raid",
	Variant = "Ghost",
	Size = UDim2.new(1, 0, 0, 44),
	LayoutOrder = 2,
})
leaveButton.Instance.Visible = false

local cardsHolder = Instance.new("Frame")
cardsHolder.Name = "Cards"
cardsHolder.BackgroundTransparency = 1
cardsHolder.AutomaticSize = Enum.AutomaticSize.Y
cardsHolder.Size = UDim2.new(1, 0, 0, 0)
cardsHolder.LayoutOrder = 3
cardsHolder.Parent = strip
local cardsLayout = Instance.new("UIGridLayout")
cardsLayout.CellSize = UDim2.fromOffset(164, 44)
cardsLayout.CellPadding = UDim2.fromOffset(6, 6)
cardsLayout.SortOrder = Enum.SortOrder.LayoutOrder
cardsLayout.Parent = cardsHolder

type CardHandle = { Frame: Frame, Fill: Frame, HpLabel: TextLabel, KoLabel: TextLabel, Signature: string }
local cards: { [string]: CardHandle } = {}

local function clearCards()
	for _, card in cards do
		card.Frame:Destroy()
	end
	table.clear(cards)
end

local function refreshStripVisibility()
	deployButton.Instance.Visible = inRaid and not deployed
	leaveButton.Instance.Visible = inRaid and isHelper
	strip.Visible = inRaid and (next(cards) ~= nil or not deployed or isHelper)
end

local function applyGuardianStatus(list: { GuardianCardInfo })
	-- Own guardians first, then cluster mates', capped so the strip stays small.
	local ordered: { GuardianCardInfo } = {}
	for _, info in ipairs(list) do
		table.insert(ordered, info)
	end
	table.sort(ordered, function(a, b)
		local ownA = a.OwnerUserId == player.UserId
		local ownB = b.OwnerUserId == player.UserId
		if ownA ~= ownB then
			return ownA
		end
		return a.InstanceId < b.InstanceId
	end)

	deployed = false
	local keep: { [string]: boolean } = {}
	for index, info in ipairs(ordered) do
		if info.OwnerUserId == player.UserId then
			deployed = true
		end
		if index > MAX_CARDS then
			continue
		end
		keep[info.InstanceId] = true

		local card = cards[info.InstanceId]
		if not card then
			local frame = Instance.new("Frame")
			frame.Name = info.InstanceId
			frame.BackgroundColor3 = Theme.Background.Panel
			frame.BackgroundTransparency = 0.15
			frame.LayoutOrder = index
			Theme.ApplyCorner(frame, UDim.new(0, 10))
			Theme.ApplyStroke(frame, if info.OwnerUserId == player.UserId then Theme.Neon.Cyan else Theme.Neon.Violet, 1.5)

			local portrait = buildPortrait(frame, info.CreatureId, info.Rarity, UDim2.fromOffset(36, 36))
			portrait.Position = UDim2.fromOffset(4, 4)

			local name = makeLabel(frame, prettyName(info.CreatureId), Theme.Font.BodyBold, rarityColor(info.Rarity), 9, 13)
			name.Size = UDim2.new(1, -48, 0, 15)
			name.Position = UDim2.fromOffset(44, 3)

			local barBack = Instance.new("Frame")
			barBack.Size = UDim2.new(1, -52, 0, 8)
			barBack.Position = UDim2.fromOffset(44, 21)
			barBack.BackgroundColor3 = Theme.Background.Deep
			Theme.ApplyCorner(barBack, UDim.new(0, 4))
			barBack.Parent = frame
			local fill = Instance.new("Frame")
			fill.Size = UDim2.fromScale(1, 1)
			fill.BackgroundColor3 = Theme.Semantic.Success
			Theme.ApplyCorner(fill, UDim.new(0, 4))
			fill.Parent = barBack

			local hpLabel = makeLabel(frame, "", Theme.Font.Body, Theme.Text.Secondary, 8, 11)
			hpLabel.Size = UDim2.new(1, -48, 0, 11)
			hpLabel.Position = UDim2.fromOffset(44, 30)

			local koLabel = makeLabel(frame, "Knocked out", Theme.Font.BodyBold, Theme.Semantic.Danger, 9, 13)
			koLabel.TextXAlignment = Enum.TextXAlignment.Center
			koLabel.Size = UDim2.fromScale(1, 1)
			koLabel.BackgroundColor3 = Theme.Background.Deepest
			koLabel.BackgroundTransparency = 0.35
			koLabel.Visible = false
			koLabel.ZIndex = 5
			Theme.ApplyCorner(koLabel, UDim.new(0, 10))

			frame.Parent = cardsHolder
			card = { Frame = frame, Fill = fill, HpLabel = hpLabel, KoLabel = koLabel, Signature = "" }
			cards[info.InstanceId] = card
		end

		card.Frame.LayoutOrder = index
		card.Fill.Size = UDim2.fromScale(math.clamp(info.HP / math.max(1, info.MaxHP), 0, 1), 1)
		card.Fill.BackgroundColor3 = if info.HP / math.max(1, info.MaxHP) > 0.35 then Theme.Semantic.Success else Theme.Semantic.Danger
		card.HpLabel.Text = ("%d / %d"):format(info.HP, info.MaxHP)
		card.KoLabel.Visible = info.KnockedOut
	end

	for instanceId, card in cards do
		if not keep[instanceId] then
			card.Frame:Destroy()
			cards[instanceId] = nil
		end
	end
	refreshStripVisibility()
end

local function requestDeploy()
	RaidRemotes.RequestDeployGuardian:FireServer()
end

deployButton.Clicked:Connect(requestDeploy)
leaveButton.Clicked:Connect(function()
	RaidRemotes.RequestLeaveCoopRaid:FireServer()
end)

-- // Loadout panel ---------------------------------------------------------------------------

local panel = Panel.new({
	Title = "Guardians",
	Closable = true,
	CenteredSize = UDim2.fromOffset(460, 540),
})

local infoLabel = makeLabel(panel.Content, "", Theme.Font.Body, Theme.Text.Secondary, 12, 16)
infoLabel.Size = UDim2.new(1, 0, 0, 40)
infoLabel.TextWrapped = true
infoLabel.TextYAlignment = Enum.TextYAlignment.Top

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "LoadoutScroll"
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.Position = UDim2.fromOffset(0, 46)
scroll.Size = UDim2.new(1, 0, 1, -46)
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ScrollBarThickness = 6
scroll.ScrollBarImageColor3 = Theme.Neon.Cyan
scroll.Parent = panel.Content
local scrollLayout = Instance.new("UIListLayout")
scrollLayout.Padding = UDim.new(0, 8)
scrollLayout.SortOrder = Enum.SortOrder.LayoutOrder
scrollLayout.Parent = scroll

local rowObjects: { Instance } = {}
local rowButtons: { any } = {}

local REASON_TEXT: { [string]: string } = {
	RateLimited = "Slow down a little.",
	InvalidRequest = "That did not work.",
	DataNotLoaded = "Your data is still loading.",
	PersistenceFailed = "Could not save the team.",
	NoActiveRaid = "There is no raid right now.",
	AlreadyDeployed = "Your guardians are already out.",
	NoGuardiansSelected = "Pick guardians first (More > Guardians).",
	NotInCluster = "Only your Reef Cluster mates can join.",
	AlreadyInRaid = "You are already in a raid.",
	OwnRaid = "That is your own raid.",
	RaidFull = "That raid already has enough helpers.",
	CannotTeleport = "Could not get you to the reef. Try again.",
}

local function addRow(height: number, order: number): Frame
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, height)
	row.BackgroundColor3 = Theme.Background.PanelLight
	row.LayoutOrder = order
	Theme.ApplyCorner(row, UDim.new(0, 8))
	row.Parent = scroll
	table.insert(rowObjects, row)
	return row
end

local function addHeader(text: string, order: number)
	local label = makeLabel(scroll, text, Theme.Font.Header, Theme.Neon.Cyan, 14, 18)
	label.Size = UDim2.new(1, 0, 0, 24)
	label.LayoutOrder = order
	table.insert(rowObjects, label)
end

local function sendLoadout(newList: { string })
	RaidRemotes.RequestSetGuardianLoadout:FireServer(newList)
end

local function findCandidate(instanceId: string): CandidateInfo?
	for _, candidate in ipairs(candidates) do
		if candidate.InstanceId == instanceId then
			return candidate
		end
	end
	return nil
end

local function rebuildPanel()
	for _, handle in rowButtons do
		handle:Destroy()
	end
	table.clear(rowButtons)
	for _, object in rowObjects do
		object:Destroy()
	end
	table.clear(rowObjects)

	local nextUnlock: number? = slotUnlockLevels[slots + 1]
	infoLabel.Text = ("Guardians fight next to your towers during a Trench Raid. Slots: %d. %s%s"):format(
		slots,
		if nextUnlock then ("Next slot at level %d. "):format(nextUnlock) else "",
		if inRaid and deployed then "Changes apply to the next raid." else "A knocked-out guardian is back next raid."
	)

	local order = 1
	addHeader("Your team", order)
	order += 1
	for slotIndex = 1, #slotUnlockLevels do
		local row = addRow(60, order)
		order += 1
		if slotIndex > slots then
			local locked = makeLabel(row, ("Slot %d unlocks at level %d"):format(slotIndex, slotUnlockLevels[slotIndex]), Theme.Font.Body, Theme.Text.Muted, 12, 16)
			locked.Size = UDim2.new(1, -16, 1, 0)
			locked.Position = UDim2.fromOffset(8, 0)
			continue
		end
		local instanceId = loadout[slotIndex]
		local info = if instanceId then findCandidate(instanceId) else nil
		if instanceId and info then
			local portrait = buildPortrait(row, info.CreatureId, info.Rarity, UDim2.fromOffset(44, 44))
			portrait.Position = UDim2.fromOffset(8, 8)
			local name = makeLabel(row, ("%s (%s)"):format(prettyName(info.CreatureId), info.Rarity), Theme.Font.BodyBold, rarityColor(info.Rarity), 12, 16)
			name.Size = UDim2.new(1, -170, 0, 22)
			name.Position = UDim2.fromOffset(60, 8)
			local stats = makeLabel(row, ("DPS %.1f  -  HP %d"):format(info.Damage, info.MaxHP), Theme.Font.Body, Theme.Text.Secondary, 11, 14)
			stats.Size = UDim2.new(1, -170, 0, 18)
			stats.Position = UDim2.fromOffset(60, 32)
			local removeButton = Button.new({ Parent = row, Text = "Remove", Variant = "Ghost", Size = UDim2.fromOffset(92, 44) })
			removeButton.Instance.AnchorPoint = Vector2.new(1, 0.5)
			removeButton.Instance.Position = UDim2.new(1, -8, 0.5, 0)
			removeButton.Clicked:Connect(function()
				local newList = {}
				for _, id in ipairs(loadout) do
					if id ~= instanceId then
						table.insert(newList, id)
					end
				end
				sendLoadout(newList)
			end)
			table.insert(rowButtons, removeButton)
		else
			local empty = makeLabel(row, ("Slot %d: empty - pick a creature below"):format(slotIndex), Theme.Font.Body, Theme.Text.Muted, 12, 16)
			empty.Size = UDim2.new(1, -16, 1, 0)
			empty.Position = UDim2.fromOffset(8, 0)
		end
	end

	addHeader("Your creatures", order)
	order += 1
	if #candidates == 0 then
		local row = addRow(50, order)
		order += 1
		local empty = makeLabel(row, "No creatures yet - open a Mystery Egg or breed one!", Theme.Font.Body, Theme.Text.Muted, 12, 16)
		empty.Size = UDim2.new(1, -16, 1, 0)
		empty.Position = UDim2.fromOffset(8, 0)
	end
	for _, candidate in ipairs(candidates) do
		local row = addRow(64, order)
		order += 1
		local portrait = buildPortrait(row, candidate.CreatureId, candidate.Rarity, UDim2.fromOffset(48, 48))
		portrait.Position = UDim2.fromOffset(8, 8)
		local name = makeLabel(row, ("%s (%s)"):format(prettyName(candidate.CreatureId), candidate.Rarity), Theme.Font.BodyBold, rarityColor(candidate.Rarity), 12, 16)
		name.Size = UDim2.new(1, -170, 0, 22)
		name.Position = UDim2.fromOffset(64, 10)
		local detail = if candidate.Eligible
			then ("DPS %.1f  -  HP %d"):format(candidate.Damage, candidate.MaxHP)
			else (candidate.Reason or "Not available")
		local stats = makeLabel(row, detail, Theme.Font.Body, if candidate.Eligible then Theme.Text.Secondary else Theme.Semantic.Warning, 11, 14)
		stats.Size = UDim2.new(1, -170, 0, 18)
		stats.Position = UDim2.fromOffset(64, 34)

		local selected = table.find(loadout, candidate.InstanceId) ~= nil
		local addButton = Button.new({
			Parent = row,
			Text = if selected then "In team" else "Add",
			Variant = "Primary",
			Size = UDim2.fromOffset(92, 44),
			Disabled = selected or not candidate.Eligible,
		})
		addButton.Instance.AnchorPoint = Vector2.new(1, 0.5)
		addButton.Instance.Position = UDim2.new(1, -8, 0.5, 0)
		addButton.Clicked:Connect(function()
			if #loadout >= slots then
				Toast.Show({ Text = "All slots are full - remove a guardian first.", Type = "Warning" })
				return
			end
			local newList = table.clone(loadout)
			table.insert(newList, candidate.InstanceId)
			sendLoadout(newList)
		end)
		table.insert(rowButtons, addButton)
	end
end

local function applyLoadoutInfo(info: { [string]: any })
	if type(info.Slots) == "number" then
		slots = info.Slots
	end
	if type(info.SlotUnlockLevels) == "table" then
		slotUnlockLevels = info.SlotUnlockLevels
	end
	if type(info.Loadout) == "table" then
		loadout = info.Loadout
	end
	if type(info.Candidates) == "table" then
		candidates = info.Candidates
	end
	if type(info.Deployed) == "boolean" then
		deployed = info.Deployed
	end
end

local function fetchLoadoutInfo(): boolean
	local ok, info = pcall(function()
		return RaidRemotes.GetGuardianLoadout:InvokeServer()
	end)
	if not ok or type(info) ~= "table" then
		return false
	end
	applyLoadoutInfo(info)
	return true
end

local bridgeConnection = openGuardiansEvent.Event:Connect(function()
	if not fetchLoadoutInfo() then
		Toast.Show({ Text = "Could not load your guardians. Try again.", Type = "Error" })
		return
	end
	rebuildPanel()
	panel:Open()
end)

RaidRemotes.GuardianLoadoutChanged.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then
		return
	end
	if type(result.Slots) == "number" then
		slots = result.Slots
	end
	if type(result.Loadout) == "table" then
		loadout = result.Loadout
	end
	if result.Success ~= true then
		Toast.Show({ Text = REASON_TEXT[tostring(result.Reason)] or "Could not change the team.", Type = "Error" })
	end
	rebuildPanel()
end)

-- // Raid / co-op events ----------------------------------------------------------------------

RaidRemotes.RaidStarted.OnClientEvent:Connect(function()
	inRaid = true
	isHelper = false
	deployed = false
	refreshStripVisibility()
	-- The server deploys the saved loadout; an empty one is answered with NoGuardiansSelected.
	requestDeploy()
end)

RaidRemotes.RaidResult.OnClientEvent:Connect(function()
	inRaid = false
	isHelper = false
	deployed = false
	clearCards()
	refreshStripVisibility()
end)

RaidRemotes.GuardianStatus.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.Guardians) ~= "table" then
		return
	end
	applyGuardianStatus(payload.Guardians)
end)

RaidRemotes.GuardianDeployResult.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then
		return
	end
	if result.Success == true then
		deployed = true
		refreshStripVisibility()
		Toast.Show({ Text = ("%d guardian(s) deployed!"):format(result.Count or 0), Type = "Success" })
	elseif result.Reason == "NoGuardiansSelected" then
		if not warnedEmptyLoadout then
			warnedEmptyLoadout = true
			Toast.Show({ Text = "No guardians picked. Open More > Guardians to choose some.", Type = "Info", Duration = 5 })
		end
	elseif result.Reason ~= "AlreadyDeployed" and result.Reason ~= "RateLimited" then
		Toast.Show({ Text = REASON_TEXT[tostring(result.Reason)] or "Could not deploy guardians.", Type = "Error" })
	end
end)

RaidRemotes.CoopRaidInvite.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.OwnerUserId) ~= "number" then
		return
	end
	if inRaid then
		return
	end
	local ownerUserId: number = payload.OwnerUserId
	local expiresAt: number = if type(payload.ExpiresAt) == "number" then payload.ExpiresAt else os.time() + 60
	ConfirmDialog.Show({
		Title = "Reef Cluster in danger!",
		Message = ("%s's reef is being raided. Join and defend with your guardians and Depth Charges?"):format(
			tostring(payload.OwnerName or "A cluster mate")
		),
		ConfirmText = "Join & Defend",
		CancelText = "Not now",
		OnConfirm = function()
			if os.time() > expiresAt then
				Toast.Show({ Text = "That raid is already over.", Type = "Info" })
				return
			end
			RaidRemotes.RequestJoinCoopRaid:FireServer(ownerUserId)
		end,
	})
end)

RaidRemotes.CoopRaidJoined.OnClientEvent:Connect(function(result)
	if type(result) ~= "table" then
		return
	end
	if result.Success == true then
		inRaid = true
		isHelper = true
		deployed = false
		refreshStripVisibility()
		Toast.Show({ Text = ("You are defending %s's reef!"):format(tostring(result.OwnerName or "your mate")), Type = "Success" })
		requestDeploy()
	else
		Toast.Show({ Text = REASON_TEXT[tostring(result.Reason)] or "Could not join the raid.", Type = "Error" })
	end
end)

RaidRemotes.CoopRaidLeft.OnClientEvent:Connect(function(payload)
	inRaid = false
	isHelper = false
	deployed = false
	clearCards()
	refreshStripVisibility()
	local reason = if type(payload) == "table" then payload.Reason else nil
	if reason == "OwnerLeft" then
		Toast.Show({ Text = "The raid ended because the reef owner left.", Type = "Info" })
	end
end)

-- // Guardian attack effect (short coloured beam) ----------------------------------------------

RaidRemotes.GuardianAttack.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or typeof(payload.From) ~= "Vector3" or typeof(payload.To) ~= "Vector3" then
		return
	end
	if Settings.ShouldSkipFX() then
		return
	end
	local color = rarityColor(tostring(payload.Rarity))

	local originPart = Instance.new("Part")
	originPart.Name = "GuardianBeamOrigin"
	originPart.Anchored = true
	originPart.CanCollide = false
	originPart.CanQuery = false
	originPart.CanTouch = false
	originPart.Transparency = 1
	originPart.Size = Vector3.new(0.2, 0.2, 0.2)
	originPart.CFrame = CFrame.new(payload.From)
	originPart.Parent = Workspace

	local targetPart = originPart:Clone()
	targetPart.Name = "GuardianBeamTarget"
	targetPart.CFrame = CFrame.new(payload.To)
	targetPart.Parent = Workspace

	local a0 = Instance.new("Attachment")
	a0.Parent = originPart
	local a1 = Instance.new("Attachment")
	a1.Parent = targetPart

	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.5
	beam.Width1 = 0.15
	beam.Color = ColorSequence.new(color)
	beam.LightEmission = 0.6
	beam.Transparency = NumberSequence.new(0.05, 0.9)
	beam.FaceCamera = true
	beam.Parent = originPart

	local burst = Instance.new("ParticleEmitter")
	burst.Color = ColorSequence.new(color)
	burst.Lifetime = NumberRange.new(0.25, 0.4)
	burst.Speed = NumberRange.new(6, 10)
	burst.SpreadAngle = Vector2.new(180, 180)
	burst.Size = NumberSequence.new(0.5, 0)
	burst.LightEmission = 0.7
	burst.Rate = 0
	burst.Parent = a1
	burst:Emit(8)

	Debris:AddItem(originPart, 0.2)
	Debris:AddItem(targetPart, 0.5)
end)

-- // Initial sync + cleanup -----------------------------------------------------------------------

task.spawn(function()
	local ok, status = pcall(function()
		return RaidRemotes.GetRaidStatus:InvokeServer()
	end)
	if ok and type(status) == "table" and status.InRaid == true then
		inRaid = true
		isHelper = status.CoopHelper == true
		refreshStripVisibility()
	end
	if fetchLoadoutInfo() then
		refreshStripVisibility()
	end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	stripLayoutConnection:Disconnect()
	bridgeConnection:Disconnect()
	unbindHudScale()
	panel:Destroy()
	screenGui:Destroy()
end)
