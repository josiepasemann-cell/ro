--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Raid-Gegner
	Name: ThornSwarmer ("Thorn Swarmer")
	Ersetzt ShadowKraken als TemplateName für RaidConfig.EnemyId "Swarmer".
	Beschreibung:
		Kleiner, kompakter Seeigel-Fisch-Hybrid mit radial abstehenden
		Dornstacheln, dunkles Türkis, orange Glow-Augen. Rundliche,
		kompakte Silhouette kommuniziert "zahlreich und lästig" -
		passend zur Schwarm-Rolle.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für serverseitige
		  Bewegungs-/Angriffssteuerung (analog zu HumanoidRootPart).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-/
		  Bedrohungs-Puls-Animation.
		- "Mantle", "Eye1", "Eye2" vorhanden -> RaidService.applyEnemyVisual()
		  überschreibt Body/Mantle.Color mit definition.BodyColor und
		  Eye1/Eye2.Color mit definition.EyeColor zur Laufzeit. Hier
		  verwendete Farben sind daher nur Vorschau-Platzhalter.
		- model:SetAttribute("EnemyTier") -> "Trash" (Schwarm-Einheit).
		- model:SetAttribute("Zone") -> Ziel-Zone, in der der Gegner auftaucht.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 4, -60) -- Vor Ausführung anpassen für gewünschte Position
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

-- Organisches, ovales Teil: Block-Part + SpecialMesh(Sphere), non-uniform
-- Size -> gestrecktes Ellipsoid statt Kiste (kartoonig rundes Stacheltier).
local function newOvalPart(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = part
	return part
end

-- Texture-Instanz mit Projekt-Texturschlüssel; FadeWithPart = true (Client
-- blendet Gegner per Transparency/ScaleTo).
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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local enemiesFolder = getOrCreateFolder(assetsFolder, "Enemies")

local previous = enemiesFolder:FindFirstChild("ThornSwarmer")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ThornSwarmer"
model.Parent = enemiesFolder

local SKIN_COLOR = Color3.fromRGB(30, 90, 95)
local ACCENT_COLOR = Color3.fromRGB(20, 65, 70)
local EYE_COLOR = Color3.fromRGB(255, 150, 60)

-- 1) Hauptkörper: kompakte, gedrungene, kartoonig-runde Kugel ---------------------
local body = newPart("Body", Vector3.new(2.2, 2.1, 2.6), ORIGIN, SKIN_COLOR, Enum.Material.Pebble, model)
body.Shape = Enum.PartType.Ball

-- 2) Kleiner Mantel-Buckel oben (leicht dunkler) -----------------------------------
local mantleCFrame = ORIGIN * CFrame.new(0, 0.7, 0)
local mantle = newPart("Mantle", Vector3.new(1.2, 0.9, 1.2), mantleCFrame, ACCENT_COLOR, Enum.Material.Pebble, model)
mantle.Shape = Enum.PartType.Ball

-- 3) Große, freundlich-freche Glow-Augen mit weißem Glanzpunkt --------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.62, 0.25, -1.15)
	local eye = newPart("Eye" .. i, Vector3.new(0.55, 0.55, 0.4), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
	local highlight = newPart("Eye" .. i .. "Highlight", Vector3.new(0.16, 0.16, 0.1), eyeCFrame * CFrame.new(side * -0.12, 0.12, 0.15), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	highlight.Shape = Enum.PartType.Ball
end

-- 4) Radial abstehende Dornstacheln: rundliche, kegelig verjüngte Ellipsoide ------
for t = 1, 6 do
	local angle = math.rad(360 / 6 * (t - 1))
	local dir = Vector3.new(math.cos(angle), math.sin(angle) * 0.6, math.sin(angle))
	local thornCFrame = ORIGIN * CFrame.new(dir * 1.3) * CFrame.Angles(0, angle, math.rad(90))
	newOvalPart("Thorn" .. t, Vector3.new(0.3, 0.9, 0.3), thornCFrame, ACCENT_COLOR, Enum.Material.SmoothPlastic, model)
end

-- 4b) Zweiter, kürzerer Dornenring (versetzt) für mehr Silhouetten-Dichte --------
for t = 1, 6 do
	local angle = math.rad(360 / 6 * (t - 1) + 30)
	local dir = Vector3.new(math.cos(angle), math.sin(angle) * 0.4, math.sin(angle))
	local thornCFrame = ORIGIN * CFrame.new(dir * 0.95) * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, angle, math.rad(90))
	newOvalPart("SmallThorn" .. t, Vector3.new(0.2, 0.55, 0.2), thornCFrame, EYE_COLOR, Enum.Material.Neon, model)
end

-- 4c) Kleiner, rundlicher Kiefer mit angedeuteten Zähnchen vorn --------------------
local jaw = newOvalPart("Jaw", Vector3.new(0.85, 0.45, 0.45), ORIGIN * CFrame.new(0, -0.3, -1.05), ACCENT_COLOR, Enum.Material.SmoothPlastic, model)
for tth = 1, 2 do
	local x = (tth - 1.5) * 0.35
	local tooth = newPart("Tooth" .. tth, Vector3.new(0.2, 0.24, 0.2), ORIGIN * CFrame.new(x, -0.42, -1.28), Color3.fromRGB(240, 235, 220), Enum.Material.SmoothPlastic, model)
	tooth.Shape = Enum.PartType.Ball
end

-- 4d) Kleine, flach gedrückte Heckflosse (stabilisiert die Schwarm-Silhouette) ----
newOvalPart("TailFin", Vector3.new(0.2, 0.9, 0.75), ORIGIN * CFrame.new(0, 0.1, 1.0), ACCENT_COLOR, Enum.Material.SmoothPlastic, model)

-- 5) Idle-/Bedrohungs-Puls-Attachment -------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("EnemyTier", ENEMY_TIER)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("EnemyName", "Thorn Swarmer")

print("[Abyssara] ThornSwarmer created under Workspace.Assets.Enemies")
