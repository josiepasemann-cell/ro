--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: Anglerfish ("Anglerfisch")
	Rarity (Platzhalter): Rare
	Beschreibung:
		Kompakter, bulliger Fisch mit großem Maul (Ober- und Unterkiefer als
		Wedges, sichtbare Zähne), stachliger Rückenflosse, Bauch- und
		Brustflossen, gebogenem Schwanzstiel mit Schwanzflosse, und der
		charakteristischen leuchtenden Angel-Rute (Illicium) über dem Kopf.
		Zone: TwilightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/Schwebeanimation.
		- "LureOrb": Neon-Part an der Illicium-Spitze, für spätere Köder-VFX.
		- "TailFin" wird von IdleSway automatisch geschwenkt.
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

local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function newWedge(name, size, cframe, color, material, parent)
	local part = Instance.new("WedgePart")
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
local BELLY_COLOR = Color3.fromRGB(70, 65, 80)
local GLOW_COLOR = Color3.fromRGB(160, 90, 255)

-- 1) Hauptkörper (bullig, abgeflacht, Ellipsoid) --------------------------------
local body = newBall("Body", Vector3.new(2.6, 2.2, 3.2), ORIGIN, SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Hellere Bauchunterseite, gut eingebettet -----------------------------------
newBall("Belly", Vector3.new(1.9, 1.1, 2.6), ORIGIN * CFrame.new(0, -0.85, 0.1), BELLY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Großes Maul: Oberkiefer (Teil des Kopfes) + Unterkiefer als Wedge -----------
local jawCFrame = ORIGIN * CFrame.new(0, -0.75, 1.45) * CFrame.Angles(math.rad(20), 0, 0)
local jaw = newWedge("LowerJaw", Vector3.new(1.6, 0.9, 1.3), jawCFrame, SKIN_COLOR, Enum.Material.SmoothPlastic, model)

local upperJawCFrame = ORIGIN * CFrame.new(0, 0.35, 1.5) * CFrame.Angles(math.rad(-12), 0, 0)
newWedge("UpperJaw", Vector3.new(1.7, 0.6, 1.1), upperJawCFrame * CFrame.Angles(math.rad(180), 0, 0), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 3) Zähne (Ober- und Unterkiefer, kleine weiße Spikes) --------------------------
for i = 1, 5 do
	local x = -0.6 + (i - 1) * 0.3
	local toothCFrame = ORIGIN * CFrame.new(x, -0.45, 1.75) * CFrame.Angles(math.rad(180), 0, 0)
	newPart("ToothLower" .. i, Vector3.new(0.12, 0.35, 0.12), toothCFrame, Color3.fromRGB(235, 235, 240), Enum.Material.SmoothPlastic, model)
	local topToothCFrame = ORIGIN * CFrame.new(x, 0.1, 1.8)
	newPart("ToothUpper" .. i, Vector3.new(0.1, 0.28, 0.1), topToothCFrame, Color3.fromRGB(235, 235, 240), Enum.Material.SmoothPlastic, model)
end

-- 4) Schwanzstiel + Schwanzflosse, überlappend an den Körper angesetzt ----------
local peduncle = newPart("TailPeduncle", Vector3.new(0.8, 1.0, 1.0), ORIGIN * CFrame.new(0, 0, -1.7), SKIN_COLOR, Enum.Material.SmoothPlastic, model)
local tailFin = newPart("TailFin", Vector3.new(0.22, 1.6, 1.3), ORIGIN * CFrame.new(0, 0, -2.65), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

-- 5) Stachlige Rückenflosse (3 überlappende Spikes) -------------------------------
for i = 1, 3 do
	local spikeCFrame = ORIGIN * CFrame.new(-0.6 + (i - 1) * 0.5, 1.15, 0.3 - (i - 1) * 0.4) * CFrame.Angles(math.rad(-90), 0, 0)
	newWedge("DorsalSpike" .. i, Vector3.new(0.15, 0.55, 0.55), spikeCFrame, SKIN_COLOR, Enum.Material.SmoothPlastic, model)
end

-- 6) Bauch- und Brustflossen -------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newWedge(
		"SideFin" .. i,
		Vector3.new(0.15, 0.8, 1.0),
		ORIGIN * CFrame.new(side * 1.3, -0.3, 0.4) * CFrame.Angles(0, math.rad(side * -90), 0),
		SKIN_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 7) Illicium (Angel-Rute) aus dem Kopf, leicht nach vorne geneigt, mit
--    Leucht-Köder. Alle Segmente liegen als durchgehende Kette entlang der
--    lokalen Y-Achse von rodCFrame, jedes um 0.2 Studs im Vorgänger
--    eingebettet - kein Segment kann dadurch freischweben. -----------------
local rodCFrame = ORIGIN * CFrame.new(0, 0.75, 1.1) * CFrame.Angles(math.rad(-25), 0, 0)
local ROD_OVERLAP = 0.2

local half1 = 0.5 -- IlliciumBase Länge 1.0
local base1Y = half1 - ROD_OVERLAP
newPart("IlliciumBase", Vector3.new(0.22, half1 * 2, 0.22), rodCFrame * CFrame.new(0, base1Y, 0), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

local half2 = 0.45 -- IlliciumTipRod Länge 0.9
local base2Y = (base1Y + half1) - ROD_OVERLAP + half2
newPart("IlliciumTipRod", Vector3.new(0.16, half2 * 2, 0.16), rodCFrame * CFrame.new(0, base2Y, 0), SKIN_COLOR, Enum.Material.SmoothPlastic, model)

local orbHalf = 0.35 -- LureOrb Durchmesser 0.7
local orbY = (base2Y + half2) - ROD_OVERLAP + orbHalf
local lureOrb = newBall("LureOrb", Vector3.new(orbHalf * 2, orbHalf * 2, orbHalf * 2), rodCFrame * CFrame.new(0, orbY, 0), GLOW_COLOR, Enum.Material.Neon, model)

-- 8) Zwei Augen ---------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall("Eye" .. i, Vector3.new(0.32, 0.32, 0.32), ORIGIN * CFrame.new(side * 0.75, 0.55, 1.3), Color3.fromRGB(255, 230, 60), Enum.Material.Neon, model)
end

-- 9) Idle-Puls-Attachment -----------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Anglerfish")

print("[Abyssara] Anglerfish created under Workspace.Assets.Creatures")
