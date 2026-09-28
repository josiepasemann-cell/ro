--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Raid-Gegner (Platzhalter-Modell)
	Name: ShadowKraken ("Shadow Kraken")
	Beschreibung:
		Bedrohlicher, deutlich größerer Trench-Raid-Gegner: dunkler,
		schattiger Körper mit bedrohlichen roten Glow-Augen und 8 langen,
		peitschenartigen Tentakeln. Dient als Platzhalter-Gegner-Modell für
		das Trench-Raid-System (Abschnitt 3 & 9 des GDD).

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für serverseitige
		  Bewegungs-/Angriffssteuerung (analog zu HumanoidRootPart).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-/
		  Bedrohungs-Puls-Animation.
		- model:SetAttribute("EnemyTier") -> Platzhalter-Einstufung
		  ("Trash"/"Elite"/"Boss"), hier "Elite" als Startwert.
		- model:SetAttribute("Zone") -> Ziel-Zone, in der der Gegner auftaucht.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 8, 90) -- Vor Ausführung anpassen für gewünschte Position
local ENEMY_TIER = "Elite"
local ZONE = "TwilightZone"
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

-- Organisches, ovales/kapselförmiges Teil: Block-Part + SpecialMesh(Sphere),
-- non-uniform Size -> gestrecktes Ellipsoid statt Kiste. Für Gliedmaßen,
-- Tentakel, Flossen, Hörner (kartoonig rund statt eckig).
local function newOvalPart(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = part
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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local enemiesFolder = getOrCreateFolder(assetsFolder, "Enemies")

local previous = enemiesFolder:FindFirstChild("ShadowKraken")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ShadowKraken"
model.Parent = enemiesFolder

local SKIN_COLOR = Color3.fromRGB(20, 18, 26)
local ACCENT_COLOR = Color3.fromRGB(35, 30, 45)
local EYE_COLOR = Color3.fromRGB(255, 40, 60)

-- 1) Hauptkörper: chunky, kartoonig-bulböses Ellipsoid (deutlich größer als
--    normale Kreaturen; leicht "aufgeplustert" statt geometrisch rund) --------
local body = newOvalPart("Body", Vector3.new(4.8, 4.4, 4.6), ORIGIN, SKIN_COLOR, Enum.Material.Basalt, model)

-- 2) Mantel-Auswölbung oben (leicht dunklerer, rundlicher Buckel) -----------------
local mantleCFrame = ORIGIN * CFrame.new(0, 1.6, -0.4)
local mantle = newOvalPart("Mantle", Vector3.new(3.2, 2.4, 3.2), mantleCFrame, ACCENT_COLOR, Enum.Material.Basalt, model)

-- 2b) Kronendorn-Reihe auf dem Mantel (rundliche Hörnchen statt eckige Zacken) -----
for c = 1, 5 do
	local angle = math.rad(-70 + (c - 1) * 35)
	local spikeCFrame = mantleCFrame * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, angle, 0) * CFrame.new(0, 0.5, 0.3)
	newOvalPart("CrownRidge" .. c, Vector3.new(0.4, 1.0, 0.4), spikeCFrame, ACCENT_COLOR, Enum.Material.CorrodedMetal, model)
end

-- 2c) Barnacle-/Warzen-Höcker auf dem Körper für mehr Oberflächen-Detail -----------
for b = 1, 6 do
	local angle = math.rad(60 * b)
	local bumpCFrame = ORIGIN * CFrame.new(math.cos(angle) * 1.7, math.sin(angle) * 0.6 - 0.4, math.sin(angle) * 1.4)
	local bump = newPart("Barnacle" .. b, Vector3.new(0.45, 0.45, 0.45), bumpCFrame, ACCENT_COLOR, Enum.Material.CorrodedMetal, model)
	bump.Shape = Enum.PartType.Ball
end

-- 2d) Hakenschnabel (Beak) am unteren Kopfansatz, zwischen den Augen -----------------
local beakUpper = Instance.new("WedgePart")
beakUpper.Name = "BeakUpper"
beakUpper.Size = Vector3.new(0.9, 0.7, 0.9)
beakUpper.CFrame = ORIGIN * CFrame.new(0, -0.1, 1.9) * CFrame.Angles(math.rad(-90), 0, 0)
beakUpper.Color = Color3.fromRGB(45, 40, 50)
beakUpper.Material = Enum.Material.CorrodedMetal
beakUpper.Anchored = true
beakUpper.CanCollide = false
beakUpper.TopSurface = Enum.SurfaceType.Smooth
beakUpper.BottomSurface = Enum.SurfaceType.Smooth
beakUpper.Parent = model

-- 2e) Rückenkamm-Naht (2 dünne, überlappende Grate über den Mantel) -----------------
-- Bricht die glatte Kugelsilhouette auf und liefert eine sichtbare "Panzernaht".
newPart("MantleSeam1", Vector3.new(0.22, 0.5, 2.6), mantleCFrame * CFrame.new(-0.6, 0.4, 0), ACCENT_COLOR, Enum.Material.CorrodedMetal, model)
newPart("MantleSeam2", Vector3.new(0.22, 0.5, 2.6), mantleCFrame * CFrame.new(0.6, 0.4, 0), ACCENT_COLOR, Enum.Material.CorrodedMetal, model)

-- 2f) Oberflächen-Textur: gehämmerte Chitinplatte auf dem flachen Schnabel -------
-- (Ellipsoid-Körper/Mantel bekommen bewusst KEINE Flächen-Texturen - dort
-- übernehmen Material + Barnacle-Höcker die Oberflächen-Wirkung, siehe Brief.)
newTexture("MetalPanels", Enum.NormalId.Front, beakUpper, { studsU = 1.5, studsV = 1.5, color = Color3.fromRGB(60, 55, 65) })

-- 3) Große, kartoonig-wütende Glow-Augen mit weißem Glanzpunkt ---------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 1.15, 0.5, 2.05)
	local eye = newPart("Eye" .. i, Vector3.new(0.95, 0.95, 0.9), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
	local highlight = newPart("Eye" .. i .. "Highlight", Vector3.new(0.24, 0.24, 0.15), eyeCFrame * CFrame.new(side * -0.2, 0.22, 0.35), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	highlight.Shape = Enum.PartType.Ball
end

-- 4) 8 lange, peitschenartige Tentakel (je 4 Segmente, radial verteilt) ------------
for t = 1, TENTACLE_COUNT do
	local angle = math.rad(360 / TENTACLE_COUNT * (t - 1))
	local baseOffset = Vector3.new(math.cos(angle) * 1.8, -1.8, math.sin(angle) * 1.8)
	local armCFrame = ORIGIN * CFrame.new(baseOffset) * CFrame.Angles(0, angle, math.rad(-95))

	local currentCFrame = armCFrame
	for seg = 1, 4 do
		local segLength = 2.0 - seg * 0.25
		local width = 0.75 - seg * 0.14
		local curl = math.rad(10 + seg * 4)

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

-- 5) Idle-/Bedrohungs-Puls-Attachment -------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("EnemyTier", ENEMY_TIER)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("EnemyName", "Shadow Kraken")

print("[Abyssara] ShadowKraken created under Workspace.Assets.Enemies")
