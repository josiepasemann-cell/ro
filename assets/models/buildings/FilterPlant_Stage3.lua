--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude (Upgrade-Stufe)
	Name: FilterPlant_Stage3 ("Filteranlage", Stufe 3/3 - Finalstufe)
	Beschreibung:
		Industrielle Großanlage: alle Stufe-2-Strukturen, zusätzlich ein
		hoher Abluft-Schornstein mit CSG-verschweißtem Leuchtring an der
		Spitze und ein dezenter Dampf-Partikelemitter (niedrige Rate).

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "FilterPlant_Stage3" (BuildingId "FilterPlant" +
		  "_Stage3").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  FilterPlant.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "FilterPlant", "Stage" = 3.
		- "StatusLight": Neon-Part für Produktionsstatus, unverändert
		  benannt wie Stufe 1/2. "StatusLight2"/"StatusLight3": zusätzliche
		  Status-Leuchtlichter.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
		HINWEIS: Verwendet :UnionAsync() - daher serverseitig bzw. in Studio
		mit CSG-Rechten ausführen.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(30, 1.5, -160) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("FilterPlant_Stage3")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "FilterPlant_Stage3"
model.Parent = buildingsFolder

-- 1) Fundament (IDENTISCH zu FilterPlant.Base für Grid-Kompatibilität) ------
local base = newPart("Base", Vector3.new(10, 1, 8), ORIGIN, Color3.fromRGB(95, 100, 108), Enum.Material.DiamondPlate, model)

-- 2) Zentraler Haupttank (größer als Stufe 2) --------------------------------
local mainTankCFrame = ORIGIN * CFrame.new(0, 4.5, 0) * CFrame.Angles(0, 0, math.rad(90))
local mainTank = newPart("MainTank", Vector3.new(6.5, 4.6, 4.6), mainTankCFrame, Color3.fromRGB(170, 178, 188), Enum.Material.Metal, model)
mainTank.Shape = Enum.PartType.Cylinder

-- 3) Drei seitliche Nebentanks ------------------------------------------------
local sideOffsets = { Vector3.new(0, 1.5, -2.8), Vector3.new(0, 1.5, 2.8), Vector3.new(3.2, 1.5, 0) }
for i, offset in ipairs(sideOffsets) do
	local sideCFrame = ORIGIN * CFrame.new(offset) * CFrame.Angles(0, 0, math.rad(90))
	local sideTank = newPart("SideTank" .. i, Vector3.new(2.8, 2.2, 2.2), sideCFrame, Color3.fromRGB(140, 148, 158), Enum.Material.Metal, model)
	sideTank.Shape = Enum.PartType.Cylinder
end

-- 4) Verbindungsrohre + Neon-Glow-Streifen -----------------------------------
for i, offset in ipairs(sideOffsets) do
	local pipeCFrame = ORIGIN * CFrame.new(offset.X * 0.5 - 2, 2.6, offset.Z * 0.6) * CFrame.Angles(0, 0, math.rad(90))
	local pipe = newPart("ConnectorPipe" .. i, Vector3.new(2.2, 0.5, 0.5), pipeCFrame, Color3.fromRGB(100, 106, 114), Enum.Material.Metal, model)
	pipe.Shape = Enum.PartType.Cylinder

	local stripeCFrame = pipeCFrame * CFrame.new(0, 0.4, 0)
	local stripe = newPart("PipeGlowStripe" .. i, Vector3.new(2.0, 0.12, 0.12), stripeCFrame, Color3.fromRGB(0, 255, 150), Enum.Material.Neon, model)
	stripe.CanCollide = false
end

-- 5) Vier Stützbeine ----------------------------------------------------------
for i = 1, 4 do
	local x = (i <= 2) and -3.5 or 3.5
	local z = (i % 2 == 0) and -3 or 3
	newPart(
		"SupportLeg" .. i,
		Vector3.new(0.6, 2.4, 0.6),
		ORIGIN * CFrame.new(x, 1.2, z),
		Color3.fromRGB(90, 94, 100),
		Enum.Material.Metal,
		model
	)
end

-- 6) Drei Status-Leuchtlichter ("StatusLight" wie Stufe 1/2 benannt) ---------
local statusLight1 = newPart(
	"StatusLight",
	Vector3.new(1.3, 1.3, 1.3),
	ORIGIN * CFrame.new(-1.3, 6.9, 0),
	Color3.fromRGB(0, 255, 150),
	Enum.Material.Neon,
	model
)
statusLight1.Shape = Enum.PartType.Ball
statusLight1.CanCollide = false

local statusLight2 = newPart(
	"StatusLight2",
	Vector3.new(1.3, 1.3, 1.3),
	ORIGIN * CFrame.new(1.3, 6.9, 0),
	Color3.fromRGB(255, 0, 200),
	Enum.Material.Neon,
	model
)
statusLight2.Shape = Enum.PartType.Ball
statusLight2.CanCollide = false

local statusLight3 = newPart(
	"StatusLight3",
	Vector3.new(1.3, 1.3, 1.3),
	ORIGIN * CFrame.new(0, 6.9, 1.6),
	Color3.fromRGB(0, 220, 255),
	Enum.Material.Neon,
	model
)
statusLight3.Shape = Enum.PartType.Ball
statusLight3.CanCollide = false

-- 7) Abluft-Schornstein mit CSG-Leuchtring + Dampf-Partikelemitter -----------
local stack = newPart(
	"ExhaustStack",
	Vector3.new(1.4, 6, 1.4),
	ORIGIN * CFrame.new(-3.4, 8, 0),
	Color3.fromRGB(80, 84, 90),
	Enum.Material.Metal,
	model
)

local stackOuterCFrame = ORIGIN * CFrame.new(-3.4, 11.2, 0) * CFrame.Angles(0, 0, math.rad(90))
local stackOuter = newPart("StackRingOuter", Vector3.new(0.5, 2.2, 2.2), stackOuterCFrame, Color3.fromRGB(0, 255, 150), Enum.Material.Neon, Workspace)
stackOuter.Shape = Enum.PartType.Cylinder

local stackInnerCFrame = ORIGIN * CFrame.new(-3.4, 11.2, 0) * CFrame.Angles(0, 0, math.rad(90))
local stackInner = newPart("StackRingInner", Vector3.new(0.7, 1.7, 1.7), stackInnerCFrame, Color3.fromRGB(0, 0, 0), Enum.Material.Neon, Workspace)
stackInner.Shape = Enum.PartType.Cylinder

local stackRingOk, stackGlowRing = pcall(function()
	return stackOuter:SubtractAsync({ stackInner })
end)
if stackRingOk and stackGlowRing then
	stackGlowRing.Name = "StackGlowRing"
	stackGlowRing.Color = Color3.fromRGB(0, 255, 150)
	stackGlowRing.Material = Enum.Material.Neon
	stackGlowRing.Anchored = true
	stackGlowRing.CanCollide = false
	stackGlowRing.Parent = model
end

local steamEmitter = Instance.new("ParticleEmitter")
steamEmitter.Name = "SteamEmitter"
steamEmitter.Color = ColorSequence.new(Color3.fromRGB(200, 255, 240))
steamEmitter.Lifetime = NumberRange.new(1, 2)
steamEmitter.Rate = 4
steamEmitter.Speed = NumberRange.new(2, 3)
steamEmitter.Size = NumberSequence.new(0.6)
steamEmitter.Parent = stack

model.PrimaryPart = base
model:SetAttribute("BuildingType", "FilterPlant")
model:SetAttribute("Stage", 3)

print("[Abyssara] FilterPlant_Stage3 erzeugt unter Workspace.Assets.Buildings")
