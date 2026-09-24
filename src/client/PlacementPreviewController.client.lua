--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Skript: PlacementPreviewController (LocalScript)
	Zuständigkeit:
		Client-Bauplatzierungs-UI: zeigt ein halbtransparentes Vorschau-
		Modell des aktuell gewählten Gebäudes am nächstgelegenen freien/
		belegten Baufeld des eigenen Plots (grün = lokal als gültig
		geschätzt, rot = ungültig), und sendet die Platzierungs-/
		Entfernungsanfrage ERST bei expliziter Bestätigung an den Server.

		GEÄNDERT (UIKit-Umstellung + echte Touch-Steuerung):
			- Der Baumodus ist jetzt ein Opt-in über die MainMenuController-
			  Menüleiste ("Bauen"-Button, Bridge-BindableEvent
			  "ToggleBuildMode") statt permanent aktiv zu sein.
			- Eine über UIKit.Button gebaute Gebäudeauswahl-Leiste
			  (Karten: Name, Kosten, Level-Sperre sichtbar) plus große
			  Drehen-/Bauen-/Abbrechen-/Verkaufen-Buttons, alle über
			  UIKit.Layout.ResponsiveRow (Phone: Spalte, sonst Reihe).
			- PC (echte Tastatur vorhanden): Tasten 1-4/R/Enter/Backspace/
			  Escape funktionieren ZUSÄTZLICH weiter, plus kontinuierliche
			  Maus-Zielhilfe (Vorschau folgt dem Mauszeiger).
			- Touch (Phone/Tablet, keine Maus): Tippen auf den Boden im
			  Baumodus setzt die Vorschau an das nächste Baufeld (kein
			  kontinuierliches "Hover" auf Touch-Geräten, siehe UIKit-Doku
			  "Responsivität"-Regel 5) - Bestätigung weiterhin nur über die
			  großen Buttons.
			- Konsole/Gamepad: die Buttons sind über UIKit.Button nativ
			  Gamepad-navigierbar; zusätzlich zyklen die Schultertasten
			  (L1/R1) durch die Baufelder und die Steuerkreuz-Tasten
			  links/rechts durch die Gebäudeauswahl.

		WICHTIG: Dies ist AUSSCHLIESSLICH visuelles Feedback/Komfort. Die
		Gültigkeitsprüfung hier ist bewusst grob (nur Baufeld-Belegung
		anhand bereits im Workspace sichtbarer Gebäude) und NICHT
		vertrauenswürdig. Ob eine Platzierung wirklich klappt (Kosten,
		Level-Freischaltung, exakte Belegung), entscheidet einzig und
		allein PlacementService auf dem Server; dieses Skript wartet auf
		HabitatRemotes.PlaceBuildingResult/RemoveBuildingResult, um Feedback
		zu geben. Das Level für die Sperr-Anzeige auf den Gebäude-Karten
		kommt aus HUDRemotes (rein informativ, keine Autorität - der
		Server prüft UnlockLevel bei jeder Bauanfrage ohnehin erneut).

	Rojo-Einhängepunkt:
		src/client/PlacementPreviewController.client.lua ->
		StarterPlayer.StarterPlayerScripts.PlacementPreviewController
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BuildingConfig = require(ReplicatedStorage:WaitForChild("BuildingConfig"))
local RaidConfig = require(ReplicatedStorage:WaitForChild("RaidConfig"))
local HabitatRemotes = require(ReplicatedStorage:WaitForChild("HabitatRemotes"))
local HUDRemotes = require(ReplicatedStorage:WaitForChild("HUDRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Layout = UIKit.Layout
local Button = UIKit.Button
local Toast = UIKit.Toast
local Panel = UIKit.Panel
local ScreenFX = UIKit.ScreenFX

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

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

local toggleBuildModeEvent = getOrCreateBridgeEvent("ToggleBuildMode")

-- // Auf eigenen Plot warten ----------------------------------------------
-- Der Server (PlotRegistry) legt ihn erst NACH dem Join unter
-- Workspace.PlayerPlots.<UserId> an; das kann (Datenladen inkl. Retries)
-- ein paar Sekunden dauern.
local playerPlotsFolder = Workspace:WaitForChild("PlayerPlots")
local plot = playerPlotsFolder:WaitForChild(tostring(player.UserId), 30) :: Model?
if not plot then
	warn("[PlacementPreviewController] Kein eigener Plot gefunden - Bauvorschau deaktiviert.")
	return
end

local plotPrimaryPart = plot.PrimaryPart :: BasePart
local buildingsFolder = plot:WaitForChild("Buildings") :: Folder
local assetTemplatesBuildings = ReplicatedStorage:WaitForChild("AssetTemplates"):WaitForChild("Buildings")

-- // Baufelder einlesen (rein lesend, gleiches Attachment-Raster wie der
-- Server über PlotRegistry - siehe HabitatPlotBase.lua) -------------------
type FieldInfo = { Index: number, Attachment: Attachment }

local fields: { FieldInfo } = {}
do
	local fieldCount = plot:GetAttribute("GridFieldCount")
	if type(fieldCount) ~= "number" then
		fieldCount = 6
	end
	for i = 1, fieldCount do
		local attachment = plotPrimaryPart:FindFirstChild("BuildField" .. i)
		if attachment and attachment:IsA("Attachment") then
			table.insert(fields, { Index = i, Attachment = attachment })
		end
	end
end

-- // Spielerlevel (nur für Lock-Anzeige auf den Baukarten, keine Autorität) ----
local playerLevel = 1
task.spawn(function()
	local ok, initialState = pcall(function()
		return HUDRemotes.GetHUDState:InvokeServer()
	end)
	if ok and type(initialState) == "table" and type(initialState.Level) == "number" then
		playerLevel = initialState.Level
	end
end)
HUDRemotes.HUDStateChanged.OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and type(payload.Level) == "number" then
		playerLevel = payload.Level
	end
end)

