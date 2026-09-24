--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude / Verteidigungsturm (Upgrade-Stufe)
	Name: CoralBarrier_Stage2 ("Korallen-Barriere", Stufe 2/3)
	Beschreibung:
		Ausgebaute Barriere: größerer Sockel, ein zusätzlicher CSG-
		verschweißter Innenring aus kürzeren Spitzen, ein Neon-Glow-Ring am
		Sockelrand sowie ein größerer/hellerer Verlangsamungs-Puls-Kern.

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "CoralBarrier_Stage2" (BuildingId "CoralBarrier" +
		  "_Stage2").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  CoralBarrier.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "CoralBarrier", "Stage" = 2.
		- "SlowPulseCore": Neon-Part, unverändert benannt, Referenzpunkt für
		  Verlangsamungs-Puls-VFX (siehe RaidService.getTowerOriginPosition).
		- Attachment "MuzzlePoint" an SlowPulseCore, unverändert.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
		HINWEIS: Verwendet :UnionAsync()/:SubtractAsync() - daher serverseitig
		bzw. in Studio mit CSG-Rechten ausführen.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(60, 1.5, -140) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("CoralBarrier_Stage2")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "CoralBarrier_Stage2"
model.Parent = buildingsFolder

local CORAL_COLOR = Color3.fromRGB(255, 90, 200)
local TEAL_GLOW = Color3.fromRGB(0, 255, 220)

-- 1) Fundament (IDENTISCH zu CoralBarrier.Base für Grid-Kompatibilität) -----
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Gerundeter Sockel-Aufbau (etwas größer als Stufe 1) ---------------------
local mound = newPart(
	"CoralMound",
	Vector3.new(5.0, 1.6, 5.0),
	ORIGIN * CFrame.new(0, 1.4, 0),
	CORAL_COLOR,
	Enum.Material.SmoothPlastic,
	model
)
mound.Shape = Enum.PartType.Cylinder
mound.CFrame = ORIGIN * CFrame.new(0, 1.4, 0) * CFrame.Angles(0, 0, math.rad(90))

-- 3) Neon-Glow-Ring am Sockelrand (CSG-Subtraktion) --------------------------
local baseRingOuterCFrame = ORIGIN * CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, math.rad(90))
local baseRingOuter = newPart("BaseGlowRingOuter", Vector3.new(0.3, 6.4, 6.4), baseRingOuterCFrame, TEAL_GLOW, Enum.Material.Neon, Workspace)
baseRingOuter.Shape = Enum.PartType.Cylinder

local baseRingInnerCFrame = ORIGIN * CFrame.new(0, 0.75, 0) * CFrame.Angles(0, 0, math.rad(90))
local baseRingInner = newPart("BaseGlowRingInner", Vector3.new(0.5, 5.8, 5.8), baseRingInnerCFrame, Color3.fromRGB(0, 0, 0), Enum.Material.Neon, Workspace)
baseRingInner.Shape = Enum.PartType.Cylinder

local baseRingOk, baseGlowRing = pcall(function()
	return baseRingOuter:SubtractAsync({ baseRingInner })
end)
if baseRingOk and baseGlowRing then
	baseGlowRing.Name = "BaseGlowRing"
	baseGlowRing.Color = TEAL_GLOW
	baseGlowRing.Material = Enum.Material.Neon
	baseGlowRing.Anchored = true
	baseGlowRing.CanCollide = false
	baseGlowRing.Parent = model
end

