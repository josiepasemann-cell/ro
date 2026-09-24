--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Script: AchievementUIController (LocalScript)
	Responsibility:
		UI for the Achievements system (AchievementService/AchievementRemotes,
		see their header comments): a tabbed panel (one tab per
		AchievementConfig category, plus a "Titles" tab), progress bars,
		claim buttons with reward FX, locked/secret card display, a toast +
		small screen-FX the instant an achievement unlocks, and a title
		picker that equips/unequips a billboard title shown above the
		player's head (server-side, see AchievementService.RefreshTitleBillboard).

		Data source exclusively AchievementRemotes (see its header comment) -
		never its own progress/claim/equip computation, every click is only
		a request, the server re-validates everything from scratch.

		HARD UIKit RULE (docs/ui-kit.md): every button exclusively via
		UIKit.Button.new(...).

		Bridge communication (ReplicatedStorage.AbyssaraUIBridge, identical
		pattern to MainMenuController/QuestUIController):
			- "OpenAchievements" (incoming) - MainMenuController's menu entry
			  opens this panel.
			- "AchievementBadgeCountChanged" (outgoing, payload: count:
			  number) - MainMenuController shows a badge on the menu entry
			  when at least one unlocked achievement's reward is unclaimed.

	Rojo mount point:
		src/client/AchievementUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.AchievementUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementRemotes = require(ReplicatedStorage:WaitForChild("AchievementRemotes"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("AchievementConfig"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Panel = UIKit.Panel
local Button = UIKit.Button
local Toast = UIKit.Toast
local ProgressBar = UIKit.ProgressBar
local ScreenFX = UIKit.ScreenFX
local Tabs = UIKit.Tabs

local localPlayer = Players.LocalPlayer

-- // Bridge (identical pattern to MainMenuController/QuestUIController) ------

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

local openAchievementsEvent = getOrCreateBridgeEvent("OpenAchievements")
local achievementBadgeCountEvent = getOrCreateBridgeEvent("AchievementBadgeCountChanged")

-- // Reason -> friendly text ---------------------------------------------------

local CLAIM_REASON_MESSAGES: { [string]: string } = {
	DataNotLoaded = "Your save data is still loading - please wait a moment.",
	UnknownAchievement = "This achievement no longer exists.",
	NotUnlocked = "This achievement isn't unlocked yet.",
	AlreadyClaimed = "You already claimed this reward.",
}

local EQUIP_REASON_MESSAGES: { [string]: string } = {
	DataNotLoaded = "Your save data is still loading - please wait a moment.",
	InvalidTitle = "That title isn't valid.",
	NotOwned = "You haven't unlocked that title yet.",
}

local function friendlyClaimReason(reason: string?): string
	if not reason then
		return "Something went wrong. Please try again."
	end
	return CLAIM_REASON_MESSAGES[reason] or ("Something went wrong (" .. reason .. ").")
end

local function friendlyEquipReason(reason: string?): string
	if not reason then
		return "Something went wrong. Please try again."
	end
	return EQUIP_REASON_MESSAGES[reason] or ("Something went wrong (" .. reason .. ").")
end

-- // Small label factory (not a button, plain labels are allowed) -----------

local function makeLabel(props: {
	Parent: Instance,
	Text: string,
	Size: UDim2,
	Position: UDim2?,
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
	label.Position = props.Position or UDim2.fromOffset(0, 0)
	label.Font = props.Font or Theme.Font.Body
	label.TextColor3 = props.Color or Theme.Text.Primary
	label.TextXAlignment = props.XAlign or Enum.TextXAlignment.Left
	label.TextScaled = true
	label.TextWrapped = props.Wrapped or false
	label.LayoutOrder = props.LayoutOrder or 0
	label.Text = props.Text
	label.Parent = props.Parent
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = props.MinSize or 12
	constraint.MaxTextSize = props.MaxSize or 20
	constraint.Parent = label
	return label
end

-- // Types --------------------------------------------------------------------

type AchievementRow = {
	Id: string,
	Category: string,
	Icon: string,
	Name: string,
	Description: string,
	Secret: boolean,
	Unlocked: boolean,
	Progress: number,
	Target: number,
	Claimed: boolean,
	RewardTideCoins: number,
	RewardAbyssalShards: number,
	RewardTitle: string?,
}

type AchievementCardHandle = {
	NameLabel: TextLabel,
	DescriptionLabel: TextLabel,
	ProgressBar: any,
	ProgressLabel: TextLabel,
	ClaimButton: any,
	Destroy: (self: AchievementCardHandle) -> (),
}

-- // State ----------------------------------------------------------------------

local achievementRows: { [string]: AchievementRow } = {}
local achievementOrder: { string } = {}
local equippedTitle: string? = nil
local unlockedTitles: { string } = {}

local mainPanel: any = nil
local tabsHandle: any = nil
local cardHostByCategory: { [string]: Frame } = {}
local cardHandles: { [string]: AchievementCardHandle } = {}
local titleTabHost: Frame? = nil
local titleButtonHandles: { any } = {}

-- // Badge count (unlocked but unclaimed) --------------------------------------

local function computeClaimableBadgeCount(): number
	local count = 0
	for _, row in achievementRows do
		if row.Unlocked and not row.Claimed then
			count += 1
		end
	end
	return count
end

local function refreshBadge()
	achievementBadgeCountEvent:Fire(computeClaimableBadgeCount())
end

-- // Achievement cards ---------------------------------------------------------

local function rewardText(row: AchievementRow): string
	local text = "🪙" .. row.RewardTideCoins
	if row.RewardAbyssalShards > 0 then
		text ..= "  💎" .. row.RewardAbyssalShards
	end
	if row.RewardTitle then
		text ..= "  🏷️ " .. row.RewardTitle
	end
	return text
end

local function buildAchievementCard(parent: Instance, layoutOrder: number, row: AchievementRow): AchievementCardHandle
	local card = Instance.new("Frame")
	card.Name = "AchievementCard_" .. row.Id
	card.BackgroundColor3 = Theme.Background.PanelLight
	card.Size = UDim2.new(1, 0, 0, 136)
	card.LayoutOrder = layoutOrder
	card.Parent = parent
	Theme.ApplyCorner(card, UDim.new(0, 14))
	local accent = if row.Secret then Theme.Neon.Violet elseif row.Unlocked then Theme.Neon.ToxicGreen else Theme.Neon.Cyan
	local stroke = Theme.ApplyStroke(card, accent, 2)
	stroke.Transparency = 0.4
	Theme.ApplyGradient(card, { Theme.Background.PanelLight, Theme.Background.Panel }, 100)

	local glyphLabel = makeLabel({
		Parent = card,
		Text = row.Unlocked and row.Icon or (row.Secret and "❓" or row.Icon),
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(10, 10),
		Font = Theme.Font.Header,
		MinSize = 18,
		MaxSize = 28,
		XAlign = Enum.TextXAlignment.Center,
	})
	glyphLabel.Name = "Glyph"

	local nameLabel = makeLabel({
		Parent = card,
		Text = row.Name,
		Size = UDim2.new(1, -60, 0, 22),
		Position = UDim2.fromOffset(54, 6),
		Font = Theme.Font.BodyBold,
		Color = if row.Unlocked then Theme.Neon.ToxicGreen else Theme.Text.Primary,
		MinSize = 12,
		MaxSize = 17,
		Wrapped = true,
	})

	local descriptionLabel = makeLabel({
		Parent = card,
		Text = row.Description,
		Size = UDim2.new(1, -60, 0, 34),
		Position = UDim2.fromOffset(54, 28),
		Color = Theme.Text.Secondary,
		MinSize = 10,
		MaxSize = 14,
		Wrapped = true,
	})

	local progressHost = Instance.new("Frame")
	progressHost.BackgroundTransparency = 1
	progressHost.Size = UDim2.new(1, -20, 0, 16)
	progressHost.Position = UDim2.fromOffset(10, 66)
	progressHost.Visible = not (row.Secret and not row.Unlocked)
	progressHost.Parent = card
	local progressBar = ProgressBar.new({
		Parent = progressHost,
		Size = UDim2.new(1, 0, 1, 0),
		Value = row.Target > 0 and (row.Progress / row.Target) or 0,
		Colors = { Theme.Neon.Cyan, Theme.Neon.ToxicGreen },
	})

	local progressLabel = makeLabel({
		Parent = card,
		Text = if row.Secret and not row.Unlocked then "" else ("%d / %d"):format(row.Progress, row.Target),
		Size = UDim2.new(1, -20, 0, 14),
		Position = UDim2.fromOffset(10, 84),
		Color = Theme.Text.Secondary,
		MinSize = 9,
		MaxSize = 12,
		XAlign = Enum.TextXAlignment.Right,
	})

	makeLabel({
		Parent = card,
		Text = if row.Secret and not row.Unlocked then "" else rewardText(row),
		Size = UDim2.new(0.6, -10, 0, 22),
		Position = UDim2.fromOffset(10, 100),
		Color = Theme.Neon.Yellow,
		MinSize = 9,
		MaxSize = 13,
		Wrapped = true,
	})

	local claimButton = Button.new({
		Parent = card,
		Text = "Locked",
		Variant = "Success",
		Important = true,
		Disabled = true,
		Size = UDim2.new(0.4, -10, 0, 30),
		LayoutOrder = 1,
	})
	claimButton.Instance.AnchorPoint = Vector2.new(1, 0)
	claimButton.Instance.Position = UDim2.new(1, -10, 0, 100)
	claimButton.Clicked:Connect(function()
		AchievementRemotes.RequestClaimReward:FireServer(row.Id)
		claimButton:SetDisabled(true)
		claimButton:SetText("Claiming...")
	end)

	local handle: AchievementCardHandle = {
		NameLabel = nameLabel,
		DescriptionLabel = descriptionLabel,
		ProgressBar = progressBar,
		ProgressLabel = progressLabel,
		ClaimButton = claimButton,
		Destroy = function(_self)
			claimButton:Destroy()
			progressBar:Destroy()
			card:Destroy()
		end,
	}
	return handle
end

local function updateCardVisual(id: string)
	local row = achievementRows[id]
	local card = cardHandles[id]
	if not row or not card then
		return
	end

	local hideContent = row.Secret and not row.Unlocked
	card.NameLabel.Text = row.Name
	card.NameLabel.TextColor3 = if row.Unlocked then Theme.Neon.ToxicGreen else Theme.Text.Primary
	card.DescriptionLabel.Text = row.Description

	if not hideContent then
		local ratio = row.Target > 0 and (row.Progress / row.Target) or 0
		card.ProgressBar:SetProgress(ratio)
		card.ProgressLabel.Text = ("%d / %d"):format(math.min(row.Progress, row.Target), row.Target)
	end

	if row.Claimed then
		card.ClaimButton:SetDisabled(true)
		card.ClaimButton:SetText("Claimed ✓")
	elseif row.Unlocked then
		card.ClaimButton:SetDisabled(false)
		card.ClaimButton:SetText("Claim!")
	else
		card.ClaimButton:SetDisabled(true)
		card.ClaimButton:SetText(if row.Secret then "???" else "Locked")
	end
end

local function rebuildCategoryCards(category: string)
	local host = cardHostByCategory[category]
	if not host then
		return
	end
	for _, child in ipairs(host:GetChildren()) do
		if child:IsA("Frame") and child.Name:match("^AchievementCard_") then
			child:Destroy()
		end
	end

	local order = 0
	for _, id in ipairs(achievementOrder) do
		local row = achievementRows[id]
		if row and row.Category == category then
			order += 1
			cardHandles[id] = buildAchievementCard(host, order, row)
			updateCardVisual(id)
		end
	end
end

local function rebuildAllCards()
	for _, handle in cardHandles do
		handle:Destroy()
	end
	table.clear(cardHandles)
	for _, category in ipairs(AchievementConfig.CATEGORY_ORDER) do
		rebuildCategoryCards(category)
	end
end

-- // Titles tab -----------------------------------------------------------------

local function requestEquipTitle(title: string?)
	AchievementRemotes.RequestEquipTitle:FireServer(title)
end

local function rebuildTitlesTab()
	local host = titleTabHost
	if not host then
		return
	end
	for _, handle in titleButtonHandles do
		handle:Destroy()
	end
	table.clear(titleButtonHandles)
	for _, child in ipairs(host:GetChildren()) do
		if child:IsA("Frame") and child.Name:match("^TitleRow_") then
			child:Destroy()
		end
	end

	local noneRow = Instance.new("Frame")
	noneRow.Name = "TitleRow_None"
	noneRow.BackgroundTransparency = 1
	noneRow.Size = UDim2.new(1, 0, 0, 40)
	noneRow.LayoutOrder = 0
	noneRow.Parent = host
	local noneButton = Button.new({
		Parent = noneRow,
		Text = if equippedTitle == nil then "No Title (equipped)" else "No Title",
		Variant = if equippedTitle == nil then "Success" else "Secondary",
		Size = UDim2.new(1, 0, 0, 40),
	})
	noneButton.Clicked:Connect(function()
		requestEquipTitle(nil)
	end)
	table.insert(titleButtonHandles, noneButton)

	if #unlockedTitles == 0 then
		makeLabel({
			Parent = host,
			Text = "No titles unlocked yet - earn achievements or complete zone/event rewards to unlock titles.",
			Size = UDim2.new(1, 0, 0, 40),
			Position = UDim2.fromOffset(0, 46),
			Color = Theme.Text.Muted,
			MinSize = 10,
			MaxSize = 14,
			Wrapped = true,
		})
		return
	end

	for index, title in ipairs(unlockedTitles) do
		local row = Instance.new("Frame")
		row.Name = "TitleRow_" .. index
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 40)
		row.LayoutOrder = index
		row.Parent = host

		local isEquipped = equippedTitle == title
		local button = Button.new({
			Parent = row,
			Text = if isEquipped then (title .. " (equipped)") else title,
			Variant = if isEquipped then "Success" else "Secondary",
			Size = UDim2.new(1, 0, 0, 40),
		})
		button.Clicked:Connect(function()
			requestEquipTitle(title)
		end)
		table.insert(titleButtonHandles, button)
	end
end

-- // Main panel -----------------------------------------------------------------

local function buildMainPanel()
	if mainPanel then
		return
	end

	mainPanel = Panel.new({
		Title = "Achievements",
		Closable = true,
		CenteredSize = UDim2.fromOffset(620, 680),
	})

	local tabDefs = {}
	for _, category in ipairs(AchievementConfig.CATEGORY_ORDER) do
		table.insert(tabDefs, { Id = category, Label = AchievementConfig.CATEGORY_LABELS[category] })
	end
	table.insert(tabDefs, { Id = "Titles", Label = "Titles" })

	tabsHandle = Tabs.new({
		Parent = mainPanel.Content,
		Tabs = tabDefs,
		DefaultTabId = AchievementConfig.CATEGORY_ORDER[1],
	})

	for _, category in ipairs(AchievementConfig.CATEGORY_ORDER) do
		local content = tabsHandle:GetContentFrame(category)
		cardHostByCategory[category] = content
	end

	local titlesContent = tabsHandle:GetContentFrame("Titles")
	titleTabHost = titlesContent

	rebuildAllCards()
	rebuildTitlesTab()
end

local function openMainPanel()
	buildMainPanel()
	mainPanel:Open()
end

-- // Remote wiring --------------------------------------------------------------

AchievementRemotes.AchievementProgressUpdated.OnClientEvent:Connect(function(payload: { Id: string, Progress: number, Target: number })
	if type(payload) ~= "table" or type(payload.Id) ~= "string" then
		return
	end
	local row = achievementRows[payload.Id]
	if not row then
		return
	end
	row.Progress = payload.Progress
	row.Target = payload.Target
	updateCardVisual(payload.Id)
end)

AchievementRemotes.AchievementUnlocked.OnClientEvent:Connect(function(payload: {
	Id: string,
	Name: string,
	Icon: string,
	Category: string,
	RewardTideCoins: number,
	RewardAbyssalShards: number,
	RewardTitle: string?,
})
	if type(payload) ~= "table" or type(payload.Id) ~= "string" then
		return
	end
	local row = achievementRows[payload.Id]
	if row then
		row.Unlocked = true
		row.Name = payload.Name
		updateCardVisual(payload.Id)
	end

	Toast.Show({
		Text = ("%s Achievement unlocked: %s!"):format(payload.Icon or "🏅", payload.Name),
		Type = "Success",
		Duration = 4,
	})
	ScreenFX.Flash({ Color = Theme.Neon.Yellow, Duration = 0.5 })
	refreshBadge()
end)

AchievementRemotes.ClaimRewardResult.OnClientEvent:Connect(function(payload: {
	Success: boolean,
	Reason: string?,
	Id: string?,
	RewardTideCoins: number?,
	RewardAbyssalShards: number?,
	RewardTitle: string?,
	NewTideCoinBalance: number?,
})
	if payload.Success and payload.Id then
		local row = achievementRows[payload.Id]
		if row then
			row.Claimed = true
			updateCardVisual(payload.Id)
		end
		if payload.RewardTitle then
			table.insert(unlockedTitles, payload.RewardTitle)
			rebuildTitlesTab()
		end
		Toast.Show({
			Text = ("Reward claimed: 🪙%d 💎%d"):format(payload.RewardTideCoins or 0, payload.RewardAbyssalShards or 0),
			Type = "Success",
			Duration = 3.5,
		})
		ScreenFX.BigMoment(Theme.Neon.ToxicGreen)
	else
		if payload.Id then
			updateCardVisual(payload.Id)
		end
		Toast.Show({ Text = friendlyClaimReason(payload.Reason), Type = "Warning", Duration = 3.5 })
	end
	refreshBadge()
end)

AchievementRemotes.EquipTitleResult.OnClientEvent:Connect(function(payload: { Success: boolean, Reason: string?, Title: string? })
	if payload.Success then
		equippedTitle = payload.Title
		rebuildTitlesTab()
		Toast.Show({
			Text = if payload.Title then ("Title equipped: " .. payload.Title) else "Title removed.",
			Type = "Success",
			Duration = 2.5,
		})
	else
		Toast.Show({ Text = friendlyEquipReason(payload.Reason), Type = "Warning", Duration = 3.5 })
	end
end)

local bridgeConnection = openAchievementsEvent.Event:Connect(openMainPanel)

-- // Initial sync ---------------------------------------------------------------

task.spawn(function()
	local ok, result = pcall(function()
		return AchievementRemotes.GetState:InvokeServer()
	end)
	if ok and type(result) == "table" and type(result.Achievements) == "table" then
		table.clear(achievementRows)
		table.clear(achievementOrder)
		for _, row in ipairs(result.Achievements) do
			achievementRows[row.Id] = row
			table.insert(achievementOrder, row.Id)
		end
		equippedTitle = result.EquippedTitle
		unlockedTitles = result.UnlockedTitles or {}
		if mainPanel then
			rebuildAllCards()
			rebuildTitlesTab()
		end
	else
		warn("[AchievementUIController] Could not load achievement state:", result)
	end
	refreshBadge()
end)

-- // Cleanup ---------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	bridgeConnection:Disconnect()
	for _, handle in cardHandles do
		handle:Destroy()
	end
	for _, handle in titleButtonHandles do
		handle:Destroy()
	end
	if tabsHandle then
		tabsHandle:Destroy()
	end
	if mainPanel then
		mainPanel:Destroy()
	end
end)