-- // Vorschau-Modell --------------------------------------------------------
local VALID_COLOR = Color3.fromRGB(90, 235, 140)
local INVALID_COLOR = Color3.fromRGB(235, 90, 90)
local PREVIEW_TRANSPARENCY = 0.55

local previewModel: Model? = nil
local previewBuildingId: string? = nil

local function destroyPreview()
	if previewModel then
		previewModel:Destroy()
		previewModel = nil
	end
end

local function paintPreview(model: Model, valid: boolean)
	local color = if valid then VALID_COLOR else INVALID_COLOR
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Anchored = true
			descendant.Color = color
			descendant.Material = Enum.Material.ForceField
			descendant.Transparency = PREVIEW_TRANSPARENCY
		end
	end
end

local function ensurePreview(buildingId: string): Model?
	if previewModel and previewBuildingId == buildingId then
		return previewModel
	end

	destroyPreview()

	local definition = BuildingConfig.Get(buildingId)
	if not definition then
		return nil
	end

	local template = assetTemplatesBuildings:FindFirstChild(definition.TemplateName)
	if not template or not template:IsA("Model") then
		-- Vorlage noch nicht bereit (AssetTemplateSetup lief noch nicht /
		-- Buildscript nie in Studio ausgeführt) - keine Vorschau möglich,
		-- der Server würde eine echte Anfrage ohnehin mit
		-- "TemplateMissing" ablehnen.
		return nil
	end

	local clone = template:Clone()
	clone.Name = "PlacementPreview"
	paintPreview(clone, false)
	clone.Parent = Workspace

	previewModel = clone
	previewBuildingId = buildingId
	return clone
end

-- // Auswahl-/Rotationszustand ----------------------------------------------
local selectedOrderIndex = 1 -- Index in BuildingConfig.ORDER
local rotationY = 0
local targetField: FieldInfo? = nil
local buildModeActive = false
local previewVisible = true

local function selectedBuildingId(): string
	return BuildingConfig.ORDER[selectedOrderIndex]
end

-- // Belegung anhand bereits im Workspace sichtbarer Gebäude schätzen ------
-- Rein visuell/lokal - der Server führt seine eigene, autoritative
-- Belegungsprüfung unabhängig davon durch (siehe Kopfkommentar).
local function isFieldLocallyOccupied(fieldIndex: number): boolean
	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("FieldIndex") == fieldIndex then
			return true
		end
	end
	return false
end

