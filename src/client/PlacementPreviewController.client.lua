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
			  Drehen-/Bauen-/Upgrade-/Verkaufen-/Fertig-Buttons (siehe
			  GERÄTE-LAYOUT unten).
			- PC (echte Tastatur vorhanden): Tasten 1-4/R/Enter/Backspace/
			  Escape funktionieren ZUSÄTZLICH weiter, plus kontinuierliche
			  Maus-Zielhilfe (Vorschau folgt dem Mauszeiger).
			- Touch (Phone/Tablet, keine Maus): Tippen auf den Boden im
			  Baumodus setzt die Vorschau an das nächste Baufeld (kein
			  kontinuierliches "Hover" auf Touch-Geräten, siehe UIKit-Doku
			  "Responsivität"-Regel 5) - Bestätigung weiterhin nur über die
			  großen Buttons.
			- Konsole/Gamepad: OHNE UI-Fokus bedienbar (die Spielfigur bleibt
			  steuerbar): L1/R1 wechseln das Baufeld (Feld-Cursor), D-Pad
			  links/rechts das Gebäude, X baut, Y dreht, B beendet den
			  Baumodus (ContextActionService, nur solange der Baumodus aktiv
			  ist). Die Buttons bleiben zusätzlich per Fokus (Y-Menü) erreichbar.
			  Die Maus-Zielhilfe läuft NUR im Tastatur/Maus-Modus, sonst würde
			  sie den Gamepad-/Touch-Cursor jeden Frame überschreiben.

			GERÄTE-LAYOUT der Baumodus-Leiste: eine Info-Zeile, eine horizontal
			scrollbare Reihe Gebäudekarten, EINE Reihe mit 5 Aktions-Buttons
			(Icon + kurzes Wort, 2 Zeilen). Desktop: 620 px breit, über der
			Menüleiste. Touch hochkant: volle Breite, ÜBER der Daumenstick-/
			Sprungknopf-Zone. Touch quer: zwischen den Zonen (schmaler).
			Tasten-Chips (1-4, R, Enter, X, Esc bzw. Y/X/B) an den Buttons folgen
			der zuletzt benutzten Eingabe. Touch-Tipps auf den Boden nutzen
			ScreenPointToRay (berücksichtigt den Topbar-Inset).

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
local ContextActionService = game:GetService("ContextActionService")
local Workspace = game:GetService("Workspace")

