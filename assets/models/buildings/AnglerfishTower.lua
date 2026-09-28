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

local CollectionService = game:GetService("CollectionService")

local function addKeyedTexture(parent, key, face, studsU, studsV, color, transparency)
	local tex = Instance.new("Texture")
	tex.Name = "Tex_" .. key
	tex.Texture = ""
	tex.Face = face
	tex.StudsPerTileU = studsU
	tex.StudsPerTileV = studsV
	tex.Color3 = color
	tex.Transparency = transparency or 0
	tex:SetAttribute("TextureKey", key)
	CollectionService:AddTag(tex, "KeyedTexture")
	tex.Parent = parent
	return tex
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
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Cobblestone, model)
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
		Enum.Material.CorrodedMetal,
		model
	)
	seg.Shape = Enum.PartType.Cylinder
	currentY += segHeight
end

-- 3) Gebogener Illicium-Arm (Angel-Rute), aus 3 abgewinkelten Segmenten -------
-- Startet 0.2 Studs INNERHALB des Turmkopfes (statt darüber), damit das erste
-- Rutensegment den Turmschaft überlappt statt daneben zu schweben.
local armBaseCFrame = ORIGIN * CFrame.new(0, currentY - 0.2, 0)

-- Kleine Sockel-Manschette, wo die Rute aus dem Turmkopf tritt (Detail) -------
local armSocket = newPart(
	"ArmSocket",
	Vector3.new(0.6, 0.5, 0.6),
	armBaseCFrame,
	Color3.fromRGB(30, 32, 38),
	Enum.Material.Metal,
	model
)
armSocket.Shape = Enum.PartType.Cylinder
armSocket.CFrame = armBaseCFrame * CFrame.Angles(0, 0, math.rad(90))

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

-- 5) Oberflaechendetails: rundlicher Steinsockel, dicker Chrom-Trimring, ------
-- klobige Bolzen-Kugeln (organisch/kartoonig statt scharfkantig) ------------
addKeyedTexture(base, "StoneTiles", Enum.NormalId.Top, 3, 3, Color3.fromRGB(150, 150, 155), 0.05)

local trimBand = newPart(
	"FoundationTrimBand",
	Vector3.new(0.55, 7.7, 7.7),
	ORIGIN * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color3.fromRGB(40, 42, 48),
	Enum.Material.CorrodedMetal,
	model
)
trimBand.Shape = Enum.PartType.Cylinder
trimBand.CanCollide = false

for i = 1, 4 do
	local angle = math.rad(90 * (i - 1))
	local rivetCFrame = ORIGIN * CFrame.new(math.cos(angle) * 3.15, 0.95, math.sin(angle) * 3.15)
	local rivet = newPart("FoundationRivet" .. i, Vector3.new(0.55, 0.55, 0.55), rivetCFrame, Color3.fromRGB(210, 212, 216), Enum.Material.DiamondPlate, model)
	rivet.Shape = Enum.PartType.Ball
	rivet.CanCollide = false
end

model.PrimaryPart = base
model:SetAttribute("BuildingType", "AnglerfishTower")
model:SetAttribute("Stage", 1)

print("[Abyssara] AnglerfishTower created under Workspace.Assets.Buildings")
