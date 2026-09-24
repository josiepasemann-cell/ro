--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude / Verteidigungsturm (Upgrade-Stufe)
	Name: AnglerfishTower_Stage3 ("Anglerfisch-Turm", Stufe 3/3 - Finalstufe)
	Beschreibung:
		Prachtvoller Turm: 4 Turmsegmente, 4 Rückenflossen, eine CSG-
		verschweißte Dornenkrone am Turmkopf, eine 4-teilige Illicium-Rute
		mit größerem/hellerem Köder-Orb und dezentem Glitzer-Partikelemitter
		(niedrige Rate).

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "AnglerfishTower_Stage3" (BuildingId "AnglerfishTower"
		  + "_Stage3").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  AnglerfishTower.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "AnglerfishTower", "Stage" = 3.
		- "LureOrb": Neon-Part (Köder-Leuchtkugel), unverändert benannt.
		- Attachment "MuzzlePoint" an LureOrb: Ursprungspunkt für Projektile
		  (unverändert, siehe src/server/RaidService.lua getTowerOriginPosition).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
		HINWEIS: Verwendet :UnionAsync() - daher serverseitig bzw. in Studio
		mit CSG-Rechten ausführen.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(45, 1.5, -160) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("AnglerfishTower_Stage3")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "AnglerfishTower_Stage3"
model.Parent = buildingsFolder

-- 1) Fundament (IDENTISCH zu AnglerfishTower.Base für Grid-Kompatibilität) --
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Turmschaft, sich nach oben verjüngend (4 Segmente) ----------------------
local segmentSizes = { 5.0, 3.8, 2.8, 2.0 }
local currentY = 0.6
for i, diameter in ipairs(segmentSizes) do
	local segHeight = 2.7
	local segCFrame = ORIGIN * CFrame.new(0, currentY + segHeight / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	local seg = newPart(
		"TowerSegment" .. i,
		Vector3.new(segHeight, diameter, diameter),
		segCFrame,
		Color3.fromRGB(55, 58, 66),
		Enum.Material.Rock,
		model
	)
	seg.Shape = Enum.PartType.Cylinder
	currentY += segHeight
end

-- 3) Vier dekorative Rückenflossen -------------------------------------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1))
	local finCFrame = ORIGIN * CFrame.new(math.cos(angle) * 2.2, 4.8, math.sin(angle) * 2.2) * CFrame.Angles(0, angle, 0)
	local fin = newPart("SpineFin" .. i, Vector3.new(0.2, 1.7, 1.0), finCFrame, Color3.fromRGB(200, 0, 255), Enum.Material.Neon, model)
	fin.CanCollide = false
end

-- 4) Dornenkrone am Turmkopf (CSG-Union aus 6 Spitzen) -----------------------
local crownSpikes = {}
local CROWN_SPIKE_COUNT = 6
local CROWN_RADIUS = 1.4
for i = 1, CROWN_SPIKE_COUNT do
	local angle = math.rad(360 / CROWN_SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * CROWN_RADIUS, currentY + 0.4, math.sin(angle) * CROWN_RADIUS)
	local spikeCFrame = ORIGIN * CFrame.new(offset) * CFrame.Angles(0, angle, math.rad(25))
	local spike = newPart("CrownSpikePiece" .. i, Vector3.new(0.35, 1.3, 0.35), spikeCFrame, Color3.fromRGB(200, 0, 255), Enum.Material.Neon, Workspace)
	table.insert(crownSpikes, spike)
end

local crownOk, crownSpikeCluster = pcall(function()
	local primary = table.remove(crownSpikes, 1)
	return primary:UnionAsync(crownSpikes)
end)
if crownOk and crownSpikeCluster then
	crownSpikeCluster.Name = "CrownSpikeCluster"
	crownSpikeCluster.Color = Color3.fromRGB(200, 0, 255)
	crownSpikeCluster.Material = Enum.Material.Neon
	crownSpikeCluster.Anchored = true
	crownSpikeCluster.CanCollide = false
	crownSpikeCluster.Parent = model
else
	warn("[Abyssara] AnglerfishTower_Stage3: CrownSpikeCluster-CSG union failed, using unwelded individual spikes.")
	for _, spike in ipairs(crownSpikes) do
		spike.Anchored = true
		spike.CanCollide = false
		spike.Parent = model
	end
end

-- 5) Gebogener Illicium-Arm (Angel-Rute), aus 4 abgewinkelten Segmenten -------
local armBaseCFrame = ORIGIN * CFrame.new(0, currentY + 0.3, 0)
local armSegCFrame = armBaseCFrame
local armLen = 1.7
for i = 1, 4 do
	local bendAngle = math.rad(12 * i)
	armSegCFrame = armSegCFrame * CFrame.Angles(0, 0, bendAngle) * CFrame.new(0, armLen / 2, 0)
	newPart(
		"IlliciumSegment" .. i,
		Vector3.new(0.45, armLen, 0.45),
		armSegCFrame,
		Color3.fromRGB(45, 48, 56),
		Enum.Material.SmoothPlastic,
		model
	)
	armSegCFrame = armSegCFrame * CFrame.new(0, armLen / 2, 0)
end

-- 6) Leuchtender Köder-Orb (größer/heller) + Glitzer-Partikelemitter ---------
local lureOrb = newPart(
	"LureOrb",
	Vector3.new(2.4, 2.4, 2.4),
	armSegCFrame,
	Color3.fromRGB(220, 0, 255),
	Enum.Material.Neon,
	model
)
lureOrb.Shape = Enum.PartType.Ball
lureOrb.CanCollide = false

local lureLight = Instance.new("PointLight")
lureLight.Name = "LureOrbLight"
lureLight.Color = Color3.fromRGB(220, 0, 255)
lureLight.Range = 18
lureLight.Brightness = 2.2
lureLight.Shadows = false
lureLight.Parent = lureOrb

local sparkleEmitter = Instance.new("ParticleEmitter")
sparkleEmitter.Name = "SparkleEmitter"
sparkleEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
sparkleEmitter.Lifetime = NumberRange.new(0.4, 0.8)
sparkleEmitter.Rate = 5
sparkleEmitter.Speed = NumberRange.new(1, 3)
sparkleEmitter.Size = NumberSequence.new(0.25)
sparkleEmitter.Parent = lureOrb

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = lureOrb

model.PrimaryPart = base
model:SetAttribute("BuildingType", "AnglerfishTower")
model:SetAttribute("Stage", 3)

print("[Abyssara] AnglerfishTower_Stage3 created under Workspace.Assets.Buildings")
