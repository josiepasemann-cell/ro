--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: TreasureTurtle ("Treasure Turtle")
	Rarity (Platzhalter): Epic
	Event: TreasureTide
	Beschreibung:
		Schildkröten-Silhouette mit einem Panzer aus einem CSG-Union
		"Schatztruhen-Deckel"-Muster (gold mit teal-farbenen Einlage-Streifen)
		und einem kleinen leuchtenden Schlüsselloch-Detail (Neon) in der
		Panzermitte. Event-exklusive Kreatur des "Treasure Tide"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (schweres, langsames Paddel-Schwanken; Beine rotieren ±15° alternierend;
		  Schlüsselloch blitzt alle ~5s kurz auf).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("TreasureTide"), analog "Zone"
		  bei Zonen-Kreaturen.
		- Parts "LegFrontLeft".."LegBackRight" -> Ansatzpunkte für die spätere
		  Paddel-Animation.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 5, 120)
local RARITY = "Epic"
local ZONE = "Global"
local EVENT = "TreasureTide"
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

-- Block-Part + SpecialMesh(Sphere): echtes Ellipsoid statt der immer
-- kugelrunden Shape=Ball-Darstellung.
local function newMeshBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("TreasureTurtle")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TreasureTurtle"
model.Parent = creaturesFolder

local SHELL_GOLD = Color3.fromRGB(210, 170, 60)
local SHELL_TEAL = Color3.fromRGB(50, 140, 130)
local GLOW_COLOR = Color3.fromRGB(255, 220, 120)
local BODY_COLOR = Color3.fromRGB(70, 150, 90)
local BODY_COLOR_LIGHT = Color3.fromRGB(95, 180, 115)

-- 1) Körper: echtes Ellipsoid (Body = untere Panzer-/Körperbasis) -------------------
local body = newMeshBall("Body", Vector3.new(3.2, 1.4, 4.2), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Panzer: CSG-Union aus goldener Basis (Block, rundlich gewölbt) + teal-farbenen
--    Einlage-Streifen -> "Schatztruhen-Deckel". Die Basis bleibt bewusst ein Block
--    (kein Shape=Ball), damit die Union eine klare, kastenartige Truhenform behält
--    statt auf die kleinste Achse zur Kugel zusammenzuschrumpfen.
do
	local shellBase = Instance.new("Part")
	shellBase.Name = "ShellBase"
	shellBase.Size = Vector3.new(3.0, 1.5, 3.9)
	shellBase.CFrame = ORIGIN * CFrame.new(0, 0.75, 0)
	shellBase.Color = SHELL_GOLD
	shellBase.Material = Enum.Material.SmoothPlastic
	shellBase.Anchored = true
	shellBase.Parent = Workspace

	local shellDome = Instance.new("Part")
	shellDome.Name = "ShellDome"
	shellDome.Size = Vector3.new(2.6, 1.0, 3.4)
	shellDome.CFrame = ORIGIN * CFrame.new(0, 1.35, 0)
	shellDome.Color = SHELL_GOLD
	shellDome.Material = Enum.Material.SmoothPlastic
	shellDome.Anchored = true
	shellDome.Parent = Workspace
	local domeMesh = Instance.new("SpecialMesh")
	domeMesh.MeshType = Enum.MeshType.Sphere
	domeMesh.Parent = shellDome

	local stripeParts = { shellDome }
	for i = 1, 3 do
		local zOffset = -1.2 + (i - 1) * 1.2
		local stripe = Instance.new("Part")
		stripe.Name = "ShellStripe" .. i
		stripe.Size = Vector3.new(3.2, 0.5, 0.5)
		stripe.CFrame = ORIGIN * CFrame.new(0, 1.5, zOffset)
		stripe.Color = SHELL_TEAL
		stripe.Material = Enum.Material.SmoothPlastic
		stripe.Anchored = true
		stripe.Parent = Workspace
		table.insert(stripeParts, stripe)
	end

	local shellUnion = shellBase:UnionAsync(stripeParts)
	shellUnion.Name = "Shell"
	shellUnion.Color = SHELL_GOLD
	shellUnion.Material = Enum.Material.SmoothPlastic
	shellUnion.Anchored = true
	shellUnion.CanCollide = false
	shellUnion.Parent = model

	shellBase:Destroy()
	for _, stripe in ipairs(stripeParts) do
		stripe:Destroy()
	end
end

-- 2b) Panzerrand (Rim), umläuft den unteren Panzerrand, überlappt Panzer + Körper ---
local shellRim = newPart(
	"ShellRim",
	Vector3.new(3.15, 0.35, 4.05),
	ORIGIN * CFrame.new(0, 0.55, 0),
	Color3.fromRGB(180, 145, 45),
	Enum.Material.Metal,
	model
)

