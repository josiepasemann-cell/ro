--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: BioluminescentEel ("Biolumineszenz-Aal")
	Rarity (Platzhalter): Epic
	Beschreibung:
		Langer, segmentierter, cartoonhaft rundlicher Aalkörper (Kette sich
		verjüngender, überlappender Zylinder-Segmente mit abgerundeten
		Ellipsen-Verbindungsstücken an jedem Gelenk, damit keine harten
		Zylinderkanten sichtbar sind) mit leuchtenden Streifen-Akzenten
		entlang des Rückens, einem übergroßen, runden Kopf mit großen
		leuchtenden Kulleraugen und kleinen Kiefer-/Rückenflossen-Details.
		Zone: TwilightZone.

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

local function newCartoonEye(name, cframe, eyeSize, pupilColor, parent)
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.55, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), pupilColor, Enum.Material.Neon, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
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

local SKIN_COLOR = Color3.fromRGB(35, 48, 65)
local SKIN_TOP = Color3.fromRGB(24, 34, 48)
local BELLY_COLOR = Color3.fromRGB(65, 82, 105)
local STRIPE_COLOR = Color3.fromRGB(90, 220, 255)

-- 1) Kopf (Body / PrimaryPart): übergroßer, runder Ellipsoid-Kopf ------------
local body = newBall("Body", Vector3.new(1.6, 1.35, 1.7), ORIGIN, SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Countershading: dunklere Kopfoberseite, helle Kehle -------------------
newBall("HeadTop", Vector3.new(1.1, 0.6, 1.2), ORIGIN * CFrame.new(0, 0.55, -0.1), SKIN_TOP, Enum.Material.SmoothPlastic, model)
newBall("Throat", Vector3.new(0.9, 0.55, 1.0), ORIGIN * CFrame.new(0, -0.45, 0.3), BELLY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Zwei große, leuchtende Kulleraugen --------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 0.48, 0.18, 0.75), Vector3.new(0.4, 0.4, 0.26), STRIPE_COLOR, model)
end

-- 2b) Kleine Kieferlinie (weiches Ellipsoid statt Kante) --------------------
newBall("Jaw", Vector3.new(0.65, 0.24, 0.55), ORIGIN * CFrame.new(0, -0.46, 0.6), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 3) Körpersegmente: sich verjüngend, überlappend und leicht schlängelnd, mit
--    kleinen abgerundeten Ellipsen-Gelenkstücken zwischen den Zylindern, damit
--    keine harten Zylinder-Endkappen sichtbar sind ---------------------------
local SEG_OVERLAP = 0.24
local prevCFrame = ORIGIN
local prevHalfLen = 0.85 -- halbe Kopf-Tiefe (Body.Size.Z / 2)

for i = 1, SEGMENT_COUNT do
	local t = i / SEGMENT_COUNT
	local segLength = 1.35
	local halfLen = segLength / 2
	local diameter = 1.15 - t * 0.85
	local waveAngle = math.rad(16 * math.sin(i * 0.9))

	local jointCFrame = prevCFrame * CFrame.Angles(0, waveAngle, 0) * CFrame.new(0, 0, -(prevHalfLen + halfLen - SEG_OVERLAP))

	-- Abgerundetes Gelenkstück (Ellipsoid) genau am Segment-Übergang, damit
	-- der Zylinder-Rand nicht als harte Kante sichtbar ist.
	newBall("SegmentJoint" .. i, Vector3.new(diameter * 1.02, diameter * 1.02, diameter * 0.5), jointCFrame * CFrame.new(0, 0, halfLen - SEG_OVERLAP * 0.5), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

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

	-- Leuchtstreifen-Akzent auf jedem Segment (schmaler, flacher Ellipsoid)
	local stripeCFrame = jointCFrame * CFrame.new(0, diameter / 2 - 0.06, 0)
	local stripe = newBall("GlowStripe" .. i, Vector3.new(diameter * 0.55, 0.16, segLength * 0.85), stripeCFrame, STRIPE_COLOR, Enum.Material.Neon, model)
	stripe.Transparency = 0.05

	-- Kleiner Rückenflossen-Zacken alle 2 Segmente (flache Ellipse) ----------
	if i % 2 == 0 then
		local finCFrame = jointCFrame * CFrame.new(0, diameter / 2 + 0.16, 0)
		newBall("DorsalFin" .. i, Vector3.new(diameter * 0.5, 0.38, segLength * 0.78), finCFrame, SKIN_COLOR, Enum.Material.SmoothPlastic, model)
	end

	prevCFrame = jointCFrame
	prevHalfLen = halfLen
end

-- Schwanzspitze (Ellipsoid statt harter Kugel-Kappe wirkt weicher)
local tailTipCFrame = prevCFrame * CFrame.new(0, 0, -(prevHalfLen + 0.14 - SEG_OVERLAP))
newBall("TailTip", Vector3.new(0.22, 0.22, 0.3), tailTipCFrame, STRIPE_COLOR, Enum.Material.Neon, model)

-- 4) Idle-Puls-Attachment -----------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Bioluminescent Eel")

print("[Abyssara] BioluminescentEel created under Workspace.Assets.Creatures")
