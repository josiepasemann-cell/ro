--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: ToxinPuffer ("Toxin Puffer")
	Rarity (Platzhalter): Rare
	Event: ToxicTide
	Beschreibung:
		Runder, aufgeblasener Kugelfisch-Körper, sickly gelb-grün, mit
		zweireihigen, nach außen zeigenden dunklen Stacheln (WedgeParts),
		unregelmäßigen dunkelolivenen Gift-Flecken (Geometrie-Muster,
		"ToxicBlotches"), heller Bauch-Gegenschattierung und einer leuchtend
		grünen Bauchnaht (Neon). Körper trägt Material Pebble für eine raue,
		warzige Haut statt der vorherigen glatten Kugel. Event-exklusive
		Kreatur des "Toxic Tide"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-
		  ("Puffing"-Skalierung 1.0 -> 1.15 -> 1.0 auf 2.5s-Zyklus, siehe Doc).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("ToxicTide"), analog "Zone" bei
		  Zonen-Kreaturen.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-15, 6, 105)
local RARITY = "Rare"
local ZONE = "Global"
local EVENT = "ToxicTide"
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
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Block-Part + SpecialMesh(Sphere): echtes Ellipsoid statt der immer
-- kugelrunden Shape=Ball-Darstellung - für flach angedrückte Flecken/Patches.
local function newMeshBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Texture-Platzhalter (siehe assets/textures/README.md-Konvention): leere
-- `Texture`-Instanz mit TextureKey-Attribut + "KeyedTexture"-Tag, bleibt bis
-- zum Einspielen des PNG-Texturpacks unsichtbar (Runtime-Skript blendet sie
-- aus). Nur auf flachen Block/Wedge-Flächen sinnvoll, nicht auf Ellipsoiden.
local function newKeyedTexture(part, key, face, color, studsPerU, studsPerV, transparency)
	local tex = Instance.new("Texture")
	tex.Name = "Tex_" .. key
	tex.Texture = ""
	tex.Face = face
	tex.Color3 = color
	tex.Transparency = transparency or 0
	tex.StudsPerTileU = studsPerU or 3
	tex.StudsPerTileV = studsPerV or 3
	tex:SetAttribute("TextureKey", key)
	CollectionService:AddTag(tex, "KeyedTexture")
	tex.Parent = part
	return tex
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("ToxinPuffer")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ToxinPuffer"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(170, 210, 60)
local BELLY_COLOR = Color3.fromRGB(212, 232, 150)
local GLOW_COLOR = Color3.fromRGB(150, 255, 60)
local SPINE_COLOR = Color3.fromRGB(70, 90, 30)
local BLOTCH_COLOR = Color3.fromRGB(95, 120, 35)

-- 1) Aufgeblasener Kugelkörper, Material Pebble für raue, warzige Toxin-Haut --------
local body = newPart("Body", Vector3.new(3, 3, 3), ORIGIN, BODY_COLOR, Enum.Material.Pebble, model)
body.Shape = Enum.PartType.Ball

-- 1b) Helle Bauch-Gegenschattierung (Countershading), flach an die Unterseite
--     angedrückt, überlappt den Körper -------------------------------------------
local bellyPatch = newMeshBall(
	"BellyPatch",
	Vector3.new(2.5, 1.4, 2.5),
	ORIGIN * CFrame.new(0, -1.05, 0),
	BELLY_COLOR,
	Enum.Material.Pebble,
	model
)

-- 1c) Unregelmäßige Gift-Flecken (Geometrie-Musterung "ToxicBlotches"), flach
--     angedrückte Ellipsoide, radial über den Rücken verteilt, in die Kugel
--     eingesenkt -> ersetzt die vorherige rein einfarbige Haut ---------------------
for i = 1, 6 do
	local angle = math.rad(60 * (i - 1) + 15)
	local elevation = math.rad(10 + 22 * ((i % 3)))
	local dir = CFrame.Angles(0, angle, 0) * CFrame.Angles(elevation, 0, 0)
	local pos = dir * CFrame.new(0, 0, 1.42)
	local blotch = newMeshBall(
		"ToxicBlotch" .. i,
		Vector3.new(0.55 + (i % 2) * 0.15, 0.22, 0.5 + (i % 3) * 0.1),
		ORIGIN * pos * CFrame.Angles(0, angle, 0),
		BLOTCH_COLOR,
		Enum.Material.Pebble,
		model
	)
end

