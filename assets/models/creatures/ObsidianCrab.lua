--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: ObsidianCrab ("Obsidiankrabbe")
	Rarity (Platzhalter): Uncommon
	Beschreibung:
		Blockiger, niedriger Krabbenkörper aus mattschwarzem Slate-Material
		mit gewölbtem Panzer (Ellipsoid), Panzerkante, 2 überdimensionierten,
		mehrteiligen eckigen Scheren, 4 gegliederten Beinpaaren (Ober-/
		Unterschenkel) und 2 kleinen leuchtenden Augen-Punkten (Neon, rot).
		Sitzt am Höhlenboden, keine Fortbewegung. Zone: MidnightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung (hier: rein
		  stationär, dient nur als Ankerpunkt).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Schere-Auf/Zu-Animation (Teile "ClawLeft"/"ClawRight" markieren
		  die zu animierenden Scheren, Präfix "claw" wird von IdleSway
		  zusätzlich automatisch geschwenkt).
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

local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
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

local BODY_COLOR = Color3.fromRGB(32, 32, 36)
local BODY_LIGHT = Color3.fromRGB(55, 55, 62)
local EYE_COLOR = Color3.fromRGB(255, 80, 60)

-- 1) Körper: gewölbter Panzer (Ellipsoid) + flache Basisplatte -------------------
local body = newBall("Body", Vector3.new(3.0, 1.2, 3.0), ORIGIN * CFrame.new(0, 0.2, 0), BODY_COLOR, Enum.Material.Slate, model)
newPart("CarapaceBase", Vector3.new(2.9, 0.5, 2.9), ORIGIN * CFrame.new(0, -0.25, 0), BODY_COLOR, Enum.Material.Slate, model)

-- 1b) Helle Panzerkante entlang des Rands -----------------------------------------
newPart("CarapaceRim", Vector3.new(3.15, 0.16, 3.15), ORIGIN * CFrame.new(0, -0.02, 0), BODY_LIGHT, Enum.Material.Slate, model)

-- 2) 4 gegliederte Beinpaare (Ober- + Unterschenkel), an der Basisplatte
--    eingebettet und nach unten abgewinkelt ----------------------------------------
local legZ = { 0.95, 0.32, -0.32, -0.95 }
for i = 1, 4 do
	for j = 1, 2 do
		local side = (j == 1) and 1 or -1
		local hipCFrame = ORIGIN * CFrame.new(side * 1.45, -0.3, legZ[i]) * CFrame.Angles(0, 0, math.rad(side * -35))
		local upperLeg = newPart(
			"LegUpper" .. i .. "_" .. j,
			Vector3.new(0.32, 0.75, 0.34),
			hipCFrame * CFrame.new(0, -0.3, 0),
			BODY_COLOR,
			Enum.Material.Slate,
			model
		)
		local kneeCFrame = hipCFrame * CFrame.new(0, -0.6, 0) * CFrame.Angles(0, 0, math.rad(side * -40))
		newPart(
			"Leg" .. i .. "_" .. j,
			Vector3.new(0.24, 0.65, 0.26),
			kneeCFrame * CFrame.new(0, -0.26, 0),
			BODY_LIGHT,
			Enum.Material.Slate,
			model
		)
	end
end

-- 3) 2 überdimensionierte, mehrteilige eckige Scheren --------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local clawName = (side == 1) and "ClawLeft" or "ClawRight"
	local shoulderCFrame = ORIGIN * CFrame.new(side * 1.6, 0.15, -1.5) * CFrame.Angles(0, math.rad(side * -20), 0)
	local upperArm = newPart(
		"ClawArm" .. i,
		Vector3.new(0.7, 0.55, 0.9),
		shoulderCFrame * CFrame.new(0, 0, -0.4),
		BODY_COLOR,
		Enum.Material.Slate,
		model
	)
	local claw = newPart(
		clawName,
		Vector3.new(1.15, 0.85, 1.5),
		shoulderCFrame * CFrame.new(0, 0.05, -1.2),
		BODY_COLOR,
		Enum.Material.Slate,
		model
	)
	claw.Name = clawName

	-- Bewegliche Scherenspitze (obere Klaue), leicht geöffnet
	local pincer = Instance.new("WedgePart")
	pincer.Name = "ClawPincer" .. i
	pincer.Size = Vector3.new(1.0, 0.3, 0.7)
	pincer.CFrame = shoulderCFrame * CFrame.new(0, 0.45, -1.55) * CFrame.Angles(math.rad(-10), 0, 0)
	pincer.Color = BODY_LIGHT
	pincer.Material = Enum.Material.Slate
	pincer.Anchored = true
	pincer.CanCollide = false
	pincer.Parent = model
end

-- 4) 2 kleine leuchtende Augen-Punkte -----------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall(
		"Eye" .. i,
		Vector3.new(0.26, 0.26, 0.26),
		ORIGIN * CFrame.new(side * 0.5, 0.65, -1.35),
		EYE_COLOR,
		Enum.Material.Neon,
		model
	)
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
