--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: CrystalLeviathan ("Kristall-Leviathan")
	Rarity (Platzhalter): Mythic
	Beschreibung:
		Die Signatur-Kreatur der Hadal-Tiefe und das erste Mythic-Kreatur-
		Asset des Spiels. Langgestreckter, aalartiger Körper aus eckigen,
		facettierten "Kristall"-Segmenten (Mix aus Part/WedgePart),
		tiefviolett-schwarze Basis mit hell leuchtenden Multi-Neon-Nähten
		(abwechselnd violett/cyan je Segment) und kleinen kristallinen
		Flossen-Zacken entlang des Rückens. Größtes Kreatur-Modell im Spiel.
		Zone: HadalDepths.

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
local SEAM_COLOR_A = Color3.fromRGB(190, 80, 255)
local SEAM_COLOR_B = Color3.fromRGB(90, 220, 255)

-- 1) Langgestreckter Körper aus 8 sich verjüngenden, eckigen Segmenten ------------------
local body
local segmentLength = 10 / SEGMENT_COUNT
for i = 1, SEGMENT_COUNT do
	local t = (i - 1) / (SEGMENT_COUNT - 1) -- 0 (Kopf) .. 1 (Schwanz)
	local width = 3.0 - t * 2.0 -- verjüngt sich zum Schwanz
	local height = 2.6 - t * 1.7
	local zPos = -4.5 + (i - 0.5) * segmentLength

	local segment = newPart(
		"Segment" .. i,
		Vector3.new(width, height, segmentLength * 1.05),
		ORIGIN * CFrame.new(0, 0, zPos),
		BASE_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)

	if i == 1 then
		body = segment
		body.Name = "Body"
	end

	-- Facettierter Kristall-Akzent (WedgePart oben auf jedem Segment)
	local facet = Instance.new("WedgePart")
	facet.Name = "Facet" .. i
	facet.Size = Vector3.new(width * 0.6, 0.7, segmentLength * 0.9)
	facet.CFrame = ORIGIN * CFrame.new(0, height / 2 + 0.3, zPos) * CFrame.Angles(0, math.rad(90), 0)
	facet.Color = BASE_COLOR
	facet.Material = Enum.Material.Glass
	facet.Transparency = 0.15
	facet.Anchored = true
	facet.CanCollide = false
	facet.Parent = model

	-- Alternierende Neon-Naht (violett/cyan je Segment)
	local seamColor = (i % 2 == 1) and SEAM_COLOR_A or SEAM_COLOR_B
	newPart(
		"Seam" .. i,
		Vector3.new(width * 0.15, height * 0.15, segmentLength * 0.9),
		ORIGIN * CFrame.new(width / 2 + 0.05, 0, zPos),
		seamColor,
		Enum.Material.Neon,
		model
	)

	-- Kleiner kristalliner Flossen-Zacken entlang des Rückens
	local spike = Instance.new("WedgePart")
	spike.Name = "SpineSpike" .. i
	spike.Size = Vector3.new(0.3, 0.7, segmentLength * 0.6)
	spike.CFrame = ORIGIN * CFrame.new(0, height / 2 + 0.7, zPos) * CFrame.Angles(0, math.rad(90), math.rad(180))
	spike.Color = seamColor
	spike.Material = Enum.Material.Neon
	spike.Anchored = true
	spike.CanCollide = false
	spike.Parent = model
end

-- 2) Kopf-Details: 2 leuchtende Augen -----------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eye = newPart(
		"Eye" .. i,
		Vector3.new(0.35, 0.35, 0.35),
		ORIGIN * CFrame.new(side * 0.9, 0.3, -4.6),
		SEAM_COLOR_B,
		Enum.Material.Neon,
		model
	)
	eye.Shape = Enum.PartType.Ball
end

-- 3) Schwanz-Kristallspitze -----------------------------------------------------------------------
local tailTip = Instance.new("WedgePart")
tailTip.Name = "TailTip"
tailTip.Size = Vector3.new(0.4, 0.4, 0.8)
tailTip.CFrame = ORIGIN * CFrame.new(0, 0, 5.0) * CFrame.Angles(0, math.rad(90), 0)
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
