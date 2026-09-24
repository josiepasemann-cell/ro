--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: BloomMoth ("Bloom Moth")
	Rarity (Platzhalter): Uncommon
	Event: BioluminescentBloom
	Beschreibung:
		Kleiner geflügelter Meeresschnecken-/Motten-Hybrid, pastellfarbener
		Körper mit zwei großen Flossen-Flügeln, deren Kante einen
		regenbogenfarbenen Neon-Verlauf (cyan -> magenta -> lime) simuliert
		(mehrere kurze Neon-Segmente je Flügelkante). Event-exklusive Kreatur
		des "Bioluminescent Bloom"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (Flügelschlag ±25° auf 1s-Zyklus, sanftes Auf-/Ab-Wippen, siehe Doc).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("BioluminescentBloom"), analog
		  "Zone" bei Zonen-Kreaturen.
		- Parts "WingLeft" / "WingRight" -> Ansatzpunkte für die spätere
		  Flügelschlag-Rotation.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(5, 6, 105)
local RARITY = "Uncommon"
local ZONE = "Global"
local EVENT = "BioluminescentBloom"
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

local previous = creaturesFolder:FindFirstChild("BloomMoth")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "BloomMoth"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(255, 200, 230)
local RAINBOW_COLORS = {
	Color3.fromRGB(80, 230, 255), -- cyan
	Color3.fromRGB(230, 90, 255), -- magenta
	Color3.fromRGB(160, 255, 90), -- lime
}

-- 1) Körper -------------------------------------------------------------------------
local body = newPart("Body", Vector3.new(0.9, 0.8, 2), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Zwei Flügel (WedgePart-Paare) mit Regenbogen-Neon-Kante -------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local wingCFrame = ORIGIN * CFrame.new(side * 0.6, 0.3, 0) * CFrame.Angles(0, 0, math.rad(side * 20))

	local wing = Instance.new("WedgePart")
	wing.Name = (i == 1) and "WingRight" or "WingLeft"
	wing.Size = Vector3.new(1.6, 0.1, 1.4)
	wing.CFrame = wingCFrame * CFrame.Angles(0, math.rad(90), 0)
	wing.Color = BODY_COLOR
	wing.Material = Enum.Material.SmoothPlastic
	wing.Anchored = true
	wing.CanCollide = false
	wing.TopSurface = Enum.SurfaceType.Smooth
	wing.BottomSurface = Enum.SurfaceType.Smooth
	wing.Parent = model

	-- Regenbogen-Kante: 3 kleine Neon-Segmente entlang der Flügelaußenkante
	for c = 1, 3 do
		local edgeOffset = wingCFrame * CFrame.new(side * (0.5 + c * 0.4), 0, -0.5 + c * 0.5)
		local edge = newPart(
			("WingEdge%d_%d"):format(i, c),
			Vector3.new(0.5, 0.1, 0.3),
			edgeOffset,
			RAINBOW_COLORS[c],
			Enum.Material.Neon,
			model
		)
	end
end

-- 3) Zwei Fühler -------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newPart(
		"Antenna" .. i,
		Vector3.new(0.1, 0.6, 0.1),
		ORIGIN * CFrame.new(side * 0.2, 0.6, 0.9) * CFrame.Angles(math.rad(-25 * side), 0, 0),
		Color3.fromRGB(255, 220, 240),
		Enum.Material.Neon,
		model
	)
end

-- 4) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Bloom Moth")

print("[Abyssara] BloomMoth erzeugt unter Workspace.Assets.Creatures")
