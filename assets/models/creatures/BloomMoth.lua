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

-- Block-Part + SpecialMesh(Sphere): rendert eine ECHTE Ellipsoid-Form (anders
-- als Shape=Ball, das Roblox immer als perfekte Kugel mit der KLEINSTEN
-- Size-Achse als Durchmesser zeichnet).
local function newMeshBall(name, size, cframe, color, material, parent)
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

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = part

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
local BELLY_COLOR = Color3.fromRGB(255, 230, 245)
local RAINBOW_COLORS = {
	Color3.fromRGB(80, 230, 255), -- cyan
	Color3.fromRGB(230, 90, 255), -- magenta
	Color3.fromRGB(160, 255, 90), -- lime
}

-- 1) Körper: echtes Ellipsoid (Block + SpecialMesh Sphere) --------------------------
local body = newMeshBall("Body", Vector3.new(1.0, 0.9, 2.0), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Helle Bauchunterseite, überlappt den Körper -----------------------------------
local belly = newMeshBall(
	"Belly",
	Vector3.new(0.75, 0.55, 1.7),
	ORIGIN * CFrame.new(0, -0.28, 0.05),
	BELLY_COLOR,
	Enum.Material.SmoothPlastic,
	model
)

-- 2) Zwei Flügel (WedgePart-Paare) mit Regenbogen-Neon-Kante, direkt am Körper -------
local wingRoots = {}
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	-- Wurzel liegt AUF der Körperoberfläche (x-Halbachse 0.5), Flügel wächst
	-- von dort nach außen -> stets überlappend mit dem Rumpf.
	local rootCFrame = ORIGIN * CFrame.new(side * 0.42, 0.15, 0.1) * CFrame.Angles(0, 0, math.rad(side * 18))

	local wing = Instance.new("WedgePart")
	wing.Name = (i == 1) and "WingRight" or "WingLeft"
	wing.Size = Vector3.new(1.7, 0.1, 1.5)
	wing.CFrame = rootCFrame * CFrame.new(side * 0.75, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	wing.Color = BODY_COLOR
	wing.Material = Enum.Material.SmoothPlastic
	wing.Anchored = true
	wing.CanCollide = false
	wing.TopSurface = Enum.SurfaceType.Smooth
	wing.BottomSurface = Enum.SurfaceType.Smooth
	wing.Parent = model
	wingRoots[i] = { cframe = wing.CFrame, side = side }

	-- Innerer Flügel-Fleck (Musterdetail), überlappt den Flügel selbst
	local spot = newMeshBall(
		"WingSpot" .. i,
		Vector3.new(0.4, 0.05, 0.4),
		wing.CFrame * CFrame.new(side * 0.1, 0.06, -0.1),
		RAINBOW_COLORS[2],
		Enum.Material.Neon,
		model
	)

	-- Regenbogen-Kante: 3 kleine Neon-Segmente ENTLANG der äußeren Flügelkante,
	-- jedes überlappt den WedgePart selbst statt frei daneben zu schweben.
	for c = 1, 3 do
		local along = -0.55 + (c - 1) * 0.55
		local edgeCFrame = wing.CFrame * CFrame.new(side * 0.78, 0, along)
		newPart(
			("WingEdge%d_%d"):format(i, c),
			Vector3.new(0.45, 0.09, 0.4),
			edgeCFrame,
			RAINBOW_COLORS[c],
			Enum.Material.Neon,
			model
		)
	end
end

-- 3) Kopf-Kapsel (klein, vorne am Körper, für Augen/Fühler-Ansatz) ------------------
local head = newMeshBall(
	"Head",
	Vector3.new(0.65, 0.6, 0.55),
	ORIGIN * CFrame.new(0, 0.05, 1.05),
	BODY_COLOR,
	Enum.Material.SmoothPlastic,
	model
)

-- 3b) Zwei Augen mit Glanzpunkt ------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.24, 0.15, 1.32)
	local eye = newMeshBall("Eye" .. i, Vector3.new(0.18, 0.18, 0.18), eyeCFrame, Color3.fromRGB(30, 20, 25), Enum.Material.SmoothPlastic, model)
	newMeshBall(
		"EyeHighlight" .. i,
		Vector3.new(0.06, 0.06, 0.06),
		eyeCFrame * CFrame.new(0.05, 0.05, 0.09),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.Neon,
		model
	)
end

-- 4) Zwei Fühler, Basis direkt auf dem Kopf ansetzend --------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local baseCFrame = ORIGIN * CFrame.new(side * 0.18, 0.35, 1.15) * CFrame.Angles(math.rad(-30 * side), 0, math.rad(-10 * side))
	newPart(
		"Antenna" .. i,
		Vector3.new(0.09, 0.55, 0.09),
		baseCFrame * CFrame.new(0, 0.25, 0),
		Color3.fromRGB(255, 220, 240),
		Enum.Material.Neon,
		model
	)
	-- kleine leuchtende Fühlerspitze, überlappt das Fühler-Ende
	newMeshBall(
		"AntennaTip" .. i,
		Vector3.new(0.14, 0.14, 0.14),
		baseCFrame * CFrame.new(0, 0.5, 0),
		RAINBOW_COLORS[3],
		Enum.Material.Neon,
		model
	)
end

-- 5) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Bloom Moth")

print("[Abyssara] BloomMoth created under Workspace.Assets.Creatures")
