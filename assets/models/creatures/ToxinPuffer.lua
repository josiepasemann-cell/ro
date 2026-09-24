--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: ToxinPuffer ("Toxin Puffer")
	Rarity (Platzhalter): Rare
	Event: ToxicTide
	Beschreibung:
		Runder, aufgeblasener Kugelfisch-Körper, sickly gelb-grün, mit kleinen
		nach außen zeigenden dunklen Stacheln (WedgeParts) und einer leuchtend
		grünen Bauchnaht (Neon). Event-exklusive Kreatur des "Toxic Tide"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-
		  ("Puffing"-Skalierung 1.0 -> 1.15 -> 1.0 auf 2.5s-Zyklus, siehe Doc).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("ToxicTide"), analog "Zone" bei
		  Zonen-Kreaturen.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-15, 6, 105)
local RARITY = "Rare"
local ZONE = "Global"
local EVENT = "ToxicTide"
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

local previous = creaturesFolder:FindFirstChild("ToxinPuffer")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ToxinPuffer"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(170, 210, 60)
local GLOW_COLOR = Color3.fromRGB(150, 255, 60)
local SPINE_COLOR = Color3.fromRGB(70, 90, 30)

-- 1) Aufgeblasener Kugelkörper -----------------------------------------------
local body = newPart("Body", Vector3.new(3, 3, 3), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Leuchtende Bauchnaht ------------------------------------------------------
local belly = newPart(
	"BellySeam",
	Vector3.new(2.4, 0.3, 2.4),
	ORIGIN * CFrame.new(0, -1.2, 0),
	GLOW_COLOR,
	Enum.Material.Neon,
	model
)
belly.Shape = Enum.PartType.Cylinder
belly.CFrame = belly.CFrame * CFrame.Angles(0, 0, math.rad(90))

-- 3) Zwei Augen -------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eye = newPart(
		"Eye" .. i,
		Vector3.new(0.35, 0.35, 0.35),
		ORIGIN * CFrame.new(side * 0.7, 0.4, 1.3),
		Color3.fromRGB(20, 20, 20),
		Enum.Material.SmoothPlastic,
		model
	)
	eye.Shape = Enum.PartType.Ball
end

-- 4) Stacheln (8 kleine WedgeParts radial verteilt) --------------------------------
for i = 1, 8 do
	local angle = math.rad(45 * (i - 1))
	local elevation = math.rad(20 * ((i % 3) - 1))
	local dir = CFrame.Angles(0, angle, 0) * CFrame.Angles(elevation, 0, 0)
	local offset = dir * CFrame.new(0, 0, 1.5)
	local spineCFrame = ORIGIN * offset * CFrame.Angles(math.rad(-90), 0, 0)

	local spine = Instance.new("WedgePart")
	spine.Name = "Spine" .. i
	spine.Size = Vector3.new(0.25, 0.6, 0.25)
	spine.CFrame = spineCFrame
	spine.Color = SPINE_COLOR
	spine.Material = Enum.Material.SmoothPlastic
	spine.Anchored = true
	spine.CanCollide = false
	spine.TopSurface = Enum.SurfaceType.Smooth
	spine.BottomSurface = Enum.SurfaceType.Smooth
	spine.Parent = model
end

-- 5) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Toxin Puffer")

print("[Abyssara] ToxinPuffer created under Workspace.Assets.Creatures")
