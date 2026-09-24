--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude / Verteidigungsturm (Basisstufe)
	Name: ElectricEelTrap ("Elektroaal-Falle", Turmtyp 3 von 3)
	Beschreibung:
		Ketten-Schaden-Turm: ein aufgerollter Aal-Körper um einen dunklen
		Felsanker, dunkles Blau-Schwarz mit gelbem Neon-Streifen über die
		gesamte Körperlänge, kleiner Funken-Partikel-Emitter am Kopf
		(Angriffs-Ursprung). Trifft neben dem Hauptziel bis zu
		RaidConfig.TOWER_STATS.ElectricEelTrap.ChainCount weitere nahe
		Gegner (siehe ChainRadius).

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Base" (Fundament-Part, für Placement/Snap-to-
		  Grid) -> identische Maße/Form (Zylinder, Ø7 Studs, Höhe 1.2 Studs)
		  wie AnglerfishTower.Base, damit dieser Turm dasselbe Grid-Feld
		  belegt (BuildingConfig.GridFieldCount = 1). Der ~2x2x6-Studs-
		  "aufgerollte Fußabdruck" aus der Spezifikation bezieht sich auf
		  den sichtbaren Aal-Körper, der oben auf diesem Fundament sitzt.
		- "EelHead": Kopf-Part des Aals = Angriffs-Ursprung (Ziel-/Schuss-
		  punkt), analog zu AnglerfishTower.LureOrb. WICHTIG: RaidService.
		  tickTowers() sucht aktuell fest nach einem Part namens "LureOrb"
		  (siehe src/server/RaidService.lua Zeile ~425) - der Code-Agent
		  muss die Turm-Ursprungs-Suche generalisieren (z. B. Fallback-
		  Liste ["LureOrb", "EelHead", "SlowPulseCore"]), damit dieser Turm
		  korrekt feuert.
		- Attachment "MuzzlePoint" an EelHead -> Ursprungspunkt für
		  Projektile/Blitz-VFX, analog zu AnglerfishTower.MuzzlePoint.
		- "ChargeCore": eigenständiger Neon-Part am Kopf, sichtbar getrennt
		  von "EelHead" -> repräsentiert den "Ladezustand" der Falle. Der
		  Code-Agent kann Transparency/Brightness/Color dieses Parts (und
		  seines PointLight "ChargeLight") zur Laufzeit ansteuern, um
		  Aufladen (z. B. vor dem Schuss) visuell darzustellen - rein
		  geometrisch/deko hier, keine Blink-/Puls-Logik im Buildscript.
		- Model-Attribute: "BuildingType" = "ElectricEelTrap", "Stage" = 1.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 1.5, -80) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("ElectricEelTrap")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ElectricEelTrap"
model.Parent = buildingsFolder

local EEL_COLOR = Color3.fromRGB(20, 30, 55)
local STRIPE_COLOR = Color3.fromRGB(255, 230, 80)
local ROCK_COLOR = Color3.fromRGB(55, 52, 50)

-- 1) Fundament (identische Form/Maße wie AnglerfishTower.Base für Grid-Kompatibilität)
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Dunkler Felsanker in der Mitte ------------------------------------------------
local rockAnchor = newPart(
	"RockAnchor",
	Vector3.new(1.8, 2.2, 1.8),
	ORIGIN * CFrame.new(0, 1.7, 0),
	ROCK_COLOR,
	Enum.Material.Rock,
	model
)

-- 3) Aufgerollter Aal-Körper (6 Segmente in Spirale um den Felsanker) --------------
local SEGMENT_COUNT = 6
local currentAngle = 0
local currentHeight = 1.0
for i = 1, SEGMENT_COUNT do
	currentAngle += math.rad(75)
	currentHeight += 0.5
	local radius = 1.6
	local segCFrame = ORIGIN
		* CFrame.new(math.cos(currentAngle) * radius, currentHeight, math.sin(currentAngle) * radius)
		* CFrame.Angles(0, -currentAngle, 0)

	local segment = newPart(
		"EelBodySegment" .. i,
		Vector3.new(1.0, 0.7, 0.7),
		segCFrame,
		EEL_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	segment.Shape = Enum.PartType.Cylinder
	segment.CanCollide = false

	-- Gelber Neon-Streifen-Akzent auf jedem Segment (Körperlange Zier-Linie) --------
	local stripeCFrame = segCFrame * CFrame.new(0, 0.42, 0)
	local stripe = newPart(
		"EelStripe" .. i,
		Vector3.new(0.9, 0.12, 0.12),
		stripeCFrame,
		STRIPE_COLOR,
		Enum.Material.Neon,
		model
	)
	stripe.CanCollide = false
end

-- 4) Aal-Kopf (Angriffs-Ursprung, oben an der Spirale) ------------------------------
currentAngle += math.rad(75)
currentHeight += 0.6
local headCFrame = ORIGIN
	* CFrame.new(math.cos(currentAngle) * 1.4, currentHeight, math.sin(currentAngle) * 1.4)
	* CFrame.Angles(0, -currentAngle, 0)

local eelHead = newPart("EelHead", Vector3.new(1.3, 1.0, 1.4), headCFrame, EEL_COLOR, Enum.Material.SmoothPlastic, model)
eelHead.CanCollide = false

-- Kleine Glow-Augen am Kopf ----------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = headCFrame * CFrame.new(side * 0.35, 0.2, -0.6)
	local eye = newPart("EelEye" .. i, Vector3.new(0.2, 0.2, 0.2), eyeCFrame, STRIPE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
	eye.CanCollide = false
end

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = eelHead

-- Funken-Partikel-Emitter am Kopf (Angriffs-VFX-Ursprung) ----------------------------
local sparkEmitter = Instance.new("ParticleEmitter")
sparkEmitter.Name = "SparkEmitter"
sparkEmitter.Color = ColorSequence.new(STRIPE_COLOR)
sparkEmitter.Lifetime = NumberRange.new(0.15, 0.3)
sparkEmitter.Rate = 6
sparkEmitter.Speed = NumberRange.new(2, 4)
sparkEmitter.Size = NumberSequence.new(0.15)
sparkEmitter.Parent = eelHead

-- 5) "Ladezustand"-Anzeige: ChargeCore + ChargeLight --------------------------------
-- Eigenständiger, klar benannter Part für die Code-Anbindung: der Code-Agent kann
-- ChargeCore.Transparency / ChargeCore.Color / ChargeLight.Brightness zur Laufzeit
-- ansteuern, um "Aufladen vor dem Schuss" darzustellen. Reine Geometrie hier -
-- keine Blink-/Timing-Logik im Buildscript selbst.
local chargeCore = newPart(
	"ChargeCore",
	Vector3.new(0.5, 0.5, 0.5),
	headCFrame * CFrame.new(0, 0.65, 0),
	STRIPE_COLOR,
	Enum.Material.Neon,
	model
)
chargeCore.Shape = Enum.PartType.Ball
chargeCore.CanCollide = false

local chargeLight = Instance.new("PointLight")
chargeLight.Name = "ChargeLight"
chargeLight.Color = STRIPE_COLOR
chargeLight.Range = 10
chargeLight.Brightness = 1.5
chargeLight.Shadows = false
chargeLight.Parent = chargeCore

model.PrimaryPart = base
model:SetAttribute("BuildingType", "ElectricEelTrap")
model:SetAttribute("Stage", 1)

print("[Abyssara] ElectricEelTrap created under Workspace.Assets.Buildings")
