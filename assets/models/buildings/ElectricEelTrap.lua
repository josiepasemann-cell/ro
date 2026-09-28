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
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Cobblestone, model)
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
-- Jedes Segment ist ein Zylinder, der exakt vom vorigen Wegpunkt zum nächsten
-- reicht (statt nur tangential ausgerichtet an seiner eigenen Position zu
-- stehen) - so bildet der Körper eine durchgehend verbundene Kette statt
-- einzelner, frei im Raum schwebender Stücke.
local SEGMENT_COUNT = 6
local BODY_DIAMETER = 0.7
local STRIPE_THICKNESS = 0.12
local waypoints = {}
waypoints[0] = (ORIGIN * CFrame.new(0, 1.7, 0)).Position -- im Felsanker
local currentAngle = 0
local currentHeight = 1.0
for i = 1, SEGMENT_COUNT - 1 do
	currentAngle += math.rad(75)
	currentHeight += 0.5
	local radius = 1.6
	waypoints[i] = (ORIGIN * CFrame.new(math.cos(currentAngle) * radius, currentHeight, math.sin(currentAngle) * radius)).Position
end

-- 4) Aal-Kopf (Angriffs-Ursprung, oben an der Spirale) ------------------------------
currentAngle += math.rad(75)
currentHeight += 0.6
local headCFrame = ORIGIN
	* CFrame.new(math.cos(currentAngle) * 1.4, currentHeight, math.sin(currentAngle) * 1.4)
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

	-- Gelber Neon-Streifen-Akzent auf jedem Segment (Körperlange Zier-Linie) --------
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

local eelHead = newPart("EelHead", Vector3.new(1.3, 1.0, 1.4), headCFrame, EEL_COLOR, Enum.Material.SmoothPlastic, model)
eelHead.CanCollide = false

-- Kleine Glow-Augen am Kopf ----------------------------------------------------------
-- Z-Offset auf -0.5 reduziert (Kopf ist 1.4 Studs lang, halbe Länge 0.7):
-- vorher lagen die Augen exakt auf der Vorderkante des Kopfes und schwebten
-- damit ohne echte Überlappung.
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = headCFrame * CFrame.new(side * 0.35, 0.2, -0.5)
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
-- Y-Offset auf 0.45 reduziert (Kopf ist 1.0 Studs hoch, halbe Höhe 0.5): der
-- Kern bettet sich damit ~0.3 Studs in den Kopf ein statt frei 0.15 Studs
-- darüber zu schweben.
local chargeCore = newPart(
	"ChargeCore",
	Vector3.new(0.5, 0.5, 0.5),
	headCFrame * CFrame.new(0, 0.45, 0),
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
model:SetAttribute("Stage", 1)

print("[Abyssara] ElectricEelTrap created under Workspace.Assets.Buildings")
