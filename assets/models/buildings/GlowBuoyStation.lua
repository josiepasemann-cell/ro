--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude (Basisstufe)
	Name: GlowBuoyStation ("Lichtboje / Glow-Sammler-Station")
	Beschreibung:
		Vertikale Boje mit leuchtender Sammel-Kugel an der Spitze und drei
		kleineren, um die Boje schwebenden Sammel-Orbs. Sammelt/produziert
		"Glow Spores" (Ressource) - hier rein als Geometrie-Platzhalter.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Base" (Fundament-Part, für Placement/Snap-to-Grid)
		- Model-Attribute: "BuildingType" = "GlowBuoyStation", "Stage" = 1
		- "MainOrb": das Haupt-Glow-Part an der Bojenspitze (für spätere
		  Emission-/Partikel-Steuerung durch den Code-Agenten).
		- "OrbitOrb1".."OrbitOrb3": kleinere Satelliten-Sammel-Orbs.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-20, 1.5, 20) -- Vor Ausführung anpassen für gewünschte Position
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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local buildingsFolder = getOrCreateFolder(assetsFolder, "Buildings")

local previous = buildingsFolder:FindFirstChild("GlowBuoyStation")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowBuoyStation"
model.Parent = buildingsFolder

-- 1) Fundament-Plattform ---------------------------------------------------
local base = newPart("Base", Vector3.new(8, 1, 8), ORIGIN, Color3.fromRGB(100, 108, 118), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Mastpfahl ---------------------------------------------------------------
local mast = newPart(
	"Mast",
	Vector3.new(1, 10, 1),
	ORIGIN * CFrame.new(0, 5.5, 0),
	Color3.fromRGB(80, 86, 94),
	Enum.Material.Metal,
	model
)

-- 3) Sammelkorb (Ring aus vier Streben oben am Mast) -------------------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1))
	local offset = Vector3.new(math.cos(angle) * 1.4, 9.5, math.sin(angle) * 1.4)
	newPart(
		"BasketStrut" .. i,
		Vector3.new(0.3, 2, 0.3),
		ORIGIN * CFrame.new(offset) * CFrame.Angles(0, angle, math.rad(20)),
		Color3.fromRGB(100, 106, 114),
		Enum.Material.Metal,
		model
	)
end

-- 4) Haupt-Glow-Orb an der Spitze --------------------------------------------
local mainOrb = newPart(
	"MainOrb",
	Vector3.new(3.2, 3.2, 3.2),
	ORIGIN * CFrame.new(0, 11.5, 0),
	Color3.fromRGB(90, 240, 255),
	Enum.Material.Neon,
	model
)
mainOrb.Shape = Enum.PartType.Ball
mainOrb.CanCollide = false

-- 5) Drei kleinere umlaufende Sammel-Orbs -------------------------------------
for i = 1, 3 do
	local angle = math.rad(120 * (i - 1))
	local offset = Vector3.new(math.cos(angle) * 3.5, 7.5 + i * 0.6, math.sin(angle) * 3.5)
	local orb = newPart(
		"OrbitOrb" .. i,
		Vector3.new(1.1, 1.1, 1.1),
		ORIGIN * CFrame.new(offset),
		Color3.fromRGB(150, 255, 235),
		Enum.Material.Neon,
		model
	)
	orb.Shape = Enum.PartType.Ball
	orb.CanCollide = false
	orb.Transparency = 0.1
end

model.PrimaryPart = base
model:SetAttribute("BuildingType", "GlowBuoyStation")
model:SetAttribute("Stage", 1)

print("[Abyssara] GlowBuoyStation erzeugt unter Workspace.Assets.Buildings")
