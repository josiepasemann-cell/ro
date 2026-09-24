--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: ObsidianCrab ("Obsidiankrabbe")
	Rarity (Platzhalter): Uncommon
	Beschreibung:
		Blockiger, niedriger Krabbenkörper aus mattschwarzem Slate-Material
		mit 2 überdimensionierten, eckigen Scheren, 4 kurzen Stummelbeinen
		und 2 kleinen leuchtenden Augen-Punkten (Neon, rot). Sitzt am
		Höhlenboden, keine Fortbewegung. Zone: MidnightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung (hier: rein
		  stationär, dient nur als Ankerpunkt).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Schere-Auf/Zu-Animation (Teile "ClawLeft"/"ClawRight" markieren
		  die zu animierenden Scheren).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-5, 6, 75) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Uncommon"
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

local previous = creaturesFolder:FindFirstChild("ObsidianCrab")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ObsidianCrab"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(20, 20, 22)
local EYE_COLOR = Color3.fromRGB(255, 80, 60)

-- 1) Körper (blockig, niedrig) --------------------------------------------------
local body = newPart("Body", Vector3.new(3, 1.1, 3), ORIGIN, BODY_COLOR, Enum.Material.Slate, model)

-- 2) 4 Stummelbeine (je 2 pro Seite) ---------------------------------------------
for i = 1, 4 do
	local side = (i <= 2) and 1 or -1
	local index = (i - 1) % 2
	local zOffset = (index == 0) and 0.9 or -0.9
	newPart(
		"Leg" .. i,
		Vector3.new(0.35, 0.5, 0.9),
		ORIGIN * CFrame.new(side * 1.6, -0.5, zOffset),
		BODY_COLOR,
		Enum.Material.Slate,
		model
	)
end

-- 3) 2 überdimensionierte, eckige Scheren -----------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local claw = newPart(
		"Claw" .. (side == 1 and "Left" or "Right"),
		Vector3.new(1.2, 0.9, 1.6),
		ORIGIN * CFrame.new(side * 2.0, 0.2, -1.8) * CFrame.Angles(0, math.rad(side * -25), 0),
		BODY_COLOR,
		Enum.Material.Slate,
		model
	)
	claw.Name = (side == 1) and "ClawLeft" or "ClawRight"
end

-- 4) 2 kleine leuchtende Augen-Punkte -----------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eye = newPart(
		"Eye" .. i,
		Vector3.new(0.25, 0.25, 0.25),
		ORIGIN * CFrame.new(side * 0.5, 0.7, -1.5),
		EYE_COLOR,
		Enum.Material.Neon,
		model
	)
	eye.Shape = Enum.PartType.Ball
end

-- 5) Idle-Puls-Attachment -----------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Obsidian Crab")

print("[Abyssara] ObsidianCrab created under Workspace.Assets.Creatures")
