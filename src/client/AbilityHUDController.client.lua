--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Script: AbilityHUDController (LocalScript)
	Responsibility:
		Small, persistent HUD strip for the purchasable abilities/boosts
		system (AbilityService.lua): a live Tidal Surge countdown (only shown
		while active), a Depth Charge button with its charge count (only
		visible/enabled during an active raid on the player's own plot), and
		a small "+Spore Shower" quick-buy button. Also shows the
		AbilityRemotes.SporeShowerToast message as a toast.

		WICHTIG: dieses Skript berechnet NIEMALS selbst, ob ein Effekt aktiv
		ist oder ob ein Depth Charge tatsächlich feuern darf - es zeigt
		ausschließlich an, was der Server über AbilityRemotes.GetAbilityStatus
		(initialer Sync) / AbilityStatusChanged (Live-Push) bereits fertig
		berechnet mitschickt, identisches Prinzip wie HUDController.
		RequestDepthCharge ist nur eine Absichtserklärung - der Server
		validiert Ladung/Cooldown/aktiven Raid komplett neu (siehe
		AbilityService.RequestDepthCharge).

		LAYOUT (no overlap with the existing HUD/raid HUD/menu bar/toasts):
			- Phone (portrait/landscape): docks directly BELOW
			  RaidUIController's status bar (which itself docks below
			  HUDController's bar, see HUDController Kopfkommentar) - full
			  width, AutomaticSize height so it collapses to just the
			  quick-buy row when nothing else is active. Sits well above the
			  MainMenuController bottom bar and the bottom-centered Toast
			  stack.
			- Tablet/PC/Console: docks top-RIGHT (HUDController is top-left,
			  RaidUIController is top-center - this is the one remaining
			  free top corner). AutomaticSize height, fixed width.

	Rojo mount point:
		src/client/AbilityHUDController.client.lua ->
		StarterPlayer.StarterPlayerScripts.AbilityHUDController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AbilityRemotes = require(ReplicatedStorage:WaitForChild("AbilityRemotes"))
local RaidRemotes = require(ReplicatedStorage:WaitForChild("RaidRemotes"))
local ShopRemotes = require(ReplicatedStorage:WaitForChild("ShopRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Button = UIKit.Button
local Toast = UIKit.Toast
local ScreenFX = UIKit.ScreenFX

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local DEPTH_CHARGE_COOLDOWN_SECONDS = 10 -- purely a LOCAL visual disable, mirrors AbilityConfig.DepthCharge.CooldownSeconds - the server is the actual authority, see Kopfkommentar

-- // Local, purely cosmetic display state (server stays authoritative) --------

type AbilityHUDState = {
	TidalSurgeActiveUntil: number?,
	DepthChargeCount: number,
	InRaidOnOwnPlot: boolean,
}

local state: AbilityHUDState = {
	TidalSurgeActiveUntil = nil,
	DepthChargeCount = 0,
	InRaidOnOwnPlot = false,
}

-- // Root ScreenGui --------------------------------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "AbilityHUD"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 16 -- just above MainHUD (15), consistent with the rest of the HUD family
Device.ApplySafeArea(screenGui)
screenGui.Parent = playerGui

local uiScale = Instance.new("UIScale")
uiScale.Parent = screenGui
local unbindScale = Device.BindUIScale(uiScale)

local panel = Instance.new("Frame")
panel.Name = "AbilityPanel"
panel.BackgroundColor3 = Theme.Background.Panel
panel.BackgroundTransparency = 0.15
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Parent = screenGui
Theme.ApplyCorner(panel, UDim.new(0, 12))
local panelStroke = Theme.ApplyStroke(panel, Theme.Neon.Magenta, 1.5)
panelStroke.Transparency = 0.3

local listLayout = Instance.new("UIListLayout")
listLayout.FillDirection = Enum.FillDirection.Vertical
listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 6)
listLayout.Parent = panel

local listPadding = Instance.new("UIPadding")
listPadding.PaddingTop = UDim.new(0, 8)
listPadding.PaddingBottom = UDim.new(0, 8)
listPadding.PaddingLeft = UDim.new(0, 8)
listPadding.PaddingRight = UDim.new(0, 8)
listPadding.Parent = panel

local function applyPanelLayout()
	if Device.ShouldUseFullscreenPanels() then
		-- Phone: below RaidUIController's status bar (y=104, height 52 ->
		-- bottom edge 156, see RaidUIController.applyStatusBarLayout).
		panel.AnchorPoint = Vector2.new(0.5, 0)
		panel.Position = UDim2.new(0.5, 0, 0, 164)
		panel.Size = UDim2.new(1, -16, 0, 0)
	else
		-- Tablet/PC/Console: top-right (HUDController = top-left,
		-- RaidUIController = top-center, see their own Kopfkommentare).
		panel.AnchorPoint = Vector2.new(1, 0)
		panel.Position = UDim2.new(1, -16, 0, 16)
		panel.Size = UDim2.new(0, 230, 0, 0)
	end
end
applyPanelLayout()
local deviceConnection = Device.Changed:Connect(applyPanelLayout)

local function makeLabel(rowLayoutOrder: number, minSize: number, maxSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, 0, 0, 22)
	label.Font = Theme.Font.BodyBold
	label.TextColor3 = Theme.Text.Primary
	label.TextScaled = true
	label.LayoutOrder = rowLayoutOrder
	label.Visible = false
	label.Parent = panel
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = minSize
	constraint.MaxTextSize = maxSize
	constraint.Parent = label
	return label
end

-- // Row 1: Tidal Surge countdown (only visible while active) -----------------

local tidalSurgeLabel = makeLabel(1, 11, 16)
tidalSurgeLabel.TextColor3 = Theme.Neon.Cyan

local function formatCountdown(totalSeconds: number): string
	local clamped = math.max(0, math.floor(totalSeconds))
	local hours = math.floor(clamped / 3600)
	local minutes = math.floor((clamped % 3600) / 60)
	local seconds = clamped % 60
	if hours > 0 then
		return string.format("%d:%02d:%02d", hours, minutes, seconds)
	end
	return string.format("%d:%02d", minutes, seconds)
end

local function refreshTidalSurgeLabel()
	local activeUntil = state.TidalSurgeActiveUntil
	if type(activeUntil) ~= "number" or activeUntil <= os.time() then
		tidalSurgeLabel.Visible = false
		return
	end
	tidalSurgeLabel.Visible = true
	tidalSurgeLabel.Text = ("🌊 Tidal Surge: %s"):format(formatCountdown(activeUntil - os.time()))
end

-- // Row 2: Depth Charge button (only visible during a raid on your OWN plot) --

local depthChargeRow = Instance.new("Frame")
depthChargeRow.Name = "DepthChargeRow"
depthChargeRow.BackgroundTransparency = 1
depthChargeRow.Size = UDim2.new(1, 0, 0, 40)
depthChargeRow.LayoutOrder = 2
depthChargeRow.Visible = false
depthChargeRow.Parent = panel

local depthChargeButton = Button.new({
	Parent = depthChargeRow,
	Text = "Depth Charge (0)",
	Variant = "Danger",
	Size = UDim2.new(1, 0, 1, 0),
})

local depthChargeCooldownUntil = 0 -- os.clock(), purely local visual cooldown

local function refreshDepthChargeButton()
	depthChargeRow.Visible = state.InRaidOnOwnPlot
	if not state.InRaidOnOwnPlot then
		return
	end
	depthChargeButton:SetText(("Depth Charge (%d)"):format(state.DepthChargeCount))
	local onCooldown = os.clock() < depthChargeCooldownUntil
	depthChargeButton:SetDisabled(state.DepthChargeCount <= 0 or onCooldown)
end

depthChargeButton.Clicked:Connect(function()
	if state.DepthChargeCount <= 0 or os.clock() < depthChargeCooldownUntil then
		return
	end
	-- Optimistic local cooldown so the button can't be spammed while waiting
	-- for the server round-trip - the server enforces the real 10s cooldown
	-- independently (see AbilityService.RequestDepthCharge), this is purely
	-- a responsive-feeling UI guard, not the source of truth.
	depthChargeCooldownUntil = os.clock() + DEPTH_CHARGE_COOLDOWN_SECONDS
	refreshDepthChargeButton()
	AbilityRemotes.RequestDepthCharge:FireServer()
end)

-- // Row 3: "+Spore Shower" quick-buy (optional convenience, Auftrag: "nice") --

local quickBuyRow = Instance.new("Frame")
quickBuyRow.Name = "QuickBuyRow"
quickBuyRow.BackgroundTransparency = 1
quickBuyRow.Size = UDim2.new(1, 0, 0, 32)
quickBuyRow.LayoutOrder = 3
quickBuyRow.Parent = panel

local quickBuySporeShowerButton = Button.new({
	Parent = quickBuyRow,
	Text = "+ Spore Shower",
	Variant = "Secondary",
	Size = UDim2.new(1, 0, 1, 0),
})
quickBuySporeShowerButton.Clicked:Connect(function()
	ShopRemotes.RequestPromptDevProductPurchase:FireServer("SporeShower", nil)
end)

-- // Countdown-Loop (nur während Tidal Surge aktiv ist, günstig) -------------

local countdownThread: thread? = nil
local function ensureCountdownLoop()
	if countdownThread then
		return
	end
	countdownThread = task.spawn(function()
		while type(state.TidalSurgeActiveUntil) == "number" and state.TidalSurgeActiveUntil > os.time() do
			refreshTidalSurgeLabel()
			task.wait(1)
		end
		refreshTidalSurgeLabel()
		countdownThread = nil
	end)
end

-- // Serverzustand anwenden ----------------------------------------------------

local function applyStatus(payload: { [string]: any })
	if type(payload) ~= "table" then
		return
	end
	state.TidalSurgeActiveUntil = payload.TidalSurgeActiveUntil
	if type(payload.DepthChargeCount) == "number" then
		state.DepthChargeCount = payload.DepthChargeCount
	end
	if type(payload.InRaidOnOwnPlot) == "boolean" then
		state.InRaidOnOwnPlot = payload.InRaidOnOwnPlot
	end

	refreshTidalSurgeLabel()
	refreshDepthChargeButton()
	ensureCountdownLoop()
end

-- // Remote-Verdrahtung --------------------------------------------------------

AbilityRemotes.AbilityStatusChanged.OnClientEvent:Connect(applyStatus)

AbilityRemotes.DepthChargeFired.OnClientEvent:Connect(function(payload: { [string]: any })
	if type(payload) ~= "table" then
		return
	end
	if payload.Success then
		ScreenFX.BigMoment(Theme.Neon.Magenta)
		local enemiesHit = payload.EnemiesHit
		Toast.Show({
			Text = if type(enemiesHit) == "number" then ("Depth Charge! Hit %d enemies."):format(enemiesHit) else "Depth Charge fired!",
			Type = "Success",
			Duration = 3,
		})
	else
		local reason = payload.Reason
		local message = "Depth Charge failed."
		if reason == "NoCharges" then
			message = "No Depth Charges left - buy more in the shop!"
		elseif reason == "OnCooldown" then
			message = "Depth Charge is still on cooldown."
		elseif reason == "NoActiveRaid" then
			message = "No active raid on your plot right now."
		elseif reason == "DataNotLoaded" then
			message = "Your game data is still loading - please wait a moment."
		end
		Toast.Show({ Text = message, Type = "Warning", Duration = 3 })
	end
end)

AbilityRemotes.SporeShowerToast.OnClientEvent:Connect(function(payload: { [string]: any })
	if type(payload) == "table" and type(payload.Message) == "string" then
		Toast.Show({ Text = payload.Message, Type = "Success", Duration = 3.5 })
	end
end)

-- Immediate, responsive raid-state toggling (no need to wait for the next
-- AbilityStatusChanged push) - RaidStarted/RaidResult are only ever fired to
-- the raided plot's OWNER (see RaidRemotes Kopfkommentar), so this is always
-- "your own plot" already.
RaidRemotes.RaidStarted.OnClientEvent:Connect(function()
	state.InRaidOnOwnPlot = true
	refreshDepthChargeButton()
end)
RaidRemotes.RaidResult.OnClientEvent:Connect(function()
	state.InRaidOnOwnPlot = false
	refreshDepthChargeButton()
end)

-- // Initialer Sync -----------------------------------------------------------

task.spawn(function()
	local ok, initialStatus = pcall(function()
		return AbilityRemotes.GetAbilityStatus:InvokeServer()
	end)
	if ok and type(initialStatus) == "table" then
		applyStatus(initialStatus)
	else
		warn("[AbilityHUDController] Initial ability status sync failed.")
	end
end)

-- // Aufräumen ------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	deviceConnection:Disconnect()
	unbindScale()
	if countdownThread then
		task.cancel(countdownThread)
		countdownThread = nil
	end
	depthChargeButton:Destroy()
	quickBuySporeShowerButton:Destroy()
	screenGui:Destroy()
end)
