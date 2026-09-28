--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude / Verteidigungsturm (Upgrade-Stufe)
	Name: ElectricEelTrap_Stage2 ("Elektroaal-Falle", Stufe 2/3)
	Beschreibung:
		Größere Falle: 8 statt 6 Körpersegmente (längerer, imposanterer
		Aal-Körper), größerer Kopf, ein zusätzlicher Neon-Ladering um den
		Felsanker sowie ein größerer/hellerer ChargeCore.

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "ElectricEelTrap_Stage2" (BuildingId "ElectricEelTrap"
		  + "_Stage2").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  ElectricEelTrap.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "ElectricEelTrap", "Stage" = 2.
		- "EelHead": Kopf-Part (Angriffs-Ursprung), unverändert benannt.
		- Attachment "MuzzlePoint" an EelHead, unverändert.
		- "ChargeCore": eigenständiger Neon-Part, DIREKT unter dem Model
		  geparentet (KEIN Unterordner!) - src/server/RaidService.lua
		  flashChargeCore() sucht mit `model:FindFirstChild("ChargeCore")`
		  NICHT rekursiv, dieser Part muss also direktes Kind des Models
		  bleiben, genau wie in Stufe 1.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(75, 1.5, -140) -- Vor Ausführung anpassen für gewünschte Position
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
	part.CanCollide = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local CollectionService = game:GetService("CollectionService")

local function addKeyedTexture(parent, key, face, studsU, studsV, color, transparency)
	local tex = Instance.new("Texture")
	tex.Name = "Tex_" .. key
	tex.Texture = ""
	tex.Face = face
	tex.StudsPerTileU = studsU
	tex.StudsPerTileV = studsV
	tex.Color3 = color
	tex.Transparency = transparency or 0
	tex:SetAttribute("TextureKey", key)
	CollectionService:AddTag(tex, "KeyedTexture")
	tex.Parent = parent
	return tex
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local buildingsFolder = getOrCreateFolder(assetsFolder, "Buildings")

local previous = buildingsFolder:FindFirstChild("ElectricEelTrap_Stage2")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ElectricEelTrap_Stage2"
model.Parent = buildingsFolder

local EEL_COLOR = Color3.fromRGB(15, 25, 50)
local STRIPE_COLOR = Color3.fromRGB(255, 240, 0)
local ROCK_COLOR = Color3.fromRGB(55, 52, 50)

-- 1) Fundament (IDENTISCH zu ElectricEelTrap.Base für Grid-Kompatibilität) --
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Cobblestone, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Dunkler Felsanker (etwas größer als Stufe 1) ----------------------------
local rockAnchor = newPart(
	"RockAnchor",
	Vector3.new(2.0, 2.4, 2.0),
	ORIGIN * CFrame.new(0, 1.8, 0),
	ROCK_COLOR,
	Enum.Material.Rock,
	model
)

-- 3) Neon-Ladering um den Felsanker (CSG-Subtraktion, neu) -------------------
local ladeOuterCFrame = ORIGIN * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90))
local ladeOuter = newPart("AnchorGlowRingOuter", Vector3.new(0.3, 3.0, 3.0), ladeOuterCFrame, STRIPE_COLOR, Enum.Material.Neon, Workspace)
ladeOuter.Shape = Enum.PartType.Cylinder

local ladeInnerCFrame = ORIGIN * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90))
local ladeInner = newPart("AnchorGlowRingInner", Vector3.new(0.5, 2.4, 2.4), ladeInnerCFrame, Color3.fromRGB(0, 0, 0), Enum.Material.Neon, Workspace)
ladeInner.Shape = Enum.PartType.Cylinder

local ladeRingOk, anchorGlowRing = pcall(function()
	return ladeOuter:SubtractAsync({ ladeInner })
end)
if ladeRingOk and anchorGlowRing then
	anchorGlowRing.Name = "AnchorGlowRing"
	anchorGlowRing.Color = STRIPE_COLOR
	anchorGlowRing.Material = Enum.Material.Neon
	anchorGlowRing.Anchored = true
	anchorGlowRing.CanCollide = false
	anchorGlowRing.Parent = model
end

-- 4) Aufgerollter Aal-Körper (8 Segmente in Spirale um den Felsanker) --------
-- Jedes Segment ist ein Zylinder, der exakt vom vorigen Wegpunkt zum nächsten
-- reicht (statt nur tangential ausgerichtet an seiner eigenen Position zu
-- stehen) - so bildet der Körper eine durchgehend verbundene Kette statt
-- einzelner, frei im Raum schwebender Stücke.
local SEGMENT_COUNT = 8
local BODY_DIAMETER = 0.75
local STRIPE_THICKNESS = 0.14
local waypoints = {}
waypoints[0] = (ORIGIN * CFrame.new(0, 1.8, 0)).Position -- im Felsanker
local currentAngle = 0
local currentHeight = 1.0
for i = 1, SEGMENT_COUNT - 1 do
	currentAngle += math.rad(58)
	currentHeight += 0.42
	local radius = 1.8
	waypoints[i] = (ORIGIN * CFrame.new(math.cos(currentAngle) * radius, currentHeight, math.sin(currentAngle) * radius)).Position
end

-- 5) Aal-Kopf (Angriffs-Ursprung, größer als Stufe 1) ------------------------
currentAngle += math.rad(58)
currentHeight += 0.6
local headCFrame = ORIGIN
	* CFrame.new(math.cos(currentAngle) * 1.5, currentHeight, math.sin(currentAngle) * 1.5)
	* CFrame.Angles(0, -currentAngle, 0)
