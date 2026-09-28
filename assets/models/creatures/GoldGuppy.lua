--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: GoldGuppy ("Gold Guppy")
	Rarity (Platzhalter): Rare
	Event: TreasureTide
	Beschreibung:
		Kleine, klassische Fisch-Silhouette, metallisch goldener Körper
		(Material Metal) mit leuchtender Schwanzflossen-Kante (Neon).
		Event-exklusive Kreatur des "Treasure Tide"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (kurze, schnelle "Dart"-Bewegungsstöße alle 2-3s, sonst regungslos).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("TreasureTide"), analog "Zone"
		  bei Zonen-Kreaturen.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(5, 6, 120)
local RARITY = "Rare"
local ZONE = "Global"
local EVENT = "TreasureTide"
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

-- Block-Part + SpecialMesh(Sphere): echtes Torpedo-Ellipsoid statt der immer
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

local previous = creaturesFolder:FindFirstChild("GoldGuppy")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GoldGuppy"
model.Parent = creaturesFolder

local GOLD_COLOR = Color3.fromRGB(230, 190, 70)
local GOLD_COLOR_DARK = Color3.fromRGB(190, 150, 50)
local GLOW_COLOR = Color3.fromRGB(255, 230, 130)

-- 1) Torpedoförmiger Körper: echtes Ellipsoid (Block + SpecialMesh Sphere) ----------
local body = newMeshBall("Body", Vector3.new(0.8, 1.0, 1.6), ORIGIN, GOLD_COLOR, Enum.Material.Metal, model)

-- 1b) Rückenflosse (klein, oben mittig), überlappt den Körper -----------------------
local dorsalFin = Instance.new("WedgePart")
dorsalFin.Name = "DorsalFin"
dorsalFin.Size = Vector3.new(0.08, 0.4, 0.5)
dorsalFin.CFrame = ORIGIN * CFrame.new(0, 0.55, 0.1) * CFrame.Angles(math.rad(-30), 0, 0)
dorsalFin.Color = GOLD_COLOR_DARK
dorsalFin.Material = Enum.Material.Metal
dorsalFin.Anchored = true
dorsalFin.CanCollide = false
dorsalFin.TopSurface = Enum.SurfaceType.Smooth
dorsalFin.BottomSurface = Enum.SurfaceType.Smooth
dorsalFin.Parent = model

-- 1c) Zwei Augen mit Glanzpunkt ------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.3, 0.18, 0.65)
	newMeshBall("Eye" .. i, Vector3.new(0.16, 0.16, 0.16), eyeCFrame, Color3.fromRGB(20, 20, 25), Enum.Material.SmoothPlastic, model)
	newMeshBall(
		"EyeHighlight" .. i,
		Vector3.new(0.05, 0.05, 0.05),
		eyeCFrame * CFrame.new(0.04, 0.04, 0.07),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.Neon,
		model
	)
end

-- 2) Schwanzflosse mit leuchtender Kante, Wurzel im Körper eingesenkt ---------------
local tailWedge = Instance.new("WedgePart")
tailWedge.Name = "TailFin"
tailWedge.Size = Vector3.new(0.1, 0.8, 0.7)
tailWedge.CFrame = ORIGIN * CFrame.new(0, 0, -0.6) * CFrame.Angles(0, math.rad(90), 0)
tailWedge.Color = GOLD_COLOR
tailWedge.Material = Enum.Material.Metal
tailWedge.Anchored = true
tailWedge.CanCollide = false
tailWedge.TopSurface = Enum.SurfaceType.Smooth
tailWedge.BottomSurface = Enum.SurfaceType.Smooth
tailWedge.Parent = model

local tailEdge = newPart(
	"TailFinEdge",
	Vector3.new(0.08, 0.85, 0.15),
	ORIGIN * CFrame.new(0, 0, -0.95),
	GLOW_COLOR,
	Enum.Material.Neon,
	model
)

-- 3) Zwei kleine Seitenflossen, Wurzel im Körper eingesenkt --------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = Instance.new("WedgePart")
	fin.Name = "SideFin" .. i
	fin.Size = Vector3.new(0.5, 0.1, 0.4)
	fin.CFrame = ORIGIN * CFrame.new(side * 0.3, -0.1, 0.1) * CFrame.Angles(0, 0, math.rad(side * 25))
	fin.Color = GOLD_COLOR
	fin.Material = Enum.Material.Metal
	fin.Anchored = true
	fin.CanCollide = false
	fin.TopSurface = Enum.SurfaceType.Smooth
	fin.BottomSurface = Enum.SurfaceType.Smooth
	fin.Parent = model
end

-- 4) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Gold Guppy")

print("[Abyssara] GoldGuppy created under Workspace.Assets.Creatures")
