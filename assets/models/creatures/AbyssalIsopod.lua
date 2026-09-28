--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: AbyssalIsopod ("Abgrund-Assel")
	Rarity (Platzhalter): Rare
	Beschreibung:
		Segmentierter, ovaler Körper aus 5 leicht versetzten, gewölbten
		Panzersegmenten (blass graviolett), mit 7 Beinpaaren, 2 kurzen
		Antennen, 2 kleinen Augen und einer leuchtenden Unterseiten-Naht
		(Neon, cyan). Zone: HadalDepths.

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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("AbyssalIsopod")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "AbyssalIsopod"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(90, 80, 110)
local BODY_LIGHT = Color3.fromRGB(120, 110, 140)
local SEAM_COLOR = Color3.fromRGB(120, 200, 255)

-- 1) 5 gestapelte, leicht überlappende, gewölbte Panzersegmente -----------------------
local body
local segmentZ = { -1.6, -0.75, 0.1, 0.95, 1.7 }
local segmentWidth = { 2.1, 2.7, 2.9, 2.6, 2.0 }
local segmentHeight = { 1.2, 1.45, 1.5, 1.4, 1.1 }
for i = 1, SEGMENT_COUNT do
	local segment = newBall(
		"Segment" .. i,
		Vector3.new(segmentWidth[i], segmentHeight[i], 1.05),
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

-- 2) 2 kurze Antennen am Kopf-Segment --------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newPart(
		"Antenna" .. i,
		Vector3.new(0.08, 0.08, 0.65),
		ORIGIN * CFrame.new(side * 0.3, 0.25, -2.15) * CFrame.Angles(math.rad(-20 * side), 0, 0),
		BODY_LIGHT,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 3) 2 kleine Augen ----------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall("Eye" .. i, Vector3.new(0.18, 0.18, 0.18), ORIGIN * CFrame.new(side * 0.55, 0.15, -1.95), Color3.fromRGB(20, 15, 30), Enum.Material.SmoothPlastic, model)
end

-- 4) 7 Beinpaare unter den Segmenten -------------------------------------------------------
local legZ = { -1.5, -1.0, -0.5, 0, 0.5, 1.0, 1.5 }
for i = 1, 7 do
	for j = 1, 2 do
		local side = (j == 1) and 1 or -1
		local legCFrame = ORIGIN * CFrame.new(side * 1.15, -0.35, legZ[i]) * CFrame.Angles(0, 0, math.rad(side * -25))
		newPart("Leg" .. i .. "_" .. j, Vector3.new(0.1, 0.5, 0.14), legCFrame * CFrame.new(0, -0.22, 0), BODY_COLOR, Enum.Material.SmoothPlastic, model)
	end
end

-- 5) Leuchtende Unterseiten-Naht (durchgehender Neon-Streifen) ------------------------
newPart("UndersideSeam", Vector3.new(2.0, 0.18, 3.5), ORIGIN * CFrame.new(0, -0.62, 0), SEAM_COLOR, Enum.Material.Neon, model)

-- 6) Idle-Puls-Attachment -----------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Abyssal Isopod")

print("[Abyssara] AbyssalIsopod created under Workspace.Assets.Creatures")
