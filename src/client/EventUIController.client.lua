--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: EventUIController (LocalScript)
	Zuständigkeit:
		UI für das rotierende Live-Event-System (docs/content-update-1.md,
		Abschnitt 1 + 7b):
			1. Ein permanent sichtbares Banner (oben mittig) mit Event-Name,
			   Event-Farbe und einem live nachziehenden Countdown bis zum
			   nächsten 12h-Slot-Wechsel.
			2. Ein Event-Panel (über den "Event"-Menüeintrag in
			   MainMenuController erreichbar, Bridge "OpenEvent") mit drei
			   Reitern: Shop (Event-Währung -> Eier/Kosmetik/Dubletten-
			   Rückkauf), Quest-Linie (3 Schritte + Abholen) und Info
			   (Modifikator-Übersicht, rein informativ).
			3. Ein "großer Moment" (ScreenFX.BigMoment + Toast) bei JEDEM
			   echten Slot-Wechsel (LiveEventRemotes.EventChanged) - NICHT
			   beim allerersten Laden (das würde wie ein Fehlalarm wirken,
			   siehe initialer Sync unten).

		Datenquelle ausschließlich `LiveEventRemotes` - nie eigene Kauf-/
		Fortschritts-Berechnung, jeder Klick ist nur eine Anfrage, der
		Server validiert komplett neu.

		HARTE UIKit-REGEL (docs/ui-kit.md): jeder Button ausschließlich über
		UIKit.Button.new(...).

	Rojo-Einhängepunkt:
		src/client/EventUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.EventUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LiveEventRemotes = require(ReplicatedStorage:WaitForChild("LiveEventRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Panel = UIKit.Panel
local Tabs = UIKit.Tabs
local Button = UIKit.Button
local Toast = UIKit.Toast
local ProgressBar = UIKit.ProgressBar
local ScreenFX = UIKit.ScreenFX

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- // Bridge (identisches Muster wie QuestUIController/MainMenuController) -----

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

local openEventEvent = getOrCreateBridgeEvent("OpenEvent")

-- // Anzeige-Metadaten ----------------------------------------------------------

local SHOP_ITEM_GLYPH: { [string]: string } = {
	CreatureEgg = "🥚",
	Cosmetic = "✨",
	Currency = "🔄",
}

local SHOP_REASON_MESSAGES: { [string]: string } = {
	DataNotLoaded = "Your save data is still loading - please wait a moment.",
	NoActiveEvent = "No event is active right now.",
	UnknownItem = "This item is no longer available.",
	InsufficientFunds = "Not enough event currency.",
	EggRollFailed = "Egg could not be opened - please try again.",
	PersistenceFailed = "Save failed - please try again.",
}

local QUEST_REASON_MESSAGES: { [string]: string } = {
	DataNotLoaded = "Your save data is still loading - please wait a moment.",
	NoActiveEvent = "No event is active right now.",
	AlreadyClaimed = "Reward already claimed.",
	NotCompleted = "Not all steps are complete yet.",
}

local CURRENCY_REASON_TOAST: { [string]: string } = {
	VentPulse = "🔥 Vent pulse! Bonus currency earned.",
	GhostShipFound = "👻 The Ghost Ship has been sighted!",
	SunkenChestOpened = "🏴‍☠️ Sunken Chest opened!",
	FrozenSporeThawed = "❄️ Frozen Spore thawed!",
}

local function friendlyReason(map: { [string]: string }, reason: string?): string
	if not reason then
		return "Action failed. Please try again."
	end
	return map[reason] or ("Aktion fehlgeschlagen (" .. reason .. ").")
end

-- // Countdown --------------------------------------------------------------

local function formatCountdown(totalSeconds: number): string
	local clamped = math.max(0, math.floor(totalSeconds))
	local hours = math.floor(clamped / 3600)
	local minutes = math.floor((clamped % 3600) / 60)
	local seconds = clamped % 60
	return string.format("%02d:%02d:%02d", hours, minutes, seconds)
end

-- // Kleine Label-Fabrik (kein Button, reine Labels sind erlaubt) --------------

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

-- // Typen -----------------------------------------------------------------------

type ShopItemRow = { Id: string, DisplayName: string, Cost: number, Type: string, Owned: boolean? }
type QuestStepRow = { Id: string, Description: string, Target: number, Progress: number }
type QuestLineRow = {
	Title: string,
	Steps: { QuestStepRow },
	Claimed: boolean,
	RewardTideCoins: number,
	RewardTitle: string,
}
type EventStateRow = {
	EventId: string,
	DisplayName: string,
	ColorPrimary: Color3,
	ColorSecondary: Color3,
	SlotStart: number,
	SlotEnd: number,
	Now: number,
	CurrencyId: string,
	CurrencyDisplayName: string,
	CurrencyGlyph: string,
	CurrencyBalance: number,
	ShopItems: { ShopItemRow },
	QuestLine: QuestLineRow,
}

-- // State ------------------------------------------------------------------------

local currentState: EventStateRow? = nil
local hasReceivedFirstState = false

local mainPanel: any = nil
local mainTabs: any = nil
local shopHost: Frame? = nil
local questHost: Frame? = nil
local infoHost: Frame? = nil
local currencyLabel: TextLabel? = nil

local shopCardHandles: { [string]: { Destroy: (self: any) -> () } } = {}
local questStepHandles: { any } = {}
local questClaimButton: any = nil
local questRewardLabel: TextLabel? = nil

-- // Banner (immer sichtbar) -----------------------------------------------------

local bannerGui = Instance.new("ScreenGui")
bannerGui.Name = "EventBannerGui"
bannerGui.ResetOnSpawn = false
bannerGui.IgnoreGuiInset = false
bannerGui.DisplayOrder = 5
bannerGui.Parent = playerGui
Device.ApplySafeArea(bannerGui)

local bannerFrame = Instance.new("Frame")
bannerFrame.Name = "EventBanner"
bannerFrame.AnchorPoint = Vector2.new(0.5, 0)
bannerFrame.Position = UDim2.new(0.5, 0, 0, 8)
bannerFrame.Size = UDim2.fromOffset(280, 46)
bannerFrame.BackgroundColor3 = Theme.Background.Panel
bannerFrame.BackgroundTransparency = 0.08
bannerFrame.Parent = bannerGui
Theme.ApplyCorner(bannerFrame, UDim.new(0, 12))
local bannerStroke = Theme.ApplyStroke(bannerFrame, Theme.Neon.Cyan, 2)

local bannerUIScale = Instance.new("UIScale")
bannerUIScale.Parent = bannerFrame
Device.BindUIScale(bannerUIScale)

local bannerGlyphLabel = makeLabel({
	Parent = bannerFrame,
	Text = "🌊",
	Size = UDim2.fromOffset(34, 34),
	Position = UDim2.fromOffset(6, 6),
	Font = Theme.Font.Header,
	MinSize = 16,
	MaxSize = 26,
	XAlign = Enum.TextXAlignment.Center,
})

local bannerNameLabel = makeLabel({
	Parent = bannerFrame,
	Text = "Loading…",
	Size = UDim2.new(1, -46, 0, 22),
	Position = UDim2.fromOffset(44, 4),
	Font = Theme.Font.BodyBold,
	MinSize = 11,
	MaxSize = 16,
})

local bannerCountdownLabel = makeLabel({
	Parent = bannerFrame,
	Text = "--:--:--",
	Size = UDim2.new(1, -46, 0, 18),
	Position = UDim2.fromOffset(44, 24),
	Color = Theme.Text.Secondary,
	Font = Theme.Font.Mono,
	MinSize = 9,
	MaxSize = 13,
})

local function applyBannerColors(colorPrimary: Color3)
	bannerStroke.Color = colorPrimary
	bannerGlyphLabel.TextColor3 = colorPrimary
end

local bannerCountdownThread: thread? = nil
local function startBannerCountdown()
	if bannerCountdownThread then
		return
	end
	bannerCountdownThread = task.spawn(function()
		while true do
			if currentState then
				local remaining = currentState.SlotEnd - os.time()
				bannerCountdownLabel.Text = formatCountdown(remaining)
			end
			task.wait(1)
		end
	end)
end

-- // Shop-Reiter ------------------------------------------------------------------

local function buildShopCard(parent: Instance, order: number, item: ShopItemRow)
	local card = Instance.new("Frame")
	card.Name = "ShopItem_" .. item.Id
	card.BackgroundColor3 = Theme.Background.PanelLight
	card.Size = UDim2.new(1, 0, 0, 74)
	card.LayoutOrder = order
	card.Parent = parent
	Theme.ApplyCorner(card, UDim.new(0, 12))
	Theme.ApplyStroke(card, Theme.Background.Divider, 1.5)

	makeLabel({
		Parent = card,
		Text = SHOP_ITEM_GLYPH[item.Type] or "❔",
		Size = UDim2.fromOffset(30, 30),
		Position = UDim2.fromOffset(8, 8),
		Font = Theme.Font.Header,
		MinSize = 14,
		MaxSize = 22,
		XAlign = Enum.TextXAlignment.Center,
	})

	makeLabel({
		Parent = card,
		Text = item.DisplayName,
		Size = UDim2.new(1, -140, 0, 22),
		Position = UDim2.fromOffset(46, 8),
		Font = Theme.Font.BodyBold,
		MinSize = 11,
		MaxSize = 16,
		Wrapped = true,
	})

	makeLabel({
		Parent = card,
		Text = tostring(item.Cost) .. " " .. (currentState and currentState.CurrencyGlyph or ""),
		Size = UDim2.new(1, -140, 0, 18),
		Position = UDim2.fromOffset(46, 32),
		Color = Theme.Neon.Yellow,
		MinSize = 10,
		MaxSize = 14,
	})

	local buyButton = Button.new({
		Parent = card,
		Text = "Buy",
		Variant = "Primary",
		Size = UDim2.fromOffset(96, 34),
		LayoutOrder = 1,
	})
	buyButton.Instance.AnchorPoint = Vector2.new(1, 0.5)
	buyButton.Instance.Position = UDim2.new(1, -10, 0.5, 0)
	buyButton.Clicked:Connect(function()
		buyButton:SetDisabled(true)
		LiveEventRemotes.RequestPurchaseShopItem:FireServer(item.Id)
	end)

	return {
		Button = buyButton,
		Destroy = function(_self)
			buyButton:Destroy()
			card:Destroy()
		end,
	}
end

local function rebuildShopTab()
	local host = shopHost
	if not host or not currentState then
		return
	end
	for _, handle in shopCardHandles do
		handle:Destroy()
	end
	table.clear(shopCardHandles)

	for order, item in ipairs(currentState.ShopItems) do
		shopCardHandles[item.Id] = buildShopCard(host, order, item)
	end
end

local function refreshShopAffordability()
	if not currentState then
		return
	end
	for _, item in ipairs(currentState.ShopItems) do
		local handle = shopCardHandles[item.Id]
		if handle then
			(handle :: any).Button:SetDisabled(currentState.CurrencyBalance < item.Cost)
		end
	end
end

-- // Quest-Reiter -----------------------------------------------------------------

-- Vorwärtsdeklaration (buildQuestStepRow/rebuildQuestTab unten referenzieren
-- diese Funktion, bevor sie definiert ist - als lokaler Upvalue statt eines
-- impliziten Globals, siehe Zuweisung weiter unten).
local refreshQuestClaimState: () -> ()

local function buildQuestStepRow(parent: Instance, order: number, step: QuestStepRow)
	local row = Instance.new("Frame")
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(1, 0, 0, 46)
	row.LayoutOrder = order
	row.Parent = parent

	makeLabel({
		Parent = row,
		Text = step.Description,
		Size = UDim2.new(1, 0, 0, 20),
		Font = Theme.Font.BodyBold,
		MinSize = 11,
		MaxSize = 15,
		Wrapped = true,
	})

	local barHost = Instance.new("Frame")
	barHost.BackgroundTransparency = 1
	barHost.Size = UDim2.new(1, -60, 0, 16)
	barHost.Position = UDim2.fromOffset(0, 24)
	barHost.Parent = row
	local bar = ProgressBar.new({
		Parent = barHost,
		Size = UDim2.new(1, 0, 1, 0),
		Value = step.Target > 0 and (step.Progress / step.Target) or 0,
		Colors = { Theme.Neon.Cyan, Theme.Neon.ToxicGreen },
	})

	local progressLabel = makeLabel({
		Parent = row,
		Text = ("%d / %d"):format(step.Progress, step.Target),
		Size = UDim2.fromOffset(56, 16),
		Position = UDim2.new(1, -56, 0, 24),
		Color = Theme.Text.Secondary,
		MinSize = 9,
		MaxSize = 12,
		XAlign = Enum.TextXAlignment.Right,
	})

	return { Bar = bar, ProgressLabel = progressLabel, Destroy = function(_self)
		bar:Destroy()
		row:Destroy()
	end }
end

local function rebuildQuestTab()
	local host = questHost
	if not host or not currentState then
		return
	end
	for _, handle in ipairs(questStepHandles) do
		handle:Destroy()
	end
	table.clear(questStepHandles)

	local questLine = currentState.QuestLine

	makeLabel({
		Parent = host,
		Text = questLine.Title,
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Font.Header,
		Color = currentState.ColorPrimary,
		MinSize = 14,
		MaxSize = 20,
		LayoutOrder = 0,
	})

	for order, step in ipairs(questLine.Steps) do
		local handle = buildQuestStepRow(host, order, step)
		table.insert(questStepHandles, handle)
	end

	questRewardLabel = makeLabel({
		Parent = host,
		Text = ("Reward: 🪙%d + \"%s\" title"):format(questLine.RewardTideCoins, questLine.RewardTitle),
		Size = UDim2.new(1, 0, 0, 20),
		Color = Theme.Neon.Yellow,
		MinSize = 10,
		MaxSize = 14,
		LayoutOrder = 10,
	})

	if questClaimButton then
		questClaimButton:Destroy()
		questClaimButton = nil
	end
	questClaimButton = Button.new({
		Parent = host,
		Text = "Claim Reward",
		Variant = "Success",
		Important = true,
		Size = UDim2.new(1, 0, 0, 42),
		LayoutOrder = 11,
	})
	questClaimButton.Clicked:Connect(function()
		questClaimButton:SetDisabled(true)
		LiveEventRemotes.RequestClaimEventQuest:FireServer()
	end)

	refreshQuestClaimState()
end

refreshQuestClaimState = function()
	if not currentState or not questClaimButton then
		return
	end
	local questLine = currentState.QuestLine
	if questLine.Claimed then
		questClaimButton:SetDisabled(true)
		questClaimButton:SetText("Done ✓")
		return
	end
	local allComplete = true
	for _, step in ipairs(questLine.Steps) do
		if step.Progress < step.Target then
			allComplete = false
			break
		end
	end
	questClaimButton:SetDisabled(not allComplete)
	questClaimButton:SetText(if allComplete then "Claim Reward!" else "In Progress")
end

-- // Info-Reiter ------------------------------------------------------------------

local function rebuildInfoTab()
	local host = infoHost
	if not host or not currentState then
		return
	end
	for _, child in ipairs(host:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	makeLabel({
		Parent = host,
		Text = currentState.DisplayName,
		Size = UDim2.new(1, 0, 0, 30),
		Font = Theme.Font.Header,
		Color = currentState.ColorPrimary,
		MinSize = 16,
		MaxSize = 24,
		LayoutOrder = 0,
	})

	makeLabel({
		Parent = host,
		Text = "This event runs for 12 hours every 3 days. Missed event creatures come back soon!",
		Size = UDim2.new(1, 0, 0, 60),
		Color = Theme.Text.Secondary,
		Wrapped = true,
		MinSize = 11,
		MaxSize = 15,
		LayoutOrder = 1,
	})

	makeLabel({
		Parent = host,
		Text = "Event currency: " .. currentState.CurrencyDisplayName .. " (resets when the slot ends)",
		Size = UDim2.new(1, 0, 0, 22),
		Color = Theme.Neon.Yellow,
		MinSize = 10,
		MaxSize = 14,
		LayoutOrder = 2,
	})
end

-- // Haupt-Panel -------------------------------------------------------------------

local function buildMainPanel()
	if mainPanel then
		return
	end

	mainPanel = Panel.new({
		Title = "Live-Event",
		Closable = true,
		CenteredSize = UDim2.fromOffset(560, 620),
	})

	currencyLabel = makeLabel({
		Parent = mainPanel.Content,
		Text = "",
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Font.BodyBold,
		Color = Theme.Neon.Yellow,
		MinSize = 12,
		MaxSize = 18,
	})

	local tabsHost = Instance.new("Frame")
	tabsHost.BackgroundTransparency = 1
	tabsHost.Size = UDim2.new(1, 0, 1, -30)
	tabsHost.Position = UDim2.fromOffset(0, 30)
	tabsHost.Parent = mainPanel.Content

	mainTabs = Tabs.new({
		Parent = tabsHost,
		Tabs = {
			{ Id = "Shop", Label = "Shop" },
			{ Id = "Quest", Label = "Quest-Linie" },
			{ Id = "Info", Label = "Info" },
		},
		DefaultTabId = "Shop",
	})

	-- WICHTIG (docs/ui-kit.md, Tabs-Abschnitt): GetContentFrame liefert
	-- bereits eine ScrollingFrame MIT eigenem UIListLayout - hier bewusst
	-- KEIN zusätzliches UIListLayout hinzufügen.
	shopHost = mainTabs:GetContentFrame("Shop")
	questHost = mainTabs:GetContentFrame("Quest")
	infoHost = mainTabs:GetContentFrame("Info")

	rebuildShopTab()
	rebuildQuestTab()
	rebuildInfoTab()
end

local function refreshCurrencyLabel()
	if not currencyLabel or not currentState then
		return
	end
	currencyLabel.Text = ("%s %s: %d"):format(
		currentState.CurrencyGlyph,
		currentState.CurrencyDisplayName,
		currentState.CurrencyBalance
	)
end

local function openMainPanel()
	buildMainPanel()
	if currentState then
		rebuildShopTab()
		rebuildQuestTab()
		rebuildInfoTab()
		refreshCurrencyLabel()
	end
	mainPanel:Open()
end

-- // Zustand anwenden --------------------------------------------------------------

local function applyState(state: EventStateRow, isBigMoment: boolean)
	currentState = state

	bannerNameLabel.Text = state.DisplayName
	applyBannerColors(state.ColorPrimary)
	startBannerCountdown()

	if mainPanel then
		rebuildShopTab()
		rebuildQuestTab()
		rebuildInfoTab()
	end
	refreshCurrencyLabel()

	if isBigMoment then
		Toast.Show({
			Text = ("🌊 New event: %s!"):format(state.DisplayName),
			Type = "Info",
			Duration = 4.5,
		})
		ScreenFX.BigMoment(state.ColorPrimary)
	end
end

-- // Remote-Verdrahtung --------------------------------------------------------

LiveEventRemotes.EventChanged.OnClientEvent:Connect(function(payload: EventStateRow)
	if type(payload) ~= "table" or type(payload.EventId) ~= "string" then
		return
	end
	applyState(payload, hasReceivedFirstState)
	hasReceivedFirstState = true
end)

LiveEventRemotes.EventCurrencyChanged.OnClientEvent:Connect(function(payload: { Balance: number, Reason: string? })
	if not currentState then
		return
	end
	currentState.CurrencyBalance = payload.Balance
	refreshCurrencyLabel()
	refreshShopAffordability()

	local toastText = payload.Reason and CURRENCY_REASON_TOAST[payload.Reason]
	if toastText then
		Toast.Show({ Text = toastText, Type = "Success", Duration = 3 })
	end
end)

LiveEventRemotes.EventQuestProgressUpdated.OnClientEvent:Connect(function(payload: { StepIndex: number, Progress: number, Target: number })
	if not currentState then
		return
	end
	local step = currentState.QuestLine.Steps[payload.StepIndex]
	if not step then
		return
	end
	step.Progress = payload.Progress
	step.Target = payload.Target

	local handle = questStepHandles[payload.StepIndex]
	if handle then
		local ratio = payload.Target > 0 and (payload.Progress / payload.Target) or 0
		handle.Bar:SetProgress(ratio)
		handle.ProgressLabel.Text = ("%d / %d"):format(payload.Progress, payload.Target)
	end
	refreshQuestClaimState()
end)

LiveEventRemotes.ShopPurchaseResult.OnClientEvent:Connect(function(payload: {
	Success: boolean,
	Reason: string?,
	ItemId: string?,
	NewBalance: number?,
	CreatureId: string?,
	Rarity: string?,
	NewTideCoinBalance: number?,
})
	if payload.Success then
		if currentState and payload.NewBalance then
			currentState.CurrencyBalance = payload.NewBalance
			refreshCurrencyLabel()
			refreshShopAffordability()
		end
		local rewardText = if payload.CreatureId
			then ("Hatched: %s (%s)!"):format(payload.CreatureId, payload.Rarity or "?")
			else "Item purchased!"
		Toast.Show({ Text = rewardText, Type = "Success", Duration = 3.5 })
		if payload.CreatureId then
			ScreenFX.BigMoment(currentState and currentState.ColorPrimary or Theme.Neon.Cyan)
		end
	else
		Toast.Show({ Text = friendlyReason(SHOP_REASON_MESSAGES, payload.Reason), Type = "Warning", Duration = 3.5 })
	end

	if payload.ItemId then
		local handle = shopCardHandles[payload.ItemId]
		if handle then
			refreshShopAffordability()
		end
	end
end)

LiveEventRemotes.ClaimEventQuestResult.OnClientEvent:Connect(function(payload: {
	Success: boolean,
	Reason: string?,
	RewardTideCoins: number?,
	RewardTitle: string?,
	NewTideCoinBalance: number?,
})
	if payload.Success then
		if currentState then
			currentState.QuestLine.Claimed = true
		end
		refreshQuestClaimState()
		Toast.Show({
			Text = ("Event quest completed: 🪙%d + \"%s\" title!"):format(
				payload.RewardTideCoins or 0,
				payload.RewardTitle or ""
			),
			Type = "Success",
			Duration = 4,
		})
		ScreenFX.BigMoment(currentState and currentState.ColorPrimary or Theme.Neon.Yellow)
	else
		refreshQuestClaimState()
		Toast.Show({ Text = friendlyReason(QUEST_REASON_MESSAGES, payload.Reason), Type = "Warning", Duration = 3.5 })
	end
end)

local bridgeConnection = openEventEvent.Event:Connect(openMainPanel)

-- // Initialer Sync ----------------------------------------------------------------

task.spawn(function()
	local ok, result = pcall(function()
		return LiveEventRemotes.GetEventState:InvokeServer()
	end)
	if ok and type(result) == "table" and type(result.EventId) == "string" then
		applyState(result :: EventStateRow, false)
		hasReceivedFirstState = true
	else
		warn("[EventUIController] Konnte Event-Status nicht laden:", result)
	end
end)

-- // Aufräumen ------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	if bannerCountdownThread then
		task.cancel(bannerCountdownThread)
		bannerCountdownThread = nil
	end
	bridgeConnection:Disconnect()
	for _, handle in shopCardHandles do
		handle:Destroy()
	end
	for _, handle in ipairs(questStepHandles) do
		handle:Destroy()
	end
	if questClaimButton then
		questClaimButton:Destroy()
	end
	if mainTabs then
		mainTabs:Destroy()
	end
	if mainPanel then
		mainPanel:Destroy()
	end
	bannerGui:Destroy()
end)
