--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: BreedingUIController (LocalScript)
	Zuständigkeit:
		Brutbecken-Interaktions-UI (GDD Abschnitt 3 + Abschnitt 9, Punkt 4):
			- Klick auf ein platziertes, eigenes BroodPool-Gebäude öffnet ein
			  UIKit-Panel mit "Zucht starten"-Button + Kostenanzeige (leer),
			  Inkubations-Fortschrittsbalken (laufend) und "Kreatur
			  abholen"-Button + Rarity-Reveal (fertig).
			- Ein zweites UIKit-Panel ("Brutbecken-Übersicht", erreichbar
			  über die MainMenuController-Menüleiste bzw. die Bridge-
			  BindableEvent "OpenBreedingOverview") listet ALLE eigenen
			  Brutbecken mit Kurzstatus und einem "Öffnen"-Button je Zeile.
			- Ein kleines, dauerhaftes BillboardGui über jedem BroodPool
			  zeigt weiterhin den Kurzstatus (leer/Countdown/abholbereit),
			  auch ohne ein Panel zu öffnen.
			- Legendary/Mythic-Schlüpfungen lösen UIKit.ScreenFX.BigMoment
			  (Flash + Kamera-Shake) und einen UIKit.Toast aus.

		WICHTIG: Dies ist AUSSCHLIESSLICH Anzeige/Komfort. Die tatsächliche
		Autorität über Kosten, Timer und Zucht-Ergebnis liegt einzig beim
		Server (BreedingService) - dieses Skript hält nur einen lokalen,
		rein kosmetischen Status-Cache (aus BreedingRemotes.
		GetBreedingStatuses initial befüllt, danach über die Server-
		Ergebnis-Events aktualisiert) und zählt dessen Timer client-seitig
		grob runter. Jede Aktion (Start/Abholen) wird server-seitig erneut
		vollständig validiert.

	Rojo-Einhängepunkt:
		src/client/BreedingUIController.client.lua ->
		StarterPlayer.StarterPlayerScripts.BreedingUIController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BreedingConfig = require(ReplicatedStorage:WaitForChild("BreedingConfig"))
