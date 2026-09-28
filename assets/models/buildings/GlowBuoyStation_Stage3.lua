--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude (Upgrade-Stufe)
	Name: GlowBuoyStation_Stage3 ("Lichtboje", Stufe 3/3 - Finalstufe)
	Beschreibung:
		Prachtvolle Lichtboje: noch höherer Mast, beide Strebenringe, eine
		CSG-verschweißte Neon-Krone rund um den Haupt-Glow-Orb, sechs
		umlaufende Sammel-Orbs und ein dezenter Glitzer-Partikelemitter am
		Haupt-Orb (niedrige Rate).

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "GlowBuoyStation_Stage3" (BuildingId "GlowBuoyStation"
		  + "_Stage3").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  GlowBuoyStation.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "GlowBuoyStation", "Stage" = 3.
		- "MainOrb": Haupt-Glow-Part, unverändert benannt.
		- "OrbitOrb1".."OrbitOrb6": Satelliten-Sammel-Orbs.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
		HINWEIS: Verwendet :UnionAsync() - daher serverseitig bzw. in Studio
		mit CSG-Rechten ausführen.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 1.5, -160) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("GlowBuoyStation_Stage3")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowBuoyStation_Stage3"
model.Parent = buildingsFolder

-- 1) Fundament (IDENTISCH zu GlowBuoyStation.Base für Grid-Kompatibilität) --
local base = newPart("Base", Vector3.new(8, 1, 8), ORIGIN, Color3.fromRGB(100, 108, 118), Enum.Material.WoodPlanks, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Mastpfahl (noch höher als Stufe 2) --------------------------------------
local MAST_HEIGHT = 16
local mast = newPart(
	"Mast",
	Vector3.new(1.1, MAST_HEIGHT, 1.1),
	ORIGIN * CFrame.new(0, MAST_HEIGHT / 2 + 0.5, 0),
	Color3.fromRGB(100, 106, 116),
	Enum.Material.Metal,
	model
)

-- 3) Vertikaler Neon-Glow-Streifen am Mast -----------------------------------
local mastStrip = newPart(
	"MastGlowStrip",
	Vector3.new(0.3, MAST_HEIGHT - 1, 0.3),
	ORIGIN * CFrame.new(0.65, MAST_HEIGHT / 2 + 0.5, 0),
	Color3.fromRGB(255, 0, 200),
	Enum.Material.Neon,
	model
)
mastStrip.CanCollide = false

-- 4) Sammelkorb (unterer Strebenring) ----------------------------------------
-- Radius 0.9 statt 1.4: der Mast hat nur Radius 0.55, die Streben müssen also
-- näher heranreichen, um ihn zu überlappen statt daneben zu schweben.
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1))
	local offset = Vector3.new(math.cos(angle) * 0.9, MAST_HEIGHT - 1.0, math.sin(angle) * 0.9)
	newPart(
		"BasketStrut" .. i,
		Vector3.new(0.3, 2, 0.3),
		ORIGIN * CFrame.new(offset) * CFrame.Angles(0, angle, math.rad(20)),
		Color3.fromRGB(120, 126, 136),
		Enum.Material.Metal,
		model
	)
end

-- 4b) Mastspitze: verjüngter Pfosten vom Mastkopf bis in den Haupt-Orb hinein
-- (Detail + garantiert, dass Mast/Sockel mit dem oberen Strebenring/Orb
-- verbunden bleiben statt als getrennte Gruppe zu schweben) -----------------
local mastTipBottom = (ORIGIN * CFrame.new(0, MAST_HEIGHT + 0.5, 0)).Position
local mastTipTop = (ORIGIN * CFrame.new(0, MAST_HEIGHT + 3.6, 0)).Position
newPart(
	"MastTip",
	Vector3.new(0.55, 0.55, (mastTipTop - mastTipBottom).Magnitude),
	CFrame.new(mastTipBottom:Lerp(mastTipTop, 0.5), mastTipTop),
	Color3.fromRGB(100, 106, 116),
	Enum.Material.Metal,
	model
)

-- 5) Oberer Strebenring ------------------------------------------------------
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

