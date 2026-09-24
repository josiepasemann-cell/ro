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
			   einfaches "Während du weg warst: +X Tide Coins"-Panel mit
			   Schließen-Button, das sich zusätzlich nach einigen Sekunden
			   automatisch ausblendet.

		WICHTIG: Dieses Skript erzeugt/verändert NIEMALS selbst einen
		Währungswert - es zeigt ausschließlich an, was der Server in der
		jeweiligen Event-Payload bereits als fertiges Ergebnis mitschickt
		(kein Client-Trust: der Server bleibt einzige Autorität über Tide
		Coins, siehe PlayerDataService/IdleIncomeService).

	Rojo-Einhängepunkt:
		src/client/IdleIncomeClient.client.lua ->
		StarterPlayer.StarterPlayerScripts.IdleIncomeClient
		(".client.lua"-Suffix signalisiert Rojo, hieraus ein `LocalScript`
		zu machen.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local IdleIncomeRemotes = require(ReplicatedStorage:WaitForChild("IdleIncomeRemotes"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- // Popup-Layer für "+X Tide Coins" ------------------------------------------

local popupGui = Instance.new("ScreenGui")
popupGui.Name = "IdleIncomePopups"
popupGui.ResetOnSpawn = false
popupGui.IgnoreGuiInset = true
popupGui.Parent = playerGui

local popupAnchor = Instance.new("Frame")
popupAnchor.Name = "PopupAnchor"
popupAnchor.AnchorPoint = Vector2.new(0.5, 1)
popupAnchor.Position = UDim2.new(0.5, 0, 1, -90)
popupAnchor.Size = UDim2.new(0, 10, 0, 10)
popupAnchor.BackgroundTransparency = 1
popupAnchor.Parent = popupGui

local POPUP_RISE_STUDS = 55 -- Pixel, die das Popup während der Animation nach oben wandert
local POPUP_DURATION_SECONDS = 1.4

local function showIncomePopup(amount: number)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.new(0.5, 0, 0, 0)
	label.Size = UDim2.new(0, 220, 0, 32)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 22
	label.TextColor3 = Color3.fromRGB(120, 235, 210)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Color3.fromRGB(5, 20, 20)
	label.Text = ("+%d Tide Coins"):format(amount)
	label.Parent = popupAnchor

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

-- // Offline-Progress-Zusammenfassung beim Login ------------------------------

local offlineGui = Instance.new("ScreenGui")
offlineGui.Name = "OfflineProgressSummary"
offlineGui.ResetOnSpawn = false
offlineGui.IgnoreGuiInset = true
offlineGui.Enabled = false
offlineGui.Parent = playerGui

local panel = Instance.new("Frame")
panel.Name = "SummaryPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.Size = UDim2.new(0, 420, 0, 170)
panel.BackgroundColor3 = Color3.fromRGB(8, 24, 32)
panel.BackgroundTransparency = 0.08
panel.BorderSizePixel = 0
panel.Parent = offlineGui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 12)
corner.Parent = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "TitleLabel"
titleLabel.BackgroundTransparency = 1
titleLabel.Position = UDim2.new(0, 20, 0, 16)
titleLabel.Size = UDim2.new(1, -40, 0, 30)
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 22
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextColor3 = Color3.fromRGB(210, 245, 250)
titleLabel.Text = "Während du weg warst ..."
titleLabel.Parent = panel

local amountLabel = Instance.new("TextLabel")
amountLabel.Name = "AmountLabel"
amountLabel.BackgroundTransparency = 1
amountLabel.Position = UDim2.new(0, 20, 0, 56)
amountLabel.Size = UDim2.new(1, -40, 0, 40)
amountLabel.Font = Enum.Font.GothamBold
amountLabel.TextSize = 28
amountLabel.TextXAlignment = Enum.TextXAlignment.Left
amountLabel.TextColor3 = Color3.fromRGB(120, 235, 210)
amountLabel.Text = "+0 Tide Coins"
amountLabel.Parent = panel

local detailLabel = Instance.new("TextLabel")
detailLabel.Name = "DetailLabel"
detailLabel.BackgroundTransparency = 1
detailLabel.Position = UDim2.new(0, 20, 0, 100)
detailLabel.Size = UDim2.new(1, -40, 0, 24)
detailLabel.Font = Enum.Font.Gotham
detailLabel.TextSize = 14
detailLabel.TextXAlignment = Enum.TextXAlignment.Left
detailLabel.TextColor3 = Color3.fromRGB(170, 200, 205)
detailLabel.Text = ""
detailLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.AnchorPoint = Vector2.new(0.5, 1)
closeButton.Position = UDim2.new(0.5, 0, 1, -16)
closeButton.Size = UDim2.new(0, 140, 0, 34)
closeButton.BackgroundColor3 = Color3.fromRGB(30, 90, 95)
closeButton.Font = Enum.Font.GothamMedium
closeButton.TextSize = 16
closeButton.TextColor3 = Color3.fromRGB(230, 250, 250)
closeButton.Text = "Danke!"
closeButton.Parent = panel

local closeButtonCorner = Instance.new("UICorner")
closeButtonCorner.CornerRadius = UDim.new(0, 8)
closeButtonCorner.Parent = closeButton

local AUTO_HIDE_SECONDS = 8
local hideConnection: thread? = nil

local function hideOfflinePanel()
	offlineGui.Enabled = false
end

local function formatDuration(totalSeconds: number): string
	local hours = math.floor(totalSeconds / 3600)
	local minutes = math.floor((totalSeconds % 3600) / 60)
	if hours > 0 then
		return ("%dh %dmin"):format(hours, minutes)
	end
	return ("%dmin"):format(math.max(minutes, 1))
end

closeButton.MouseButton1Click:Connect(hideOfflinePanel)

IdleIncomeRemotes.OfflineProgressSummary.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end

	local amount = tonumber(payload.Amount) or 0
	local cappedSeconds = tonumber(payload.CappedSeconds) or 0
	local wasCapped = payload.WasCapped == true

	amountLabel.Text = ("+%d Tide Coins"):format(amount)
	detailLabel.Text = if wasCapped
		then ("Abwesenheit: %s (auf max. 4h gedeckelt)"):format(formatDuration(cappedSeconds))
		else ("Abwesenheit: %s"):format(formatDuration(cappedSeconds))

	offlineGui.Enabled = true

	if hideConnection then
		task.cancel(hideConnection)
	end
	hideConnection = task.delay(AUTO_HIDE_SECONDS, hideOfflinePanel)
end)
