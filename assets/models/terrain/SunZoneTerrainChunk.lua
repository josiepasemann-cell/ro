--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Terrain-Chunk
	Name: SunZoneTerrainChunk (v2 – ausgebaut)

	Angewandte Design-Prinzipien (siehe /home/user/ro/docs/terrain-design-notes.md
	für die vollständige Recherche-Zusammenfassung):
		1. Verticality/Höhenrhythmus – Grundfläche ist keine reine Ebene mehr:
		   eine per CSG-Subtraktion (NegateOperation) in den Sandboden
		   eingesenkte, sanfte Mulde ("Tidal Basin") plus zwei aufgeschichtete,
		   sonnengebleichte Dünenhügel sorgen für echte Höhenunterschiede statt
		   nur flacher Deko-Klötze.
		2. Landmarks/Points of Interest – zwei klar lesbare Wegmarken: der
		   "Sonnentor"-Felsbogen (CSG-Union) am Hub-seitigen Rand und ein
		   gestrandetes Schiffswrack tiefer in der Zone.
		3. Sichtachsen/Leading the Eye – eine bewusst freigehaltene "Hub-Gasse"
		   (Sichtachse) führt vom Felsbogen quer durch die Zone; von Dünenrücken
		   auf beiden Seiten eingerahmt, lenkt sie Blick & Bewegung.
		4. Silhouetten-Lesbarkeit (Low-Poly) – Landmarks bestehen aus wenigen,
		   großen, eindeutigen Blockformen statt vieler Kleinteile.
		5. Farbpalette/Kontrast – warme, helle Sand-/Korallentöne für die
		   Tutorial-Stimmung, mit Farbbänderung (helle Bergkuppen) als billiger
		   Tiefenhinweis.
		6. Deko-Dichte-Rhythmus – dichte Deko-Taschen rund um beide Landmarks,
		   dazwischen bewusst offene, ruhige Sandflächen (Spannungsrhythmus statt
		   Gleichverteilung).
		7. Performance-Grenzen – ein Terrain-Part (CSG-Ergebnis) statt Roblox-
		   Smooth-Terrain (bessere Kontrolle/Determinismus für ein Buildscript),
		   CSG-Union/-Subtract für komplexe Formen statt Dutzender Einzelteile,
		   PartCount pro Chunk bewusst auf niedrigem zwei- bis unterem
		   dreistelligem Bereich gehalten.

	Beschreibung:
		Stilisiertes Low-Poly Meeresboden-Terrain-Set für die SONNENZONE
		(Tutorial/Start-Zone, Level 1-10): heller, sandiger Meeresboden mit
		sanfter Mulde, zwei Dünenhügeln, einem Felsbogen-Landmark ("Sonnentor")
		nahe des Hubs und einem gestrandeten Schiffswrack als zweitem Landmark,
		umgeben von wechselnd dichten/offenen Deko-Taschen (Steine, Korallen).

	NAMENSKONVENTION:
		- Model.PrimaryPart = "ChunkBase" (die Grundfläche, jetzt ein CSG-Result)
		- Model-Attribute: "Zone" = "SunZone"

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(120, 0, 0) -- Vor Ausführung anpassen (Portal-Richtung: -X = Richtung Hub)
local CHUNK_SIZE = 100 -- Studs, quadratische Grundfläche
local BASE_THICKNESS = 3
local DUNE_COUNT = 14
local ROCK_COUNT = 10
local CORAL_ACCENT_COUNT = 8
local RANDOM_SEED = 3001 -- fix für reproduzierbares Ergebnis
local LANE_HALF_WIDTH = 8 -- Breite der freigehaltenen Hub-Sichtachse (lokale Z-Achse)
-- // ----------------------------------------------------------------------

local rng = Random.new(RANDOM_SEED)
local HALF = CHUNK_SIZE / 2
local BASE_TOP_Y = BASE_THICKNESS / 2

local SAND_COLORS = {
	Color3.fromRGB(238, 217, 176),
	Color3.fromRGB(230, 206, 160),
	Color3.fromRGB(244, 226, 190),
}

local ROCK_COLORS = {
	Color3.fromRGB(205, 195, 180),
	Color3.fromRGB(214, 202, 186),
}

