--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Terrain-Chunk
	Name: MidnightZoneTerrainChunk (neu, Phase 2 / Erweiterungskonzept 1.1)

	Angewandte Design-Prinzipien (siehe /home/user/ro/docs/terrain-design-notes.md
	für die vollständige Recherche-Zusammenfassung):
		1. Verticality/Höhen- & Enge-Rhythmus – eine enge Einstiegs-Passage
		   (überhängende Deckenplatte, dichte Wände) wechselt sich mit einer
		   offenen, hohen Hauptkaverne (Stalagmiten vom Boden, Stalaktiten von
		   "oben") ab – klassischer Cave-Rhythmus aus Enge und Weite.
		2. Landmark – der dramatische Arena-Eingang "Der Tiefenfürst": ein per
		   CSG-Subtraktion (NegateOperation) aus einem massiven Felsblock
		   herausgeschnittenes, rundes Höhlentor, flankiert von zwei mit
		   Lava-Adern durchzogenen Felsnadeln (CSG-Union), vor einer
		   eingesenkten, von Lava umrandeten Arena-Bodenfläche.
		3. Licht als Wegführung ("Leading the Eye" in der Dunkelheit) – da im
		   Dunkeln Silhouetten kaum lesbar sind, übernehmen glühende
		   Lava-Spalten (Neon + PointLight) die Rolle der Sonnenzonen-
		   Sichtachse: ihre Lichtinseln markieren den begehbaren Pfad von der
		   Einstiegs-Passage durch die Kaverne bis zum Arena-Tor.
		4. Silhouetten-Lesbarkeit im Dunkeln – große, einfache dunkle
		   Blockformen, deren Kontur nur durch schmale, sehr helle Neon-Risse
		   an Kanten/Rändern erkennbar bleibt (starker Hell-Dunkel-Kontrast
		   statt Detailfülle).
		5. Farbpalette/Kontrast – fast schwarzes Basalt-/Obsidian-Grau als
		   Basis, dazu heißes Orange-Rot (Lava) als einzige warme Akzentfarbe –
		   deutlicher Bruch zur kühlen, hellen Sonnenzone und zur
		   türkisen Dämmerzone.
		6. Deko-Dichte-Rhythmus – dichte Steinwände in der Passage, sehr
		   sparsame, dafür monumentale Formationen in der Kaverne, dichte
		   Deko-Tasche direkt am Arena-Tor (Erwartungsspannung vor dem "Boss").
		7. Performance-Grenzen – CSG-Union für Felsnadeln/Stalagmiten, CSG-
		   Subtract (NegateOperation) für Höhlentor & Arena-Mulde statt vieler
		   Einzelteile; Lichtquellen sparsam (kleine `PointLight`s) statt
		   teurer Partikel-Systeme.

	Beschreibung:
		Dunkles Höhlen-/Lavaspalten-Terrain-Set für die MITTERNACHTSZONE
		(Level 25-45, siehe expansion-concepts.md Abschnitt 1.1): enge
		Einstiegs-Passage -> offene Kaverne mit Lavaspalten -> monumentaler
		Arena-Eingang "Der Tiefenfürst" als Meilenstein-Landmark.

	NAMENSKONVENTION:
		- Model.PrimaryPart = "ChunkBase" (die Grundfläche, CSG-Result)
		- Model-Attribute: "Zone" = "MidnightZone"

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 0, 120) -- Vor Ausführung anpassen (Portal-Richtung: -Z = Richtung Hub)
local CHUNK_SIZE = 110
local BASE_THICKNESS = 3
local RANDOM_SEED = 5003
local LANE_HALF_WIDTH = 6 -- eng: Höhlenpassage statt offener Sichtachse
-- // ----------------------------------------------------------------------

local rng = Random.new(RANDOM_SEED)
local HALF = CHUNK_SIZE / 2
local BASE_TOP_Y = BASE_THICKNESS / 2

local ROCK_COLORS = {
	Color3.fromRGB(24, 24, 28),
	Color3.fromRGB(32, 30, 34),
	Color3.fromRGB(40, 37, 40),
}

local LAVA_COLOR = Color3.fromRGB(255, 96, 28)
local LAVA_GLOW_COLOR = Color3.fromRGB(255, 150, 60)

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

local function newLavaLight(parent, brightness, range)
	local light = Instance.new("PointLight")
	light.Color = LAVA_GLOW_COLOR
	light.Brightness = brightness or 2.5
	light.Range = range or 14
	light.Shadows = false
	light.Parent = parent
end

local function inHubLane(localX)
	return math.abs(localX) < LANE_HALF_WIDTH
end

