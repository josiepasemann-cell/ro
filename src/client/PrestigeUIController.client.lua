--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Script: PrestigeUIController (LocalScript)
	Responsibility:
		"Resurface" (prestige) panel: shows the ascend count and the
		permanent income multiplier, explains clearly what you KEEP and what
		RESETS (texts come from PrestigeConfig so UI and design doc stay in
		sync), shows the next multiplier/title/shard reward and the
		requirement status, and starts the resurface through a strong
		two-step UIKit.ConfirmDialog (dialog 1 -> server "arm" -> dialog 2
		-> RequestResurface). Display only: eligibility, multiplier and
		rewards are decided by PrestigeService on the server.

		Opened from the More drawer of MainMenuController through the
		AbyssaraUIBridge event "OpenPrestige" (no keyboard shortcut on
		purpose, so it can not be triggered by accident). After a successful
		resurface it fires the bridge event "PrestigeCompleted" so the quest
		and raid UIs re-sync.

	Rojo mount point:
		src/client/PrestigeUIController.client.lua -> StarterPlayerScripts.PrestigeUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PrestigeRemotes = require(ReplicatedStorage:WaitForChild("PrestigeRemotes"))
local PrestigeConfig = require(ReplicatedStorage:WaitForChild("PrestigeConfig"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Panel = UIKit.Panel
local Button = UIKit.Button
local Toast = UIKit.Toast
local ScreenFX = UIKit.ScreenFX
local ConfirmDialog = UIKit.ConfirmDialog

local localPlayer = Players.LocalPlayer

-- // Bridge (same pattern as the other controllers) -------------------------------

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

local openPrestigeEvent = getOrCreateBridgeEvent("OpenPrestige")
local prestigeCompletedEvent = getOrCreateBridgeEvent("PrestigeCompleted")

-- // Texts --------------------------------------------------------------------------

local BLOCK_TEXT: { [string]: string } = {
	NotEligible = "Reach the Hadal Depths or level %d to resurface.",
	InRaid = "A raid is running. Resurface when it is over.",
	Cooldown = "You just resurfaced. Give it a minute.",
	FinishedEggWaiting = "Collect your finished Brood Pool egg first so you don't lose it.",
	DataNotLoaded = "Still loading your reef ... try again in a moment.",
	Busy = "Resurfacing is already in progress.",
	RateLimited = "Slow down a little!",
	NotArmed = "Please confirm again.",
}

local function blockText(reason: string?): string
	local text = BLOCK_TEXT[tostring(reason)] or "You can't resurface right now."
	if reason == "NotEligible" then
		return text:format(PrestigeConfig.REQUIRED_LEVEL)
	end
	return text
end

-- // Panel --------------------------------------------------------------------------

local panel: any = nil
local scroller: ScrollingFrame? = nil
local resurfaceButton: any = nil
local requestPending = false
local currentInfo: { [string]: any }? = nil

local function makeLabel(parent: Instance, order: number, text: string, font: Enum.Font, color: Color3, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.Font = font
	label.TextColor3 = color
	label.TextSize = size
	label.TextWrapped = true
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.Text = text
	label.LayoutOrder = order
	label.Parent = parent
	return label
end

local function formatList(items: { string }): string
	local lines = {}
	for _, item in ipairs(items) do
		table.insert(lines, "•  " .. item)
	end
	return table.concat(lines, "\n")
end

local function rebuildContent(info: { [string]: any })
	local host = scroller
	if not host then
		return
	end
	for _, child in ipairs(host:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local count = info.AscendCount or 0
	local multiplier = info.IncomeMultiplier or 1

	makeLabel(host, 1, ("Resurfaced: %d times   |   Income bonus: x%.2f"):format(count, multiplier), Theme.Font.Header, Theme.Neon.Cyan, 20)
	makeLabel(
		host,
		2,
		"Return to the Sun Zone and start again with a permanent income bonus and a new title. Your reef will grow back faster every time!",
		Theme.Font.Body,
		Theme.Text.Secondary,
		16
	)

	makeLabel(host, 3, "You KEEP", Theme.Font.Header, Theme.Neon.ToxicGreen, 18)
	makeLabel(host, 4, formatList(PrestigeConfig.KEPT), Theme.Font.Body, Theme.Text.Primary, 16)

	makeLabel(host, 5, "What RESETS", Theme.Font.Header, Theme.Semantic.Danger, 18)
	makeLabel(host, 6, formatList(PrestigeConfig.RESET), Theme.Font.Body, Theme.Text.Primary, 16)

	local nextLines = {
		("Next income bonus: +%d%% (total x%.2f)"):format(info.NextBonusPercent or 0, info.NextIncomeMultiplier or 1),
		("One-time reward: %d Abyssal Shards"):format(info.NextShardReward or 0),
	}
	if info.NextTitle then
		table.insert(nextLines, ("Next title: \"%s\" (at Resurface #%d)"):format(info.NextTitle, info.NextTitleAtAscend or 0))
	end
	makeLabel(host, 7, "Your next Resurface", Theme.Font.Header, Theme.Neon.Yellow, 18)
	makeLabel(host, 8, formatList(nextLines), Theme.Font.Body, Theme.Text.Primary, 16)

	local statusColor = if info.Eligible then Theme.Neon.ToxicGreen else Theme.Semantic.Warning
	local statusText = if info.Eligible
		then "You are ready to resurface!"
		else blockText(info.BlockReason)
	if info.BlockReason == "NotEligible" then
		statusText ..= ("  (Level %d, deepest zone %d of %d)"):format(info.Level or 1, info.DeepestZone or 1, info.RequiredZone or 4)
	end
	makeLabel(host, 9, statusText, Theme.Font.BodyBold, statusColor, 16)

	makeLabel(
		host,
		10,
		"Tip: running Brood Pool eggs are lost when you resurface. Collect them first!",
		Theme.Font.Body,
		Theme.Text.Secondary,
		14
	)

	if resurfaceButton then
		resurfaceButton:SetDisabled(not info.Eligible or requestPending)
	end
end

local function refreshInfo()
	task.spawn(function()
		local ok, info = pcall(function()
			return PrestigeRemotes.GetPrestigeInfo:InvokeServer()
		end)
		if ok and type(info) == "table" then
			currentInfo = info
			rebuildContent(info)
		else
			warn("[PrestigeUIController] Could not load prestige info.")
		end
	end)
end

-- // Two-step confirmation ----------------------------------------------------------

local function startResurfaceFlow()
	if requestPending then
		return
	end
	local info = currentInfo
	local nextMultiplier = if info then (info.NextIncomeMultiplier or 1) else 1

	ConfirmDialog.Show({
		Title = "Resurface? (1 of 2)",
		Message = ("You will go back to level 1 and the Sun Zone. Your coins, buildings and zone progress are reset. You keep your creatures, shards, codex and cosmetics, and your income bonus becomes x%.2f."):format(nextMultiplier),
		ConfirmText = "Continue",
		CancelText = "Stay here",
		Danger = true,
		OnConfirm = function()
			requestPending = true
			task.spawn(function()
				local ok, result = pcall(function()
					return PrestigeRemotes.ArmResurface:InvokeServer()
				end)
				if not ok or type(result) ~= "table" or not result.Success then
					requestPending = false
					Toast.Show({ Text = blockText(if ok and type(result) == "table" then result.Reason else nil), Type = "Warning", Duration = 4 })
					refreshInfo()
					return
				end

				ConfirmDialog.Show({
					Title = "Are you really sure? (2 of 2)",
					Message = "This cannot be undone. All your buildings and coins will be gone. Press Resurface now to start over with your new bonus.",
					ConfirmText = "Resurface now",
					CancelText = "No, go back",
					Danger = true,
					OnConfirm = function()
						PrestigeRemotes.RequestResurface:FireServer()
					end,
					OnCancel = function()
						requestPending = false
						refreshInfo()
					end,
				})
			end)
		end,
		OnCancel = function() end,
	})
end

local function buildPanel()
	if panel then
		return
	end
	panel = Panel.new({
		Title = "Resurface",
		Closable = true,
		CenteredSize = UDim2.fromOffset(560, 660),
	})

	local scrollFrame = Instance.new("ScrollingFrame")
	scrollFrame.Name = "Scroller"
	scrollFrame.BackgroundTransparency = 1
	scrollFrame.BorderSizePixel = 0
	scrollFrame.Size = UDim2.new(1, 0, 1, -64)
	scrollFrame.CanvasSize = UDim2.new()
	scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scrollFrame.ScrollBarThickness = 6
	scrollFrame.ScrollBarImageColor3 = Theme.Neon.Cyan
	scrollFrame.Parent = panel.Content
	scroller = scrollFrame

	local list = Instance.new("UIListLayout")
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Padding = UDim.new(0, 8)
	list.Parent = scrollFrame

	resurfaceButton = Button.new({
		Parent = panel.Content,
		Text = "Resurface",
		Variant = "Danger",
		Important = true,
		Size = UDim2.new(1, 0, 0, 52),
		Disabled = true,
	})
	resurfaceButton.Instance.AnchorPoint = Vector2.new(0, 1)
	resurfaceButton.Instance.Position = UDim2.new(0, 0, 1, 0)
	resurfaceButton.Clicked:Connect(startResurfaceFlow)
end

local function openPanel()
	buildPanel()
	panel:Open()
	refreshInfo()
end

local bridgeConnection = openPrestigeEvent.Event:Connect(openPanel)

-- // Server result ---------------------------------------------------------------------

local resultConnection = PrestigeRemotes.ResurfaceResult.OnClientEvent:Connect(function(result)
	requestPending = false
	if type(result) ~= "table" then
		return
	end

	if result.Success then
		ScreenFX.BigMoment(Theme.Neon.Cyan)
		local text = ("You resurfaced! Income bonus is now x%.2f. +%d Abyssal Shards."):format(
			result.IncomeMultiplier or 1,
			result.ShardsGranted or 0
		)
		if type(result.TitleGranted) == "string" then
			text ..= (" New title: %s!"):format(result.TitleGranted)
		end
		Toast.Show({ Text = text, Type = "Success", Duration = 6 })
		prestigeCompletedEvent:Fire()
		if panel then
			panel:Close()
		end
	else
		Toast.Show({ Text = blockText(result.Reason), Type = "Warning", Duration = 4 })
		if panel then
			refreshInfo()
		end
	end
end)

-- // Cleanup ---------------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= localPlayer then
		return
	end
	bridgeConnection:Disconnect()
	resultConnection:Disconnect()
	if resurfaceButton then
		resurfaceButton:Destroy()
	end
	if panel then
		panel:Destroy()
	end
end)
