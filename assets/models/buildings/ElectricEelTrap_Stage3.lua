--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude / Verteidigungsturm (Upgrade-Stufe)
	Name: ElectricEelTrap_Stage3 ("Elektroaal-Falle", Stufe 3/3 - Finalstufe)
	Beschreibung:
		Monumentale Falle: alle Stufe-2-Strukturen, 10 Körpersegmente für
		einen noch längeren Spiralkörper, eine CSG-verschweißte Dornenkrone
		am Fuß des Felsankers sowie ein größerer, hellerer ChargeCore mit
		dezentem Extra-Funkenemitter (niedrige Rate).

	NAMENSKONVENTION FÜR DEN CODE-AGENTEN (Upgrade-System):
		- Modellname "ElectricEelTrap_Stage3" (BuildingId "ElectricEelTrap"
		  + "_Stage3").
		- Model.PrimaryPart = "Base" (IDENTISCHE Größe/Form/Offset wie
		  ElectricEelTrap.Base -> gleiches Baufeld-Footprint).
		- Model-Attribute: "BuildingType" = "ElectricEelTrap", "Stage" = 3.
		- "EelHead": Kopf-Part (Angriffs-Ursprung), unverändert benannt.
		- Attachment "MuzzlePoint" an EelHead, unverändert.
		- "ChargeCore": eigenständiger Neon-Part, DIREKT unter dem Model
		  geparentet (KEIN Unterordner!) - src/server/RaidService.lua
		  flashChargeCore() sucht mit `model:FindFirstChild("ChargeCore")`
		  NICHT rekursiv, dieser Part muss also direktes Kind des Models
		  bleiben, genau wie in Stufe 1/2.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
		HINWEIS: Verwendet :UnionAsync()/:SubtractAsync() - daher serverseitig
		bzw. in Studio mit CSG-Rechten ausführen.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(75, 1.5, -160) -- Vor Ausführung anpassen für gewünschte Position
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

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local buildingsFolder = getOrCreateFolder(assetsFolder, "Buildings")

local previous = buildingsFolder:FindFirstChild("ElectricEelTrap_Stage3")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ElectricEelTrap_Stage3"
model.Parent = buildingsFolder

local EEL_COLOR = Color3.fromRGB(10, 20, 45)
local STRIPE_COLOR = Color3.fromRGB(255, 245, 0)
local ROCK_COLOR = Color3.fromRGB(55, 52, 50)

-- 1) Fundament (IDENTISCH zu ElectricEelTrap.Base für Grid-Kompatibilität) --
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Dunkler Felsanker (größer als Stufe 2) ----------------------------------
local rockAnchor = newPart(
	"RockAnchor",
	Vector3.new(2.2, 2.6, 2.2),
	ORIGIN * CFrame.new(0, 1.9, 0),
	ROCK_COLOR,
	Enum.Material.Rock,
	model
)

-- 3) Neon-Ladering um den Felsanker (CSG-Subtraktion) ------------------------
local ladeOuterCFrame = ORIGIN * CFrame.new(0, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90))
local ladeOuter = newPart("AnchorGlowRingOuter", Vector3.new(0.3, 3.2, 3.2), ladeOuterCFrame, STRIPE_COLOR, Enum.Material.Neon, Workspace)
ladeOuter.Shape = Enum.PartType.Cylinder

local ladeInnerCFrame = ORIGIN * CFrame.new(0, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90))
local ladeInner = newPart("AnchorGlowRingInner", Vector3.new(0.5, 2.6, 2.6), ladeInnerCFrame, Color3.fromRGB(0, 0, 0), Enum.Material.Neon, Workspace)
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

-- 4) Dornenkrone am Fuß des Felsankers (CSG-Union aus 6 Spitzen) -------------
local crownSpikes = {}
local CROWN_SPIKE_COUNT = 6
local CROWN_RADIUS = 1.9
for i = 1, CROWN_SPIKE_COUNT do
	local angle = math.rad(360 / CROWN_SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * CROWN_RADIUS, 0.7, math.sin(angle) * CROWN_RADIUS)
	local spikeCFrame = ORIGIN * CFrame.new(offset) * CFrame.Angles(0, angle, math.rad(70))
	local spike = newPart("CrownSpikePiece" .. i, Vector3.new(0.3, 1.4, 0.3), spikeCFrame, STRIPE_COLOR, Enum.Material.Neon, Workspace)
	table.insert(crownSpikes, spike)
