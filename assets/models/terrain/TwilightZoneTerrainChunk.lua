--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Terrain-Chunk
	Name: TwilightZoneTerrainChunk (v2 – ausgebaut)

	Angewandte Design-Prinzipien (siehe /home/user/ro/docs/terrain-design-notes.md
	für die vollständige Recherche-Zusammenfassung):
		1. Verticality/Höhenrhythmus – zwei aufragende Felsnadeln (CSG-Union
		   gestapelter, leicht versetzter Blöcke) durchbrechen die Horizontlinie;
		   eine per CSG-Subtraktion in den Felsboden eingeschnittene, lang
		   gezogene Spalte sorgt zusätzlich für Tiefe statt einer reinen Ebene.
		2. Landmark/Point of Interest – ein "Kelp-Torbogen" aus zwei
		   zueinander gebogenen Kelp-Stämmen (prozedural entlang einer Kurve
		   platziert, kein reines Rotations-Sway) markiert den Hub-seitigen
		   Zonen-Eingang.
		3. Sichtachsen/Leading the Eye – wie in der Sonnenzone bleibt eine
		   schmale Hub-Gasse frei; hier jedoch bewusst enger und von dichteren
		   Fels-/Kelp-Wänden gesäumt, um das "geschlossenere", mysteriösere
		   Zonengefühl der Dämmerzone von der offenen Sonnenzone abzusetzen.
		4. Silhouetten-Lesbarkeit (Low-Poly) – Felsnadeln und Torbogen bleiben
		   grobe, eindeutige Blockformen statt organisch-glatter Kurven.
		5. Farbpalette/Kontrast – dunklere, kühlere Grau-/Blautöne gegenüber
		   der hellen Sonnenzone, mit leuchtend türkisen/aqua Neon-Kelpspitzen
		   als einzige helle Akzente (starker Wert-Kontrast in der Dunkelheit).
		6. Deko-Dichte-Rhythmus – dichte Kelp-/Felsblock-Wände säumen die
		   Ränder, die Mitte (Hub-Gasse) bleibt bewusst klar.
		7. Performance-Grenzen – CSG-Union für die Felsnadeln, CSG-Subtract für
		   die Spalte statt vieler Einzelteile; Kelp-Cluster-/Segmentzahlen
		   moderat gehalten (kein Terrain-Part pro Halm).

	Beschreibung:
		Stilisiertes Low-Poly Meeresboden-Terrain-Set für die DÄMMERZONE
		(Level 10-25): dunklerer, felsiger Meeresboden mit einer eingeschnittenen
		Felsspalte, zwei aufragenden Felsnadeln, dichten Kelpwäldern und einem
		gebogenen Kelp-Torbogen als Landmark am Zonen-Eingang.

	NAMENSKONVENTION:
		- Model.PrimaryPart = "ChunkBase" (die Grundfläche, CSG-Result)
		- Model-Attribute: "Zone" = "TwilightZone"

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-120, 0, 0) -- Vor Ausführung anpassen (Portal-Richtung: +X = Richtung Hub)
local CHUNK_SIZE = 100
local BASE_THICKNESS = 3
local BOULDER_COUNT = 9
local KELP_CLUSTER_COUNT = 6
local RANDOM_SEED = 4002
local LANE_HALF_WIDTH = 7 -- schmaler als in der Sonnenzone -> geschlossenere Anmutung
-- // ----------------------------------------------------------------------

local rng = Random.new(RANDOM_SEED)
local HALF = CHUNK_SIZE / 2
local BASE_TOP_Y = BASE_THICKNESS / 2
local originPos = ORIGIN.Position -- alle ORIGINs in diesem Projekt sind reine Translationen (keine Rotation)

local ROCK_COLORS = {
	Color3.fromRGB(70, 72, 78),
	Color3.fromRGB(55, 57, 63),
	Color3.fromRGB(85, 88, 95),
}

local SPIRE_COLORS = {
	Color3.fromRGB(60, 63, 70),
	Color3.fromRGB(48, 50, 56),
}

local KELP_COLORS = {
	Color3.fromRGB(35, 90, 75),
	Color3.fromRGB(30, 75, 90),
}

local KELP_TIP_COLOR = Color3.fromRGB(90, 230, 200)

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

-- Erzeugt ein Part entlang einer Richtung `dir` (Weltraum, normalisiert),
-- beginnend bei `fromPos` (Weltraum). Genutzt für gebogene Kelp-Stämme, deren
-- Segmente sich tatsächlich krümmen statt nur um die eigene Achse zu wackeln.
local function partAlongDirection(name, length, width, fromPos, dir, color, material, parent)
	local center = fromPos + dir * (length / 2)
	local upHint = Vector3.new(0, 1, 0)
	if math.abs(dir:Dot(upHint)) > 0.999 then
		upHint = Vector3.new(1, 0, 0)
	end
	local lookCFrame = CFrame.lookAt(center, center + dir, upHint)
	local partCFrame = lookCFrame * CFrame.Angles(math.rad(90), 0, 0)
	local part = newPart(name, Vector3.new(width, length, width), partCFrame, color, material, parent)
	return part, fromPos + dir * length
