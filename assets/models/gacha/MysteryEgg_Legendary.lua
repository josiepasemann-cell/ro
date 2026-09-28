--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Mystery Egg (Rarity-Erwartungsstufe 5/6)
	Name: MysteryEgg_Legendary
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)".
	Beschreibung:
		Zweifarbige (Violett-Körper + Cyan-Krone) Kristall-Eischale mit
		Dornenkrone, einem eng anliegenden leuchtenden Runenring um den
		Äquator und glühenden Rissen sowie einem sanften Punktlicht als
		zusätzlichem Glanz-Element. Deutlich aufwendiger als Epic: mehr
		Spitzen, zweiter Farbakzent, eigene Lichtquelle, sichtbare Risse.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Shell" -> Ansatzpunkt für Öffnungs-Animation und
		  zum Andocken des Öffnungs-VFX-Rigs (siehe GachaEggOpenVFX.lua).
		- model:GetAttribute("EggTier") -> String-Platzhalter ("Legendary").
		- Attachment "PulseAttachment" an Shell -> Ansatzpunkt für Idle-Schwebe-
		  /Puls-Animation.
		- model:GetAttribute("EggName") -> Anzeigename (Platzhalter).
		- PointLight "ShineLight" an Shell -> rein dekorative Lichtquelle,
		  vom Code-Agenten später ggf. für Intensitäts-Animation nutzbar.

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
local ORIGIN = CFrame.new(64, 5, 0) -- Vor Ausführung anpassen für gewünschte Position
local EGG_TIER = "Legendary"
local EGG_NAME = "Mystery Egg (Legendary)"
local SHARD_COUNT = 8
local SPIKE_COUNT = 5
local CRACK_COUNT = 4
local SHELL_SIZE = Vector3.new(2.8, 3.6, 2.8)
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

local previous = gachaFolder:FindFirstChild("MysteryEgg_Legendary")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MysteryEgg_Legendary"
model.Parent = gachaFolder

local SHELL_COLOR = Color3.fromRGB(150, 70, 255)
local CROWN_COLOR = Color3.fromRGB(110, 245, 255)
local RUNE_COLOR = Color3.fromRGB(160, 255, 255)
local CRACK_COLOR = Color3.fromRGB(255, 245, 255)

-- 1) Grundkörper: echte Eiform (Block + SpecialMesh Sphere) -------------------------
local shell = newMeshBall("Shell", SHELL_SIZE, ORIGIN, SHELL_COLOR, Enum.Material.Glass, model)
shell.Transparency = 0.08

-- 2) Kristallschübe (facettierte Oberfläche, zahlreicher als Epic), eingesenkt ------
for i = 1, SHARD_COUNT do
	local angle = math.rad(360 / SHARD_COUNT * (i - 1))
	local y = 0.1 + 0.4 * math.sin(i * 1.3)
	local r = eggRadiusAt(y) - 0.2
	local pos = Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
	local shard = Instance.new("WedgePart")
	shard.Name = "Shard" .. i
	shard.Size = Vector3.new(0.65, 0.8, 0.5)
	shard.CFrame = ORIGIN * CFrame.new(pos) * CFrame.Angles(0, angle, 0) * CFrame.Angles(0, 0, math.rad(90))
	shard.Color = SHELL_COLOR
	shard.Material = Enum.Material.Glass
	shard.Transparency = 0.05
	shard.Anchored = true
	shard.CanCollide = false
	shard.TopSurface = Enum.SurfaceType.Smooth
	shard.BottomSurface = Enum.SurfaceType.Smooth
	shard.Parent = model
end

-- 3) Dornenkrone oben (radial angeordnete, sich verjüngende Cyan-Spitzen), Basis
--    im oberen Schalenbereich eingesenkt ------------------------------------------
for i = 1, SPIKE_COUNT do
	local angle = math.rad(360 / SPIKE_COUNT * (i - 1))
	local y = HALF_Y - 0.55
	local r = eggRadiusAt(y) * 0.7
	local spikeCFrame = ORIGIN
		* CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r)
		* CFrame.Angles(0, angle, 0)
		* CFrame.Angles(math.rad(-20), 0, 0)
	newPart("CrownSpike" .. i, Vector3.new(0.28, 1.0, 0.28), spikeCFrame * CFrame.new(0, 0.3, 0), CROWN_COLOR, Enum.Material.Neon, model)
end

-- 4) Leuchtender Runenring, eng um den Äquator anliegend (kein freischwebendes CSG-
--    Objekt mehr, sondern fest mit der Schale verbunden), plus kleine "Runen"-Gemme
--    entlang des Rings --------------------------------------------------------------
do
	local y = 0
	local r = eggRadiusAt(y) + 0.12
	local runeRing = newPart(
		"RuneRing",
		Vector3.new(0.35, r * 2, r * 2),
		ORIGIN * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		RUNE_COLOR,
		Enum.Material.Neon,
		model
	)
	runeRing.Shape = Enum.PartType.Cylinder

	for i = 1, 6 do
		local angle = math.rad(60 * (i - 1))
		local gemPos = Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
		newMeshBall("RuneGem" .. i, Vector3.new(0.22, 0.22, 0.22), ORIGIN * CFrame.new(gemPos), CROWN_COLOR, Enum.Material.Neon, model)
	end
end

-- 5) Glühende Risse (Neon-Linien), Legendary-exklusives Ornament --------------------
for i = 1, CRACK_COUNT do
	local angle = math.rad(360 / CRACK_COUNT * (i - 1) + 45)
	local y = -0.9
	local r = eggRadiusAt(y) - 0.04
	local crack = newPart(
		"CrackGlow" .. i,
		Vector3.new(0.08, 0.9, 0.08),
		ORIGIN * CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r) * CFrame.Angles(0, angle, math.rad(15)),
		CRACK_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 6) Standring unten -------------------------------------------------------------------
do
	local y = -HALF_Y + 0.35
	local r = eggRadiusAt(y) + 0.05
	local footRing = newPart(
		"FootRing",
		Vector3.new(0.24, r * 2, r * 2),
		ORIGIN * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(90, 40, 160),
		Enum.Material.Metal,
		model
	)
	footRing.Shape = Enum.PartType.Cylinder
end

-- 7) Punktlicht als zusätzlicher Glanz-Akzent (rein dekorativ, statisch) ----
local shineLight = Instance.new("PointLight")
shineLight.Name = "ShineLight"
shineLight.Color = CROWN_COLOR
shineLight.Range = 12
shineLight.Brightness = 1.5
shineLight.Parent = shell

-- 8) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Legendary created under Workspace.Assets.Gacha")