waypoints[SEGMENT_COUNT] = headCFrame.Position -- letztes Segment mündet im Kopf

for i = 1, SEGMENT_COUNT do
	local p1, p2 = waypoints[i - 1], waypoints[i]
	local dir = p2 - p1
	local length = dir.Magnitude
	local xAxis = dir.Unit
	local upRef = Vector3.new(0, 1, 0)
	if math.abs(xAxis:Dot(upRef)) > 0.95 then
		upRef = Vector3.new(1, 0, 0)
	end
	local zAxis = xAxis:Cross(upRef).Unit
	local yAxis = zAxis:Cross(xAxis).Unit
	local segCFrame = CFrame.fromMatrix(p1:Lerp(p2, 0.5), xAxis, yAxis, zAxis)

	-- +0.3 Studs Länge (Padding) sorgt für ~0.15 Studs Überlappung an jedem
	-- Gelenk mit dem vorigen/nächsten Segment bzw. Felsanker/Kopf.
	local segment = newPart(
		"EelBodySegment" .. i,
		Vector3.new(length + 0.3, BODY_DIAMETER, BODY_DIAMETER),
		segCFrame,
		EEL_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	segment.Shape = Enum.PartType.Cylinder
	segment.CanCollide = false

	local stripeCFrame = segCFrame * CFrame.new(0, BODY_DIAMETER / 2 - 0.05, 0)
	local stripe = newPart(
		"EelStripe" .. i,
		Vector3.new(length * 0.85, STRIPE_THICKNESS, STRIPE_THICKNESS),
		stripeCFrame,
		STRIPE_COLOR,
		Enum.Material.Neon,
		model
	)
	stripe.CanCollide = false
end

local eelHead = newPart("EelHead", Vector3.new(1.5, 1.15, 1.6), headCFrame, EEL_COLOR, Enum.Material.SmoothPlastic, model)
eelHead.CanCollide = false

-- Z-Offset reduziert (Kopf ist 1.6 Studs lang, halbe Länge 0.8): vorher lagen
-- die Augen fast auf der Vorderkante des Kopfes und schwebten damit ohne
-- echte Überlappung.
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = headCFrame * CFrame.new(side * 0.4, 0.22, -0.55)
	local eye = newPart("EelEye" .. i, Vector3.new(0.22, 0.22, 0.22), eyeCFrame, STRIPE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
	eye.CanCollide = false
end

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = eelHead

local sparkEmitter = Instance.new("ParticleEmitter")
sparkEmitter.Name = "SparkEmitter"
sparkEmitter.Color = ColorSequence.new(STRIPE_COLOR)
sparkEmitter.Lifetime = NumberRange.new(0.15, 0.3)
sparkEmitter.Rate = 6
sparkEmitter.Speed = NumberRange.new(2, 4)
sparkEmitter.Size = NumberSequence.new(0.15)
sparkEmitter.Parent = eelHead

-- 6) "Ladezustand"-Anzeige: ChargeCore (größer/heller) + ChargeLight ---------
-- ChargeCore bleibt DIREKTES Kind von `model` (kein Unterordner), siehe
-- Kopfkommentar - RaidService.flashChargeCore() sucht nicht rekursiv.
-- Y-Offset reduziert (Kopf ist 1.15 Studs hoch, halbe Höhe 0.575): der Kern
-- bettet sich damit in den Kopf ein statt frei darüber zu schweben.
local chargeCore = newPart(
	"ChargeCore",
	Vector3.new(0.65, 0.65, 0.65),
	headCFrame * CFrame.new(0, 0.525, 0),
	STRIPE_COLOR,
	Enum.Material.Neon,
	model
)
chargeCore.Shape = Enum.PartType.Ball
chargeCore.CanCollide = false

local chargeLight = Instance.new("PointLight")
chargeLight.Name = "ChargeLight"
chargeLight.Color = STRIPE_COLOR
chargeLight.Range = 14
chargeLight.Brightness = 2
chargeLight.Shadows = false
chargeLight.Parent = chargeCore

-- 6) Oberflaechendetails: Steinsockel-Textur, Basalt-Felsanker, Ankerklammern -
addKeyedTexture(base, "StoneTiles", Enum.NormalId.Top, 3, 3, Color3.fromRGB(150, 150, 155), 0.05)
addKeyedTexture(rockAnchor, "BasaltRock", Enum.NormalId.Front, 1.5, 1.5, ROCK_COLOR, 0.05)

local CLAMP_COLOR = Color3.fromRGB(210, 212, 216)
for i = 1, 3 do
	local angle = math.rad(120 * (i - 1))
	local clampCFrame = ORIGIN * CFrame.new(math.cos(angle) * 1.1, 0.9, math.sin(angle) * 1.1)
	local clamp = newPart("AnchorClamp" .. i, Vector3.new(0.4, 0.5, 0.4), clampCFrame, CLAMP_COLOR, Enum.Material.DiamondPlate, model)
	clamp.CanCollide = false
end

model.PrimaryPart = base
model:SetAttribute("BuildingType", "ElectricEelTrap")
model:SetAttribute("Stage", 2)

print("[Abyssara] ElectricEelTrap_Stage2 created under Workspace.Assets.Buildings")
