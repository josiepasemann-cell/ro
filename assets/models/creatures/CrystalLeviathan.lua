--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: CrystalLeviathan ("Kristall-Leviathan")
	Rarity (Platzhalter): Mythic
	Beschreibung:
		Die Signatur-Kreatur der Hadal-Tiefe und das erste Mythic-Kreatur-
		Asset des Spiels - soll deutlich beeindruckender wirken als alle
		anderen Kreaturen. Langgestreckter, aalartiger Körper aus 9 sich
		verjüngenden, überlappenden ELLIPSOID-Segmenten (organisch rund,
		keine kantigen Blöcke), tiefviolett-schwarze Basis mit hell
		leuchtenden Multi-Neon-Nähten (abwechselnd violett/cyan je
		Segment), kleinen Kristallfacetten-Zacken (WedgePart, bewusst
		spärlich als "hartes" Detail) entlang des Rückens, einem
		übergroßen, cartoonhaft ausdrucksstarken Kopf mit Kristallkrone,
		leuchtendem Brust-Kernjuwel, großen Kulleraugen, sichtbaren
		Fangzähnen, einem fächerartigen Brustflossen-Paar und einer
		großen, dramatischen Schwanzflossen-Fächer-Spitze. Größtes und
		aufwendigstes Kreatur-Modell im Spiel. Zone: HadalDepths.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Kopf-/Hauptsegment) -> für
		  Bewegungssteuerung (langsame, schwere Sinuswellen-Schwimmbewegung
		  mit langer Wellenlänge wird vom Code-Agenten ergänzt).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-Animation. Teile "Segment1".."Segment9" (Kopf zu
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
local SEGMENT_COUNT = 9
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

local function newWedge(name, size, cframe, color, material, parent)
	local part = Instance.new("WedgePart")
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

local function newCartoonEye(name, cframe, eyeSize, pupilColor, parent)
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.55, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), pupilColor, Enum.Material.Neon, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
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

local BASE_COLOR = Color3.fromRGB(32, 16, 48)
local BASE_TOP = Color3.fromRGB(20, 9, 32)
local BASE_LIGHT = Color3.fromRGB(56, 30, 78)
local SEAM_COLOR_A = Color3.fromRGB(195, 85, 255)
local SEAM_COLOR_B = Color3.fromRGB(90, 220, 255)

-- 1) Langgestreckter Körper aus 9 sich verjüngenden, ORGANISCHEN Ellipsoid-
--    Segmenten (Kette entlang lokaler Z-Achse mit garantierter Überlappung) -----
local body
local SEG_OVERLAP = 0.32
local prevCFrame = ORIGIN
local prevHalfZ = 0.05
local segCenters = {}
local segHeights = {}
for i = 1, SEGMENT_COUNT do
	local t = (i - 1) / (SEGMENT_COUNT - 1) -- 0 (Kopf) .. 1 (Schwanz)
	local width = 3.2 - t * 2.3
	local height = 2.8 - t * 1.9
	local segLength = 1.3
	local halfZ = segLength / 2

	local jointCFrame = prevCFrame * CFrame.new(0, 0, -(prevHalfZ + halfZ - SEG_OVERLAP))

	local segment = newBall(
		"Segment" .. i,
		Vector3.new(width, height, segLength * 1.6),
		jointCFrame,
		BASE_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)

	if i == 1 then
		body = segment
		body.Name = "Body"
	end

	-- Countershading: dunklere Rückenzeichnung, tief eingebettet
	newBall("SegmentShade" .. i, Vector3.new(width * 0.55, height * 0.4, segLength * 1.3), jointCFrame * CFrame.new(0, height * 0.28, 0), BASE_TOP, Enum.Material.SmoothPlastic, model)

	-- Kleine Kristallfacette (hartes Detail, bewusst spärlich: WedgePart)
	local facet = newWedge(
		"Facet" .. i,
		Vector3.new(width * 0.45, 0.55, segLength * 0.9),
		jointCFrame * CFrame.new(0, height / 2 + 0.02, 0) * CFrame.Angles(0, math.rad(90), 0),
		BASE_LIGHT,
		Enum.Material.Glass,
		model
	)
	facet.Transparency = 0.15

	-- Alternierende Neon-Naht (violett/cyan je Segment), als flacher,
	-- eingebetteter Ellipsoid-Streifen auf der Seitenfläche statt Block
	local seamColor = (i % 2 == 1) and SEAM_COLOR_A or SEAM_COLOR_B
	local seam = newBall(
		"Seam" .. i,
		Vector3.new(width * 0.16, height * 0.42, segLength * 1.4),
		jointCFrame * CFrame.new(width / 2 - 0.08, 0, 0),
		seamColor,
		Enum.Material.Neon,
		model
	)
	seam.Transparency = 0.05

	-- Kleiner kristalliner Flossen-Zacken entlang des Rückens (WedgePart)
	local spike = newWedge(
		"SpineSpike" .. i,
		Vector3.new(0.32, 0.8, segLength * 0.8),
		jointCFrame * CFrame.new(0, height / 2 + 0.4, 0) * CFrame.Angles(0, math.rad(90), math.rad(180)),
		seamColor,
		Enum.Material.Neon,
		model
	)

	segCenters[i] = jointCFrame
	segHeights[i] = height

	prevCFrame = jointCFrame
	prevHalfZ = halfZ
