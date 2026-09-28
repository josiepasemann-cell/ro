--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GlowShrimp ("Leuchtgarnele")
	Rarity (Platzhalter): Common
	Beschreibung:
		Kleine, pummelige, cartoonhafte Garnele: übergroßer runder Kopf mit
		großen Kulleraugen, dicker Körper, 2 rundliche Schwanzsegmente,
		fächerartiger Schwanzflossen-Ellipsen-Büschel, kleine Rostrum-Spitze,
		2 geschwungene Antennen-Ketten, 4 kurze, stummelige Beinpaare und
		leuchtende Punktmuster entlang des Rückens. Rein organische Formen
		(Ellipsoide), keine Blockkanten. Zone: SunZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (mittleres Körpersegment) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/Schwebeanimation.
		- "TailFin"-Teil (Schwanzfächer) wird von IdleSway automatisch geschwenkt.
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(6, 5, 60) -- Vor Ausführung anpassen für gewünschte Position
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

-- Organischer Baustein für praktisch jeden Körperteil (siehe GlowJelly.lua).
local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function newCartoonEye(name, cframe, eyeSize, parent)
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.55, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), Color3.fromRGB(20, 15, 15), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("GlowShrimp")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowShrimp"
model.Parent = creaturesFolder

local SHELL_COLOR = Color3.fromRGB(255, 200, 150)
local SHELL_DARK = Color3.fromRGB(215, 150, 105)
local SHELL_BELLY = Color3.fromRGB(255, 228, 200)
local GLOW_COLOR = Color3.fromRGB(255, 150, 220)

-- 1) Körpersegmente: übergroßer, runder Kopf (cartoonhaft) + Körper + 2
--    Schwanzsegmente, alle großzügig überlappend. Leicht bumpiges Pebble-
--    Material für organische Panzeroberfläche. ------------------------------
local head = newBall("HeadSegment", Vector3.new(1.15, 1.05, 0.95), ORIGIN * CFrame.new(0.75, 0.15, 0) * CFrame.Angles(0, 0, math.rad(-6)), SHELL_COLOR, Enum.Material.Pebble, model)

local body = newBall("Body", Vector3.new(1.1, 0.9, 0.85), ORIGIN, SHELL_COLOR, Enum.Material.Pebble, model)

local tail1 = newBall("TailSegment1", Vector3.new(0.78, 0.68, 0.66), ORIGIN * CFrame.new(-0.72, -0.1, 0) * CFrame.Angles(0, 0, math.rad(10)), SHELL_COLOR, Enum.Material.Pebble, model)

local tail2 = newBall("TailSegment2", Vector3.new(0.55, 0.5, 0.48), ORIGIN * CFrame.new(-1.2, -0.26, 0) * CFrame.Angles(0, 0, math.rad(20)), SHELL_DARK, Enum.Material.Pebble, model)

-- 1b) Hellere Bauchunterseite (Countershading), deutlich eingebettet ---------
newBall("Belly", Vector3.new(1.5, 0.32, 0.62), ORIGIN * CFrame.new(-0.15, -0.4, 0), SHELL_BELLY, Enum.Material.SmoothPlastic, model)

-- 1c) Niedliches Cartoon-Gesicht am übergroßen Kopf ---------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(1.05, 0.4, side * 0.34), Vector3.new(0.4, 0.4, 0.24), model)
end

-- 2) Schwanzfächer: 3 überlappende, abgeflachte Ellipsen (statt Platte),
--    fächerförmig aufgestellt, tief in TailSegment2 eingebettet -------------
for i = 1, 3 do
	local spread = math.rad(20 * (i - 2))
	local fanCFrame = ORIGIN * CFrame.new(-1.55, -0.42, 0) * CFrame.Angles(0, spread, 0) * CFrame.Angles(0, 0, math.rad(26))
	local fanPart = newBall("TailFin" .. (i == 2 and "" or i), Vector3.new(0.16, 0.75, 0.95), fanCFrame, GLOW_COLOR, Enum.Material.Neon, model)
	fanPart.Transparency = 0.1
end

-- 3) Rostrum (kleine, stumpfe Nasenspitze) am Kopf ---------------------------
newBall("Rostrum", Vector3.new(0.45, 0.28, 0.26), ORIGIN * CFrame.new(1.35, 0.12, 0) * CFrame.Angles(0, 0, math.rad(-4)), SHELL_COLOR, Enum.Material.Pebble, model)

-- 4) Zwei geschwungene Antennen-Ketten (je 2 sich verjüngende Ellipsen) ------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local baseCFrame = ORIGIN * CFrame.new(1.1, 0.4, side * 0.28) * CFrame.Angles(0, 0, math.rad(-38))
	local seg1 = newBall("Antenna" .. i, Vector3.new(0.13, 0.85, 0.13), baseCFrame * CFrame.new(0, 0.4, 0), Color3.fromRGB(255, 220, 190), Enum.Material.SmoothPlastic, model)
	local seg2CFrame = baseCFrame * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(-16 * side))
	newBall("AntennaTip" .. i, Vector3.new(0.08, 0.9, 0.08), seg2CFrame * CFrame.new(0, 0.42, 0), Color3.fromRGB(255, 220, 190), Enum.Material.SmoothPlastic, model)
end

-- 5) 4 kurze, stummelige Beinpaare unter Körper/Schwanz (cartoony dick) ------
local legX = { 0.4, 0.0, -0.4, -0.8 }
for i = 1, 4 do
	for j = 1, 2 do
		local side = (j == 1) and 1 or -1
		local legCFrame = ORIGIN * CFrame.new(legX[i], -0.42, side * 0.3) * CFrame.Angles(0, 0, math.rad(side * -14))
		newBall("Leg" .. i .. "_" .. j, Vector3.new(0.16, 0.32, 0.16), legCFrame * CFrame.new(0, -0.16, 0), SHELL_DARK, Enum.Material.SmoothPlastic, model)
	end
end

-- 6) Leuchtpunkte entlang des Rückens (direkt auf der jeweiligen
--    Segment-Panzeroberfläche, Höhe pro Segment angepasst) -------------------
local dots = { { 0.75, 0.52 }, { 0.3, 0.4 }, { 0, 0.32 }, { -0.72, 0.14 }, { -1.2, -0.08 } }
for i, d in ipairs(dots) do
	newBall("GlowSpot" .. i, Vector3.new(0.2, 0.2, 0.2), ORIGIN * CFrame.new(d[1], d[2], 0), GLOW_COLOR, Enum.Material.Neon, model)
end

-- 7) Idle-Puls-Attachment -----------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

-- The parts above were laid out with the head toward +X, but the game treats
-- the body's LookVector (-Z) as the front, so turn everything except the body
-- a quarter circle around it.
do
	local turn = body.CFrame * CFrame.Angles(0, math.pi / 2, 0) * body.CFrame:Inverse()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= body then
			part.CFrame = turn * part.CFrame
		end
	end
end

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Glow Shrimp")

print("[Abyssara] GlowShrimp created under Workspace.Assets.Creatures")
