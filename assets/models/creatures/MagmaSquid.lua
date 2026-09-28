--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: MagmaSquid ("Magmakalmar")
	Rarity (Platzhalter): Epic
	Beschreibung:
		Bauchiger, cartoonhaft rundlicher, dunkelroter Ellipsoid-Mantel
		(Material.CrackedLava für rissige Magma-Optik) mit fächerartigen
		Flossen an den Seiten, 8 sanft gebogenen, sich verjüngenden
		Tentakel-Ellipsenketten (keine kantigen Segmente) mit dünner,
		leuchtend-oranger Ader-Linie, 2 kürzeren Greifarmen und einem
		großen, ausdrucksstarken Kulleraugen-Paar. Zone: MidnightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Mantel) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-Animation (Mantel pulsiert 3s-Zyklus, Tentakel-Wellen
		  mit je 0,3s Versatz - Teile "Tentacle1".."Tentacle8" markieren die
		  zu animierenden Arme, IdleSway schwenkt sie automatisch).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(5, 8, 75) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Epic"
local ZONE = "MidnightZone"
local TENTACLE_COUNT = 8
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
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 250, 235), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.5, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), pupilColor, Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("MagmaSquid")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MagmaSquid"
model.Parent = creaturesFolder

local MANTLE_COLOR = Color3.fromRGB(70, 18, 22)
local MANTLE_TOP = Color3.fromRGB(45, 10, 14)
local MANTLE_LIGHT = Color3.fromRGB(105, 35, 32)
local VEIN_COLOR = Color3.fromRGB(255, 110, 35)

-- 1) Mantel: bauchiger, cartoonhaft übergroßer Ellipsoid, rissige Magma-Haut -
local body = newBall("Body", Vector3.new(2.7, 2.8, 3.1), ORIGIN, MANTLE_COLOR, Enum.Material.CrackedLava, model)

-- 1b) Countershading: dunklere Mantelspitze oben, hellere Unterseite --------
newBall("MantleTip", Vector3.new(1.3, 1.35, 1.5), ORIGIN * CFrame.new(0, 1.25, -0.15), MANTLE_TOP, Enum.Material.CrackedLava, model)
newBall("MantleBelly", Vector3.new(1.7, 1.2, 2.0), ORIGIN * CFrame.new(0, -0.95, 0.3), MANTLE_LIGHT, Enum.Material.CrackedLava, model)

-- 1c) Zwei seitliche, fächerartige Flossen (flache, überlappende Ellipsen) ---
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall("Wing" .. i, Vector3.new(0.28, 1.15, 1.35), ORIGIN * CFrame.new(side * 1.4, 0.4, -0.3) * CFrame.Angles(0, 0, math.rad(side * -18)), MANTLE_LIGHT, Enum.Material.SmoothPlastic, model)
	newBall("Wing" .. i .. "Tip", Vector3.new(0.2, 0.7, 0.85), ORIGIN * CFrame.new(side * 2.0, 0.5, -0.55) * CFrame.Angles(0, 0, math.rad(side * -24)), VEIN_COLOR, Enum.Material.Neon, model).Transparency = 0.4
end

-- 2) Großes, ausdrucksstarkes Augenpaar ---------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 0.55, 0.3, -1.5), Vector3.new(0.6, 0.6, 0.32), Color3.fromRGB(60, 20, 10), model)
end

-- 3) 8 sanft gebogene, sich verjüngende Tentakel-Ellipsenketten (3 Segmente,
--    runde Gelenke statt kantiger Sticks) mit dünner Ader-Linie -------------------
local SEG_OVERLAP = 0.2
for t = 1, TENTACLE_COUNT do
	local angle = math.rad(45 * (t - 1))
	local radius = 0.9
	local baseOffset = Vector3.new(math.cos(angle) * radius, -1.35, math.sin(angle) * radius + 0.5)
	local armCFrame = ORIGIN * CFrame.new(baseOffset) * CFrame.Angles(math.rad(-8), angle, 0)

	local diameters = { 0.42, 0.3, 0.2 }
	local lengths = { 0.85, 0.75, 0.65 }
	local curl = (t % 2 == 0) and 10 or -10
	local currentCFrame = armCFrame
	local prevHalf = 0.05
	for seg = 1, 3 do
		local half = lengths[seg] / 2
		currentCFrame = currentCFrame * CFrame.Angles(math.rad(curl), 0, 0) * CFrame.new(0, -(prevHalf + half - SEG_OVERLAP), 0)
		local segName = (seg == 1) and ("Tentacle" .. t) or ((seg == 2) and ("Tentacle" .. t .. "Mid") or ("Tentacle" .. t .. "Tip"))
		newBall(segName, Vector3.new(diameters[seg], lengths[seg], diameters[seg]), currentCFrame, MANTLE_COLOR, Enum.Material.SmoothPlastic, model)
		if seg == 3 then
			-- Nur an der Spitze eine leuchtende Ader-Markierung (Budget-schonend)
			local vein = newBall("TentacleVein" .. t, Vector3.new(diameters[seg] * 0.4, lengths[seg] * 0.9, diameters[seg] * 0.4), currentCFrame * CFrame.new(diameters[seg] * 0.4, 0, diameters[seg] * 0.4), VEIN_COLOR, Enum.Material.Neon, model)
			vein.Transparency = 0.1
		end
		prevHalf = half
	end
end

-- 4) Idle-Puls-Attachment -----------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Magma Squid")

print("[Abyssara] MagmaSquid created under Workspace.Assets.Creatures")
