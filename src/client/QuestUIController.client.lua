--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: QuestUIController (LocalScript)
	Zuständigkeit:
		UI für die beiden in `docs/server-features.md` Abschnitt 3.1/3.2
		beschriebenen, bereits fertig serverseitig validierten Systeme:
			1. Tages-Quests (3 Stück/Tag, Fortschrittsbalken, Abholen-Button,
			   Countdown bis 00:00 UTC Reset).
			2. Tages-Login-Belohnung (7-Tage-Streak) – erscheint automatisch
			   als eigenes Popup beim Join, sofern abholbar, zusätzlich immer
			   über die kompakte Streak-Leiste oben im Quests-Panel erreichbar.

		Datenquelle ausschließlich `QuestRemotes` (siehe dortiger Kopf-
		kommentar) – nie eigene Fortschritts-/Claim-Berechnung, jeder Klick
		ist nur eine Anfrage, der Server validiert komplett neu.

		HARTE UIKit-REGEL (docs/ui-kit.md): jeder Button ausschließlich über
		UIKit.Button.new(...).

		Bridge-Kommunikation (ReplicatedStorage.AbyssaraUIBridge, identisches
		Muster wie MainMenuController/ShopUIController):
			- "OpenQuests" (eingehend) – MainMenuController-Menüeintrag öffnet
			  dieses Panel.
			- "QuestBadgeCountChanged" (ausgehend, Payload: count: number) –
			  MainMenuController zeigt damit ein Badge am Menüeintrag, wenn
			  etwas abholbar ist (offene Quest-Belohnung ODER Tages-Login).
			- "DailyRewardPopupClosed" (ausgehend, keine Payload) – feuert,
			  sobald das automatische Login-Popup entschieden/geschlossen
			  wurde (oder sofort, falls beim Start nichts abzuholen war).
			  OnboardingController wartet kurz darauf, damit sich das
			  Login-Popup und das Einstiegs-Tutorial nicht überlappen.

	Rojo-Einhängepunkt:
		src/client/QuestUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.QuestUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local QuestRemotes = require(ReplicatedStorage:WaitForChild("QuestRemotes"))
