--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude (Upgrade-Stufe)
	Name: FilterPlant_Stage2 ("Filteranlage", Stufe 2/3)
	Beschreibung:
		Erweiterte Filteranlage: dritter Nebentank, ein weiteres Verbindungs-
		rohr, ein zweites Status-Leuchtlicht sowie Neon-Glow-Streifen auf den
		Rohrleitungen (mehr sichtbare Struktur/Glow als Stufe 1).

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "FilterPlant_Stage2" (BuildingId "FilterPlant" +
		  "_Stage2").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  FilterPlant.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "FilterPlant", "Stage" = 2.
		- "StatusLight": Neon-Part für Produktionsstatus, unverändert
		  benannt wie Stufe 1. "StatusLight2": zusätzliches, neues
		  Status-Leuchtlicht (optionaler Zusatz-Hook für den Code-Agenten).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(30, 1.5, -140) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("FilterPlant_Stage2")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "FilterPlant_Stage2"
model.Parent = buildingsFolder

-- 1) Fundament (IDENTISCH zu FilterPlant.Base für Grid-Kompatibilität) ------
local base = newPart("Base", Vector3.new(10, 1, 8), ORIGIN, Color3.fromRGB(95, 100, 108), Enum.Material.DiamondPlate, model)

-- 2) Zentraler Haupttank (etwas größer als Stufe 1) --------------------------
local mainTankCFrame = ORIGIN * CFrame.new(0, 4.3, 0) * CFrame.Angles(0, 0, math.rad(90))
local mainTank = newPart("MainTank", Vector3.new(6.5, 4.2, 4.2), mainTankCFrame, Color3.fromRGB(160, 168, 178), Enum.Material.Metal, model)
mainTank.Shape = Enum.PartType.Cylinder

-- 3) Drei seitliche Nebentanks (1 mehr als Stufe 1) --------------------------
local sideOffsets = { Vector3.new(0, 1.5, -2.8), Vector3.new(0, 1.5, 2.8), Vector3.new(3.2, 1.5, 0) }
for i, offset in ipairs(sideOffsets) do
	local sideCFrame = ORIGIN * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
	local sideTank = newPart("SideTank" .. i, Vector3.new(2.8, 2, 2), sideCFrame, Color3.fromRGB(130, 138, 148), Enum.Material.Metal, model)
	sideTank.Shape = Enum.PartType.Cylinder
end

-- 4) Verbindungsrohre + Neon-Glow-Streifen -----------------------------------
for i, offset in ipairs(sideOffsets) do
	local pipeCFrame = ORIGIN * CFrame.new(offset.X * 0.5 - 2, 2.6, offset.Z * 0.6) * CFrame.Angles(0, 0, math.rad(90))
	local pipe = newPart("ConnectorPipe" .. i, Vector3.new(2.2, 0.5, 0.5), pipeCFrame, Color3.fromRGB(90, 96, 104), Enum.Material.Metal, model)
	pipe.Shape = Enum.PartType.Cylinder

	if i <= 2 then
		local stripeCFrame = pipeCFrame * CFrame.new(0, 0.4, 0)
		local stripe = newPart("PipeGlowStripe" .. i, Vector3.new(2.0, 0.12, 0.12), stripeCFrame, Color3.fromRGB(0, 255, 150), Enum.Material.Neon, model)
		stripe.CanCollide = false
	end
end

-- 5) Vier Stützbeine ----------------------------------------------------------
for i = 1, 4 do
	local x = (i <= 2) and -3.5 or 3.5
	local z = (i % 2 == 0) and -3 or 3
	newPart(
		"SupportLeg" .. i,
		Vector3.new(0.6, 2.4, 0.6),
		ORIGIN * CFrame.new(x, 1.2, z),
		Color3.fromRGB(80, 84, 90),
		Enum.Material.Metal,
		model
	)
end

-- 6) Zwei Status-Leuchtlichter (Neon; "StatusLight" bleibt wie Stufe 1 benannt,
--    "StatusLight2" ist neu dazugekommen) -------------------------------------
local statusLight1 = newPart(
	"StatusLight",
	Vector3.new(1.2, 1.2, 1.2),
	ORIGIN * CFrame.new(-1.2, 6.6, 0),
	Color3.fromRGB(0, 255, 150),
	Enum.Material.Neon,
	model
)
statusLight1.Shape = Enum.PartType.Ball
statusLight1.CanCollide = false

local statusLight2 = newPart(
	"StatusLight2",
	Vector3.new(1.2, 1.2, 1.2),
	ORIGIN * CFrame.new(1.2, 6.6, 0),
	Color3.fromRGB(255, 0, 200),
	Enum.Material.Neon,
	model
)
statusLight2.Shape = Enum.PartType.Ball
statusLight2.CanCollide = false

model.PrimaryPart = base
model:SetAttribute("BuildingType", "FilterPlant")
model:SetAttribute("Stage", 2)

print("[Abyssara] FilterPlant_Stage2 erzeugt unter Workspace.Assets.Buildings")
