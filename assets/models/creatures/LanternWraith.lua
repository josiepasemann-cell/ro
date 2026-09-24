--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: LanternWraith ("Laternengeist")
	Rarity (Platzhalter): Rare
	Beschreibung:
		Schlanke Geister-Anglerfisch-Silhouette: abgeflachter, dunkelvioletter
		Körper mit einem gebogenen, biolumineszenten Köder-Stiel (Neon) der
		vom Kopf nach vorne ragt, sowie zwei dünnen, halbtransparenten Flossen
		(Glass). Zone: MidnightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-/Schwebe-Animation. Laut Spezifikation bewegt sich der
		  Köder-Stiel mit 2s Sinus-Verzögerung gegenüber dem Körper - das
		  übernimmt der Code-Agent zur Laufzeit, das Buildscript liefert nur
		  die Geometrie (Part "LureTip" markiert die Köder-Spitze).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-15, 6, 75) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Rare"
local ZONE = "MidnightZone"
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

local previous = creaturesFolder:FindFirstChild("LanternWraith")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "LanternWraith"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(35, 20, 45)
local LURE_COLOR = Color3.fromRGB(180, 255, 210)

-- 1) Körper (abgeflacht, geisterhaft) ----------------------------------------
local body = newPart("Body", Vector3.new(2, 2, 5), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Block

-- 2) Kopf (etwas breiter, vorne) -----------------------------------------------
newPart("Head", Vector3.new(1.6, 1.6, 1.2), ORIGIN * CFrame.new(0, 0.2, -2.4), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 3) Köder-Stiel (3 gebogene Segmente, Neon) ------------------------------------
local stalkCFrame = ORIGIN * CFrame.new(0, 0.9, -3.0)
local segLength = 0.9
for seg = 1, 3 do
	stalkCFrame = stalkCFrame * CFrame.Angles(math.rad(-22), 0, 0) * CFrame.new(0, segLength / 2, 0)
	newPart(
		"LureStalk" .. seg,
		Vector3.new(0.25, segLength, 0.25),
		stalkCFrame,
		LURE_COLOR,
		Enum.Material.Neon,
		model
	)
	stalkCFrame = stalkCFrame * CFrame.new(0, segLength / 2, 0)
end

local lureTip = newPart("LureTip", Vector3.new(0.5, 0.5, 0.5), stalkCFrame, LURE_COLOR, Enum.Material.Neon, model)
lureTip.Shape = Enum.PartType.Ball

-- 4) Zwei dünne, halbtransparente Flossen ---------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = newPart(
		"Fin" .. i,
		Vector3.new(0.15, 1.4, 1.8),
		ORIGIN * CFrame.new(side * 1.1, 0.1, 0.6) * CFrame.Angles(0, math.rad(side * 20), 0),
		Color3.fromRGB(120, 90, 150),
		Enum.Material.Glass,
		model
	)
	fin.Transparency = 0.5
end

-- 5) Kleine Glow-Augen -----------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eye = newPart(
		"Eye" .. i,
		Vector3.new(0.2, 0.2, 0.2),
		ORIGIN * CFrame.new(side * 0.5, 0.3, -2.8),
		Color3.fromRGB(200, 255, 220),
		Enum.Material.Neon,
		model
	)
	eye.Shape = Enum.PartType.Ball
end

-- 6) Idle-Puls-Attachment ---------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Laternengeist")

print("[Abyssara] LanternWraith erzeugt unter Workspace.Assets.Creatures")
