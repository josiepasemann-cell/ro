--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GlowJelly ("Glühqualle")
	Rarity (Platzhalter): Common
	Beschreibung:
		Kleine, rundliche, cartoonhafte Qualle: bauchige, halbtransparente
		Glocke (Neon-Glas) mit niedlichen großen Augen und einem kleinen
		Lächeln, gekräuseltem Glockensaum aus überlappenden Ellipsen, kurzen
		pummeligen Mundarmen und mehreren dünnen, geschwungenen
		Ellipsen-Tentakel-Ketten. Rein organische Formen (keine Blöcke/Keile
		außer Textur-Trägern). Zone: SunZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (die Glocke) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-/Skalierungs-Animation durch den Code-Agenten.
		- Teile "Tentacle1".."Tentacle8" werden von IdleSway automatisch geschwenkt.
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 6, 60) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Common"
local ZONE = "SunZone"
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

-- Organischer Baustein: Block-Part + SpecialMesh(Sphere)-Kind, damit eine
-- nicht-uniforme Size zu einem Ellipsoid gestreckt wird (ein Part mit
-- Shape=Ball rendert IMMER als Kugel mit der KLEINSTEN Achse als
-- Durchmesser). Wird für praktisch jeden Körperteil verwendet - rundliche,
-- cartoonhafte Silhouette statt harter Blockkanten. ------------------------
local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Großes, niedliches Cartoon-Auge: weißer Ellipsoid + dunkle Pupille + kleiner
-- weißer Glanzpunkt, alle deutlich ineinander eingebettet. ------------------
local function newCartoonEye(name, cframe, eyeSize, parent)
	local white = newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	local pupil = newBall(
		name .. "Pupil",
		eyeSize * 0.55,
		cframe * CFrame.new(0, 0, -eyeSize.Z * 0.28),
		Color3.fromRGB(15, 15, 20),
		Enum.Material.SmoothPlastic,
		parent
	)
	newBall(
		name .. "Glint",
		eyeSize * 0.18,
		cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.18, -eyeSize.Z * 0.4),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.Neon,
		parent
	)
	return white
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("GlowJelly")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowJelly"
model.Parent = creaturesFolder

local BELL_COLOR = Color3.fromRGB(150, 230, 255)
local BELL_TOP = Color3.fromRGB(110, 200, 240)
local GLOW_COLOR = Color3.fromRGB(90, 240, 255)
local ARM_COLOR = Color3.fromRGB(200, 245, 255)

-- 1) Glocke: bauchiger, cartoonhaft übergroßer Ellipsoid-"Kopf" ---------------
local body = newBall("Body", Vector3.new(2.6, 2.1, 2.6), ORIGIN, BELL_COLOR, Enum.Material.Glass, model)
body.Transparency = 0.22

-- 1b) Countershading: dunklerer Scheitel oben, tief eingebettet --------------
newBall("BellCrown", Vector3.new(1.7, 1.0, 1.7), ORIGIN * CFrame.new(0, 0.65, 0), BELL_TOP, Enum.Material.Glass, model).Transparency = 0.28

-- 2) Innerer Glow-Kern --------------------------------------------------------
newBall("GlowCore", Vector3.new(1.2, 0.95, 1.2), ORIGIN * CFrame.new(0, -0.05, 0.1), GLOW_COLOR, Enum.Material.Neon, model)

-- 2b) Niedliches Cartoon-Gesicht: 2 große Augen + kleines Lächeln, vorne
--     tief in die Glocke eingebettet ------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 0.55, 0.15, -1.05), Vector3.new(0.42, 0.42, 0.24), model)
end
local smile = newBall("Smile", Vector3.new(0.55, 0.14, 0.2), ORIGIN * CFrame.new(0, -0.35, -1.15) * CFrame.Angles(0, 0, math.rad(180)), Color3.fromRGB(60, 40, 70), Enum.Material.SmoothPlastic, model)

-- 3) Gekräuselter Glockensaum: überlappende, abgeflachte Ellipsen statt Keile -
for i = 1, 8 do
	local angle = math.rad(45 * (i - 1))
	local radius = 1.15
	local frillCFrame = ORIGIN * CFrame.new(math.cos(angle) * radius, -0.85, math.sin(angle) * radius)
		* CFrame.Angles(0, -angle, 0)
		* CFrame.Angles(math.rad(35), 0, 0)
	local frill = newBall("Frill" .. i, Vector3.new(0.5, 0.62, 0.16), frillCFrame, (i % 2 == 0) and BELL_COLOR or ARM_COLOR, Enum.Material.Glass, model)
	frill.Transparency = 0.2
end

-- 4) 4 pummelige Mundarme (2 dicke, sich verjüngende Ellipsen-Segmente) ------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 45)
	local radius = 0.35
	local baseCFrame = ORIGIN * CFrame.new(math.cos(angle) * radius, -1.1, math.sin(angle) * radius) * CFrame.Angles(math.rad(6 * i), 0, 0)
	local arm1 = newBall("OralArm" .. i, Vector3.new(0.34, 0.62, 0.34), baseCFrame, ARM_COLOR, Enum.Material.Neon, model)
	arm1.Transparency = 0.15
	local arm2 = newBall("OralArm" .. i .. "Tip", Vector3.new(0.24, 0.55, 0.24), baseCFrame * CFrame.new(0, -0.5, 0), ARM_COLOR, Enum.Material.Neon, model)
	arm2.Transparency = 0.1
end

-- 5) 8 dünne, geschwungene Tentakel-Ketten (3 sich verjüngende Ellipsen je Arm) --
for i = 1, 8 do
	local angle = math.rad(45 * (i - 1))
	local radius = 1.0
	local baseOffset = Vector3.new(math.cos(angle) * radius, -0.75, math.sin(angle) * radius)
	local segCFrame = ORIGIN * CFrame.new(baseOffset)
	local diameters = { 0.26, 0.19, 0.13 }
	local lengths = { 0.7, 0.6, 0.55 }
	local curl = (i % 2 == 0) and 6 or -6
	for seg = 1, 3 do
		segCFrame = segCFrame * CFrame.Angles(math.rad(curl), 0, 0) * CFrame.new(0, -lengths[seg] * 0.42, 0)
		local segName = (seg == 1) and ("Tentacle" .. i) or (seg == 2 and ("Tentacle" .. i .. "Mid") or ("TentacleTip" .. i))
		local color = (seg == 3) and GLOW_COLOR or BELL_COLOR
		local part = newBall(segName, Vector3.new(diameters[seg], lengths[seg], diameters[seg]), segCFrame, color, Enum.Material.Neon, model)
		part.Transparency = 0.1
		segCFrame = segCFrame * CFrame.new(0, -lengths[seg] * 0.42, 0)
	end
end

-- 6) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Glow Jelly")

print("[Abyssara] GlowJelly created under Workspace.Assets.Creatures")