local BreedingRemotes = require(ReplicatedStorage:WaitForChild("BreedingRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Panel = UIKit.Panel
local Button = UIKit.Button
local ProgressBar = UIKit.ProgressBar
local RarityBadge = UIKit.RarityBadge
local Toast = UIKit.Toast
local ScreenFX = UIKit.ScreenFX

local player = Players.LocalPlayer

-- // Bridge (siehe MainMenuController.client.lua Kopfkommentar) ----------------
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

local openOverviewEvent = getOrCreateBridgeEvent("OpenBreedingOverview")

-- // Auf eigenen Plot warten (gleiches Muster wie PlacementPreviewController) --
local playerPlotsFolder = Workspace:WaitForChild("PlayerPlots")
local plot = playerPlotsFolder:WaitForChild(tostring(player.UserId), 30) :: Model?
if not plot then
	warn("[BreedingUIController] Kein eigener Plot gefunden - Brutbecken-UI deaktiviert.")
	return
end

local buildingsFolder = plot:WaitForChild("Buildings") :: Folder

local CLICK_MAX_DISTANCE = 20
local BIG_MOMENT_RARITIES = { Legendary = true, Mythic = true }

type BroodPoolStatus = {
	PlacementId: string,
	State: "Empty" | "Incubating" | "Ready",
	StartedAt: number?,
	ReadyAt: number?,
	RemainingSeconds: number?,
}

-- lokaler, rein kosmetischer Status-Cache je PlacementId
local statusCache: { [string]: BroodPoolStatus } = {}
-- Billboard-Referenzen je PlacementId, für die laufende Countdown-Aktualisierung
local billboardLabels: { [string]: TextLabel } = {}

-- // Farb-Hilfsfunktion (gleiches Rarity-Farbschema wie BreedingConfig/Theme) --
local function rarityColor(rarity: string): Color3
	local key = (rarity :: any) :: Theme.Rarity
	if table.find(Theme.RarityOrder, key) then
		return Theme.Rarity[key]
	end
	local definition = BreedingConfig.RARITY_DEFINITIONS[rarity]
	return definition and definition.Color or Color3.fromRGB(190, 255, 235)
end

local function formatDuration(totalSeconds: number): string
	totalSeconds = math.max(0, math.floor(totalSeconds))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return ("%02d:%02d"):format(minutes, seconds)
end

-- // Detail-Panel (einzelnes, wiederverwendetes UIKit.Panel) -------------------

local detailPanel = Panel.new({
	Title = "Brutbecken",
	Closable = true,
	CenteredSize = UDim2.fromOffset(420, 320),
})

local infoLabel = Instance.new("TextLabel")
infoLabel.Name = "Info"
infoLabel.BackgroundTransparency = 1
infoLabel.Size = UDim2.new(1, 0, 0, 110)
infoLabel.Font = Theme.Font.Body
infoLabel.TextWrapped = true
infoLabel.TextColor3 = Theme.Text.Secondary
infoLabel.TextYAlignment = Enum.TextYAlignment.Top
infoLabel.TextScaled = true
infoLabel.Text = ""
infoLabel.Parent = detailPanel.Content
local infoConstraint = Instance.new("UITextSizeConstraint")
infoConstraint.MinTextSize = 13
infoConstraint.MaxTextSize = 18
infoConstraint.Parent = infoLabel

local progressHost = Instance.new("Frame")
progressHost.Name = "ProgressHost"
progressHost.BackgroundTransparency = 1
progressHost.Position = UDim2.new(0, 0, 0, 116)
progressHost.Size = UDim2.new(1, 0, 0, 22)
progressHost.Visible = false
progressHost.Parent = detailPanel.Content
local progressBar = ProgressBar.new({
	Parent = progressHost,
	Size = UDim2.new(1, 0, 1, 0),
	Colors = { Theme.Neon.Cyan, Theme.Neon.Violet },
})

local rewardBadgeHost = Instance.new("Frame")
rewardBadgeHost.Name = "RewardBadgeHost"
rewardBadgeHost.BackgroundTransparency = 1
rewardBadgeHost.Position = UDim2.new(0, 0, 0, 116)
rewardBadgeHost.Size = UDim2.new(1, 0, 0, 36)
rewardBadgeHost.Visible = false
rewardBadgeHost.Parent = detailPanel.Content
local rewardBadge: any = nil

local actionButton = Button.new({
	Parent = detailPanel.Content,
	Text = "",
	Variant = "Success",
	Important = true,
	Size = UDim2.new(1, 0, 0, 48),
	LayoutOrder = 5,
})
actionButton.Instance.Position = UDim2.new(0, 0, 1, -48)

local activePlacementId: string? = nil

local function closePanel()
	activePlacementId = nil
	detailPanel:Close()
end

-- // Panel-Inhalt anhand des aktuellen Status aufbauen ------------------------

local function refreshPanel()
	if not activePlacementId then
		return
	end

	local status = statusCache[activePlacementId]
	if not status then
		return
	end

	progressHost.Visible = false
	rewardBadgeHost.Visible = false
	if rewardBadge then
		rewardBadge:Destroy()
		rewardBadge = nil
	end

	if status.State == "Empty" then
		local tier = BreedingConfig.GetTier(1) -- MVP: nur BroodPool_Basic (Level 1) baubar
		infoLabel.Text = ("%s\nFütterungskosten: %d Tide Coins\nInkubationsdauer: ~%d Min.\nChancen: Gewöhnlich %.0f%% · Selten %.0f%% · Legendär %.1f%%"):format(
			tier.DisplayName,
			tier.FeedCostTideCoins,
			tier.IncubationMinutes,
			tier.RarityWeights.Common,
			tier.RarityWeights.Rare,
			tier.RarityWeights.Legendary
		)
		actionButton:SetText(("Zucht starten (%d Tide Coins)"):format(tier.FeedCostTideCoins))
		actionButton:SetDisabled(false)
		actionButton.Instance.Visible = true
	elseif status.State == "Incubating" then
		infoLabel.Text = "Zucht läuft ..."
		actionButton:SetText("Noch nicht bereit")
		actionButton:SetDisabled(true)
		actionButton.Instance.Visible = true

		progressHost.Visible = true
		local total = (status.ReadyAt or 0) - (status.StartedAt or 0)
		local remaining = status.RemainingSeconds or 0
		local ratio = if total > 0 then math.clamp(1 - remaining / total, 0, 1) else 0
		progressBar:SetProgress(ratio, false)
		infoLabel.Text = ("Zucht läuft ...\nFertig in: %s"):format(formatDuration(remaining))
	elseif status.State == "Ready" then
		infoLabel.Text = "Eine Kreatur ist bereit zum Schlüpfen!"
		actionButton:SetText("Kreatur abholen")
		actionButton:SetDisabled(false)
		actionButton.Instance.Visible = true
	end
end

local function openPanelFor(placementId: string)
	activePlacementId = placementId
	refreshPanel()
	detailPanel:Open()
end

detailPanel.Closed:Connect(function()
	activePlacementId = nil
end)

actionButton.Clicked:Connect(function()
	if not activePlacementId then
		return
	end
	local status = statusCache[activePlacementId]
	if not status then
		return
	end

	if status.State == "Empty" then
		actionButton:SetDisabled(true)
		infoLabel.Text = "Zucht wird angefragt ..."
		BreedingRemotes.RequestStartBreeding:FireServer(activePlacementId)
	elseif status.State == "Ready" then
		actionButton:SetDisabled(true)
		infoLabel.Text = "Kreatur wird abgeholt ..."
		BreedingRemotes.RequestClaimBreeding:FireServer(activePlacementId)
	end
end)

-- // Übersichts-Panel (alle eigenen Brutbecken) --------------------------------

local overviewPanel = Panel.new({
	Title = "Brutbecken-Übersicht",
	Closable = true,
	CenteredSize = UDim2.fromOffset(420, 420),
})

local overviewScroll = Instance.new("ScrollingFrame")
overviewScroll.Name = "OverviewScroll"
overviewScroll.BackgroundTransparency = 1
overviewScroll.BorderSizePixel = 0
overviewScroll.Size = UDim2.fromScale(1, 1)
overviewScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
overviewScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
overviewScroll.ScrollBarThickness = 6
overviewScroll.ScrollBarImageColor3 = Theme.Neon.Cyan
overviewScroll.Parent = overviewPanel.Content

local overviewList = Instance.new("UIListLayout")
overviewList.SortOrder = Enum.SortOrder.LayoutOrder
overviewList.Padding = UDim.new(0, 8)
overviewList.Parent = overviewScroll

local overviewEmptyLabel = Instance.new("TextLabel")
overviewEmptyLabel.Name = "EmptyLabel"
overviewEmptyLabel.BackgroundTransparency = 1
overviewEmptyLabel.Size = UDim2.new(1, 0, 0, 40)
overviewEmptyLabel.Font = Theme.Font.Body
overviewEmptyLabel.TextColor3 = Theme.Text.Muted
overviewEmptyLabel.TextScaled = true
overviewEmptyLabel.Text = "Noch kein Brutbecken gebaut. Baue eins über das Bauen-Menü."
overviewEmptyLabel.LayoutOrder = 0
overviewEmptyLabel.Parent = overviewScroll

local overviewRowHandles: { [string]: { Frame: Frame, Button: any } } = {}

local function stateShortText(status: BroodPoolStatus): string
	if status.State == "Empty" then
		return "Frei - Zucht starten"
	elseif status.State == "Incubating" then
		return "Inkubiert: " .. formatDuration(status.RemainingSeconds or 0)
	else
		return "Bereit zum Abholen!"
	end
end

local function rebuildOverview()
	for _, entry in overviewRowHandles do
		entry.Button:Destroy()
		entry.Frame:Destroy()
	end
	table.clear(overviewRowHandles)

	local count = 0
	local order = 1
	for placementId, status in pairs(statusCache) do
		count += 1
		order += 1

		local row = Instance.new("Frame")
		row.Name = placementId
		row.BackgroundColor3 = Theme.Background.PanelLight
		row.Size = UDim2.new(1, 0, 0, 56)
		row.LayoutOrder = order
		row.Parent = overviewScroll
		Theme.ApplyCorner(row, UDim.new(0, 10))

		local statusLabel = Instance.new("TextLabel")
		statusLabel.BackgroundTransparency = 1
		statusLabel.Position = UDim2.fromOffset(10, 6)
		statusLabel.Size = UDim2.new(1, -110, 1, -12)
		statusLabel.Font = Theme.Font.BodyBold
		statusLabel.TextColor3 = if status.State == "Ready"
			then Theme.Neon.Yellow
			elseif status.State == "Incubating" then Theme.Neon.Cyan
			else Theme.Text.Secondary
		statusLabel.TextXAlignment = Enum.TextXAlignment.Left
		statusLabel.TextWrapped = true
		statusLabel.TextScaled = true
		statusLabel.Text = stateShortText(status)
		statusLabel.Parent = row
		local statusConstraint = Instance.new("UITextSizeConstraint")
		statusConstraint.MinTextSize = 12
		statusConstraint.MaxTextSize = 16
		statusConstraint.Parent = statusLabel

		local openButton = Button.new({
			Parent = row,
			Text = "Öffnen",
			Variant = "Primary",
			Size = UDim2.fromOffset(90, 40),
		})
		openButton.Instance.AnchorPoint = Vector2.new(1, 0.5)
		openButton.Instance.Position = UDim2.new(1, -8, 0.5, 0)
		openButton.Clicked:Connect(function()
			overviewPanel:Close()
			openPanelFor(placementId)
		end)

		overviewRowHandles[placementId] = { Frame = row, Button = openButton }
	end

	overviewEmptyLabel.Visible = count == 0
end

local bridgeConnection = openOverviewEvent.Event:Connect(function()
	rebuildOverview()
	overviewPanel:Open()
end)

-- // Billboards über jedem BroodPool (dauerhaft sichtbarer Kurzstatus) --------

local function updateBillboard(placementId: string)
	local label = billboardLabels[placementId]
	local status = statusCache[placementId]
	if not label or not status then
		return
	end
	label.Text = stateShortText(status)
	if status.State == "Ready" then
		label.TextColor3 = Theme.Neon.Yellow
	elseif status.State == "Incubating" then
		label.TextColor3 = Theme.Neon.Cyan
	else
		label.TextColor3 = Theme.Text.Secondary
	end
end

local function ensureBroodPoolInteraction(model: Model)
	if model:GetAttribute("BuildingId") ~= "BroodPool" then
		return
	end
	local placementId = model:GetAttribute("PlacementId")
	if type(placementId) ~= "string" then
		return
	end
	local primaryPart = model.PrimaryPart
	if not primaryPart then
		return
	end

	if not statusCache[placementId] then
		statusCache[placementId] = { PlacementId = placementId, State = "Empty" }
	end

	if not primaryPart:FindFirstChildOfClass("ClickDetector") then
		local clickDetector = Instance.new("ClickDetector")
		clickDetector.MaxActivationDistance = CLICK_MAX_DISTANCE
		clickDetector.Parent = primaryPart

		clickDetector.MouseClick:Connect(function(clickingPlayer)
			if clickingPlayer ~= player then
				return
			end
			openPanelFor(placementId)
		end)
	end

	if not billboardLabels[placementId] then
		local billboard = Instance.new("BillboardGui")
		billboard.Name = "BreedingStatusBillboard"
		billboard.Size = UDim2.fromOffset(200, 40)
		billboard.StudsOffset = Vector3.new(0, 6, 0)
		billboard.AlwaysOnTop = true
		billboard.Parent = primaryPart

		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Theme.Background.Panel
		bg.BackgroundTransparency = 0.35
		bg.BorderSizePixel = 0
		bg.Parent = billboard
		Theme.ApplyCorner(bg, UDim.new(0, 8))

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Theme.Font.Body
		label.TextScaled = true
		label.Text = "..."
		label.TextColor3 = Theme.Text.Secondary
		label.Parent = bg

		billboardLabels[placementId] = label
	end

	updateBillboard(placementId)
end

local function scanExistingBroodPools()
	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child:IsA("Model") then
			ensureBroodPoolInteraction(child)
		end
	end
end

buildingsFolder.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		ensureBroodPoolInteraction(child)
		rebuildOverview()
	end
end)

buildingsFolder.ChildRemoved:Connect(function(child)
	local placementId = child:GetAttribute("PlacementId")
	if type(placementId) == "string" then
		statusCache[placementId] = nil
		billboardLabels[placementId] = nil
		if activePlacementId == placementId then
			closePanel()
		end
		rebuildOverview()
	end
end)

-- // Initialer Status-Sync + laufender lokaler Countdown ----------------------

local function applyStatuses(statuses: { BroodPoolStatus })
	for _, status in ipairs(statuses) do
		statusCache[status.PlacementId] = status
		updateBillboard(status.PlacementId)
	end
	refreshPanel()
	rebuildOverview()
end

task.spawn(function()
	local ok, statuses = pcall(function()
		return BreedingRemotes.GetBreedingStatuses:InvokeServer()
	end)
	if ok and type(statuses) == "table" then
		applyStatuses(statuses)
	else
		warn("[BreedingUIController] Initialer Status-Sync fehlgeschlagen.")
	end
end)

-- Lokaler, rein kosmetischer Countdown (1x/Sekunde) - keine Autorität, siehe
-- Kopfkommentar. Server-Ergebnisse überschreiben den Cache jederzeit wieder
-- korrekt.
local countdownThread = task.spawn(function()
	while true do
		task.wait(1)
		for placementId, status in pairs(statusCache) do
			if status.State == "Incubating" and status.ReadyAt then
				local remaining = status.ReadyAt - os.time()
				if remaining <= 0 then
					status.State = "Ready"
					status.RemainingSeconds = 0
				else
					status.RemainingSeconds = remaining
				end
				updateBillboard(placementId)
				if activePlacementId == placementId then
					refreshPanel()
				end
			end
		end
	end
end)

-- // Server-Ergebnisse (Feedback + Cache-Update) ------------------------------

BreedingRemotes.StartBreedingResult.OnClientEvent:Connect(function(result)
	if not result then
		return
	end
	if result.Success then
		statusCache[result.PlacementId] = {
			PlacementId = result.PlacementId,
			State = "Incubating",
			StartedAt = result.StartedAt,
			ReadyAt = result.ReadyAt,
			RemainingSeconds = math.max(0, result.ReadyAt - os.time()),
		}
		updateBillboard(result.PlacementId)
		rebuildOverview()
	end
	if activePlacementId == result.PlacementId then
		if result.Success then
			refreshPanel()
		else
			infoLabel.Text = ("Zucht-Start fehlgeschlagen: %s"):format(tostring(result.Reason or "Unbekannt"))
			actionButton.Instance.Visible = true
			actionButton:SetDisabled(false)
			Toast.Show({ Text = "Zucht-Start fehlgeschlagen.", Type = "Error" })
		end
	end
end)

BreedingRemotes.ClaimBreedingResult.OnClientEvent:Connect(function(result)
	if not result then
		return
	end

	if result.Success then
		statusCache[result.PlacementId] = { PlacementId = result.PlacementId, State = "Empty" }
		updateBillboard(result.PlacementId)
		rebuildOverview()

		local color = rarityColor(result.Rarity)
		if BIG_MOMENT_RARITIES[result.Rarity] then
			ScreenFX.BigMoment(color)
		end
		Toast.Show({
			Text = ("Geschlüpft: %s (%s)!"):format(result.CreatureName, result.Rarity),
			Type = "Success",
			Duration = 4,
		})

		if activePlacementId == result.PlacementId then
			infoLabel.Text = ("Geschlüpft: %s!"):format(result.CreatureName)
			progressHost.Visible = false
			rewardBadgeHost.Visible = true
			local rarityKey = (result.Rarity :: any) :: Theme.Rarity
			if table.find(Theme.RarityOrder, rarityKey) then
				rewardBadge = RarityBadge.new({
					Parent = rewardBadgeHost,
					Rarity = rarityKey,
					Size = UDim2.fromOffset(140, 32),
				})
			end
			actionButton.Instance.Visible = false
			task.delay(2.5, function()
				if activePlacementId == result.PlacementId then
					refreshPanel()
				end
			end)
		end
	else
		if activePlacementId == result.PlacementId then
			if result.Reason == "NotReadyYet" then
				infoLabel.Text = ("Noch nicht bereit: %s"):format(formatDuration(result.RemainingSeconds or 0))
			else
				infoLabel.Text = ("Abholen fehlgeschlagen: %s"):format(tostring(result.Reason or "Unbekannt"))
			end
			refreshPanel()
		end
	end
end)

BreedingRemotes.InstantCompleteBreedingResult.OnClientEvent:Connect(function(result)
	if activePlacementId and result then
		infoLabel.Text = if result.Success
			then "Zucht sofort abgeschlossen!"
			else "Sofort-Abschluss aktuell nicht verfügbar (folgt später)."
	end
end)

-- // Setup ---------------------------------------------------------------------

scanExistingBroodPools()
rebuildOverview()

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	bridgeConnection:Disconnect()
	task.cancel(countdownThread)
	detailPanel:Destroy()
	overviewPanel:Destroy()
end)
