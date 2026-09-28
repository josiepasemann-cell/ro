--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: Anglerfish ("Anglerfisch")
	Rarity (Platzhalter): Rare
	Beschreibung:
		Kompakter, bulliger, cartoonhafter Fisch: übergroßer runder Kopf-Körper
		mit rundem, breitem Maul (Ober-/Unterkiefer als Ellipsoide statt
		spitzer Keile), kleinen weichen Zahn-Spitzen, stachliger Rückenflosse
		(überlappende flache Ellipsen), Bauch- und Brustflossen, gebogenem
		Schwanzstiel mit Schwanzflosse, großen Kulleraugen und der
		charakteristischen leuchtenden Angel-Rute (Illicium, Ellipsen-Kette)
		über dem Kopf. Zone: TwilightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/Schwebeanimation.
		- "LureOrb": Neon-Part an der Illicium-Spitze, für spätere Köder-VFX.
		- "TailFin" wird von IdleSway automatisch geschwenkt.
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-6, 5, 60) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Rare"
local ZONE = "TwilightZone"
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

local function newCartoonEye(name, cframe, eyeSize, parent)
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.55, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), Color3.fromRGB(30, 20, 40), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("Anglerfish")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "Anglerfish"
model.Parent = creaturesFolder

local SKIN_COLOR = Color3.fromRGB(60, 56, 72)
local SKIN_TOP = Color3.fromRGB(42, 38, 54)
local BELLY_COLOR = Color3.fromRGB(95, 88, 108)
local GLOW_COLOR = Color3.fromRGB(160, 90, 255)

-- 1) Hauptkörper: übergroßer, bulliger, runder Ellipsoid-Kopf-Körper ------------
local body = newBall("Body", Vector3.new(2.8, 2.4, 3.0), ORIGIN, SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Countershading: dunklerer Rücken, hellerer Bauch, gut eingebettet ---------
newBall("BackShade", Vector3.new(1.8, 1.1, 2.2), ORIGIN * CFrame.new(0, 0.9, -0.1), SKIN_TOP, Enum.Material.SmoothPlastic, model)
newBall("Belly", Vector3.new(1.9, 1.1, 2.5), ORIGIN * CFrame.new(0, -0.85, 0.1), BELLY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Großes, rundes Maul: Ober-/Unterkiefer als dicke, sich überlappende
--    Ellipsoide statt spitzer Keile ----------------------------------------------
local jaw = newBall("LowerJaw", Vector3.new(1.7, 0.85, 1.3), ORIGIN * CFrame.new(0, -0.7, 1.3) * CFrame.Angles(math.rad(14), 0, 0), SKIN_COLOR, Enum.Material.SmoothPlastic, model)
newBall("UpperJaw", Vector3.new(1.8, 0.7, 1.15), ORIGIN * CFrame.new(0, 0.15, 1.35) * CFrame.Angles(math.rad(-8), 0, 0), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 3) Kleine, weiche Zahn-Spitzen (Ober- und Unterkiefer) --------------------------
for i = 1, 5 do
	local x = -0.55 + (i - 1) * 0.28
	newBall("ToothLower" .. i, Vector3.new(0.11, 0.28, 0.11), ORIGIN * CFrame.new(x, -0.42, 1.75) * CFrame.Angles(math.rad(180), 0, 0), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic, model)
	newBall("ToothUpper" .. i, Vector3.new(0.09, 0.22, 0.09), ORIGIN * CFrame.new(x, 0.08, 1.78), Color3.fromRGB(240, 240, 245), Enum.Material.SmoothPlastic, model)
end

-- 4) Schwanzstiel + Schwanzflosse (überlappende, sich verjüngende Ellipsen) -------
newBall("TailPeduncle", Vector3.new(0.85, 1.0, 1.0), ORIGIN * CFrame.new(0, 0, -1.65), SKIN_COLOR, Enum.Material.SmoothPlastic, model)
newBall("TailFin", Vector3.new(0.2, 1.4, 1.15), ORIGIN * CFrame.new(0, 0, -2.55), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 5) Stachlige Rückenflosse (3 überlappende, flache Ellipsen) --------------------
for i = 1, 3 do
	local spikeCFrame = ORIGIN * CFrame.new(-0.55 + (i - 1) * 0.5, 1.25, 0.25 - (i - 1) * 0.4) * CFrame.Angles(math.rad(-18), 0, 0)
	newBall("DorsalSpike" .. i, Vector3.new(0.18, 0.6, 0.5), spikeCFrame, SKIN_COLOR, Enum.Material.SmoothPlastic, model)
end

-- 6) Bauch- und Brustflossen (flache, überlappende Ellipsen-Paare) --------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall(
		"SideFin" .. i,
		Vector3.new(0.18, 0.85, 1.05),
		ORIGIN * CFrame.new(side * 1.35, -0.3, 0.4) * CFrame.Angles(0, 0, math.rad(side * -78)),
		SKIN_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 7) Illicium (Angel-Rute) aus dem Kopf: Kette aus sich verjüngenden,
--    überlappenden Ellipsen mit leuchtendem Köder-Ball an der Spitze --------------
local rodCFrame = ORIGIN * CFrame.new(0, 0.85, 1.1) * CFrame.Angles(math.rad(-25), 0, 0)
local ROD_OVERLAP = 0.16

local half1 = 0.42 -- IlliciumBase Länge 0.84
local base1Y = half1 - ROD_OVERLAP
newBall("IlliciumBase", Vector3.new(0.2, half1 * 2, 0.2), rodCFrame * CFrame.new(0, base1Y, 0), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

local half2 = 0.38 -- IlliciumTipRod Länge 0.76
local base2Y = (base1Y + half1) - ROD_OVERLAP + half2
newBall("IlliciumTipRod", Vector3.new(0.14, half2 * 2, 0.14), rodCFrame * CFrame.new(0, base2Y, 0), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

local orbHalf = 0.36 -- LureOrb Durchmesser 0.72
local orbY = (base2Y + half2) - ROD_OVERLAP + orbHalf
newBall("LureOrb", Vector3.new(orbHalf * 2, orbHalf * 2, orbHalf * 2), rodCFrame * CFrame.new(0, orbY, 0), GLOW_COLOR, Enum.Material.Neon, model)

-- 8) Große Kulleraugen ---------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 0.85, 0.6, 1.25), Vector3.new(0.5, 0.5, 0.3), model)
end

-- 9) Idle-Puls-Attachment -----------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

-- The parts above were laid out facing +Z, but the game treats the body's
-- LookVector (-Z) as the front, so turn everything except the body half a
-- circle around it.
do
	local flip = body.CFrame * CFrame.Angles(0, math.pi, 0) * body.CFrame:Inverse()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= body then
			part.CFrame = flip * part.CFrame
		end
	end
end

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Anglerfish")

print("[Abyssara] Anglerfish created under Workspace.Assets.Creatures")
