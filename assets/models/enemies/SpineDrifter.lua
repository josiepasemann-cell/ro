--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Raid-Gegner
	Name: SpineDrifter ("Stachel-Treiber")
	Ersetzt ShadowKraken als TemplateName für RaidConfig.EnemyId "Drifter".
	Beschreibung:
		Schlanker, spindeldürrer aalartiger Körper, dunkles Schiefer-Blau,
		dünne Rückenstacheln, rote Glow-Augenschlitze. Dünne Silhouette
		kommuniziert Zerbrechlichkeit - schneller, schwacher "Skirmisher".

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für serverseitige
		  Bewegungs-/Angriffssteuerung (analog zu HumanoidRootPart).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-/
		  Bedrohungs-Puls-Animation.
		- "Mantle", "Eye1", "Eye2" vorhanden -> RaidService.applyEnemyVisual()
		  überschreibt Body/Mantle.Color mit definition.BodyColor und
		  Eye1/Eye2.Color mit definition.EyeColor zur Laufzeit (siehe
		  src/server/RaidService.lua). Hier verwendete Farben sind daher nur
		  Vorschau-Platzhalter, keine Gameplay-Wahrheit.
		- model:SetAttribute("EnemyTier") -> "Trash" (schwacher Skirmisher).
		- model:SetAttribute("Zone") -> Ziel-Zone, in der der Gegner auftaucht.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 5, -60) -- Vor Ausführung anpassen für gewünschte Position
local ENEMY_TIER = "Trash"
local ZONE = "TwilightZone"
-- // ----------------------------------------------------------------------

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function newPart(name, size, cframe, color, material, parent)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local enemiesFolder = getOrCreateFolder(assetsFolder, "Enemies")

local previous = enemiesFolder:FindFirstChild("SpineDrifter")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "SpineDrifter"
model.Parent = enemiesFolder

local SKIN_COLOR = Color3.fromRGB(40, 60, 70)
local ACCENT_COLOR = Color3.fromRGB(28, 44, 52)
local EYE_COLOR = Color3.fromRGB(255, 60, 80)

-- 1) Hauptkörper: schlanker, langgezogener Rumpf --------------------------------
local body = newPart("Body", Vector3.new(1.4, 1.4, 4.0), ORIGIN, SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Kopf-/Mantel-Verjüngung vorn (leicht dunkler) --------------------------------
local mantleCFrame = ORIGIN * CFrame.new(0, 0.1, -2.1)
newPart("Mantle", Vector3.new(0.9, 0.9, 1.3), mantleCFrame, ACCENT_COLOR, Enum.Material.SmoothPlastic, model)

-- 3) Glühende Augenschlitze -------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.45, 0.15, -2.6)
	local eye = newPart("Eye" .. i, Vector3.new(0.5, 0.15, 0.2), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.CanCollide = false
end

-- 4) Dünne Rückenstacheln (6 Stück, abnehmend zum Schwanz, WedgeParts entlang des Rückens) --
for i = 1, 6 do
	local z = -1.7 + (i - 1) * 0.75
	local spineHeight = 0.7 - i * 0.05
	local spineCFrame = ORIGIN * CFrame.new(0, 0.85, z) * CFrame.Angles(math.rad(90), 0, 0)
	local spine = Instance.new("WedgePart")
	spine.Name = "DorsalSpine" .. i
	spine.Size = Vector3.new(0.15, spineHeight, 0.55)
	spine.CFrame = spineCFrame
	spine.Color = i % 2 == 0 and ACCENT_COLOR or EYE_COLOR
	spine.Material = i % 2 == 0 and Enum.Material.SmoothPlastic or Enum.Material.Neon
	spine.Anchored = true
	spine.CanCollide = false
	spine.TopSurface = Enum.SurfaceType.Smooth
	spine.BottomSurface = Enum.SurfaceType.Smooth
	spine.Parent = model
end

-- 5) Seitliche Steuerflossen (dünn, knapp an der Körpermitte anliegend) ------------
for _, side in ipairs({ -1, 1 }) do
	local finCFrame = ORIGIN * CFrame.new(side * 0.75, -0.1, -0.3) * CFrame.Angles(0, 0, math.rad(side * 20))
	local fin = Instance.new("WedgePart")
	fin.Name = "SideFin" .. (side < 0 and "L" or "R")
	fin.Size = Vector3.new(0.75, 0.1, 0.9)
	fin.CFrame = finCFrame * CFrame.Angles(0, 0, math.rad(90))
	fin.Color = ACCENT_COLOR
	fin.Material = Enum.Material.SmoothPlastic
	fin.Anchored = true
	fin.CanCollide = false
	fin.TopSurface = Enum.SurfaceType.Smooth
	fin.BottomSurface = Enum.SurfaceType.Smooth
	fin.Parent = model
end

-- 6) Schwanzstiel (verjüngendes Segment, schließt die Lücke Body -> Flosse) --------
newPart("TailStalk", Vector3.new(0.55, 0.55, 1.3), ORIGIN * CFrame.new(0, 0, 2.45), ACCENT_COLOR, Enum.Material.SmoothPlastic, model)

-- 7) Schwanzflosse (überlappt den Stiel, gefächertes Doppel-Wedge) -----------------
local tailBaseCFrame = ORIGIN * CFrame.new(0, 0, 2.9)
local tailFin = Instance.new("WedgePart")
tailFin.Name = "TailFin"
tailFin.Size = Vector3.new(0.1, 1.2, 1.1)
tailFin.CFrame = tailBaseCFrame * CFrame.Angles(0, math.rad(90), 0)
tailFin.Color = ACCENT_COLOR
tailFin.Material = Enum.Material.SmoothPlastic
tailFin.Anchored = true
tailFin.CanCollide = false
tailFin.TopSurface = Enum.SurfaceType.Smooth
tailFin.BottomSurface = Enum.SurfaceType.Smooth
tailFin.Parent = model

local tailFinLower = Instance.new("WedgePart")
tailFinLower.Name = "TailFinLower"
tailFinLower.Size = Vector3.new(0.1, 0.7, 0.8)
tailFinLower.CFrame = tailBaseCFrame * CFrame.new(0, -0.55, 0.1) * CFrame.Angles(0, math.rad(-90), 0)
tailFinLower.Color = EYE_COLOR
tailFinLower.Material = Enum.Material.Neon
tailFinLower.Anchored = true
tailFinLower.CanCollide = false
tailFinLower.TopSurface = Enum.SurfaceType.Smooth
tailFinLower.BottomSurface = Enum.SurfaceType.Smooth
tailFinLower.Parent = model

-- 6) Idle-/Bedrohungs-Puls-Attachment -------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("EnemyTier", ENEMY_TIER)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("EnemyName", "Stachel-Treiber")

print("[Abyssara] SpineDrifter created under Workspace.Assets.Enemies")
