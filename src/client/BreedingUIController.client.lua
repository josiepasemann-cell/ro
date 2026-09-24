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
local BuildingConfig = require(ReplicatedStorage:WaitForChild("BuildingConfig"))
local HabitatRemotes = require(ReplicatedStorage:WaitForChild("HabitatRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = require(ReplicatedStorage:WaitForChild("UIKit"):WaitForChild("Theme"))
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
	warn("[BreedingUIController] No own plot found - Brood Pool UI disabled.")
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
-- Gebäude-Upgrade-System (siehe docs/building-upgrades.md): lokaler Cache der
-- aktuellen Ausbaustufe je PlacementId (== BreedingConfig-Zucht-Stufe für
-- dieses BroodPool) - initial vom Modell-Attribut "Level" übernommen (siehe
-- PlacementService.tagModel), danach über UpgradeBuildingResult aktuell
-- gehalten (siehe unten). Rein kosmetisch, identisches Prinzip wie
-- statusCache - keine Autorität.
local placementLevelCache: { [string]: number } = {}

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
	Title = "Brood Pool",
	Closable = true,
	-- +80px ggü. vorher: Platz für die Stufen-/Upgrade-Sektion (siehe
	-- upgradeInfoLabel/breedingUpgradeButton unten, Auftrag Gebäude-Upgrade-
	-- System).
	CenteredSize = UDim2.fromOffset(420, 400),
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

-- // Gebäude-Upgrade-System (siehe docs/building-upgrades.md, Auftrag Punkt
-- 4 "Breeding panel shows the pool's tier") - eigene, vom Zucht-Zustand
-- (Empty/Incubating/Ready) unabhängige Sektion: aktuelle Stufe, nächste
-- Stufe (Zucht-Tier-Name + Kosten), Upgrade-Button. Deaktiviert, während
-- eine Inkubation läuft (siehe PlacementService.RequestUpgrade
-- Kopfkommentar "kein Upgrade während laufender Inkubation" für die volle
-- Begründung dieser Design-Entscheidung).
local upgradeInfoLabel = Instance.new("TextLabel")
upgradeInfoLabel.Name = "UpgradeInfo"
upgradeInfoLabel.BackgroundTransparency = 1
upgradeInfoLabel.Position = UDim2.new(0, 0, 0, 154)
upgradeInfoLabel.Size = UDim2.new(1, 0, 0, 60)
upgradeInfoLabel.Font = Theme.Font.Body
upgradeInfoLabel.TextWrapped = true
upgradeInfoLabel.TextColor3 = Theme.Text.Secondary
upgradeInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
upgradeInfoLabel.TextScaled = true
upgradeInfoLabel.Text = ""
upgradeInfoLabel.Parent = detailPanel.Content
local upgradeInfoConstraint = Instance.new("UITextSizeConstraint")
upgradeInfoConstraint.MinTextSize = 11
upgradeInfoConstraint.MaxTextSize = 15
upgradeInfoConstraint.Parent = upgradeInfoLabel

local breedingUpgradeButton = Button.new({
	Parent = detailPanel.Content,
	Text = "Upgrade",
	Variant = "Primary",
	Size = UDim2.new(1, 0, 0, 40),
	LayoutOrder = 4,
})
breedingUpgradeButton.Instance.Position = UDim2.new(0, 0, 0, 218)

local activePlacementId: string? = nil

local function closePanel()
	activePlacementId = nil
	detailPanel:Close()
end

--- Aktualisiert die Stufen-/Upgrade-Sektion (siehe upgradeInfoLabel/
--- breedingUpgradeButton oben) für das aktuell geöffnete Brutbecken -
--- unabhängig vom Zucht-Zustand (Empty/Incubating/Ready), daher eine
--- eigene Funktion statt Teil des state-spezifischen if/elseif in
--- refreshPanel unten.
local function refreshUpgradeSection()
	if not activePlacementId then
		return
	end

	local definition = BuildingConfig.Get("BroodPool")
	if not definition then
		return
	end

	local stage = placementLevelCache[activePlacementId] or 1
	local status = statusCache[activePlacementId]
	local incubating = status ~= nil and status.State ~= "Empty"

	if stage >= definition.MaxStage then
		upgradeInfoLabel.Text = ("Stage %d/%d (Master) — maximum stage reached."):format(stage, definition.MaxStage)
		breedingUpgradeButton:SetText("Max Stage")
		breedingUpgradeButton:SetDisabled(true)
		return
	end

	local nextStage = stage + 1
	local cost = definition.UpgradeCosts[nextStage]
	local nextTier = BreedingConfig.GetTier(nextStage)

	local costText = "—"
	if cost then
		if cost.AbyssalShards and cost.AbyssalShards > 0 then
			costText = ("%d Tide Coins + %d Abyssal Shards"):format(cost.TideCoins, cost.AbyssalShards)
		else
			costText = ("%d Tide Coins"):format(cost.TideCoins)
		end
	end

	local suffix = if incubating then "\n(finish the current incubation first)" else ""
	upgradeInfoLabel.Text = ("Stage %d/%d — Next: %s (requires Level %d)\nCost: %s%s"):format(
		stage,
		definition.MaxStage,
		nextTier.DisplayName,
		cost and cost.LevelRequirement or 0,
		costText,
		suffix
	)
	breedingUpgradeButton:SetText(if cost then ("Upgrade (%d 🌊)"):format(cost.TideCoins) else "Upgrade")
	breedingUpgradeButton:SetDisabled(incubating)
end

breedingUpgradeButton.Clicked:Connect(function()
	if not activePlacementId then
		return
	end
	breedingUpgradeButton:SetDisabled(true)
	HabitatRemotes.RequestUpgradeBuilding:FireServer(activePlacementId)
end)

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
		-- Gebäude-Upgrade-System: die tatsächliche, aktuelle Ausbaustufe
		-- dieses Brutbeckens bestimmt jetzt die Zucht-Stufe (statt fest 1) -
		-- siehe placementLevelCache/ensureBroodPoolInteraction unten.
		local tier = BreedingConfig.GetTier(placementLevelCache[activePlacementId] or 1)
		infoLabel.Text = ("%s\nFeeding cost: %d Tide Coins\nIncubation time: ~%d min.\nOdds: Common %.0f%% · Rare %.0f%% · Legendary %.1f%%"):format(
			tier.DisplayName,
			tier.FeedCostTideCoins,
			tier.IncubationMinutes,
			tier.RarityWeights.Common,
			tier.RarityWeights.Rare,
			tier.RarityWeights.Legendary
		)
		actionButton:SetText(("Start Breeding (%d Tide Coins)"):format(tier.FeedCostTideCoins))
		actionButton:SetDisabled(false)
		actionButton.Instance.Visible = true
	elseif status.State == "Incubating" then
		infoLabel.Text = "Breeding in progress ..."
		actionButton:SetText("Not Ready Yet")
		actionButton:SetDisabled(true)
		actionButton.Instance.Visible = true

		progressHost.Visible = true
		local total = (status.ReadyAt or 0) - (status.StartedAt or 0)
		local remaining = status.RemainingSeconds or 0
		local ratio = if total > 0 then math.clamp(1 - remaining / total, 0, 1) else 0
		progressBar:SetProgress(ratio, false)
		infoLabel.Text = ("Breeding in progress ...\nReady in: %s"):format(formatDuration(remaining))
	elseif status.State == "Ready" then
		infoLabel.Text = "A creature is ready to hatch!"
		actionButton:SetText("Claim Creature")
		actionButton:SetDisabled(false)
		actionButton.Instance.Visible = true
	end

	refreshUpgradeSection()
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
		infoLabel.Text = "Requesting breeding ..."
		BreedingRemotes.RequestStartBreeding:FireServer(activePlacementId)
	elseif status.State == "Ready" then
		actionButton:SetDisabled(true)
		infoLabel.Text = "Claiming creature ..."
		BreedingRemotes.RequestClaimBreeding:FireServer(activePlacementId)
	end
end)

