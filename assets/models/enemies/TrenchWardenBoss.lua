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

-- Deep purple + gold "crowned leviathan" palette - deliberately NOT close to
-- ShadowKraken's near-black/red palette (see design brief: boss must be
-- unmistakable at a glance). EYE_COLOR/CROWN_COLOR/WEAKSPOT_COLOR are bright
-- gold/white so the face + weak spot pop against the dark purple hull.
local SKIN_COLOR = Color3.fromRGB(46, 14, 64)
local ACCENT_COLOR = Color3.fromRGB(30, 12, 42)
local EYE_COLOR = Color3.fromRGB(255, 170, 30)
local CROWN_COLOR = Color3.fromRGB(255, 205, 60)
local WEAKSPOT_COLOR = Color3.fromRGB(255, 250, 200)
local TOOTH_COLOR = Color3.fromRGB(240, 235, 220)

-- NOTE: -Z is the model's front (LookVector side; RaidService/ModelAnimator
-- orient the boss so -Z faces its direction of travel / the plot center, see
-- ModelAnimator.client.lua's atan2(planar.X, planar.Z) yaw) - every face/
-- crown/armor part below sits on -Z so the boss is unmistakable head-on.

-- 1) Hauptkörper: turmhoch, bulbös-rund, deutlich größer als jeder andere Gegner --
local body = newOvalPart("Body", Vector3.new(8.6, 8.0, 8.2), ORIGIN, SKIN_COLOR, Enum.Material.Basalt, model)

-- 2) Mantel-Auswölbung oben, rundlich, mit goldenem Zierring --------------------
local mantleCFrame = ORIGIN * CFrame.new(0, 2.9, -0.6)
local mantle = newOvalPart("Mantle", Vector3.new(5.8, 4.0, 5.8), mantleCFrame, ACCENT_COLOR, Enum.Material.Basalt, model)
newOvalPart("MantleGoldBand", Vector3.new(5.9, 0.3, 5.9), mantleCFrame * CFrame.new(0, -1.2, 0), CROWN_COLOR, Enum.Material.Neon, model)

-- 3) Größte, wildeste Glow-Augen im Spiel, mit Zornesbrauen + weißem Glanzpunkt ----
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 2.0, 0.9, -3.6)
	local eye = newPart("Eye" .. i, Vector3.new(1.7, 1.7, 1.4), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
	local highlight = newPart("Eye" .. i .. "Highlight", Vector3.new(0.44, 0.44, 0.26), eyeCFrame * CFrame.new(side * -0.32, 0.32, -0.55), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	highlight.Shape = Enum.PartType.Ball
	-- Angled angry eyebrow ridge above each eye
	newOvalPart("Eyebrow" .. i, Vector3.new(1.5, 0.4, 0.5), eyeCFrame * CFrame.new(side * 0.15, 1.05, -0.1) * CFrame.Angles(0, 0, math.rad(side * -22)), ACCENT_COLOR, Enum.Material.Basalt, model)
end

-- 4) Kronendorn-Cluster auf dem Kopf: 5 goldene, kegelig verjüngte Hörner, nach
-- vorn geschwenkt für eine majestätische, klar erkennbare Krone -------------------
local crownLight
for c = 1, 5 do
	local angle = math.rad(-60 + (c - 1) * 30)
	local crownCFrame = ORIGIN * CFrame.new(0, 3.8, -1.0) * CFrame.Angles(0, angle, math.rad(90)) * CFrame.new(0, 0, 1.1)
	local spike = newOvalPart("CrownSpike" .. c, Vector3.new(0.65, 2.3, 0.65), crownCFrame, CROWN_COLOR, Enum.Material.Neon, model)
	if c == 1 then
		local pointLight = Instance.new("PointLight")
		pointLight.Name = "CrownLight"
		pointLight.Color = CROWN_COLOR
		pointLight.Range = 28
		pointLight.Brightness = 3.5
		pointLight.Shadows = false
		pointLight.Parent = spike
		crownLight = pointLight
	end
end

-- 4a) Anglerfish-Lockangel: gebogener Stiel über dem Kopf mit leuchtender Spitze --
-- Signature-Silhouette-Element, macht den Boss auf den ersten Blick von
-- ShadowKraken/allen anderen Gegnern unterscheidbar.
local lureBase = ORIGIN * CFrame.new(0, 4.3, -0.6)
newOvalPart("LureStalk1", Vector3.new(0.3, 1.4, 0.3), lureBase * CFrame.Angles(math.rad(-18), 0, 0), ACCENT_COLOR, Enum.Material.Basalt, model)
local lureStalk2CFrame = lureBase * CFrame.Angles(math.rad(-18), 0, 0) * CFrame.new(0, 1.2, 0) * CFrame.Angles(math.rad(-30), 0, 0)
newOvalPart("LureStalk2", Vector3.new(0.24, 1.2, 0.24), lureStalk2CFrame, ACCENT_COLOR, Enum.Material.Basalt, model)
local lureTipCFrame = lureStalk2CFrame * CFrame.new(0, 1.0, 0)
local lureOrb = newPart("LureOrb", Vector3.new(0.9, 0.9, 0.9), lureTipCFrame, WEAKSPOT_COLOR, Enum.Material.Neon, model)
lureOrb.Shape = Enum.PartType.Ball
local lureLight = Instance.new("PointLight")
lureLight.Name = "LureLight"
lureLight.Color = WEAKSPOT_COLOR
lureLight.Range = 20
lureLight.Brightness = 2.5
lureLight.Shadows = false
lureLight.Parent = lureOrb

