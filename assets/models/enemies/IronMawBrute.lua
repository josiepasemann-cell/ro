--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Raid-Gegner
	Name: IronMawBrute ("Eisenmaul-Brute")
	Ersetzt ShadowKraken als TemplateName für RaidConfig.EnemyId "Brute".
	Beschreibung:
		Schwerer, gedrungener Körper mit überdimensioniertem Kiefer,
		dunkles Violett-Grau, sichtbare CSG-verschweißte Panzerplatten auf
		der Brust, rote Glow-Augen. Wuchtige Silhouette kommuniziert hohe
		HP / langsame "Tank"-Rolle.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für serverseitige
		  Bewegungs-/Angriffssteuerung (analog zu HumanoidRootPart).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-/
		  Bedrohungs-Puls-Animation.
		- "Mantle", "Eye1", "Eye2" vorhanden -> RaidService.applyEnemyVisual()
		  überschreibt Body/Mantle.Color mit definition.BodyColor und
		  Eye1/Eye2.Color mit definition.EyeColor zur Laufzeit. Hier
		  verwendete Farben sind daher nur Vorschau-Platzhalter.
		- model:SetAttribute("EnemyTier") -> "Elite" (Tank-Einheit).
		- model:SetAttribute("Zone") -> Ziel-Zone, in der der Gegner auftaucht.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
		HINWEIS: Verwendet :UnionAsync() für die Panzerplatte - muss daher
		serverseitig bzw. in Studio mit CSG-Rechten ausgeführt werden (wie
		alle anderen CSG-Buildscripts in diesem Projekt).
]]

local CollectionService = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(30, 6, -60) -- Vor Ausführung anpassen für gewünschte Position
local ENEMY_TIER = "Elite"
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
-- Size -> gestrecktes Ellipsoid (chunky, kartoonig runde Gliedmaßen).
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

local previous = enemiesFolder:FindFirstChild("IronMawBrute")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "IronMawBrute"
model.Parent = enemiesFolder

local SKIN_COLOR = Color3.fromRGB(55, 35, 70)
local ACCENT_COLOR = Color3.fromRGB(40, 25, 52)
local EYE_COLOR = Color3.fromRGB(255, 40, 60)
local ARMOR_COLOR = Color3.fromRGB(70, 60, 80)

-- 1) Hauptkörper: gedrungener, wuchtiger, kartoonig-bulböser Rumpf (Ellipsoid) ----
local body = newOvalPart("Body", Vector3.new(4.4, 3.4, 4.2), ORIGIN, SKIN_COLOR, Enum.Material.Granite, model)

-- 2) Gehockter Schulter-/Nacken-Buckel (Mantel), rundlich ---------------------------
local mantleCFrame = ORIGIN * CFrame.new(0, 1.6, 0.8)
local mantle = newOvalPart("Mantle", Vector3.new(3.6, 1.8, 2.4), mantleCFrame, ACCENT_COLOR, Enum.Material.Granite, model)

-- 3) Überdimensionierter Kiefer (Wedge, ragt nach vorn) -----------------------------
local jawCFrame = ORIGIN * CFrame.new(0, -0.9, -2.2) * CFrame.Angles(math.rad(-15), 0, 0)
local jaw = Instance.new("WedgePart")
jaw.Name = "Jaw"
jaw.Size = Vector3.new(2.6, 1.2, 2.0)
jaw.CFrame = jawCFrame
jaw.Color = ACCENT_COLOR
jaw.Material = Enum.Material.Granite
jaw.Anchored = true
jaw.CanCollide = false
jaw.TopSurface = Enum.SurfaceType.Smooth
jaw.BottomSurface = Enum.SurfaceType.Smooth
jaw.Parent = model

