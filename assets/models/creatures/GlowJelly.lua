--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GlowJelly ("Glühqualle")
	Rarity (Platzhalter): Common
	Beschreibung:
		Kleine, transluzente Qualle mit gewölbter Glocke (halbtransparentes
		Neon-Glas) und hängenden Tentakeln. Zone: SunZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (die Glocke) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-/Schwebe-Animation (Skalierung/Bobbing) durch den Code-Agenten.
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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("GlowJelly")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowJelly"
model.Parent = creaturesFolder

-- 1) Glocke (Körper) -------------------------------------------------------
local body = newPart("Body", Vector3.new(2.6, 1.8, 2.6), ORIGIN, Color3.fromRGB(150, 230, 255), Enum.Material.Glass, model)
body.Shape = Enum.PartType.Ball
body.Transparency = 0.25

-- 2) Innerer Glow-Kern -------------------------------------------------------
newPart(
	"GlowCore",
	Vector3.new(1.1, 0.8, 1.1),
	ORIGIN,
	Color3.fromRGB(90, 240, 255),
	Enum.Material.Neon,
	model
).Shape = Enum.PartType.Ball

-- 3) Tentakel (6 dünne, leicht unterschiedlich lange Stränge) ---------------
for i = 1, 6 do
	local angle = math.rad(60 * (i - 1))
	local radius = 0.9
	local length = 2.2 + (i % 2) * 0.6
	local offset = Vector3.new(math.cos(angle) * radius, -0.9 - length / 2, math.sin(angle) * radius)
	local tentacle = newPart(
		"Tentacle" .. i,
		Vector3.new(0.2, length, 0.2),
		ORIGIN * CFrame.new(offset),
		Color3.fromRGB(180, 240, 255),
		Enum.Material.Neon,
		model
	)
	tentacle.Transparency = 0.2
end

-- 4) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Glow Jelly")

print("[Abyssara] GlowJelly created under Workspace.Assets.Creatures")