end

-- 2) Kopf-Details: übergroßer, ausdrucksstarker Kopf mit Kristallkrone,
--    sichtbaren Fangzähnen, großen Kulleraugen und Brust-Kernjuwel --------------------
local headCFrame = segCenters[1]

-- 2a) Kristallkrone auf dem Kopf (5 kleine, hart facettierte Zacken) -----------------
for i = 1, 5 do
	local x = -1.1 + (i - 1) * 0.55
	local crown = newWedge(
		"Crown" .. i,
		Vector3.new(0.24, 0.5 + (i == 3 and 0.25 or 0), 0.3),
		headCFrame * CFrame.new(x, 1.55, -0.2) * CFrame.Angles(0, 0, math.rad(6 * (i - 3))),
		(i % 2 == 1) and SEAM_COLOR_A or SEAM_COLOR_B,
		Enum.Material.Neon,
		model
	)
end

-- 2b) Fangzähne (kleine weiche Ellipsoide statt harter Keile) ------------------------
for i = 1, 4 do
	local x = -0.75 + (i - 1) * 0.5
	newBall("HeadTooth" .. i, Vector3.new(0.2, 0.4, 0.2), headCFrame * CFrame.new(x, -1.1, -0.55) * CFrame.Angles(math.rad(180), 0, 0), Color3.fromRGB(225, 225, 232), Enum.Material.SmoothPlastic, model)
end

-- 2c) Große, leuchtende Kulleraugen -------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, headCFrame * CFrame.new(side * 0.95, 0.35, -0.6), Vector3.new(0.55, 0.55, 0.32), SEAM_COLOR_B, model)
end

-- 2d) Leuchtendes Brust-Kernjuwel (Mythic-Flair), tief in den Hals eingebettet -----------
local coreGem = newBall("CoreGem", Vector3.new(0.85, 0.85, 0.6), headCFrame * CFrame.new(0, -0.6, 0.7), SEAM_COLOR_A, Enum.Material.Neon, model)
coreGem.Transparency = 0.05

-- 2e) Brustflossen-Paar am Kopfsegment (fächerartig, überlappende flache Ellipsen) -------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local finCFrame = headCFrame * CFrame.new(side * 1.65, -0.2, 0.4) * CFrame.Angles(0, 0, math.rad(side * -80))
	newBall("SideFin" .. i, Vector3.new(0.24, 1.0, 1.8), finCFrame, BASE_COLOR, Enum.Material.Glass, model).Transparency = 0.2
	newBall("SideFin" .. i .. "Tip", Vector3.new(0.16, 0.6, 1.0), finCFrame * CFrame.new(0, 0.75, 0), SEAM_COLOR_B, Enum.Material.Neon, model).Transparency = 0.35
end

-- 3) Große, dramatische Schwanzflossen-Fächer-Spitze (statt kleinem Keil) -----------------------------------
local tailCFrame = prevCFrame * CFrame.new(0, 0, -(prevHalfZ + 0.5 - SEG_OVERLAP))
for i = 1, 3 do
	local spread = math.rad(20 * (i - 2))
	newBall(
		"TailTip" .. (i == 2 and "" or i),
		Vector3.new(0.22, 1.3 - math.abs(i - 2) * 0.4, 1.0),
		tailCFrame * CFrame.Angles(0, spread, 0),
		(i == 2) and SEAM_COLOR_A or BASE_LIGHT,
		Enum.Material.Neon,
		model
	)
end

-- 4) Idle-Puls-Attachment ----------------------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Crystal Leviathan")

print("[Abyssara] CrystalLeviathan created under Workspace.Assets.Creatures")
