--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Mystery Egg (Rarity-Erwartungsstufe 4/6)
	Name: MysteryEgg_Epic
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)".
	Beschreibung:
		Kristalline, violett-neon leuchtende Schale (CSG-Union aus Grundkörper
		+ spitzen Kristallschüben) mit vier pulsierenden Ader-Linien und einer
		leuchtenden Spitze oben. Deutlich "wertiger" als Rare: mehr Facetten,
		kräftigeres Glühen, klar erkennbare Kristallform statt Ei-Kugel.

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
local EGG_NAME = "Mysterium-Ei (Episch)"
local SHARD_COUNT = 5
local VEIN_COUNT = 4
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

-- 1) Grundkörper (leicht verjüngte Eiform) -----------------------------------
local baseBall = newPart("ShellBase", Vector3.new(2.7, 3.5, 2.7), ORIGIN, SHELL_COLOR, Enum.Material.Glass, Workspace)
baseBall.Shape = Enum.PartType.Ball

-- 2) Kristallschübe (verjüngte Boxen, radial nach außen geneigt) ------------
local shardParts = {}
for i = 1, SHARD_COUNT do
	local angle = math.rad(360 / SHARD_COUNT * (i - 1))
	local shardCFrame = ORIGIN
		* CFrame.new(math.cos(angle) * 1.1, 0.1, math.sin(angle) * 1.1)
		* CFrame.Angles(0, angle, 0)
		* CFrame.Angles(math.rad(35), 0, 0)
	local shard = newPart("Shard" .. i, Vector3.new(0.65, 1.4, 0.4), shardCFrame, SHELL_COLOR, Enum.Material.Glass, Workspace)
	table.insert(shardParts, shard)
end

-- 3) CSG-Union: Grundkörper + Kristallschübe -> facettierte Kristallschale --
local shell = baseBall:UnionAsync(shardParts)
shell.Name = "Shell"
shell.Color = SHELL_COLOR
shell.Material = Enum.Material.Glass
shell.Transparency = 0.1
shell.Anchored = true
shell.CanCollide = false
shell.Parent = model

-- 4) Pulsierende Ader-Linien (dünne Neon-Streifen von oben nach unten) ------
for i = 1, VEIN_COUNT do
	local angle = math.rad(360 / VEIN_COUNT * (i - 1))
	local veinCFrame = ORIGIN * CFrame.new(math.cos(angle) * 1.15, 0, math.sin(angle) * 1.15) * CFrame.Angles(0, angle, 0)
	local vein = newPart("Vein" .. i, Vector3.new(0.12, 2.6, 0.12), veinCFrame, VEIN_COLOR, Enum.Material.Neon, model)
end

-- 5) Leuchtende Spitze oben ---------------------------------------------------
local tipCFrame = ORIGIN * CFrame.new(0, 1.95, 0)
local tip = newPart("CrownTip", Vector3.new(0.5, 0.7, 0.5), tipCFrame, TIP_COLOR, Enum.Material.Neon, model)

-- 6) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Epic created under Workspace.Assets.Gacha")
