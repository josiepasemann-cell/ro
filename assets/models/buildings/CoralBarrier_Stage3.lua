--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude / Verteidigungsturm (Upgrade-Stufe)
	Name: CoralBarrier_Stage3 ("Korallen-Barriere", Stufe 3/3 - Finalstufe)
	Beschreibung:
		Prachtvolle Barriere: alle Stufe-2-Strukturen, zusätzlich eine
		CSG-verschweißte hohe Kronenspitzen-Krone über dem Puls-Kern, zwei
		umlaufende Puls-Orbit-Akzente und ein dezenter Puls-Partikelemitter
		(niedrige Rate).

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "CoralBarrier_Stage3" (BuildingId "CoralBarrier" +
		  "_Stage3").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  CoralBarrier.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "CoralBarrier", "Stage" = 3.
		- "SlowPulseCore": Neon-Part, unverändert benannt.
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
local ORIGIN = CFrame.new(60, 1.5, -160) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("CoralBarrier_Stage3")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "CoralBarrier_Stage3"
model.Parent = buildingsFolder

local CORAL_COLOR = Color3.fromRGB(255, 60, 190)
local TEAL_GLOW = Color3.fromRGB(0, 255, 220)

-- 1) Fundament (IDENTISCH zu CoralBarrier.Base für Grid-Kompatibilität) -----
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Gerundeter Sockel-Aufbau (größer als Stufe 2) ---------------------------
local mound = newPart(
	"CoralMound",
	Vector3.new(5.4, 1.8, 5.4),
	ORIGIN * CFrame.new(0, 1.5, 0),
	CORAL_COLOR,
	Enum.Material.SmoothPlastic,
	model
)
mound.Shape = Enum.PartType.Cylinder
mound.CFrame = ORIGIN * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90))

-- 3) Neon-Glow-Ring am Sockelrand (CSG-Subtraktion) --------------------------
local baseRingOuterCFrame = ORIGIN * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
local baseRingOuter = newPart("BaseGlowRingOuter", Vector3.new(0.3, 6.8, 6.8), baseRingOuterCFrame, TEAL_GLOW, Enum.Material.Neon, Workspace)
baseRingOuter.Shape = Enum.PartType.Cylinder

local baseRingInnerCFrame = ORIGIN * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(90))
local baseRingInner = newPart("BaseGlowRingInner", Vector3.new(0.5, 6.2, 6.2), baseRingInnerCFrame, Color3.fromRGB(0, 0, 0), Enum.Material.Neon, Workspace)
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
local RING_RADIUS = 3.0
for i = 1, SPIKE_COUNT do
	local angle = math.rad(360 / SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	local spikeCFrame = ORIGIN * CFrame.new(offset + Vector3.new(0, 2.4, 0)) * CFrame.Angles(0, angle, 0)
	local spike = newPart("CoralSpikePiece" .. i, Vector3.new(0.8, 2.4, 0.8), spikeCFrame, CORAL_COLOR, Enum.Material.SmoothPlastic, Workspace)
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
	warn("[Abyssara] CoralBarrier_Stage3: CoralRing-CSG-Union fehlgeschlagen, verwende ungeschweißte Einzelspitzen.")
	for _, spike in ipairs(spikeParts) do
		spike.Anchored = true
		spike.CanCollide = false
		spike.Parent = model
	end
end

-- 5) Innenring aus kürzeren Spitzen (CSG-Union) ------------------------------
local innerSpikeParts = {}
local INNER_SPIKE_COUNT = 6
local INNER_RING_RADIUS = 1.6
for i = 1, INNER_SPIKE_COUNT do
	local angle = math.rad(360 / INNER_SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * INNER_RING_RADIUS, 0, math.sin(angle) * INNER_RING_RADIUS)
	local spikeCFrame = ORIGIN * CFrame.new(offset + Vector3.new(0, 2.2, 0)) * CFrame.Angles(0, angle, 0)
	local spike = newPart("InnerSpikePiece" .. i, Vector3.new(0.45, 1.4, 0.45), spikeCFrame, TEAL_GLOW, Enum.Material.Neon, Workspace)
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
	warn("[Abyssara] CoralBarrier_Stage3: InnerRing-CSG-Union fehlgeschlagen, verwende ungeschweißte Einzelspitzen.")
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
	local tipCFrame = ORIGIN * CFrame.new(offset + Vector3.new(0, 3.7, 0))
	local tip = newPart("SpikeTip" .. i, Vector3.new(0.45, 0.45, 0.45), tipCFrame, TEAL_GLOW, Enum.Material.Neon, model)
	tip.Shape = Enum.PartType.Ball
	tip.CanCollide = false