local CORAL_COLORS = {
	Color3.fromRGB(255, 170, 150),
	Color3.fromRGB(255, 205, 130),
	Color3.fromRGB(150, 230, 210),
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
	wedge.CanCollide = true
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
end

-- Sichtachse Richtung Hub: hält die lokale Z-Nähe der Mittelachse frei von Deko.
local function inHubSightLane(localZ)
	return math.abs(localZ) < LANE_HALF_WIDTH
end

-- Liefert eine zufällige Position außerhalb der Sichtachse (für Deko-Streuung).
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

local previous = terrainFolder:FindFirstChild("SunZoneTerrainChunk")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "SunZoneTerrainChunk"
model.Parent = terrainFolder

-- 1) Grundfläche: heller Sandboden MIT eingesenkter Mulde (Verticality) -----
-- CSG-Subtraktion einer großen, flachen Kugel erzeugt eine sanfte, runde
-- Senke im Sandboden statt einer reinen flachen Platte.
local rawBase = newPart(
	"ChunkBase",
	Vector3.new(CHUNK_SIZE, BASE_THICKNESS, CHUNK_SIZE),
	ORIGIN,
	Color3.fromRGB(233, 212, 170),
	Enum.Material.Sand,
	model
)

local basinX, basinZ = 8, -26 -- abseits der Hub-Sichtachse
local basinCutter = newPart(
	"BasinCutter",
	Vector3.new(34, 7, 34), -- horizontaler Radius 17, vertikaler Radius 3.5
	ORIGIN * CFrame.new(basinX, BASE_TOP_Y, basinZ),
	Color3.fromRGB(233, 212, 170),
	Enum.Material.Sand,
	model
)
basinCutter.Shape = Enum.PartType.Ball

local base = rawBase:SubtractAsync({ basinCutter })
base.Name = "ChunkBase"
base.Color = Color3.fromRGB(233, 212, 170)
base.Material = Enum.Material.Sand
base.Anchored = true
base.CanCollide = true
base.TopSurface = Enum.SurfaceType.Smooth
base.BottomSurface = Enum.SurfaceType.Smooth
base.Parent = model

-- 2) Zwei Dünenhügel (echte Höhe statt Deko-Klötze) -------------------------
-- Gestapelte, verjüngende Tiers mit heller "Sonnenkuppe" als Farbbänderung.
local HILL_SITES = {
	{ x = -HALF + 14, z = -20 }, -- flankiert den Felsbogen
	{ x = 26, z = 30 }, -- Rückgrat hinter dem Schiffswrack
}
for i, site in ipairs(HILL_SITES) do
	local tiers = 3
	local currentY = BASE_TOP_Y
	local baseSize = rng:NextNumber(16, 20)
	for tier = 1, tiers do
		local shrink = 1 - (tier - 1) * 0.32
		local w = baseSize * shrink
		local h = rng:NextNumber(2.2, 3.2)
		local rotY = rng:NextNumber(0, 360)
		local color = tier == tiers and Color3.fromRGB(248, 234, 200) or SAND_COLORS[rng:NextInteger(1, #SAND_COLORS)]
		local hillCFrame = ORIGIN
			* CFrame.new(site.x, currentY + h / 2, site.z)
			* CFrame.Angles(0, math.rad(rotY), 0)
		local tierPart = newPart("Hill" .. i .. "_Tier" .. tier, Vector3.new(w, h, w), hillCFrame, color, Enum.Material.Sand, model)
		tierPart.CanCollide = tier == 1
		currentY += h
	end
end

-- 3) Sichtachsen-Rahmung: zwei Dünenrücken entlang der Hub-Gasse ------------
for _, side in ipairs({ 1, -1 }) do
	local ridgeZ = side * (LANE_HALF_WIDTH + 4)
	local ridge = newPart(
		"LaneRidge" .. tostring(side),
		Vector3.new(CHUNK_SIZE - 20, 2.6, 6),
		ORIGIN * CFrame.new(2, BASE_TOP_Y + 1.3, ridgeZ),
		SAND_COLORS[2],
		Enum.Material.Sand,
		model
	)
	ridge.CanCollide = false
end

-- 4) Landmark A: "Sonnentor" – Felsbogen als CSG-Union, rahmt die Hub-Sicht -
local archX, archZ = -HALF + 8, 0
local pillarHeight = 9
local pillarL = newPart(
	"ArchPillarL",
	Vector3.new(3, pillarHeight, 3.4),
	ORIGIN * CFrame.new(archX, BASE_TOP_Y + pillarHeight / 2, archZ - 6),
	Color3.fromRGB(196, 176, 150),
	Enum.Material.Rock,
	model
)
local pillarR = newPart(
	"ArchPillarR",
	Vector3.new(3, pillarHeight, 3.4),
	ORIGIN * CFrame.new(archX, BASE_TOP_Y + pillarHeight / 2, archZ + 6),
	Color3.fromRGB(196, 176, 150),
	Enum.Material.Rock,
	model
)
local lintel = newPart(
	"ArchLintel",
	Vector3.new(3.6, 3, 15),
	ORIGIN * CFrame.new(archX, BASE_TOP_Y + pillarHeight + 1.5, archZ),
	Color3.fromRGB(196, 176, 150),
	Enum.Material.Rock,
	model
)

