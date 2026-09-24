--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Mystery Egg (Rarity-Erwartungsstufe 6/6, höchste Stufe)
	Name: MysteryEgg_Mythic
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)"; Rarity-Skala gemäß GDD Abschnitt 3/8
	("Common → Uncommon → Rare → Epic → Legendary → Mythic → Abyssal").
	Beschreibung:
		Aufwendigstes Ei-Design des Gacha-Sets: zweifarbige Kristallschale
		(Violett-Körper + heller Cyan-Kern), hohe Dornenkrone, ZWEI versetzt
		geneigte Runenringe (CSG-Subtraktion) und drei kleine frei schwebende
		Kristallsplitter-Satelliten um das Ei herum. Hellste Punktlichtquelle
		im gesamten Ei-Set. Klar als "über Legendary" erkennbar, aber noch
		unterhalb der (im GDD separat vorgesehenen) Abyssal-Stufe.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Shell" -> Ansatzpunkt für Öffnungs-Animation und
		  zum Andocken des Öffnungs-VFX-Rigs (siehe GachaEggOpenVFX.lua).
		- model:GetAttribute("EggTier") -> String-Platzhalter ("Mythic").
		- Attachment "PulseAttachment" an Shell -> Ansatzpunkt für Idle-Schwebe-
		  /Puls-Animation.
		- model:GetAttribute("EggName") -> Anzeigename (Platzhalter).
		- PointLight "ShineLight" an Shell -> rein dekorative Lichtquelle.
		- "Satellite1".."Satellite3" -> frei schwebende Splitter-Parts, als
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
local EGG_NAME = "Mysterium-Ei (Mythisch)"
local SHARD_COUNT = 7
local SPIKE_COUNT = 7
local SATELLITE_COUNT = 3
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

-- 1) Grundkörper ----------------------------------------------------------
local baseBall = newPart("ShellBase", Vector3.new(2.9, 3.7, 2.9), ORIGIN, SHELL_COLOR, Enum.Material.Glass, Workspace)
baseBall.Shape = Enum.PartType.Ball

-- 2) Kristallschübe (dichtestes Facettenmuster im Egg-Set) ------------------
local shardParts = {}
for i = 1, SHARD_COUNT do
	local angle = math.rad(360 / SHARD_COUNT * (i - 1))
	local shardCFrame = ORIGIN
		* CFrame.new(math.cos(angle) * 1.2, 0.15, math.sin(angle) * 1.2)
		* CFrame.Angles(0, angle, 0)
		* CFrame.Angles(math.rad(35), 0, 0)
	local shard = newPart("Shard" .. i, Vector3.new(0.72, 1.55, 0.48), shardCFrame, SHELL_COLOR, Enum.Material.Glass, Workspace)
	table.insert(shardParts, shard)
end

-- 3) CSG-Union: Grundkörper + Kristallschübe -------------------------------
local shell = baseBall:UnionAsync(shardParts)
shell.Name = "Shell"
shell.Color = SHELL_COLOR
shell.Material = Enum.Material.Glass
shell.Transparency = 0.05
shell.Anchored = true
shell.CanCollide = false
shell.Parent = model

-- 4) Heller Kern im Zentrum der Schale (durch das Glas sichtbar) ------------
local core = newPart("GlowCore", Vector3.new(0.9, 0.9, 0.9), ORIGIN, CORE_COLOR, Enum.Material.Neon, model)
core.Shape = Enum.PartType.Ball

-- 5) Hohe Dornenkrone (mehr und längere Spitzen als Legendary) --------------
for i = 1, SPIKE_COUNT do
	local angle = math.rad(360 / SPIKE_COUNT * (i - 1))
	local radius = 0.8
	local spikeCFrame = ORIGIN
		* CFrame.new(math.cos(angle) * radius, 1.85, math.sin(angle) * radius)
		* CFrame.Angles(0, angle, 0)
		* CFrame.Angles(math.rad(-15), 0, 0)
	newPart("CrownSpike" .. i, Vector3.new(0.26, 1.3, 0.26), spikeCFrame, CROWN_COLOR, Enum.Material.Neon, model)
end

-- 6) Zwei versetzt geneigte Runenringe (je CSG-Subtraktion) -----------------
local ringConfigs = {
	{ yOffset = -0.2, tilt = 0 },
	{ yOffset = 0.1, tilt = 35 },
}
for i, cfg in ipairs(ringConfigs) do
	local ringBaseCFrame = ORIGIN * CFrame.new(0, cfg.yOffset, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(math.rad(cfg.tilt), 0, 0)

	local outerCyl = newPart("RuneRingOuter" .. i, Vector3.new(0.3, 4.5, 4.5), ringBaseCFrame, RUNE_COLOR, Enum.Material.Neon, Workspace)
	outerCyl.Shape = Enum.PartType.Cylinder

	local innerCyl = newPart("RuneRingInner" .. i, Vector3.new(0.55, 3.8, 3.8), ringBaseCFrame, RUNE_COLOR, Enum.Material.Neon, Workspace)
	innerCyl.Shape = Enum.PartType.Cylinder

	local runeRing = outerCyl:SubtractAsync({ innerCyl })
	runeRing.Name = "RuneRing" .. i
	runeRing.Color = RUNE_COLOR
	runeRing.Material = Enum.Material.Neon
	runeRing.Transparency = 0.1
	runeRing.Anchored = true
	runeRing.CanCollide = false
	runeRing.Parent = model
end

-- 7) Frei schwebende Kristallsplitter-Satelliten um das Ei ------------------
for i = 1, SATELLITE_COUNT do
	local angle = math.rad(360 / SATELLITE_COUNT * (i - 1) + 20)
	local offset = Vector3.new(math.cos(angle) * 3.1, math.sin(angle * 2) * 0.6, math.sin(angle) * 3.1)
	local satellite = newPart("Satellite" .. i, Vector3.new(0.45, 0.7, 0.45), ORIGIN * CFrame.new(offset) * CFrame.Angles(0, angle, math.rad(20)), CORE_COLOR, Enum.Material.Neon, model)
end

-- 8) Punktlicht (hellste Lichtquelle im Egg-Set) -----------------------------
local shineLight = Instance.new("PointLight")
shineLight.Name = "ShineLight"
shineLight.Color = CORE_COLOR
shineLight.Range = 16
shineLight.Brightness = 2.2
shineLight.Parent = shell

-- 9) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Mythic erzeugt unter Workspace.Assets.Gacha")
