--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GhostFinTuna ("Geisterflossen-Thun")
	Rarity (Platzhalter): Epic
	Beschreibung:
		Stromlinienförmiger, torpedoartiger Körper, blass blau-weiß, mit
		halbtransparenten Flossen (Glass). Zone: HadalDepths.

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

-- 1) Torpedoförmiger Körper ---------------------------------------------------------
local body = newPart("Body", Vector3.new(1.8, 1.8, 5.4), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Kopf-Verjüngung (spitzer nach vorne) -----------------------------------------------
local nose = Instance.new("WedgePart")
nose.Name = "Nose"
nose.Size = Vector3.new(1.4, 1.2, 1.0)
nose.CFrame = ORIGIN * CFrame.new(0, 0, -3.0) * CFrame.Angles(0, math.rad(90), 0)
nose.Color = BODY_COLOR
nose.Material = Enum.Material.SmoothPlastic
nose.Anchored = true
nose.CanCollide = false
nose.Parent = model

-- 3) Rückenflosse ---------------------------------------------------------------------------
local dorsalFin = Instance.new("WedgePart")
dorsalFin.Name = "DorsalFin"
dorsalFin.Size = Vector3.new(1.0, 1.2, 0.2)
dorsalFin.CFrame = ORIGIN * CFrame.new(0, 1.1, 0.3) * CFrame.Angles(0, math.rad(90), 0)
dorsalFin.Color = BODY_COLOR
dorsalFin.Material = Enum.Material.Glass
dorsalFin.Transparency = 0.35
dorsalFin.Anchored = true
dorsalFin.CanCollide = false
dorsalFin.Parent = model

-- 4) Zwei Seitenflossen (halbtransparent) ------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local fin = newPart(
		"SideFin" .. i,
		Vector3.new(0.15, 0.6, 1.2),
		ORIGIN * CFrame.new(side * 1.0, -0.1, 0.4) * CFrame.Angles(0, 0, math.rad(side * 20)),
		BODY_COLOR,
		Enum.Material.Glass,
		model
	)
	fin.Transparency = 0.4
end

-- 5) Schwanzflosse (2 Wedges) ------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local tailFin = Instance.new("WedgePart")
	tailFin.Name = "TailFin" .. i
	tailFin.Size = Vector3.new(0.15, 1.0, 1.0)
	tailFin.CFrame = ORIGIN * CFrame.new(0, side * 0.5, 2.9) * CFrame.Angles(0, 0, math.rad(side * 90))
	tailFin.Color = BODY_COLOR
	tailFin.Material = Enum.Material.Glass
	tailFin.Transparency = 0.35
	tailFin.Anchored = true
	tailFin.CanCollide = false
	tailFin.Parent = model
end

-- 6) Idle-Puls-Attachment -----------------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Ghost Fin Tuna")

print("[Abyssara] GhostFinTuna created under Workspace.Assets.Creatures")
