--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Event-Kosmetik-Dekoration (Plot-Baufeld)
	Name: TreasurePile ("Treasure Pile" – Treasure Tide Shop-Item, Abschnitt
	1.3: "gold coin/chest cluster")
	Beschreibung:
		Häufchen aus goldenen Münzen mit einer halb geöffneten Schatztruhe.
		Kaufbar im Treasure-Tide-Event-Shop für 60 Doubloons.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (siehe assets/models/README.md):
		- Model.PrimaryPart = "Base" (Sockel-Part)
		- model:SetAttribute("DecorationId", "TreasurePile")
		- model:SetAttribute("Event", "TreasureTide")
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
local ORIGIN = CFrame.new(60, 0.5, -100) -- Vor Ausführung anpassen für gewünschte Position
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
-- Size -> gestrecktes, toy-like Ellipsoid statt Kiste (nur für runde Deko-Bits;
-- die Truhe selbst bleibt bewusst blockig mit gerundeten Kanten/Trims).
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

local previous = decorationsFolder:FindFirstChild("TreasurePile")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TreasurePile"
model.Parent = decorationsFolder

-- 1) Sockel-Base: rundlicher, toy-like Sandhügel -----------------------------
local base = newOvalPart("Base", Vector3.new(4, 1.0, 4), ORIGIN, Color3.fromRGB(210, 200, 160), Enum.Material.Sand, model)
base.CanCollide = true
newTexture("CoinPile", Enum.NormalId.Top, base, { studsU = 1, studsV = 1, color = Color3.fromRGB(255, 215, 90), transparency = 0.55 })

-- 2) Truhe (Korpus + angewinkelter Deckel) - bleibt bewusst blockig als
-- "hartes Material"-Requisit, bekommt aber gerundete Trim-Kanten (Zylinder) ------
local chestBody = newPart(
	"ChestBody",
	Vector3.new(2, 1.1, 1.4),
	ORIGIN * CFrame.new(-0.6, 0.8, 0),
	Color3.fromRGB(120, 75, 35),
	Enum.Material.WoodPlanks,
	model
)
chestBody.CanCollide = true
newTexture("WoodPlanks", Enum.NormalId.Front, chestBody, { studsU = 0.6, studsV = 0.6, color = Color3.fromRGB(90, 58, 28), transparency = 0.35 })

local chestLid = newPart(
	"ChestLid",
	Vector3.new(2, 0.25, 1.5),
	ORIGIN * CFrame.new(-0.6, 1.5, -0.55) * CFrame.Angles(math.rad(-55), 0, 0),
	Color3.fromRGB(140, 90, 45),
	Enum.Material.WoodPlanks,
	model
)

local chestTrim = newPart(
	"ChestTrim",
	Vector3.new(2.05, 0.15, 1.45),
	ORIGIN * CFrame.new(-0.6, 1.05, 0),
	Color3.fromRGB(230, 190, 70),
	Enum.Material.Foil,
	model
)
newTexture("GoldFoil", Enum.NormalId.Front, chestTrim, { studsU = 0.8, studsV = 0.8, color = Color3.fromRGB(250, 220, 140), transparency = 0.4 })

-- Gerundete Eckbeschläge (Zylinder mit runden Kappen statt scharfer Kanten)
for _, dx in ipairs({ -0.9, 0.9 }) do
	local corner = newPart("ChestCorner" .. (dx < 0 and "L" or "R"), Vector3.new(0.18, 1.15, 0.18), ORIGIN * CFrame.new(-0.6 + dx, 0.8, 0.68), Color3.fromRGB(230, 190, 70), Enum.Material.Foil, model)
	corner.Shape = Enum.PartType.Cylinder
end

-- 3) Münzhaufen (gestapelte, leicht rotierte flache Zylinder) -------------------
for i = 1, 10 do
	local angle = math.rad(36 * i)
	local radius = 0.6 + (i % 3) * 0.25
	local coin = newPart(
		"Coin" .. i,
		Vector3.new(0.18, 0.62, 0.62),
		ORIGIN * CFrame.new(0.8 + math.cos(angle) * radius, 0.35 + (i % 4) * 0.12, math.sin(angle) * radius)
			* CFrame.Angles(0, angle, math.rad(90)),
		Color3.fromRGB(255, 215, 90),
		Enum.Material.Foil,
		model
	)
	coin.Shape = Enum.PartType.Cylinder
end

-- 3b) Kleine goldene Ringe/Schmuckstücke, die aus dem Münzhaufen ragen -----------
for i = 1, 2 do
	local ring = newPart(
		"JewelRing" .. i,
		Vector3.new(0.1, 0.35, 0.35),
		ORIGIN * CFrame.new(1.3 + i * 0.35, 0.15, -0.3 + i * 0.5) * CFrame.Angles(math.rad(70), math.rad(20 * i), 0),
		Color3.fromRGB(255, 225, 130),
		Enum.Material.Metal,
		model
	)
	ring.Shape = Enum.PartType.Cylinder
end

-- 4) Glänzende Neon-Akzente (Funkeln aus der Truhe) ------------------------------
for i = 1, 3 do
	local sparkle = newPart(
		"Sparkle" .. i,
		Vector3.new(0.25, 0.25, 0.25),
		ORIGIN * CFrame.new(-0.6 + 0.3 * (i - 2), 1.65 + i * 0.1, -0.1),
		Color3.fromRGB(255, 240, 180),
		Enum.Material.Neon,
		model
	)
	sparkle.Shape = Enum.PartType.Ball
end

-- 5) Glühlicht -------------------------------------------------------------------
local light = Instance.new("PointLight")
light.Name = "GoldGlow"
light.Color = Color3.fromRGB(255, 220, 130)
light.Range = 10
light.Brightness = 1.8
light.Shadows = false
light.Parent = chestTrim

model.PrimaryPart = base
model:SetAttribute("DecorationId", "TreasurePile")
model:SetAttribute("Event", "TreasureTide")

print("[Abyssara] TreasurePile created under Workspace.Assets.Decorations")
