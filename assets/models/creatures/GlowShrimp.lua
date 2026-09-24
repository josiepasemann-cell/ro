--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GlowShrimp ("Leuchtgarnele")
	Rarity (Platzhalter): Common
	Beschreibung:
		Kleine, längliche Garnele mit segmentiertem Körper, Schwanzfächer,
		zwei dünnen Antennen und leuchtenden Punktmustern entlang des Rückens.
		Zone: SunZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (mittleres Körpersegment) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/Schwebeanimation.
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
local GLOW_COLOR = Color3.fromRGB(255, 150, 220)

-- 1) Körpersegmente (3 Stück, leicht gebogen wie eine Garnele) --------------
local body = newPart("Body", Vector3.new(1.2, 0.9, 0.9), ORIGIN, SHELL_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

local headCFrame = ORIGIN * CFrame.new(0.9, 0.15, 0) * CFrame.Angles(0, 0, math.rad(-8))
local head = newPart("HeadSegment", Vector3.new(0.9, 0.75, 0.75), headCFrame, SHELL_COLOR, Enum.Material.SmoothPlastic, model)
head.Shape = Enum.PartType.Ball

local tailCFrame = ORIGIN * CFrame.new(-0.95, -0.1, 0) * CFrame.Angles(0, 0, math.rad(12))
local tailSeg = newPart("TailSegment", Vector3.new(0.9, 0.7, 0.7), tailCFrame, SHELL_COLOR, Enum.Material.SmoothPlastic, model)
tailSeg.Shape = Enum.PartType.Ball

-- 2) Schwanzfächer -----------------------------------------------------------
local fanCFrame = ORIGIN * CFrame.new(-1.7, -0.25, 0) * CFrame.Angles(0, 0, math.rad(20))
local tailFan = newPart("TailFan", Vector3.new(0.15, 0.8, 1.1), fanCFrame, GLOW_COLOR, Enum.Material.Neon, model)

-- 3) Zwei dünne Antennen -------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local antennaCFrame = ORIGIN * CFrame.new(1.4, 0.5, side * 0.25) * CFrame.Angles(0, 0, math.rad(-35)) * CFrame.new(0, 0.9, 0)
	newPart("Antenna" .. i, Vector3.new(0.08, 1.8, 0.08), antennaCFrame, Color3.fromRGB(255, 220, 190), Enum.Material.SmoothPlastic, model)
end

-- 4) Leuchtpunkte entlang des Rückens -------------------------------------------
for i = 1, 3 do
	local dotCFrame = ORIGIN * CFrame.new(0.9 - i * 0.7, 0.5, 0)
	local dot = newPart("GlowSpot" .. i, Vector3.new(0.25, 0.25, 0.25), dotCFrame, GLOW_COLOR, Enum.Material.Neon, model)
	dot.Shape = Enum.PartType.Ball
end

-- 5) Idle-Puls-Attachment -------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Leuchtgarnele")

print("[Abyssara] GlowShrimp erzeugt unter Workspace.Assets.Creatures")