end

local crownOk, crownArc = pcall(function()
	local primary = table.remove(crownSpikes, 1)
	return primary:UnionAsync(crownSpikes)
end)
if crownOk and crownArc then
	crownArc.Name = "CrownArc"
	crownArc.Color = STRIPE_COLOR
	crownArc.Material = Enum.Material.Neon
	crownArc.Anchored = true
	crownArc.CanCollide = false
	crownArc.Parent = model
else
	warn("[Abyssara] ElectricEelTrap_Stage3: CrownArc-CSG union failed, using unwelded individual spikes.")
	for _, spike in ipairs(crownSpikes) do
		spike.Anchored = true
		spike.CanCollide = false
		spike.Parent = model
	end
end

-- 5) Aufgerollter Aal-Körper (10 Segmente in Spirale um den Felsanker) -------
local SEGMENT_COUNT = 10
local currentAngle = 0
local currentHeight = 1.0
for i = 1, SEGMENT_COUNT do
	currentAngle += math.rad(50)
	currentHeight += 0.36
	local radius = 2.0
	local segCFrame = ORIGIN
		* CFrame.new(math.cos(currentAngle) * radius, currentHeight, math.sin(currentAngle) * radius)
		* CFrame.Angles(0, -currentAngle, 0)

	local segment = newPart(
		"EelBodySegment" .. i,
		Vector3.new(1.1, 0.8, 0.8),
		segCFrame,
		EEL_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	segment.Shape = Enum.PartType.Cylinder
	segment.CanCollide = false

	local stripeCFrame = segCFrame * CFrame.new(0, 0.46, 0)
	local stripe = newPart(
		"EelStripe" .. i,
		Vector3.new(1.0, 0.15, 0.15),
		stripeCFrame,
		STRIPE_COLOR,
		Enum.Material.Neon,
		model
	)
	stripe.CanCollide = false
end

-- 6) Aal-Kopf (Angriffs-Ursprung, größer als Stufe 2) ------------------------
currentAngle += math.rad(50)
currentHeight += 0.6
local headCFrame = ORIGIN
	* CFrame.new(math.cos(currentAngle) * 1.6, currentHeight, math.sin(currentAngle) * 1.6)
	* CFrame.Angles(0, -currentAngle, 0)

local eelHead = newPart("EelHead", Vector3.new(1.7, 1.3, 1.8), headCFrame, EEL_COLOR, Enum.Material.SmoothPlastic, model)
eelHead.CanCollide = false

for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = headCFrame * CFrame.new(side * 0.45, 0.24, -0.8)
	local eye = newPart("EelEye" .. i, Vector3.new(0.25, 0.25, 0.25), eyeCFrame, STRIPE_COLOR, Enum.Material.Neon, model)
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

-- 7) "Ladezustand"-Anzeige: ChargeCore (größer/heller) + ChargeLight ---------
-- ChargeCore bleibt DIREKTES Kind von `model` (kein Unterordner), siehe
-- Kopfkommentar - RaidService.flashChargeCore() sucht nicht rekursiv.
local chargeCore = newPart(
	"ChargeCore",
	Vector3.new(0.8, 0.8, 0.8),
	headCFrame * CFrame.new(0, 0.75, 0),
	STRIPE_COLOR,
	Enum.Material.Neon,
	model
)
chargeCore.Shape = Enum.PartType.Ball
chargeCore.CanCollide = false

local chargeLight = Instance.new("PointLight")
chargeLight.Name = "ChargeLight"
chargeLight.Color = STRIPE_COLOR
chargeLight.Range = 18
chargeLight.Brightness = 2.4
chargeLight.Shadows = false
chargeLight.Parent = chargeCore

local chargeSparkEmitter = Instance.new("ParticleEmitter")
chargeSparkEmitter.Name = "ChargeSparkEmitter"
chargeSparkEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
chargeSparkEmitter.Lifetime = NumberRange.new(0.2, 0.4)
chargeSparkEmitter.Rate = 4
chargeSparkEmitter.Speed = NumberRange.new(3, 5)
chargeSparkEmitter.Size = NumberSequence.new(0.12)
chargeSparkEmitter.Parent = chargeCore

model.PrimaryPart = base
model:SetAttribute("BuildingType", "ElectricEelTrap")
model:SetAttribute("Stage", 3)

print("[Abyssara] ElectricEelTrap_Stage3 created under Workspace.Assets.Buildings")
