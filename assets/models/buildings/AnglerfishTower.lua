--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude / Verteidigungsturm (Basisstufe)
	Name: AnglerfishTower ("Anglerfisch-Turm", Verteidigungsturm 1 von 3 Typen)
	Beschreibung:
		Verteidigungsturm im Anglerfisch-Thema: Turmsockel mit spitzem Aufbau,
		auf dem ein gebogener "Illicium"-Arm (Angel-Rute) sitzt, an dessen Spitze
		ein leuchtender Köder-Orb hängt (Anspielung auf das Leuchtorgan des
		echten Anglerfischs). Der Köder-Orb dient später als visueller Anker
		für Angriffs-/Ziel-Effekte des Code-Agenten.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Base" (Fundament-Part, für Placement/Snap-to-Grid)
		- Model-Attribute: "BuildingType" = "AnglerfishTower", "Stage" = 1
		- "LureOrb": Neon-Part (Köder-Leuchtkugel) = Referenzpunkt für
		  Ziel-/Schuss-Effekte (z.B. Raycast-Ursprung) im Trench-Raid-System.
		- Attachment "MuzzlePoint" an LureOrb: Ursprungspunkt für Projektile.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-20, 1.5, -20) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("AnglerfishTower")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "AnglerfishTower"
model.Parent = buildingsFolder

-- 1) Fundament ---------------------------------------------------------------
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Turmschaft, sich nach oben verjüngend (3 gestapelte Segmente) ------------
local segmentSizes = { 4.5, 3.2, 2.0 }
local currentY = 0.6
for i, diameter in ipairs(segmentSizes) do
	local segHeight = 3
	local segCFrame = ORIGIN * CFrame.new(0, currentY + segHeight / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	local seg = newPart(
		"TowerSegment" .. i,
		Vector3.new(segHeight, diameter, diameter),
		segCFrame,
		Color3.fromRGB(45, 48, 54),
		Enum.Material.Rock,
		model
	)
	seg.Shape = Enum.PartType.Cylinder
	currentY += segHeight
end

-- 3) Gebogener Illicium-Arm (Angel-Rute), aus 3 abgewinkelten Segmenten -------
local armBaseCFrame = ORIGIN * CFrame.new(0, currentY + 0.3, 0)
local armSegCFrame = armBaseCFrame
local armLen = 1.6
for i = 1, 3 do
	local bendAngle = math.rad(15 * i)
	armSegCFrame = armSegCFrame * CFrame.Angles(0, 0, bendAngle) * CFrame.new(0, armLen / 2, 0)
	newPart(
		"IlliciumSegment" .. i,
		Vector3.new(0.35, armLen, 0.35),
		armSegCFrame,
		Color3.fromRGB(35, 38, 44),
		Enum.Material.SmoothPlastic,
		model
	)
	armSegCFrame = armSegCFrame * CFrame.new(0, armLen / 2, 0)
end

-- 4) Leuchtender Köder-Orb an der Spitze der Rute ------------------------------
local lureOrb = newPart(
	"LureOrb",
	Vector3.new(1.6, 1.6, 1.6),
	armSegCFrame,
	Color3.fromRGB(160, 90, 255),
	Enum.Material.Neon,
	model
)
lureOrb.Shape = Enum.PartType.Ball
lureOrb.CanCollide = false

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = lureOrb

model.PrimaryPart = base
model:SetAttribute("BuildingType", "AnglerfishTower")
model:SetAttribute("Stage", 1)

print("[Abyssara] AnglerfishTower erzeugt unter Workspace.Assets.Buildings")
