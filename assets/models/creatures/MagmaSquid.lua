--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: MagmaSquid ("Magmakalmar")
	Rarity (Platzhalter): Epic
	Beschreibung:
		Bauchiger, dunkelroter Ellipsoid-Mantel mit Fin-Flossen an den
		Seiten, 8 Tentakeln (2 Segmente je Arm, mit dünner leuchtend-oranger
		Ader-Linie), 2 kürzeren Greifarmen und einem großen leuchtenden Auge.
		Zone: MidnightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Mantel) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-Animation (Mantel pulsiert 3s-Zyklus, Tentakel-Wellen
		  mit je 0,3s Versatz - Teile "Tentacle1".."Tentacle8" markieren die
		  zu animierenden Arme, IdleSway schwenkt sie automatisch).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(5, 8, 75) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Epic"
local ZONE = "MidnightZone"
local TENTACLE_COUNT = 8
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

local previous = creaturesFolder:FindFirstChild("MagmaSquid")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MagmaSquid"
model.Parent = creaturesFolder

local MANTLE_COLOR = Color3.fromRGB(60, 15, 20)
local MANTLE_LIGHT = Color3.fromRGB(95, 30, 30)
local VEIN_COLOR = Color3.fromRGB(255, 100, 30)

-- 1) Mantel (bauchiger Körper, Ellipsoid) -----------------------------------------
local body = newBall("Body", Vector3.new(2.6, 2.7, 3.0), ORIGIN, MANTLE_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Helle Mantelspitze oben, gut eingebettet ------------------------------------
newBall("MantleTip", Vector3.new(1.1, 1.2, 1.3), ORIGIN * CFrame.new(0, 1.3, -0.2), MANTLE_LIGHT, Enum.Material.SmoothPlastic, model)

-- 1c) Zwei seitliche Flossen (Fin-Präfix, IdleSway) -------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = Instance.new("WedgePart")
	fin.Name = "Wing" .. i
	fin.Size = Vector3.new(1.1, 0.18, 1.3)
	fin.CFrame = ORIGIN * CFrame.new(side * 1.35, 0.4, -0.3) * CFrame.Angles(0, 0, math.rad(side * -90))
	fin.Color = MANTLE_LIGHT
	fin.Material = Enum.Material.SmoothPlastic
	fin.Anchored = true
	fin.CanCollide = false
	fin.Parent = model
end

-- 2) Großes leuchtendes Auge --------------------------------------------------------
newBall("Eye", Vector3.new(0.9, 0.9, 0.5), ORIGIN * CFrame.new(0, 0.3, -1.45), Color3.fromRGB(255, 200, 60), Enum.Material.Neon, model)
newBall("Pupil", Vector3.new(0.35, 0.35, 0.2), ORIGIN * CFrame.new(0, 0.3, -1.65), Color3.fromRGB(20, 10, 5), Enum.Material.SmoothPlastic, model)

-- 3) 8 Tentakel mit Neon-Ader-Linie (2 Segmente je Arm, überlappend) ----------------
local SEG_OVERLAP = 0.22
for t = 1, TENTACLE_COUNT do
	local angle = math.rad(45 * (t - 1))
	local radius = 0.85
	local baseOffset = Vector3.new(math.cos(angle) * radius, -1.3, math.sin(angle) * radius + 0.5)
	local armCFrame = ORIGIN * CFrame.new(baseOffset) * CFrame.Angles(math.rad(-8), angle, 0)

	local seg1Len = 1.5
	local seg2Len = 1.15
	local half1 = seg1Len / 2
	local half2 = seg2Len / 2

	local seg1CFrame = armCFrame * CFrame.new(0, -(0.1 + half1 - SEG_OVERLAP), 0)
	newPart("Tentacle" .. t, Vector3.new(0.5, seg1Len, 0.5), seg1CFrame, MANTLE_COLOR, Enum.Material.SmoothPlastic, model)
	newPart(
		"TentacleVein" .. t,
		Vector3.new(0.13, seg1Len * 0.9, 0.13),
		seg1CFrame * CFrame.new(0.16, 0, 0.16),
		VEIN_COLOR,
		Enum.Material.Neon,
		model
	)

	local seg2CFrame = seg1CFrame * CFrame.Angles(math.rad(10), 0, 0) * CFrame.new(0, -(half1 + half2 - SEG_OVERLAP), 0)
	newPart("Tentacle" .. t .. "Tip", Vector3.new(0.32, seg2Len, 0.32), seg2CFrame, MANTLE_COLOR, Enum.Material.SmoothPlastic, model)
	newPart(
		"TentacleVein" .. t .. "Tip",
		Vector3.new(0.1, seg2Len * 0.85, 0.1),
		seg2CFrame * CFrame.new(0.1, 0, 0.1),
		VEIN_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 4) Idle-Puls-Attachment -----------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Magma Squid")

print("[Abyssara] MagmaSquid created under Workspace.Assets.Creatures")
