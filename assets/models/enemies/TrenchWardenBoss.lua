--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Raid-Gegner (Boss)
	Name: TrenchWardenBoss ("The Trench Warden")
	Ersetzt ShadowKraken als TemplateName für RaidConfig.EnemyId "TrenchWarden"
	(Boss). Visueller Auszahlungspunkt für das "The Trench Warden"-Arena-
	Landmark in MidnightZoneTerrainChunk.lua.
	Beschreibung:
		Turmhohe Kraken-Fürst-Silhouette, nahezu schwarzer Körper, 8 lange
		und dickere Tentakel (länger/wuchtiger als der alte ShadowKraken-
		Platzhalter), glühende rote Kronendorn-Cluster auf dem Kopf, größte
		Glow-Augen im Spiel, PointLight für dramatische Arena-Beleuchtung.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für serverseitige
		  Bewegungs-/Angriffssteuerung (analog zu HumanoidRootPart).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-/
		  Bedrohungs-Puls-Animation.
		- "Mantle", "Eye1", "Eye2" vorhanden -> RaidService.applyEnemyVisual()
		  überschreibt Body/Mantle.Color mit definition.BodyColor und
		  Eye1/Eye2.Color mit definition.EyeColor zur Laufzeit. Hier
		  verwendete Farben sind daher nur Vorschau-Platzhalter.
		- model:SetAttribute("EnemyTier") -> "Boss".
		- model:SetAttribute("Zone") -> Ziel-Zone, in der der Boss auftaucht
		  (Standard hier: "MidnightZone").
		- PointLight "CrownLight" an CrownSpike1 -> reine Deko-Beleuchtung
		  für die Boss-Arena, keine Gameplay-Logik.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(45, 10, -60) -- Vor Ausführung anpassen für gewünschte Position
local ENEMY_TIER = "Boss"
local ZONE = "MidnightZone"
local TENTACLE_COUNT = 8
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
-- Size -> gestrecktes Ellipsoid (big & funny-scary statt geometrisch hart).
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

local previous = enemiesFolder:FindFirstChild("TrenchWardenBoss")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TrenchWardenBoss"
model.Parent = enemiesFolder

local SKIN_COLOR = Color3.fromRGB(15, 10, 15)
local ACCENT_COLOR = Color3.fromRGB(28, 20, 30)
local EYE_COLOR = Color3.fromRGB(255, 20, 30)
local CROWN_COLOR = Color3.fromRGB(255, 30, 40)

-- 1) Hauptkörper: turmhoch, bulbös-rund, "big & funny-scary" statt hart-geometrisch
local body = newOvalPart("Body", Vector3.new(7.6, 7.2, 7.4), ORIGIN, SKIN_COLOR, Enum.Material.Basalt, model)

-- 2) Mantel-Auswölbung oben, rundlich --------------------------------------------
local mantleCFrame = ORIGIN * CFrame.new(0, 2.6, -0.6)
local mantle = newOvalPart("Mantle", Vector3.new(5.2, 3.6, 5.2), mantleCFrame, ACCENT_COLOR, Enum.Material.Basalt, model)

-- 3) Größte, wildeste Glow-Augen im Spiel, mit weißem Glanzpunkt ---------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 1.85, 0.7, 3.25)
	local eye = newPart("Eye" .. i, Vector3.new(1.5, 1.5, 1.3), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
	local highlight = newPart("Eye" .. i .. "Highlight", Vector3.new(0.4, 0.4, 0.24), eyeCFrame * CFrame.new(side * -0.3, 0.3, 0.5), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	highlight.Shape = Enum.PartType.Ball
end

-- 4) Kronendorn-Cluster auf dem Kopf: 5 rundliche, kegelig verjüngte Neon-Hörner ---
local crownLight
for c = 1, 5 do
	local angle = math.rad(-60 + (c - 1) * 30)
	local crownCFrame = ORIGIN * CFrame.new(0, 3.4, 1.0) * CFrame.Angles(0, angle, math.rad(90)) * CFrame.new(0, 0, 1.0)
	local spike = newOvalPart("CrownSpike" .. c, Vector3.new(0.6, 2.0, 0.6), crownCFrame, CROWN_COLOR, Enum.Material.Neon, model)
	if c == 1 then
		local pointLight = Instance.new("PointLight")
		pointLight.Name = "CrownLight"
		pointLight.Color = CROWN_COLOR
		pointLight.Range = 24
		pointLight.Brightness = 3
		pointLight.Shadows = false
		pointLight.Parent = spike
		crownLight = pointLight
	end
end

-- 4b) Gepanzerte Brustplatten (flache, echte Blockform - hier bleibt hartes
-- Material sinnvoll; bekommt eine genietete Flächen-Textur) ------------------------
local chestPlates = {}
for p = 1, 3 do
	local x = (p - 2) * 1.6
	local plate = newPart(
		"ChestPlate" .. p,
		Vector3.new(1.5 - math.abs(p - 2) * 0.3, 2.6, 0.9),
		ORIGIN * CFrame.new(x, -0.3, 3.4) * CFrame.Angles(math.rad(6 * (p - 2)), 0, 0),
		ACCENT_COLOR,
		Enum.Material.CorrodedMetal,
		model
	)
	chestPlates[p] = plate
end
newTexture("RivetedPlates", Enum.NormalId.Front, chestPlates[2], { studsU = 1.2, studsV = 1.2, color = Color3.fromRGB(70, 55, 62) })
newTexture("MetalPanels", Enum.NormalId.Front, chestPlates[1], { studsU = 1.5, studsV = 1.5, color = Color3.fromRGB(60, 48, 54) })

-- 4c) Rundlicher Hakenschnabel unterhalb der Augen (kartoonig statt spitz) --------
local beak = newOvalPart("Beak", Vector3.new(1.6, 1.2, 1.3), ORIGIN * CFrame.new(0, -1.0, 3.6), Color3.fromRGB(35, 25, 32), Enum.Material.Granite, model)

-- 5) 8 lange, dicke, peitschenartige Tentakel (je 3 Segmente, radial verteilt) -----
for t = 1, TENTACLE_COUNT do
	local angle = math.rad(360 / TENTACLE_COUNT * (t - 1))
	local baseOffset = Vector3.new(math.cos(angle) * 2.8, -2.8, math.sin(angle) * 2.8)
	local armCFrame = ORIGIN * CFrame.new(baseOffset) * CFrame.Angles(0, angle, math.rad(-95))

	local currentCFrame = armCFrame
	for seg = 1, 3 do
		local segLength = 3.4 - seg * 0.4
		local width = 1.3 - seg * 0.22
		local curl = math.rad(10 + seg * 5)

		currentCFrame = currentCFrame * CFrame.Angles(curl, 0, 0) * CFrame.new(0, segLength / 2, 0)

		newOvalPart(
			"Tentacle" .. t .. "_Segment" .. seg,
			Vector3.new(width * 1.15, segLength, width * 1.15),
			currentCFrame,
			seg % 2 == 0 and SKIN_COLOR or ACCENT_COLOR,
			seg % 2 == 0 and Enum.Material.Basalt or Enum.Material.CorrodedMetal,
			model
		)

		currentCFrame = currentCFrame * CFrame.new(0, segLength / 2, 0)
	end
end

-- 6) Idle-/Bedrohungs-Puls-Attachment -------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("EnemyTier", ENEMY_TIER)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("EnemyName", "The Trench Warden")

print("[Abyssara] TrenchWardenBoss created under Workspace.Assets.Enemies")
