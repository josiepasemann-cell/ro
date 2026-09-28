--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: TreasureTurtle ("Treasure Turtle")
	Rarity (Platzhalter): Epic
	Event: TreasureTide
	Beschreibung (Update: organisch/cartoony statt Box-Silhouette):
		Chunky Cartoon-Schildkröte: klar erkennbarer, kugelig-gewölbter
		Ellipsoid-Panzer (gold, aus 3 überlappenden Ellipsoiden statt CSG-Box),
		schmale teal-farbene Bänder als Panzernähte, deutlicher, weit nach
		vorne herausragender Kopf auf kurzem Hals, große Cartoon-Augen,
		stummelige Ellipsoid-Flipper an allen vier Ecken. Event-exklusive
		Kreatur des "Treasure Tide"-Events.

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
-- kugelrunden Shape=Ball-Darstellung - EINZIGE Grundform in diesem Skript
-- (Panzer, Kopf, Flipper, Bänder) für eine durchgehend organische Silhouette.
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

local SHELL_GOLD = Color3.fromRGB(215, 175, 60)
local SHELL_TEAL = Color3.fromRGB(50, 145, 130)
local GLOW_COLOR = Color3.fromRGB(255, 220, 120)
local BODY_COLOR = Color3.fromRGB(75, 155, 95)
local BODY_COLOR_LIGHT = Color3.fromRGB(100, 185, 120)

-- 1) Körper: chunky Ellipsoid (untere Panzer-/Körperbasis) -------------------------
local body = newMeshBall("Body", Vector3.new(3.4, 1.6, 4.4), ORIGIN, BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 2) Panzer: 2 überlappende, sich verjüngende gold Ellipsoide -> klar gewölbte,
--    kuppelförmige Panzersilhouette statt Box/CSG. -----------------------------
local shellLower = newMeshBall("ShellLower", Vector3.new(3.3, 1.6, 4.1), ORIGIN * CFrame.new(0, 0.55, -0.1), SHELL_GOLD, Enum.Material.Slate, model)
local shell = newMeshBall("Shell", Vector3.new(2.7, 1.7, 3.5), ORIGIN * CFrame.new(0, 1.15, -0.1), SHELL_GOLD, Enum.Material.Slate, model)
newMeshBall("ShellCap", Vector3.new(1.7, 0.9, 2.2), ORIGIN * CFrame.new(0, 1.85, -0.1), SHELL_GOLD, Enum.Material.Slate, model)

-- 2b) Zwei schmale, gebogene teal Panzernähte (flache Ellipsoid-Bänder statt Box-
--     Streifen), hugging die Panzeroberfläche ---------------------------------
for i = 1, 2 do
	local zOffset = (i - 1) * 1.5 - 0.75
	newMeshBall(
		"ShellSeam" .. i,
		Vector3.new(2.75, 0.32, 0.5),
		ORIGIN * CFrame.new(0, 1.55, zOffset),
		SHELL_TEAL,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 2c) Panzerrand-Kragen (stark abgeflachtes Ellipsoid statt Box-Rim), umläuft den
--     unteren Panzerrand, überlappt Panzer + Körper -----------------------------
newMeshBall("ShellRim", Vector3.new(3.5, 0.45, 4.35), ORIGIN * CFrame.new(0, 0.35, -0.1), Color3.fromRGB(190, 155, 50), Enum.Material.Foil, model)

-- 3) Leuchtendes Schlüsselloch-Detail (Panzermitte) ----------------------------------
newMeshBall("KeyholeDetail", Vector3.new(0.4, 0.14, 0.5), ORIGIN * CFrame.new(0, 1.95, -0.1), GLOW_COLOR, Enum.Material.Neon, model)

