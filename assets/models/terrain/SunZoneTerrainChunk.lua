--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Terrain-Chunk
	Name: SunZoneTerrainChunk
	Beschreibung:
		Stilisiertes Low-Poly Meeresboden-Terrain-Set für die SONNENZONE
		(Tutorial/Start-Zone, Level 1-10): heller, sandiger Meeresboden mit
		sanften Dünen, vereinzelten hellen Steinen und ein paar kleinen
		Korallen-Akzenten. Gedacht als wiederholbares/kachelbares Terrain-
		Chunk-Modul um die Habitat-Plots herum.

	NAMENSKONVENTION:
		- Model.PrimaryPart = "ChunkBase" (die Grundfläche)
		- Model-Attribute: "Zone" = "SunZone"

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(80, 0, 0) -- Vor Ausführung anpassen für gewünschte Position
local CHUNK_SIZE = 50 -- Studs, quadratische Grundfläche
local BASE_THICKNESS = 3
local DUNE_COUNT = 10
local ROCK_COUNT = 5
local CORAL_ACCENT_COUNT = 4
local RANDOM_SEED = 3001 -- fix für reproduzierbares Ergebnis
-- // ----------------------------------------------------------------------

local rng = Random.new(RANDOM_SEED)

local SAND_COLORS = {
	Color3.fromRGB(238, 217, 176),
	Color3.fromRGB(230, 206, 160),
	Color3.fromRGB(244, 226, 190),
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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local terrainFolder = getOrCreateFolder(assetsFolder, "Terrain")

local previous = terrainFolder:FindFirstChild("SunZoneTerrainChunk")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "SunZoneTerrainChunk"
model.Parent = terrainFolder

-- 1) Grundfläche: heller Sandboden ---------------------------------------
local base = newPart(
	"ChunkBase",
	Vector3.new(CHUNK_SIZE, BASE_THICKNESS, CHUNK_SIZE),
	ORIGIN,
	Color3.fromRGB(233, 212, 170),
	Enum.Material.Sand,
	model
)

-- 2) Sanfte Dünen (niedrige, breite Blöcke, leicht verdreht) -------------
for i = 1, DUNE_COUNT do
	local w = rng:NextNumber(4, 9)
	local d = rng:NextNumber(4, 9)
	local h = rng:NextNumber(0.6, 1.8)
	local offsetX = rng:NextNumber(-CHUNK_SIZE / 2 + 4, CHUNK_SIZE / 2 - 4)
	local offsetZ = rng:NextNumber(-CHUNK_SIZE / 2 + 4, CHUNK_SIZE / 2 - 4)
	local rotY = rng:NextNumber(0, 360)

	local duneCFrame = ORIGIN
		* CFrame.new(offsetX, BASE_THICKNESS / 2 + h / 2, offsetZ)
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

-- 3) Vereinzelte helle Steine (blocky Low-Poly) ---------------------------
for i = 1, ROCK_COUNT do
	local size = rng:NextNumber(1.2, 2.6)
	local offsetX = rng:NextNumber(-CHUNK_SIZE / 2 + 3, CHUNK_SIZE / 2 - 3)
	local offsetZ = rng:NextNumber(-CHUNK_SIZE / 2 + 3, CHUNK_SIZE / 2 - 3)
	local rotY = rng:NextNumber(0, 360)

	local rockCFrame = ORIGIN
		* CFrame.new(offsetX, BASE_THICKNESS / 2 + size / 2, offsetZ)
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

-- 4) Kleine helle Korallen-Akzente (Sonnenzone = flach & lebendig) -------
local CORAL_COLORS = {
	Color3.fromRGB(255, 170, 150),
	Color3.fromRGB(255, 205, 130),
	Color3.fromRGB(150, 230, 210),
}
for i = 1, CORAL_ACCENT_COUNT do
	local offsetX = rng:NextNumber(-CHUNK_SIZE / 2 + 5, CHUNK_SIZE / 2 - 5)
	local offsetZ = rng:NextNumber(-CHUNK_SIZE / 2 + 5, CHUNK_SIZE / 2 - 5)
	local height = rng:NextNumber(1.5, 3)

	local coralCFrame = ORIGIN * CFrame.new(offsetX, BASE_THICKNESS / 2 + height / 2, offsetZ)
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

print("[Abyssara] SunZoneTerrainChunk erzeugt unter Workspace.Assets.Terrain")