local function randomOffLanePosition(marginX, marginZ)
	for _ = 1, 6 do
		local x = rng:NextNumber(-HALF + marginX, HALF - marginX)
		local z = rng:NextNumber(-HALF + marginZ, HALF - marginZ)
		if not inHubLane(x) then
			return x, z
		end
	end
	local x = LANE_HALF_WIDTH + rng:NextNumber(1, 5)
	if rng:NextNumber() < 0.5 then
		x = -x
	end
	return x, rng:NextNumber(-HALF + marginZ, HALF - marginZ)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local terrainFolder = getOrCreateFolder(assetsFolder, "Terrain")

local previous = terrainFolder:FindFirstChild("MidnightZoneTerrainChunk")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MidnightZoneTerrainChunk"
model.Parent = terrainFolder

-- 1) Grundfläche: fast schwarzer Basaltboden, plus eingesenkte Arena-Mulde --
local rawBase = newPart(
	"ChunkBase",
	Vector3.new(CHUNK_SIZE, BASE_THICKNESS, CHUNK_SIZE),
	ORIGIN,
	Color3.fromRGB(26, 25, 29),
	Enum.Material.Slate,
	model
)

local arenaLocalZ = HALF - 20 -- tiefster Punkt der Zone = Arena-Vorplatz
local arenaCutter = newPart(
	"ArenaBasinCutter",
	Vector3.new(34, 7, 34),
	ORIGIN * CFrame.new(0, BASE_TOP_Y, arenaLocalZ),
	Color3.fromRGB(26, 25, 29),
	Enum.Material.Slate,
	model
)
arenaCutter.Shape = Enum.PartType.Ball

local base = rawBase:SubtractAsync({ arenaCutter })
base.Name = "ChunkBase"
base.Color = Color3.fromRGB(26, 25, 29)
base.Material = Enum.Material.Slate
base.Anchored = true
base.CanCollide = true
base.TopSurface = Enum.SurfaceType.Smooth
base.BottomSurface = Enum.SurfaceType.Smooth
base.Parent = model

-- 2) Enge Einstiegs-Passage (Hub-seitig, -Z): dichte Wände + Überhang -------
local passageLocalZ = -HALF + 16
for _, side in ipairs({ 1, -1 }) do
	local wallX = side * (LANE_HALF_WIDTH + 3)
	local wall = newPart(
		"PassageWall" .. tostring(side),
		Vector3.new(5, 10, 26),
		ORIGIN * CFrame.new(wallX, BASE_TOP_Y + 5, passageLocalZ),
		ROCK_COLORS[1],
		Enum.Material.Rock,
		model
	)
	wall.CanCollide = true
end

local overhang = newPart(
	"PassageOverhang",
	Vector3.new(LANE_HALF_WIDTH * 2 + 12, 3, 14),
	ORIGIN * CFrame.new(0, BASE_TOP_Y + 11, passageLocalZ) * CFrame.Angles(math.rad(-6), 0, 0),
	ROCK_COLORS[2],
	Enum.Material.Rock,
	model
)
overhang.CanCollide = true

-- Schmale Lava-Ader entlang des Passagebodens markiert den einzigen Weg hindurch
local passageLavaVein = newPart(
	"PassageLavaVein",
	Vector3.new(1.2, 0.15, 20),
	ORIGIN * CFrame.new(0, BASE_TOP_Y + 0.1, passageLocalZ),
	LAVA_COLOR,
	Enum.Material.Neon,
	model
)
passageLavaVein.CanCollide = false
newLavaLight(passageLavaVein, 2, 16)

-- 3) Offene Hauptkaverne: Stalagmiten, Stalaktiten, verstreute Brocken ------
for i = 1, 8 do
	local size = rng:NextNumber(1.6, 4.2)
	local offsetX, offsetZ = randomOffLanePosition(4, 20)
	offsetZ = math.clamp(offsetZ, -HALF + 25, arenaLocalZ - 22)
	newPart(
		"CaveBoulder" .. i,
		Vector3.new(size, size * 0.85, size),
		ORIGIN * CFrame.new(offsetX, BASE_TOP_Y + size * 0.4, offsetZ) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0),
		ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)],
		Enum.Material.Rock,
		model
	)
end