-- 6) Haupt-Glow-Orb (größer/heller) + Glitzer-Partikelemitter ---------------
local mainOrb = newPart(
	"MainOrb",
	Vector3.new(4.4, 4.4, 4.4),
	ORIGIN * CFrame.new(0, MAST_HEIGHT + 3.6, 0),
	Color3.fromRGB(255, 0, 200),
	Enum.Material.Neon,
	model
)
mainOrb.Shape = Enum.PartType.Ball
mainOrb.CanCollide = false

local sparkleEmitter = Instance.new("ParticleEmitter")
sparkleEmitter.Name = "SparkleEmitter"
sparkleEmitter.Color = ColorSequence.new(Color3.fromRGB(0, 255, 255))
sparkleEmitter.Lifetime = NumberRange.new(0.5, 1)
sparkleEmitter.Rate = 5
sparkleEmitter.Speed = NumberRange.new(1, 3)
sparkleEmitter.Size = NumberSequence.new(0.25)
sparkleEmitter.Parent = mainOrb

local mainOrbLight = Instance.new("PointLight")
mainOrbLight.Name = "MainOrbLight"
mainOrbLight.Color = Color3.fromRGB(255, 0, 200)
mainOrbLight.Range = 18
mainOrbLight.Brightness = 2
mainOrbLight.Shadows = false
mainOrbLight.Parent = mainOrb

-- 7) Sechs kleinere umlaufende Sammel-Orbs, an dünnen Streben vom Mast -------
for i = 1, 6 do
	local angle = math.rad(60 * (i - 1))
	local orbY = MAST_HEIGHT - 2 + i * 0.4
	local offset = Vector3.new(math.cos(angle) * 4.2, orbY, math.sin(angle) * 4.2)
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

-- 8) Neon-Krone rund um den Haupt-Orb (CSG-Union aus 6 Spitzen) --------------
local crownSpikes = {}
local CROWN_SPIKE_COUNT = 6
local CROWN_RADIUS = 2.6
local crownY = MAST_HEIGHT + 5.2
for i = 1, CROWN_SPIKE_COUNT do
	local angle = math.rad(360 / CROWN_SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * CROWN_RADIUS, crownY, math.sin(angle) * CROWN_RADIUS)
	local spikeCFrame = ORIGIN * CFrame.new(offset) * CFrame.Angles(0, angle, math.rad(25))
	local spike = newPart("CrownSpikePiece" .. i, Vector3.new(0.4, 1.6, 0.4), spikeCFrame, Color3.fromRGB(0, 220, 255), Enum.Material.Neon, Workspace)
	table.insert(crownSpikes, spike)
end

local crownOk, crownRing = pcall(function()
	local primary = table.remove(crownSpikes, 1)
	return primary:UnionAsync(crownSpikes)
end)
if crownOk and crownRing then
	crownRing.Name = "CrownRing"
	crownRing.Color = Color3.fromRGB(0, 220, 255)
	crownRing.Material = Enum.Material.Neon
	crownRing.Anchored = true
	crownRing.CanCollide = false
	crownRing.Parent = model
else
	warn("[Abyssara] GlowBuoyStation_Stage3: CrownRing-CSG union failed, using unwelded individual spikes.")
	for _, spike in ipairs(crownSpikes) do
		spike.Anchored = true
		spike.CanCollide = false
		spike.Parent = model
	end
end

-- 6) Oberflaechendetails: Holzdeck-Plattform, Metall-Mastbeschlag -----------
addKeyedTexture(base, "WoodPlanks", Enum.NormalId.Top, 2.5, 2.5, Color3.fromRGB(150, 120, 90), 0.05)
addKeyedTexture(mast, "RivetedPlates", Enum.NormalId.Front, 1.5, 2, Color3.fromRGB(130, 134, 140), 0.05)

local collar = newPart(
	"MastCollar",
	Vector3.new(0.35, 1.6, 1.6),
	ORIGIN * CFrame.new(0, 1.6, 0) * CFrame.Angles(0, 0, math.rad(90)),
	Color3.fromRGB(70, 74, 80),
	Enum.Material.CorrodedMetal,
	model
)
collar.Shape = Enum.PartType.Cylinder
collar.CanCollide = false

model.PrimaryPart = base
model:SetAttribute("BuildingType", "GlowBuoyStation")
model:SetAttribute("Stage", 3)

print("[Abyssara] GlowBuoyStation_Stage3 created under Workspace.Assets.Buildings")