local BuildingConfig = require(ReplicatedStorage:WaitForChild("BuildingConfig"))
local RaidConfig = require(ReplicatedStorage:WaitForChild("RaidConfig"))
local HabitatRemotes = require(ReplicatedStorage:WaitForChild("HabitatRemotes"))
local HUDRemotes = require(ReplicatedStorage:WaitForChild("HUDRemotes"))
local TravelRemotes = require(ReplicatedStorage:WaitForChild("TravelRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local InputMode = UIKit.InputMode
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
local plotOrNil = playerPlotsFolder:WaitForChild(tostring(player.UserId), 30) :: Model?
while not plotOrNil do
	-- Datenladen (DataStore-Retries) kann laenger als 30 s dauern - weiter
	-- warten statt den Baumodus dauerhaft abzuschalten.
	warn("[PlacementPreviewController] Own plot not replicated yet - still waiting.")
	plotOrNil = playerPlotsFolder:WaitForChild(tostring(player.UserId), 60) :: Model?
end
local plot = (plotOrNil :: any) :: Model

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

-- `isInputPosition` = true für InputObject.Position (Touch): diese Koordinaten
-- liegen UNTER der Topbar (ohne GuiInset) und brauchen ScreenPointToRay.
-- UserInputService:GetMouseLocation() ist dagegen ein Viewport-Punkt.
local function nearestFieldToScreenPoint(screenPoint: Vector2, isInputPosition: boolean?): FieldInfo?
	local viewportRay = if isInputPosition
		then camera:ScreenPointToRay(screenPoint.X, screenPoint.Y)
		else camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)

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

local scaledRoot, unbindScale = Device.CreateScaledRoot(screenGui)

local BAR_HEIGHT = 168
local CARD_ROW_HEIGHT = 60
local ACTION_ROW_HEIGHT = 56

local buildBar = Instance.new("Frame")
buildBar.Name = "BuildBar"
buildBar.AnchorPoint = Vector2.new(0.5, 1)
buildBar.BackgroundColor3 = Theme.Background.Panel
buildBar.BackgroundTransparency = 0.06
buildBar.BorderSizePixel = 0
buildBar.Active = true -- Tippen auf die Leiste soll kein Baufeld im Boden wählen
buildBar.Parent = scaledRoot
Theme.ApplyCorner(buildBar, UDim.new(0, 18))
local buildBarStroke = Theme.ApplyStroke(buildBar, Theme.Neon.ToxicGreen, 2)
buildBarStroke.Transparency = 0.3
Theme.ApplyGradient(buildBar, { Theme.Background.Panel, Theme.Background.Deepest }, 90)

local cardActionButtons: { any } = {}
local actionButtonList: { any } = {}

local function applyBuildBarLayout()
	local viewport = Device.GetVirtualViewport()
	if Device.IsTouchPrimary() then
		local sideInset, bottomInset = Device.GetBottomDockInsets()
		-- Hochformat: volle Breite ÜBER der Stick-/Sprungknopf-Zone.
		-- Querformat: zwischen den Zonen (mind. 320 px, damit 5 Buttons passen).
		local width = math.max(320, math.min(620, viewport.X - sideInset * 2 - 16))
		buildBar.Size = UDim2.fromOffset(width, BAR_HEIGHT)
		buildBar.Position = UDim2.new(0.5, 0, 1, -(bottomInset + 8))
	else
		-- Über der unten mittigen Menüleiste (76 px + 18 px Rand + Lücke).
		buildBar.Size = UDim2.fromOffset(620, BAR_HEIGHT)
		buildBar.Position = UDim2.new(0.5, 0, 1, -104)
	end
end
applyBuildBarLayout()
local buildBarDeviceConnection = Device.Changed:Connect(applyBuildBarLayout)

local infoLabel = Instance.new("TextLabel")
infoLabel.Name = "InfoLabel"
infoLabel.BackgroundTransparency = 1
infoLabel.Position = UDim2.fromOffset(12, 6)
infoLabel.Size = UDim2.new(1, -24, 0, 24)
infoLabel.Font = Theme.Font.Body
infoLabel.TextColor3 = Theme.Text.Secondary
infoLabel.TextWrapped = true
infoLabel.TextScaled = true
infoLabel.TextXAlignment = Enum.TextXAlignment.Left
infoLabel.Text = ""
infoLabel.Parent = buildBar
local infoConstraint = Instance.new("UITextSizeConstraint")
infoConstraint.MinTextSize = 12
infoConstraint.MaxTextSize = 15
infoConstraint.Parent = infoLabel

-- Kleiner Helfer: Tasten-Chip links oben an einem Button (nur im passenden Eingabemodus sichtbar).
local function attachHint(handle: any, keyboard: string?, gamepad: Enum.KeyCode?)
	local hint = InputMode.CreateHint({
		Parent = handle.Instance,
		Keyboard = keyboard,
		Gamepad = gamepad,
		Position = UDim2.fromOffset(-3, -10),
		ZIndex = 20,
	})
	table.insert(cardActionButtons, hint)
end

-- Kleinere Beschriftung (Icon + Wort, 2 Zeilen), damit 5 Buttons in 320 px passen.
local function styleCompactLabel(handle: any)
	local label = handle.Instance:FindFirstChild("Label") :: TextLabel?
	if not label then
		return
	end
	label.TextWrapped = true
	label.Position = UDim2.fromOffset(2, 2)
	label.Size = UDim2.new(1, -4, 1, -4)
	local constraint = label:FindFirstChildOfClass("UITextSizeConstraint")
	if constraint then
		constraint.MinTextSize = 12
		constraint.MaxTextSize = 15
	end
end

-- // Gebäudeauswahl-Karten (horizontal scrollbar) ------------------------------------

local cardScroller = Instance.new("ScrollingFrame")
cardScroller.Name = "CardScroller"
cardScroller.BackgroundTransparency = 1
cardScroller.BorderSizePixel = 0
cardScroller.Position = UDim2.fromOffset(10, 36)
cardScroller.Size = UDim2.new(1, -20, 0, CARD_ROW_HEIGHT + 8)
cardScroller.CanvasSize = UDim2.new()
cardScroller.AutomaticCanvasSize = Enum.AutomaticSize.X
cardScroller.ScrollingDirection = Enum.ScrollingDirection.X
cardScroller.ScrollBarThickness = 0
cardScroller.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
cardScroller.Parent = buildBar

local cardList = Instance.new("UIListLayout")
cardList.FillDirection = Enum.FillDirection.Horizontal
cardList.SortOrder = Enum.SortOrder.LayoutOrder
cardList.Padding = UDim.new(0, 8)
cardList.VerticalAlignment = Enum.VerticalAlignment.Bottom
cardList.Parent = cardScroller

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
		Parent = cardScroller,
		Text = definition and definition.DisplayName or buildingId,
		Variant = "Ghost",
		Size = UDim2.fromOffset(124, CARD_ROW_HEIGHT),
		LayoutOrder = index,
	})
	styleCompactLabel(card)
	card.Clicked:Connect(function()
		selectedOrderIndex = index
		rotationY = 0
		refreshBuildingCards()
	end)
	cardHandles[index] = card
	if index <= 4 then
		attachHint(card, tostring(index), nil)
	end
