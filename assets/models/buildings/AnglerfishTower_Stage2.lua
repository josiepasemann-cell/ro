--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude / Verteidigungsturm (Upgrade-Stufe)
	Name: AnglerfishTower_Stage2 ("Anglerfisch-Turm", Stufe 2/3)
	Beschreibung:
		Höherer Turmschaft (4 statt 3 Segmente) mit 4 dekorativen Rücken-
		flossen, größerer/hellerer Köder-Orb an der Spitze der Illicium-Rute.

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "AnglerfishTower_Stage2" (BuildingId "AnglerfishTower"
		  + "_Stage2").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  AnglerfishTower.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "AnglerfishTower", "Stage" = 2.
		- "LureOrb": Neon-Part (Köder-Leuchtkugel), unverändert benannt,
		  Referenzpunkt für Ziel-/Schuss-Effekte im Trench-Raid-System.
		- Attachment "MuzzlePoint" an LureOrb: Ursprungspunkt für Projektile
		  (unverändert, siehe src/server/RaidService.lua getTowerOriginPosition).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(45, 1.5, -140) -- Vor Ausführung anpassen für gewünschte Position
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
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local buildingsFolder = getOrCreateFolder(assetsFolder, "Buildings")

local previous = buildingsFolder:FindFirstChild("AnglerfishTower_Stage2")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "AnglerfishTower_Stage2"
model.Parent = buildingsFolder

-- 1) Fundament (IDENTISCH zu AnglerfishTower.Base für Grid-Kompatibilität) --
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Turmschaft, sich nach oben verjüngend (4 Segmente statt 3) --------------
local segmentSizes = { 4.8, 3.6, 2.6, 1.8 }
local currentY = 0.6
for i, diameter in ipairs(segmentSizes) do
	local segHeight = 2.6
	local segCFrame = ORIGIN * CFrame.new(0, currentY + segHeight / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	local seg = newPart(
		"TowerSegment" .. i,
		Vector3.new(segHeight, diameter, diameter),
		segCFrame,
		Color3.fromRGB(50, 54, 62),
		Enum.Material.Rock,
		model
	)
	seg.Shape = Enum.PartType.Cylinder
	currentY += segHeight
end

-- 3) Vier dekorative Rückenflossen (mehr Struktur) ---------------------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1))
	local finCFrame = ORIGIN * CFrame.new(math.cos(angle) * 2.0, 4.5, math.sin(angle) * 2.0) * CFrame.Angles(0, angle, 0)
	local fin = newPart("SpineFin" .. i, Vector3.new(0.2, 1.4, 0.9), finCFrame, Color3.fromRGB(160, 90, 255), Enum.Material.Neon, model)
	fin.CanCollide = false
end

-- 4) Gebogener Illicium-Arm (Angel-Rute), aus 3 abgewinkelten Segmenten -------
local armBaseCFrame = ORIGIN * CFrame.new(0, currentY + 0.3, 0)
local armSegCFrame = armBaseCFrame
local armLen = 1.7
for i = 1, 3 do
	local bendAngle = math.rad(15 * i)
	armSegCFrame = armSegCFrame * CFrame.Angles(0, 0, bendAngle) * CFrame.new(0, armLen / 2, 0)
	newPart(
		"IlliciumSegment" .. i,
		Vector3.new(0.4, armLen, 0.4),
		armSegCFrame,
		Color3.fromRGB(40, 44, 50),
		Enum.Material.SmoothPlastic,
		model
	)
	armSegCFrame = armSegCFrame * CFrame.new(0, armLen / 2, 0)
end

-- 5) Leuchtender Köder-Orb an der Spitze der Rute (größer/heller) ------------
local lureOrb = newPart(
	"LureOrb",
	Vector3.new(2.0, 2.0, 2.0),
	armSegCFrame,
	Color3.fromRGB(200, 0, 255),
	Enum.Material.Neon,
	model
)
lureOrb.Shape = Enum.PartType.Ball
lureOrb.CanCollide = false

local lureLight = Instance.new("PointLight")
lureLight.Name = "LureOrbLight"
lureLight.Color = Color3.fromRGB(200, 0, 255)
lureLight.Range = 14
lureLight.Brightness = 1.8
lureLight.Shadows = false
lureLight.Parent = lureOrb

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = lureOrb

model.PrimaryPart = base
model:SetAttribute("BuildingType", "AnglerfishTower")
model:SetAttribute("Stage", 2)

print("[Abyssara] AnglerfishTower_Stage2 created under Workspace.Assets.Buildings")
