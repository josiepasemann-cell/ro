--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Mystery Egg (Rarity-Erwartungsstufe 2/6)
	Name: MysteryEgg_Uncommon
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)".
	Beschreibung:
		Etwas edler als das Common-Ei: satteres Türkis, glatter Kunststoff mit
		leichtem Glanz-Anstrich, zwei Neon-Nahtringe statt einem und ein
		gesprenkeltes Muster aus kleinen Leuchtpunkten. Signalisiert "etwas
		Besseres als Standard", ohne bereits kristallin/durchscheinend zu wirken.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Shell" -> Ansatzpunkt für Öffnungs-Animation und
		  zum Andocken des Öffnungs-VFX-Rigs (siehe GachaEggOpenVFX.lua).
		- model:GetAttribute("EggTier") -> String-Platzhalter ("Uncommon").
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
local ORIGIN = CFrame.new(46, 5, 0) -- Vor Ausführung anpassen für gewünschte Position
local EGG_TIER = "Uncommon"
local EGG_NAME = "Mystery Egg (Uncommon)"
local SPOT_COUNT = 5
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

local previous = gachaFolder:FindFirstChild("MysteryEgg_Uncommon")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MysteryEgg_Uncommon"
model.Parent = gachaFolder

local SHELL_COLOR = Color3.fromRGB(120, 235, 205)
local SEAM_COLOR = Color3.fromRGB(90, 250, 220)
local SPOT_COLOR = Color3.fromRGB(200, 255, 240)

-- 1) Schale: echte Eiform (Block + SpecialMesh Sphere), satteres Türkis -------------
local shell = newMeshBall("Shell", SHELL_SIZE, ORIGIN, SHELL_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Zwei Neon-Nahtringe (oberes + unteres Drittel), exakt auf der Eioberfläche -----
local ringOffsets = { 0.75, -0.75 }
for i, yOffset in ipairs(ringOffsets) do
	local r = eggRadiusAt(yOffset) + 0.05
	local ring = newPart(
		"SeamRing" .. i,
		Vector3.new(0.16, r * 2, r * 2),
		ORIGIN * CFrame.new(0, yOffset, 0) * CFrame.Angles(0, 0, math.rad(90)),
		SEAM_COLOR,
		Enum.Material.Neon,
		model
	)
	ring.Shape = Enum.PartType.Cylinder
end

-- 3) Standring unten -----------------------------------------------------------------
do
	local y = -HALF_Y + 0.35
	local r = eggRadiusAt(y) + 0.05
	local footRing = newPart(
		"FootRing",
		Vector3.new(0.22, r * 2, r * 2),
		ORIGIN * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 190, 165),
		Enum.Material.SmoothPlastic,
		model
	)
	footRing.Shape = Enum.PartType.Cylinder
end

-- 4) Kleiner Gem-Stud oben (glänzendes Ellipsoid statt Wedge-Spitze), überlappt
--    die Schale - toy-artiger Candy-Egg-Look ----------------------------------------
local tip = newMeshBall("TopTip", Vector3.new(0.45, 0.4, 0.45), ORIGIN * CFrame.new(0, HALF_Y - 0.2, 0), SPOT_COLOR, Enum.Material.Neon, model)

-- 5) Gesprenkeltes Muster aus kleinen Leuchtpunkten, ringförmig auf der Schale ------
for i = 1, SPOT_COUNT do
	local angle = math.rad(360 / SPOT_COUNT * (i - 1))
	local y = 0.15
	local r = eggRadiusAt(y) - 0.06
	local pos = Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
	newMeshBall("Spot" .. i, Vector3.new(0.28, 0.28, 0.28), ORIGIN * CFrame.new(pos), SPOT_COLOR, Enum.Material.Neon, model)
end

-- 6) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Uncommon created under Workspace.Assets.Gacha")
