--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: IdleIncomeClient (LocalScript)
	Zuständigkeit:
		Reines Anzeige-Feedback für das Idle-Einkommen-/Produktionssystem:
			1. Bei jeder Online-Tick-Gutschrift (IdleIncomeRemotes.
			   IncomeGranted) ein kurzes "+X Tide Coins"-Popup, das
			   hochschwebt und ausblendet.
			2. Beim Login, falls seit dem letzten Logout spürbar Zeit
			   vergangen ist (IdleIncomeRemotes.OfflineProgressSummary), ein
			   UIKit.Panel ("Während du weg warst ...") mit UIKit.CountUp-
			   Hochzähl-Animation für den Betrag und einem UIKit.Button
			   zum Schließen, das sich zusätzlich nach einigen Sekunden
			   automatisch ausblendet.

		WICHTIG: Dieses Skript erzeugt/verändert NIEMALS selbst einen
		Währungswert - es zeigt ausschließlich an, was der Server in der
		jeweiligen Event-Payload bereits als fertiges Ergebnis mitschickt
		(kein Client-Trust: der Server bleibt einzige Autorität über Tide
		Coins, siehe PlayerDataService/IdleIncomeService).

		Layout: Popups erscheinen über dem Anker unten-mittig, knapp über
		der MainMenuController-Menüleiste (siehe dort für das
		Gesamt-Layout); das Offline-Panel ist ein zentriertes/fullscreen
		UIKit.Panel wie jedes andere Menü.

	Rojo-Einhängepunkt:
		src/client/IdleIncomeClient.client.lua ->
		StarterPlayer.StarterPlayerScripts.IdleIncomeClient
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local IdleIncomeRemotes = require(ReplicatedStorage:WaitForChild("IdleIncomeRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Panel = UIKit.Panel
local Button = UIKit.Button
local CountUp = UIKit.CountUp
local ScreenFX = UIKit.ScreenFX

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- // Popup-Layer für "+X Tide Coins" ------------------------------------------

local popupGui = Instance.new("ScreenGui")
popupGui.Name = "IdleIncomePopups"
popupGui.ResetOnSpawn = false
popupGui.IgnoreGuiInset = false
popupGui.DisplayOrder = 18
Device.ApplySafeArea(popupGui)
popupGui.Parent = playerGui

local popupUiScale = Instance.new("UIScale")
popupUiScale.Parent = popupGui
local unbindPopupScale = Device.BindUIScale(popupUiScale)

local popupAnchor = Instance.new("Frame")
popupAnchor.Name = "PopupAnchor"
popupAnchor.AnchorPoint = Vector2.new(0.5, 1)
popupAnchor.Size = UDim2.new(0, 10, 0, 10)
popupAnchor.BackgroundTransparency = 1
popupAnchor.Parent = popupGui

-- Knapp über der unten angedockten MainMenuController-Leiste positionieren,
-- damit sich Popups und Menüleiste auf keinem Gerät überlappen.
local function applyPopupAnchorPosition()
	if Device.ShouldUseFullscreenPanels() then
		popupAnchor.Position = UDim2.new(0.5, 0, 1, -108) -- über der ~84px hohen Phone-Menüleiste
	else
		popupAnchor.Position = UDim2.new(0.5, 0, 1, -100) -- über der ~68px hohen Desktop/Konsolen-Menüleiste
	end
end
applyPopupAnchorPosition()
local popupDeviceConnection = Device.Changed:Connect(applyPopupAnchorPosition)

local POPUP_RISE_STUDS = 55 -- Pixel, die das Popup während der Animation nach oben wandert
local POPUP_DURATION_SECONDS = 1.4

local function showIncomePopup(amount: number)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0, 0)
	label.Size = UDim2.new(0, 220, 0, 32)
	label.BackgroundTransparency = 1
	label.Font = Theme.Font.BodyBold
	label.TextScaled = true
	label.TextColor3 = Theme.Neon.ToxicGreen
	label.Text = ("+%d Tide Coins"):format(amount)
	label.Parent = popupAnchor
	Theme.ApplyStroke(label, Theme.Text.Stroke, 1.25)
	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 14
	constraint.MaxTextSize = 22
	constraint.Parent = label

	local tweenUp = TweenService:Create(
		label,
		TweenInfo.new(POPUP_DURATION_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Position = UDim2.new(0.5, 0, 0, -POPUP_RISE_STUDS), TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	tweenUp:Play()
	tweenUp.Completed:Once(function()
		label:Destroy()
	end)
end

IdleIncomeRemotes.IncomeGranted.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" or type(payload.Amount) ~= "number" or payload.Amount <= 0 then
		return
	end
	showIncomePopup(payload.Amount)
end)

-- // Offline-Progress-Zusammenfassung beim Login (UIKit.Panel) ---------------

local offlinePanel = Panel.new({
	Title = "While you were away ...",
	Closable = true,
	CenteredSize = UDim2.fromOffset(440, 240),
})

local amountLabel = Instance.new("TextLabel")
amountLabel.Name = "AmountLabel"
amountLabel.BackgroundTransparency = 1
amountLabel.Size = UDim2.new(1, 0, 0, 48)
amountLabel.Font = Theme.Font.Header
amountLabel.TextScaled = true
amountLabel.TextXAlignment = Enum.TextXAlignment.Left
amountLabel.TextColor3 = Theme.Neon.ToxicGreen
amountLabel.Text = "+0"
amountLabel.Parent = offlinePanel.Content
local amountConstraint = Instance.new("UITextSizeConstraint")
amountConstraint.MinTextSize = 20
amountConstraint.MaxTextSize = 32
amountConstraint.Parent = amountLabel

local detailLabel = Instance.new("TextLabel")
detailLabel.Name = "DetailLabel"
detailLabel.BackgroundTransparency = 1
detailLabel.Position = UDim2.new(0, 0, 0, 52)
detailLabel.Size = UDim2.new(1, 0, 0, 28)
detailLabel.Font = Theme.Font.Body
detailLabel.TextScaled = true
detailLabel.TextXAlignment = Enum.TextXAlignment.Left
detailLabel.TextColor3 = Theme.Text.Secondary
detailLabel.Text = ""
detailLabel.Parent = offlinePanel.Content
local detailConstraint = Instance.new("UITextSizeConstraint")
detailConstraint.MinTextSize = 12
detailConstraint.MaxTextSize = 16
detailConstraint.Parent = detailLabel

local thanksButton = Button.new({
	Parent = offlinePanel.Content,
	Text = "Thanks!",
	Variant = "Primary",
	Important = true,
	Size = UDim2.new(1, 0, 0, 48),
})
thanksButton.Instance.Position = UDim2.new(0, 0, 1, -48)
thanksButton.Clicked:Connect(function()
	offlinePanel:Close()
end)

local AUTO_HIDE_SECONDS = 8
local hideThread: thread? = nil

local function formatDuration(totalSeconds: number): string
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	if hours > 0 then
		return ("%dh %dmin"):format(hours, minutes)
	end
	return ("%dmin"):format(math.max(minutes, 1))
end

IdleIncomeRemotes.OfflineProgressSummary.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	local amount = tonumber(payload.Amount) or 0
	local cappedSeconds = tonumber(payload.CappedSeconds) or 0
	local wasCapped = payload.WasCapped == true

	amountLabel.Text = "+0 Tide Coins"
	CountUp.Animate(amountLabel, 0, amount, 1.0, function(value)
		return ("+%s Tide Coins"):format(CountUp.DefaultFormat(value))
	end)
	detailLabel.Text = if wasCapped
		then ("Time away: %s (capped at max. 4h)"):format(formatDuration(cappedSeconds))
		else ("Time away: %s"):format(formatDuration(cappedSeconds))

	offlinePanel:Open()
	ScreenFX.Flash({ Color = Theme.Neon.Cyan, Duration = 0.4, MaxTransparency = 0.35 })

	if hideThread then
		task.cancel(hideThread)
	end
	hideThread = task.delay(AUTO_HIDE_SECONDS, function()
		hideThread = nil
		offlinePanel:Close()
	end)
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	popupDeviceConnection:Disconnect()
	unbindPopupScale()
	if hideThread then
		task.cancel(hideThread)
	end
	offlinePanel:Destroy()
	popupGui:Destroy()
end)