end

local function inHubSightLane(localZ)
	return math.abs(localZ) < LANE_HALF_WIDTH
end

local function randomOffLanePosition(marginX, marginZ)
	for _ = 1, 6 do
		local x = rng:NextNumber(-HALF + marginX, HALF - marginX)
		local z = rng:NextNumber(-HALF + marginZ, HALF - marginZ)
		if not inHubSightLane(z) then
			return x, z
		end
	end
	local z = LANE_HALF_WIDTH + rng:NextNumber(1, 6)
	if rng:NextNumber() < 0.5 then
		z = -z
	end
	return rng:NextNumber(-HALF + marginX, HALF - marginX), z
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local terrainFolder = getOrCreateFolder(assetsFolder, "Terrain")

local previous = terrainFolder:FindFirstChild("TwilightZoneTerrainChunk")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TwilightZoneTerrainChunk"
model.Parent = terrainFolder

-- 1) Grundfläche: dunkler Felsboden MIT eingeschnittener Spalte (Verticality) -
local rawBase = newPart(
	"ChunkBase",
	Vector3.new(CHUNK_SIZE, BASE_THICKNESS, CHUNK_SIZE),
	ORIGIN,
	Color3.fromRGB(48, 50, 56),
	Enum.Material.Slate,
	model
)

local crevice = newPart(
	"CreviceCutter",
	Vector3.new(9, 7, 66), -- schmal, lang gezogen -> Canyon-Charakter statt runder Mulde
	ORIGIN * CFrame.new(-14, BASE_TOP_Y, 14) * CFrame.Angles(0, math.rad(28), 0),
	Color3.fromRGB(48, 50, 56),
	Enum.Material.Slate,
	model
)
crevice.Shape = Enum.PartType.Ball

local base = rawBase:SubtractAsync({ crevice })
base.Name = "ChunkBase"
base.Color = Color3.fromRGB(48, 50, 56)
base.Material = Enum.Material.Slate
base.Anchored = true
base.CanCollide = true
base.TopSurface = Enum.SurfaceType.Smooth
base.BottomSurface = Enum.SurfaceType.Smooth
base.Parent = model

-- 2) Zwei aufragende Felsnadeln (CSG-Union gestapelter Blöcke) -------------
local SPIRE_SITES = {
	{ x = -30, z = -30 },
	{ x = 20, z = -34 },
}
for i, site in ipairs(SPIRE_SITES) do
	local tiers = 4
	local currentY = BASE_TOP_Y
	local baseSize = rng:NextNumber(5, 6.5)
	local tierParts = {}
	for tier = 1, tiers do
		local shrink = 1 - (tier - 1) * 0.2
		local w = baseSize * shrink
		local h = rng:NextNumber(4, 6)
		local jitterX = rng:NextNumber(-1, 1)
		local jitterZ = rng:NextNumber(-1, 1)
		local rotY = rng:NextNumber(0, 360)
		local overlap = h * 0.15
		local tierCFrame = ORIGIN
			* CFrame.new(site.x + jitterX, currentY + h / 2 - overlap, site.z + jitterZ)
			* CFrame.Angles(rng:NextNumber(-0.05, 0.05), math.rad(rotY), rng:NextNumber(-0.05, 0.05))
		local tierPart = newPart("Spire" .. i .. "_Tier" .. tier, Vector3.new(w, h, w), tierCFrame, SPIRE_COLORS[1], Enum.Material.Rock, model)
		table.insert(tierParts, tierPart)
		currentY += h - overlap
	end

	local first = table.remove(tierParts, 1)
	local spire = first:UnionAsync(tierParts)
	spire.Name = "RockSpire" .. i
	spire.Color = SPIRE_COLORS[i % #SPIRE_COLORS + 1]
	spire.Material = Enum.Material.Rock
	spire.Anchored = true
	spire.CanCollide = true
	spire.TopSurface = Enum.SurfaceType.Smooth
	spire.BottomSurface = Enum.SurfaceType.Smooth
	spire.Parent = model
end

-- 3) Landmark: Kelp-Torbogen am Hub-seitigen Zonen-Eingang ------------------
-- Zwei Stämme krümmen sich entlang einer echten Kurve (nicht nur Rotation)
-- zueinander und schließen oben mit einem leuchtenden Neon-Knoten.
local archLocalX, archLocalZ = HALF - 12, 0
local archWorldBase = originPos + Vector3.new(archLocalX, BASE_TOP_Y, archLocalZ)
local ARCH_SPAN = 6.5
local ARCH_SEGMENTS = 6
local ARCH_SEG_LEN = 3.1

