--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: UIKitDemo.client.lua
	Zuständigkeit:
		Zeigt alle UIKit-Bausteine (Button-Varianten, Panel+Tabs, Toasts,
		CountUp, ProgressBar, RarityBadges, ConfirmDialog, ScreenFX) in
		einem einzigen Demo-Panel. Rein zu Abnahme-/Referenzzwecken für den
		nächsten Agenten, der bestehende Menüs auf UIKit umstellt.

		STANDARDMÄSSIG AUS: Läuft nur, wenn das Attribut
		"UIKitDemoEnabled" auf Workspace (oder alternativ auf diesem
		Script selbst) auf `true` gesetzt ist - sonst beendet sich das
		Skript sofort und stört das Live-Spiel nicht.

		Aktivieren zu Testzwecken (z. B. im Command Bar von Studio):
			workspace:SetAttribute("UIKitDemoEnabled", true)

	Rojo-Einhängepunkt:
		src/client/UIKitDemo.client.lua -> StarterPlayer.StarterPlayerScripts
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local function isDemoEnabled(): boolean
	local fromWorkspace = Workspace:GetAttribute("UIKitDemoEnabled")
	if fromWorkspace == true then
		return true
	end
	local fromScript = script:GetAttribute("UIKitDemoEnabled")
	if fromScript == true then
		return true
	end
	return false
end

if not isDemoEnabled() then
	return
end

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local panel = UIKit.Panel.new({
	Title = "UIKit Demo - Abyssara",
	CenteredSize = UDim2.fromOffset(680, 520),
})

local tabs = UIKit.Tabs.new({
	Parent = panel.Content,
	Tabs = {
		{ Id = "Buttons", Label = "Buttons" },
		{ Id = "Widgets", Label = "Widgets" },
		{ Id = "Rarity", Label = "Rarity" },
		{ Id = "FX", Label = "Screen FX" },
	},
	DefaultTabId = "Buttons",
})

-- // Tab: Buttons -----------------------------------------------------------
do
	local content = tabs:GetContentFrame("Buttons")


	local variants = { "Primary", "Secondary", "Success", "Danger", "Ghost" }
	for index, variant in variants do
		local button = UIKit.Button.new({
			Parent = content,
			Text = variant .. " Button",
			Variant = variant :: any,
			LayoutOrder = index,
			Size = UDim2.new(1, 0, 0, 48),
		})
		button.Clicked:Connect(function()
			UIKit.Toast.Show({ Text = variant .. " Button clicked!", Type = "Info" })
		end)
	end

	local importantButton = UIKit.Button.new({
		Parent = content,
		Text = "Buy (Idle Pulse)",
		Variant = "Success",
		Important = true,
		LayoutOrder = 10,
		Size = UDim2.new(1, 0, 0, 52),
	})
	importantButton.Clicked:Connect(function()
		UIKit.Toast.Show({ Text = "Purchase confirmed!", Type = "Success" })
	end)

	local disabledButton = UIKit.Button.new({
		Parent = content,
		Text = "Disabled Button",
		Variant = "Primary",
		Disabled = true,
		LayoutOrder = 11,
		Size = UDim2.new(1, 0, 0, 48),
	})
	disabledButton.Clicked:Connect(function() end)

	local confirmButton = UIKit.Button.new({
		Parent = content,
		Text = "Open Confirmation Dialog",
		Variant = "Danger",
		LayoutOrder = 12,
		Size = UDim2.new(1, 0, 0, 48),
	})
	confirmButton.Clicked:Connect(function()
		UIKit.ConfirmDialog.Show({
			Title = "Really sell?",
			Message = "This creature will be permanently removed from your inventory. Continue?",
			Danger = true,
			ConfirmText = "Sell",
			CancelText = "Cancel",
			OnConfirm = function()
				UIKit.Toast.Show({ Text = "Sold!", Type = "Warning" })
			end,
			OnCancel = function()
				UIKit.Toast.Show({ Text = "Cancelled.", Type = "Info" })
			end,
		})
	end)
end

