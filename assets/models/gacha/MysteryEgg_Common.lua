--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gacha – Mystery Egg (Rarity-Erwartungsstufe 1/6)
	Name: MysteryEgg_Common
	Bezug: docs/expansion-concepts.md, Abschnitt 1.7 "Mystery Egg Gacha
	(Compliance-konform)".
	Beschreibung:
		Einfachstes Ei-Design des Gacha-Sets: schlichte, glatte Eiform aus
		mattem Kunststoff, blass cyanfarben, mit nur einem dünnen Neon-Nahtring.
		Bewusst das "günstigste" Erscheinungsbild (Form/Muster/Glanz minimal) –
		die Erwartung "das ist wahrscheinlich nur ein Common" soll optisch klar
		sein, ohne dass Zahlen sichtbar sein müssen.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Shell" -> Ansatzpunkt für Öffnungs-Animation
		  (Skalierung/Zerbersten) und zum Andocken des Öffnungs-VFX-Rigs
		  (siehe GachaEggOpenVFX.lua).
		- model:GetAttribute("EggTier") -> String-Platzhalter ("Common"), vom
		  Code-Agenten später mit der echten Drop-Tabelle/GachaService
		  verknüpft. Bestimmt NICHT selbst irgendeine Zufalls-Logik.
		- Attachment "PulseAttachment" an Shell -> Ansatzpunkt für Idle-Schwebe-
		  /Puls-Animation, analog zu den Kreaturen-Modellen.
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
local ORIGIN = CFrame.new(40, 5, 0) -- Vor Ausführung anpassen für gewünschte Position
local EGG_TIER = "Common"
local EGG_NAME = "Mystery Egg (Common)"
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

local previous = gachaFolder:FindFirstChild("MysteryEgg_Common")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MysteryEgg_Common"
model.Parent = gachaFolder

local SHELL_COLOR = Color3.fromRGB(215, 250, 245)
local SEAM_COLOR = Color3.fromRGB(140, 230, 255)

-- 1) Schale (glatte Eiform, mattes Plastik, kein Glanz) ---------------------
local shell = newPart("Shell", Vector3.new(2.6, 3.4, 2.6), ORIGIN, SHELL_COLOR, Enum.Material.SmoothPlastic, model)
shell.Shape = Enum.PartType.Ball

-- 2) Einzelner dünner Neon-Nahtring um die Äquatorlinie ---------------------
local seamCFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))
local seam = newPart("SeamRing", Vector3.new(0.18, 2.75, 2.75), seamCFrame, SEAM_COLOR, Enum.Material.Neon, model)
seam.Shape = Enum.PartType.Cylinder

-- 3) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Common created under Workspace.Assets.Gacha")
