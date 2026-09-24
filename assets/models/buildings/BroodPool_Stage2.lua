--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude (Upgrade-Stufe)
	Name: BroodPool_Stage2 ("Brutbecken", Stufe 2/3)
	Beschreibung:
		Ausgebautes Brutbecken: höherer CSG-Becken-Ring, ein zusätzlicher
		Neon-Rand-Ring knapp über der Wasserlinie, an den 4 Stützpfeilern
		montierte Glow-Streifen sowie ein CSG-verschweißter Ring aus
		Querstreben, der die Pfeiler oben verbindet (mehr sichtbare
		Struktur als Stufe 1).

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "BroodPool_Stage2" (BuildingId "BroodPool" + "_Stage2"),
		  wird von PlacementService/UpgradeService anstelle von
		  "BroodPool_Basic" eingesetzt.
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  BroodPool_Basic.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "BroodPool", "Stage" = 2.
		- "EggSlot1".."EggSlot3": Attachments am Wasser-Part, unverändert
		  gegenüber Stufe 1 (gleiche Namen/Anzahl).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
		HINWEIS: Verwendet :SubtractAsync()/:UnionAsync() - daher serverseitig
		bzw. in Studio mit CSG-Rechten ausführen.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 2, -140) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("BroodPool_Stage2")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "BroodPool_Stage2"
model.Parent = buildingsFolder

-- 1) Fundament (IDENTISCH zu BroodPool_Basic.Base für Grid-Kompatibilität) --
local base = newPart("Base", Vector3.new(14, 1.2, 14), ORIGIN, Color3.fromRGB(110, 118, 128), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Becken-Ring per CSG-Subtraktion, etwas höher/wuchtiger als Stufe 1 ------
local outerCFrame = ORIGIN * CFrame.new(0, 2.2, 0) * CFrame.Angles(0, 0, math.rad(90))
local outerCyl = newPart("PoolOuter", Vector3.new(3.4, 11, 11), outerCFrame, Color3.fromRGB(130, 150, 170), Enum.Material.SmoothPlastic, Workspace)
outerCyl.Shape = Enum.PartType.Cylinder

local innerCFrame = ORIGIN * CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(90))
local innerCyl = newPart("PoolInner", Vector3.new(3.6, 9.4, 9.4), innerCFrame, Color3.fromRGB(0, 0, 0), Enum.Material.SmoothPlastic, Workspace)
innerCyl.Shape = Enum.PartType.Cylinder

local poolRing = outerCyl:SubtractAsync({ innerCyl })
poolRing.Name = "PoolBasin"
poolRing.Color = Color3.fromRGB(130, 150, 170)
poolRing.Material = Enum.Material.SmoothPlastic
poolRing.Anchored = true
poolRing.CanCollide = true
poolRing.Parent = model

-- 3) Leuchtendes Wasser, kräftigeres Neon-Cyan -------------------------------
local waterCFrame = ORIGIN * CFrame.new(0, 2.0, 0) * CFrame.Angles(0, 0, math.rad(90))
local water = newPart("GlowWater", Vector3.new(0.6, 9, 9), waterCFrame, Color3.fromRGB(0, 255, 255), Enum.Material.Neon, model)
water.Shape = Enum.PartType.Cylinder
water.Transparency = 0.25
water.CanCollide = false

-- 4) Neon-Rand-Ring knapp über der Wasserlinie (CSG-Subtraktion) -------------
local ringOuterCFrame = ORIGIN * CFrame.new(0, 3.0, 0) * CFrame.Angles(0, 0, math.rad(90))
local ringOuter = newPart("RimRingOuter", Vector3.new(0.4, 10.4, 10.4), ringOuterCFrame, Color3.fromRGB(255, 0, 220), Enum.Material.Neon, Workspace)
ringOuter.Shape = Enum.PartType.Cylinder

local ringInnerCFrame = ORIGIN * CFrame.new(0, 3.0, 0) * CFrame.Angles(0, 0, math.rad(90))
local ringInner = newPart("RimRingInner", Vector3.new(0.6, 9.6, 9.6), ringInnerCFrame, Color3.fromRGB(0, 0, 0), Enum.Material.Neon, Workspace)
ringInner.Shape = Enum.PartType.Cylinder

