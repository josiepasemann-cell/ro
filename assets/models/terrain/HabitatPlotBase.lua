--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Terrain / Plot-Struktur
	Name: HabitatPlotBase
	Beschreibung:
		Modulare, sechseckige Habitat-Plot-Plattform (~60 Studs Kante-zu-Kante /
		"flat-to-flat"), die als persönliche Baugrundfläche jedes Spielers dient.
		Die Plattform ist in ein sichtbares Baufelder-Raster aus 6 Sektoren unterteilt
		(Neon-Trennlinien + Slot-Marker-Scheiben), auf denen später Gebäude platziert
		werden können (Snap-to-Grid durch den Code-Agenten).

	GEOMETRIE-TRICK:
		Das perfekte Sechseck wird performant per CSG als Schnittmenge (IntersectAsync)
		dreier rotierter Quader (0°, 60°, 120°) erzeugt -> nur 1 finales Part, sehr
		performant statt vieler Einzel-Parts.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "PlatformBase" (das Sechseck-Part selbst)
		- 6x Attachment unter PlatformBase, benannt "BuildField1" .. "BuildField6"
		  markieren die Zentren der Baufelder (für Placement-/Snap-Logik).
		- Model-Attribute: "FlatToFlatSize" (number), "GridFieldCount" (number)

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 0, 0) -- Vor Ausführung anpassen für gewünschte Position
local FLAT_TO_FLAT = 60 -- Studs, Kante-zu-Kante Breite des Sechsecks
local THICKNESS = 4 -- Studs, Höhe der Plattform
local FIELD_COUNT = 6
local FIELD_RING_RADIUS = 20 -- Abstand der Baufeld-Zentren von der Plot-Mitte
local FIELD_MARKER_DIAMETER = 15
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

-- Keyed-Textur-Platzhalter (siehe assets/textures/): Texture-Instanz mit
-- Attribut "TextureKey" + Tag "KeyedTexture", Texture-Property bleibt leer
-- bis die Nutzerin die PNGs hochlädt. StudsPerTileU/V bewusst groß (6-16)
-- fuer Boden-/Gelaendeflaechen.
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

-- Rundlicher, organisch-kartoonig geformter Fels/Kiesel statt scharfkantiger
-- Box (Kugel-Shape mit leicht abgeflachter Hoehe).
local function newRock(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	part.Shape = Enum.PartType.Ball
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local terrainFolder = getOrCreateFolder(assetsFolder, "Terrain")

-- Idempotenz: vorheriges Modell entfernen
local previous = terrainFolder:FindFirstChild("HabitatPlotBase")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "HabitatPlotBase"
model.Parent = terrainFolder

-- 1) Sechseck-Plattform per CSG-Schnittmenge dreier Quader ---------------
local LONG = FLAT_TO_FLAT * 3 -- lang genug, damit der Schnitt sauber das Sechseck ergibt

local slabA = newPart("SlabA", Vector3.new(FLAT_TO_FLAT, THICKNESS, LONG), ORIGIN, Color3.fromRGB(255, 255, 255), Enum.Material.Slate, Workspace)
local slabB = newPart("SlabB", Vector3.new(FLAT_TO_FLAT, THICKNESS, LONG), ORIGIN * CFrame.Angles(0, math.rad(60), 0), Color3.fromRGB(255, 255, 255), Enum.Material.Slate, Workspace)
local slabC = newPart("SlabC", Vector3.new(FLAT_TO_FLAT, THICKNESS, LONG), ORIGIN * CFrame.Angles(0, math.rad(120), 0), Color3.fromRGB(255, 255, 255), Enum.Material.Slate, Workspace)

local hexPlatform = slabA:IntersectAsync({ slabB, slabC })
hexPlatform.Name = "PlatformBase"
hexPlatform.Color = Color3.fromRGB(120, 128, 140) -- kühles Grau-Blau, Korallengestein/Beton-Look
hexPlatform.Material = Enum.Material.Cobblestone
hexPlatform.Anchored = true
hexPlatform.CanCollide = true
hexPlatform.TopSurface = Enum.SurfaceType.Smooth
hexPlatform.BottomSurface = Enum.SurfaceType.Smooth
hexPlatform.Parent = model
addKeyedTexture(hexPlatform, "StoneTiles", Enum.NormalId.Top, 6, 6, Color3.fromRGB(140, 146, 156), 0.05)

-- 1b) Ein paar dicke, rundliche Basalt-Brocken am Sechseck-Rand (kartoonig,
-- bricht die glatte Kante organisch auf, bleibt außerhalb der Baufelder)
for i = 1, 6 do
	local angle = math.rad(60 * (i - 1) + 30)
	local edgeRadius = FLAT_TO_FLAT * 0.52
	local pos = ORIGIN * CFrame.new(math.cos(angle) * edgeRadius, THICKNESS / 2, math.sin(angle) * edgeRadius)
	local rock = newRock("PlotEdgeRock" .. i, Vector3.new(2.4, 1.8, 2.4), pos, Color3.fromRGB(90, 96, 106), Enum.Material.Basalt, model)
	rock.CanCollide = false
end

-- 2) Sichtbares Baufelder-Raster: 6 Trennlinien (Sektorspeichen) ---------
local topY = ORIGIN.Position.Y + THICKNESS / 2 + 0.05
for i = 1, FIELD_COUNT do
	local angle = math.rad(60 * (i - 1) + 30) -- versetzt zu den Feldzentren
	local lineLength = FLAT_TO_FLAT / 2 - 1
	local lineCFrame = ORIGIN
		* CFrame.new(0, THICKNESS / 2 + 0.05, 0)
		* CFrame.Angles(0, angle, 0)
		* CFrame.new(0, 0, -lineLength / 2)
	local line = newPart("GridDivider" .. i, Vector3.new(0.4, 0.1, lineLength), lineCFrame, Color3.fromRGB(70, 220, 230), Enum.Material.Neon, model)
	line.CanCollide = false
end

-- 3) 6 Baufeld-Marker (Scheiben) + Attachments für Snap-Logik ------------
for i = 1, FIELD_COUNT do
	local angle = math.rad(60 * (i - 1))
	local slotOffset = Vector3.new(math.cos(angle) * FIELD_RING_RADIUS, 0, math.sin(angle) * FIELD_RING_RADIUS)
	local slotCFrame = ORIGIN * CFrame.new(slotOffset) * CFrame.new(0, THICKNESS / 2 + 0.06, 0) * CFrame.Angles(0, 0, math.rad(90))

	local marker = newPart(
		"BuildField" .. i,
		Vector3.new(0.15, FIELD_MARKER_DIAMETER, FIELD_MARKER_DIAMETER),
		slotCFrame,
		Color3.fromRGB(70, 220, 230),
		Enum.Material.Neon,
		model
	)
	marker.Shape = Enum.PartType.Cylinder
	marker.CanCollide = false
	marker.Transparency = 0.55

	local attachment = Instance.new("Attachment")
	attachment.Name = "BuildField" .. i
	attachment.Position = Vector3.new(0, THICKNESS / 2 + 0.06, 0)
	attachment.WorldCFrame = ORIGIN * CFrame.new(slotOffset) * CFrame.new(0, THICKNESS / 2 + 0.06, 0)
	attachment.Parent = hexPlatform
end

model.PrimaryPart = hexPlatform
model:SetAttribute("FlatToFlatSize", FLAT_TO_FLAT)
model:SetAttribute("GridFieldCount", FIELD_COUNT)

print("[Abyssara] HabitatPlotBase created under Workspace.Assets.Terrain")
