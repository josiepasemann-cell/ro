--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: VentDrake ("Vent Drake")
	Rarity (Platzhalter): Legendary
	Event: VolcanicVent
	Beschreibung (Update: echte serpentine Silhouette statt Perlenkette):
		Schlangenförmiger Meeresdrache: 5 sich verjüngende Rumpf-Ellipsoide,
		die LEICHT SEITLICH versetzt sind (Sinus-Kurve) statt stur gerade
		aufgereiht -> liest sich als sich windende Schlange statt "Reihe aus
		Bällen". Zugespitzter Schnauzen-Ellipsoid vor dem Kopfsegment, kleine
		Ellipsoid-Hörner, aufgefächerte Flossen-Flügel (je 2 überlappende
		flache Ellipsoide), leuchtend orangefarbene Ellipsoid-Rückenstacheln
		und große Glow-Augen. Event-exklusive Headliner-Kreatur des
		"Volcanic Vent"-Events.

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
-- Shape=Ball-Darstellung - EINZIGE Grundform hier (Rumpf, Schnauze, Hörner,
-- Stacheln, Flügel).
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

local BODY_COLOR = Color3.fromRGB(75, 22, 16)
local BODY_COLOR_LIGHT = Color3.fromRGB(100, 32, 24)
local GLOW_COLOR = Color3.fromRGB(255, 115, 20)

-- 1) Schlangenkörper aus 5 sich verjüngenden Segmenten (Ellipsoide), MIT seitlichem
--    Sinus-Versatz (SERPENTINE_AMPLITUDE) -> liest sich als sich windende Schlange
--    statt gerade aufgereihte Perlenkette. Z-Abstand bleibt knapp kleiner als die
--    konstante Segment-Halbtiefe, sodass Segmente trotz Versatz überlappen. -------
local SEGMENT_Z_STEP = 1.1
local SERPENTINE_AMPLITUDE = 0.55
local segments = {}
local segmentHalfHeights = {}
local segmentX = {}
for i = 1, SEGMENT_COUNT do
	local zOffset = (SEGMENT_COUNT - 1) / 2 * SEGMENT_Z_STEP - (i - 1) * SEGMENT_Z_STEP
	local xOffset = math.sin((i - 1) * 1.05) * SERPENTINE_AMPLITUDE
	local scale = 1.0 - (i - 1) * 0.14
	local girth = 1.75 * scale
	local seg = newMeshBall(
		i == math.ceil(SEGMENT_COUNT / 2) and "Body" or ("BodySegment" .. i),
		Vector3.new(girth, girth, 1.35),
		ORIGIN * CFrame.new(xOffset, 0, zOffset),
		i % 2 == 0 and BODY_COLOR_LIGHT or BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	segments[i] = seg
	segmentHalfHeights[i] = girth / 2
	segmentX[i] = xOffset
end
local body = segments[math.ceil(SEGMENT_COUNT / 2)]
local headZ = (SEGMENT_COUNT - 1) / 2 * SEGMENT_Z_STEP
local headX = segmentX[1]

-- 1b) Zugespitzte Schnauze vor dem Kopfsegment (verjüngtes Ellipsoid), überlappt
--     das erste Rumpfsegment -> klar "Drache" statt stumpfer Kugelkopf ------------
newMeshBall("Snout", Vector3.new(0.85, 0.75, 1.1), ORIGIN * CFrame.new(headX, -0.05, headZ + 0.85), BODY_COLOR, Enum.Material.SmoothPlastic, model)
newMeshBall("SnoutTip", Vector3.new(0.5, 0.4, 0.5), ORIGIN * CFrame.new(headX, -0.1, headZ + 1.35), BODY_COLOR_LIGHT, Enum.Material.SmoothPlastic, model)

-- 2) Kopf-Horn-Cluster (3 kleine, sich verjüngende Ellipsoid-Hörner), Basis im
--    Kopfsegment eingesenkt ---------------------------------------------------------
for i = 1, 3 do
	local xOff = (i - 2) * 0.35
	newMeshBall(
		"Horn" .. i,
		Vector3.new(0.22, 0.55, 0.22),
		ORIGIN * CFrame.new(headX + xOff, 0.5, headZ + 0.5) * CFrame.Angles(math.rad(-25), 0, 0),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 3) Leuchtende Rückenstacheln (6, entlang der Wirbelsäule, an Segment-Höhe UND
--    Serpentine-X-Versatz angepasst) ------------------------------------------------
for i = 1, 6 do
	local t = (i - 1) / 5 -- 0 (Kopf) .. 1 (Schwanz)
	local zOffset = headZ - t * (SEGMENT_Z_STEP * (SEGMENT_COUNT - 1) + 0.6)
	local segFloat = 1 + t * (SEGMENT_COUNT - 1)
	local lowIndex = math.clamp(math.floor(segFloat), 1, SEGMENT_COUNT)
	local highIndex = math.clamp(math.ceil(segFloat), 1, SEGMENT_COUNT)
	local frac = segFloat - lowIndex
	local halfHeight = segmentHalfHeights[lowIndex] + (segmentHalfHeights[highIndex] - segmentHalfHeights[lowIndex]) * frac
	local xAtSpike = segmentX[lowIndex] + (segmentX[highIndex] - segmentX[lowIndex]) * frac

	newMeshBall(
		"SpineSpike" .. i,
		Vector3.new(0.28, 0.6, 0.3),
		ORIGIN * CFrame.new(xAtSpike, halfHeight + 0.1, zOffset),
		GLOW_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 4) Zwei aufgefächerte Flossen-Flügel (je 2 überlappende, flache Ellipsoide),
--    Wurzel im Rumpf eingesenkt -------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local wingRoot = ORIGIN * CFrame.new(segmentX[2] + side * 0.5, 0.1, 0.9)
	newMeshBall("Wing" .. i, Vector3.new(1.3, 0.18, 1.0), wingRoot * CFrame.new(side * 0.55, 0, 0) * CFrame.Angles(0, 0, math.rad(side * 12)), Color3.fromRGB(95, 28, 22), Enum.Material.SmoothPlastic, model)
	newMeshBall("Wing" .. i .. "Tip", Vector3.new(0.9, 0.14, 0.7), wingRoot * CFrame.new(side * 1.1, 0.05, -0.25) * CFrame.Angles(0, 0, math.rad(side * 22)), GLOW_COLOR, Enum.Material.SmoothPlastic, model)
end

-- 5) Zwei große Glow-Augen, auf dem Kopfsegment sitzend -------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newMeshBall("EyeWhite" .. i, Vector3.new(0.42, 0.4, 0.32), ORIGIN * CFrame.new(headX + side * 0.5, 0.4, headZ + 0.35), Color3.fromRGB(255, 235, 210), Enum.Material.SmoothPlastic, model)
	newMeshBall("Eye" .. i, Vector3.new(0.26, 0.26, 0.2), ORIGIN * CFrame.new(headX + side * 0.5, 0.4, headZ + 0.55), GLOW_COLOR, Enum.Material.Neon, model)
end

-- 6) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

-- The parts above were laid out facing +Z, but the game treats the body's
-- LookVector (-Z) as the front, so turn everything except the body half a
-- circle around it.
do
	local flip = body.CFrame * CFrame.Angles(0, math.pi, 0) * body.CFrame:Inverse()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= body then
			part.CFrame = flip * part.CFrame
		end
	end
end

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Vent Drake")

print("[Abyssara] VentDrake created under Workspace.Assets.Creatures")
