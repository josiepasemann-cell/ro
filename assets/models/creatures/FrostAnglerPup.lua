--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: FrostAnglerPup ("Frost Angler Pup")
	Rarity (Platzhalter): Rare
	Event: FrozenCurrent
	Beschreibung:
		Kleine, rundlichere Jungtier-Version der Anglerfisch-Silhouette,
		blass eisblauer Körper, winziger leuchtender Köder-Spitze und
		Frost-Kristall-Akzenten (kleine weiße WedgeParts am Rücken).
		Event-exklusive Kreatur des "Frozen Current"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (schnelles Zittern 0.2s-Periode zwischen langsamen Hover-Drifts).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("FrozenCurrent"), analog "Zone"
		  bei Zonen-Kreaturen.
		- Part "LureOrb" + Attachment "MuzzlePoint" -> Köder-/Effektpunkt, analog
		  AnglerfishTower/Anglerfish-Konvention.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 6, 105)
local RARITY = "Rare"
local ZONE = "Global"
local EVENT = "FrozenCurrent"
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

local previous = creaturesFolder:FindFirstChild("FrostAnglerPup")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "FrostAnglerPup"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(180, 220, 240)
local LURE_COLOR = Color3.fromRGB(210, 245, 255)

-- 1) Rundlicher Körper -----------------------------------------------------------
local body = newPart("Body", Vector3.new(1.8, 1.5, 2.4), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Köderstab (gebogen) + leuchtende Spitze -------------------------------------
local stalkBase = ORIGIN * CFrame.new(0, 0.9, 1.0)
local stalk = newPart(
	"LureStalk",
	Vector3.new(0.12, 0.8, 0.12),
	stalkBase * CFrame.Angles(math.rad(-25), 0, 0),
	BODY_COLOR,
	Enum.Material.SmoothPlastic,
	model
)

local lureOrb = newPart(
	"LureOrb",
	Vector3.new(0.35, 0.35, 0.35),
	stalkBase * CFrame.Angles(math.rad(-25), 0, 0) * CFrame.new(0, 0.6, 0),
	LURE_COLOR,
	Enum.Material.Neon,
	model
)
lureOrb.Shape = Enum.PartType.Ball

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = lureOrb

-- 3) Frost-Kristall-Akzente (3 kleine weiße WedgeParts am Rücken) -----------------
for i = 1, 3 do
	local wedge = Instance.new("WedgePart")
	wedge.Name = "FrostCrystal" .. i
	wedge.Size = Vector3.new(0.25, 0.35, 0.25)
	wedge.CFrame = ORIGIN * CFrame.new(0, 0.75, 0.6 - i * 0.5) * CFrame.Angles(0, 0, math.rad(180))
	wedge.Color = Color3.fromRGB(240, 250, 255)
	wedge.Material = Enum.Material.Glass
	wedge.Anchored = true
	wedge.CanCollide = false
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = model
end

-- 4) Kleine Seitenflossen (Glass) ---------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = newPart(
		"Fin" .. i,
		Vector3.new(0.1, 0.6, 0.8),
		ORIGIN * CFrame.new(side * 0.95, 0, -0.3) * CFrame.Angles(0, 0, math.rad(side * 15)),
		Color3.fromRGB(200, 235, 250),
		Enum.Material.Glass,
		model
	)
	fin.Transparency = 0.4
end

-- 5) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Frost Angler Pup")

print("[Abyssara] FrostAnglerPup created under Workspace.Assets.Creatures")
