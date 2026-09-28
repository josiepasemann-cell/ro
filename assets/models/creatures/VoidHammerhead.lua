--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: VoidHammerhead ("Leerenhammerhai")
	Rarity (Platzhalter): Legendary
	Beschreibung:
		Rundliche, cartoonhaft kräftige Hammerhai-Silhouette: fast schwarzer
		Ellipsoid-Körper (Kopf/Torso/Schwanzbasis als 3 überlappende
		Ellipsoide) mit einem Hammerkopf aus 2 länglichen, abgerundeten
		Ellipsoid-"Lappen" (statt kantiger Keile), sanften Kiemen-Punkten,
		fächerartigen Brust-/Bauchflossen, großer Rückenflosse, gegliedertem
		Schwanzstiel, Schwanzflosse, einem leuchtend-violetten Streifen
		(Neon) von Kopf bis Schwanz sowie großen leuchtend-violetten
		Kulleraugen an den Hammer-Enden. Zone: MidnightZone.

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

local function newCartoonEye(name, cframe, eyeSize, pupilColor, parent)
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.55, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), pupilColor, Enum.Material.Neon, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
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

local BODY_COLOR = Color3.fromRGB(20, 20, 30)
local BODY_TOP = Color3.fromRGB(12, 12, 18)
local BODY_LIGHT = Color3.fromRGB(36, 36, 50)
local STRIPE_COLOR = Color3.fromRGB(160, 60, 255)

-- 1) Körper: 3 überlappende Ellipsoide (Kopf/Torso/Schwanzbasis) für eine
--    runde, cartoonhafte Silhouette statt eines einzelnen Blocks ------------
local head = newBall("Head", Vector3.new(1.9, 1.6, 2.0), ORIGIN * CFrame.new(0, 0.1, -2.4), BODY_COLOR, Enum.Material.SmoothPlastic, model)
local body = newBall("Body", Vector3.new(2.1, 1.7, 4.4), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)
newBall("TailBase", Vector3.new(1.3, 1.0, 2.2), ORIGIN * CFrame.new(0, -0.1, 2.6), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Countershading: dunklerer Rücken, hellere Bauchunterseite -------------
newBall("BackShade", Vector3.new(1.3, 0.7, 3.6), ORIGIN * CFrame.new(0, 0.7, 0), BODY_TOP, Enum.Material.SmoothPlastic, model)
newBall("Belly", Vector3.new(1.5, 0.9, 5.2), ORIGIN * CFrame.new(0, -0.85, 0), BODY_LIGHT, Enum.Material.SmoothPlastic, model)

-- 2) Hammerkopf: 2 längliche, abgerundete Ellipsoid-"Lappen" statt kantiger
--    Wedges - überlappen deutlich mit dem Kopf ---------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall(
		"HammerLobe" .. i,
		Vector3.new(2.9, 0.95, 1.15),
		ORIGIN * CFrame.new(side * 1.7, 0.2, -3.15) * CFrame.Angles(0, 0, 0),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end
-- Zentraler Verbindungswulst zwischen den beiden Lappen, verhindert eine
-- sichtbare Einschnürung in der Mitte des Hammers.
newBall("HammerBridge", Vector3.new(2.0, 1.0, 1.3), ORIGIN * CFrame.new(0, 0.2, -3.1), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2b) Sanfte Kiemen-Punkte unter dem Hammerkopf-Übergang -----------------------
for i = 1, 4 do
	local x = -0.5 + (i - 1) * 0.33
	newBall("GillLine" .. i, Vector3.new(0.07, 0.32, 0.07), ORIGIN * CFrame.new(x, -0.1, -2.6), Color3.fromRGB(8, 8, 14), Enum.Material.SmoothPlastic, model)
end

-- 3) Große, fächerartige Rückenflosse (2 überlappende flache Ellipsen) --------
newBall("DorsalFin", Vector3.new(0.24, 1.6, 1.5), ORIGIN * CFrame.new(0, 1.35, 0.3) * CFrame.Angles(0, 0, math.rad(-8)), BODY_COLOR, Enum.Material.SmoothPlastic, model)
newBall("DorsalFinTip", Vector3.new(0.16, 0.9, 0.9), ORIGIN * CFrame.new(0, 1.95, 0.55) * CFrame.Angles(0, 0, math.rad(-14)), BODY_LIGHT, Enum.Material.SmoothPlastic, model)

-- 4) Brust-/Bauchflossen (flache, fächerartige Ellipsen) -----------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall(
		"SideFin" .. i,
		Vector3.new(0.2, 0.55, 1.7),
		ORIGIN * CFrame.new(side * 1.1, -0.2, -0.8) * CFrame.Angles(0, 0, math.rad(side * -70)),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 5) Gegliederter Schwanzstiel + Schwanzflosse (überlappende Ellipsen) --------
newBall("TailPeduncle", Vector3.new(0.75, 0.75, 1.3), ORIGIN * CFrame.new(0, 0, 3.5), BODY_COLOR, Enum.Material.SmoothPlastic, model)
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newBall(
		"TailFin" .. i,
		Vector3.new(0.2, 1.4, 1.4),
		ORIGIN * CFrame.new(0, side * 0.6, 4.3) * CFrame.Angles(0, 0, math.rad(side * 62)),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 6) Leuchtend-violetter Streifen (Kopf bis Schwanz), schmaler, flacher Ellipsoid
local stripe = newBall("StripeGlow", Vector3.new(0.22, 0.22, 6.6), ORIGIN * CFrame.new(0, 0.82, 0.3), STRIPE_COLOR, Enum.Material.Neon, model)
stripe.Transparency = 0.05

-- 7) Große leuchtend-violette Kulleraugen an den Hammer-Enden -------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 3.05, 0.15, -3.15), Vector3.new(0.5, 0.5, 0.3), STRIPE_COLOR, model)
end

-- 8) Idle-Puls-Attachment -----------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Void Hammerhead")

print("[Abyssara] VoidHammerhead created under Workspace.Assets.Creatures")