-- 4) Kurzer Hals + großer, deutlich sichtbarer Kopf, weit vor dem Panzer -------------
local neck = newMeshBall("Neck", Vector3.new(1.0, 0.9, 1.0), ORIGIN * CFrame.new(0, 0.3, 1.75), BODY_COLOR, Enum.Material.SmoothPlastic, model)
local head = newMeshBall("Head", Vector3.new(1.5, 1.35, 1.4), ORIGIN * CFrame.new(0, 0.45, 2.55), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 4b) Große Cartoon-Augen: übergroße weiße Ellipsoide + Pupille + Glanzpunkt --------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.5, 0.65, 3.05)
	newMeshBall("EyeWhite" .. i, Vector3.new(0.5, 0.5, 0.4), eyeCFrame, Color3.fromRGB(250, 252, 245), Enum.Material.SmoothPlastic, model)
	newMeshBall("Eye" .. i, Vector3.new(0.28, 0.28, 0.24), eyeCFrame * CFrame.new(0, 0, 0.18), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic, model)
	newMeshBall("EyeHighlight" .. i, Vector3.new(0.1, 0.1, 0.08), eyeCFrame * CFrame.new(0.08, 0.08, 0.3), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	newMeshBall("Blush" .. i, Vector3.new(0.32, 0.18, 0.2), eyeCFrame * CFrame.new(0, -0.4, -0.05), Color3.fromRGB(255, 165, 150), Enum.Material.SmoothPlastic, model)
end

-- 4c) Kleiner Schnabel-Akzent (Ellipsoid statt Box), vorne am Kopf ------------------
newMeshBall("BeakDetail", Vector3.new(0.55, 0.35, 0.4), ORIGIN * CFrame.new(0, 0.1, 3.2), BODY_COLOR_LIGHT, Enum.Material.SmoothPlastic, model)

-- 4d) Cartoon-Lächeln unter dem Schnabel (dünnes Ellipsoid) -------------------------
newMeshBall("HeadSmile", Vector3.new(0.5, 0.1, 0.15), ORIGIN * CFrame.new(0, -0.15, 3.28) * CFrame.Angles(math.rad(10), 0, 0), Color3.fromRGB(40, 60, 35), Enum.Material.SmoothPlastic, model)

-- 5) Vier stummelige Flipper: je 2 überlappende, sich verjüngende Ellipsoide -------
local legPositions = {
	{ "LegFrontLeft", 1.5, 1.3, 1 },
	{ "LegFrontRight", -1.5, 1.3, -1 },
	{ "LegBackLeft", 1.45, -1.6, 1 },
	{ "LegBackRight", -1.45, -1.6, -1 },
}
for _, legData in ipairs(legPositions) do
	local legName, xOff, zOff, side = legData[1], legData[2], legData[3], legData[4]
	local root = ORIGIN * CFrame.new(xOff * 0.62, -0.25, zOff)
	newMeshBall(legName, Vector3.new(0.95, 0.55, 1.3), root, BODY_COLOR, Enum.Material.SmoothPlastic, model)
	newMeshBall(legName .. "Tip", Vector3.new(0.7, 0.4, 0.85), root * CFrame.new(side * 0.6, -0.05, 0), BODY_COLOR_LIGHT, Enum.Material.SmoothPlastic, model)
end

-- 6) Kurzer, rundlicher Schwanzstummel hinten, überlappt den Körper -------------------
newMeshBall("TailStub", Vector3.new(0.6, 0.5, 0.6), ORIGIN * CFrame.new(0, -0.05, -2.2), BODY_COLOR, Enum.Material.SmoothPlastic, model)

-- 7) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

-- The parts above were laid out facing +Z, but the game treats the body's
-- LookVector (-Z) as the front, so turn everything except the body half a
-- circle around it.
do
	local flip = body.CFrame * CFrame.Angles(0, math.pi, 0) * body.CFrame:Inverse()
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= body then
			part.CFrame = flip * part.CFrame
		end
	end
end

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Treasure Turtle")

print("[Abyssara] TreasureTurtle created under Workspace.Assets.Creatures")
