--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: FrostAnglerPup ("Frost Angler Pup")
	Rarity (Platzhalter): Rare
	Event: FrozenCurrent
	Beschreibung:
		Kleine, rundlichere Jungtier-Version der Anglerfisch-Silhouette,
		blass eisblauer Körper, winziger leuchtender Köder-Spitze und
		Frost-Kristall-Akzenten (kleine weiße WedgeParts am Rücken).
		Event-exklusive Kreatur des "Frozen Current"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (schnelles Zittern 0.2s-Periode zwischen langsamen Hover-Drifts).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("FrozenCurrent"), analog "Zone"
		  bei Zonen-Kreaturen.
		- Part "LureOrb" + Attachment "MuzzlePoint" -> Köder-/Effektpunkt, analog
		  AnglerfishTower/Anglerfish-Konvention.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 6, 105)
local RARITY = "Rare"
local ZONE = "Global"
local EVENT = "FrozenCurrent"
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
-- kugelrunden Shape=Ball-Darstellung.
local function newMeshBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("FrostAnglerPup")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "FrostAnglerPup"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(180, 220, 240)
local BELLY_COLOR = Color3.fromRGB(220, 240, 250)
local LURE_COLOR = Color3.fromRGB(210, 245, 255)

-- 1) Rundlicher Körper: echtes Ellipsoid (Block + SpecialMesh Sphere) --------------
local body = newMeshBall("Body", Vector3.new(1.8, 1.5, 2.4), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Helle Bauchunterseite, überlappt den Körper -----------------------------------
local belly = newMeshBall(
	"Belly",
	Vector3.new(1.35, 0.85, 1.9),
	ORIGIN * CFrame.new(0, -0.4, 0.05),
	BELLY_COLOR,
	Enum.Material.SmoothPlastic,
	model
)

-- 1c) Zwei Augen mit Glanzpunkt ------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.42, 0.24, 1.15)
	newMeshBall("EyeWhite" .. i, Vector3.new(0.42, 0.42, 0.32), eyeCFrame, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, model)
	newMeshBall("Eye" .. i, Vector3.new(0.24, 0.24, 0.2), eyeCFrame * CFrame.new(0, -0.01, 0.1), Color3.fromRGB(20, 30, 40), Enum.Material.SmoothPlastic, model)
	newMeshBall(
		"EyeHighlight" .. i,
		Vector3.new(0.09, 0.09, 0.08),
		eyeCFrame * CFrame.new(0.07, 0.07, 0.16),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.Neon,
		model
	)
end

-- 2) Köderstab (2 leicht gebogene, sich verjüngende Ellipsoid-Segmente statt Box)
--    + leuchtende Spitze, Basis im Körper eingesenkt -------------------------------
local stalkBase = ORIGIN * CFrame.new(0, 0.35, 0.85)
newMeshBall("LureStalk", Vector3.new(0.16, 0.4, 0.16), stalkBase * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0.2, 0), BODY_COLOR, Enum.Material.Ice, model)
newMeshBall("LureStalkTip", Vector3.new(0.13, 0.35, 0.13), stalkBase * CFrame.Angles(math.rad(-10), 0, 0) * CFrame.new(0, 0.55, 0), BODY_COLOR, Enum.Material.Ice, model)

local lureOrb = newMeshBall(
	"LureOrb",
	Vector3.new(0.35, 0.35, 0.35),
	stalkBase * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0.75, 0),
	LURE_COLOR,
	Enum.Material.Neon,
	model
)

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = lureOrb

-- 3) Frost-Kristall-Akzente (3 kleine, spitz zulaufende Ellipsoide statt Wedges,
--    Material Ice) am Rücken, eingesenkt --------------------------------------------
for i = 1, 3 do
	local zOffset = 0.5 - i * 0.4
	newMeshBall("FrostCrystal" .. i, Vector3.new(0.28, 0.45, 0.28), ORIGIN * CFrame.new(0, 0.6, zOffset), Color3.fromRGB(235, 248, 255), Enum.Material.Ice, model)
end

-- 4) Zwei kleine, aufgefächerte Seitenflossen (je 2 dünne Ellipsoide, Glass),
--    Basis im Körper eingesenkt ------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local finRoot = ORIGIN * CFrame.new(side * 0.65, -0.1, -0.3) * CFrame.Angles(0, 0, math.rad(side * 20))
	local fin1 = newMeshBall("SideFin" .. i, Vector3.new(0.14, 0.5, 0.7), finRoot, Color3.fromRGB(200, 235, 250), Enum.Material.Glass, model)
	fin1.Transparency = 0.4
	local fin2 = newMeshBall("SideFin" .. i .. "B", Vector3.new(0.12, 0.35, 0.45), finRoot * CFrame.new(side * 0.12, -0.15, -0.25), Color3.fromRGB(200, 235, 250), Enum.Material.Glass, model)
	fin2.Transparency = 0.4
end

-- 4b) Fächerförmige Schwanzflosse (3 überlappende dünne Ellipsoide statt Wedge),
--     hinten, überlappt den Körper ---------------------------------------------------
local tailRoot = ORIGIN * CFrame.new(0, 0, -1.05)
for i, angleDeg in ipairs({ -22, 0, 22 }) do
	local lamellaCFrame = tailRoot * CFrame.Angles(0, math.rad(angleDeg), 0)
	local tailFin = newMeshBall(i == 2 and "TailFin" or ("TailFin" .. i), Vector3.new(0.12, 0.55, 0.5), lamellaCFrame * CFrame.new(0, 0, -0.25), Color3.fromRGB(200, 235, 250), Enum.Material.Glass, model)
	tailFin.Transparency = 0.35
end

-- 5) Idle-Puls-Attachment ------------------------------------------------------------
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
model:SetAttribute("CreatureName", "Frost Angler Pup")

print("[Abyssara] FrostAnglerPup created under Workspace.Assets.Creatures")
