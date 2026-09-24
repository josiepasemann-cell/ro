--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: PhantomJelly ("Phantom Jelly")
	Rarity (Platzhalter): Epic
	Event: SpookyTide
	Beschreibung:
		Klassische Qualle-Glocke, aber vollständig transluzent (Glass,
		Transparency 0.6), blass blau-weißer innerer Glow (Neon-Kern) und 5
		dünne, zum Ende hin ausfadende Tentakelstränge. Event-exklusive
		Kreatur des "Spooky Tide"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Schwebe-
		  Animation (langsames Aufsteigen, Tentakel-Nachlauf, periodisches
		  Transparency-"Phasing" alle ~6s, siehe Doc).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("SpookyTide"), analog "Zone" bei
		  Zonen-Kreaturen.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-5, 8, 105)
local RARITY = "Epic"
local ZONE = "Global"
local EVENT = "SpookyTide"
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

local previous = creaturesFolder:FindFirstChild("PhantomJelly")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "PhantomJelly"
model.Parent = creaturesFolder

local GHOST_COLOR = Color3.fromRGB(210, 225, 255)
local GLOW_COLOR = Color3.fromRGB(190, 210, 255)

-- 1) Glocke (Körper, transluzent) --------------------------------------------------
local body = newPart("Body", Vector3.new(3, 2.4, 3), ORIGIN, GHOST_COLOR, Enum.Material.Glass, model)
body.Shape = Enum.PartType.Ball
body.Transparency = 0.6

-- 2) Innerer Glow-Kern ---------------------------------------------------------------
local core = newPart("GlowCore", Vector3.new(1.3, 1.0, 1.3), ORIGIN, GLOW_COLOR, Enum.Material.Neon, model)
core.Shape = Enum.PartType.Ball
core.Transparency = 0.1

-- 3) 5 ausfadende Tentakelstränge (je 3 Segmente, Transparency steigt zur Spitze) -----
for t = 1, 5 do
	local angle = math.rad(72 * (t - 1))
	local radius = 1.0
	local baseOffset = Vector3.new(math.cos(angle) * radius, -1.1, math.sin(angle) * radius)

	local currentCFrame = ORIGIN * CFrame.new(baseOffset)
	for seg = 1, 3 do
		local segLength = 1.4
		currentCFrame = currentCFrame * CFrame.new(0, -segLength / 2, 0)
		local strand = newPart(
			"Tentacle" .. t .. "_Segment" .. seg,
			Vector3.new(0.22, segLength, 0.22),
			currentCFrame,
			GHOST_COLOR,
			Enum.Material.Glass,
			model
		)
		strand.Transparency = 0.5 + (seg - 1) * 0.15
		currentCFrame = currentCFrame * CFrame.new(0, -segLength / 2, 0)
	end
end

-- 4) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Phantom Jelly")

print("[Abyssara] PhantomJelly created under Workspace.Assets.Creatures")