local function nearestFieldToScreenPoint(screenPoint: Vector2): FieldInfo?
	local viewportRay = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)

	-- Schnittpunkt mit der (horizontalen) Plot-Ebene auf Höhe der
	-- Baufelder berechnen, statt teuer gegen die gesamte Welt zu raycasten
	-- - für die reine Vorschau-Positionierung reicht das.
	local planeY = plotPrimaryPart.Position.Y
	local direction = viewportRay.Direction
	if math.abs(direction.Y) < 1e-4 then
		return nil
	end
	local t = (planeY - viewportRay.Origin.Y) / direction.Y
	if t < 0 then
		return nil
	end
	local hitPoint = viewportRay.Origin + direction * t

	local best: FieldInfo? = nil
	local bestDist = math.huge
	for _, field in ipairs(fields) do
		local worldPos = field.Attachment.WorldPosition
		local dist = (Vector3.new(worldPos.X, planeY, worldPos.Z) - hitPoint).Magnitude
		if dist < bestDist then
			best = field
			bestDist = dist
		end
	end
	return best
end

-- // On-Screen-Feedback (Baumodus-Leiste) -------------------------------------

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlacementHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = false
screenGui.DisplayOrder = 25
Device.ApplySafeArea(screenGui)
screenGui.Enabled = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local uiScale = Instance.new("UIScale")
uiScale.Parent = screenGui
local unbindScale = Device.BindUIScale(uiScale)

local buildBar = Instance.new("Frame")
buildBar.Name = "BuildBar"
buildBar.AnchorPoint = Vector2.new(0.5, 1)
buildBar.BackgroundColor3 = Theme.Background.Panel
buildBar.BackgroundTransparency = 0.06
buildBar.BorderSizePixel = 0
buildBar.Parent = screenGui
Theme.ApplyCorner(buildBar, UDim.new(0, 18))
local buildBarStroke = Theme.ApplyStroke(buildBar, Theme.Neon.ToxicGreen, 2)
buildBarStroke.Transparency = 0.3
Theme.ApplyGradient(buildBar, { Theme.Background.Panel, Theme.Background.Deepest }, 90)

local function applyBuildBarLayout()
	if Device.ShouldUseFullscreenPanels() then
		buildBar.Position = UDim2.new(0.5, 0, 1, -100) -- über der MainMenuBar (siehe MainMenuController)
		buildBar.Size = UDim2.new(1, -16, 0, 300) -- +60px ggü. vorher: Platz für die 5. Aktions-Zeile (Upgrade-Button)
	else
		buildBar.Position = UDim2.new(0.5, 0, 1, -100)
		buildBar.Size = UDim2.fromOffset(620, 260) -- +60px ggü. vorher, siehe oben
	end
end
applyBuildBarLayout()
local buildBarDeviceConnection = Device.Changed:Connect(applyBuildBarLayout)

local infoLabel = Instance.new("TextLabel")
infoLabel.Name = "InfoLabel"
infoLabel.BackgroundTransparency = 1
infoLabel.Position = UDim2.fromOffset(12, 8)
infoLabel.Size = UDim2.new(1, -24, 0, 26)
infoLabel.Font = Theme.Font.Body
infoLabel.TextColor3 = Theme.Text.Secondary
infoLabel.TextWrapped = true
infoLabel.TextScaled = true
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Text = ""
infoLabel.Parent = buildBar
local infoConstraint = Instance.new("UITextSizeConstraint")
infoConstraint.MinTextSize = 11
infoConstraint.MaxTextSize = 15
infoConstraint.Parent = infoLabel

-- // Gebäudeauswahl-Karten ------------------------------------------------------

local cardRowHost = Instance.new("Frame")
cardRowHost.Name = "CardRowHost"
cardRowHost.BackgroundTransparency = 1
cardRowHost.Position = UDim2.fromOffset(0, 40)
cardRowHost.Size = UDim2.new(1, 0, 0, 68)
cardRowHost.Parent = buildBar

local cardRow = Layout.ResponsiveRow({
	Parent = cardRowHost,
	Padding = 8,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
})
cardRow.Frame.Size = UDim2.fromScale(1, 1)

local cardHandles: { any } = {}

