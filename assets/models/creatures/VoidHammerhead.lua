--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: VoidHammerhead ("Leerenhammerhai")
	Rarity (Platzhalter): Legendary
	Beschreibung:
		Eckige Hammerhai-Silhouette, fast schwarzer Ellipsoid-Körper mit
		Hammerkopf (aus 2 Wedges verjüngt), Kiemenlinien, Brust-/Bauchflossen,
		Rückenflosse, gegliedertem Schwanzstiel, Schwanzflosse und einem
		leuchtend-violetten Streifen (Neon) von Kopf bis Schwanz sowie
		leuchtend-violetten Augen an den Hammer-Enden. Zone: MidnightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung (S-Kurven-
		  Schwimmpfad wird vom Code-Agenten ergänzt).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-
		  Puls-/Helligkeitsanimation (Teil "StripeGlow" pulsiert mit der
		  Schwimmgeschwindigkeit).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 6, 75) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Legendary"
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

local previous = creaturesFolder:FindFirstChild("VoidHammerhead")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "VoidHammerhead"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(18, 18, 28)
local BODY_LIGHT = Color3.fromRGB(32, 32, 46)
local STRIPE_COLOR = Color3.fromRGB(160, 60, 255)

-- 1) Körper (eckig, langgestreckt, Ellipsoid) -----------------------------------------
local body = newBall("Body", Vector3.new(2.1, 1.7, 6.5), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Hellere Bauchunterseite ------------------------------------------------------------
newBall("Belly", Vector3.new(1.5, 0.9, 5.2), ORIGIN * CFrame.new(0, -0.85, 0), BODY_LIGHT, Enum.Material.SmoothPlastic, model)

-- 2) Hammerkopf: zentraler Querbalken + 2 sich verjüngende Enden -----------------------
newPart("HammerHead", Vector3.new(6.8, 0.9, 1.2), ORIGIN * CFrame.new(0, 0.1, -3.15), BODY_COLOR, Enum.Material.SmoothPlastic, model)
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newWedge(
		"HammerTip" .. i,
		Vector3.new(0.6, 0.75, 1.0),
		ORIGIN * CFrame.new(side * 3.6, 0.1, -3.15) * CFrame.Angles(0, math.rad(side * 90), 0),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 2b) Kiemenlinien unter dem Hammerkopf-Übergang --------------------------------------
for i = 1, 4 do
	local x = -0.5 + (i - 1) * 0.33
	newPart("GillLine" .. i, Vector3.new(0.06, 0.4, 0.06), ORIGIN * CFrame.new(x, -0.1, -2.55), Color3.fromRGB(10, 10, 16), Enum.Material.SmoothPlastic, model)
end

-- 3) Rückenflosse -----------------------------------------------------------------------
local dorsalFin = newWedge("DorsalFin", Vector3.new(1.5, 1.7, 0.35), ORIGIN * CFrame.new(0, 1.35, 0.4) * CFrame.Angles(0, math.rad(90), 0), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 4) Brust-/Bauchflossen -----------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newWedge(
		"SideFin" .. i,
		Vector3.new(0.2, 0.5, 1.6),
		ORIGIN * CFrame.new(side * 1.3, -0.2, -0.8) * CFrame.Angles(0, 0, math.rad(side * -90)),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 5) Gegliederter Schwanzstiel + Schwanzflosse (2 Wedges) ------------------------------
local peduncle = newPart("TailPeduncle", Vector3.new(0.8, 0.9, 1.2), ORIGIN * CFrame.new(0, 0, 2.9), BODY_COLOR, Enum.Material.SmoothPlastic, model)
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newWedge(
		"TailFin" .. i,
		Vector3.new(0.25, 1.5, 1.5),
		ORIGIN * CFrame.new(0, side * 0.65, 3.9) * CFrame.Angles(0, 0, math.rad(side * 90)),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 6) Leuchtend-violetter Streifen (Kopf bis Schwanz) -----------------------------------------
newPart("StripeGlow", Vector3.new(0.25, 0.25, 6.3), ORIGIN * CFrame.new(0, 0.82, 0.1), STRIPE_COLOR, Enum.Material.Neon, model)

-- 7) Leuchtende violette Augen an den Hammer-Enden -----------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall(
		"Eye" .. i,
		Vector3.new(0.38, 0.34, 0.38),
		ORIGIN * CFrame.new(side * 3.25, 0.1, -3.15),
		STRIPE_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 8) Idle-Puls-Attachment -----------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Void Hammerhead")

print("[Abyssara] VoidHammerhead created under Workspace.Assets.Creatures")