-- 2) Leuchtende Bauchnaht ------------------------------------------------------
local belly = newPart(
	"BellySeam",
	Vector3.new(2.4, 0.3, 2.4),
	ORIGIN * CFrame.new(0, -1.2, 0),
	GLOW_COLOR,
	Enum.Material.Neon,
	model
)
belly.Shape = Enum.PartType.Cylinder
belly.CFrame = belly.CFrame * CFrame.Angles(0, 0, math.rad(90))

-- 3) Zwei Augen mit Pupille + Glanzpunkt ---------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.62, 0.4, 1.05)
	local eyeWhite = newPart(
		"EyeWhite" .. i,
		Vector3.new(0.45, 0.45, 0.4),
		eyeCFrame,
		Color3.fromRGB(235, 240, 220),
		Enum.Material.SmoothPlastic,
		model
	)
	eyeWhite.Shape = Enum.PartType.Ball

	local eye = newPart(
		"Eye" .. i,
		Vector3.new(0.3, 0.3, 0.3),
		eyeCFrame * CFrame.new(0, 0, 0.18),
		Color3.fromRGB(20, 20, 20),
		Enum.Material.SmoothPlastic,
		model
	)
	eye.Shape = Enum.PartType.Ball

	local highlight = newPart(
		"EyeHighlight" .. i,
		Vector3.new(0.1, 0.1, 0.1),
		eyeCFrame * CFrame.new(0.08, 0.08, 0.3),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.Neon,
		model
	)
	highlight.Shape = Enum.PartType.Ball
end

-- 3b) Kleines Maul --------------------------------------------------------------------
local mouth = newPart(
	"Mouth",
	Vector3.new(0.6, 0.15, 0.3),
	ORIGIN * CFrame.new(0, -0.35, 1.35),
	SPINE_COLOR,
	Enum.Material.SmoothPlastic,
	model
)
mouth.Shape = Enum.PartType.Cylinder
mouth.CFrame = mouth.CFrame * CFrame.Angles(0, 0, math.rad(90))

-- 4) Stacheln, ZWEI Reihen (Äquator + oberer Ring) radial verteilt, in den Körper
--    eingesenkt -> deutlich stachligere, weniger "glatte Kugel"-Silhouette --------
for i = 1, 8 do
	local angle = math.rad(45 * (i - 1))
	local elevation = math.rad(20 * ((i % 3) - 1))
	local dir = CFrame.Angles(0, angle, 0) * CFrame.Angles(elevation, 0, 0)
	local offset = dir * CFrame.new(0, 0, 1.3)
	local spineCFrame = ORIGIN * offset * CFrame.Angles(math.rad(-90), 0, 0)

	local spine = Instance.new("WedgePart")
	spine.Name = "Spine" .. i
	spine.Size = Vector3.new(0.25, 0.6, 0.25)
	spine.CFrame = spineCFrame
	spine.Color = SPINE_COLOR
	spine.Material = Enum.Material.SmoothPlastic
	spine.Anchored = true
	spine.CanCollide = false
	spine.TopSurface = Enum.SurfaceType.Smooth
	spine.BottomSurface = Enum.SurfaceType.Smooth
	spine.Parent = model

	-- flache Rücken-Face jedes 2. Stachels: Texture-Platzhalter für die
	-- feine Warzenstruktur an der Stachelbasis (Block-taugliche Fläche)
	if i % 2 == 0 then
		newKeyedTexture(spine, "ToxicBlotches", Enum.NormalId.Back, BLOTCH_COLOR, 1, 1, 0.1)
	end
end

for i = 1, 6 do
	local angle = math.rad(60 * (i - 1) + 30)
	local elevation = math.rad(55)
	local dir = CFrame.Angles(0, angle, 0) * CFrame.Angles(elevation, 0, 0)
	local offset = dir * CFrame.new(0, 0, 1.28)
	local spineCFrame = ORIGIN * offset * CFrame.Angles(math.rad(-90), 0, 0)

	local spine = Instance.new("WedgePart")
	spine.Name = "SpineTop" .. i
	spine.Size = Vector3.new(0.2, 0.45, 0.2)
	spine.CFrame = spineCFrame
	spine.Color = SPINE_COLOR
	spine.Material = Enum.Material.SmoothPlastic
	spine.Anchored = true
	spine.CanCollide = false
	spine.TopSurface = Enum.SurfaceType.Smooth
	spine.BottomSurface = Enum.SurfaceType.Smooth
	spine.Parent = model
end

-- 5) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Toxin Puffer")

print("[Abyssara] ToxinPuffer created under Workspace.Assets.Creatures")
