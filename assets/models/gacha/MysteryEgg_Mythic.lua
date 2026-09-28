--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Mystery Egg (Rarity-Erwartungsstufe 6/6, höchste Stufe)
	Name: MysteryEgg_Mythic
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)"; Rarity-Skala gemäß GDD Abschnitt 3/8
	("Common → Uncommon → Rare → Epic → Legendary → Mythic → Abyssal").
	Beschreibung:
		Aufwendigstes Ei-Design des Gacha-Sets: zweifarbige Kristall-Eischale
		(Violett-Körper + heller Cyan-Kern), hohe Dornenkrone, ZWEI Runenringe
		auf unterschiedlicher Höhe, glühende Risse und drei kleine Kristall-
		splitter-Satelliten, die über dünne Leuchtstreben mit der Schale
		verbunden bleiben (kein frei schwebendes Geometrie-Fragment). Hellste
		Punktlichtquelle im gesamten Ei-Set. Klar als "über Legendary"
		erkennbar, aber noch unterhalb der (im GDD separat vorgesehenen)
		Abyssal-Stufe.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Shell" -> Ansatzpunkt für Öffnungs-Animation und
		  zum Andocken des Öffnungs-VFX-Rigs (siehe GachaEggOpenVFX.lua).
		- model:GetAttribute("EggTier") -> String-Platzhalter ("Mythic").
		- Attachment "PulseAttachment" an Shell -> Ansatzpunkt für Idle-Schwebe-
		  /Puls-Animation.
		- model:GetAttribute("EggName") -> Anzeigename (Platzhalter).
		- PointLight "ShineLight" an Shell -> rein dekorative Lichtquelle.
		- "Satellite1".."Satellite3" -> kleine Kristallsplitter, je über eine
		  eigene "SatelliteTether"-Strebe fest mit der Schale verbunden, als
		  spätere Ansatzpunkte für Orbit-/Rotations-Animation durch den
		  Code-Agenten (rein geometrisch platziert, keine Bewegung im Skript).

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
local ORIGIN = CFrame.new(70, 5, 0) -- Vor Ausführung anpassen für gewünschte Position
local EGG_TIER = "Mythic"
local EGG_NAME = "Mystery Egg (Mythic)"
local SHARD_COUNT = 9
local SPIKE_COUNT = 7
local SATELLITE_COUNT = 3
local CRACK_COUNT = 6
local SHELL_SIZE = Vector3.new(2.9, 3.7, 2.9)
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

local previous = gachaFolder:FindFirstChild("MysteryEgg_Mythic")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MysteryEgg_Mythic"
model.Parent = gachaFolder

local SHELL_COLOR = Color3.fromRGB(135, 60, 255)
local CORE_COLOR = Color3.fromRGB(180, 255, 255)
local CROWN_COLOR = Color3.fromRGB(120, 250, 255)
local RUNE_COLOR = Color3.fromRGB(200, 150, 255)
local CRACK_COLOR = Color3.fromRGB(255, 250, 255)

-- 1) Grundkörper: echte Eiform (Block + SpecialMesh Sphere) -------------------------
local shell = newMeshBall("Shell", SHELL_SIZE, ORIGIN, SHELL_COLOR, Enum.Material.Glass, model)
shell.Transparency = 0.05

-- 2) Kristallschübe (dichtestes Facettenmuster im Egg-Set), eingesenkt --------------
for i = 1, SHARD_COUNT do
	local angle = math.rad(360 / SHARD_COUNT * (i - 1))
	local y = 0.1 + 0.45 * math.sin(i * 1.1)
	local r = eggRadiusAt(y) - 0.22
	local pos = Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
	local shard = newMeshBall("Shard" .. i, Vector3.new(0.52, 0.58, 0.42), ORIGIN * CFrame.new(pos) * CFrame.Angles(0, angle, 0), SHELL_COLOR, Enum.Material.Glass, model)
	shard.Transparency = 0.02
end

-- 3) Heller Kern im oberen Zentrum der Schale (durch das Glas sichtbar) -------------
local core = newMeshBall("GlowCore", Vector3.new(0.9, 0.9, 0.9), ORIGIN * CFrame.new(0, 0.3, 0), CORE_COLOR, Enum.Material.Neon, model)

-- 4) Hohe Dornenkrone (mehr und längere Spitzen als Legendary), Basis eingesenkt ---
for i = 1, SPIKE_COUNT do
	local angle = math.rad(360 / SPIKE_COUNT * (i - 1))
	local y = HALF_Y - 0.6
	local r = eggRadiusAt(y) * 0.72
	local spikeCFrame = ORIGIN
		* CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r)
		* CFrame.Angles(0, angle, 0)
		* CFrame.Angles(math.rad(-20), 0, 0)
	newMeshBall("CrownSpike" .. i, Vector3.new(0.28, 1.2, 0.28), spikeCFrame * CFrame.new(0, 0.4, 0), CROWN_COLOR, Enum.Material.Neon, model)