end

-- // Aktions-Buttons (Drehen/Bauen/Upgrade/Verkaufen/Fertig) ----------------------------

local actionRow = Instance.new("Frame")
actionRow.Name = "ActionRow"
actionRow.BackgroundTransparency = 1
actionRow.Position = UDim2.new(0, 10, 1, -(ACTION_ROW_HEIGHT + 10))
actionRow.Size = UDim2.new(1, -20, 0, ACTION_ROW_HEIGHT)
actionRow.Parent = buildBar

local actionList = Instance.new("UIListLayout")
actionList.FillDirection = Enum.FillDirection.Horizontal
actionList.SortOrder = Enum.SortOrder.LayoutOrder
actionList.Padding = UDim.new(0, 6)
actionList.VerticalAlignment = Enum.VerticalAlignment.Center
actionList.Parent = actionRow

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

local unbindBuildActions: () -> ()

local function exitBuildMode()
	buildModeActive = false
	screenGui.Enabled = false
	destroyPreview()
	unbindBuildActions()
end

local function makeActionButton(text: string, variant: string, order: number, important: boolean?): any
	local handle = Button.new({
		Parent = actionRow,
		Text = text,
		Variant = variant :: any,
		Important = important,
		Size = UDim2.new(0.2, -5, 1, 0),
		LayoutOrder = order,
	})
	styleCompactLabel(handle)
	table.insert(actionButtonList, handle)
	return handle
end

local rotateButton = makeActionButton("↻\nRotate", "Secondary", 1)
rotateButton.Clicked:Connect(rotatePreview)
attachHint(rotateButton, "R", Enum.KeyCode.ButtonY)

local buildButton = makeActionButton("✓\nBuild", "Success", 2, true)
buildButton.Clicked:Connect(confirmPlacement)
attachHint(buildButton, "Enter", Enum.KeyCode.ButtonX)

local buildModeUpgradeButton = makeActionButton("⬆\nUpgrade", "Primary", 3)
buildModeUpgradeButton.Clicked:Connect(confirmUpgrade)

local sellButton = makeActionButton("🗑\nSell", "Danger", 4)
sellButton.Clicked:Connect(confirmSell)
attachHint(sellButton, "X", nil)

local cancelButton = makeActionButton("✕\nDone", "Ghost", 5)
cancelButton.Clicked:Connect(exitBuildMode)
attachHint(cancelButton, "Esc", Enum.KeyCode.ButtonB)

-- // Baumodus umschalten (über MainMenuController-Bridge) ------------------------

local FAR_FROM_PLOT_STUDS = 90

-- Gamepad-Aktionen NUR solange der Baumodus aktiv ist (Priorität knapp unter
-- Panels/Menü-Zurück, damit B dort zuerst das offene Panel schließt):
-- X = Bauen, Y = Drehen, B = Baumodus beenden.
local BUILD_ACTION_NAME = "AbyssaraBuildMode"
local buildActionsBound = false