end

-- 7) Kronenspitzen-Krone über dem Puls-Kern (CSG-Union aus 6 Spitzen) --------
local crownSpikes = {}
local CROWN_SPIKE_COUNT = 6
local CROWN_RADIUS = 1.1
for i = 1, CROWN_SPIKE_COUNT do
	local angle = math.rad(360 / CROWN_SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * CROWN_RADIUS, 4.6, math.sin(angle) * CROWN_RADIUS)
	local spikeCFrame = ORIGIN * CFrame.new(offset) * CFrame.Angles(0, angle, math.rad(20))
	local spike = newPart("CrownSpikePiece" .. i, Vector3.new(0.3, 1.5, 0.3), spikeCFrame, CORAL_COLOR, Enum.Material.Neon, Workspace)
	table.insert(crownSpikes, spike)
end

local crownOk, crownSpikeCluster = pcall(function()
	local primary = table.remove(crownSpikes, 1)
	return primary:UnionAsync(crownSpikes)
end)
if crownOk and crownSpikeCluster then
	crownSpikeCluster.Name = "CrownSpikeCluster"
	crownSpikeCluster.Color = CORAL_COLOR
	crownSpikeCluster.Material = Enum.Material.Neon
	crownSpikeCluster.Anchored = true
	crownSpikeCluster.CanCollide = false
	crownSpikeCluster.Parent = model
else
	warn("[Abyssara] CoralBarrier_Stage3: CrownSpikeCluster-CSG-Union fehlgeschlagen, verwende ungeschweißte Einzelspitzen.")
	for _, spike in ipairs(crownSpikes) do
		spike.Anchored = true
		spike.CanCollide = false
		spike.Parent = model
	end
end

-- 8) Zentraler Verlangsamungs-Puls-Kern (größer/heller) + Partikelemitter ----
local slowPulseCore = newPart(
	"SlowPulseCore",
	Vector3.new(2.2, 2.2, 2.2),
	ORIGIN * CFrame.new(0, 3.9, 0),
	TEAL_GLOW,
	Enum.Material.Neon,
	model
)
slowPulseCore.Shape = Enum.PartType.Ball
slowPulseCore.CanCollide = false

local pulseLight = Instance.new("PointLight")
pulseLight.Name = "SlowPulseCoreLight"
pulseLight.Color = TEAL_GLOW
pulseLight.Range = 18
pulseLight.Brightness = 2.2
pulseLight.Shadows = false
pulseLight.Parent = slowPulseCore

local pulseEmitter = Instance.new("ParticleEmitter")
pulseEmitter.Name = "PulseEmitter"
pulseEmitter.Color = ColorSequence.new(TEAL_GLOW)
pulseEmitter.Lifetime = NumberRange.new(0.4, 0.8)
pulseEmitter.Rate = 4
pulseEmitter.Speed = NumberRange.new(2, 4)
pulseEmitter.Size = NumberSequence.new(0.3)
pulseEmitter.Parent = slowPulseCore

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = slowPulseCore

-- 9) Zwei umlaufende Puls-Orbit-Akzente ---------------------------------------
for i = 1, 2 do
	local angle = math.rad(180 * (i - 1))
	local orbitCFrame = ORIGIN * CFrame.new(math.cos(angle) * 1.6, 3.9, math.sin(angle) * 1.6)
	local orbit = newPart("PulseOrbit" .. i, Vector3.new(0.6, 0.6, 0.6), orbitCFrame, CORAL_COLOR, Enum.Material.Neon, model)
	orbit.Shape = Enum.PartType.Ball
	orbit.CanCollide = false
end

model.PrimaryPart = base
model:SetAttribute("BuildingType", "CoralBarrier")
model:SetAttribute("Stage", 3)

print("[Abyssara] CoralBarrier_Stage3 erzeugt unter Workspace.Assets.Buildings")