local STALAGMITE_COUNT = 6
for i = 1, STALAGMITE_COUNT do
	local offsetX, offsetZ = randomOffLanePosition(6, 22)
	offsetZ = math.clamp(offsetZ, -HALF + 25, arenaLocalZ - 20)
	local tiers = 3
	local currentY = BASE_TOP_Y
	local baseSize = rng:NextNumber(2.6, 3.8)
	local tierParts = {}
	for tier = 1, tiers do
		local shrink = 1 - (tier - 1) * 0.3
		local w = baseSize * shrink
		local h = rng:NextNumber(2.6, 4)
		local overlap = h * 0.2
		local tierCFrame = ORIGIN
			* CFrame.new(offsetX + rng:NextNumber(-0.4, 0.4), currentY + h / 2 - overlap, offsetZ + rng:NextNumber(-0.4, 0.4))
			* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		table.insert(tierParts, newPart("Stalagmite" .. i .. "_T" .. tier, Vector3.new(w, h, w), tierCFrame, ROCK_COLORS[1], Enum.Material.Rock, model))
		currentY += h - overlap
	end
	local first = table.remove(tierParts, 1)
	local stalagmite = first:UnionAsync(tierParts)
	stalagmite.Name = "Stalagmite" .. i
	stalagmite.Color = ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)]
	stalagmite.Material = Enum.Material.Rock
	stalagmite.Anchored = true
	stalagmite.CanCollide = true
	stalagmite.TopSurface = Enum.SurfaceType.Smooth
	stalagmite.BottomSurface = Enum.SurfaceType.Smooth
	stalagmite.Parent = model
end

local STALACTITE_COUNT = 5
local CEILING_Y = BASE_TOP_Y + 20
for i = 1, STALACTITE_COUNT do
	local offsetX, offsetZ = randomOffLanePosition(6, 22)
	offsetZ = math.clamp(offsetZ, -HALF + 25, arenaLocalZ - 20)
	local h = rng:NextNumber(5, 9)
	local wTop = rng:NextNumber(2, 3)
	local top = newPart(
		"Stalactite" .. i .. "_Top",
		Vector3.new(wTop, h * 0.55, wTop),
		ORIGIN * CFrame.new(offsetX, CEILING_Y - h * 0.275, offsetZ),
		ROCK_COLORS[2],
		Enum.Material.Rock,
		model
	)
	top.CanCollide = false
	local tip = newPart(
		"Stalactite" .. i .. "_Tip",
		Vector3.new(wTop * 0.4, h * 0.45, wTop * 0.4),
		ORIGIN * CFrame.new(offsetX, CEILING_Y - h * 0.55 - h * 0.225, offsetZ),
		ROCK_COLORS[1],
		Enum.Material.Rock,
		model
	)
	tip.CanCollide = false
end

-- Lavaspalten & -pools als Licht-Wegweiser durch die Kaverne ----------------
local LAVA_FISSURE_COUNT = 4
for i = 1, LAVA_FISSURE_COUNT do
	local cx, cz = randomOffLanePosition(6, 22)
	cz = math.clamp(cz, -HALF + 28, arenaLocalZ - 18)
	local rotY = rng:NextNumber(0, 360)
	local segCount = 3
	for seg = 1, segCount do
		local along = (seg - (segCount + 1) / 2) * 2.4
		local jitter = rng:NextNumber(-0.6, 0.6)
		local veinCFrame = ORIGIN
			* CFrame.new(cx, BASE_TOP_Y + 0.1, cz)
			* CFrame.Angles(0, math.rad(rotY), 0)
			* CFrame.new(jitter, 0, along)
		local vein = newPart(
			"LavaFissure" .. i .. "_" .. seg,
			Vector3.new(1 + rng:NextNumber(0, 0.6), 0.15, 2.6),
			veinCFrame,
			LAVA_COLOR,
			Enum.Material.Neon,
			model
		)
		vein.CanCollide = false
		if seg == 2 then
			newLavaLight(vein, 2.5, 18)
		end
	end
end

local LAVA_POOL_COUNT = 3
for i = 1, LAVA_POOL_COUNT do
	local px, pz = randomOffLanePosition(8, 24)
	pz = math.clamp(pz, -HALF + 28, arenaLocalZ - 16)
	local pool = newPart(
		"LavaPool" .. i,
		Vector3.new(rng:NextNumber(4, 6), 0.3, rng:NextNumber(4, 6)),
		ORIGIN * CFrame.new(px, BASE_TOP_Y + 0.15, pz),
		LAVA_COLOR,
		Enum.Material.Neon,
		model
	)
	pool.Shape = Enum.PartType.Cylinder
	pool.CFrame = pool.CFrame * CFrame.Angles(0, 0, math.rad(90))
	pool.CanCollide = false
	newLavaLight(pool, 3, 20)
end

