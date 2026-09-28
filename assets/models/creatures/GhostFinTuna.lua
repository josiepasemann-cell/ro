--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GhostFinTuna ("Geisterflossen-Thun")
	Rarity (Platzhalter): Epic
	Beschreibung:
		Stromlinienförmiger, torpedoartiger Ellipsoid-Körper, blass blau-weiß,
		mit spitzer Kopf-Verjüngung, Kiemenlinien, Rücken-, Bauch-, Seiten-
		und Schwanzflossen (alle halbtransparent, Glass). Zone: HadalDepths.

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

local previous = creaturesFolder:FindFirstChild("GhostFinTuna")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GhostFinTuna"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(200, 220, 235)
local BODY_DARK = Color3.fromRGB(150, 175, 200)

-- 1) Torpedoförmiger Körper (Ellipsoid) ---------------------------------------------
local body = newBall("Body", Vector3.new(1.8, 1.8, 5.4), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Dunklere Rückenzeichnung -------------------------------------------------------
newBall("BackStripe", Vector3.new(1.0, 0.6, 4.6), ORIGIN * CFrame.new(0, 0.65, 0), BODY_DARK, Enum.Material.SmoothPlastic, model)

-- 2) Kopf-Verjüngung (spitzer nach vorne), tief im Körper eingebettet -----------------------
local nose = newWedge("Nose", Vector3.new(1.4, 1.2, 1.0), ORIGIN * CFrame.new(0, 0, -2.75) * CFrame.Angles(0, math.rad(90), 0), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2b) Kiemenlinien -----------------------------------------------------------------------
for i = 1, 3 do
	local x = -0.2 + (i - 1) * 0.2
	newPart("GillLine" .. i, Vector3.new(0.05, 0.7, 0.05), ORIGIN * CFrame.new(x, 0.1, -2.0), BODY_DARK, Enum.Material.SmoothPlastic, model)
end

-- 3) Rückenflosse ---------------------------------------------------------------------------
local dorsalFin = newWedge("DorsalFin", Vector3.new(0.9, 1.3, 1.1), ORIGIN * CFrame.new(0, 1.15, 0.3) * CFrame.Angles(0, math.rad(90), 0), BODY_COLOR, Enum.Material.Glass, model)
dorsalFin.Transparency = 0.35

-- 3b) Bauchflosse --------------------------------------------------------------------------
local ventralFin = newWedge("VentralFin", Vector3.new(0.7, 0.8, 0.8), ORIGIN * CFrame.new(0, -1.05, 0.5) * CFrame.Angles(0, math.rad(90), math.rad(180)), BODY_COLOR, Enum.Material.Glass, model)
ventralFin.Transparency = 0.35

-- 4) Zwei Seitenflossen (halbtransparent) ------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = newPart(
		"SideFin" .. i,
		Vector3.new(0.15, 0.6, 1.2),
		ORIGIN * CFrame.new(side * 0.85, -0.1, 0.4) * CFrame.Angles(0, 0, math.rad(side * 20)),
		BODY_COLOR,
		Enum.Material.Glass,
		model
	)
	fin.Transparency = 0.4
end

-- 5) Schwanzstiel + Schwanzflosse (2 Wedges) ------------------------------------------------------
local peduncle = newPart("TailPeduncle", Vector3.new(0.5, 0.55, 0.9), ORIGIN * CFrame.new(0, 0, 2.55), BODY_DARK, Enum.Material.SmoothPlastic, model)
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local tailFin = newWedge(
		"TailFin" .. i,
		Vector3.new(0.15, 1.1, 1.1),
		ORIGIN * CFrame.new(0, side * 0.5, 3.35) * CFrame.Angles(0, 0, math.rad(side * 90)),
		BODY_COLOR,
		Enum.Material.Glass,
		model
	)
	tailFin.Transparency = 0.35
end

-- 6) Zwei kleine Augen -----------------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall("Eye" .. i, Vector3.new(0.3, 0.3, 0.3), ORIGIN * CFrame.new(side * 0.65, 0.2, -2.35), Color3.fromRGB(20, 30, 45), Enum.Material.SmoothPlastic, model)
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