local rockArch = pillarL:UnionAsync({ pillarR, lintel })
rockArch.Name = "SunGateArch"
rockArch.Color = Color3.fromRGB(200, 182, 156)
rockArch.Material = Enum.Material.Rock
rockArch.Anchored = true
rockArch.CanCollide = true
rockArch.TopSurface = Enum.SurfaceType.Smooth
rockArch.BottomSurface = Enum.SurfaceType.Smooth
rockArch.Parent = model

-- Dichte Deko-Tasche rund um den Felsbogen (Deko-Rhythmus: dicht am Landmark)
for i = 1, 5 do
	local px = archX + rng:NextNumber(3, 12)
	local pz = archZ + rng:NextNumber(-14, 14)
	if not inHubSightLane(pz) then
		local size = rng:NextNumber(1, 2.2)
		newPart(
			"GateRock" .. i,
			Vector3.new(size, size * 0.8, size),
			ORIGIN * CFrame.new(px, BASE_TOP_Y + size * 0.4, pz) * CFrame.Angles(0, math.rad(rng:NextNumber(0, 360)), 0),
			ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)],
			Enum.Material.Rock,
			model
		)
	end
end

-- 5) Landmark B: gestrandetes Schiffswrack (blocky Silhouette) -------------
local wreckX, wreckZ = 30, 30
local wreckCFrame = ORIGIN * CFrame.new(wreckX, BASE_TOP_Y, wreckZ) * CFrame.Angles(0, math.rad(24), math.rad(-14))