end

-- 5) Zwei Runenringe auf unterschiedlicher Höhe, fest an die Schale anliegend ------
local ringConfigs = { { y = 0.4, thickness = 0.15 }, { y = -0.5, thickness = 0.16 } }
for i, cfg in ipairs(ringConfigs) do
	local r = eggRadiusAt(cfg.y) + 0.12
	local runeRing = newPart(
		"RuneRing" .. i,
		Vector3.new(cfg.thickness, r * 2, r * 2),
		ORIGIN * CFrame.new(0, cfg.y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		RUNE_COLOR,
		Enum.Material.Neon,
		model
	)
	runeRing.Shape = Enum.PartType.Cylinder
	runeRing.Transparency = 0.1

	for g = 1, 5 do
		local angle = math.rad(72 * (g - 1) + i * 20)
		local gemPos = Vector3.new(math.cos(angle) * r, cfg.y, math.sin(angle) * r)
		newMeshBall("RuneGem" .. i .. "_" .. g, Vector3.new(0.2, 0.2, 0.2), ORIGIN * CFrame.new(gemPos), CROWN_COLOR, Enum.Material.Neon, model)
	end
end

-- 6) Glühende Risse (Neon-Linien), dichter als Legendary -----------------------------
for i = 1, CRACK_COUNT do
	local angle = math.rad(360 / CRACK_COUNT * (i - 1) + 30)
	local y = -1.1
	local r = eggRadiusAt(y) - 0.04
	newMeshBall(
		"CrackGlow" .. i,
		Vector3.new(0.13, 0.95, 0.13),
		ORIGIN * CFrame.new(math.cos(angle) * r, y, math.sin(angle) * r) * CFrame.Angles(0, angle, math.rad(15)),
		CRACK_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 7) Standring unten -------------------------------------------------------------------
do
	local y = -HALF_Y + 0.35
	local r = eggRadiusAt(y) + 0.05
	local footRing = newPart(
		"FootRing",
		Vector3.new(0.26, r * 2, r * 2),
		ORIGIN * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(80, 35, 150),
		Enum.Material.Metal,
		model
	)
	footRing.Shape = Enum.PartType.Cylinder
end

-- 8) Drei Kristallsplitter-Satelliten, JEWEILS über eine dünne Leuchtstrebe fest mit
--    der Schale verbunden (kein frei schwebendes Fragment mehr) --------------------
for i = 1, SATELLITE_COUNT do
	local angle = math.rad(360 / SATELLITE_COUNT * (i - 1) + 20)
	local y = 0.2 * math.sin(i * 2)
	local shellR = eggRadiusAt(y)
	local satR = shellR + 1.15
	local satPos = Vector3.new(math.cos(angle) * satR, y, math.sin(angle) * satR)
	local satCFrame = ORIGIN * CFrame.new(satPos) * CFrame.Angles(0, angle, math.rad(20))

	-- Leuchtstrebe von der Schaloberfläche zum Satelliten (garantiert Überlappung).
	-- CFrame.new(from, to) richtet die lokale -Z-Achse auf `to` aus; ein Part mit
	-- passender Size.Z, mittig auf der Verbindungsstrecke platziert, überdeckt so
	-- exakt (und robust gegenüber Winkeln) die Strecke zwischen beiden Enden.
	local surfacePos = Vector3.new(math.cos(angle) * (shellR - 0.05), y, math.sin(angle) * (shellR - 0.05))
	local worldSurface = (ORIGIN * CFrame.new(surfacePos)).Position
	local worldSatellite = (ORIGIN * CFrame.new(satPos)).Position
	local worldMid = worldSurface:Lerp(worldSatellite, 0.5)
	local tetherLength = (worldSatellite - worldSurface).Magnitude + 0.2
	local tetherCFrame = CFrame.new(worldMid, worldSatellite)
	newPart("SatelliteTether" .. i, Vector3.new(0.12, 0.12, tetherLength), tetherCFrame, CORE_COLOR, Enum.Material.Neon, model)

	newMeshBall("Satellite" .. i, Vector3.new(0.45, 0.6, 0.45), satCFrame, CORE_COLOR, Enum.Material.Neon, model)
end

-- 9) Punktlicht (hellste Lichtquelle im Egg-Set) -----------------------------
local shineLight = Instance.new("PointLight")
shineLight.Name = "ShineLight"
shineLight.Color = CORE_COLOR
shineLight.Range = 16
shineLight.Brightness = 2.2
shineLight.Parent = shell

-- 10) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Mythic created under Workspace.Assets.Gacha")
