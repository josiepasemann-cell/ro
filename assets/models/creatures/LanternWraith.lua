--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: LanternWraith ("Laternengeist")
	Rarity (Platzhalter): Rare
	Beschreibung:
		Schlanke Geister-Anglerfisch-Silhouette: abgeflachter, dunkelvioletter
		Ellipsoid-Körper mit spitzem Kopf, sichtbaren Zähnen, einem gebogenen,
		biolumineszenten Köder-Stiel (Neon) der vom Kopf nach vorne ragt,
		Rücken-/Schwanzflosse und zwei dünnen, halbtransparenten Seitenflossen
		(Glass). Zone: MidnightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-/Schwebe-Animation. Laut Spezifikation bewegt sich der
		  Köder-Stiel mit 2s Sinus-Verzögerung gegenüber dem Körper - das
		  übernimmt der Code-Agent zur Laufzeit, das Buildscript liefert nur
		  die Geometrie (Part "LureTip" markiert die Köder-Spitze).
		- Teile "Fin1"/"Fin2" (Präfix "Fin" -> "SideFin"? nein: siehe
		  IdleSway-Präfixliste "wing") heißen "SideFin1"/"SideFin2" für
		  automatisches Schwenken.
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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("LanternWraith")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "LanternWraith"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(35, 20, 45)
local BODY_LIGHT = Color3.fromRGB(60, 38, 78)
local LURE_COLOR = Color3.fromRGB(180, 255, 210)

-- 1) Körper (abgeflacht, geisterhaft, Ellipsoid) -------------------------------
local body = newBall("Body", Vector3.new(2, 2, 5), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Hellere Rückenzeichnung, gut eingebettet ---------------------------------
newBall("BackStripe", Vector3.new(0.7, 1.7, 4.2), ORIGIN * CFrame.new(0, 0.55, 0), BODY_LIGHT, Enum.Material.SmoothPlastic, model)

-- 2) Kopf (etwas breiter, vorne, deutlich überlappend) --------------------------
newBall("Head", Vector3.new(1.7, 1.7, 1.6), ORIGIN * CFrame.new(0, 0.2, -2.1), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2b) Spitzes Kiefer-Wedge und Zähne ---------------------------------------------
local jawCFrame = ORIGIN * CFrame.new(0, -0.35, -2.6) * CFrame.Angles(math.rad(10), 0, 0)
local jaw = Instance.new("WedgePart")
jaw.Name = "LowerJaw"
jaw.Size = Vector3.new(1.0, 0.5, 0.8)
jaw.CFrame = jawCFrame
jaw.Color = BODY_COLOR
jaw.Material = Enum.Material.SmoothPlastic
jaw.Anchored = true
jaw.CanCollide = false
jaw.Parent = model

for i = 1, 4 do
	local x = -0.35 + (i - 1) * 0.23
	local toothCFrame = ORIGIN * CFrame.new(x, -0.15, -2.95) * CFrame.Angles(math.rad(180), 0, 0)
	newPart("Tooth" .. i, Vector3.new(0.07, 0.22, 0.07), toothCFrame, Color3.fromRGB(220, 220, 230), Enum.Material.SmoothPlastic, model)
end

-- 3) Köder-Stiel (3 gebogene, überlappende Segmente, Neon) -----------------------
local SEG_OVERLAP = 0.2
local stalkBaseCFrame = ORIGIN * CFrame.new(0, 0.85, -2.9)
local prevHalf = 0.1
local stalkCFrame = stalkBaseCFrame
for seg = 1, 3 do
	local segLength = 0.9
	local half = segLength / 2
	stalkCFrame = stalkCFrame * CFrame.Angles(math.rad(-22), 0, 0) * CFrame.new(0, prevHalf + half - SEG_OVERLAP, 0)
	newPart(
		"LureStalk" .. seg,
		Vector3.new(0.25, segLength, 0.25),
		stalkCFrame,
		LURE_COLOR,
		Enum.Material.Neon,
		model
	)
	prevHalf = half
end

local lureTipCFrame = stalkCFrame * CFrame.new(0, prevHalf + 0.25 - SEG_OVERLAP, 0)
newBall("LureTip", Vector3.new(0.5, 0.5, 0.5), lureTipCFrame, LURE_COLOR, Enum.Material.Neon, model)

-- 4) Rücken- und Schwanzflosse -----------------------------------------------------
local dorsalFin = Instance.new("WedgePart")
dorsalFin.Name = "DorsalFin"
dorsalFin.Size = Vector3.new(0.18, 0.9, 1.6)
dorsalFin.CFrame = ORIGIN * CFrame.new(0, 1.1, 0.6) * CFrame.Angles(0, math.rad(90), 0)
dorsalFin.Color = BODY_COLOR
dorsalFin.Material = Enum.Material.SmoothPlastic
dorsalFin.Anchored = true
dorsalFin.CanCollide = false
dorsalFin.Parent = model

local tailFinCFrame = ORIGIN * CFrame.new(0, 0, 2.6)
newPart("TailFin", Vector3.new(0.2, 1.7, 1.3), tailFinCFrame, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 5) Zwei dünne, halbtransparente Seitenflossen ------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = newPart(
		"SideFin" .. i,
		Vector3.new(0.15, 1.4, 1.8),
		ORIGIN * CFrame.new(side * 0.9, 0.1, 0.6) * CFrame.Angles(0, math.rad(side * 20), 0),
		Color3.fromRGB(120, 90, 150),
		Enum.Material.Glass,
		model
	)
	fin.Transparency = 0.5
end

-- 6) Kleine Glow-Augen -----------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall(
		"Eye" .. i,
		Vector3.new(0.22, 0.22, 0.22),
		ORIGIN * CFrame.new(side * 0.5, 0.35, -2.55),
		Color3.fromRGB(200, 255, 220),
		Enum.Material.Neon,
		model
	)
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
