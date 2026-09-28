--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GhostFinTuna ("Geisterflossen-Thun")
	Rarity (Platzhalter): Epic
	Beschreibung:
		Stromlinienförmiger, cartoonhaft rundlicher, torpedoartiger
		Ellipsoid-Körper, blass blau-weiß, mit sanft verjüngter
		Kopf-Schnauze (Ellipsoid statt Keil), sanften Kiemen-Punkten,
		fächerartigen Rücken-, Bauch-, Seiten- und Schwanzflossen (alle
		halbtransparent, Glass, aus überlappenden flachen Ellipsen) und
		großen Kulleraugen. Zone: HadalDepths.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung. Laut
		  Spezifikation schwimmt diese Kreatur (anders als die meisten
		  anderen, die auf der Stelle schweben) aktiv in einer festen
		  Gleit-Schleife um einen Radius - das übernimmt der Code-Agent.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-/Bewegungs-Animation.
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(5, 6, 90) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Epic"
local ZONE = "HadalDepths"
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

local previous = creaturesFolder:FindFirstChild("GhostFinTuna")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GhostFinTuna"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(200, 220, 235)
local BODY_DARK = Color3.fromRGB(150, 175, 200)
local BODY_BELLY = Color3.fromRGB(230, 240, 250)

-- 1) Torpedoförmiger, cartoonhaft rundlicher Körper (Ellipsoid) ---------------------
local body = newBall("Body", Vector3.new(1.9, 1.85, 5.2), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Countershading: dunklere Rückenzeichnung, hellere Bauchunterseite --------------
newBall("BackStripe", Vector3.new(1.05, 0.65, 4.4), ORIGIN * CFrame.new(0, 0.68, 0), BODY_DARK, Enum.Material.SmoothPlastic, model)
newBall("Belly", Vector3.new(1.3, 0.5, 3.8), ORIGIN * CFrame.new(0, -0.72, 0.2), BODY_BELLY, Enum.Material.SmoothPlastic, model)

-- 2) Sanft verjüngte Kopf-Schnauze (Ellipsoid statt Keil), tief eingebettet -----------------
newBall("Nose", Vector3.new(1.3, 1.15, 1.1), ORIGIN * CFrame.new(0, 0, -2.65), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2b) Sanfte Kiemen-Punkte -----------------------------------------------------------------
for i = 1, 3 do
	local x = -0.2 + (i - 1) * 0.2
	newBall("GillLine" .. i, Vector3.new(0.07, 0.55, 0.07), ORIGIN * CFrame.new(x, 0.1, -2.0), BODY_DARK, Enum.Material.SmoothPlastic, model)
end

-- 3) Rückenflosse (2 überlappende flache Ellipsen, fächerartig) ---------------------------------
local dorsalFin = newBall("DorsalFin", Vector3.new(0.24, 1.35, 1.0), ORIGIN * CFrame.new(0, 1.15, 0.3), BODY_COLOR, Enum.Material.Glass, model)
dorsalFin.Transparency = 0.3
local dorsalTip = newBall("DorsalFinTip", Vector3.new(0.16, 0.7, 0.6), ORIGIN * CFrame.new(0, 1.75, 0.55), BODY_DARK, Enum.Material.Glass, model)
dorsalTip.Transparency = 0.35

-- 3b) Bauchflosse --------------------------------------------------------------------------
local ventralFin = newBall("VentralFin", Vector3.new(0.2, 0.8, 0.7), ORIGIN * CFrame.new(0, -1.05, 0.5), BODY_COLOR, Enum.Material.Glass, model)
ventralFin.Transparency = 0.3

-- 4) Zwei Seitenflossen (halbtransparent, flache Ellipsen) ------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = newBall(
		"SideFin" .. i,
		Vector3.new(0.18, 0.6, 1.15),
		ORIGIN * CFrame.new(side * 0.9, -0.1, 0.4) * CFrame.Angles(0, 0, math.rad(side * 22)),
		BODY_COLOR,
		Enum.Material.Glass,
		model
	)
	fin.Transparency = 0.35
end

-- 5) Schwanzstiel + fächerartige Schwanzflosse (überlappende Ellipsen) ------------------------------------
newBall("TailPeduncle", Vector3.new(0.5, 0.65, 0.9), ORIGIN * CFrame.new(0, 0, 2.5), BODY_DARK, Enum.Material.SmoothPlastic, model)
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local tailFin = newBall(
		"TailFin" .. i,
		Vector3.new(0.18, 1.1, 1.05),
		ORIGIN * CFrame.new(0, side * 0.35, 3.3) * CFrame.Angles(0, 0, math.rad(side * 58)),
		BODY_COLOR,
		Enum.Material.Glass,
		model
	)
	tailFin.Transparency = 0.3
end

-- 6) Große Kulleraugen -----------------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 0.65, 0.22, -2.3), Vector3.new(0.4, 0.4, 0.24), Color3.fromRGB(20, 30, 45), model)
end

-- 7) Idle-Puls-Attachment -----------------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Ghost Fin Tuna")

print("[Abyssara] GhostFinTuna created under Workspace.Assets.Creatures")
