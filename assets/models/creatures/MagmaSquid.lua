--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: MagmaSquid ("Magmakalmar")
	Rarity (Platzhalter): Epic
	Beschreibung:
		Bauchiger, dunkelroter Mantel mit 6 Tentakeln, die je eine dünne
		leuchtend-orange Ader-Linie (Neon) tragen, plus einem großen
		leuchtenden Auge. Zone: MidnightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Mantel) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-Animation (Mantel pulsiert 3s-Zyklus, Tentakel-Wellen
		  mit je 0,3s Versatz - Teile "Tentacle1".."Tentacle6" markieren die
		  zu animierenden Arme).
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
local TENTACLE_COUNT = 6
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

local previous = creaturesFolder:FindFirstChild("MagmaSquid")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MagmaSquid"
model.Parent = creaturesFolder

local MANTLE_COLOR = Color3.fromRGB(60, 15, 20)
local VEIN_COLOR = Color3.fromRGB(255, 100, 30)

-- 1) Mantel (bauchiger Körper) -----------------------------------------------------
local body = newPart("Body", Vector3.new(2.6, 2.6, 3.0), ORIGIN, MANTLE_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Großes leuchtendes Auge --------------------------------------------------------
local eye = newPart("Eye", Vector3.new(0.9, 0.9, 0.5), ORIGIN * CFrame.new(0, 0.3, -1.4), Color3.fromRGB(255, 200, 60), Enum.Material.Neon, model)
eye.Shape = Enum.PartType.Ball

-- 3) 6 Tentakel mit Neon-Ader-Linie --------------------------------------------------
for t = 1, TENTACLE_COUNT do
	local angle = math.rad(60 * (t - 1))
	local radius = 1.0
	local baseOffset = Vector3.new(math.cos(angle) * radius, -1.6, math.sin(angle) * radius + 0.4)
	local armCFrame = ORIGIN * CFrame.new(baseOffset) * CFrame.Angles(math.rad(-10), angle, 0)

	newPart(
		"Tentacle" .. t,
		Vector3.new(0.5, 2.6, 0.5),
		armCFrame * CFrame.new(0, -1.3, 0),
		MANTLE_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)

	newPart(
		"TentacleVein" .. t,
		Vector3.new(0.12, 2.4, 0.12),
		armCFrame * CFrame.new(0.15, -1.3, 0.15),
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
model:SetAttribute("CreatureName", "Magmakalmar")

print("[Abyssara] MagmaSquid erzeugt unter Workspace.Assets.Creatures")
