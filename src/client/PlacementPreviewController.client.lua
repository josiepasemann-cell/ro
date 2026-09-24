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
local HabitatRemotes = require(ReplicatedStorage:WaitForChild("HabitatRemotes"))
local HUDRemotes = require(ReplicatedStorage:WaitForChild("HUDRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Device = UIKit.Device
local Layout = UIKit.Layout
local Button = UIKit.Button
local Toast = UIKit.Toast

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
		buildBar.Size = UDim2.new(1, -16, 0, 240)
	else
		buildBar.Position = UDim2.new(0.5, 0, 1, -100)
		buildBar.Size = UDim2.fromOffset(620, 200)
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
actionRowHost.Size = UDim2.new(1, 0, 0, 116)
actionRowHost.Parent = buildBar

local actionRow = Layout.ResponsiveRow({
	Parent = actionRowHost,
	Padding = 8,
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
})
actionRow.Frame.Size = UDim2.fromScale(1, 1)

local function confirmPlacement()
	if not targetField then
		infoLabel.Text = "Kein Baufeld anvisiert."
		return
	end
	HabitatRemotes.RequestPlaceBuilding:FireServer(selectedBuildingId(), targetField.Index, rotationY)
	infoLabel.Text = "Platzierung angefragt ..."
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
				infoLabel.Text = "Verkauf angefragt ..."
			end
			return
		end
	end
	Toast.Show({ Text = "Kein Gebäude auf diesem Feld.", Type = "Warning", Duration = 2 })
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
	Text = "↻ Drehen",
	Variant = "Secondary",
	Size = UDim2.new(0.48, 0, 0, 52),
	LayoutOrder = 1,
})
rotateButton.Clicked:Connect(rotatePreview)

local buildButton = Button.new({
	Parent = actionRow.Frame,
	Text = "✓ Bauen",
	Variant = "Success",
	Important = true,
	Size = UDim2.new(0.48, 0, 0, 52),
	LayoutOrder = 2,
})
buildButton.Clicked:Connect(confirmPlacement)

local sellButton = Button.new({
	Parent = actionRow.Frame,
	Text = "🗑 Verkaufen",
	Variant = "Danger",
	Size = UDim2.new(0.48, 0, 0, 52),
	LayoutOrder = 3,
})
sellButton.Clicked:Connect(confirmSell)

local cancelButton = Button.new({
	Parent = actionRow.Frame,
	Text = "✕ Fertig",
	Variant = "Ghost",
	Size = UDim2.new(0.48, 0, 0, 52),
	LayoutOrder = 4,
})
cancelButton.Clicked:Connect(exitBuildMode)

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
		infoLabel.Text = "Vorschau ausgeblendet (Esc erneut: Baumodus verlassen)."
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
		infoLabel.Text = "Gebäude-Vorlage noch nicht bereit ..."
		return
	end

	if definition.UnlockLevel > playerLevel then
		preview.Parent = nil
		infoLabel.Text = ("%s benötigt Level %d (du bist Level %d)."):format(
			definition.DisplayName,
			definition.UnlockLevel,
			playerLevel
		)
		return
	end

	if not targetField then
		preview.Parent = nil
		infoLabel.Text = ("%s (%d Tide Coins) - kein Baufeld anvisiert."):format(definition.DisplayName, definition.Cost)
		return
	end

	preview.Parent = Workspace
	local worldCFrame = targetField.Attachment.WorldCFrame * CFrame.Angles(0, math.rad(rotationY), 0)
	preview:PivotTo(worldCFrame)

	local occupied = isFieldLocallyOccupied(targetField.Index)
	paintPreview(preview, not occupied)

	infoLabel.Text = ("%s - %d Tide Coins | Feld %d %s"):format(
		definition.DisplayName,
		definition.Cost,
		targetField.Index,
		if occupied then "(belegt)" else "(frei)"
	)
end)

-- // Server-Ergebnisse (nur Feedback, keine Autorität) ----------------------
HabitatRemotes.PlaceBuildingResult.OnClientEvent:Connect(function(result)
	if result and result.Success then
		infoLabel.Text = ("Gebaut! Neuer Kontostand: %s Tide Coins."):format(tostring(result.NewBalance))
		Toast.Show({ Text = "Gebäude platziert!", Type = "Success" })
	else
		infoLabel.Text = ("Bau fehlgeschlagen: %s"):format(tostring(result and result.Reason or "Unbekannt"))
		Toast.Show({ Text = "Bau fehlgeschlagen.", Type = "Error" })
	end
end)

HabitatRemotes.RemoveBuildingResult.OnClientEvent:Connect(function(result)
	if result and result.Success then
		infoLabel.Text = ("Verkauft! Rückerstattung: %s Tide Coins."):format(tostring(result.RefundAmount))
		Toast.Show({ Text = "Gebäude verkauft.", Type = "Info" })
	else
		infoLabel.Text = ("Verkauf fehlgeschlagen: %s"):format(tostring(result and result.Reason or "Unbekannt"))
		Toast.Show({ Text = "Verkauf fehlgeschlagen.", Type = "Error" })
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
	screenGui:Destroy()
end)
