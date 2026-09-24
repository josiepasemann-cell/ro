--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: Anglerfish ("Anglerfisch")
	Rarity (Platzhalter): Rare
	Beschreibung:
		Kompakter, bulliger Fisch mit großem Maul (kleine Zahn-Wedges), stachliger
		Rückenflosse und der charakteristischen leuchtenden Angel-Rute (Illicium)
		über dem Kopf. Zone: TwilightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/Schwebeanimation.
		- "LureOrb": Neon-Part an der Illicium-Spitze, für spätere Köder-VFX.
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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("Anglerfish")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "Anglerfish"
model.Parent = creaturesFolder

local SKIN_COLOR = Color3.fromRGB(45, 42, 55)
local GLOW_COLOR = Color3.fromRGB(160, 90, 255)

-- 1) Hauptkörper (bullig, abgeflacht) -----------------------------------------
local body = newPart("Body", Vector3.new(2.6, 2.2, 3.2), ORIGIN, SKIN_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Großes Maul (Unterkiefer als Wedge) ---------------------------------------
local jawCFrame = ORIGIN * CFrame.new(0, -0.9, 1.6) * CFrame.Angles(math.rad(20), 0, 0)
local jaw = Instance.new("WedgePart")
jaw.Name = "LowerJaw"
jaw.Size = Vector3.new(1.6, 0.9, 1.3)
jaw.CFrame = jawCFrame
jaw.Color = SKIN_COLOR
jaw.Material = Enum.Material.SmoothPlastic
jaw.Anchored = true
jaw.CanCollide = false
jaw.Parent = model

-- 3) Zähne (kleine weiße Spikes) -----------------------------------------------
for i = 1, 5 do
	local x = -0.6 + (i - 1) * 0.3
	local toothCFrame = ORIGIN * CFrame.new(x, -0.5, 1.7) * CFrame.Angles(math.rad(180), 0, 0)
	newPart("Tooth" .. i, Vector3.new(0.12, 0.35, 0.12), toothCFrame, Color3.fromRGB(235, 235, 240), Enum.Material.SmoothPlastic, model)
end

-- 4) Schwanzflosse ---------------------------------------------------------------
local tailCFrame = ORIGIN * CFrame.new(0, 0, -1.9)
local tailFin = newPart("TailFin", Vector3.new(0.25, 1.6, 1.4), tailCFrame, SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 5) Stachlige Rückenflosse (3 kleine Spikes) ------------------------------------
for i = 1, 3 do
	local spikeCFrame = ORIGIN * CFrame.new(-0.6 + (i - 1) * 0.5, 1.3, 0.3 - (i - 1) * 0.4) * CFrame.Angles(math.rad(-90), 0, 0)
	local spike = Instance.new("WedgePart")
	spike.Name = "DorsalSpike" .. i
	spike.Size = Vector3.new(0.15, 0.5, 0.5)
	spike.CFrame = spikeCFrame
	spike.Color = SKIN_COLOR
	spike.Material = Enum.Material.SmoothPlastic
	spike.Anchored = true
	spike.CanCollide = false
	spike.Parent = model
end

-- 6) Illicium (Angel-Rute) aus dem Kopf, gebogen, mit Leucht-Köder --------------
local rodCFrame = ORIGIN * CFrame.new(0, 1.2, 1.2)
local rodSeg1 = newPart("IlliciumBase", Vector3.new(0.2, 1.2, 0.2), rodCFrame * CFrame.new(0, 0.6, 0), SKIN_COLOR, Enum.Material.SmoothPlastic, model)
local rodTipCFrame = rodCFrame * CFrame.new(0, 1.3, 0.4) * CFrame.Angles(math.rad(-15), 0, 0)
local rodSeg2 = newPart("IlliciumTipRod", Vector3.new(0.15, 0.9, 0.15), rodTipCFrame, SKIN_COLOR, Enum.Material.SmoothPlastic, model)

local lureOrb = newPart(
	"LureOrb",
	Vector3.new(0.7, 0.7, 0.7),
	rodTipCFrame * CFrame.new(0, 0.55, 0),
	GLOW_COLOR,
	Enum.Material.Neon,
	model
)
lureOrb.Shape = Enum.PartType.Ball

-- 7) Idle-Puls-Attachment ---------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Anglerfisch")

print("[Abyssara] Anglerfish erzeugt unter Workspace.Assets.Creatures")
