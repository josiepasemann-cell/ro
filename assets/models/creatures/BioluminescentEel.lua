--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: BioluminescentEel ("Biolumineszenz-Aal")
	Rarity (Platzhalter): Epic
	Beschreibung:
		Langer, segmentierter Aalkörper (Kette sich verjüngender, überlappender
		Zylinder-Segmente) mit leuchtenden Streifen-Akzenten entlang des
		Rückens, einem Kopf mit zwei Glow-Augen und kleinen Kiefer-/
		Rückenflossen-Details. Zone: TwilightZone.

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

local previous = creaturesFolder:FindFirstChild("BioluminescentEel")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "BioluminescentEel"
model.Parent = creaturesFolder

local SKIN_COLOR = Color3.fromRGB(30, 40, 55)
local BELLY_COLOR = Color3.fromRGB(55, 70, 90)
local STRIPE_COLOR = Color3.fromRGB(90, 220, 255)

-- 1) Kopf (Body / PrimaryPart) -------------------------------------------------
local body = newBall("Body", Vector3.new(1.3, 1.1, 1.5), ORIGIN, SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Helle Kehl-/Bauchzeichnung am Kopf, direkt eingebettet -------------------
newBall("Throat", Vector3.new(0.8, 0.5, 0.9), ORIGIN * CFrame.new(0, -0.4, 0.3), BELLY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Zwei Glow-Augen ---------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.4, 0.12, 0.65)
	newBall("Eye" .. i, Vector3.new(0.26, 0.26, 0.26), eyeCFrame, STRIPE_COLOR, Enum.Material.Neon, model)
end

-- 2b) Kleine Kieferlinie -----------------------------------------------------------
newPart("Jaw", Vector3.new(0.6, 0.18, 0.5), ORIGIN * CFrame.new(0, -0.42, 0.6), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 3) Körpersegmente: sich verjüngend, überlappend und leicht schlängelnd ----------
-- currentZ/currentCFrame verfolgt jeweils das Zentrum des ZULETZT gebauten
-- Segments (bzw. des Kopfes), so dass jedes neue Segment garantiert um
-- SEG_OVERLAP Studs in seinen Vorgänger einbettet, unabhängig vom lokalen
-- Schlängel-Winkel.
local SEG_OVERLAP = 0.22
local prevCFrame = ORIGIN
local prevHalfLen = 0.75 -- halbe Kopf-Tiefe (Body.Size.Z / 2)

for i = 1, SEGMENT_COUNT do
	local t = i / SEGMENT_COUNT
	local segLength = 1.35
	local halfLen = segLength / 2
	local diameter = 1.05 - t * 0.75
	local waveAngle = math.rad(16 * math.sin(i * 0.9))

	local jointCFrame = prevCFrame * CFrame.Angles(0, waveAngle, 0) * CFrame.new(0, 0, -(prevHalfLen + halfLen - SEG_OVERLAP))

	-- Cylinder-Shape: Roblox rendert die Länge IMMER entlang der lokalen
	-- X-Achse (Size.X = Länge, Size.Y/Z = Durchmesser) - deshalb Size.X =
	-- segLength, und die CFrame wird um 90° um Y gedreht, damit die
	-- (vorher lokale Z-) Kettenrichtung zur neuen lokalen X-Achse wird.
	local segPart = newPart(
		"BodySegment" .. i,
		Vector3.new(segLength, diameter, diameter),
		jointCFrame * CFrame.Angles(0, math.rad(90), 0),
		SKIN_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	segPart.Shape = Enum.PartType.Cylinder

	-- Leuchtstreifen-Akzent auf jedem Segment (durchgehend eingebettet)
	local stripeCFrame = jointCFrame * CFrame.new(0, diameter / 2 - 0.05, 0)
	newPart(
		"GlowStripe" .. i,
		Vector3.new(diameter * 0.5, 0.14, segLength * 0.75),
		stripeCFrame,
		STRIPE_COLOR,
		Enum.Material.Neon,
		model
	)

	-- Kleiner Rückenflossen-Zacken alle 2 Segmente
	if i % 2 == 0 then
		local finCFrame = jointCFrame * CFrame.new(0, diameter / 2 + 0.15, 0)
		local fin = Instance.new("WedgePart")
		fin.Name = "DorsalFin" .. i
		fin.Size = Vector3.new(diameter * 0.4, 0.35, segLength * 0.7)
		fin.CFrame = finCFrame
		fin.Color = SKIN_COLOR
		fin.Material = Enum.Material.SmoothPlastic
		fin.Anchored = true
		fin.CanCollide = false
		fin.Parent = model
	end

	prevCFrame = jointCFrame
	prevHalfLen = halfLen
end

-- Schwanzspitze
local tailTipCFrame = prevCFrame * CFrame.new(0, 0, -(prevHalfLen + 0.12 - SEG_OVERLAP))
newBall("TailTip", Vector3.new(0.25, 0.25, 0.25), tailTipCFrame, STRIPE_COLOR, Enum.Material.Neon, model)

-- 4) Idle-Puls-Attachment -----------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Bioluminescent Eel")

print("[Abyssara] BioluminescentEel created under Workspace.Assets.Creatures")
