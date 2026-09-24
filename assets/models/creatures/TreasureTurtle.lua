--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: TreasureTurtle ("Treasure Turtle")
	Rarity (Platzhalter): Epic
	Event: TreasureTide
	Beschreibung:
		Schildkröten-Silhouette mit einem Panzer aus einem CSG-Union
		"Schatztruhen-Deckel"-Muster (gold mit teal-farbenen Einlage-Streifen)
		und einem kleinen leuchtenden Schlüsselloch-Detail (Neon) in der
		Panzermitte. Event-exklusive Kreatur des "Treasure Tide"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (schweres, langsames Paddel-Schwanken; Beine rotieren ±15° alternierend;
		  Schlüsselloch blitzt alle ~5s kurz auf).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("TreasureTide"), analog "Zone"
		  bei Zonen-Kreaturen.
		- Parts "LegFrontLeft".."LegBackRight" -> Ansatzpunkte für die spätere
		  Paddel-Animation.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 5, 120)
local RARITY = "Epic"
local ZONE = "Global"
local EVENT = "TreasureTide"
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

local previous = creaturesFolder:FindFirstChild("TreasureTurtle")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TreasureTurtle"
model.Parent = creaturesFolder

local SHELL_GOLD = Color3.fromRGB(210, 170, 60)
local SHELL_TEAL = Color3.fromRGB(50, 140, 130)
local GLOW_COLOR = Color3.fromRGB(255, 220, 120)
local BODY_COLOR = Color3.fromRGB(70, 150, 90)

-- 1) Körper (Body = untere Panzer-/Körperbasis) --------------------------------------
local body = newPart("Body", Vector3.new(3.2, 1.4, 4.2), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Panzer: CSG-Union aus goldener Basis + teal-farbenen Einlage-Streifen -----------
do
	local shellBase = Instance.new("Part")
	shellBase.Name = "ShellBase"
	shellBase.Size = Vector3.new(3.4, 1.6, 4.4)
	shellBase.CFrame = ORIGIN * CFrame.new(0, 0.9, 0)
	shellBase.Color = SHELL_GOLD
	shellBase.Material = Enum.Material.SmoothPlastic
	shellBase.Shape = Enum.PartType.Ball
	shellBase.Anchored = true
	shellBase.Parent = Workspace

	local stripeParts = {}
	for i = 1, 3 do
		local zOffset = -1.2 + (i - 1) * 1.2
		local stripe = Instance.new("Part")
		stripe.Name = "ShellStripe" .. i
		stripe.Size = Vector3.new(3.6, 0.5, 0.5)
		stripe.CFrame = ORIGIN * CFrame.new(0, 1.5, zOffset)
		stripe.Color = SHELL_TEAL
		stripe.Material = Enum.Material.SmoothPlastic
		stripe.Anchored = true
		stripe.Parent = Workspace
		table.insert(stripeParts, stripe)
	end

	local shellUnion = shellBase:UnionAsync(stripeParts)
	shellUnion.Name = "Shell"
	shellUnion.Color = SHELL_GOLD
	shellUnion.Material = Enum.Material.SmoothPlastic
	shellUnion.Anchored = true
	shellUnion.CanCollide = false
	shellUnion.Parent = model

	shellBase:Destroy()
	for _, stripe in ipairs(stripeParts) do
		stripe:Destroy()
	end
end

-- 3) Leuchtendes Schlüsselloch-Detail (Panzermitte) ----------------------------------
local keyhole = newPart(
	"KeyholeDetail",
	Vector3.new(0.35, 0.1, 0.5),
	ORIGIN * CFrame.new(0, 1.75, 0),
	GLOW_COLOR,
	Enum.Material.Neon,
	model
)

-- 4) Kopf --------------------------------------------------------------------------------
local head = newPart(
	"Head",
	Vector3.new(0.9, 0.9, 0.9),
	ORIGIN * CFrame.new(0, 0.2, 2.2),
	BODY_COLOR,
	Enum.Material.SmoothPlastic,
	model
)
head.Shape = Enum.PartType.Ball

-- 5) Vier Beine (paddelförmig, Ansatzpunkte für spätere Animation) -------------------
local legPositions = {
	{ "LegFrontLeft", 1.4, 1.2 },
	{ "LegFrontRight", -1.4, 1.2 },
	{ "LegBackLeft", 1.4, -1.4 },
	{ "LegBackRight", -1.4, -1.4 },
}
for _, legData in ipairs(legPositions) do
	local legName, xOff, zOff = legData[1], legData[2], legData[3]
	local leg = Instance.new("WedgePart")
	leg.Name = legName
	leg.Size = Vector3.new(0.6, 0.3, 1.0)
	leg.CFrame = ORIGIN * CFrame.new(xOff, -0.3, zOff)
	leg.Color = BODY_COLOR
	leg.Material = Enum.Material.SmoothPlastic
	leg.Anchored = true
	leg.CanCollide = false
	leg.TopSurface = Enum.SurfaceType.Smooth
	leg.BottomSurface = Enum.SurfaceType.Smooth
	leg.Parent = model
end

-- 6) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Treasure Turtle")

print("[Abyssara] TreasureTurtle created under Workspace.Assets.Creatures")
