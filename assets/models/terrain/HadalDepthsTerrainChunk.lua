--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Terrain-Chunk
	Name: HadalDepthsTerrainChunk (neu, Phase 3 / Erweiterungskonzept 2.8)

	Angewandte Design-Prinzipien (siehe /home/user/ro/docs/terrain-design-notes.md
	für die vollständige Recherche-Zusammenfassung):
		1. Extremste Verticality – die begehbare Plateau-Fläche deckt nur einen
		   Teil des Chunk-Footprints ab; jenseits der Abgrund-Kante gibt es
		   bewusst KEINEN Boden mehr (echter Blick in einen bodenlosen
		   Abgrund statt einer weiteren Deko-Fläche), verstärkt durch winzige,
		   weit unten verstreute Glanzpunkte ("Deep Glints") als Tiefen-Cue.
		2. Landmark – ein monumentales Kristallspitzen-Ensemble (CSG-Union
		   mehrerer Kristallschalen) direkt an der Abgrund-Kante, mit einer
		   schmalen, freischwebenden Aussichtsplattform ("Void-Tech"-Look) als
		   dramatischer Zonen-Höhepunkt.
		3. Sichtachsen/Leading the Eye – wie in Mitternachtszone (selbe
		   Hub-Achse) bleibt eine "Void-Gasse" frei, die geradewegs auf die
		   Aussichtsplattform zuführt; Kristallfelder links/rechts werden zur
		   Kante hin bewusst größer (Skalen-Crescendo lenkt den Blick).
		4. Silhouetten-Lesbarkeit/Formsprache – scharfkantige, spitze
		   Kristallformen (WedgePart-Splitter) statt organischer Rundungen:
		   bewusster stilistischer Kontrast zu den organischeren Formen der
		   ersten drei Zonen (fremdartig/"Void-Tech" statt Fels/Kelp/Sand).
		5. Farbpalette/Kontrast – fast schwarzes Abgrund-Violett als Basis,
		   dazu ein knalliges Neon-Quartett (Cyan/Magenta/Violett/Teal) als
		   einzige Lichtquelle – stärkster Palettenkontrast aller vier Zonen.
		6. Deko-Dichte-Rhythmus – dichte Kristallfelder in Kantennähe, ruhige,
		   fast leere Fläche direkt vor der Kante (Ehrfurchts-Moment vor dem
		   großen Ausblick), analog zum "empty space as breathing room"-Prinzip.
		7. Performance-Grenzen – CSG-Union für die beiden Hero-Kristallcluster
		   an der Kante statt Dutzender Einzelteile; kleinere Feld-Kristalle
		   bleiben einzelne, günstige WedgeParts ohne Kollision.

	Beschreibung:
		Kristallines Abgrund-Terrain-Set für die HADAL-TIEFE (Level 45+,
		Endgame/Prestige-Zone, siehe expansion-concepts.md Abschnitt 2.8):
		begehbares Plateau mit Kristallfeldern, das an einer schroffen Kante
		in einen bodenlosen Abgrund übergeht, gekrönt von einem monumentalen
		Kristallspitzen-Landmark mit Aussichtsplattform.

	NAMENSKONVENTION:
		- Model.PrimaryPart = "ChunkBase" (die Plateau-Grundfläche)
		- Model-Attribute: "Zone" = "HadalDepths"

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 0, -120) -- Vor Ausführung anpassen (Portal-Richtung: +Z = Richtung Hub)
local CHUNK_SIZE = 120 -- Bounding-Footprint; das begehbare Plateau ist kleiner (s. FLOOR_DEPTH)
local FLOOR_DEPTH = 78 -- Tiefe (Z) der begehbaren Plateau-Fläche, Rest = offener Abgrund
local BASE_THICKNESS = 3
local RANDOM_SEED = 6004
local LANE_HALF_WIDTH = 9 -- freie "Void-Gasse" Richtung Aussichtsplattform
-- // ----------------------------------------------------------------------

local rng = Random.new(RANDOM_SEED)
local HALF = CHUNK_SIZE / 2
local BASE_TOP_Y = BASE_THICKNESS / 2

-- Abgrund-Kante: Plateau reicht von localZ = cliffZ .. +HALF, dahinter (Richtung
-- -HALF) gibt es absichtlich keinen Boden mehr.
local cliffZ = HALF - FLOOR_DEPTH
local floorCenterZ = (cliffZ + HALF) / 2

local ROCK_COLORS = {
	Color3.fromRGB(20, 16, 28),
	Color3.fromRGB(28, 22, 36),
}

local CRYSTAL_PALETTE = {
	Color3.fromRGB(70, 230, 255), -- Cyan
	Color3.fromRGB(230, 70, 235), -- Magenta
	Color3.fromRGB(150, 90, 255), -- Violett
	Color3.fromRGB(60, 235, 190), -- Teal
}

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