-- 4b) Gepanzerte Brustplatten (flache, echte Blockform mit Gold-Nieten-Textur) ----
local chestPlates = {}
for p = 1, 3 do
	local x = (p - 2) * 1.8
	local plate = newPart(
		"ChestPlate" .. p,
		Vector3.new(1.7 - math.abs(p - 2) * 0.3, 2.9, 1.0),
		ORIGIN * CFrame.new(x, -0.3, -3.7) * CFrame.Angles(math.rad(-6 * (p - 2)), 0, 0),
		ACCENT_COLOR,
		Enum.Material.CorrodedMetal,
		model
	)
	chestPlates[p] = plate
end
newTexture("RivetedPlates", Enum.NormalId.Front, chestPlates[2], { studsU = 1.2, studsV = 1.2, color = Color3.fromRGB(120, 95, 40) })
newTexture("MetalPanels", Enum.NormalId.Front, chestPlates[1], { studsU = 1.5, studsV = 1.5, color = Color3.fromRGB(60, 48, 54) })

-- 4c) Glühender Schwachpunkt-Kern, mittig in der Brustpanzerung eingelassen -------
local weakSpot = newPart("WeakSpotCore", Vector3.new(0.95, 0.95, 0.5), ORIGIN * CFrame.new(0, -0.3, -4.05), WEAKSPOT_COLOR, Enum.Material.Neon, model)
weakSpot.Shape = Enum.PartType.Ball
local weakSpotLight = Instance.new("PointLight")
weakSpotLight.Name = "WeakSpotLight"
weakSpotLight.Color = WEAKSPOT_COLOR
weakSpotLight.Range = 18
weakSpotLight.Brightness = 3
weakSpotLight.Shadows = false
weakSpotLight.Parent = weakSpot

-- 4d) Rundlicher Unterkiefer + große, runde Kartoon-Zähne (statt spitzem Schnabel) -
local jawCFrame = ORIGIN * CFrame.new(0, -1.3, -3.8)
local jaw = newOvalPart("Beak", Vector3.new(2.2, 1.3, 1.6), jawCFrame, Color3.fromRGB(60, 22, 40), Enum.Material.Granite, model)
newOvalPart("UpperSnout", Vector3.new(2.0, 0.9, 1.3), ORIGIN * CFrame.new(0, -0.25, -3.85), Color3.fromRGB(60, 22, 40), Enum.Material.Granite, model)
for tth = 1, 4 do
	local x = (tth - 2.5) * 0.55
	local tooth = newPart("Tooth" .. tth, Vector3.new(0.42, 0.5, 0.4), jawCFrame * CFrame.new(x, 0.55, -0.55), TOOTH_COLOR, Enum.Material.SmoothPlastic, model)
	tooth.Shape = Enum.PartType.Ball
end

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
