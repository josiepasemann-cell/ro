--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Mystery Egg (Rarity-Erwartungsstufe 3/6)
	Name: MysteryEgg_Rare
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)".
	Beschreibung:
		Durchscheinende Glas-Schale (Cyan/Türkis) mit per CSG-Union
		aufgesetzten Facetten-Höckern (leicht "juwelenartige" Form statt
		perfekter Kugel), zwei Nahtringen und einem Punktmuster. Deutlich mehr
		"Glanz" als Uncommon durch Glass-Material und Transparenz.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Shell" -> Ansatzpunkt für Öffnungs-Animation und
		  zum Andocken des Öffnungs-VFX-Rigs (siehe GachaEggOpenVFX.lua).
		- model:GetAttribute("EggTier") -> String-Platzhalter ("Rare").
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
local ORIGIN = CFrame.new(52, 5, 0) -- Vor Ausführung anpassen für gewünschte Position
local EGG_TIER = "Rare"
local EGG_NAME = "Mystery Egg (Rare)"
local FACET_COUNT = 6
local SPOT_COUNT = 6
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

local previous = gachaFolder:FindFirstChild("MysteryEgg_Rare")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MysteryEgg_Rare"
model.Parent = gachaFolder

local SHELL_COLOR = Color3.fromRGB(70, 210, 235)
local SEAM_COLOR = Color3.fromRGB(150, 245, 255)
local SPOT_COLOR = Color3.fromRGB(220, 255, 255)

-- 1) Grund-Ei-Körper (temporär in Workspace, wird per Union verschmolzen) ---
local baseBall = newPart("ShellBase", Vector3.new(2.7, 3.6, 2.7), ORIGIN, SHELL_COLOR, Enum.Material.Glass, Workspace)
baseBall.Shape = Enum.PartType.Ball

-- 2) Facetten-Höcker (kleine Kugeln, ringförmig auf halber Höhe verteilt) ---
local facetParts = {}
for i = 1, FACET_COUNT do
	local angle = math.rad(360 / FACET_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * 1.3, 0.2, math.sin(angle) * 1.3)
	local facet = newPart("Facet" .. i, Vector3.new(0.75, 0.75, 0.75), ORIGIN * CFrame.new(offset), SHELL_COLOR, Enum.Material.Glass, Workspace)
	facet.Shape = Enum.PartType.Ball
	table.insert(facetParts, facet)
end

-- 3) CSG-Union: Grundkörper + Facetten -> eine "juwelenartige" Schale -------
local shell = baseBall:UnionAsync(facetParts)
shell.Name = "Shell"
shell.Color = SHELL_COLOR
shell.Material = Enum.Material.Glass
shell.Transparency = 0.15
shell.Anchored = true
shell.CanCollide = false
shell.Parent = model

-- 4) Zwei Neon-Nahtringe -----------------------------------------------------
local ringOffsets = { 0.6, -0.6 }
for i, yOffset in ipairs(ringOffsets) do
	local ringCFrame = ORIGIN * CFrame.new(0, yOffset, 0) * CFrame.Angles(0, 0, math.rad(90))
	local diameter = 2.9 - math.abs(yOffset) * 0.4
	local ring = newPart("SeamRing" .. i, Vector3.new(0.14, diameter, diameter), ringCFrame, SEAM_COLOR, Enum.Material.Neon, model)
	ring.Shape = Enum.PartType.Cylinder
end

-- 5) Leuchtpunkt-Muster ------------------------------------------------------
for i = 1, SPOT_COUNT do
	local angle = math.rad(360 / SPOT_COUNT * (i - 1) + 30)
	local offset = Vector3.new(math.cos(angle) * 1.35, -0.9, math.sin(angle) * 1.35)
	local spot = newPart("Spot" .. i, Vector3.new(0.22, 0.22, 0.22), ORIGIN * CFrame.new(offset), SPOT_COLOR, Enum.Material.Neon, model)
	spot.Shape = Enum.PartType.Ball
end

-- 6) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Rare created under Workspace.Assets.Gacha")
