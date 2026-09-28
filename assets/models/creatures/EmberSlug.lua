--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: EmberSlug ("Ember Slug")
	Rarity (Platzhalter): Uncommon
	Event: VolcanicVent
	Beschreibung:
		Gedrungener Meeresschnecken-Körper, dunkles Anthrazit, mit leuchtend
		orangefarbener Rückenrippe (Neon). Event-exklusive Kreatur des
		"Volcanic Vent"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (Glow wandert Schwanz->Kopf auf 3s-Zyklus entlang der Rippen-Segmente,
		  ansonsten stationär).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("VolcanicVent"), analog "Zone"
		  bei Zonen-Kreaturen.
		- Parts "RidgeSegment1".."RidgeSegment4" -> Ansatzpunkte für die spätere
		  Lauflicht-Animation entlang der Rückenrippe.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-15, 5, 120)
local RARITY = "Uncommon"
local ZONE = "Global"
local EVENT = "VolcanicVent"
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

-- Block-Part + SpecialMesh(Sphere): echtes Ellipsoid statt der immer
-- kugelrunden Shape=Ball-Darstellung (Roblox zeichnet Ball-Parts stets als
-- perfekte Kugel mit der kleinsten Size-Achse als Durchmesser).
local function newMeshBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("EmberSlug")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "EmberSlug"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(40, 30, 30)
local BODY_COLOR_LIGHT = Color3.fromRGB(60, 45, 42)
local GLOW_COLOR = Color3.fromRGB(255, 130, 30)
local CRACK_COLOR = Color3.fromRGB(255, 90, 20)

-- 1) Gedrungener Körper: echtes Ellipsoid (Block + SpecialMesh Sphere) --------------
local body = newMeshBall("Body", Vector3.new(2.5, 1.5, 3.5), ORIGIN, BODY_COLOR, Enum.Material.CrackedLava, model)

-- 1b) Helleres Unterbauch-Detail, überlappt den Körper -------------------------------
local belly = newMeshBall(
	"BellyPlate",
	Vector3.new(1.9, 0.7, 3.0),
	ORIGIN * CFrame.new(0, -0.5, 0),
	BODY_COLOR_LIGHT,
	Enum.Material.SmoothPlastic,
	model
)

-- 2) Glühende Rückenrippe (4 Segmente, Schwanz -> Kopf), in den Rücken eingesenkt ----
for i = 1, 4 do
	local zOffset = 1.1 - (i - 1) * 0.75
	local ridge = newMeshBall(
		"RidgeSegment" .. i,
		Vector3.new(0.45, 0.45, 0.7),
		ORIGIN * CFrame.new(0, 0.42, zOffset),
		GLOW_COLOR,
		Enum.Material.Neon,
		model
	)

	-- feine Riss-Ader (flaches Ellipsoid statt Box) neben jedem Rippensegment,
	-- überlappt Segment + Körper
	newMeshBall(
		"EmberCrack" .. i,
		Vector3.new(0.1, 0.14, 0.5),
		ORIGIN * CFrame.new(0.3, 0.3, zOffset) * CFrame.Angles(0, 0, math.rad(15)),
		CRACK_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 3) Kopfhöcker (klein, vorne, Ansatzpunkt für Augen/Fühler) -------------------------
local head = newMeshBall(
	"Head",
	Vector3.new(1.3, 0.95, 1.0),
	ORIGIN * CFrame.new(0, 0.15, 1.55),
	BODY_COLOR,
	Enum.Material.SmoothPlastic,
	model
)

-- 3b) Zwei Augen mit Glanzpunkt ------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.4, 0.35, 1.95)
	newMeshBall("Eye" .. i, Vector3.new(0.24, 0.24, 0.22), eyeCFrame, GLOW_COLOR, Enum.Material.Neon, model)
	newMeshBall(
		"EyeHighlight" .. i,
		Vector3.new(0.08, 0.08, 0.08),
		eyeCFrame * CFrame.new(0.05, 0.05, 0.1),
		Color3.fromRGB(255, 240, 220),
		Enum.Material.Neon,
		model
	)
end

-- 4) Zwei Fühler, Basis direkt auf dem Kopf ansetzend --------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local baseCFrame = ORIGIN * CFrame.new(side * 0.35, 0.55, 1.85) * CFrame.Angles(math.rad(-20), 0, 0)
	newMeshBall(
		"Antenna" .. i,
		Vector3.new(0.14, 0.45, 0.14),
		baseCFrame * CFrame.new(0, 0.22, 0),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	newMeshBall(
		"AntennaTip" .. i,
		Vector3.new(0.16, 0.16, 0.16),
		baseCFrame * CFrame.new(0, 0.46, 0),
		GLOW_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 5) Kleine Mantelkante hinten (Schwanzabschluss), überlappt den Körper --------------
local tail = newMeshBall(
	"TailRidge",
	Vector3.new(0.6, 0.5, 0.5),
	ORIGIN * CFrame.new(0, 0.1, -1.75),
	BODY_COLOR_LIGHT,
	Enum.Material.SmoothPlastic,
	model
)

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
model:SetAttribute("CreatureName", "Ember Slug")

print("[Abyssara] EmberSlug created under Workspace.Assets.Creatures")
