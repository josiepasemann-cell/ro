--[[
	Abyssara – Deep Tide Tycoon
	Skript: PlacementPreviewController (LocalScript)
	Zuständigkeit:
		Einfaches Client-Bauplatzierungs-UI für das MVP: zeigt ein
		halbtransparentes Vorschau-Modell des aktuell gewählten Gebäudes am
		nächstgelegenen freien/belegten Baufeld des eigenen Plots (grün =
		lokal als gültig geschätzt, rot = ungültig), und sendet die
		Platzierungs-/Entfernungsanfrage ERST bei expliziter Bestätigung an
		den Server.

		WICHTIG: Dies ist AUSSCHLIESSLICH visuelles Feedback/Komfort. Die
		Gültigkeitsprüfung hier ist bewusst grob (nur Baufeld-Belegung
		anhand bereits im Workspace sichtbarer Gebäude - siehe unten) und
		NICHT vertrauenswürdig. Ob eine Platzierung wirklich klappt
		(Kosten, Level-Freischaltung, exakte Belegung), entscheidet einzig
		und allein PlacementService auf dem Server; dieses Skript wartet
		auf HabitatRemotes.PlaceBuildingResult/RemoveBuildingResult, um die
		Vorschau ggf. zu korrigieren.

		Bewusst schlank gehalten (kein grafisches Baumenü): Zahlen-Tasten
		1-4 wählen ein Gebäude aus BuildingConfig.ORDER, R rotiert die
		Vorschau in 90°-Schritten, Enter bestätigt den Bau,
		Backspace/X verkauft das Gebäude am aktuell anvisierten Baufeld,
		Escape blendet die Vorschau aus. Ein einfaches On-Screen-Label
		zeigt Auswahl/letztes Server-Ergebnis.

	Rojo-Einhängepunkt:
		src/client/PlacementPreviewController.client.lua ->
		StarterPlayer.StarterPlayerScripts.PlacementPreviewController
		(".client.lua"-Suffix signalisiert Rojo, hieraus ein `LocalScript`
		zu machen.)
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BuildingConfig = require(ReplicatedStorage:WaitForChild("BuildingConfig"))
local HabitatRemotes = require(ReplicatedStorage:WaitForChild("HabitatRemotes"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

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

-- // Einfaches On-Screen-Feedback ------------------------------------------
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "PlacementHud"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.Parent = player:WaitForChild("PlayerGui")

local label = Instance.new("TextLabel")
label.Name = "PlacementLabel"
label.AnchorPoint = Vector2.new(0.5, 1)
label.Position = UDim2.new(0.5, 0, 1, -16)
label.Size = UDim2.new(0, 520, 0, 60)
label.BackgroundColor3 = Color3.fromRGB(10, 20, 28)
label.BackgroundTransparency = 0.25
label.TextColor3 = Color3.fromRGB(220, 245, 250)
label.Font = Enum.Font.GothamMedium
label.TextSize = 16
label.TextWrapped = true
label.Text = ""
label.Parent = screenGui

local function setLabel(text: string)
	label.Text = text
end

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

local function nearestFieldToMouse(): FieldInfo?
	local mouseLocation = UserInputService:GetMouseLocation()
	local viewportRay = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)

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

-- // Aktionen ---------------------------------------------------------------
local function confirmPlacement()
	if not targetField then
		setLabel("Kein Baufeld anvisiert.")
		return
	end
	HabitatRemotes.RequestPlaceBuilding:FireServer(selectedBuildingId(), targetField.Index, rotationY)
	setLabel("Platzierung angefragt ...")
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
				setLabel("Verkauf angefragt ...")
			end
			return
		end
	end
end

-- // Input --------------------------------------------------------------
local previewVisible = true

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then
		return
	end

	local keyCode = input.KeyCode
	if keyCode == Enum.KeyCode.One then
		selectedOrderIndex = 1
	elseif keyCode == Enum.KeyCode.Two then
		selectedOrderIndex = math.min(2, #BuildingConfig.ORDER)
	elseif keyCode == Enum.KeyCode.Three then
		selectedOrderIndex = math.min(3, #BuildingConfig.ORDER)
	elseif keyCode == Enum.KeyCode.Four then
		selectedOrderIndex = math.min(4, #BuildingConfig.ORDER)
	elseif keyCode == Enum.KeyCode.R then
		rotationY = (rotationY + 90) % 360
	elseif keyCode == Enum.KeyCode.Return or keyCode == Enum.KeyCode.KeypadEnter then
		confirmPlacement()
	elseif keyCode == Enum.KeyCode.Backspace or keyCode == Enum.KeyCode.X then
		confirmSell()
	elseif keyCode == Enum.KeyCode.Escape then
		previewVisible = not previewVisible
	end
end)

-- // Laufende Aktualisierung der Vorschau -----------------------------------
RunService.RenderStepped:Connect(function()
	if not previewVisible then
		destroyPreview()
		setLabel("Vorschau ausgeblendet (Esc zum Einblenden).")
		return
	end

	local buildingId = selectedBuildingId()
	local definition = BuildingConfig.Get(buildingId)
	local preview = ensurePreview(buildingId)
	targetField = nearestFieldToMouse()

	if not preview or not definition then
		setLabel("Gebäude-Vorlage noch nicht bereit ...")
		return
	end

	if not targetField then
		preview.Parent = nil
		setLabel(("%s (%d Tide Coins) - kein Baufeld anvisiert."):format(definition.DisplayName, definition.Cost))
		return
	end

	preview.Parent = Workspace
	local worldCFrame = targetField.Attachment.WorldCFrame * CFrame.Angles(0, math.rad(rotationY), 0)
	preview:PivotTo(worldCFrame)

	local occupied = isFieldLocallyOccupied(targetField.Index)
	paintPreview(preview, not occupied)

	setLabel(
		("[%d/%d] %s - %d Tide Coins | Feld %d %s | R: rotieren, Enter: bauen, Backspace: verkaufen"):format(
			selectedOrderIndex,
			#BuildingConfig.ORDER,
			definition.DisplayName,
			definition.Cost,
			targetField.Index,
			if occupied then "(belegt)" else "(frei)"
		)
	)
end)

-- // Server-Ergebnisse (nur Feedback, keine Autorität) ----------------------
HabitatRemotes.PlaceBuildingResult.OnClientEvent:Connect(function(result)
	if result and result.Success then
		setLabel(("Gebaut! Neuer Kontostand: %s Tide Coins."):format(tostring(result.NewBalance)))
	else
		setLabel(("Bau fehlgeschlagen: %s"):format(tostring(result and result.Reason or "Unbekannt")))
	end
end)

HabitatRemotes.RemoveBuildingResult.OnClientEvent:Connect(function(result)
	if result and result.Success then
		setLabel(("Verkauft! Rückerstattung: %s Tide Coins."):format(tostring(result.RefundAmount)))
	else
		setLabel(("Verkauf fehlgeschlagen: %s"):format(tostring(result and result.Reason or "Unbekannt")))
	end
end)

Players.PlayerRemoving:Connect(function(leavingPlayer)
	if leavingPlayer == player then
		destroyPreview()
	end
end)
