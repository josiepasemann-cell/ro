--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Mystery Egg (Rarity-Erwartungsstufe 4/6)
	Name: MysteryEgg_Epic
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)".
	Beschreibung:
		Kristalline, violett-neon leuchtende Eischale mit dichten Facetten-
		Kristallschüben, vier pulsierenden Ader-Linien und einer leuchtenden
		Kronenspitze oben. Deutlich "wertiger" als Rare: mehr Facetten,
		kräftigeres Glühen, klar erkennbare Kristall-Textur.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Shell" -> Ansatzpunkt für Öffnungs-Animation und
		  zum Andocken des Öffnungs-VFX-Rigs (siehe GachaEggOpenVFX.lua).
		- model:GetAttribute("EggTier") -> String-Platzhalter ("Epic").
		- Attachment "PulseAttachment" an Shell -> Ansatzpunkt für Idle-Schwebe-
		  /Puls-Animation.
		- model:GetAttribute("EggName") -> Anzeigename (Platzhalter).

	WICHTIG: Dieses Skript enthält AUSSCHLIESSLICH Geometrie-Erzeugung. Keine
	Gacha-/Zufalls-/Kauf-/Persistenz-Logik. Das kommt bewusst erst später durch
	den Code-Agenten.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script
		unter ServerScriptService einfügen und einmal laufen lassen. Wiederholtes
		Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(58, 5, 0) -- Vor Ausführung anpassen für gewünschte Position
local EGG_TIER = "Epic"
local EGG_NAME = "Mystery Egg (Epic)"
local SHARD_COUNT = 7
local VEIN_COUNT = 4
local SHELL_SIZE = Vector3.new(2.7, 3.5, 2.7)
local HALF_X, HALF_Y = SHELL_SIZE.X / 2, SHELL_SIZE.Y / 2
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

-- Block-Part + SpecialMesh(Sphere): echte Ei-Form (Ellipsoid) statt der immer
-- kugelrunden Shape=Ball-Darstellung.
local function newMeshBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function eggRadiusAt(y)
	local t = math.clamp(y / HALF_Y, -1, 1)
	return HALF_X * math.sqrt(1 - t * t)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local gachaFolder = getOrCreateFolder(assetsFolder, "Gacha")

local previous = gachaFolder:FindFirstChild("MysteryEgg_Epic")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MysteryEgg_Epic"
model.Parent = gachaFolder

local SHELL_COLOR = Color3.fromRGB(170, 90, 255)
local VEIN_COLOR = Color3.fromRGB(210, 150, 255)
local TIP_COLOR = Color3.fromRGB(225, 180, 255)

-- 1) Grundkörper: echte Eiform (Block + SpecialMesh Sphere), leicht verjüngt --------
local shell = newMeshBall("Shell", SHELL_SIZE, ORIGIN, SHELL_COLOR, Enum.Material.Glass, model)
shell.Transparency = 0.1

-- 2) Kristall-Gems (glänzende Ellipsoide statt Keile), dichter als Rare, eingesenkt
--    in die Schale -> toy-artige Candy-Gem-Studs ------------------------------------
for i = 1, SHARD_COUNT do
	local angle = math.rad(360 / SHARD_COUNT * (i - 1))
	local y = 0.15 + 0.35 * math.sin(i)
	local r = eggRadiusAt(y) - 0.18
	local pos = Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
	local shard = newMeshBall("Shard" .. i, Vector3.new(0.45, 0.5, 0.35), ORIGIN * pos * CFrame.Angles(0, angle, 0), SHELL_COLOR, Enum.Material.Glass, model)
	shard.Transparency = 0.05
end

-- 3) Pulsierende Ader-Bänder (dünne, hohe Neon-Ellipsoide statt Boxen) --------------
for i = 1, VEIN_COUNT do
	local angle = math.rad(360 / VEIN_COUNT * (i - 1))
	local r = eggRadiusAt(0) - 0.04
	newMeshBall(
		"Vein" .. i,
		Vector3.new(0.18, HALF_Y * 1.5, 0.18),
		ORIGIN * CFrame.new(math.cos(angle) * r, 0, math.sin(angle) * r) * CFrame.Angles(0, angle, 0),
		VEIN_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 4) Standring unten -------------------------------------------------------------------
do
	local y = -HALF_Y + 0.35
	local r = eggRadiusAt(y) + 0.05
	local footRing = newPart(
		"FootRing",
		Vector3.new(0.22, r * 2, r * 2),
		ORIGIN * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(120, 60, 190),
		Enum.Material.Metal,
		model
	)
	footRing.Shape = Enum.PartType.Cylinder
end

-- 5) Leuchtender Gem-Stud oben (Ellipsoid statt Kronenspitze), überlappt die Schale --
local tip = newMeshBall("CrownTip", Vector3.new(0.55, 0.6, 0.55), ORIGIN * CFrame.new(0, HALF_Y - 0.25, 0), TIP_COLOR, Enum.Material.Neon, model)

-- 6) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Epic created under Workspace.Assets.Gacha")
