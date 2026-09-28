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
-- Halbachsen der Eiform (siehe SHELL_SIZE weiter unten) - werden gebraucht,
-- um Nahtringe/Details exakt auf die gewölbte Oberfläche zu setzen.
local SHELL_SIZE = Vector3.new(2.6, 3.4, 2.6)
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

-- Block-Part + SpecialMesh(Sphere): rendert eine ECHTE Ei-Form (Ellipsoid,
-- höher als breit). Shape=Ball würde Roblox immer als perfekte Kugel mit der
-- KLEINSTEN Size-Achse als Durchmesser zeichnen - hier bewusst vermieden.
local function newMeshBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Horizontaler Ei-Querschnittsradius auf Höhe `y` (relativ zur Eimitte) -----
local function eggRadiusAt(y)
	local t = math.clamp(y / HALF_Y, -1, 1)
	return HALF_X * math.sqrt(1 - t * t)
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

-- 1) Schale: echte Eiform (Block + SpecialMesh Sphere), mattes Plastik --------------
local shell = newMeshBall("Shell", SHELL_SIZE, ORIGIN, SHELL_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Einzelner dünner Neon-Nahtring um die Äquatorlinie, exakt auf der Schale -------
do
	local y = 0
	local r = eggRadiusAt(y) + 0.05
	local ring = newPart(
		"SeamRing",
		Vector3.new(0.18, r * 2, r * 2),
		ORIGIN * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		SEAM_COLOR,
		Enum.Material.Neon,
		model
	)
	ring.Shape = Enum.PartType.Cylinder
end

-- 3) Kleiner Standring unten (Ei "sitzt" sichtbar auf, statt frei zu schweben) ------
do
	local y = -HALF_Y + 0.35
	local r = eggRadiusAt(y) + 0.05
	local footRing = newPart(
		"FootRing",
		Vector3.new(0.22, r * 2, r * 2),
		ORIGIN * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(180, 220, 220),
		Enum.Material.SmoothPlastic,
		model
	)
	footRing.Shape = Enum.PartType.Cylinder
end

-- 4) Spitzen-Glanzpunkt oben, überlappt die Schale -----------------------------------
newMeshBall(
	"TopHighlight",
	Vector3.new(0.4, 0.35, 0.4),
	ORIGIN * CFrame.new(0, HALF_Y - 0.35, 0),
	Color3.fromRGB(240, 255, 253),
	Enum.Material.SmoothPlastic,
	model
)

-- 5) Drei winzige Sprenkel, leicht in die Schale eingesenkt --------------------------
for i = 1, 3 do
	local angle = math.rad(120 * (i - 1) + 20)
	local y = 0.5
	local r = eggRadiusAt(y) - 0.05
	local pos = Vector3.new(math.cos(angle) * r, y, math.sin(angle) * r)
	newMeshBall("Speckle" .. i, Vector3.new(0.18, 0.18, 0.18), ORIGIN * CFrame.new(pos), SEAM_COLOR, Enum.Material.Neon, model)
end

-- 6) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = shell

model.PrimaryPart = shell
model:SetAttribute("EggTier", EGG_TIER)
model:SetAttribute("EggName", EGG_NAME)

print("[Abyssara] MysteryEgg_Common created under Workspace.Assets.Gacha")
