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

-- 2) Zwei Flügel: je 2 überlappende, flache, aufgefächerte Ellipsoide statt
--    WedgeParts, mit Regenbogen-Neon-Kante, direkt am Körper -----------------------
local wingRoots = {}
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	-- Wurzel liegt AUF der Körperoberfläche, Flügel wächst von dort nach außen
	-- -> stets überlappend mit dem Rumpf.
	local rootCFrame = ORIGIN * CFrame.new(side * 0.4, 0.12, 0.05) * CFrame.Angles(0, 0, math.rad(side * 16))
	local wingName = (i == 1) and "WingRight" or "WingLeft"

	local wingMain = newMeshBall(wingName, Vector3.new(0.9, 0.1, 1.0), rootCFrame * CFrame.new(side * 0.42, 0, 0.05), BODY_COLOR, Enum.Material.SmoothPlastic, model)
	newMeshBall(wingName .. "Fore", Vector3.new(0.6, 0.08, 0.7), rootCFrame * CFrame.new(side * 0.78, 0.02, -0.35) * CFrame.Angles(0, 0, math.rad(side * -10)), BODY_COLOR, Enum.Material.SmoothPlastic, model)
	wingRoots[i] = { cframe = wingMain.CFrame, side = side }

	-- Innerer Flügel-Fleck (Musterdetail), überlappt den Flügel selbst
	newMeshBall("WingSpot" .. i, Vector3.new(0.22, 0.08, 0.22), wingMain.CFrame * CFrame.new(side * 0.08, 0.05, -0.06), RAINBOW_COLORS[2], Enum.Material.Neon, model)

	-- Regenbogen-Kante: 3 kleine Neon-Ellipsoide ENTLANG der äußeren Flügelkante,
	-- jedes überlappt den Flügel selbst statt frei daneben zu schweben.
	for c = 1, 3 do
		local along = -0.32 + (c - 1) * 0.32
		local edgeCFrame = wingMain.CFrame * CFrame.new(side * 0.42, 0, along)
		newMeshBall(("WingEdge%d_%d"):format(i, c), Vector3.new(0.22, 0.09, 0.24), edgeCFrame, RAINBOW_COLORS[c], Enum.Material.Neon, model)
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

-- 3b) Große Cartoon-Augen: übergroße weiße Ellipsoide + Pupille + Glanzpunkt -------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.26, 0.17, 1.3)
	newMeshBall("EyeWhite" .. i, Vector3.new(0.3, 0.3, 0.24), eyeCFrame, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, model)
	newMeshBall("Eye" .. i, Vector3.new(0.17, 0.17, 0.14), eyeCFrame * CFrame.new(0, -0.01, 0.08), Color3.fromRGB(35, 25, 30), Enum.Material.SmoothPlastic, model)
	newMeshBall(
		"EyeHighlight" .. i,
		Vector3.new(0.06, 0.06, 0.05),
		eyeCFrame * CFrame.new(0.05, 0.05, 0.14),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.Neon,
		model
	)
end

-- 4) Zwei Fühler, Basis direkt auf dem Kopf ansetzend --------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local baseCFrame = ORIGIN * CFrame.new(side * 0.18, 0.35, 1.15) * CFrame.Angles(math.rad(-30 * side), 0, math.rad(-10 * side))
	newMeshBall(
		"Antenna" .. i,
		Vector3.new(0.1, 0.5, 0.1),
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
