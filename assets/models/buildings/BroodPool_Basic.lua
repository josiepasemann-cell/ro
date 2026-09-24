--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude (Basisstufe)
	Name: BroodPool_Basic ("Brutbecken", Stufe 1/3 - Basic)
	Beschreibung:
		Rundes Zuchtbecken, in dem Kreaturen-Eier inkubiert werden.
		Gebaut per CSG-Subtraktion (Ring-Becken aus großem Zylinder minus
		kleinerem Innenzylinder), gefüllt mit leuchtendem Wasser und ein paar
		schwebenden Ei-Platzhaltern.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Base" (Fundament-Part, für Placement/Snap-to-Grid)
		- Model-Attribute: "BuildingType" = "BroodPool", "Stage" = 1 (von 3)
		- "EggSlot1".."EggSlot3": Attachments am Wasser-Part, als Platzhalter
		  für spätere Ei-/Inkubations-Logik (rein geometrischer Marker).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(20, 2, 20) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("BroodPool_Basic")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "BroodPool_Basic"
model.Parent = buildingsFolder

-- 1) Fundament / Sockel ---------------------------------------------------
local base = newPart("Base", Vector3.new(14, 1.2, 14), ORIGIN, Color3.fromRGB(110, 118, 128), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Becken-Ring per CSG-Subtraktion (Außenzylinder minus Innenzylinder) --
local outerCFrame = ORIGIN * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.rad(90))
local outerCyl = newPart("PoolOuter", Vector3.new(3, 11, 11), outerCFrame, Color3.fromRGB(150, 158, 168), Enum.Material.SmoothPlastic, Workspace)
outerCyl.Shape = Enum.PartType.Cylinder

local innerCFrame = ORIGIN * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90))
local innerCyl = newPart("PoolInner", Vector3.new(3.2, 9.4, 9.4), innerCFrame, Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic, Workspace)
innerCyl.Shape = Enum.PartType.Cylinder

local poolRing = outerCyl:SubtractAsync({ innerCyl })
poolRing.Name = "PoolBasin"
poolRing.Color = Color3.fromRGB(150, 158, 168)
poolRing.Material = Enum.Material.SmoothPlastic
poolRing.Anchored = true
poolRing.CanCollide = true
poolRing.Parent = model

-- 3) Leuchtendes Wasser im Becken ------------------------------------------
local waterCFrame = ORIGIN * CFrame.new(0, 2.0, 0) * CFrame.Angles(0, 0, math.rad(90))
local water = newPart("GlowWater", Vector3.new(0.6, 9, 9), waterCFrame, Color3.fromRGB(70, 220, 230), Enum.Material.Neon, model)
water.Shape = Enum.PartType.Cylinder
water.Transparency = 0.35
water.CanCollide = false

-- 4) Ei-Platzhalter (schwebende Kugeln) + Attachments ----------------------
local EGG_COLOR = Color3.fromRGB(190, 255, 235)
local eggPositions = {
	Vector3.new(-2.5, 3.4, 0),
	Vector3.new(2.5, 3.4, -1.5),
	Vector3.new(1, 3.4, 2.7),
}
for i, offset in ipairs(eggPositions) do
	local eggCFrame = ORIGIN * CFrame.new(offset)
	local egg = newPart("Egg" .. i, Vector3.new(1.4, 1.7, 1.4), eggCFrame, EGG_COLOR, Enum.Material.Glass, model)
	egg.Shape = Enum.PartType.Ball
	egg.Transparency = 0.15
	egg.CanCollide = false

	local slot = Instance.new("Attachment")
	slot.Name = "EggSlot" .. i
	slot.WorldCFrame = eggCFrame
	slot.Parent = water
end

-- 5) Vier Stützpfeiler um das Becken ---------------------------------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 45)
	local offset = Vector3.new(math.cos(angle) * 6.2, 1.6, math.sin(angle) * 6.2)
	newPart(
		"SupportPillar" .. i,
		Vector3.new(1, 3.2, 1),
		ORIGIN * CFrame.new(offset),
		Color3.fromRGB(90, 96, 104),
		Enum.Material.Metal,
		model
	)
end

model.PrimaryPart = base
model:SetAttribute("BuildingType", "BroodPool")
model:SetAttribute("Stage", 1)

print("[Abyssara] BroodPool_Basic created under Workspace.Assets.Buildings")
