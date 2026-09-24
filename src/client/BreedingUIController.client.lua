--[[
	Abyssara – Deep Tide Tycoon
	Skript: BreedingUIController (LocalScript)
	Zuständigkeit:
		Einfaches Brutbecken-Interaktions-UI für das MVP (GDD Abschnitt 3 +
		Abschnitt 9, Punkt 4): Klick auf ein platziertes, eigenes BroodPool-
		Gebäude öffnet ein Panel mit
			- "Zucht starten"-Button + Kostenanzeige (falls leer),
			- laufender Timer-Anzeige (falls eine Inkubation läuft),
			- "Kreatur abholen"-Button + kurzer Reveal-Anzeige (falls fertig).
		Zusätzlich zeigt ein kleines, dauerhaftes BillboardGui über jedem
		BroodPool den aktuellen Status (leer/Countdown/abholbereit), auch
		ohne das Panel zu öffnen.

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
		(".client.lua"-Suffix signalisiert Rojo, hieraus ein `LocalScript`
		zu machen.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BreedingConfig = require(ReplicatedStorage:WaitForChild("BreedingConfig"))
local BreedingRemotes = require(ReplicatedStorage:WaitForChild("BreedingRemotes"))

local player = Players.LocalPlayer

-- // Auf eigenen Plot warten (gleiches Muster wie PlacementPreviewController) --
local playerPlotsFolder = Workspace:WaitForChild("PlayerPlots")
local plot = playerPlotsFolder:WaitForChild(tostring(player.UserId), 30) :: Model?
if not plot then
	warn("[BreedingUIController] Kein eigener Plot gefunden - Brutbecken-UI deaktiviert.")
	return
end

local buildingsFolder = plot:WaitForChild("Buildings") :: Folder

local CLICK_MAX_DISTANCE = 20

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

-- // Farb-Hilfsfunktion (gleiches Rarity-Farbschema wie BreedingConfig) -------
local function rarityColor(rarity: string): Color3
	local definition = BreedingConfig.RARITY_DEFINITIONS[rarity]
	return definition and definition.Color or Color3.fromRGB(190, 255, 235)
end

local function formatDuration(totalSeconds: number): string
	totalSeconds = math.max(0, math.floor(totalSeconds))
	local minutes = math.floor(totalSeconds / 60)
	local seconds = totalSeconds % 60
	return ("%02d:%02d"):format(minutes, seconds)
end

-- // Haupt-Panel (einzelnes, wiederverwendetes ScreenGui) ---------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BreedingUI"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Name = "BreedingPanel"
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.fromScale(0.5, 0.5)
panel.Size = UDim2.fromOffset(360, 220)
panel.BackgroundColor3 = Color3.fromRGB(10, 22, 30)
panel.BackgroundTransparency = 0.05
panel.Parent = screenGui

local panelCorner = Instance.new("UICorner")
panelCorner.CornerRadius = UDim.new(0, 14)
panelCorner.Parent = panel

local panelStroke = Instance.new("UIStroke")
panelStroke.Color = Color3.fromRGB(70, 210, 235)
panelStroke.Thickness = 2
panelStroke.Parent = panel

local titleLabel = Instance.new("TextLabel")
titleLabel.Name = "Title"
titleLabel.Size = UDim2.new(1, -20, 0, 34)
titleLabel.Position = UDim2.new(0, 10, 0, 10)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 20
titleLabel.TextColor3 = Color3.fromRGB(230, 245, 250)
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Text = "Brutbecken"
titleLabel.Parent = panel

local closeButton = Instance.new("TextButton")
closeButton.Name = "CloseButton"
closeButton.Size = UDim2.fromOffset(28, 28)
closeButton.Position = UDim2.new(1, -38, 0, 10)
closeButton.BackgroundColor3 = Color3.fromRGB(235, 90, 90)
closeButton.Text = "X"
closeButton.Font = Enum.Font.GothamBold
closeButton.TextColor3 = Color3.fromRGB(255, 255, 255)
closeButton.Parent = panel

local closeCorner = Instance.new("UICorner")
closeCorner.CornerRadius = UDim.new(1, 0)
closeCorner.Parent = closeButton

local infoLabel = Instance.new("TextLabel")
infoLabel.Name = "Info"
infoLabel.Size = UDim2.new(1, -20, 0, 90)
infoLabel.Position = UDim2.new(0, 10, 0, 50)
infoLabel.BackgroundTransparency = 1
infoLabel.Font = Enum.Font.GothamMedium
infoLabel.TextSize = 16
infoLabel.TextWrapped = true
infoLabel.TextColor3 = Color3.fromRGB(210, 235, 240)
infoLabel.TextYAlignment = Enum.TextYAlignment.Top
infoLabel.Text = ""
infoLabel.Parent = panel

local actionButton = Instance.new("TextButton")
actionButton.Name = "ActionButton"
actionButton.Size = UDim2.new(1, -20, 0, 44)
actionButton.Position = UDim2.new(0, 10, 1, -56)
actionButton.BackgroundColor3 = Color3.fromRGB(90, 235, 140)
actionButton.Font = Enum.Font.GothamBold
actionButton.TextSize = 18
actionButton.TextColor3 = Color3.fromRGB(10, 20, 15)
actionButton.Text = ""
actionButton.Parent = panel

local actionCorner = Instance.new("UICorner")
actionCorner.CornerRadius = UDim.new(0, 10)
actionCorner.Parent = actionButton

local activePlacementId: string? = nil

local function closePanel()
	activePlacementId = nil
	screenGui.Enabled = false
end

closeButton.MouseButton1Click:Connect(closePanel)

-- // Panel-Inhalt anhand des aktuellen Status aufbauen ------------------------

local function refreshPanel()
	if not activePlacementId then
		return
	end

	local status = statusCache[activePlacementId]
	if not status then
		return
	end

	if status.State == "Empty" then
		local tier = BreedingConfig.GetTier(1) -- MVP: nur BroodPool_Basic (Level 1) baubar, siehe BreedingConfig-Kopfkommentar
		infoLabel.Text = ("%s\nFütterungskosten: %d Tide Coins\nInkubationsdauer: ~%d Min.\nChancen: Gewöhnlich %.0f%% · Selten %.0f%% · Legendär %.1f%%"):format(
			tier.DisplayName,
			tier.FeedCostTideCoins,
			tier.IncubationMinutes,
			tier.RarityWeights.Common,
			tier.RarityWeights.Rare,
			tier.RarityWeights.Legendary
		)
		actionButton.Text = ("Zucht starten (%d Tide Coins)"):format(tier.FeedCostTideCoins)
		actionButton.BackgroundColor3 = Color3.fromRGB(90, 235, 140)
		actionButton.Visible = true
	elseif status.State == "Incubating" then
		infoLabel.Text = ("Zucht läuft ...\nFertig in: %s"):format(formatDuration(status.RemainingSeconds or 0))
		actionButton.Text = "Noch nicht bereit"
		actionButton.BackgroundColor3 = Color3.fromRGB(90, 140, 200)
		actionButton.Visible = false
	elseif status.State == "Ready" then
		infoLabel.Text = "Eine Kreatur ist bereit zum Schlüpfen!"
		actionButton.Text = "Kreatur abholen"
		actionButton.BackgroundColor3 = Color3.fromRGB(255, 210, 90)
		actionButton.Visible = true
	end
end

local function openPanelFor(placementId: string)
	activePlacementId = placementId
	screenGui.Enabled = true
	refreshPanel()
end

actionButton.MouseButton1Click:Connect(function()
	if not activePlacementId then
		return
	end
	local status = statusCache[activePlacementId]
	if not status then
		return
	end

	if status.State == "Empty" then
		actionButton.Visible = false
		infoLabel.Text = "Zucht wird angefragt ..."
		BreedingRemotes.RequestStartBreeding:FireServer(activePlacementId)
	elseif status.State == "Ready" then
		actionButton.Visible = false
		infoLabel.Text = "Kreatur wird abgeholt ..."
		BreedingRemotes.RequestClaimBreeding:FireServer(activePlacementId)
	end
end)

-- // Billboards über jedem BroodPool (dauerhaft sichtbarer Kurzstatus) --------

local function stateShortText(status: BroodPoolStatus): string
	if status.State == "Empty" then
		return "Frei - klicken zum Züchten"
	elseif status.State == "Incubating" then
		return "Inkubiert: " .. formatDuration(status.RemainingSeconds or 0)
	else
		return "Bereit zum Abholen!"
	end
end

local function updateBillboard(placementId: string)
	local label = billboardLabels[placementId]
	local status = statusCache[placementId]
	if not label or not status then
		return
	end
	label.Text = stateShortText(status)
	if status.State == "Ready" then
		label.TextColor3 = Color3.fromRGB(255, 210, 90)
	elseif status.State == "Incubating" then
		label.TextColor3 = Color3.fromRGB(150, 220, 255)
	else
		label.TextColor3 = Color3.fromRGB(190, 255, 235)
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
		bg.BackgroundColor3 = Color3.fromRGB(10, 20, 28)
		bg.BackgroundTransparency = 0.35
		bg.BorderSizePixel = 0
		bg.Parent = billboard

		local bgCorner = Instance.new("UICorner")
		bgCorner.CornerRadius = UDim.new(0, 8)
		bgCorner.Parent = bg

		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamMedium
		label.TextScaled = true
		label.Text = "..."
		label.TextColor3 = Color3.fromRGB(190, 255, 235)
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
	end
end)

-- // Initialer Status-Sync + laufender lokaler Countdown ----------------------

local function applyStatuses(statuses: { BroodPoolStatus })
	for _, status in ipairs(statuses) do
		statusCache[status.PlacementId] = status
		updateBillboard(status.PlacementId)
	end
	refreshPanel()
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
task.spawn(function()
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
	elseif result.PlacementId then
		-- Fehlschlag: Cache unverändert lassen, Panel zeigt bei erneutem
		-- Öffnen wieder den korrekten ("Empty") Zustand.
	end
	if activePlacementId == result.PlacementId or (not result.Success and activePlacementId) then
		if result.Success then
			refreshPanel()
		else
			infoLabel.Text = ("Zucht-Start fehlgeschlagen: %s"):format(tostring(result.Reason or "Unbekannt"))
			actionButton.Visible = true
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

		if activePlacementId == result.PlacementId then
			infoLabel.Text = ("Geschlüpft: %s (%s)!"):format(result.CreatureName, result.Rarity)
			infoLabel.TextColor3 = rarityColor(result.Rarity)
			actionButton.Visible = false
			task.delay(2.5, function()
				infoLabel.TextColor3 = Color3.fromRGB(210, 235, 240)
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

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		screenGui:Destroy()
	end
end)