local function refreshBuildingCards()
	for index, handle in cardHandles do
		local buildingId = BuildingConfig.ORDER[index]
		local definition = BuildingConfig.Get(buildingId)
		if definition then
			local locked = definition.UnlockLevel > playerLevel
			local prefix = if index == selectedOrderIndex then "▶ " else ""
			local lockSuffix = if locked then ("\n🔒 Lvl " .. tostring(definition.UnlockLevel)) else ""
			handle:SetText(("%s%s\n%d 🌊%s"):format(prefix, definition.DisplayName, definition.Cost, lockSuffix))
			handle:SetDisabled(locked)
		end
	end
end

for index, buildingId in ipairs(BuildingConfig.ORDER) do
	local definition = BuildingConfig.Get(buildingId)
	local card = Button.new({
		Parent = cardRow.Frame,
		Text = definition and definition.DisplayName or buildingId,
		Variant = "Ghost",
		Size = UDim2.fromOffset(120, 64),
		LayoutOrder = index,
	})
	card.Clicked:Connect(function()
		selectedOrderIndex = index
		rotationY = 0
		refreshBuildingCards()
	end)
	cardHandles[index] = card
end

-- // Aktions-Buttons (Drehen/Bauen/Abbrechen/Verkaufen) --------------------------

local actionRowHost = Instance.new("Frame")
actionRowHost.Name = "ActionRowHost"
actionRowHost.BackgroundTransparency = 1
actionRowHost.Position = UDim2.fromOffset(0, 116)
actionRowHost.Size = UDim2.new(1, 0, 0, 172) -- +56px ggü. vorher: Platz für 5 statt 4 Aktions-Buttons (Upgrade ergänzt)
actionRowHost.Parent = buildBar

local actionRow = Layout.ResponsiveRow({
	Parent = actionRowHost,
	Padding = 8,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
})
actionRow.Frame.Size = UDim2.fromScale(1, 1)

local function confirmPlacement()
	if not targetField then
		infoLabel.Text = "No build field targeted."
		return
	end
	HabitatRemotes.RequestPlaceBuilding:FireServer(selectedBuildingId(), targetField.Index, rotationY)
	infoLabel.Text = "Placement requested ..."
end

local function confirmSell()
	if not targetField then
		return
	end
	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("FieldIndex") == targetField.Index then
			local placementId = child:GetAttribute("PlacementId")
			if type(placementId) == "string" then
				HabitatRemotes.RequestRemoveBuilding:FireServer(placementId)
				infoLabel.Text = "Sale requested ..."
			end
			return
		end
	end
	Toast.Show({ Text = "No building on this field.", Type = "Warning", Duration = 2 })
end

