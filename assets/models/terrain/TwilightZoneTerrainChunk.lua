--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Terrain-Chunk
	Name: TwilightZoneTerrainChunk
	Beschreibung:
		Stilisiertes Low-Poly Meeresboden-Terrain-Set für die DÄMMERZONE
		(Level 10-25): dunklerer, felsiger Meeresboden mit Gesteinsbrocken
		und wogenden Kelp-Bündeln mit leicht bioluminiszenten Spitzen.

	NAMENSKONVENTION:
		- Model.PrimaryPart = "ChunkBase" (die Grundfläche)
		- Model-Attribute: "Zone" = "TwilightZone"

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-80, 0, 0) -- Vor Ausführung anpassen für gewünschte Position
local CHUNK_SIZE = 50
local BASE_THICKNESS = 3
local BOULDER_COUNT = 9
local KELP_CLUSTER_COUNT = 6
local RANDOM_SEED = 4002
-- // ----------------------------------------------------------------------

local rng = Random.new(RANDOM_SEED)

local ROCK_COLORS = {
	Color3.fromRGB(70, 72, 78),
	Color3.fromRGB(55, 57, 63),
	Color3.fromRGB(85, 88, 95),
}

local KELP_COLORS = {
	Color3.fromRGB(35, 90, 75),
	Color3.fromRGB(30, 75, 90),
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

local previous = terrainFolder:FindFirstChild("TwilightZoneTerrainChunk")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TwilightZoneTerrainChunk"
model.Parent = terrainFolder

-- 1) Grundfläche: dunkler Felsboden ---------------------------------------
local base = newPart(
	"ChunkBase",
	Vector3.new(CHUNK_SIZE, BASE_THICKNESS, CHUNK_SIZE),
	ORIGIN,
	Color3.fromRGB(48, 50, 56),
	Enum.Material.Slate,
	model
)

-- 2) Gesteinsbrocken (blocky, unterschiedlich groß) ------------------------
for i = 1, BOULDER_COUNT do
	local w = rng:NextNumber(1.5, 5)
	local h = rng:NextNumber(1.2, 4)
	local d = rng:NextNumber(1.5, 5)
	local offsetX = rng:NextNumber(-CHUNK_SIZE / 2 + 3, CHUNK_SIZE / 2 - 3)
	local offsetZ = rng:NextNumber(-CHUNK_SIZE / 2 + 3, CHUNK_SIZE / 2 - 3)
	local rotY = rng:NextNumber(0, 360)

	local boulderCFrame = ORIGIN
		* CFrame.new(offsetX, BASE_THICKNESS / 2 + h / 2, offsetZ)
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

-- 3) Kelp-Bündel (gestapelte, sich verjüngende Segmente mit Glow-Spitze) --
for c = 1, KELP_CLUSTER_COUNT do
	local clusterOffsetX = rng:NextNumber(-CHUNK_SIZE / 2 + 5, CHUNK_SIZE / 2 - 5)
	local clusterOffsetZ = rng:NextNumber(-CHUNK_SIZE / 2 + 5, CHUNK_SIZE / 2 - 5)
	local strandsInCluster = rng:NextInteger(2, 4)

	for s = 1, strandsInCluster do
		local strandX = clusterOffsetX + rng:NextNumber(-1.5, 1.5)
		local strandZ = clusterOffsetZ + rng:NextNumber(-1.5, 1.5)
		local segmentCount = rng:NextInteger(3, 5)
		local segmentHeight = rng:NextNumber(1.6, 2.4)
		local currentY = BASE_THICKNESS / 2
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
				isTip and Color3.fromRGB(90, 230, 200) or kelpColor,
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

print("[Abyssara] TwilightZoneTerrainChunk erzeugt unter Workspace.Assets.Terrain")