-- // Übersichts-Panel (alle eigenen Brutbecken) --------------------------------

local overviewPanel = Panel.new({
	Title = "Brood Pool Overview",
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
overviewEmptyLabel.Text = "No Brood Pool built yet. Build one via the Build menu."
overviewEmptyLabel.LayoutOrder = 0
overviewEmptyLabel.Parent = overviewScroll

local overviewRowHandles: { [string]: { Frame: Frame, Button: any } } = {}

local function stateShortText(status: BroodPoolStatus): string
	if status.State == "Empty" then
		return "Free - Start Breeding"
	elseif status.State == "Incubating" then
		return "Incubating: " .. formatDuration(status.RemainingSeconds or 0)
	else
		return "Ready to Claim!"
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
			Text = "Open",
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

		-- Gebäude-Upgrade-System: Ausbaustufe initial vom Modell-Attribut
		-- übernehmen + auf künftige Änderungen reagieren (ein Upgrade tauscht
		-- entweder DIESES Modell-Attribut live aus - Fail-Soft-Akzent-Pfad,
		-- siehe PlacementService.applyStageToModel - oder ersetzt das Modell
		-- komplett, was hier über buildingsFolder.ChildAdded erneut
		-- ensureBroodPoolInteraction für die NEUE Instanz auslöst). An den
		-- ClickDetector-Erstellungs-Guard gekoppelt, damit diese Verbindung
		-- pro Modell-Instanz nur einmal entsteht.
		local level = model:GetAttribute("Level")
		placementLevelCache[placementId] = if type(level) == "number" then level else 1
		model:GetAttributeChangedSignal("Level"):Connect(function()
			local newLevel = model:GetAttribute("Level")
			placementLevelCache[placementId] = if type(newLevel) == "number" then newLevel else 1
			if activePlacementId == placementId then
				refreshUpgradeSection()
			end
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
		warn("[BreedingUIController] Initial status sync failed.")
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
			infoLabel.Text = ("Breeding start failed: %s"):format(tostring(result.Reason or "Unknown"))
			actionButton.Instance.Visible = true
			actionButton:SetDisabled(false)
			Toast.Show({ Text = "Breeding start failed.", Type = "Error" })
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
			Text = ("Hatched: %s (%s)!"):format(result.CreatureName, result.Rarity),
			Type = "Success",
			Duration = 4,
		})

		if activePlacementId == result.PlacementId then
			infoLabel.Text = ("Hatched: %s!"):format(result.CreatureName)
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
				infoLabel.Text = ("Not ready yet: %s"):format(formatDuration(result.RemainingSeconds or 0))
			else
				infoLabel.Text = ("Claim failed: %s"):format(tostring(result.Reason or "Unknown"))
			end
			refreshPanel()
		end
	end
end)