-- 4) Landmark: Arena-Eingang "Der Tiefenfürst" -------------------------------
local gateLocalZ = HALF - 8
local gateMass = newPart(
	"GateMass",
	Vector3.new(26, 16, 6),
	ORIGIN * CFrame.new(0, BASE_TOP_Y + 8, gateLocalZ),
	ROCK_COLORS[1],
	Enum.Material.Rock,
	model
)
local doorCutter = newPart(
	"GateDoorCutter",
	Vector3.new(10, 12, 8),
	ORIGIN * CFrame.new(0, BASE_TOP_Y + 6, gateLocalZ),
	ROCK_COLORS[1],
	Enum.Material.Rock,
	model
)
doorCutter.Shape = Enum.PartType.Cylinder
-- Rotation um die Y-Achse dreht die Zylinderachse (standardmäßig lokal X) auf
-- die Welt-Z-Achse, sodass der Zylinder waagerecht durch die Torwand-Tiefe
-- verläuft (statt senkrecht) -> sauber ausgeschnittener, ovaler Torbogen.
doorCutter.CFrame = doorCutter.CFrame * CFrame.Angles(0, math.rad(90), 0)

local gate = gateMass:SubtractAsync({ doorCutter })
gate.Name = "TiefenfuerstGate"
gate.Color = ROCK_COLORS[1]
gate.Material = Enum.Material.Rock
gate.Anchored = true
gate.CanCollide = true
gate.TopSurface = Enum.SurfaceType.Smooth
gate.BottomSurface = Enum.SurfaceType.Smooth
gate.Parent = model

-- Lava-Ader über dem Torbogen als bedrohlicher Akzent
local gateVein = newPart(
	"GateLavaVein",
	Vector3.new(11, 0.6, 0.3),
	ORIGIN * CFrame.new(0, BASE_TOP_Y + 12.2, gateLocalZ - 3.1),
	LAVA_COLOR,
	Enum.Material.Neon,
	model
)
gateVein.CanCollide = false
newLavaLight(gateVein, 3.5, 24)

-- Zwei von Lava-Adern durchzogene Felsnadeln flankieren das Tor (CSG-Union)
local SPIRE_OFFSETS = { -16, 16 }
for i, offsetX in ipairs(SPIRE_OFFSETS) do
	local tiers = 4
	local currentY = BASE_TOP_Y
	local baseSize = rng:NextNumber(5.5, 7)
	local tierParts = {}
	for tier = 1, tiers do
		local shrink = 1 - (tier - 1) * 0.2
		local w = baseSize * shrink
		local h = rng:NextNumber(5, 7)
		local overlap = h * 0.15
		local tierCFrame = ORIGIN
			* CFrame.new(offsetX + rng:NextNumber(-0.5, 0.5), currentY + h / 2 - overlap, gateLocalZ + rng:NextNumber(-0.5, 0.5))
			* CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0)
		table.insert(tierParts, newPart("GateSpire" .. i .. "_T" .. tier, Vector3.new(w, h, w), tierCFrame, ROCK_COLORS[1], Enum.Material.Rock, model))
		currentY += h - overlap
	end
	local first = table.remove(tierParts, 1)
	local spire = first:UnionAsync(tierParts)
	spire.Name = "GateSpire" .. i
	spire.Color = ROCK_COLORS[2]
	spire.Material = Enum.Material.Rock
	spire.Anchored = true
	spire.CanCollide = true
	spire.TopSurface = Enum.SurfaceType.Smooth
	spire.BottomSurface = Enum.SurfaceType.Smooth
	spire.Parent = model

	local vein = newPart(
		"GateSpireVein" .. i,
		Vector3.new(0.3, currentY - BASE_TOP_Y - 1, 0.3),
		ORIGIN * CFrame.new(offsetX, BASE_TOP_Y + (currentY - BASE_TOP_Y) / 2, gateLocalZ + baseSize / 2 + 0.2),
		LAVA_COLOR,
		Enum.Material.Neon,
		model
	)
	vein.CanCollide = false
end

-- Lava-Ring um den eingesenkten Arena-Vorplatz (Erwartungsspannung vor dem Boss)
local RING_ROCK_COUNT = 10
for i = 1, RING_ROCK_COUNT do
	local angle = (i / RING_ROCK_COUNT) * math.pi * 2
	local radius = 16
	local rx = math.cos(angle) * radius
	local rz = arenaLocalZ + math.sin(angle) * radius
	local emberRock = newPart(
		"ArenaRingEmber" .. i,
		Vector3.new(1.4, 1, 1.4),
		ORIGIN * CFrame.new(rx, BASE_TOP_Y + 0.4, rz),
		ROCK_COLORS[2],
		Enum.Material.Rock,
		model
	)
	emberRock.CanCollide = false
	local crack = newPart(
		"ArenaRingCrack" .. i,
		Vector3.new(0.5, 0.15, 0.9),
		ORIGIN * CFrame.new(rx, BASE_TOP_Y + 0.95, rz),
		LAVA_COLOR,
		Enum.Material.Neon,
		model
	)
	crack.CanCollide = false
end

model.PrimaryPart = base
model:SetAttribute("Zone", "MidnightZone")

print("[Abyssara] MidnightZoneTerrainChunk created under Workspace.Assets.Terrain")
