--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GlowShrimp ("Leuchtgarnele")
	Rarity (Platzhalter): Common
	Beschreibung:
		Kleine, längliche Garnele mit segmentiertem Körper (Kopf, Körper,
		2 Schwanzsegmente), Schwanzfächer, Rostrum-Spitze, 2 Antennen,
		4 Laufbeinpaaren und leuchtenden Punktmustern entlang des Rückens.
		Zone: SunZone.

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

-- Block-Part + SpecialMesh(Sphere)-Kind für Ellipsoide (siehe GlowJelly.lua).
local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
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
local SHELL_DARK = Color3.fromRGB(220, 160, 120)
local GLOW_COLOR = Color3.fromRGB(255, 150, 220)
local EYE_COLOR = Color3.fromRGB(20, 20, 25)

-- 1) Körpersegmente entlang der lokalen X-Achse (Kopf = +X, Schwanz = -X),
--    jeweils mit großzügiger Überlappung zum Nachbarsegment ---------------
local head = newBall("HeadSegment", Vector3.new(0.95, 0.85, 0.78), ORIGIN * CFrame.new(0.78, 0.1, 0) * CFrame.Angles(0, 0, math.rad(-6)), SHELL_COLOR, Enum.Material.SmoothPlastic, model)

local body = newBall("Body", Vector3.new(1.15, 0.95, 0.88), ORIGIN, SHELL_COLOR, Enum.Material.SmoothPlastic, model)

local tail1 = newBall("TailSegment1", Vector3.new(0.85, 0.75, 0.72), ORIGIN * CFrame.new(-0.78, -0.08, 0) * CFrame.Angles(0, 0, math.rad(8)), SHELL_COLOR, Enum.Material.SmoothPlastic, model)

local tail2 = newBall("TailSegment2", Vector3.new(0.62, 0.58, 0.55), ORIGIN * CFrame.new(-1.3, -0.22, 0) * CFrame.Angles(0, 0, math.rad(18)), SHELL_DARK, Enum.Material.SmoothPlastic, model)

-- 2) Schwanzfächer, deutlich in TailSegment2 eingebettet ---------------------
local fanCFrame = ORIGIN * CFrame.new(-1.7, -0.42, 0) * CFrame.Angles(0, 0, math.rad(26))
local tailFin = newPart("TailFin", Vector3.new(0.32, 0.85, 1.15), fanCFrame, GLOW_COLOR, Enum.Material.Neon, model)
tailFin.Transparency = 0.1

-- 3) Rostrum (spitzer Nasenstachel) am Kopf ----------------------------------
local rostrumCFrame = ORIGIN * CFrame.new(1.25, 0.15, 0) * CFrame.Angles(0, 0, math.rad(-4))
local rostrum = Instance.new("WedgePart")
rostrum.Name = "Rostrum"
rostrum.Size = Vector3.new(0.55, 0.22, 0.2)
rostrum.CFrame = rostrumCFrame * CFrame.Angles(0, math.rad(90), 0)
rostrum.Color = SHELL_COLOR
rostrum.Material = Enum.Material.SmoothPlastic
rostrum.Anchored = true
rostrum.CanCollide = false
rostrum.Parent = model

-- 4) Zwei dünne, geschwungene Antennen ---------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local baseCFrame = ORIGIN * CFrame.new(1.1, 0.35, side * 0.22) * CFrame.Angles(0, 0, math.rad(-38))
	newPart("Antenna" .. i, Vector3.new(0.07, 1.9, 0.07), baseCFrame * CFrame.new(0, 0.9, 0), Color3.fromRGB(255, 220, 190), Enum.Material.SmoothPlastic, model)
end

-- 5) Zwei kleine Stielaugen ---------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(1.0, 0.42, side * 0.32)
	local eye = newBall("Eye" .. i, Vector3.new(0.22, 0.22, 0.22), eyeCFrame, EYE_COLOR, Enum.Material.SmoothPlastic, model)
end

-- 6) 4 Laufbeinpaare unter Körper/Schwanz ------------------------------------
local legX = { 0.45, 0.05, -0.4, -0.85 }
for i = 1, 4 do
	for j = 1, 2 do
		local side = (j == 1) and 1 or -1
		local legCFrame = ORIGIN * CFrame.new(legX[i], -0.42, side * 0.32) * CFrame.Angles(0, 0, math.rad(side * -12))
		newPart("Leg" .. i .. "_" .. j, Vector3.new(0.08, 0.45, 0.08), legCFrame * CFrame.new(0, -0.2, 0), SHELL_DARK, Enum.Material.SmoothPlastic, model)
	end
end

-- 7) Leuchtpunkte entlang des Rückens (direkt auf der Panzeroberfläche) -----
local dotX = { 0.78, 0.3, -0.2, -0.7, -1.15 }
for i = 1, #dotX do
	local dotCFrame = ORIGIN * CFrame.new(dotX[i], 0.42, 0)
	newBall("GlowSpot" .. i, Vector3.new(0.22, 0.22, 0.22), dotCFrame, GLOW_COLOR, Enum.Material.Neon, model)
end

-- 8) Idle-Puls-Attachment -----------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Glow Shrimp")

print("[Abyssara] GlowShrimp created under Workspace.Assets.Creatures")
