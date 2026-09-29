--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: ToxinPuffer ("Toxin Puffer")
	Rarity (Platzhalter): Rare
	Event: ToxicTide
	Beschreibung (Update: organisch/cartoony, siehe Kommentar unten):
		Rundlicher, aufgeblasener Kugelfisch, sickly gelb-grün mit dunkelolivenen
		Gift-Flecken (Ellipsoid-Muster) und heller Bauch-Gegenschattierung.
		Große, übertrieben runde Cartoon-Augen, winziges Lächel-Maul, kurze
		stachelige Ellipsoid-"Noppen" statt spitzer Wedges. Material Pebble
		für eine leicht raue, warzige Haut. Event-exklusive Kreatur des
		"Toxic Tide"-Events.

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

-- Block-Part + SpecialMesh(Sphere): echtes Ellipsoid statt der immer
-- kugelrunden Shape=Ball-Darstellung - Basis für JEDE organische Form hier
-- (Körper, Noppen, Flecken).
local function newMeshBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
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

local BODY_COLOR = Color3.fromRGB(175, 215, 65)
local BELLY_COLOR = Color3.fromRGB(225, 240, 165)
local GLOW_COLOR = Color3.fromRGB(150, 255, 60)
local SPINE_COLOR = Color3.fromRGB(75, 95, 35)
local BLOTCH_COLOR = Color3.fromRGB(100, 125, 40)

-- 1) Aufgeblasener, leicht ellipsoider Kugelkörper (chunky, Pebble-Haut) -----------
local body = newMeshBall("Body", Vector3.new(3.4, 3.1, 3.4), ORIGIN, BODY_COLOR, Enum.Material.Pebble, model)

-- 1b) Helle Bauch-Gegenschattierung, flach angedrückt, überlappt den Körper --------
newMeshBall("BellyPatch", Vector3.new(2.6, 1.5, 2.6), ORIGIN * CFrame.new(0, -1.1, 0.05), BELLY_COLOR, Enum.Material.Pebble, model)

-- 1c) Vier große Gift-Flecken (Geometrie-Muster statt flacher Textur), auf den
--     Rücken gesetzt, in den Körper eingesenkt -----------------------------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 45)
	local dir = CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(28), 0, 0)
	local pos = dir * CFrame.new(0, 0, 1.55)
	newMeshBall("ToxicBlotch" .. i, Vector3.new(0.75, 0.3, 0.65), ORIGIN * pos * CFrame.Angles(0, angle, 0), BLOTCH_COLOR, Enum.Material.Pebble, model)
end

-- 2) Leuchtende Bauchnaht ------------------------------------------------------
local belly = newPart("BellySeam", Vector3.new(0.3, 2.6, 2.6), ORIGIN * CFrame.new(0, -1.3, 0), GLOW_COLOR, Enum.Material.Neon, model)
belly.Shape = Enum.PartType.Cylinder
belly.CFrame = belly.CFrame * CFrame.Angles(0, 0, math.rad(90))

-- 3) Große Cartoon-Augen: übergroße weiße Ellipsoide + dunkle Pupille + Glanzpunkt --
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.62, 0.3, 1.5)
	newMeshBall("EyeWhite" .. i, Vector3.new(0.62, 0.62, 0.5), eyeCFrame, Color3.fromRGB(250, 252, 245), Enum.Material.SmoothPlastic, model)
	newMeshBall("Eye" .. i, Vector3.new(0.36, 0.36, 0.3), eyeCFrame * CFrame.new(0, -0.02, 0.22), Color3.fromRGB(25, 20, 20), Enum.Material.SmoothPlastic, model)
	newMeshBall("EyeHighlight" .. i, Vector3.new(0.13, 0.13, 0.1), eyeCFrame * CFrame.new(0.1, 0.1, 0.35), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	-- Blush-Fleck unter dem Auge, überlappt Körper + Auge -> niedliches Cartoon-Detail
	newMeshBall("Blush" .. i, Vector3.new(0.35, 0.2, 0.22), eyeCFrame * CFrame.new(0, -0.42, -0.05), Color3.fromRGB(255, 160, 150), Enum.Material.SmoothPlastic, model)
end

-- 3b) Kleines Lächel-Maul (dünnes, gebogenes Ellipsoid) ------------------------------
local mouth = newMeshBall("Mouth", Vector3.new(0.55, 0.14, 0.2), ORIGIN * CFrame.new(0, -0.25, 1.62) * CFrame.Angles(math.rad(15), 0, 0), SPINE_COLOR, Enum.Material.SmoothPlastic, model)

-- 4) Kurze, stumpfe Ellipsoid-"Noppen" (2 Ringe) statt spitzer Wedges - chunky,
--    cartoony statt bedrohlich-scharf, aber deutlich stachelige Silhouette --------
for i = 1, 8 do
	local angle = math.rad(45 * (i - 1))
	local dir = CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(10 * ((i % 3) - 1)), 0, 0)
	local pos = dir * CFrame.new(0, 0, 1.68)
	newMeshBall("Spine" .. i, Vector3.new(0.3, 0.3, 0.55), ORIGIN * pos * CFrame.Angles(0, angle, 0), SPINE_COLOR, Enum.Material.SmoothPlastic, model)
end
for i = 1, 5 do
	local angle = math.rad(72 * (i - 1) + 36)
	local dir = CFrame.Angles(0, angle, 0) * CFrame.Angles(math.rad(58), 0, 0)
	local pos = dir * CFrame.new(0, 0, 1.55)
	newMeshBall("SpineTop" .. i, Vector3.new(0.24, 0.24, 0.42), ORIGIN * pos * CFrame.Angles(0, angle, 0), SPINE_COLOR, Enum.Material.SmoothPlastic, model)
end

-- 5) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

-- The parts above were laid out facing +Z, but the game treats the body's
-- LookVector (-Z) as the front, so turn everything except the body half a
-- circle around it.
do
	local flip = body.CFrame * CFrame.Angles(0, math.pi, 0) * body.CFrame:Inverse()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= body then
			part.CFrame = flip * part.CFrame
		end
	end
end

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Toxin Puffer")

print("[Abyssara] ToxinPuffer created under Workspace.Assets.Creatures")
