--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Event-Kosmetik-Dekoration (Plot-Baufeld)
	Name: VenomDrip ("Venom Drip" – Toxic Tide Shop-Item, Abschnitt 1.3)
	Beschreibung:
		Tropfende, giftgrüne Kristallspitze auf einem kleinen Sockel. Kaufbar
		im Toxic-Tide-Event-Shop für 60 Venom Pearls und auf einem Baufeld des
		Spieler-Plots platzierbar (reine Kosmetik, keine Einkommens-Logik).

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (siehe assets/models/README.md,
	Abschnitt "decorations/" für den vollen Vertrag):
		- Model.PrimaryPart = "Base" (Sockel-Part) -> Ansatzpunkt für
		  Platzierungslogik/Snap-to-Grid, analog zu Gebäuden.
		- model:SetAttribute("DecorationId", "VenomDrip")
		- model:SetAttribute("Event", "ToxicTide")
		- Footprint bewusst klein (< 15 Stud Baufeld-Durchmesser, siehe
		  HabitatPlotBase.lua FIELD_MARKER_DIAMETER = 15) - passt auf EIN
		  BuildField.
		- Wird zur Laufzeit unter Workspace.Assets.Decorations abgelegt
		  (analog zu Assets.Buildings/Assets.Pickups).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein
		Script unter ServerScriptService einfügen und einmal laufen lassen.
		Reine Geometrie-Erzeugung, keine Gameplay-Logik. Wiederholtes
		Ausführen ist sicher (idempotent).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 1, -100) -- Vor Ausführung anpassen für gewünschte Position
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

-- Organisches, ovales/kapselförmiges Teil: Block-Part + SpecialMesh(Sphere),
-- non-uniform Size -> gestrecktes, toy-like Ellipsoid statt Kiste.
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

local previous = decorationsFolder:FindFirstChild("VenomDrip")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "VenomDrip"
model.Parent = decorationsFolder

-- 1) Sockel-Base: rundlicher, toy-like Fels ------------------------------------
local base = newOvalPart("Base", Vector3.new(4, 1.0, 4), ORIGIN, Color3.fromRGB(45, 55, 30), Enum.Material.Basalt, model)
base.CanCollide = true
newTexture("ToxicBlotches", Enum.NormalId.Top, base, { studsU = 1.5, studsV = 1.5, color = Color3.fromRGB(90, 200, 40), transparency = 0.25 })

-- 2) Hauptspitze: bulböser, kartoonig-runder Kristallstamm aus 3 gestapelten,
-- überlappenden Ellipsoid-Segmenten (statt eckiger Kegel) ----------------------
local segmentHeights = { 2.6, 2.0, 1.4 }
local segmentWidths = { 2.4, 1.7, 1.1 }
local stackY = 0.3
for i, height in ipairs(segmentHeights) do
	local width = segmentWidths[i]
	local segment = newOvalPart(
		"SpikeSegment" .. i,
		Vector3.new(width, height, width),
		ORIGIN * CFrame.new(0, stackY + height / 2 - 0.3, 0),
		Color3.fromRGB(90, 200, 40),
		Enum.Material.Glass,
		model
	)
	segment.Transparency = 0.15
	stackY += height * 0.75
end

-- 3) Leuchtender Kern innerhalb der Spitze (gestrecktes Ellipsoid) -------------
local core = newOvalPart(
	"GlowCore",
	Vector3.new(0.7, 4.8, 0.7),
	ORIGIN * CFrame.new(0, 3.1, 0),
	Color3.fromRGB(150, 255, 60),
	Enum.Material.Neon,
	model
)

-- 4) Zwei kleine, rundliche Nebenspitzen -----------------------------------------
for i, angle in ipairs({ 55, -70 }) do
	local rad = math.rad(angle)
	local sub = newOvalPart(
		"MinorSpike" .. i,
		Vector3.new(0.8, 1.8, 0.8),
		ORIGIN * CFrame.new(math.cos(rad) * 1.2, 1.2, math.sin(rad) * 1.2) * CFrame.Angles(0, 0, math.rad(15 * (i == 1 and 1 or -1))),
		Color3.fromRGB(110, 220, 50),
		Enum.Material.Glass,
		model
	)
	sub.Transparency = 0.2
end

-- 5) Dripping-Tropfen (kleine, runde Neon-Kugeln unterhalb der Spitze) --------
for i = 1, 3 do
	local drip = newPart(
		"VenomDrop" .. i,
		Vector3.new(0.4, 0.4, 0.4),
		ORIGIN * CFrame.new(0.4 * (i - 2), stackY - i * 0.9, 0.3 * (i - 2)),
		Color3.fromRGB(170, 255, 70),
		Enum.Material.Neon,
		model
	)
	drip.Shape = Enum.PartType.Ball
end

-- 5b) Kleine Ranken/Blasen am Sockel für mehr Lebendigkeit ------------------------
for i = 1, 3 do
	local angle = math.rad(120 * i + 15)
	local bubble = newPart(
		"VenomBubble" .. i,
		Vector3.new(0.32, 0.32, 0.32),
		ORIGIN * CFrame.new(math.cos(angle) * 1.7, 0.3, math.sin(angle) * 1.7),
		Color3.fromRGB(160, 255, 80),
		Enum.Material.Neon,
		model
	)
	bubble.Shape = Enum.PartType.Ball
end

-- 6) Glow-Licht ------------------------------------------------------------------
local light = Instance.new("PointLight")
light.Name = "VenomGlow"
light.Color = Color3.fromRGB(140, 255, 60)
light.Range = 12
light.Brightness = 2.2
light.Shadows = false
light.Parent = core

model.PrimaryPart = base
model:SetAttribute("DecorationId", "VenomDrip")
model:SetAttribute("Event", "ToxicTide")

print("[Abyssara] VenomDrip created under Workspace.Assets.Decorations")