local hull = newPart("WreckHull", Vector3.new(18, 4, 6), wreckCFrame * CFrame.new(0, 2.4, 0), Color3.fromRGB(92, 78, 62), Enum.Material.WoodPlanks, model)
local bow = newWedge("WreckBow", Vector3.new(6, 4, 6), wreckCFrame * CFrame.new(11, 2.4, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(92, 78, 62), Enum.Material.WoodPlanks, model)
local stern = newPart("WreckStern", Vector3.new(4, 5.4, 7), wreckCFrame * CFrame.new(-10, 3.1, 0), Color3.fromRGB(78, 66, 52), Enum.Material.WoodPlanks, model)
local deckBreak = newPart("WreckDeckBreak", Vector3.new(5, 1.6, 6.4), wreckCFrame * CFrame.new(1, 4.4, 0) * CFrame.Angles(0, 0, math.rad(18)), Color3.fromRGB(70, 60, 48), Enum.Material.WoodPlanks, model)
deckBreak.CanCollide = false
local mastStump = newPart("WreckMastStump", Vector3.new(1, 6, 1), wreckCFrame * CFrame.new(-2, 6.4, 0) * CFrame.Angles(0, 0, math.rad(-10)), Color3.fromRGB(60, 50, 40), Enum.Material.Wood, model)
mastStump.CanCollide = false
local ribA = newPart("WreckRibA", Vector3.new(0.6, 3, 5.6), wreckCFrame * CFrame.new(6, 4.6, 0) * CFrame.Angles(0, 0, math.rad(12)), Color3.fromRGB(70, 60, 48), Enum.Material.WoodPlanks, model)
ribA.CanCollide = false
local ribB = newPart("WreckRibB", Vector3.new(0.6, 2.4, 5.2), wreckCFrame * CFrame.new(-4.5, 4.2, 0) * CFrame.Angles(0, 0, math.rad(-16)), Color3.fromRGB(70, 60, 48), Enum.Material.WoodPlanks, model)
ribB.CanCollide = false

-- Dichte Deko-Tasche rund um das Wrack (Muscheln/Korallen erobern den Rumpf)
for i = 1, 6 do
	local px = wreckX + rng:NextNumber(-12, 12)
	local pz = wreckZ + rng:NextNumber(-10, 10)
	if not inHubSightLane(pz) then
		if i % 2 == 0 then
			local size = rng:NextNumber(1.2, 2.4)
			newPart(
				"WreckRock" .. i,
				Vector3.new(size, size * 0.8, size),
				ORIGIN * CFrame.new(px, BASE_TOP_Y + size * 0.4, pz),
				ROCK_COLORS[rng:NextInteger(1, #ROCK_COLORS)],
				Enum.Material.Rock,
				model
			)
		else
			local height = rng:NextNumber(1.4, 2.8)
			local coral = newPart(
				"WreckCoral" .. i,
				Vector3.new(0.8, height, 0.8),
				ORIGIN * CFrame.new(px, BASE_TOP_Y + height / 2, pz),
				CORAL_COLORS[rng:NextInteger(1, #CORAL_COLORS)],
				Enum.Material.SmoothPlastic,
				model
			)
			coral.Shape = Enum.PartType.Cylinder
			coral.CFrame = coral.CFrame * CFrame.Angles(0, 0, math.rad(90))
			coral.CanCollide = false
		end
	end
end

-- 6) Zonenweite, gleichmäßig-ruhige Streuung außerhalb der Sichtachse ------
for i = 1, DUNE_COUNT do
	local w = rng:NextNumber(4, 9)
	local d = rng:NextNumber(4, 9)
	local h = rng:NextNumber(0.6, 1.8)
	local offsetX, offsetZ = randomOffLanePosition(4, 4)
	local rotY = rng:NextNumber(0, 360)

	local duneCFrame = ORIGIN
		* CFrame.new(offsetX, BASE_TOP_Y + h / 2, offsetZ)
		* CFrame.Angles(0, math.rad(rotY), 0)

	local dune = newPart(
		"Dune" .. i,
		Vector3.new(w, h, d),
		duneCFrame,
		SAND_COLORS[rng:NextInteger(1, #SAND_COLORS)],
		Enum.Material.Sand,
		model
	)
	dune.CanCollide = false
end

for i = 1, ROCK_COUNT do
	local size = rng:NextNumber(1.2, 2.6)
	local offsetX, offsetZ = randomOffLanePosition(3, 3)
	local rotY = rng:NextNumber(0, 360)

	local rockCFrame = ORIGIN
		* CFrame.new(offsetX, BASE_TOP_Y + size / 2, offsetZ)
		* CFrame.Angles(rng:NextNumber(-0.15, 0.15), math.rad(rotY), rng:NextNumber(-0.15, 0.15))

	newPart(
		"SandRock" .. i,
		Vector3.new(size, size * 0.8, size),
		rockCFrame,
		Color3.fromRGB(205, 195, 180),
		Enum.Material.Rock,
		model
	)
end

for i = 1, CORAL_ACCENT_COUNT do
	local offsetX, offsetZ = randomOffLanePosition(5, 5)
	local height = rng:NextNumber(1.5, 3)

	local coralCFrame = ORIGIN * CFrame.new(offsetX, BASE_TOP_Y + height / 2, offsetZ)
	local coral = newPart(
		"CoralAccent" .. i,
		Vector3.new(0.8, height, 0.8),
		coralCFrame,
		CORAL_COLORS[rng:NextInteger(1, #CORAL_COLORS)],
		Enum.Material.SmoothPlastic,
		model
	)
	coral.Shape = Enum.PartType.Cylinder
	coral.CFrame = coralCFrame * CFrame.Angles(0, 0, math.rad(90))
	coral.CanCollide = false
end

model.PrimaryPart = base
model:SetAttribute("Zone", "SunZone")

print("[Abyssara] SunZoneTerrainChunk (v2) erzeugt unter Workspace.Assets.Terrain")
