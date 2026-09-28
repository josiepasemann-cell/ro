--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: CrystalLeviathan ("Kristall-Leviathan")
	Rarity (Platzhalter): Mythic
	Beschreibung:
		Die Signatur-Kreatur der Hadal-Tiefe und das erste Mythic-Kreatur-
		Asset des Spiels. Langgestreckter, aalartiger Körper aus eckigen,
		facettierten "Kristall"-Segmenten (Mix aus Part/WedgePart), alle
		lückenlos ineinander verschachtelt, tiefviolett-schwarze Basis mit
		hell leuchtenden Multi-Neon-Nähten (abwechselnd violett/cyan je
		Segment), kleinen kristallinen Flossen-Zacken entlang des Rückens,
		Brustflossen-Paar und einem facettierten Kopf mit Kieferzacken.
		Größtes Kreatur-Modell im Spiel. Zone: HadalDepths.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Kopf-/Hauptsegment) -> für
		  Bewegungssteuerung (langsame, schwere Sinuswellen-Schwimmbewegung
		  mit langer Wellenlänge wird vom Code-Agenten ergänzt).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-Animation. Teile "Segment1".."Segment8" (Kopf zu
		  Schwanz) markieren die Körperkette; ihre jeweiligen
		  "SeamN"-Neon-Teile sollen sequenziell Kopf->Schwanz aufleuchten
		  ("Lauflicht"-Effekt).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 8, 90) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Mythic"
local ZONE = "HadalDepths"
local SEGMENT_COUNT = 8
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

local previous = creaturesFolder:FindFirstChild("CrystalLeviathan")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "CrystalLeviathan"
model.Parent = creaturesFolder

local BASE_COLOR = Color3.fromRGB(30, 15, 45)
local BASE_LIGHT = Color3.fromRGB(50, 28, 70)
local SEAM_COLOR_A = Color3.fromRGB(190, 80, 255)
local SEAM_COLOR_B = Color3.fromRGB(90, 220, 255)

-- 1) Langgestreckter Körper aus 8 sich verjüngenden, eckigen, überlappenden
--    Segmenten (Kette entlang lokaler Z-Achse mit garantierter Überlappung) -----
local body
local SEG_OVERLAP = 0.3
local prevCFrame = ORIGIN
local prevHalfZ = 0.05
local segCenters = {}
local segHeights = {}
for i = 1, SEGMENT_COUNT do
	local t = (i - 1) / (SEGMENT_COUNT - 1) -- 0 (Kopf) .. 1 (Schwanz)
	local width = 3.0 - t * 2.0
	local height = 2.6 - t * 1.7
	local segLength = 1.35
	local halfZ = segLength / 2

	local jointCFrame = prevCFrame * CFrame.new(0, 0, -(prevHalfZ + halfZ - SEG_OVERLAP))

	local segment = newPart(
		"Segment" .. i,
		Vector3.new(width, height, segLength),
		jointCFrame,
		BASE_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)

	if i == 1 then
		body = segment
		body.Name = "Body"
	end

	-- Facettierter Kristall-Akzent (WedgePart oben auf jedem Segment, tief eingebettet)
	local facet = Instance.new("WedgePart")
	facet.Name = "Facet" .. i
	facet.Size = Vector3.new(width * 0.6, 0.7, segLength * 1.0)
	facet.CFrame = jointCFrame * CFrame.new(0, height / 2 + 0.05, 0) * CFrame.Angles(0, math.rad(90), 0)
	facet.Color = BASE_LIGHT
	facet.Material = Enum.Material.Glass
	facet.Transparency = 0.15
	facet.Anchored = true
	facet.CanCollide = false
	facet.Parent = model

	-- Alternierende Neon-Naht (violett/cyan je Segment), auf der Seitenfläche
	local seamColor = (i % 2 == 1) and SEAM_COLOR_A or SEAM_COLOR_B
	newPart(
		"Seam" .. i,
		Vector3.new(width * 0.12, height * 0.4, segLength * 0.95),
		jointCFrame * CFrame.new(width / 2 - 0.05, 0, 0),
		seamColor,
		Enum.Material.Neon,
		model
	)

	-- Kleiner kristalliner Flossen-Zacken entlang des Rückens, in Segment eingebettet
	local spike = Instance.new("WedgePart")
	spike.Name = "SpineSpike" .. i
	spike.Size = Vector3.new(0.3, 0.75, segLength * 0.75)
	spike.CFrame = jointCFrame * CFrame.new(0, height / 2 + 0.35, 0) * CFrame.Angles(0, math.rad(90), math.rad(180))
	spike.Color = seamColor
	spike.Material = Enum.Material.Neon
	spike.Anchored = true
	spike.CanCollide = false
	spike.Parent = model

	segCenters[i] = jointCFrame
	segHeights[i] = height

	prevCFrame = jointCFrame
	prevHalfZ = halfZ
end

-- 2) Kopf-Details: facettierte Kieferzacken + 2 leuchtende Augen ------------------------------------
local headCFrame = segCenters[1]
for i = 1, 4 do
	local x = -0.75 + (i - 1) * 0.5
	local tooth = Instance.new("WedgePart")
	tooth.Name = "HeadTooth" .. i
	tooth.Size = Vector3.new(0.2, 0.4, 0.2)
	tooth.CFrame = headCFrame * CFrame.new(x, -1.1, -0.55) * CFrame.Angles(math.rad(180), 0, 0)
	tooth.Color = Color3.fromRGB(220, 220, 230)
	tooth.Material = Enum.Material.SmoothPlastic
	tooth.Anchored = true
	tooth.CanCollide = false
	tooth.Parent = model
end

for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall(
		"Eye" .. i,
		Vector3.new(0.4, 0.4, 0.4),
		headCFrame * CFrame.new(side * 0.9, 0.3, -0.55),
		SEAM_COLOR_B,
		Enum.Material.Neon,
		model
	)
end

-- 2b) Brustflossen-Paar am Kopfsegment -----------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = Instance.new("WedgePart")
	fin.Name = "SideFin" .. i
	fin.Size = Vector3.new(0.2, 0.9, 1.6)
	fin.CFrame = headCFrame * CFrame.new(side * 1.55, -0.2, 0.4) * CFrame.Angles(0, 0, math.rad(side * -90))
	fin.Color = BASE_COLOR
	fin.Material = Enum.Material.Glass
	fin.Transparency = 0.2
	fin.Anchored = true
	fin.CanCollide = false
	fin.Parent = model
end

-- 3) Schwanz-Kristallspitze, tief im letzten Segment eingebettet -----------------------------------------
local tailCFrame = prevCFrame * CFrame.new(0, 0, -(prevHalfZ + 0.4 - SEG_OVERLAP))
local tailTip = Instance.new("WedgePart")
tailTip.Name = "TailTip"
tailTip.Size = Vector3.new(0.4, 0.4, 0.8)
tailTip.CFrame = tailCFrame * CFrame.Angles(0, math.rad(90), 0)
tailTip.Color = SEAM_COLOR_A
tailTip.Material = Enum.Material.Neon
tailTip.Anchored = true
tailTip.CanCollide = false
tailTip.Parent = model

-- 4) Idle-Puls-Attachment ----------------------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Crystal Leviathan")

print("[Abyssara] CrystalLeviathan created under Workspace.Assets.Creatures")
