--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur (Event-exklusiv)
	Name: GoldGuppy ("Gold Guppy")
	Rarity (Platzhalter): Rare
	Event: TreasureTide
	Beschreibung (Update: organisch/cartoony, echter Fächerschwanz):
		Kleine, chunky Cartoon-Fisch-Silhouette, metallisch goldener
		Ellipsoid-Körper (Material Metal/Foil) mit einem ECHTEN Fächerschwanz
		aus 3 überlappenden, dünnen, aufgefächerten Ellipsoid-Lamellen (statt
		einer flachen leuchtenden Planke) und großen Cartoon-Augen.
		Event-exklusive Kreatur des "Treasure Tide"-Events.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Animation
		  (kurze, schnelle "Dart"-Bewegungsstöße alle 2-3s, sonst regungslos).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Event") -> Event-Id ("TreasureTide"), analog "Zone"
		  bei Zonen-Kreaturen.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(5, 6, 120)
local RARITY = "Rare"
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
-- kugelrunden Shape=Ball-Darstellung - EINZIGE Grundform hier (Körper,
-- Flossen, Fächerschwanz-Lamellen).
local function newMeshBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("GoldGuppy")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GoldGuppy"
model.Parent = creaturesFolder

local GOLD_COLOR = Color3.fromRGB(235, 195, 75)
local GOLD_COLOR_DARK = Color3.fromRGB(195, 155, 55)
local GLOW_COLOR = Color3.fromRGB(255, 230, 130)

-- 1) Chunky, rundlicher torpedoförmiger Körper (Ellipsoid, Material Foil für
--    glänzenden Goldglanz) -----------------------------------------------------
local body = newMeshBall("Body", Vector3.new(1.15, 1.25, 1.75), ORIGIN, GOLD_COLOR, Enum.Material.Foil, model)

-- 1b) Kleine, stummelige Rückenflosse (flaches Ellipsoid statt Wedge), überlappt
--     den Körper -----------------------------------------------------------------
local dorsalFin = newMeshBall("DorsalFin", Vector3.new(0.16, 0.55, 0.6), ORIGIN * CFrame.new(0, 0.75, 0.1) * CFrame.Angles(math.rad(-20), 0, 0), GOLD_COLOR_DARK, Enum.Material.Foil, model)

-- 1c) Große Cartoon-Augen: übergroße weiße Ellipsoide + Pupille + Glanzpunkt -------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.4, 0.22, 0.75)
	newMeshBall("EyeWhite" .. i, Vector3.new(0.32, 0.32, 0.26), eyeCFrame, Color3.fromRGB(250, 252, 245), Enum.Material.SmoothPlastic, model)
	newMeshBall("Eye" .. i, Vector3.new(0.19, 0.19, 0.15), eyeCFrame * CFrame.new(0, -0.01, 0.1), Color3.fromRGB(20, 20, 25), Enum.Material.SmoothPlastic, model)
	newMeshBall("EyeHighlight" .. i, Vector3.new(0.07, 0.07, 0.05), eyeCFrame * CFrame.new(0.05, 0.05, 0.16), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
end

-- 2) Echter Fächerschwanz: 3 überlappende, dünne, aufgefächerte Ellipsoid-Lamellen,
--    Wurzel im Körper eingesenkt, Winkel zwischen -28° und +28° für die Fächerform,
--    Größe wächst von der Wurzel zur Spitze -> deutlich als Fächer statt Planke ----
local tailRoot = ORIGIN * CFrame.new(0, 0, -0.75)
local TAIL_ANGLES = { -28, 0, 28 }
for i, angleDeg in ipairs(TAIL_ANGLES) do
	local lamellaCFrame = tailRoot * CFrame.Angles(0, math.rad(angleDeg), 0)
	-- dünnes, hohes, LANGES Ellipsoid (Länge auf lokaler Z, nach hinten weisend)
	local lamella = newMeshBall(
		"TailLamella" .. i,
		Vector3.new(0.16, 0.5, 0.85),
		lamellaCFrame * CFrame.new(0, 0, -0.4),
		i == 2 and GOLD_COLOR or GOLD_COLOR_DARK,
		Enum.Material.Foil,
		model
	)
	-- leuchtende Lamellen-Spitze, überlappt das hintere Ende der Lamelle
	newMeshBall(
		"TailLamella" .. i .. "Tip",
		Vector3.new(0.13, 0.24, 0.3),
		lamellaCFrame * CFrame.new(0, 0, -0.75),
		GLOW_COLOR,
		Enum.Material.Neon,
		model
	)
end
-- Name "TailFin" bleibt als IdleSway-Sway-Anker erhalten (Präfix "tailfin"),
-- deckt die mittlere Lamelle zusätzlich mit ab, damit vorhandene Sway-Logik
-- weiter genau EINEN benannten "TailFin"-Part findet.
local tailFinAnchor = newMeshBall("TailFin", Vector3.new(0.3, 0.3, 0.3), tailRoot, GOLD_COLOR, Enum.Material.Foil, model)
tailFinAnchor.Transparency = 1

-- 3) Zwei kleine Seitenflossen (flache Ellipsoide statt Wedges), Wurzel im Körper
--    eingesenkt -------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newMeshBall("SideFin" .. i, Vector3.new(0.45, 0.14, 0.4), ORIGIN * CFrame.new(side * 0.42, -0.12, 0.15) * CFrame.Angles(0, 0, math.rad(side * 25)), GOLD_COLOR, Enum.Material.Foil, model)
end

-- 4) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("Event", EVENT)
model:SetAttribute("CreatureName", "Gold Guppy")

print("[Abyssara] GoldGuppy created under Workspace.Assets.Creatures")