local ringOk, rimGlowRing = pcall(function()
	return ringOuter:SubtractAsync({ ringInner })
end)
if ringOk and rimGlowRing then
	rimGlowRing.Name = "RimGlowRing"
	rimGlowRing.Color = Color3.fromRGB(255, 0, 220)
	rimGlowRing.Material = Enum.Material.Neon
	rimGlowRing.Anchored = true
	rimGlowRing.CanCollide = false
	rimGlowRing.Parent = model
end

-- 5) Ei-Platzhalter (etwas größer als Stufe 1) + Attachments -----------------
local EGG_COLOR = Color3.fromRGB(200, 255, 245)
local eggPositions = {
	Vector3.new(-2.5, 3.4, 0),
	Vector3.new(2.5, 3.4, -1.5),
	Vector3.new(1, 3.4, 2.7),
}
for i, offset in ipairs(eggPositions) do
	local eggCFrame = ORIGIN * CFrame.new(offset)
	local egg = newPart("Egg" .. i, Vector3.new(1.6, 1.9, 1.6), eggCFrame, EGG_COLOR, Enum.Material.Glass, model)
	egg.Shape = Enum.PartType.Ball
	egg.Transparency = 0.1
	egg.CanCollide = false

	local slot = Instance.new("Attachment")
	slot.Name = "EggSlot" .. i
	slot.WorldCFrame = eggCFrame
	slot.Parent = water
end

-- 6) Vier Stützpfeiler + Neon-Glow-Streifen ----------------------------------
local pillarPositions = {}
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 45)
	pillarPositions[i] = Vector3.new(math.cos(angle) * 6.2, 0, math.sin(angle) * 6.2)
	newPart(
		"SupportPillar" .. i,
		Vector3.new(1, 3.2, 1),
		ORIGIN * CFrame.new(pillarPositions[i] + Vector3.new(0, 1.6, 0)),
		Color3.fromRGB(110, 118, 130),
		Enum.Material.Metal,
		model
	)
	local strip = newPart(
		"PillarGlowStrip" .. i,
		Vector3.new(0.25, 3.4, 0.25),
		ORIGIN * CFrame.new(pillarPositions[i] * 1.12 + Vector3.new(0, 1.6, 0)),
		Color3.fromRGB(0, 255, 255),
		Enum.Material.Neon,
		model
	)
	strip.CanCollide = false
end

-- 7) Obere Verbindungs-Streben, CSG-verschweißt zu einem Ring ----------------
local collarBars = {}
for i = 1, 4 do
	local a = pillarPositions[i]
	local b = pillarPositions[(i % 4) + 1]
	local mid = (a + b) / 2
	local dist = (a - b).Magnitude
	local dir = (b - a).Unit
	local yaw = math.atan2(dir.X, dir.Z)
	local barCFrame = ORIGIN * CFrame.new(mid + Vector3.new(0, 3.4, 0)) * CFrame.Angles(0, yaw, 0)
	local bar = newPart("CollarBar" .. i, Vector3.new(0.6, 0.6, dist), barCFrame, Color3.fromRGB(80, 160, 255), Enum.Material.Neon, Workspace)
	table.insert(collarBars, bar)
end

local collarOk, upperCollarRing = pcall(function()
	local primary = table.remove(collarBars, 1)
	return primary:UnionAsync(collarBars)
end)
if collarOk and upperCollarRing then
	upperCollarRing.Name = "UpperCollarRing"
	upperCollarRing.Color = Color3.fromRGB(80, 160, 255)
	upperCollarRing.Material = Enum.Material.Neon
	upperCollarRing.Anchored = true
	upperCollarRing.CanCollide = false
	upperCollarRing.Parent = model
else
	warn("[Abyssara] BroodPool_Stage2: UpperCollarRing-CSG union failed, using unwelded individual struts.")
	for _, bar in ipairs(collarBars) do
		bar.Anchored = true
		bar.CanCollide = false
		bar.Parent = model
	end
end

model.PrimaryPart = base
model:SetAttribute("BuildingType", "BroodPool")
model:SetAttribute("Stage", 2)

print("[Abyssara] BroodPool_Stage2 created under Workspace.Assets.Buildings")
