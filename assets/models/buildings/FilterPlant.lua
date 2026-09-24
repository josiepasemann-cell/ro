--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude (Basisstufe)
	Name: FilterPlant ("Filteranlage", Ressourcen-Produktionsgebäude)
	Beschreibung:
		Kompakte, industrielle Filteranlage: zentraler Tank mit zwei seitlichen
		Nebentanks, verbunden über Rohrleitungen, plus ein Status-Leuchtlicht
		oben (Neon) als Platzhalter für spätere Produktions-Visualisierung.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Base" (Fundament-Part, für Placement/Snap-to-Grid)
		- Model-Attribute: "BuildingType" = "FilterPlant", "Stage" = 1
		- "StatusLight": Neon-Part, das der Code-Agent z.B. bei Produktion
		  pulsieren lassen kann.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(20, 1.5, -20) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("FilterPlant")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "FilterPlant"
model.Parent = buildingsFolder

-- 1) Fundament ---------------------------------------------------------------
local base = newPart("Base", Vector3.new(10, 1, 8), ORIGIN, Color3.fromRGB(95, 100, 108), Enum.Material.DiamondPlate, model)

-- 2) Zentraler Haupttank ------------------------------------------------------
local mainTankCFrame = ORIGIN * CFrame.new(0, 4, 0) * CFrame.Angles(0, 0, math.rad(90))
local mainTank = newPart("MainTank", Vector3.new(6.5, 3.6, 3.6), mainTankCFrame, Color3.fromRGB(150, 158, 168), Enum.Material.Metal, model)
mainTank.Shape = Enum.PartType.Cylinder

-- 3) Zwei seitliche Nebentanks -------------------------------------------------
local sideOffsets = { Vector3.new(0, 1.5, -2.6), Vector3.new(0, 1.5, 2.6) }
for i, offset in ipairs(sideOffsets) do
	local sideCFrame = ORIGIN * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
	local sideTank = newPart("SideTank" .. i, Vector3.new(2.8, 2, 2), sideCFrame, Color3.fromRGB(120, 128, 138), Enum.Material.Metal, model)
	sideTank.Shape = Enum.PartType.Cylinder
end

-- 4) Verbindungsrohre ----------------------------------------------------------
for i, offset in ipairs(sideOffsets) do
	local pipeCFrame = ORIGIN * CFrame.new(-2, 2.6, offset.Z * 0.6) * CFrame.Angles(0, 0, math.rad(90))
	local pipe = newPart("ConnectorPipe" .. i, Vector3.new(2.2, 0.5, 0.5), pipeCFrame, Color3.fromRGB(80, 86, 94), Enum.Material.Metal, model)
	pipe.Shape = Enum.PartType.Cylinder
end

-- 5) Vier Stützbeine ------------------------------------------------------------
for i = 1, 4 do
	local x = (i <= 2) and -3.5 or 3.5
	local z = (i % 2 == 0) and -3 or 3
	newPart(
		"SupportLeg" .. i,
		Vector3.new(0.6, 2.4, 0.6),
		ORIGIN * CFrame.new(x, 1.2, z),
		Color3.fromRGB(70, 74, 80),
		Enum.Material.Metal,
		model
	)
end

-- 6) Status-Leuchtlicht (Neon, Platzhalter für Produktionsstatus) --------------
local statusLight = newPart(
	"StatusLight",
	Vector3.new(1, 1, 1),
	ORIGIN * CFrame.new(0, 6.2, 0),
	Color3.fromRGB(80, 255, 150),
	Enum.Material.Neon,
	model
)
statusLight.Shape = Enum.PartType.Ball
statusLight.CanCollide = false

model.PrimaryPart = base
model:SetAttribute("BuildingType", "FilterPlant")
model:SetAttribute("Stage", 1)

print("[Abyssara] FilterPlant erzeugt unter Workspace.Assets.Buildings")