-- Gebäude-Upgrade-System (siehe docs/building-upgrades.md): identisches
-- Muster zu confirmSell oben, nur mit RequestUpgradeBuilding statt
-- RequestRemoveBuilding - der Server (PlacementService.RequestUpgrade)
-- validiert Stufe/Level-Anforderung/Kontostand vollständig neu.
local function confirmUpgrade()
	if not targetField then
		return
	end
	for _, child in ipairs(buildingsFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("FieldIndex") == targetField.Index then
			local placementId = child:GetAttribute("PlacementId")
			if type(placementId) == "string" then
				HabitatRemotes.RequestUpgradeBuilding:FireServer(placementId)
				infoLabel.Text = "Upgrade requested..."
			end
			return
		end
	end
	Toast.Show({ Text = "No building on this field.", Type = "Warning", Duration = 2 })
end

local function rotatePreview()
	rotationY = (rotationY + 90) % 360
end

local function exitBuildMode()
	buildModeActive = false
	screenGui.Enabled = false
	destroyPreview()
end

local rotateButton = Button.new({
	Parent = actionRow.Frame,
	Text = "↻ Rotate",
	Variant = "Secondary",
	Size = UDim2.new(0.48, 0, 0, 52),
	LayoutOrder = 1,
})
rotateButton.Clicked:Connect(rotatePreview)

local buildButton = Button.new({
	Parent = actionRow.Frame,
	Text = "✓ Build",
	Variant = "Success",
	Important = true,
	Size = UDim2.new(0.48, 0, 0, 52),
	LayoutOrder = 2,
})
buildButton.Clicked:Connect(confirmPlacement)

local sellButton = Button.new({
	Parent = actionRow.Frame,
	Text = "🗑 Sell",
	Variant = "Danger",
	Size = UDim2.new(0.48, 0, 0, 52),
	LayoutOrder = 3,
})
sellButton.Clicked:Connect(confirmSell)

local cancelButton = Button.new({
	Parent = actionRow.Frame,
	Text = "✕ Done",
	Variant = "Ghost",
	Size = UDim2.new(0.48, 0, 0, 52),
	LayoutOrder = 4,
})
cancelButton.Clicked:Connect(exitBuildMode)

local buildModeUpgradeButton = Button.new({
	Parent = actionRow.Frame,
	Text = "⬆ Upgrade",
	Variant = "Primary",
	Size = UDim2.new(0.48, 0, 0, 52),
	LayoutOrder = 5,
})
buildModeUpgradeButton.Clicked:Connect(confirmUpgrade)

-- // Baumodus umschalten (über MainMenuController-Bridge) ------------------------

local function enterBuildMode()
	buildModeActive = true
	previewVisible = true
	screenGui.Enabled = true
	refreshBuildingCards()
end

local function toggleBuildMode()
	if buildModeActive then
		exitBuildMode()
	else
		enterBuildMode()
	end
end

local bridgeConnection = toggleBuildModeEvent.Event:Connect(toggleBuildMode)

-- // Input: Tastatur (nur zusätzlich, wenn Baumodus aktiv ist) -------------------

local inputBeganConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not buildModeActive then
		return
	end

	-- Touch: Tippen auf den Boden setzt die Vorschau ans nächste Baufeld.
	if input.UserInputType == Enum.UserInputType.Touch and not gameProcessed and Device.IsTouch() then
		local point = Vector2.new(input.Position.X, input.Position.Y)
		local field = nearestFieldToScreenPoint(point)
		if field then
			targetField = field
		end
		return
	end

	if gameProcessed then
		return
	end

	local keyCode = input.KeyCode
	if keyCode == Enum.KeyCode.One then
		selectedOrderIndex = 1
		refreshBuildingCards()
	elseif keyCode == Enum.KeyCode.Two then
		selectedOrderIndex = math.min(2, #BuildingConfig.ORDER)
		refreshBuildingCards()
	elseif keyCode == Enum.KeyCode.Three then
		selectedOrderIndex = math.min(3, #BuildingConfig.ORDER)
		refreshBuildingCards()
	elseif keyCode == Enum.KeyCode.Four then
		selectedOrderIndex = math.min(4, #BuildingConfig.ORDER)
		refreshBuildingCards()
	elseif keyCode == Enum.KeyCode.R then
		rotatePreview()
	elseif keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
		confirmPlacement()
	elseif keyCode == Enum.KeyCode.Backspace or keyCode == Enum.KeyCode.X then
		confirmSell()
	elseif keyCode == Enum.KeyCode.Escape then
		if previewVisible then
			previewVisible = false
			destroyPreview()
		else
			exitBuildMode()
		end
	-- Gamepad: Schultertasten zyklen durch Baufelder, Steuerkreuz links/
	-- rechts durch die Gebäudeauswahl (zusätzlich zur nativen UIKit.Button
	-- Gamepad-Selektion auf den Action-/Karten-Buttons selbst).
	elseif keyCode == Enum.KeyCode.ButtonR1 then
		if #fields > 0 then
			local currentIndex = targetField and table.find(fields, targetField) or 0
			local nextIndex = (currentIndex % #fields) + 1
			targetField = fields[nextIndex]
		end
	elseif keyCode == Enum.KeyCode.ButtonL1 then
		if #fields > 0 then
			local currentIndex = targetField and table.find(fields, targetField) or 1
			local prevIndex = ((currentIndex - 2) % #fields) + 1
			targetField = fields[prevIndex]
		end
	elseif keyCode == Enum.KeyCode.DPadRight then
		selectedOrderIndex = math.min(selectedOrderIndex + 1, #BuildingConfig.ORDER)
		refreshBuildingCards()
	elseif keyCode == Enum.KeyCode.DPadLeft then
		selectedOrderIndex = math.max(selectedOrderIndex - 1, 1)
		refreshBuildingCards()
	end
end)

-- // Laufende Aktualisierung der Vorschau -----------------------------------
local renderConnection = RunService.RenderStepped:Connect(function()
	if not buildModeActive then
		return
	end

	if not previewVisible then
		destroyPreview()
		infoLabel.Text = "Preview hidden (press Esc again to leave build mode)."
		return
	end

	local buildingId = selectedBuildingId()
	local definition = BuildingConfig.Get(buildingId)
	local preview = ensurePreview(buildingId)

	-- Kontinuierliche Maus-Zielhilfe nur auf Geräten mit echter Maus (kein
	-- Touch) - auf Touch-Geräten bestimmt ausschließlich ein expliziter Tap
	-- das Zielfeld (siehe InputBegan oben), siehe UIKit-Doku "Gleiches
	-- Feedback, unterschiedlicher Auslöser".
	if not Device.IsTouch() then
		targetField = nearestFieldToScreenPoint(UserInputService:GetMouseLocation())
	end

	if not preview or not definition then
		infoLabel.Text = "Building template not ready yet ..."
		return
	end

	if definition.UnlockLevel > playerLevel then
		preview.Parent = nil
		infoLabel.Text = ("%s requires level %d (you are level %d)."):format(
			definition.DisplayName,
			definition.UnlockLevel,
			playerLevel
		)
		return
	end

	if not targetField then
		preview.Parent = nil
		infoLabel.Text = ("%s (%d Tide Coins) - no build field targeted."):format(definition.DisplayName, definition.Cost)
		return
	end

	preview.Parent = Workspace
	local worldCFrame = targetField.Attachment.WorldCFrame * CFrame.Angles(0, math.rad(rotationY), 0)
	preview:PivotTo(worldCFrame)

	local occupied = isFieldLocallyOccupied(targetField.Index)
	paintPreview(preview, not occupied)

	infoLabel.Text = ("%s - %d Tide Coins | Field %d %s"):format(
		definition.DisplayName,
		definition.Cost,
		targetField.Index,
		if occupied then "(occupied)" else "(free)"
	)
end)

-- // Gebäude-Upgrade-Panel (klickbar auch AUSSERHALB des Baumodus) ---------------
-- Auftrag Punkt 4: "tapping/clicking a placed building ... opens a small
-- UIKit panel with current stage, next-stage effects, cost, and an Upgrade
-- button". Gilt hier für ALLE Gebäudetypen AUSSER BroodPool - BroodPool hat
-- bereits ein eigenes, Zucht-fokussiertes Klick-Panel (siehe
-- BreedingUIController.client.lua), das den Upgrade-Button/die Stufen-
-- Anzeige dort direkt ergänzt bekommt (kein zweiter ClickDetector auf
-- demselben PrimaryPart, der beide Panels gleichzeitig öffnen würde).
--
-- WICHTIG: rein Anzeige-/Komfort-UI, identisch zum Rest dieses Skripts -
-- die eigentliche Autorität über Kosten/Stufe/Effekt liegt beim Server
-- (PlacementService.RequestUpgrade); dieses Panel liest BuildingConfig/
-- RaidConfig nur zur Vorschau der NÄCHSTEN Stufe.

local UPGRADE_CLICK_MAX_DISTANCE = 20

local upgradePanel = Panel.new({
	Title = "Building Upgrade",
	Closable = true,
	CenteredSize = UDim2.fromOffset(420, 320),
})

local upgradeInfoLabel = Instance.new("TextLabel")
upgradeInfoLabel.Name = "Info"
upgradeInfoLabel.BackgroundTransparency = 1
upgradeInfoLabel.Size = UDim2.new(1, 0, 0, 220)
upgradeInfoLabel.Font = Theme.Font.Body
upgradeInfoLabel.TextWrapped = true
upgradeInfoLabel.TextColor3 = Theme.Text.Secondary
upgradeInfoLabel.TextYAlignment = Enum.TextYAlignment.Top
upgradeInfoLabel.TextXAlignment = Enum.TextXAlignment.Left
upgradeInfoLabel.TextScaled = true
upgradeInfoLabel.Text = ""
upgradeInfoLabel.Parent = upgradePanel.Content
local upgradeInfoConstraint = Instance.new("UITextSizeConstraint")
upgradeInfoConstraint.MinTextSize = 13
upgradeInfoConstraint.MaxTextSize = 18
upgradeInfoConstraint.Parent = upgradeInfoLabel

local panelUpgradeButton = Button.new({
	Parent = upgradePanel.Content,
	Text = "Upgrade",
	Variant = "Success",
	Important = true,
	Size = UDim2.new(1, 0, 0, 48),
	LayoutOrder = 2,
})
panelUpgradeButton.Instance.Position = UDim2.new(0, 0, 1, -48)

local activeUpgradePlacementId: string? = nil
local activeUpgradeBuildingId: string? = nil
local activeUpgradeStage = 1

--- Formatiert die Effekt-Zeile einer Stufe (`stage`) für `buildingId`, rein
--- lesend aus BuildingConfig/RaidConfig - identisches Datenmodell wie
--- Server-seitig IdleIncomeService/RaidService, siehe dort.
local function describeStageEffect(buildingId: string, definition: BuildingConfig.BuildingDefinition, stage: number): string
	if definition.IncomeMultiplierByStage then
		local rate = definition.IncomeRate * BuildingConfig.GetIncomeMultiplier(buildingId, stage)
		return ("%d Tide Coins / minute"):format(math.floor(rate + 0.5))
	end

	local towerStats = RaidConfig.GetTowerStats(buildingId)
	if towerStats then
		local bonus = stage > 1 and definition.TowerStageBonus and definition.TowerStageBonus[stage] or nil
		local damage = towerStats.Damage * (bonus and bonus.DamageMultiplier or 1)
		local fireRate = towerStats.FireRate * (bonus and bonus.FireRateMultiplier or 1)
		local range = towerStats.Range + (bonus and bonus.RangeBonus or 0)
		local text = ("%.0f DPS · Range %.0f"):format(damage * fireRate, range)
		if towerStats.BlockRadius then
			local blockRadius = towerStats.BlockRadius + (bonus and bonus.BlockRadiusBonus or 0)
			text ..= (" · Slow Radius %.0f"):format(blockRadius)
		end
		if towerStats.ChainCount then
			local chainCount = towerStats.ChainCount + (bonus and bonus.ChainCountBonus or 0)
			text ..= (" · Chains to %d"):format(chainCount)
		end
		return text
	end

	return "—"
end

local function refreshUpgradePanel()
	if not activeUpgradePlacementId or not activeUpgradeBuildingId then
		return
	end
	local definition = BuildingConfig.Get(activeUpgradeBuildingId)
	if not definition then
		return
	end

	local currentLine = ("%s — Stage %d/%d\nCurrent: %s"):format(
		definition.DisplayName,
		activeUpgradeStage,
		definition.MaxStage,
		describeStageEffect(activeUpgradeBuildingId, definition, activeUpgradeStage)
	)

	if activeUpgradeStage >= definition.MaxStage then
		upgradeInfoLabel.Text = currentLine .. "\n\nMaximum stage reached."
		panelUpgradeButton:SetText("Max Stage")
		panelUpgradeButton:SetDisabled(true)
		return
	end

	local nextStage = activeUpgradeStage + 1
	local cost = definition.UpgradeCosts[nextStage]
	local nextLine = ("Next: %s"):format(describeStageEffect(activeUpgradeBuildingId, definition, nextStage))

	local costText = "—"
	local buttonCostSuffix = ""
	if cost then
		if cost.AbyssalShards and cost.AbyssalShards > 0 then
			costText = ("%d Tide Coins + %d Abyssal Shards (requires Level %d)"):format(
				cost.TideCoins,
				cost.AbyssalShards,
				cost.LevelRequirement
			)
		else
			costText = ("%d Tide Coins (requires Level %d)"):format(cost.TideCoins, cost.LevelRequirement)
		end
		buttonCostSuffix = (" (%d 🌊)"):format(cost.TideCoins)
	end

	upgradeInfoLabel.Text = ("%s\n\n%s\nCost: %s"):format(currentLine, nextLine, costText)
	panelUpgradeButton:SetText("Upgrade" .. buttonCostSuffix)
	panelUpgradeButton:SetDisabled(false)
end

local function openUpgradePanelFor(model: Model)
	local buildingId = model:GetAttribute("BuildingId")
	local placementId = model:GetAttribute("PlacementId")
	if type(buildingId) ~= "string" or type(placementId) ~= "string" then
		return
	end
	if buildingId == "BroodPool" then
		return -- eigenes Panel, siehe BreedingUIController.client.lua
	end

	activeUpgradeBuildingId = buildingId
	activeUpgradePlacementId = placementId
	local level = model:GetAttribute("Level")
	activeUpgradeStage = if type(level) == "number" then level else 1

	refreshUpgradePanel()
	upgradePanel:Open()
end

panelUpgradeButton.Clicked:Connect(function()
	if not activeUpgradePlacementId then
		return
	end
	panelUpgradeButton:SetDisabled(true)
	HabitatRemotes.RequestUpgradeBuilding:FireServer(activeUpgradePlacementId)
end)

upgradePanel.Closed:Connect(function()
	activeUpgradePlacementId = nil
	activeUpgradeBuildingId = nil
end)

local function ensureBuildingUpgradeClickDetector(model: Model)
	if model:GetAttribute("BuildingId") == "BroodPool" then
		return
	end
	local primaryPart = model.PrimaryPart
	if not primaryPart or primaryPart:FindFirstChildOfClass("ClickDetector") then
		return
	end

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = UPGRADE_CLICK_MAX_DISTANCE
	clickDetector.Parent = primaryPart

	clickDetector.MouseClick:Connect(function(clickingPlayer)
		if clickingPlayer ~= player then
			return
		end
		openUpgradePanelFor(model)
	end)
end

for _, child in ipairs(buildingsFolder:GetChildren()) do
	if child:IsA("Model") then
		ensureBuildingUpgradeClickDetector(child)
	end
end

local buildingsUpgradeChildAddedConnection = buildingsFolder.ChildAdded:Connect(function(child)
	if child:IsA("Model") then
		ensureBuildingUpgradeClickDetector(child)
	end
end)

HabitatRemotes.UpgradeBuildingResult.OnClientEvent:Connect(function(result)
	if not result then
		return
	end

	if result.Success then
		infoLabel.Text = ("Upgraded! New balance: %s Tide Coins."):format(tostring(result.NewBalance))
		Toast.Show({ Text = "Building upgraded!", Type = "Success" })
		ScreenFX.BigMoment(if result.NewStage and result.NewStage >= 3 then Theme.Neon.Violet else Theme.Neon.Cyan)
	else
		infoLabel.Text = ("Upgrade failed: %s"):format(tostring(result.Reason or "Unknown"))
		Toast.Show({ Text = "Upgrade failed.", Type = "Error" })
	end

	if activeUpgradePlacementId and result.PlacementId == activeUpgradePlacementId then
		if result.Success and result.NewStage then
			activeUpgradeStage = result.NewStage
		end
		refreshUpgradePanel()
	end
end)

-- // Server-Ergebnisse (nur Feedback, keine Autorität) ----------------------
HabitatRemotes.PlaceBuildingResult.OnClientEvent:Connect(function(result)
	if result and result.Success then
		infoLabel.Text = ("Built! New balance: %s Tide Coins."):format(tostring(result.NewBalance))
		Toast.Show({ Text = "Building placed!", Type = "Success" })
	else
		infoLabel.Text = ("Build failed: %s"):format(tostring(result and result.Reason or "Unknown"))
		Toast.Show({ Text = "Build failed.", Type = "Error" })
	end
end)

HabitatRemotes.RemoveBuildingResult.OnClientEvent:Connect(function(result)
	if result and result.Success then
		infoLabel.Text = ("Sold! Refund: %s Tide Coins."):format(tostring(result.RefundAmount))
		Toast.Show({ Text = "Building sold.", Type = "Info" })
	else
		infoLabel.Text = ("Sale failed: %s"):format(tostring(result and result.Reason or "Unknown"))
		Toast.Show({ Text = "Sale failed.", Type = "Error" })
	end
end)

-- // Aufräumen -------------------------------------------------------------------

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer ~= player then
		return
	end
	destroyPreview()
	renderConnection:Disconnect()
	inputBeganConnection:Disconnect()
	bridgeConnection:Disconnect()
	buildBarDeviceConnection:Disconnect()
	buildingsUpgradeChildAddedConnection:Disconnect()
	unbindScale()
	cardRow:Destroy()
	actionRow:Destroy()
	for _, handle in cardHandles do
		handle:Destroy()
	end
	rotateButton:Destroy()
	buildButton:Destroy()
	sellButton:Destroy()
	cancelButton:Destroy()
	buildModeUpgradeButton:Destroy()
	panelUpgradeButton:Destroy()
	upgradePanel:Destroy()
	screenGui:Destroy()
end)
