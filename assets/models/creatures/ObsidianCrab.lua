--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: ObsidianCrab ("Obsidiankrabbe")
	Rarity (Platzhalter): Uncommon
	Beschreibung:
		Rundlicher, cartoonhaft pummeliger Krabbenkörper aus mattschwarzem
		Slate-Material: gewölbter Ellipsoid-Panzer mit Rand-Wulst (statt
		harter Blockkanten), 2 überdimensionierten, rundlichen Scheren aus
		überlappenden Ellipsoiden, 4 kurzen, rundlich gegliederten
		Beinpaaren (Ober-/Unterschenkel-Ellipsen mit kleinen Fuß-Kugeln) und
		2 großen Kulleraugen auf kurzen Stielen. Sitzt am Höhlenboden, keine
		Fortbewegung. Zone: MidnightZone.

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

local function newCartoonEye(name, cframe, eyeSize, pupilColor, parent)
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.55, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), pupilColor, Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
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

local BODY_COLOR = Color3.fromRGB(34, 34, 38)
local BODY_LIGHT = Color3.fromRGB(58, 58, 66)
local BODY_BELLY = Color3.fromRGB(70, 70, 78)
local EYE_COLOR = Color3.fromRGB(255, 80, 60)

-- 1) Rundlicher, gewölbter Panzer (Ellipsoid) + flache Unterseiten-Basis -----
local body = newBall("Body", Vector3.new(3.2, 1.6, 3.2), ORIGIN * CFrame.new(0, 0.2, 0), BODY_COLOR, Enum.Material.Slate, model)
newBall("CarapaceBase", Vector3.new(3.0, 0.7, 3.0), ORIGIN * CFrame.new(0, -0.28, 0), BODY_COLOR, Enum.Material.Slate, model)

-- 1b) Countershading: heller Scheitel oben, hellere Unterseite ----------------
newBall("CarapaceHighlight", Vector3.new(1.9, 0.9, 1.9), ORIGIN * CFrame.new(0, 0.75, -0.2), BODY_LIGHT, Enum.Material.Slate, model)
newBall("CarapaceRim", Vector3.new(3.35, 0.45, 3.35), ORIGIN * CFrame.new(0, -0.05, 0), BODY_LIGHT, Enum.Material.Slate, model)
newBall("Belly", Vector3.new(2.2, 0.4, 2.2), ORIGIN * CFrame.new(0, -0.55, 0), BODY_BELLY, Enum.Material.SmoothPlastic, model)

-- 2) 4 kurze, rundliche Beinpaare (Ober-/Unterschenkel-Ellipsen + Fuß-Kugel),
--    an der Basisplatte eingebettet und nach unten abgewinkelt --------------------
local legZ = { 0.95, 0.32, -0.32, -0.95 }
for i = 1, 4 do
	for j = 1, 2 do
		local side = (j == 1) and 1 or -1
		local hipCFrame = ORIGIN * CFrame.new(side * 1.5, -0.25, legZ[i]) * CFrame.Angles(0, 0, math.rad(side * -35))
		newBall(
			"LegUpper" .. i .. "_" .. j,
			Vector3.new(0.42, 0.62, 0.42),
			hipCFrame * CFrame.new(0, -0.26, 0),
			BODY_COLOR,
			Enum.Material.Slate,
			model
		)
		local kneeCFrame = hipCFrame * CFrame.new(0, -0.52, 0) * CFrame.Angles(0, 0, math.rad(side * -42))
		newBall(
			"Leg" .. i .. "_" .. j,
			Vector3.new(0.32, 0.55, 0.32),
			kneeCFrame * CFrame.new(0, -0.22, 0),
			BODY_LIGHT,
			Enum.Material.Slate,
			model
		)
		local footCFrame = kneeCFrame * CFrame.new(0, -0.5, 0)
		newBall("LegFoot" .. i .. "_" .. j, Vector3.new(0.16, 0.16, 0.16), footCFrame, BODY_LIGHT, Enum.Material.Slate, model)
	end
end

-- 3) 2 überdimensionierte, rundliche Scheren aus überlappenden Ellipsoiden ------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local clawName = (side == 1) and "ClawLeft" or "ClawRight"
	local shoulderCFrame = ORIGIN * CFrame.new(side * 1.7, 0.2, -1.4) * CFrame.Angles(0, math.rad(side * -22), 0)
	newBall("ClawArm" .. i, Vector3.new(0.65, 0.55, 0.85), shoulderCFrame * CFrame.new(0, 0, -0.35), BODY_COLOR, Enum.Material.Slate, model)
	local claw = newBall(clawName, Vector3.new(1.25, 0.95, 1.4), shoulderCFrame * CFrame.new(0, 0.05, -1.15), BODY_COLOR, Enum.Material.Slate, model)
	claw.Name = clawName

	-- Bewegliche, gerundete Scherenspitze (obere Klauenhälfte), leicht geöffnet
	newBall("ClawPincer" .. i, Vector3.new(0.85, 0.32, 0.7), shoulderCFrame * CFrame.new(0, 0.5, -1.55) * CFrame.Angles(math.rad(-10), 0, 0), BODY_LIGHT, Enum.Material.Slate, model)
end

-- 4) 2 große Kulleraugen auf kurzen Stielen -------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local stalkCFrame = ORIGIN * CFrame.new(side * 0.5, 0.55, -1.3) * CFrame.Angles(math.rad(-20), 0, 0)
	newBall("EyeStalk" .. i, Vector3.new(0.22, 0.42, 0.22), stalkCFrame, BODY_COLOR, Enum.Material.Slate, model)
	newCartoonEye("Eye" .. i, stalkCFrame * CFrame.new(0, 0.4, 0), Vector3.new(0.4, 0.4, 0.26), EYE_COLOR, model)
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
