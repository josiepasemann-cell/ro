--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: EmberSlug ("Ember Slug")
	Rarity (Platzhalter): Uncommon
	Event: VolcanicVent
	Beschreibung:
		Gedrungener Meeresschnecken-Körper, dunkles Anthrazit, mit leuchtend
		orangefarbener Rückenrippe (Neon). Event-exklusive Kreatur des
		"Volcanic Vent"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (Glow wandert Schwanz->Kopf auf 3s-Zyklus entlang der Rippen-Segmente,
		  ansonsten stationär).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("VolcanicVent"), analog "Zone"
		  bei Zonen-Kreaturen.
		- Parts "RidgeSegment1".."RidgeSegment4" -> Ansatzpunkte für die spätere
		  Lauflicht-Animation entlang der Rückenrippe.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-15, 5, 120)
local RARITY = "Uncommon"
local ZONE = "Global"
local EVENT = "VolcanicVent"
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

local previous = creaturesFolder:FindFirstChild("EmberSlug")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "EmberSlug"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(40, 30, 30)
local GLOW_COLOR = Color3.fromRGB(255, 130, 30)

-- 1) Gedrungener Körper -------------------------------------------------------------
local body = newPart("Body", Vector3.new(2.5, 1.5, 3.5), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Glühende Rückenrippe (4 Segmente, Schwanz -> Kopf) ------------------------------
for i = 1, 4 do
	local zOffset = 1.3 - (i - 1) * 0.85
	local ridge = newPart(
		"RidgeSegment" .. i,
		Vector3.new(0.4, 0.4, 0.7),
		ORIGIN * CFrame.new(0, 0.85, zOffset),
		GLOW_COLOR,
		Enum.Material.Neon,
		model
	)
	ridge.Shape = Enum.PartType.Ball
end

-- 3) Zwei Fühler (klein, am Kopf) ---------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newPart(
		"Antenna" .. i,
		Vector3.new(0.12, 0.5, 0.12),
		ORIGIN * CFrame.new(side * 0.35, 0.9, 1.6) * CFrame.Angles(math.rad(-15), 0, 0),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 4) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Ember Slug")

print("[Abyssara] EmberSlug erzeugt unter Workspace.Assets.Creatures")