local function buildKelpArchArm(sideSign)
	local pos = archWorldBase + Vector3.new(0, 0, sideSign * ARCH_SPAN)
	for seg = 1, ARCH_SEGMENTS do
		local t = seg / ARCH_SEGMENTS
		local bendAngle = math.rad(80) * (t ^ 1.4)
		local dir = Vector3.new(0, math.cos(bendAngle), -sideSign * math.sin(bendAngle))
		local width = math.max(0.4, 1.1 - t * 0.55)
		local isTip = seg == ARCH_SEGMENTS
		local color = isTip and KELP_TIP_COLOR or KELP_COLORS[1]
		local material = isTip and Enum.Material.Neon or Enum.Material.Grass
		local part
		part, pos = partAlongDirection("KelpArch_" .. (sideSign > 0 and "N" or "S") .. seg, ARCH_SEG_LEN, width, pos, dir, color, material, model)
		part.CanCollide = false
	end
	return pos
end

local archTopA = buildKelpArchArm(1)
local archTopB = buildKelpArchArm(-1)
local knotCenter = (archTopA + archTopB) / 2
local knot = newPart("KelpArchKnot", Vector3.new(1.6, 1.6, 1.6), CFrame.new(knotCenter), KELP_TIP_COLOR, Enum.Material.Neon, model)
knot.Shape = Enum.PartType.Ball
knot.CanCollide = false

-- Dichte Fels-/Kelp-Wand flankiert den Torbogen (Deko-Rhythmus: dicht am Landmark)
for i = 1, 5 do
	local px = archLocalX + rng:NextNumber(-6, 6)
	local pz = archLocalZ + rng:NextNumber(9, 16) * (rng:NextNumber() < 0.5 and 1 or -1)
	local size = rng:NextNumber(1.4, 3)
	newPart(
		"ArchFlankRock" .. i,
		Vector3.new(size, size * 0.9, size),
		ORIGIN * CFrame.new(px, BASE_TOP_Y + size / 2, pz) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0),
		ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)],
		Enum.Material.Rock,
		model
	)
end

-- 4) Gesteinsbrocken (blocky, unterschiedlich groß), außerhalb der Hub-Gasse -
for i = 1, BOULDER_COUNT do
	local w = rng:NextNumber(1.5, 5)
	local h = rng:NextNumber(1.2, 4)
	local d = rng:NextNumber(1.5, 5)
	local offsetX, offsetZ = randomOffLanePosition(3, 3)
	local rotY = rng:NextNumber(0, 360)

	local boulderCFrame = ORIGIN
		* CFrame.new(offsetX, BASE_TOP_Y + h / 2, offsetZ)
		* CFrame.Angles(rng:NextNumber(-0.2, 0.2), math.rad(rotY), rng:NextNumber(-0.2, 0.2))

	newPart(
		"Boulder" .. i,
		Vector3.new(w, h, d),
		boulderCFrame,
		ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)],
		Enum.Material.Rock,
		model
	)
end

-- 5) Kelp-Wälder (dichte Cluster säumen die Ränder, Gasse bleibt frei) ------
for c = 1, KELP_CLUSTER_COUNT do
	local clusterOffsetX, clusterOffsetZ = randomOffLanePosition(5, 5)
	local strandsInCluster = rng:NextInteger(2, 3)

	for s = 1, strandsInCluster do
		local strandX = clusterOffsetX + rng:NextNumber(-1.5, 1.5)
		local strandZ = clusterOffsetZ + rng:NextNumber(-1.5, 1.5)
		local segmentCount = rng:NextInteger(3, 4)
		local segmentHeight = rng:NextNumber(1.6, 2.4)
		local currentY = BASE_TOP_Y
		local sway = rng:NextNumber(-8, 8)
		local kelpColor = KELP_COLORS[rng:NextInteger(1, #KELP_COLORS)]

		for seg = 1, segmentCount do
			local segWidth = math.max(0.35, 0.9 - seg * 0.12)
			local swayAngle = math.rad(sway * (seg / segmentCount))
			local segCFrame = ORIGIN
				* CFrame.new(strandX, currentY + segmentHeight / 2, strandZ)
				* CFrame.Angles(0, 0, swayAngle)

			local isTip = seg == segmentCount
			local segPart = newPart(
				"KelpSegment",
				Vector3.new(segWidth, segmentHeight, segWidth),
				segCFrame,
				isTip and KELP_TIP_COLOR or kelpColor,
				isTip and Enum.Material.Neon or Enum.Material.Grass,
				model
			)
			segPart.CanCollide = false
			currentY += segmentHeight * math.cos(swayAngle)
		end
	end
end

model.PrimaryPart = base
model:SetAttribute("Zone", "TwilightZone")

print("[Abyssara] TwilightZoneTerrainChunk (v2) created under Workspace.Assets.Terrain")