-- // Tab: Widgets ------------------------------------------------------------
do
	local content = tabs:GetContentFrame("Widgets")

	local currencyLabel = Instance.new("TextLabel")
	currencyLabel.Size = UDim2.new(1, 0, 0, 40)
	currencyLabel.BackgroundTransparency = 1
	currencyLabel.Font = UIKit.Theme.Font.Header
	currencyLabel.TextColor3 = UIKit.Theme.Neon.Yellow
	currencyLabel.TextScaled = true
	currencyLabel.LayoutOrder = 1
	currencyLabel.Parent = content
	UIKit.CountUp.Animate(currencyLabel, 0, 12450, 1.4)

	local progressRow = Instance.new("Frame")
	progressRow.BackgroundTransparency = 1
	progressRow.Size = UDim2.new(1, 0, 0, 20)
	progressRow.LayoutOrder = 2
	progressRow.Parent = content

	local progress = UIKit.ProgressBar.new({
		Parent = progressRow,
		Size = UDim2.new(1, 0, 0, 20),
	})
	progress:SetProgress(0.65)

	local progressButton = UIKit.Button.new({
		Parent = content,
		Text = "Randomize Progress",
		Variant = "Secondary",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 44),
	})
	progressButton.Clicked:Connect(function()
		progress:SetProgress(math.random())
	end)

	local toastButton = UIKit.Button.new({
		Parent = content,
		Text = "Show Toast",
		Variant = "Primary",
		LayoutOrder = 4,
		Size = UDim2.new(1, 0, 0, 44),
	})
	local toastTypes = { "Info", "Success", "Warning", "Error" }
	local toastIndex = 0
	toastButton.Clicked:Connect(function()
		toastIndex = (toastIndex % #toastTypes) + 1
		local toastType = toastTypes[toastIndex]
		UIKit.Toast.Show({ Text = "Example toast (" .. toastType .. ")", Type = toastType :: any })
	end)
end

-- // Tab: Rarity --------------------------------------------------------
do
	local content = tabs:GetContentFrame("Rarity")

	for index, rarity in UIKit.Theme.RarityOrder do
		local badge = UIKit.RarityBadge.new({
			Parent = content,
			Rarity = rarity,
			Size = UDim2.new(1, 0, 0, 32),
		})
		badge.Instance.LayoutOrder = index
	end
end

-- // Tab: Screen-FX -----------------------------------------------------
do
	local content = tabs:GetContentFrame("FX")

	local flashButton = UIKit.Button.new({
		Parent = content,
		Text = "Flash (Level Up)",
		Variant = "Success",
		LayoutOrder = 1,
		Size = UDim2.new(1, 0, 0, 48),
	})
	flashButton.Clicked:Connect(function()
		UIKit.ScreenFX.Flash({ Color = UIKit.Theme.Neon.ToxicGreen })
	end)

	local bigMomentButton = UIKit.Button.new({
		Parent = content,
		Text = "Big Moment (Mythic Drop)",
		Variant = "Danger",
		Important = true,
		LayoutOrder = 2,
		Size = UDim2.new(1, 0, 0, 52),
	})
	bigMomentButton.Clicked:Connect(function()
		UIKit.ScreenFX.BigMoment(UIKit.Theme.Rarity.Mythic)
		UIKit.Toast.Show({ Text = "Mythic creature obtained!", Type = "Success", Duration = 4 })
	end)

	local reducedFxButton = UIKit.Button.new({
		Parent = content,
		Text = "Toggle Reduced Effects",
		Variant = "Ghost",
		LayoutOrder = 3,
		Size = UDim2.new(1, 0, 0, 44),
	})
	reducedFxButton.Clicked:Connect(function()
		local newValue = not UIKit.Settings.GetReducedEffects()
		UIKit.Settings.SetReducedEffects(newValue)
		UIKit.Toast.Show({
			Text = "Reduced effects: " .. (newValue and "ON" or "OFF"),
			Type = "Info",
		})
	end)

	local deviceInfoLabel = Instance.new("TextLabel")
	deviceInfoLabel.BackgroundTransparency = 1
	deviceInfoLabel.Size = UDim2.new(1, 0, 0, 60)
	deviceInfoLabel.Font = UIKit.Theme.Font.Mono
	deviceInfoLabel.TextColor3 = UIKit.Theme.Text.Secondary
	deviceInfoLabel.TextWrapped = true
	deviceInfoLabel.TextScaled = true
	deviceInfoLabel.LayoutOrder = 4
	deviceInfoLabel.Parent = content

	local function updateDeviceInfo()
		local state = UIKit.Device.GetState()
		deviceInfoLabel.Text = string.format(
			"Device: %s | Scale: %.2f | Touch: %s | Keyboard: %s | Gamepad: %s",
			state.Class,
			state.Scale,
			tostring(state.HasTouch),
			tostring(state.HasKeyboard),
			tostring(state.HasGamepad)
		)
	end
	updateDeviceInfo()
	UIKit.Device.Changed:Connect(updateDeviceInfo)
end

panel:Open()