local DailyRewardConfig = require(ReplicatedStorage:WaitForChild("DailyRewardConfig"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Panel = UIKit.Panel
local Button = UIKit.Button
local Toast = UIKit.Toast
local ProgressBar = UIKit.ProgressBar
local ScreenFX = UIKit.ScreenFX

local localPlayer = Players.LocalPlayer

-- // Bridge (identisches Muster wie MainMenuController/ShopUIController) -------

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

local openQuestsEvent = getOrCreateBridgeEvent("OpenQuests")
local questBadgeCountEvent = getOrCreateBridgeEvent("QuestBadgeCountChanged")
local dailyRewardPopupClosedEvent = getOrCreateBridgeEvent("DailyRewardPopupClosed")

-- // Anzeige-Metadaten ----------------------------------------------------------

local QUEST_GLYPH: { [string]: string } = {
	DeliverSpores = "🌟",
	CompleteBreeding = "🥚",
	WinRaid = "⚔️",
	PlaceBuilding = "🏗️",
}

local QUEST_REASON_MESSAGES: { [string]: string } = {
	DataNotLoaded = "Deine Spieldaten laden noch – bitte kurz warten.",
	UnknownQuest = "Diese Quest ist nicht mehr gültig.",
	NotCompleted = "Diese Quest ist noch nicht abgeschlossen.",
	AlreadyClaimed = "Belohnung wurde bereits abgeholt.",
}

local DAILY_REASON_MESSAGES: { [string]: string } = {
	DataNotLoaded = "Deine Spieldaten laden noch – bitte kurz warten.",
	AlreadyClaimedToday = "Heute schon abgeholt – komm morgen wieder!",
}

local function friendlyQuestReason(reason: string?): string
	if not reason then
		return "Aktion fehlgeschlagen. Bitte erneut versuchen."
	end
	return QUEST_REASON_MESSAGES[reason] or ("Aktion fehlgeschlagen (" .. reason .. ").")
end

local function friendlyDailyReason(reason: string?): string
	if not reason then
		return "Aktion fehlgeschlagen. Bitte erneut versuchen."
	end
	return DAILY_REASON_MESSAGES[reason] or ("Aktion fehlgeschlagen (" .. reason .. ").")
end

-- // Countdown bis 00:00 UTC (identisches Muster zu ShopUIController) ----------

local function secondsUntilNextUtcMidnight(): number
	local now = os.time()
	local utcNow = os.date("!*t", now)
	local nowClock = utcNow.hour * 3600 + utcNow.min * 60 + utcNow.sec
	local remaining = (24 * 3600) - nowClock
	if remaining <= 0 then
		remaining = 24 * 3600
	end
	return remaining
end

local function formatCountdown(totalSeconds: number): string
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	local seconds = math.floor(totalSeconds % 60)
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

type QuestRow = {
	TemplateId: string,
	Description: string,
	Target: number,
	Progress: number,
	Completed: boolean,
	Claimed: boolean,
	RewardTideCoins: number,
	RewardAbyssalShards: number,
	RewardXP: number,
}

type DailyRewardState = {
	CanClaim: boolean,
	PendingStreakDay: number,
	PreviewTideCoins: number,
	PreviewAbyssalShards: number,
	VipBonusActive: boolean,
	AlreadyClaimedToday: boolean,
}

-- // State ------------------------------------------------------------------------

local questRows: { [string]: QuestRow } = {}
local questOrder: { string } = {}
local dailyState: DailyRewardState? = nil

local mainPanel: any = nil
local mainCountdownLabel: TextLabel? = nil
local mainCountdownThread: thread? = nil
local mainStreakWidget: any = nil
local mainQuestCardsHost: Frame? = nil

type QuestCardHandle = {
	DescriptionLabel: TextLabel,
	ProgressBar: any,
	ProgressLabel: TextLabel,
	ClaimButton: any,
	Destroy: (self: QuestCardHandle) -> (),
}
local questCardHandles: { [string]: QuestCardHandle } = {}

local popupPanel: any = nil
local popupStreakWidget: any = nil
local popupResolved = false

-- // Badge-Berechnung --------------------------------------------------------------

local function computeClaimableBadgeCount(): number
	local count = 0
	for _, row in questRows do
		if row.Completed and not row.Claimed then
			count += 1
		end
	end
	if dailyState and dailyState.CanClaim then
		count += 1
	end
	return count
end

local function refreshBadge()
	questBadgeCountEvent:Fire(computeClaimableBadgeCount())
end

-- // Tages-Login-Streak-Widget (wird sowohl im Panel als auch im Auto-Popup
-- verwendet, um Doppelcode zu vermeiden) ------------------------------------------

local function buildStreakWidget(parent: Instance, compact: boolean): any
	local host = Instance.new("Frame")
	host.Name = "StreakWidget"
	host.BackgroundTransparency = 1
	host.AutomaticSize = Enum.AutomaticSize.Y
	host.Size = UDim2.new(1, 0, 0, 0)
	host.Parent = parent

	local title = makeLabel({
		Parent = host,
		Text = "🔥 Tages-Login-Serie",
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.Font.BodyBold,
		Color = Theme.Neon.Yellow,
		MinSize = 13,
		MaxSize = 18,
	})

	local pillHost = Instance.new("Frame")
	pillHost.Name = "Pills"
	pillHost.BackgroundTransparency = 1
	pillHost.Size = UDim2.new(1, 0, 0, compact and 56 or 72)
	pillHost.Position = UDim2.fromOffset(0, 26)
	pillHost.Parent = host

	local pillGrid = Instance.new("UIGridLayout")
	pillGrid.SortOrder = Enum.SortOrder.LayoutOrder
	pillGrid.CellPadding = UDim2.fromOffset(6, 6)
	pillGrid.CellSize = UDim2.new(1 / 7, -6, 1, 0)
	pillGrid.FillDirectionMaxCells = 7
	pillGrid.Parent = pillHost

	local pills: { Frame } = {}
	local pillStrokes: { UIStroke } = {}
	for day = 1, DailyRewardConfig.MAX_STREAK_DAY do
		local reward = DailyRewardConfig.GetReward(day)
		local pill = Instance.new("Frame")
		pill.Name = "Day" .. day
		pill.BackgroundColor3 = Theme.Background.PanelLight
		pill.LayoutOrder = day
		Theme.ApplyCorner(pill, UDim.new(0, 10))
		local pillStroke = Theme.ApplyStroke(pill, Theme.Background.Divider, 2)
		pill.Parent = pillHost

		local dayLabel = makeLabel({
			Parent = pill,
			Text = "Tag " .. day,
			Size = UDim2.new(1, -6, 0, 16),
			Position = UDim2.fromOffset(3, 4),
			Font = Theme.Font.BodyBold,
			MinSize = 8,
			MaxSize = 12,
			XAlign = Enum.TextXAlignment.Center,
		})
		dayLabel.Name = "DayLabel"

		local rewardText = "🪙" .. reward.TideCoins
		if reward.AbyssalShards > 0 then
			rewardText ..= "\n💎" .. reward.AbyssalShards
		end
		local rewardLabel = makeLabel({
			Parent = pill,
			Text = rewardText,
			Size = UDim2.new(1, -6, 1, -22),
			Position = UDim2.fromOffset(3, 20),
			Color = Theme.Text.Secondary,
			MinSize = 8,
			MaxSize = 12,
			XAlign = Enum.TextXAlignment.Center,
			Wrapped = true,
		})
		rewardLabel.Name = "RewardLabel"

		table.insert(pills, pill)
		table.insert(pillStrokes, pillStroke)
	end

	local vipLabel = makeLabel({
		Parent = host,
		Text = "",
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.fromOffset(0, 26 + (compact and 56 or 72) + 4),
		Color = Theme.Neon.Magenta,
		MinSize = 9,
		MaxSize = 12,
	})

	local claimButton = Button.new({
		Parent = host,
		Text = "Abholen",
		Variant = "Success",
		Important = true,
		Size = UDim2.new(1, 0, 0, 40),
		LayoutOrder = 10,
	})
	claimButton.Instance.Position = UDim2.fromOffset(0, 26 + (compact and 56 or 72) + 22)

	local handle: any = {}
	handle.Host = host
	handle.ClaimButton = claimButton

	handle.Refresh = function(_self, state: DailyRewardState?)
		if not state then
			claimButton:SetDisabled(true)
			claimButton:SetText("Lädt…")
			return
		end
		for day, pill in ipairs(pills) do
			local stroke = pillStrokes[day]
			if day < state.PendingStreakDay or (day == state.PendingStreakDay and state.AlreadyClaimedToday) then
				pill.BackgroundColor3 = Theme.Background.Panel
				stroke.Color = Theme.Neon.ToxicGreen
				stroke.Thickness = 2
			elseif day == state.PendingStreakDay then
				pill.BackgroundColor3 = Theme.Background.PanelLight
				stroke.Color = Theme.Neon.Yellow
				stroke.Thickness = 3
			else
				pill.BackgroundColor3 = Theme.Background.Deepest
				stroke.Color = Theme.Background.Divider
				stroke.Thickness = 1.5
			end
		end

		if state.VipBonusActive then
			vipLabel.Text = "👑 VIP-Taucher-Bonus: +50% Tide Coins heute"
		else
			vipLabel.Text = ""
		end

		if state.AlreadyClaimedToday then
			claimButton:SetDisabled(true)
			claimButton:SetText("Heute schon abgeholt")
		elseif state.CanClaim then
			claimButton:SetDisabled(false)
			claimButton:SetText(("Tag %d abholen: 🪙%d 💎%d"):format(
				state.PendingStreakDay,
				state.PreviewTideCoins,
				state.PreviewAbyssalShards
			))
		else
			claimButton:SetDisabled(true)
			claimButton:SetText("Nicht verfügbar")
		end
	end

	handle.Destroy = function(_self)
		claimButton:Destroy()
		host:Destroy()
	end

	return handle
end

-- // Tages-Login-Belohnung: Netzwerk-Aufrufe --------------------------------------

local function requestDailyRewardState(): DailyRewardState?
	local ok, result = pcall(function()
		return QuestRemotes.GetDailyRewardState:InvokeServer()
	end)
	if ok and type(result) == "table" then
		return result :: DailyRewardState
	end
	warn("[QuestUIController] Konnte Tages-Login-Status nicht laden:", result)
	return nil
end

local function claimDailyReward()
	QuestRemotes.RequestClaimDailyReward:FireServer()
end

-- // Quest-Karten (Panel-Inhalt) ---------------------------------------------------

local function buildQuestCard(parent: Instance, layoutOrder: number, row: QuestRow): QuestCardHandle
	local card = Instance.new("Frame")
	card.Name = "QuestCard_" .. row.TemplateId
	card.BackgroundColor3 = Theme.Background.PanelLight
	card.Size = UDim2.new(1, 0, 0, 128)
	card.LayoutOrder = layoutOrder
	card.Parent = parent
	Theme.ApplyCorner(card, UDim.new(0, 14))
	local stroke = Theme.ApplyStroke(card, Theme.Neon.Cyan, 2)
	stroke.Transparency = 0.4
	Theme.ApplyGradient(card, { Theme.Background.PanelLight, Theme.Background.Panel }, 100)

	local glyph = QUEST_GLYPH[row.TemplateId] or "📜"
	local glyphLabel = makeLabel({
		Parent = card,
		Text = glyph,
		Size = UDim2.fromOffset(36, 36),
		Position = UDim2.fromOffset(10, 10),
		Font = Theme.Font.Header,
		MinSize = 18,
		MaxSize = 28,
		XAlign = Enum.TextXAlignment.Center,
	})
	glyphLabel.Name = "Glyph"

	local descriptionLabel = makeLabel({
		Parent = card,
		Text = row.Description,
		Size = UDim2.new(1, -60, 0, 40),
		Position = UDim2.fromOffset(54, 8),
		Font = Theme.Font.BodyBold,
		MinSize = 12,
		MaxSize = 17,
		Wrapped = true,
	})

	local progressHost = Instance.new("Frame")
	progressHost.BackgroundTransparency = 1
	progressHost.Size = UDim2.new(1, -20, 0, 18)
	progressHost.Position = UDim2.fromOffset(10, 54)
	progressHost.Parent = card
	local progressBar = ProgressBar.new({
		Parent = progressHost,
		Size = UDim2.new(1, 0, 1, 0),
		Value = row.Target > 0 and (row.Progress / row.Target) or 0,
		Colors = { Theme.Neon.Cyan, Theme.Neon.ToxicGreen },
	})

	local progressLabel = makeLabel({
		Parent = card,
		Text = ("%d / %d"):format(row.Progress, row.Target),
		Size = UDim2.new(1, -20, 0, 16),
		Position = UDim2.fromOffset(10, 74),
		Color = Theme.Text.Secondary,
		MinSize = 9,
		MaxSize = 13,
		XAlign = Enum.TextXAlignment.Right,
	})

	local rewardText = "🪙" .. row.RewardTideCoins
	if row.RewardAbyssalShards > 0 then
		rewardText ..= "  💎" .. row.RewardAbyssalShards
	end
	rewardText ..= "  ⭐" .. row.RewardXP .. " XP"
	makeLabel({
		Parent = card,
		Text = rewardText,
		Size = UDim2.new(0.6, -10, 0, 22),
		Position = UDim2.fromOffset(10, 92),
		Color = Theme.Neon.Yellow,
		MinSize = 10,
		MaxSize = 14,
	})

	local claimButton = Button.new({
		Parent = card,
		Text = "In Arbeit",
		Variant = "Success",
		Important = true,
		Disabled = true,
		Size = UDim2.new(0.4, -10, 0, 30),
		LayoutOrder = 1,
	})
	claimButton.Instance.AnchorPoint = Vector2.new(1, 0)
	claimButton.Instance.Position = UDim2.new(1, -10, 0, 92)
	claimButton.Clicked:Connect(function()
		QuestRemotes.RequestClaimQuestReward:FireServer(row.TemplateId)
		claimButton:SetDisabled(true)
		claimButton:SetText("Wird abgeholt…")
	end)

	local handle: QuestCardHandle = {
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

local function updateQuestCardVisual(templateId: string)
	local row = questRows[templateId]
	local card = questCardHandles[templateId]
	if not row or not card then
		return
	end
	local ratio = row.Target > 0 and (row.Progress / row.Target) or 0
	card.ProgressBar:SetProgress(ratio)
	card.ProgressLabel.Text = ("%d / %d"):format(math.min(row.Progress, row.Target), row.Target)

	if row.Claimed then
		card.ClaimButton:SetDisabled(true)
		card.ClaimButton:SetText("Erledigt ✓")
	elseif row.Completed then
		card.ClaimButton:SetDisabled(false)
		card.ClaimButton:SetText("Abholen!")
	else
		card.ClaimButton:SetDisabled(true)
		card.ClaimButton:SetText("In Arbeit")
	end
end

local function rebuildQuestCards()
	local host = mainQuestCardsHost
	if not host then
		return
	end
	for _, handle in questCardHandles do
		handle:Destroy()
	end
	table.clear(questCardHandles)

	for order, templateId in ipairs(questOrder) do
		local row = questRows[templateId]
		if row then
			questCardHandles[templateId] = buildQuestCard(host, order, row)
			updateQuestCardVisual(templateId)
		end
	end
end

-- // Countdown-Loop (nur während Panel offen) -------------------------------------

local function stopCountdown()
	if mainCountdownThread then
		task.cancel(mainCountdownThread)
		mainCountdownThread = nil
	end
end

local function startCountdown()
	stopCountdown()
	mainCountdownThread = task.spawn(function()
		while true do
			if mainCountdownLabel then
				mainCountdownLabel.Text = "Neue Quests in " .. formatCountdown(secondsUntilNextUtcMidnight())
			end
			task.wait(1)
		end
	end)
end

-- // Haupt-Panel -------------------------------------------------------------------

local function buildMainPanel()
	if mainPanel then
		return
	end

	mainPanel = Panel.new({
		Title = "Tages-Quests",
		Closable = true,
		CenteredSize = UDim2.fromOffset(560, 640),
		OnClose = function()
			stopCountdown()
		end,
	})

	local scroller = Instance.new("ScrollingFrame")
	scroller.Name = "Scroller"
	scroller.BackgroundTransparency = 1
	scroller.Size = UDim2.fromScale(1, 1)
	scroller.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroller.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroller.ScrollBarThickness = 6
	scroller.ScrollBarImageColor3 = Theme.Neon.Cyan
	scroller.BorderSizePixel = 0
	scroller.Parent = mainPanel.Content

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 12)
	list.Parent = scroller

	mainStreakWidget = buildStreakWidget(scroller, true)
	mainStreakWidget.Host.LayoutOrder = 1
	mainStreakWidget.ClaimButton.Clicked:Connect(claimDailyReward)

	local divider = Instance.new("Frame")
	divider.BackgroundColor3 = Theme.Background.Divider
	divider.BorderSizePixel = 0
	divider.Size = UDim2.new(1, 0, 0, 1)
	divider.LayoutOrder = 2
	divider.Parent = scroller

	mainCountdownLabel = makeLabel({
		Parent = scroller,
		Text = "Neue Quests in --:--:--",
		Size = UDim2.new(1, 0, 0, 22),
		Font = Theme.Font.BodyBold,
		Color = Theme.Neon.Cyan,
		MinSize = 11,
		MaxSize = 16,
		LayoutOrder = 3,
	})

	mainQuestCardsHost = Instance.new("Frame")
	mainQuestCardsHost.Name = "QuestCards"
	mainQuestCardsHost.BackgroundTransparency = 1
	mainQuestCardsHost.AutomaticSize = Enum.AutomaticSize.Y
	mainQuestCardsHost.Size = UDim2.new(1, 0, 0, 0)
	mainQuestCardsHost.LayoutOrder = 4
	mainQuestCardsHost.Parent = scroller
	local cardsList = Instance.new("UIListLayout")
	cardsList.SortOrder = Enum.SortOrder.LayoutOrder
	cardsList.Padding = UDim.new(0, 10)
	cardsList.Parent = mainQuestCardsHost

	rebuildQuestCards()
	mainStreakWidget:Refresh(dailyState)
end

local function openMainPanel()
	buildMainPanel()
	mainPanel:Open()
	startCountdown()
	-- Beim Öffnen den Tages-Login-Status frisch nachladen, falls das
	-- automatische Popup ihn zwischenzeitlich verändert hat.
	task.spawn(function()
		dailyState = requestDailyRewardState()
		if mainStreakWidget then
			mainStreakWidget:Refresh(dailyState)
		end
		refreshBadge()
	end)
end

-- // Automatisches Login-Popup -----------------------------------------------------

local function resolveDailyPopup()
	if popupResolved then
		return
	end
	popupResolved = true
	dailyRewardPopupClosedEvent:Fire()
end

local function showAutoPopup()
	if not dailyState or not dailyState.CanClaim then
		resolveDailyPopup()
		return
	end

	popupPanel = Panel.new({
		Title = "Willkommen zurück!",
		Closable = true,
		CenteredSize = UDim2.fromOffset(480, 360),
		OnClose = function()
			resolveDailyPopup()
		end,
	})

	local intro = makeLabel({
		Parent = popupPanel.Content,
		Text = "Deine Tages-Belohnung wartet auf dich!",
		Size = UDim2.new(1, 0, 0, 26),
		Font = Theme.Font.BodyBold,
		Color = Theme.Text.Primary,
		MinSize = 13,
		MaxSize = 19,
	})
	intro.Position = UDim2.fromOffset(0, 0)

	popupStreakWidget = buildStreakWidget(popupPanel.Content, false)
	popupStreakWidget.Host.Position = UDim2.fromOffset(0, 32)
	popupStreakWidget:Refresh(dailyState)
	popupStreakWidget.ClaimButton.Clicked:Connect(claimDailyReward)

	popupPanel:Open()
end

-- // Remote-Verdrahtung --------------------------------------------------------

QuestRemotes.QuestProgressUpdated.OnClientEvent:Connect(function(payload: { TemplateId: string, Progress: number, Target: number, Completed: boolean })
	if type(payload) ~= "table" or type(payload.TemplateId) ~= "string" then
		return
	end
	local row = questRows[payload.TemplateId]
	if not row then
		return
	end
	row.Progress = payload.Progress
	row.Target = payload.Target
	row.Completed = payload.Completed
	updateQuestCardVisual(payload.TemplateId)
	refreshBadge()
end)

QuestRemotes.ClaimQuestRewardResult.OnClientEvent:Connect(function(payload: {
	Success: boolean,
	Reason: string?,
	TemplateId: string?,
	RewardTideCoins: number?,
	RewardAbyssalShards: number?,
	RewardXP: number?,
})
	if payload.Success and payload.TemplateId then
		local row = questRows[payload.TemplateId]
		if row then
			row.Claimed = true
			updateQuestCardVisual(payload.TemplateId)
		end
		Toast.Show({
			Text = ("Quest-Belohnung erhalten: 🪙%d 💎%d ⭐%d XP"):format(
				payload.RewardTideCoins or 0,
				payload.RewardAbyssalShards or 0,
				payload.RewardXP or 0
			),
			Type = "Success",
			Duration = 3.5,
		})
		ScreenFX.BigMoment(Theme.Neon.ToxicGreen)
	else
		if payload.TemplateId then
			local card = questCardHandles[payload.TemplateId]
			local row = questRows[payload.TemplateId]
			if card and row then
				updateQuestCardVisual(payload.TemplateId)
			end
		end
		Toast.Show({ Text = friendlyQuestReason(payload.Reason), Type = "Warning", Duration = 3.5 })
	end
	refreshBadge()
end)

QuestRemotes.DailyRewardClaimed.OnClientEvent:Connect(function(payload: {
	Success: boolean,
	Reason: string?,
	StreakDay: number?,
	RewardTideCoins: number?,
	RewardAbyssalShards: number?,
})
	if payload.Success then
		if dailyState then
			dailyState.AlreadyClaimedToday = true
			dailyState.CanClaim = false
		end
		if mainStreakWidget then
			mainStreakWidget:Refresh(dailyState)
		end
		if popupStreakWidget then
			popupStreakWidget:Refresh(dailyState)
		end
		Toast.Show({
			Text = ("Tag %d abgeholt: 🪙%d 💎%d – bis morgen!"):format(
				payload.StreakDay or 1,
				payload.RewardTideCoins or 0,
				payload.RewardAbyssalShards or 0
			),
			Type = "Success",
			Duration = 4,
		})
		ScreenFX.BigMoment(Theme.Neon.Yellow)
		if popupPanel then
			task.delay(1.6, function()
				if popupPanel then
					popupPanel:Close()
				end
			end)
		end
	else
		Toast.Show({ Text = friendlyDailyReason(payload.Reason), Type = "Warning", Duration = 3.5 })
	end
	refreshBadge()
end)

local bridgeConnection = openQuestsEvent.Event:Connect(openMainPanel)

-- // Initialer Sync (Quests + Tages-Login) -----------------------------------------

task.spawn(function()
	local ok, result = pcall(function()
		return QuestRemotes.GetQuestState:InvokeServer()
	end)
	if ok and type(result) == "table" and type(result.Quests) == "table" then
		table.clear(questRows)
		table.clear(questOrder)
		for _, row in ipairs(result.Quests) do
			questRows[row.TemplateId] = row
			table.insert(questOrder, row.TemplateId)
		end
		if mainPanel then
			rebuildQuestCards()
		end
	else
		warn("[QuestUIController] Konnte Tages-Quest-Status nicht laden:", result)
	end

	dailyState = requestDailyRewardState()
	refreshBadge()

	-- Kleine Verzögerung, damit das Popup nicht exakt beim allerersten Frame
	-- (noch während andere UIs sich aufbauen) erscheint.
	task.wait(1.5)
	showAutoPopup()
end)

-- // Aufräumen ------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	stopCountdown()
	bridgeConnection:Disconnect()
	for _, handle in questCardHandles do
		handle:Destroy()
	end
	if mainStreakWidget then
		mainStreakWidget:Destroy()
	end
	if popupStreakWidget then
		popupStreakWidget:Destroy()
	end
	if mainPanel then
		mainPanel:Destroy()
	end
	if popupPanel then
		popupPanel:Destroy()
	end
end)