local function onBuildAction(_actionName: string, inputState: Enum.UserInputState, inputObject: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Sink
	end
	if not buildModeActive then
		return Enum.ContextActionResult.Pass
	end
	if inputObject.KeyCode == Enum.KeyCode.ButtonX then
		confirmPlacement()
	elseif inputObject.KeyCode == Enum.KeyCode.ButtonY then
		rotatePreview()
	elseif inputObject.KeyCode == Enum.KeyCode.ButtonB then
		exitBuildMode()
	end
	return Enum.ContextActionResult.Sink
end

local function bindBuildActions()
	if buildActionsBound then
		return
	end
	buildActionsBound = true
	ContextActionService:BindActionAtPriority(
		BUILD_ACTION_NAME,
		onBuildAction,
		false,
		Enum.ContextActionPriority.High.Value - 2,
		Enum.KeyCode.ButtonX,
		Enum.KeyCode.ButtonY,
		Enum.KeyCode.ButtonB
	)
end

unbindBuildActions = function()
	if not buildActionsBound then
		return
	end
	buildActionsBound = false
	ContextActionService:UnbindAction(BUILD_ACTION_NAME)
end

local function enterBuildMode()
	buildModeActive = true
	previewVisible = true
	screenGui.Enabled = true
	refreshBuildingCards()
	bindBuildActions()

	-- Touch/Gamepad haben keinen Mauszeiger: gleich das erste freie Baufeld
	-- vorwaehlen, damit "Build" sofort etwas tut (statt "no build field
	-- targeted"). Mit Maus ueberschreibt der RenderStepped-Loop das laufend.
	if not targetField then
		for _, field in ipairs(fields) do
			if not isFieldLocallyOccupied(field.Index) then
				targetField = field
				break
			end
		end
		if not targetField then
			targetField = fields[1]
		end
	end

	-- Steht der Spieler noch im Hub (Plot liegt weit weg), sieht er die
	-- Bauvorschau gar nicht - dann direkt zum eigenen Plot bringen.
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and (root.Position - plotPrimaryPart.Position).Magnitude > FAR_FROM_PLOT_STUDS then
		TravelRemotes.RequestTravelToPlot:FireServer()
		Toast.Show({ Text = "Taking you to your reef plot to build ...", Type = "Info", Duration = 3 })
	end
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

	-- Touch: Tippen auf den Boden setzt die Vorschau ans nächste Baufeld
	-- (nicht, wenn das Tippen von der UI geschluckt wurde).
	if input.UserInputType == Enum.UserInputType.Touch then
		if not gameProcessed then
			local point = Vector2.new(input.Position.X, input.Position.Y)
			local field = nearestFieldToScreenPoint(point, true)
			if field then
				targetField = field
			end
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
		infoLabel.Text = ("Preview hidden (press %s again to leave build mode)."):format(
			InputMode.Pick("Esc", "B", "Done")
		)
		return
	end

	local buildingId = selectedBuildingId()
	local definition = BuildingConfig.Get(buildingId)
	local preview = ensurePreview(buildingId)

	-- Kontinuierliche Maus-Zielhilfe NUR im Tastatur/Maus-Modus. Bei Touch
	-- bestimmt ein expliziter Tap das Zielfeld (siehe InputBegan oben), bei
	-- Gamepad L1/R1 - die Maus-Position würde diesen Cursor sonst jeden Frame
	-- überschreiben (Konsole!).
	if InputMode.IsKeyboardMouse() then
		local hovered = nearestFieldToScreenPoint(UserInputService:GetMouseLocation())
		if hovered then
			targetField = hovered
		end
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
upgradeInfoConstraint.MinTextSize = 14
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

-- ProximityPrompts fürs Upgrade-Panel: ein ClickDetector funktioniert mit
-- Maus/Touch, aber NICHT mit dem Gamepad. Der Prompt ist deshalb nur im
-- Gamepad-Modus aktiv (sonst würde er bei jedem Gebäude Bildschirmplatz
-- belegen).
local upgradePrompts: { ProximityPrompt } = {}

InputMode.Changed:Connect(function(mode)
	for index = #upgradePrompts, 1, -1 do
		local prompt = upgradePrompts[index]
		if prompt.Parent then
			prompt.Enabled = mode == "Gamepad"
		else
			table.remove(upgradePrompts, index)
		end
	end
end)

local function ensureBuildingUpgradeClickDetector(model: Model)
	if model:GetAttribute("BuildingId") == "BroodPool" then
		return
	end
	local primaryPart = model.PrimaryPart
	if not primaryPart or primaryPart:FindFirstChildOfClass("ClickDetector") then
		return
	end

	local upgradePrompt = Instance.new("ProximityPrompt")
	upgradePrompt.Name = "UpgradePrompt"
	upgradePrompt.ActionText = "Upgrade"
	local definition = BuildingConfig.Get(model:GetAttribute("BuildingId") :: any)
	upgradePrompt.ObjectText = if definition then definition.DisplayName else "Building"
	upgradePrompt.HoldDuration = 0
	upgradePrompt.MaxActivationDistance = 10
	upgradePrompt.RequiresLineOfSight = false
	upgradePrompt.KeyboardKeyCode = Enum.KeyCode.E
	upgradePrompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	upgradePrompt.Enabled = InputMode.IsGamepad()
	upgradePrompt.Parent = primaryPart
	table.insert(upgradePrompts, upgradePrompt)
	upgradePrompt.Triggered:Connect(function(triggeringPlayer: Player)
		if triggeringPlayer == player then
			openUpgradePanelFor(model)
		end
	end)

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

-- Server-Reason-Codes in kindgerechte Saetze uebersetzen (nie rohe Codes zeigen).
local FAILURE_TEXT: { [string]: string } = {
	InsufficientFunds = "Not enough Tide Coins yet!",
	FieldOccupied = "There is already a building on this field.",
	InvalidField = "Pick one of the glowing build fields.",
	LevelTooLow = "You need a higher level for that.",
	BroodPoolLimitReached = "You can't build another Brood Pool yet - reach level 6 for a second one!",
	TemplateMissing = "That building isn't ready yet. Try again in a moment.",
	NoPlot = "Your plot isn't ready yet. Try again in a moment.",
	DataNotLoaded = "Still loading your reef ... try again in a moment.",
	MaxStageReached = "This building is already at its maximum stage!",
	IncubationActive = "Collect the egg from this Brood Pool first, then upgrade.",
	NotFound = "There is no building there.",
	InvalidPlacement = "There is no building there.",
}

local function friendlyFailure(reason: any, fallback: string): string
	return FAILURE_TEXT[tostring(reason)] or fallback
end

HabitatRemotes.UpgradeBuildingResult.OnClientEvent:Connect(function(result)
	if not result then
		return
	end

	if result.Success then
		infoLabel.Text = ("Upgraded! New balance: %s Tide Coins."):format(tostring(result.NewBalance))
		Toast.Show({ Text = "Building upgraded!", Type = "Success" })
		ScreenFX.BigMoment(if result.NewStage and result.NewStage >= 3 then Theme.Neon.Violet else Theme.Neon.Cyan)
	else
		local text = friendlyFailure(result.Reason, "Couldn't upgrade that. Please try again.")
		infoLabel.Text = text
		Toast.Show({ Text = text, Type = "Error" })
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
		local text = friendlyFailure(result and result.Reason, "Couldn't build that. Please try again.")
		infoLabel.Text = text
		Toast.Show({ Text = text, Type = "Error" })
	end
end)

HabitatRemotes.RemoveBuildingResult.OnClientEvent:Connect(function(result)
	if result and result.Success then
		infoLabel.Text = ("Sold! Refund: %s Tide Coins."):format(tostring(result.RefundAmount))
		Toast.Show({ Text = "Building sold.", Type = "Info" })
	else
		local text = friendlyFailure(result and result.Reason, "Couldn't sell that. Please try again.")
		infoLabel.Text = text
		Toast.Show({ Text = text, Type = "Error" })
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
	unbindBuildActions()
	for _, hint in cardActionButtons do
		hint:Destroy()
	end
	for _, handle in cardHandles do
		handle:Destroy()
	end
	for _, handle in actionButtonList do
		handle:Destroy()
	end
	panelUpgradeButton:Destroy()
	upgradePanel:Destroy()
	screenGui:Destroy()
end)