BreedingRemotes.InstantCompleteBreedingResult.OnClientEvent:Connect(function(result)
	if activePlacementId and result then
		infoLabel.Text = if result.Success
			then "Breeding completed instantly!"
			else "Instant completion is not available yet (coming later)."
	end
end)

-- Gebäude-Upgrade-System: hält placementLevelCache aktuell und aktualisiert
-- die Stufen-Sektion des offenen Panels, falls es gerade dieses Brutbecken
-- zeigt. Erfolgs-Toast/BigMoment-FX kommen bereits generisch für JEDES
-- Gebäude aus PlacementPreviewController.client.lua (Auftrag Punkt 4) -
-- hier bewusst KEIN zweiter Toast, um Doppel-Feedback bei einem BroodPool-
-- Upgrade zu vermeiden. `statusCache[result.PlacementId] == nil` filtert
-- zuverlässig Upgrade-Ergebnisse anderer Gebäudetypen heraus (dieses
-- Skript kennt nur BroodPool-PlacementIds).
HabitatRemotes.UpgradeBuildingResult.OnClientEvent:Connect(function(result)
	if not result or type(result.PlacementId) ~= "string" then
		return
	end
	if not statusCache[result.PlacementId] then
		return
	end

	if result.Success and type(result.NewStage) == "number" then
		placementLevelCache[result.PlacementId] = result.NewStage
	end

	if activePlacementId == result.PlacementId then
		refreshUpgradeSection()
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