local function newWedge(name, size, cframe, color, material, parent)
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color
	wedge.Material = material
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
end

local function inVoidLane(localX)
	return math.abs(localX) < LANE_HALF_WIDTH
end

-- Zufallsposition auf dem begehbaren Plateau, außerhalb der Void-Gasse.
local function randomOnPlateauOffLane(marginX, marginBackZ, marginFrontZ)
	for _ = 1, 6 do
		local x = rng:NextNumber(-HALF + marginX, HALF - marginX)
		local z = rng:NextNumber(cliffZ + marginBackZ, HALF - marginFrontZ)
		if not inVoidLane(x) then
			return x, z
		end
	end
	local x = LANE_HALF_WIDTH + rng:NextNumber(1, 5)
	if rng:NextNumber() < 0.5 then
		x = -x
	end
	return x, rng:NextNumber(cliffZ + marginBackZ, HALF - marginFrontZ)
end

-- Ein einzelner Kristallsplitter (WedgePart), leicht zufällig gekippt/gedreht.
local function spawnCrystalShard(name, centerX, centerZ, minH, maxH, colorList, material, parent)
	local h = rng:NextNumber(minH, maxH)
	local w = h * rng:NextNumber(0.14, 0.22)
	local d = h * rng:NextNumber(0.55, 0.85)
	local rotY = rng:NextNumber(0, 360)
	local tiltX = rng:NextNumber(-9, 9)
	local tiltZ = rng:NextNumber(-9, 9)
	local px = centerX + rng:NextNumber(-1.6, 1.6)
	local pz = centerZ + rng:NextNumber(-1.6, 1.6)
	local shardCFrame = ORIGIN
		* CFrame.new(px, BASE_TOP_Y + h * 0.4, pz)
		* CFrame.Angles(0, math.rad(rotY), 0)
		* CFrame.Angles(math.rad(tiltX), 0, math.rad(tiltZ))
	return newWedge(name, Vector3.new(w, h, d), shardCFrame, colorList[rng:NextInteger(1, #colorList)], material, parent)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local terrainFolder = getOrCreateFolder(assetsFolder, "Terrain")

local previous = terrainFolder:FindFirstChild("HadalDepthsTerrainChunk")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "HadalDepthsTerrainChunk"
model.Parent = terrainFolder

-- 1) Begehbares Plateau (bewusst kleiner als der Chunk-Footprint) ----------
local base = newPart(
	"ChunkBase",
	Vector3.new(CHUNK_SIZE, BASE_THICKNESS, FLOOR_DEPTH),
	ORIGIN * CFrame.new(0, 0, floorCenterZ),
	Color3.fromRGB(22, 18, 30),
	Enum.Material.Slate,
	model
)

-- 2) Schroffe Abgrund-Kante: jagged Klippenwand, die tief unter das Plateau
--    hinabreicht (Andeutung von Bodenlosigkeit statt einer sichtbaren Sohle).
local CLIFF_SEGMENT_COUNT = 9
for i = 1, CLIFF_SEGMENT_COUNT do
	local segX = -HALF + (i - 0.5) * (CHUNK_SIZE / CLIFF_SEGMENT_COUNT)
	local jitterZ = rng:NextNumber(-1.2, 1.2)
	local lipHeight = rng:NextNumber(0.5, 2.4)
	local dropDepth = rng:NextNumber(30, 55)
	local wall = newPart(
		"CliffFace" .. i,
		Vector3.new(CHUNK_SIZE / CLIFF_SEGMENT_COUNT + 0.6, dropDepth, 6),
		ORIGIN * CFrame.new(segX, BASE_TOP_Y - dropDepth / 2 + lipHeight, cliffZ + jitterZ),
		ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)],
		Enum.Material.Rock,
		model
	)
	wall.CanCollide = true

	if i % 3 == 0 then
		-- Vereinzelte Kristalladern direkt in der Klippenwand -> Kristalle
		-- wachsen selbst aus dem nackten Fels, nicht nur auf dem Plateau.
		spawnCrystalShard("CliffVeinCrystal" .. i, segX, cliffZ - 1.5, 3, 6, CRYSTAL_PALETTE, Enum.Material.Neon, model)
	end
end

-- 3) Kristallfelder auf dem Plateau: Skalen-Crescendo Richtung Kante --------
local FIELD_CLUSTER_COUNT = 12
for c = 1, FIELD_CLUSTER_COUNT do
	local cx, cz = randomOnPlateauOffLane(6, 6, 10)
	-- Je näher an der Kante (kleineres cz-cliffZ), desto größer die Kristalle.
	local proximityToEdge = 1 - math.clamp((cz - cliffZ) / FLOOR_DEPTH, 0, 1)
	local minH = 2 + proximityToEdge * 3
	local maxH = 4 + proximityToEdge * 6
	local shardsPerCluster = rng:NextInteger(2, 4)
	local material = rng:NextNumber() < 0.7 and Enum.Material.Neon or Enum.Material.Glass
	for s = 1, shardsPerCluster do
		spawnCrystalShard("FieldCrystal_C" .. c .. "_" .. s, cx, cz, minH, maxH, CRYSTAL_PALETTE, material, model)
	end
