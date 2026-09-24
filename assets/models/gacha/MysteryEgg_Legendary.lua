--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Mystery Egg (Rarity-Erwartungsstufe 5/6)
	Name: MysteryEgg_Legendary
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)".
	Beschreibung:
		Zweifarbige (Violett-Körper + Cyan-Krone) Kristallschale mit
		Dornenkrone, einem freischwebenden Runenring (CSG-Subtraktion, analog
		zur BroodPool-Ringtechnik) und einem sanften Punktlicht als zusätzlichem
		Glanz-Element. Deutlich aufwendiger als Epic: mehr Spitzen, zweiter
		Farbakzent, eigene Lichtquelle.

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
local EGG_NAME = "Mysterium-Ei (Legendär)"
local SHARD_COUNT = 6
local SPIKE_COUNT = 5
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

-- 1) Grundkörper --------------------------------------------------------------
local baseBall = newPart("ShellBase", Vector3.new(2.8, 3.6, 2.8), ORIGIN, SHELL_COLOR, Enum.Material.Glass, Workspace)
baseBall.Shape = Enum.PartType.Ball

-- 2) Kristallschübe (facettierte Oberfläche, wie Epic aber zahlreicher) -----
local shardParts = {}
for i = 1, SHARD_COUNT do
	local angle = math.rad(360 / SHARD_COUNT * (i - 1))
	local shardCFrame = ORIGIN
		* CFrame.new(math.cos(angle) * 1.15, 0.15, math.sin(angle) * 1.15)
		* CFrame.Angles(0, angle, 0)
		* CFrame.Angles(math.rad(35), 0, 0)
	local shard = newPart("Shard" .. i, Vector3.new(0.7, 1.5, 0.45), shardCFrame, SHELL_COLOR, Enum.Material.Glass, Workspace)
	table.insert(shardParts, shard)
end

-- 3) CSG-Union: Grundkörper + Kristallschübe ---------------------------------
local shell = baseBall:UnionAsync(shardParts)
shell.Name = "Shell"
shell.Color = SHELL_COLOR
shell.Material = Enum.Material.Glass
shell.Transparency = 0.08
shell.Anchored = true
shell.CanCollide = false
shell.Parent = model

-- 4) Dornenkrone oben (radial angeordnete, sich verjüngende Cyan-Spitzen) ---
for i = 1, SPIKE_COUNT do
	local angle = math.rad(360 / SPIKE_COUNT * (i - 1))
	local radius = 0.75
	local spikeCFrame = ORIGIN
		* CFrame.new(math.cos(angle) * radius, 1.75, math.sin(angle) * radius)
		* CFrame.Angles(0, angle, 0)
		* CFrame.Angles(math.rad(-15), 0, 0)
	newPart("CrownSpike" .. i, Vector3.new(0.28, 1.0, 0.28), spikeCFrame, CROWN_COLOR, Enum.Material.Neon, model)
end

-- 5) Freischwebender Runenring (CSG-Subtraktion: Außen- minus Innenzylinder,
--    analog zur BroodPool-Ringtechnik) --------------------------------------
local outerCFrame = ORIGIN * CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(90))
local outerCyl = newPart("RuneRingOuter", Vector3.new(0.35, 4.2, 4.2), outerCFrame, RUNE_COLOR, Enum.Material.Neon, Workspace)
outerCyl.Shape = Enum.PartType.Cylinder

local innerCFrame = ORIGIN * CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(90))
local innerCyl = newPart("RuneRingInner", Vector3.new(0.6, 3.5, 3.5), innerCFrame, RUNE_COLOR, Enum.Material.Neon, Workspace)
innerCyl.Shape = Enum.PartType.Cylinder

local runeRing = outerCyl:SubtractAsync({ innerCyl })
runeRing.Name = "RuneRing"
runeRing.Color = RUNE_COLOR
runeRing.Material = Enum.Material.Neon
runeRing.Anchored = true
runeRing.CanCollide = false
runeRing.Parent = model

-- 6) Punktlicht als zusätzlicher Glanz-Akzent (rein dekorativ, statisch) ----
local shineLight = Instance.new("PointLight")
shineLight.Name = "ShineLight"
shineLight.Color = CROWN_COLOR
shineLight.Range = 12
shineLight.Brightness = 1.5
shineLight.Parent = shell

-- 7) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Legendary created under Workspace.Assets.Gacha")