-- 3) Leuchtendes Schlüsselloch-Detail (Panzermitte) ----------------------------------
local keyhole = newPart(
	"KeyholeDetail",
	Vector3.new(0.35, 0.12, 0.5),
	ORIGIN * CFrame.new(0, 1.7, 0),
	GLOW_COLOR,
	Enum.Material.Neon,
	model
)

-- 4) Kopf, im vorderen Körperbereich eingesenkt ---------------------------------------
local head = newMeshBall(
	"Head",
	Vector3.new(0.9, 0.9, 0.9),
	ORIGIN * CFrame.new(0, 0.05, 1.85),
	BODY_COLOR,
	Enum.Material.SmoothPlastic,
	model
)

-- 4b) Zwei Augen mit Glanzpunkt -------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.28, 0.2, 2.2)
	newMeshBall("Eye" .. i, Vector3.new(0.18, 0.18, 0.18), eyeCFrame, Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic, model)
	newMeshBall(
		"EyeHighlight" .. i,
		Vector3.new(0.06, 0.06, 0.06),
		eyeCFrame * CFrame.new(0.04, 0.04, 0.08),
		Color3.fromRGB(255, 255, 255),
		Enum.Material.Neon,
		model
	)
end

-- 4c) Kleiner Schnabel-Akzent vorne am Kopf, überlappt Kopf + Körper -----------------
local beak = newPart(
	"BeakDetail",
	Vector3.new(0.5, 0.3, 0.3),
	ORIGIN * CFrame.new(0, -0.05, 2.35),
	BODY_COLOR_LIGHT,
	Enum.Material.SmoothPlastic,
	model
)

-- 5) Vier Beine (paddelförmig), Wurzel im Körper eingesenkt --------------------------
local legPositions = {
	{ "LegFrontLeft", 1.0, 1.4 },
	{ "LegFrontRight", -1.0, 1.4 },
	{ "LegBackLeft", 1.0, -1.5 },
	{ "LegBackRight", -1.0, -1.5 },
}
for _, legData in ipairs(legPositions) do
	local legName, xOff, zOff = legData[1], legData[2], legData[3]
	local leg = Instance.new("WedgePart")
	leg.Name = legName
	leg.Size = Vector3.new(0.65, 0.35, 1.05)
	leg.CFrame = ORIGIN * CFrame.new(xOff, -0.15, zOff)
	leg.Color = BODY_COLOR
	leg.Material = Enum.Material.SmoothPlastic
	leg.Anchored = true
	leg.CanCollide = false
	leg.TopSurface = Enum.SurfaceType.Smooth
	leg.BottomSurface = Enum.SurfaceType.Smooth
	leg.Parent = model
end

-- 6) Kurzer Schwanzstummel hinten, überlappt den Körper -------------------------------
local tail = newMeshBall(
	"TailStub",
	Vector3.new(0.5, 0.4, 0.5),
	ORIGIN * CFrame.new(0, -0.1, -2.1),
	BODY_COLOR,
	Enum.Material.SmoothPlastic,
	model
)

-- 7) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Treasure Turtle")

print("[Abyssara] TreasureTurtle created under Workspace.Assets.Creatures")
