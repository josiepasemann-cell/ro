--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: AbyssalIsopod ("Abgrund-Assel")
	Rarity (Platzhalter): Rare
	Beschreibung:
		Segmentierter, cartoonhaft rundlicher, ovaler Körper aus 5 leicht
		versetzten, gewölbten Panzersegmenten (blass graviolett), mit 7
		kurzen, stummeligen Beinpaaren (Ellipsoide statt dünner Stäbe), 2
		kurzen Antennen-Ellipsen, großen Kulleraugen und einer leuchtenden,
		flach abgerundeten Unterseiten-Naht (Neon, cyan). Zone: HadalDepths.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (mittleres Hauptsegment) -> für
		  Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Einroll-/Ausroll-Animation (4s-Zyklus, Teile "Segment1"..
		  "Segment5" markieren die zu rotierenden Segmente).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-5, 6, 90) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Rare"
local ZONE = "HadalDepths"
local SEGMENT_COUNT = 5
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
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.55, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), pupilColor, Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("AbyssalIsopod")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "AbyssalIsopod"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(95, 84, 115)
local BODY_LIGHT = Color3.fromRGB(128, 116, 150)
local BODY_BELLY = Color3.fromRGB(150, 138, 170)
local SEAM_COLOR = Color3.fromRGB(120, 200, 255)

-- 1) 5 gestapelte, leicht überlappende, gewölbte, cartoonhaft dicke
--    Panzersegmente -----------------------------------------------------------------
local body
local segmentZ = { -1.55, -0.72, 0.1, 0.92, 1.65 }
local segmentWidth = { 2.15, 2.75, 2.95, 2.65, 2.05 }
local segmentHeight = { 1.3, 1.55, 1.6, 1.5, 1.2 }
for i = 1, SEGMENT_COUNT do
	local segment = newBall(
		"Segment" .. i,
		Vector3.new(segmentWidth[i], segmentHeight[i], 1.1),
		ORIGIN * CFrame.new(0, segmentHeight[i] * 0.15, segmentZ[i]),
		(i % 2 == 0) and BODY_LIGHT or BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	if i == 3 then
		body = segment
		body.Name = "Body"
	end
end

-- 1b) Hellere Bauchunterseite (Countershading) über die ganze Länge ---------------
newBall("Belly", Vector3.new(1.9, 0.5, 3.4), ORIGIN * CFrame.new(0, -0.55, 0), BODY_BELLY, Enum.Material.SmoothPlastic, model)

-- 2) 2 kurze Antennen-Ellipsen am Kopf-Segment --------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall(
		"Antenna" .. i,
		Vector3.new(0.14, 0.14, 0.6),
		ORIGIN * CFrame.new(side * 0.32, 0.28, -2.1) * CFrame.Angles(math.rad(-20 * side), 0, 0),
		BODY_LIGHT,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 3) Große Kulleraugen ----------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 0.55, 0.18, -1.95), Vector3.new(0.32, 0.32, 0.2), Color3.fromRGB(20, 15, 30), model)
end

-- 4) 7 kurze, stummelige Beinpaare unter den Segmenten (Ellipsoide statt Stäbe) -----------
local legZ = { -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5 }
for i = 1, 7 do
	for j = 1, 2 do
		local side = (j == 1) and 1 or -1
		local legCFrame = ORIGIN * CFrame.new(side * 1.2, -0.4, legZ[i]) * CFrame.Angles(0, 0, math.rad(side * -28))
		newBall("Leg" .. i .. "_" .. j, Vector3.new(0.18, 0.4, 0.22), legCFrame * CFrame.new(0, -0.16, 0), BODY_COLOR, Enum.Material.SmoothPlastic, model)
	end
end

-- 5) Leuchtende Unterseiten-Naht (flach abgerundeter, durchgehender Neon-Streifen) --------
local seam = newBall("UndersideSeam", Vector3.new(1.8, 0.2, 3.4), ORIGIN * CFrame.new(0, -0.68, 0), SEAM_COLOR, Enum.Material.Neon, model)
seam.Transparency = 0.05

-- 6) Idle-Puls-Attachment -----------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Abyssal Isopod")

print("[Abyssara] AbyssalIsopod created under Workspace.Assets.Creatures")
