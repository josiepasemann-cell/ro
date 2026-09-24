--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: VoidHammerhead ("Leerenhammerhai")
	Rarity (Platzhalter): Legendary
	Beschreibung:
		Eckige Hammerhai-Silhouette, fast schwarzer Körper mit einem
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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("VoidHammerhead")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "VoidHammerhead"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(15, 15, 25)
local STRIPE_COLOR = Color3.fromRGB(160, 60, 255)

-- 1) Körper (eckig, langgestreckt) --------------------------------------------------
local body = newPart("Body", Vector3.new(2, 1.6, 6.5), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Hammerkopf (breiter Querbalken vorne) --------------------------------------------
newPart("HammerHead", Vector3.new(7, 0.9, 1.2), ORIGIN * CFrame.new(0, 0.1, -3.2), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 3) Rückenflosse -----------------------------------------------------------------------
local dorsalFin = Instance.new("WedgePart")
dorsalFin.Name = "DorsalFin"
dorsalFin.Size = Vector3.new(1.4, 1.6, 0.3)
dorsalFin.CFrame = ORIGIN * CFrame.new(0, 1.4, 0.5) * CFrame.Angles(0, math.rad(90), 0)
dorsalFin.Color = BODY_COLOR
dorsalFin.Material = Enum.Material.SmoothPlastic
dorsalFin.Anchored = true
dorsalFin.CanCollide = false
dorsalFin.Parent = model

-- 4) Schwanzflosse (2 Wedges) --------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local tailFin = Instance.new("WedgePart")
	tailFin.Name = "TailFin" .. i
	tailFin.Size = Vector3.new(0.25, 1.4, 1.4)
	tailFin.CFrame = ORIGIN * CFrame.new(0, side * 0.6, 3.4) * CFrame.Angles(0, 0, math.rad(side * 90))
	tailFin.Color = BODY_COLOR
	tailFin.Material = Enum.Material.SmoothPlastic
	tailFin.Anchored = true
	tailFin.CanCollide = false
	tailFin.Parent = model
end

-- 5) Leuchtend-violetter Streifen (Kopf bis Schwanz) -----------------------------------------
newPart("StripeGlow", Vector3.new(0.25, 0.25, 6.2), ORIGIN * CFrame.new(0, 0.85, 0.1), STRIPE_COLOR, Enum.Material.Neon, model)

-- 6) Leuchtende violette Augen an den Hammer-Enden -----------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eye = newPart(
		"Eye" .. i,
		Vector3.new(0.35, 0.35, 0.35),
		ORIGIN * CFrame.new(side * 3.3, 0.1, -3.2),
		STRIPE_COLOR,
		Enum.Material.Neon,
		model
	)
	eye.Shape = Enum.PartType.Ball
end

-- 7) Idle-Puls-Attachment -----------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Leerenhammerhai")

print("[Abyssara] VoidHammerhead erzeugt unter Workspace.Assets.Creatures")
