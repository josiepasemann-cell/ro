--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: BioluminescentEel ("Biolumineszenz-Aal")
	Rarity (Platzhalter): Epic
	Beschreibung:
		Langer, segmentierter Aalkörper (Kette sich verjüngender Zylinder-
		Segmente) mit leuchtenden Streifen-Akzenten entlang des Rückens und
		einem Kopf mit zwei Glow-Augen. Zone: TwilightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Kopfsegment) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/
		  Schlängel-Animation.
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-14, 5, 60) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Epic"
local ZONE = "TwilightZone"
local SEGMENT_COUNT = 7
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

local previous = creaturesFolder:FindFirstChild("BioluminescentEel")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "BioluminescentEel"
model.Parent = creaturesFolder

local SKIN_COLOR = Color3.fromRGB(30, 40, 55)
local STRIPE_COLOR = Color3.fromRGB(90, 220, 255)

-- 1) Kopf (Body / PrimaryPart) -------------------------------------------------
local body = newPart("Body", Vector3.new(1.3, 1.1, 1.5), ORIGIN, SKIN_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Zwei Glow-Augen ---------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.4, 0.1, 0.65)
	local eye = newPart("Eye" .. i, Vector3.new(0.25, 0.25, 0.25), eyeCFrame, STRIPE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
end

-- 3) Körpersegmente, sich nach hinten verjüngend und leicht schlängelnd -----------
local currentCFrame = ORIGIN * CFrame.new(0, 0, -0.9)
for i = 1, SEGMENT_COUNT do
	local t = i / SEGMENT_COUNT
	local segLength = 1.4
	local diameter = 1.1 - t * 0.75
	local waveAngle = math.rad(18 * math.sin(i * 0.9))

	currentCFrame = currentCFrame * CFrame.Angles(0, waveAngle, 0) * CFrame.new(0, 0, -segLength / 2)

	local segPart = newPart(
		"BodySegment" .. i,
		Vector3.new(diameter, diameter, segLength),
		currentCFrame,
		SKIN_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	segPart.Shape = Enum.PartType.Cylinder
	segPart.CFrame = currentCFrame * CFrame.Angles(0, math.rad(90), 0)

	-- Leuchtstreifen-Akzent auf jedem zweiten Segment
	if i % 2 == 0 then
		local stripeCFrame = currentCFrame * CFrame.new(0, diameter / 2 + 0.05, 0)
		local stripe = newPart(
			"GlowStripe" .. i,
			Vector3.new(diameter * 0.5, 0.12, segLength * 0.6),
			stripeCFrame,
			STRIPE_COLOR,
			Enum.Material.Neon,
			model
		)
	end

	currentCFrame = currentCFrame * CFrame.new(0, 0, -segLength / 2)
end

-- 4) Idle-Puls-Attachment -----------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Biolumineszenz-Aal")

print("[Abyssara] BioluminescentEel erzeugt unter Workspace.Assets.Creatures")
