--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: VentDrake ("Vent Drake")
	Rarity (Platzhalter): Legendary
	Event: VolcanicVent
	Beschreibung:
		Schlangenförmige Meeresdrachen-Silhouette mit 2 kleinen Flossen-
		Flügeln, dunkler rot-schwarzer Schuppenkörper, leuchtend orangefarbene
		Rückenstacheln (Neon) und einem kleinen Horn-Cluster am Kopf.
		Event-exklusive Headliner-Kreatur des "Volcanic Vent"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung (mittleres
		  Rumpfsegment).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (langsames, schlängelndes Schwimmen; Rückenstacheln blitzen bei jedem
		  Undulations-Peak heller auf).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("VolcanicVent"), analog "Zone"
		  bei Zonen-Kreaturen.
		- Parts "SpineSpike1".."SpineSpike6" -> Ansatzpunkte für die spätere
		  Undulations-Glow-Animation.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-5, 7, 120)
local RARITY = "Legendary"
local ZONE = "Global"
local EVENT = "VolcanicVent"
local SEGMENT_COUNT = 5
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
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

-- Block-Part + SpecialMesh(Sphere): echtes, sich verjüngendes Ellipsoid statt der
-- Shape=Ball-Darstellung (die Roblox immer als perfekte Kugel mit der kleinsten
-- Size-Achse als Durchmesser zeichnet - das ließ die Rumpfsegmente hier vorher
-- ungleichmäßig schrumpfen und auseinanderdriften).
local function newMeshBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("VentDrake")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "VentDrake"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(70, 20, 15)
local BODY_COLOR_LIGHT = Color3.fromRGB(95, 30, 22)
local GLOW_COLOR = Color3.fromRGB(255, 110, 20)

-- 1) Schlangenkörper aus 5 sich leicht verjüngenden Segmenten (Ellipsoide) -----------
-- Der Z-Abstand (1.1) ist knapp kleiner als die konstante Segment-Halbtiefe (0.65),
-- sodass aufeinanderfolgende Segmente unabhängig von ihrer X/Y-Verjüngung immer
-- überlappen (mind. ~0.2 Stud).
local SEGMENT_Z_STEP = 1.1
local segments = {}
local segmentHalfHeights = {}
for i = 1, SEGMENT_COUNT do
	local zOffset = (SEGMENT_COUNT - 1) / 2 * SEGMENT_Z_STEP - (i - 1) * SEGMENT_Z_STEP
	local scale = 1.0 - (i - 1) * 0.14
	local girth = 1.7 * scale
	local seg = newMeshBall(
		i == math.ceil(SEGMENT_COUNT / 2) and "Body" or ("BodySegment" .. i),
		Vector3.new(girth, girth, 1.3),
		ORIGIN * CFrame.new(0, 0, zOffset),
		i % 2 == 0 and BODY_COLOR_LIGHT or BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	segments[i] = seg
	segmentHalfHeights[i] = girth / 2
end
local body = segments[math.ceil(SEGMENT_COUNT / 2)]

-- 2) Kopf-Horn-Cluster (3 kleine WedgeParts), Basis im Kopfsegment eingesenkt -------
local headZ = (SEGMENT_COUNT - 1) / 2 * SEGMENT_Z_STEP
for i = 1, 3 do
	local xOff = (i - 2) * 0.35
	local horn = Instance.new("WedgePart")
	horn.Name = "Horn" .. i
	horn.Size = Vector3.new(0.2, 0.5, 0.2)
	horn.CFrame = ORIGIN * CFrame.new(xOff, 0.55, headZ + 0.55) * CFrame.Angles(math.rad(-20), 0, 0)
	horn.Color = BODY_COLOR
	horn.Material = Enum.Material.SmoothPlastic
	horn.Anchored = true
	horn.CanCollide = false
	horn.TopSurface = Enum.SurfaceType.Smooth
	horn.BottomSurface = Enum.SurfaceType.Smooth
	horn.Parent = model
end

-- 3) Leuchtende Rückenstacheln (6, entlang der Wirbelsäule, an Segment-Höhe angepasst)
for i = 1, 6 do
	local t = (i - 1) / 5 -- 0 (Kopf) .. 1 (Schwanz)
	local zOffset = headZ - t * (SEGMENT_Z_STEP * (SEGMENT_COUNT - 1) + 0.6)
	-- lineare Interpolation der Segment-Halbhöhe entlang der Kette für einen
	-- glaubwürdig eingesenkten Stachel-Fuß
	local segFloat = 1 + t * (SEGMENT_COUNT - 1)
	local lowIndex = math.clamp(math.floor(segFloat), 1, SEGMENT_COUNT)
	local highIndex = math.clamp(math.ceil(segFloat), 1, SEGMENT_COUNT)
	local frac = segFloat - lowIndex
	local halfHeight = segmentHalfHeights[lowIndex] + (segmentHalfHeights[highIndex] - segmentHalfHeights[lowIndex]) * frac

	local spike = Instance.new("WedgePart")
	spike.Name = "SpineSpike" .. i
	spike.Size = Vector3.new(0.25, 0.7, 0.25)
	spike.CFrame = ORIGIN * CFrame.new(0, halfHeight + 0.15, zOffset) * CFrame.Angles(0, 0, math.rad(180))
	spike.Color = GLOW_COLOR
	spike.Material = Enum.Material.Neon
	spike.Anchored = true
	spike.CanCollide = false
	spike.TopSurface = Enum.SurfaceType.Smooth
	spike.BottomSurface = Enum.SurfaceType.Smooth
	spike.Parent = model
end

-- 4) Zwei kleine Flossen-Flügel, Wurzel im Rumpf eingesenkt --------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local wing = Instance.new("WedgePart")
	wing.Name = "Wing" .. i
	wing.Size = Vector3.new(1.6, 0.15, 1.2)
	wing.CFrame = ORIGIN * CFrame.new(side * 0.65, 0.1, 0.9) * CFrame.Angles(0, math.rad(90), math.rad(side * 15))
	wing.Color = Color3.fromRGB(90, 25, 20)
	wing.Material = Enum.Material.SmoothPlastic
	wing.Anchored = true
	wing.CanCollide = false
	wing.TopSurface = Enum.SurfaceType.Smooth
	wing.BottomSurface = Enum.SurfaceType.Smooth
	wing.Parent = model
end

-- 5) Zwei Glow-Augen, auf dem Kopfsegment sitzend -------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eye = newMeshBall(
		"Eye" .. i,
		Vector3.new(0.3, 0.3, 0.3),
		ORIGIN * CFrame.new(side * 0.45, 0.35, headZ + 0.5),
		GLOW_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 6) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Vent Drake")

print("[Abyssara] VentDrake created under Workspace.Assets.Creatures")