end

-- Ruhige, fast leere Fläche unmittelbar vor der Kante (Ehrfurchts-Moment) --
-- (bewusst keine Deko-Platzierung im Bereich cliffZ .. cliffZ+9 außerhalb der
-- Hero-Landmark-Zone -> siehe margin in randomOnPlateauOffLane / Abschnitt 4)

-- 4) Landmark: Kristallspitzen-Ensemble + Aussichtsplattform an der Kante --
local landmarkZ = cliffZ + 6
local HERO_OFFSETS = { -13, 13 }
for i, offsetX in ipairs(HERO_OFFSETS) do
	local shardCount = 5
	local shardParts = {}
	for s = 1, shardCount do
		table.insert(shardParts, spawnCrystalShard("HeroShard" .. i .. "_" .. s, offsetX, landmarkZ, 12, 22, CRYSTAL_PALETTE, Enum.Material.Neon, model))
	end
	local first = table.remove(shardParts, 1)
	local heroCrystal = first:UnionAsync(shardParts)
	heroCrystal.Name = "HeroCrystalCluster" .. i
	heroCrystal.Color = CRYSTAL_PALETTE[i % #CRYSTAL_PALETTE + 1]
	heroCrystal.Material = Enum.Material.Neon
	heroCrystal.Anchored = true
	heroCrystal.CanCollide = true
	heroCrystal.TopSurface = Enum.SurfaceType.Smooth
	heroCrystal.BottomSurface = Enum.SurfaceType.Smooth
	heroCrystal.Parent = model
end

-- Freischwebende Aussichtsplattform ("Void-Tech"): schmale Glasplatte, die
-- über die Kante hinaus in den Abgrund ragt, an zwei dünnen Neon-Streben
-- "verankert" (rein dekorativ, kein Gameplay-Geländer).
local platform = newPart(
	"OverlookPlatform",
	Vector3.new(10, 0.6, 16),
	ORIGIN * CFrame.new(0, BASE_TOP_Y + 0.3, cliffZ - 6),
	Color3.fromRGB(200, 230, 240),
	Enum.Material.Glass,
	model
)
platform.CanCollide = true
platform.Transparency = 0.25

for _, side in ipairs({ 1, -1 }) do
	local strut = newPart(
		"OverlookStrut" .. tostring(side),
		Vector3.new(0.4, 14, 0.4),
		ORIGIN * CFrame.new(side * 4, BASE_TOP_Y - 6.5, cliffZ - 6),
		CRYSTAL_PALETTE[1],
		Enum.Material.Neon,
		model
	)
	strut.CanCollide = false
end

-- 5) "Deep Glints": winzige, weit verstreute Lichtpunkte tief im Abgrund ---
-- Reiner Tiefen-Parallaxe-Trick: verstärkt den Eindruck von Bodenlosigkeit.
local DEEP_GLINT_COUNT = 7
for i = 1, DEEP_GLINT_COUNT do
	local gx = rng:NextNumber(-HALF + 6, HALF - 6)
	local gz = rng:NextNumber(-HALF + 4, cliffZ - 4)
	local gy = -rng:NextNumber(24, 85)
	local glint = newPart(
		"DeepGlint" .. i,
		Vector3.new(0.6, 0.6, 0.6),
		ORIGIN * CFrame.new(gx, gy, gz),
		CRYSTAL_PALETTE[rng:NextInteger(1, #CRYSTAL_PALETTE)],
		Enum.Material.Neon,
		model
	)
	glint.Shape = Enum.PartType.Ball
	glint.CanCollide = false
end

-- 6) Vereinzelte dunkle Abgrund-Felsen als Bodenanker (Silhouette-Kontrast) -
for i = 1, 6 do
	local bx, bz = randomOnPlateauOffLane(5, 5, 14)
	local size = rng:NextNumber(1.6, 3.4)
	newPart(
		"PlateauBoulder" .. i,
		Vector3.new(size, size * 0.8, size),
		ORIGIN * CFrame.new(bx, BASE_TOP_Y + size * 0.4, bz) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0),
		ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)],
		Enum.Material.Rock,
		model
	)
end

model.PrimaryPart = base
model:SetAttribute("Zone", "HadalDepths")

print("[Abyssara] HadalDepthsTerrainChunk created under Workspace.Assets.Terrain")