-- 4) Ring aus verschweißten Korallenspitzen (CSG-Union) ----------------------
local spikeParts = {}
local SPIKE_COUNT = 8
local RING_RADIUS = 2.8
for i = 1, SPIKE_COUNT do
	local angle = math.rad(360 / SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	local spikeCFrame = ORIGIN * CFrame.new(offset + Vector3.new(0, 2.2, 0)) * CFrame.Angles(0, angle, 0)
	local spike = newPart("CoralSpikePiece" .. i, Vector3.new(0.7, 2.1, 0.7), spikeCFrame, CORAL_COLOR, Enum.Material.SmoothPlastic, Workspace)
	table.insert(spikeParts, spike)
end

local ringUnionOk, coralRing = pcall(function()
	local primarySpike = table.remove(spikeParts, 1)
	return primarySpike:UnionAsync(spikeParts)
end)
if ringUnionOk and coralRing then
	coralRing.Name = "CoralRing"
	coralRing.Color = CORAL_COLOR
	coralRing.Material = Enum.Material.SmoothPlastic
	coralRing.Anchored = true
	coralRing.CanCollide = false
	coralRing.Parent = model
else
	warn("[Abyssara] CoralBarrier_Stage2: CoralRing-CSG-Union fehlgeschlagen, verwende ungeschweißte Einzelspitzen.")
	for _, spike in ipairs(spikeParts) do
		spike.Anchored = true
		spike.CanCollide = false
		spike.Parent = model
	end
end

-- 5) Innenring aus kürzeren Spitzen (CSG-Union, neu, mehr Struktur) ----------
local innerSpikeParts = {}
local INNER_SPIKE_COUNT = 6
local INNER_RING_RADIUS = 1.5
for i = 1, INNER_SPIKE_COUNT do
	local angle = math.rad(360 / INNER_SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * INNER_RING_RADIUS, 0, math.sin(angle) * INNER_RING_RADIUS)
	local spikeCFrame = ORIGIN * CFrame.new(offset + Vector3.new(0, 2.0, 0)) * CFrame.Angles(0, angle, 0)
	local spike = newPart("InnerSpikePiece" .. i, Vector3.new(0.4, 1.2, 0.4), spikeCFrame, TEAL_GLOW, Enum.Material.Neon, Workspace)
	table.insert(innerSpikeParts, spike)
end

local innerRingOk, innerRing = pcall(function()
	local primarySpike = table.remove(innerSpikeParts, 1)
	return primarySpike:UnionAsync(innerSpikeParts)
end)
if innerRingOk and innerRing then
	innerRing.Name = "InnerRing"
	innerRing.Color = TEAL_GLOW
	innerRing.Material = Enum.Material.Neon
	innerRing.Anchored = true
	innerRing.CanCollide = false
	innerRing.Parent = model
else
	warn("[Abyssara] CoralBarrier_Stage2: InnerRing-CSG-Union fehlgeschlagen, verwende ungeschweißte Einzelspitzen.")
	for _, spike in ipairs(innerSpikeParts) do
		spike.Anchored = true
		spike.CanCollide = false
		spike.Parent = model
	end
end

-- 6) Neon-türkisene Spitzen-Tips -----------------------------------------------
for i = 1, SPIKE_COUNT do
	local angle = math.rad(360 / SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	local tipCFrame = ORIGIN * CFrame.new(offset + Vector3.new(0, 3.3, 0))
	local tip = newPart("SpikeTip" .. i, Vector3.new(0.4, 0.4, 0.4), tipCFrame, TEAL_GLOW, Enum.Material.Neon, model)
	tip.Shape = Enum.PartType.Ball
	tip.CanCollide = false
end

-- 7) Zentraler Verlangsamungs-Puls-Kern (größer/heller als Stufe 1) ----------
local slowPulseCore = newPart(
	"SlowPulseCore",
	Vector3.new(1.8, 1.8, 1.8),
	ORIGIN * CFrame.new(0, 3.6, 0),
	TEAL_GLOW,
	Enum.Material.Neon,
	model
)
slowPulseCore.Shape = Enum.PartType.Ball
slowPulseCore.CanCollide = false

local pulseLight = Instance.new("PointLight")
pulseLight.Name = "SlowPulseCoreLight"
pulseLight.Color = TEAL_GLOW
pulseLight.Range = 14
pulseLight.Brightness = 1.8
pulseLight.Shadows = false
pulseLight.Parent = slowPulseCore

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = slowPulseCore

model.PrimaryPart = base
model:SetAttribute("BuildingType", "CoralBarrier")
model:SetAttribute("Stage", 2)

print("[Abyssara] CoralBarrier_Stage2 erzeugt unter Workspace.Assets.Buildings")
