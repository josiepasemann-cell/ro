--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Raid-Gegner
	Name: SpineDrifter ("Spine Drifter")
	Ersetzt ShadowKraken als TemplateName für RaidConfig.EnemyId "Drifter".
	Beschreibung:
		Schlanker, spindeldürrer aalartiger Körper, dunkles Schiefer-Blau,
		dünne Rückenstacheln, rote Glow-Augenschlitze. Dünne Silhouette
		kommuniziert Zerbrechlichkeit - schneller, schwacher "Skirmisher".

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für serverseitige
		  Bewegungs-/Angriffssteuerung (analog zu HumanoidRootPart).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-/
		  Bedrohungs-Puls-Animation.
		- "Mantle", "Eye1", "Eye2" vorhanden -> RaidService.applyEnemyVisual()
		  überschreibt Body/Mantle.Color mit definition.BodyColor und
		  Eye1/Eye2.Color mit definition.EyeColor zur Laufzeit (siehe
		  src/server/RaidService.lua). Hier verwendete Farben sind daher nur
		  Vorschau-Platzhalter, keine Gameplay-Wahrheit.
		- model:SetAttribute("EnemyTier") -> "Trash" (schwacher Skirmisher).
		- model:SetAttribute("Zone") -> Ziel-Zone, in der der Gegner auftaucht.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 5, -60) -- Vor Ausführung anpassen für gewünschte Position
local ENEMY_TIER = "Trash"
local ZONE = "TwilightZone"
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

-- Texture-Instanz mit Projekt-Texturschlüssel (siehe assets/textures/README.md).
-- "FadeWithPart" = true, da der Client Gegner per Transparency/ScaleTo ein-
-- und ausblendet - der Animator muss diese Texturen mitfaden.
local function newTexture(key, face, part, opts)
	opts = opts or {}
	local tex = Instance.new("Texture")
	tex.Name = "Tex_" .. key
	tex.Texture = ""
	tex.Face = face
	tex.StudsPerTileU = opts.studsU or 3
	tex.StudsPerTileV = opts.studsV or 3
	tex.Color3 = opts.color or Color3.new(1, 1, 1)
	tex.Transparency = opts.transparency or 0
	tex:SetAttribute("TextureKey", key)
	tex:SetAttribute("FadeWithPart", true)
	CollectionService:AddTag(tex, "KeyedTexture")
	tex.Parent = part
	return tex
end

-- Organisches, ovales/kapselförmiges Teil: Block-Part + SpecialMesh(Sphere),
-- non-uniform Size -> gestrecktes Ellipsoid statt Kiste. Für Gliedmaßen,
-- Flossen, Schwanz (kartoonig rund statt eckig).
local function newOvalPart(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = part
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local enemiesFolder = getOrCreateFolder(assetsFolder, "Enemies")

local previous = enemiesFolder:FindFirstChild("SpineDrifter")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "SpineDrifter"
model.Parent = enemiesFolder

local SKIN_COLOR = Color3.fromRGB(40, 60, 70)
local ACCENT_COLOR = Color3.fromRGB(28, 44, 52)
local EYE_COLOR = Color3.fromRGB(255, 60, 80)

-- 1) Hauptkörper: schlanker, langgezogener, ovaler Rumpf (Ellipsoid) ------------
local body = newOvalPart("Body", Vector3.new(1.5, 1.5, 4.0), ORIGIN, SKIN_COLOR, Enum.Material.Pebble, model)

-- Countershading: heller Bauchstreifen entlang der Unterseite (überlappt Body)
newOvalPart("BellyStripe", Vector3.new(0.65, 0.4, 3.6), ORIGIN * CFrame.new(0, -0.65, 0.1), Color3.fromRGB(120, 150, 160), Enum.Material.Pebble, model)

-- 2) Kopf-/Mantel-Verjüngung vorn: großer, kartoonig runder Kopf -----------------
local mantleCFrame = ORIGIN * CFrame.new(0, 0.15, -2.1)
local mantle = newOvalPart("Mantle", Vector3.new(1.3, 1.2, 1.5), mantleCFrame, ACCENT_COLOR, Enum.Material.Pebble, model)

-- 3) Große, freundlich-fiese Glow-Augen mit weißem Glanzpunkt --------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.5, 0.2, -2.6)
	local eye = newPart("Eye" .. i, Vector3.new(0.45, 0.45, 0.28), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
	local highlight = newPart("Eye" .. i .. "Highlight", Vector3.new(0.14, 0.14, 0.1), eyeCFrame * CFrame.new(side * -0.1, 0.1, 0.12), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	highlight.Shape = Enum.PartType.Ball
end

-- 4) Dünne, gerundete Rückenstacheln (6 Stück, abnehmend zum Schwanz) -------------
for i = 1, 6 do
	local z = -1.7 + (i - 1) * 0.75
	local spineHeight = 0.7 - i * 0.05
	local spineCFrame = ORIGIN * CFrame.new(0, 0.85, z) * CFrame.Angles(math.rad(90), 0, 0)
	newOvalPart(
		"DorsalSpine" .. i,
		Vector3.new(0.22, spineHeight, 0.55),
		spineCFrame,
		i % 2 == 0 and ACCENT_COLOR or EYE_COLOR,
		i % 2 == 0 and Enum.Material.SmoothPlastic or Enum.Material.Neon,
		model
	)
end

-- 5) Seitliche Steuerflossen: dünne, flach gedrückte Ellipsoide, angestellt -------
for _, side in ipairs({ -1, 1 }) do
	local finCFrame = ORIGIN * CFrame.new(side * 0.75, -0.1, -0.3) * CFrame.Angles(0, 0, math.rad(side * 20))
	newOvalPart(
		"SideFin" .. (side < 0 and "L" or "R"),
		Vector3.new(0.9, 0.18, 1.0),
		finCFrame,
		ACCENT_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
end

-- 6) Schwanzstiel (verjüngendes ovales Segment, schließt die Lücke Body -> Flosse) --
newOvalPart("TailStalk", Vector3.new(0.55, 0.55, 1.3), ORIGIN * CFrame.new(0, 0, 2.45), ACCENT_COLOR, Enum.Material.SmoothPlastic, model)

-- 7) Schwanzflosse (überlappt den Stiel, gefächerte flache Ellipsoide) -----------
local tailBaseCFrame = ORIGIN * CFrame.new(0, 0, 2.9)
newOvalPart("TailFin", Vector3.new(0.18, 1.2, 1.1), tailBaseCFrame, ACCENT_COLOR, Enum.Material.SmoothPlastic, model)
newOvalPart("TailFinLower", Vector3.new(0.16, 0.7, 0.8), tailBaseCFrame * CFrame.new(0, -0.55, 0.1), EYE_COLOR, Enum.Material.Neon, model)

-- 8) Idle-/Bedrohungs-Puls-Attachment -------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("EnemyTier", ENEMY_TIER)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("EnemyName", "Spine Drifter")

print("[Abyssara] SpineDrifter created under Workspace.Assets.Enemies")