-- 4) Große, wütende Glow-Augen mit weißem Glanzpunkt (kartoonig-bedrohlich) --------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 1.3, 0.6, -1.9)
	local eye = newPart("Eye" .. i, Vector3.new(0.85, 0.85, 0.7), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
	local highlight = newPart("Eye" .. i .. "Highlight", Vector3.new(0.22, 0.22, 0.14), eyeCFrame * CFrame.new(side * -0.18, 0.18, 0.3), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	highlight.Shape = Enum.PartType.Ball
end

-- 5) Panzerplatte auf der Brust (CSG-Union aus 3 angularen Platten) -----------------
local armorParts = {}
local platePositions = {
	{ CFrame.new(0, 0.6, -1.9), Vector3.new(2.2, 1.4, 0.4) },
	{ CFrame.new(-1.0, 0.0, -1.9), Vector3.new(1.0, 1.0, 0.4) },
	{ CFrame.new(1.0, 0.0, -1.9), Vector3.new(1.0, 1.0, 0.4) },
}
for i, spec in ipairs(platePositions) do
	local plate = newPart("ArmorPlatePiece" .. i, spec[2], ORIGIN * spec[1], ARMOR_COLOR, Enum.Material.CorrodedMetal, workspace)
	plate.CanCollide = true
	table.insert(armorParts, plate)
end

local armorUnionOk, armorPlate = pcall(function()
	local primaryPlate = table.remove(armorParts, 1)
	return primaryPlate:UnionAsync(armorParts)
end)

if armorUnionOk and armorPlate then
	armorPlate.Name = "ArmorPlate"
	armorPlate.Color = ARMOR_COLOR
	armorPlate.Material = Enum.Material.CorrodedMetal
	armorPlate.Anchored = true
	armorPlate.CanCollide = false
	armorPlate.Parent = model
	-- Genietete Flächen-Textur auf der flachen Panzerplatte (echte Blockform,
	-- daher geeignet für eine Face-Texture statt Ellipsoid-Materialtrick).
	newTexture("RivetedPlates", Enum.NormalId.Front, armorPlate, { studsU = 1.2, studsV = 1.2, color = Color3.fromRGB(90, 78, 100) })
else
	warn("[Abyssara] IronMawBrute: ArmorPlate-CSG union failed, using unwelded individual plates.")
	for _, plate in ipairs(armorParts) do
		plate.Parent = model
	end
end

-- 6) 4 kurze Stummel-Beine -----------------------------------------------------------
local legOffsets = {
	Vector3.new(-1.4, -1.7, -1.4),
	Vector3.new(1.4, -1.7, -1.4),
	Vector3.new(-1.4, -1.7, 1.4),
	Vector3.new(1.4, -1.7, 1.4),
}
for i, offset in ipairs(legOffsets) do
	newOvalPart("Leg" .. i, Vector3.new(0.85, 0.95, 0.85), ORIGIN * CFrame.new(offset), ACCENT_COLOR, Enum.Material.Granite, model)
	-- Stumpfe, rundliche Klauenfüße (überlappen das jeweilige Bein)
	local footOffset = offset + Vector3.new(0, -0.55, offset.Z > 0 and 0.35 or -0.35)
	newOvalPart("Foot" .. i, Vector3.new(0.75, 0.45, 0.8), ORIGIN * CFrame.new(footOffset), ARMOR_COLOR, Enum.Material.CorrodedMetal, model)
end

-- 6b) Rückendornreihe auf dem Nacken-Buckel (Mantle) für mehr Bedrohlichkeit -------
-- (rundliche, gestreckte Höcker statt eckige Zacken)
for s = 1, 3 do
	local x = (s - 2) * 0.9
	newOvalPart(
		"BackSpike" .. s,
		Vector3.new(0.42, 0.9 - math.abs(s - 2) * 0.2, 0.5),
		ORIGIN * CFrame.new(x, 2.3, 0.9) * CFrame.Angles(math.rad(-12), 0, 0),
		ARMOR_COLOR,
		Enum.Material.CorrodedMetal,
		model
	)
end

-- 6c) Sichtbare untere Zahnreihe im überdimensionierten Kiefer: wenige, große,
-- runde kartoonige Zähne statt vieler kleiner Zacken -------------------------------
for tth = 1, 2 do
	local x = (tth - 1.5) * 0.7
	local tooth = newPart(
		"Tooth" .. tth,
		Vector3.new(0.4, 0.5, 0.4),
		ORIGIN * CFrame.new(x, -1.2, -2.2),
		Color3.fromRGB(230, 225, 210),
		Enum.Material.SmoothPlastic,
		model
	)
	tooth.Shape = Enum.PartType.Ball
end

-- 7) Idle-/Bedrohungs-Puls-Attachment -------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("EnemyTier", ENEMY_TIER)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("EnemyName", "Eisenmaul-Brute")

print("[Abyssara] IronMawBrute created under Workspace.Assets.Enemies")
