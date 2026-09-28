--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Event-Kosmetik-Dekoration (Plot-Baufeld)
	Name: JackOCoral ("Jack-o-Coral" – Spooky Tide Shop-Item, Abschnitt 1.3)
	Beschreibung:
		Geschnitzter, leuchtender Korallenkopf mit Kürbis-Gesicht-Schnitzerei.
		Kaufbar im Spooky-Tide-Event-Shop für 70 Spirit Motes und auf einem
		Baufeld des Spieler-Plots platzierbar (reine Kosmetik).

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (siehe assets/models/README.md):
		- Model.PrimaryPart = "Base" (Sockel-Part)
		- model:SetAttribute("DecorationId", "JackOCoral")
		- model:SetAttribute("Event", "SpookyTide")
		- Footprint klein (< 15 Stud Baufeld-Durchmesser), passt auf EIN
		  BuildField.
		- Wird unter Workspace.Assets.Decorations abgelegt.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein
		Script unter ServerScriptService einfügen und einmal laufen lassen.
		Reine Geometrie-Erzeugung, keine Gameplay-Logik. Idempotent.
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(12, 1.5, -100) -- Vor Ausführung anpassen für gewünschte Position
-- // ----------------------------------------------------------------------

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
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

-- Organisches, ovales Teil: Block-Part + SpecialMesh(Sphere), non-uniform
-- Size -> gestrecktes, toy-like Ellipsoid statt Kiste.
local function newOvalPart(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = part
	return part
end

-- Texture-Instanz mit Projekt-Texturschlüssel (siehe assets/textures/README.md).
local function newTexture(key, face, part, opts)
	opts = opts or {}
	local tex = Instance.new("Texture")
	tex.Name = "Tex_" .. key
	tex.Texture = ""
	tex.Face = face
	tex.StudsPerTileU = opts.studsU or 3
	tex.StudsPerTileV = opts.studsV or 3
	tex.Color3 = opts.color or Color3.new(1, 1, 1)
	tex.Transparency = opts.transparency or 0
	tex:SetAttribute("TextureKey", key)
	CollectionService:AddTag(tex, "KeyedTexture")
	tex.Parent = part
	return tex
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local decorationsFolder = getOrCreateFolder(assetsFolder, "Decorations")

local previous = decorationsFolder:FindFirstChild("JackOCoral")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "JackOCoral"
model.Parent = decorationsFolder

-- 1) Sockel-Base: rundlicher, toy-like Fels ------------------------------------
local base = newOvalPart("Base", Vector3.new(3.5, 1.0, 3.5), ORIGIN, Color3.fromRGB(40, 55, 45), Enum.Material.Basalt, model)
base.CanCollide = true
newTexture("StoneTiles", Enum.NormalId.Top, base, { studsU = 1.5, studsV = 1.5, color = Color3.fromRGB(50, 65, 55), transparency = 0.2 })

-- 1b) Korallenstamm: verbindet Base mit dem Kopf, rundlich-organisch -------------
local stalk = newOvalPart("Stalk", Vector3.new(1.7, 1.0, 1.7), ORIGIN * CFrame.new(0, 0.5, 0), Color3.fromRGB(230, 120, 30), Enum.Material.SmoothPlastic, model)

-- Kleine Basis-Polypen rund um den Sockel für mehr Lebendigkeit -------------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 30)
	local polyp = newPart(
		"BasePolyp" .. i,
		Vector3.new(0.55, 0.55, 0.55),
		ORIGIN * CFrame.new(math.cos(angle) * 1.55, -0.15, math.sin(angle) * 1.55),
		Color3.fromRGB(255, 150, 50),
		Enum.Material.SmoothPlastic,
		model
	)
	polyp.Shape = Enum.PartType.Ball
end

-- 2) Korallenkopf (CSG-Union aus Kugel + Höckern) ------------------------------
local headParts = {}
local headBall = Instance.new("Part")
headBall.Name = "HeadBall"
headBall.Shape = Enum.PartType.Ball
headBall.Size = Vector3.new(3, 3, 3)
headBall.CFrame = ORIGIN * CFrame.new(0, 2, 0)
headBall.Color = Color3.fromRGB(255, 140, 40)
headBall.Material = Enum.Material.SmoothPlastic
headBall.Anchored = true
headBall.Parent = model
table.insert(headParts, headBall)

for i = 1, 5 do
	local angle = math.rad(72 * (i - 1))
	local bump = Instance.new("Part")
	bump.Name = "Bump" .. i
	bump.Shape = Enum.PartType.Ball
	bump.Size = Vector3.new(1.1, 1.6, 1.1)
	bump.CFrame = ORIGIN * CFrame.new(math.cos(angle) * 1.3, 3.1, math.sin(angle) * 1.3)
	bump.Color = Color3.fromRGB(255, 140, 40)
	bump.Material = Enum.Material.SmoothPlastic
	bump.Anchored = true
	bump.Parent = model
	table.insert(headParts, bump)
end

local union = headParts[1]:UnionAsync(headParts)
union.Name = "CoralHead"
union.Color = Color3.fromRGB(255, 140, 40)
union.Material = Enum.Material.SmoothPlastic
union.Anchored = true
union.CanCollide = false
union.Parent = model
for _, part in ipairs(headParts) do
	part:Destroy()
end

-- 3) Kürbis-Gesicht: 2 dreieckige Neon-Augen + Zickzack-Mund -------------------
for i, xOffset in ipairs({ -0.8, 0.8 }) do
	local eye = newPart(
		"Eye" .. i,
		Vector3.new(0.75, 0.75, 0.45),
		ORIGIN * CFrame.new(xOffset, 2.3, 1.45) * CFrame.Angles(0, 0, math.rad(45)),
		Color3.fromRGB(190, 255, 210),
		Enum.Material.Neon,
		model
	)
	eye.Shape = Enum.PartType.Wedge
end

local mouth = newOvalPart(
	"Mouth",
	Vector3.new(1.8, 0.55, 0.45),
	ORIGIN * CFrame.new(0, 1.5, 1.5),
	Color3.fromRGB(190, 255, 210),
	Enum.Material.Neon,
	model
)

-- 4) Interne Glühquelle ---------------------------------------------------------
local light = Instance.new("PointLight")
light.Name = "JackGlow"
light.Color = Color3.fromRGB(190, 255, 210)
light.Range = 12
light.Brightness = 2.5
light.Shadows = false
light.Parent = mouth

model.PrimaryPart = base
model:SetAttribute("DecorationId", "JackOCoral")
model:SetAttribute("Event", "SpookyTide")

print("[Abyssara] JackOCoral created under Workspace.Assets.Decorations")
