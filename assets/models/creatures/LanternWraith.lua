--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: LanternWraith ("Laternengeist")
	Rarity (Platzhalter): Rare
	Beschreibung:
		Rundlicher, cartoonhaft geisterhafter Anglerfisch-Kobold: Silhouette
		aus 3 überlappenden Ellipsoiden (übergroßer Kopf, bauchiger Torso,
		sich verjüngende Schwanzbasis) statt einem einzelnen flachen
		Ellipsoid, mit schimmernder halbtransparenter "Geist"-Hülle
		(Material.ForceField), sichtbaren leuchtenden Zähnchen, einem
		gebogenen, biolumineszenten 4-Segment-Köder-Stiel der vom Kopf nach
		vorne ragt, fächerartiger Rücken-/Schwanzflosse, zwei dünnen,
		halbtransparenten Seitenflossen und großen leuchtend-grünen
		Kulleraugen. Zone: MidnightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-/Schwebe-Animation. Laut Spezifikation bewegt sich der
		  Köder-Stiel mit 2s Sinus-Verzögerung gegenüber dem Körper - das
		  übernimmt der Code-Agent zur Laufzeit, das Buildscript liefert nur
		  die Geometrie (Part "LureTip" markiert die Köder-Spitze).
		- Teile "SideFin1"/"SideFin2" heißen exakt so für automatisches
		  Schwenken (Präfix "sidefin" in IdleSway).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-15, 6, 75) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Rare"
local ZONE = "MidnightZone"
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

local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function newCartoonEye(name, cframe, eyeSize, pupilColor, parent)
	newBall(name, eyeSize, cframe, Color3.fromRGB(230, 255, 240), Enum.Material.Neon, parent)
	newBall(name .. "Pupil", eyeSize * 0.5, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), pupilColor, Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("LanternWraith")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "LanternWraith"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(45, 26, 58)
local BODY_TOP = Color3.fromRGB(30, 16, 42)
local BODY_LIGHT = Color3.fromRGB(75, 48, 96)
local LURE_COLOR = Color3.fromRGB(180, 255, 210)

-- 1) Silhouette aus 3 überlappenden Ellipsoiden: übergroßer Kopf, bauchiger
--    Torso, sich verjüngende Schwanzbasis - statt einem flachen Einzelkörper --
local head = newBall("Head", Vector3.new(2.1, 1.9, 1.9), ORIGIN * CFrame.new(0, 0.15, -1.1), BODY_COLOR, Enum.Material.SmoothPlastic, model)
local body = newBall("Body", Vector3.new(2.0, 1.8, 2.3), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)
newBall("TailBase", Vector3.new(1.3, 1.2, 1.7), ORIGIN * CFrame.new(0, -0.05, 1.7), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Countershading: dunklere Rückenzeichnung, gut eingebettet ---------------
newBall("BackStripe", Vector3.new(0.9, 0.7, 3.3), ORIGIN * CFrame.new(0, 0.85, 0.2), BODY_TOP, Enum.Material.SmoothPlastic, model)

-- 1c) Schimmernde, halbtransparente "Geist"-Hülle über dem gesamten Körper
--     (Material.ForceField gibt eine schwach schimmernde Energie-Textur) -----
local shimmer = newBall("GhostShimmer", Vector3.new(2.6, 2.3, 3.9), ORIGIN * CFrame.new(0, 0.1, 0.1), BODY_LIGHT, Enum.Material.ForceField, model)
shimmer.Transparency = 0.55

-- 2) Kleine, weiche Zahn-Spitzen ----------------------------------------------
local jaw = newBall("LowerJaw", Vector3.new(1.1, 0.55, 0.9), ORIGIN * CFrame.new(0, -0.55, -1.9) * CFrame.Angles(math.rad(8), 0, 0), BODY_COLOR, Enum.Material.SmoothPlastic, model)
for i = 1, 4 do
	local x = -0.32 + (i - 1) * 0.21
	newBall("Tooth" .. i, Vector3.new(0.09, 0.24, 0.09), ORIGIN * CFrame.new(x, -0.2, -2.3) * CFrame.Angles(math.rad(180), 0, 0), Color3.fromRGB(230, 230, 235), Enum.Material.SmoothPlastic, model)
end

-- 3) Köder-Stiel: 4 gebogene, überlappende Ellipsen-Segmente + Leucht-Köder ---
local SEG_OVERLAP = 0.18
local stalkBaseCFrame = ORIGIN * CFrame.new(0, 0.95, -2.15)
local prevHalf = 0.08
local stalkCFrame = stalkBaseCFrame
for seg = 1, 4 do
	local segLength = 0.62
	local half = segLength / 2
	stalkCFrame = stalkCFrame * CFrame.Angles(math.rad(-18), 0, 0) * CFrame.new(0, prevHalf + half - SEG_OVERLAP, 0)
	newBall("LureStalk" .. seg, Vector3.new(0.19, segLength, 0.19), stalkCFrame, LURE_COLOR, Enum.Material.Neon, model)
	prevHalf = half
end

local lureTipCFrame = stalkCFrame * CFrame.new(0, prevHalf + 0.22 - SEG_OVERLAP, 0)
newBall("LureTip", Vector3.new(0.46, 0.46, 0.46), lureTipCFrame, LURE_COLOR, Enum.Material.Neon, model)

-- 4) Fächerartige Rücken- und Schwanzflosse (überlappende, flache Ellipsen) ---
for i = 1, 3 do
	local spread = math.rad(16 * (i - 2))
	newBall(
		"DorsalFin" .. (i == 2 and "" or i),
		Vector3.new(0.16, 0.95, 0.75),
		ORIGIN * CFrame.new(0, 1.05, 0.5) * CFrame.Angles(0, spread, 0),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

for i = 1, 3 do
	local spread = math.rad(14 * (i - 2))
	newBall(
		"TailFin" .. (i == 2 and "" or i),
		Vector3.new(0.16, 1.5, 0.7),
		ORIGIN * CFrame.new(0, 0, 2.7) * CFrame.Angles(0, spread, 0),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 5) Zwei dünne, halbtransparente Seitenflossen --------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = newBall(
		"SideFin" .. i,
		Vector3.new(0.16, 1.2, 1.5),
		ORIGIN * CFrame.new(side * 0.95, 0.1, 0.6) * CFrame.Angles(0, math.rad(side * 20), 0),
		Color3.fromRGB(140, 105, 175),
		Enum.Material.Glass,
		model
	)
	fin.Transparency = 0.4
end

-- 6) Große leuchtend-grüne Kulleraugen ------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 0.6, 0.4, -1.9), Vector3.new(0.46, 0.46, 0.26), Color3.fromRGB(20, 40, 25), model)
end

-- 7) Idle-Puls-Attachment ---------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Lantern Wraith")

print("[Abyssara] LanternWraith created under Workspace.Assets.Creatures")
