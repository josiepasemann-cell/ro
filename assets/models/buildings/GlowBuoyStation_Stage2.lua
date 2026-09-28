--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude (Upgrade-Stufe)
	Name: GlowBuoyStation_Stage2 ("Lichtboje", Stufe 2/3)
	Beschreibung:
		Höherer Mast mit zweitem Strebenring (UpperCollarStrut1-4) über dem
		Sammelkorb, größerer/hellerer Haupt-Glow-Orb, ein vertikaler Neon-
		Glow-Streifen am Mast sowie ein vierter umlaufender Sammel-Orb.

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "GlowBuoyStation_Stage2" (BuildingId "GlowBuoyStation"
		  + "_Stage2").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  GlowBuoyStation.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "GlowBuoyStation", "Stage" = 2.
		- "MainOrb": Haupt-Glow-Part, unverändert benannt.
		- "OrbitOrb1".."OrbitOrb4": Satelliten-Sammel-Orbs (1 mehr als Stufe 1).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 1.5, -140) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("GlowBuoyStation_Stage2")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowBuoyStation_Stage2"
model.Parent = buildingsFolder

-- 1) Fundament (IDENTISCH zu GlowBuoyStation.Base für Grid-Kompatibilität) --
local base = newPart("Base", Vector3.new(8, 1, 8), ORIGIN, Color3.fromRGB(100, 108, 118), Enum.Material.WoodPlanks, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Mastpfahl (höher als Stufe 1) -------------------------------------------
local MAST_HEIGHT = 12
local mast = newPart(
	"Mast",
	Vector3.new(1, MAST_HEIGHT, 1),
	ORIGIN * CFrame.new(0, MAST_HEIGHT / 2 + 0.5, 0),
	Color3.fromRGB(90, 96, 104),
	Enum.Material.Metal,
	model
)

-- 3) Vertikaler Neon-Glow-Streifen am Mast -----------------------------------
local mastStrip = newPart(
	"MastGlowStrip",
	Vector3.new(0.3, MAST_HEIGHT - 1, 0.3),
	ORIGIN * CFrame.new(0.6, MAST_HEIGHT / 2 + 0.5, 0),
	Color3.fromRGB(255, 0, 200),
	Enum.Material.Neon,
	model
)
mastStrip.CanCollide = false

-- 4) Sammelkorb (unterer Strebenring, wie Stufe 1) ---------------------------
-- Radius 0.85 statt 1.4: der Mast hat nur Radius 0.5, die Streben müssen also
-- näher heranreichen, um ihn zu überlappen statt daneben zu schweben.
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1))
	local offset = Vector3.new(math.cos(angle) * 0.85, MAST_HEIGHT - 1.0, math.sin(angle) * 0.85)
	newPart(
		"BasketStrut" .. i,
		Vector3.new(0.3, 2, 0.3),
		ORIGIN * CFrame.new(offset) * CFrame.Angles(0, angle, math.rad(20)),
		Color3.fromRGB(110, 116, 126),
		Enum.Material.Metal,
		model
	)
end

-- 5) Mastspitze: verjüngter Pfosten vom Mastkopf bis in den Haupt-Orb hinein
-- (Detail + garantiert, dass Mast/Sockel mit dem oberen Strebenring/Orb
-- verbunden bleiben statt als getrennte Gruppe zu schweben) -----------------
local mastTipBottom = (ORIGIN * CFrame.new(0, MAST_HEIGHT + 0.5, 0)).Position
local mastTipTop = (ORIGIN * CFrame.new(0, MAST_HEIGHT + 3.2, 0)).Position
local mastTip = newPart(
	"MastTip",
	Vector3.new(0.5, 0.5, (mastTipTop - mastTipBottom).Magnitude),
	CFrame.new(mastTipBottom:Lerp(mastTipTop, 0.5), mastTipTop),
	Color3.fromRGB(90, 96, 104),
	Enum.Material.Metal,
	model
)

-- 6) Zweiter, oberer Strebenring (neu, mehr Struktur) ------------------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 45)
	local offset = Vector3.new(math.cos(angle) * 2.0, MAST_HEIGHT + 1.0, math.sin(angle) * 2.0)
	newPart(
		"UpperCollarStrut" .. i,
		Vector3.new(0.3, 1.8, 0.3),
		ORIGIN * CFrame.new(offset) * CFrame.Angles(0, angle, math.rad(-20)),
		Color3.fromRGB(0, 220, 255),
		Enum.Material.Neon,
		model
	)
end

-- 7) Haupt-Glow-Orb an der Spitze (größer/heller als Stufe 1) ----------------
local mainOrb = newPart(
	"MainOrb",
	Vector3.new(3.8, 3.8, 3.8),
	ORIGIN * CFrame.new(0, MAST_HEIGHT + 3.2, 0),
	Color3.fromRGB(255, 0, 200),
	Enum.Material.Neon,
	model
)
mainOrb.Shape = Enum.PartType.Ball
mainOrb.CanCollide = false

-- 8) Vier kleinere umlaufende Sammel-Orbs (1 mehr als Stufe 1), an dünnen
-- Streben vom Mast (siehe Stufe 1) -------------------------------------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1))
	local orbY = MAST_HEIGHT - 2 + i * 0.5
	local offset = Vector3.new(math.cos(angle) * 3.8, orbY, math.sin(angle) * 3.8)
	local orbPos = (ORIGIN * CFrame.new(offset)).Position
	local mastPoint = (ORIGIN * CFrame.new(0, orbY, 0)).Position

	local arm = newPart(
		"OrbitArm" .. i,
		Vector3.new(0.24, 0.24, (orbPos - mastPoint).Magnitude),
		CFrame.new(mastPoint:Lerp(orbPos, 0.5), orbPos),
		Color3.fromRGB(150, 255, 235),
		Enum.Material.Neon,
		model
	)
	arm.CanCollide = false

	local orb = newPart(
		"OrbitOrb" .. i,
		Vector3.new(1.2, 1.2, 1.2),
		ORIGIN * CFrame.new(offset),
		Color3.fromRGB(150, 255, 235),
		Enum.Material.Neon,
		model
	)
	orb.Shape = Enum.PartType.Ball
	orb.CanCollide = false
	orb.Transparency = 0.1
end

-- 6) Oberflaechendetails: Holzdeck-Plattform, dicker rundlicher Mastbeschlag -
addKeyedTexture(base, "WoodPlanks", Enum.NormalId.Top, 2.5, 2.5, Color3.fromRGB(150, 120, 90), 0.05)

local collar = newPart(
	"MastCollar",
	Vector3.new(0.6, 2.0, 2.0),
	ORIGIN * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color3.fromRGB(75, 80, 88),
	Enum.Material.CorrodedMetal,
	model
)
collar.Shape = Enum.PartType.Cylinder
collar.CanCollide = false

model.PrimaryPart = base
model:SetAttribute("BuildingType", "GlowBuoyStation")
model:SetAttribute("Stage", 2)

print("[Abyssara] GlowBuoyStation_Stage2 created under Workspace.Assets.Buildings")
