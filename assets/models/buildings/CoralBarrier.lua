--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Gebäude / Verteidigungsturm (Basisstufe)
	Name: CoralBarrier ("Korallen-Barriere", Turmtyp 2 von 3)
	Beschreibung:
		Flächen-Verteidigung/Tank-Turm: ein Ring/Bogen aus verschweißten
		Korallenspitzen auf einem gerundeten Sockel (CSG-Union, analog zur
		Becken-Ring-Technik in BroodPool_Basic.lua), warmes Pink-Orange mit
		Neon-türkisenen Spitzen. Statt hoher Einzelziel-Schadenswerte (wie
		AnglerfishTower) verlangsamt diese Barriere Gegner in ihrer Nähe
		(siehe RaidConfig.TOWER_STATS.CoralBarrier.BlockRadius).

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Base" (Fundament-Part, für Placement/Snap-to-
		  Grid) -> identische Maße/Form (Zylinder, Ø7 Studs, Höhe 1.2 Studs)
		  wie AnglerfishTower.Base, damit dieser Turm dasselbe Grid-Feld
		  belegt (BuildingConfig.GridFieldCount = 1).
		- Model-Attribute: "BuildingType" = "CoralBarrier", "Stage" = 1.
		- "SlowPulseCore": Neon-Part (türkisener Glüh-Kern in der Turmmitte)
		  = LureOrb-Äquivalent, Referenzpunkt für die Verlangsamungs-
		  Puls-VFX (analog zu AnglerfishTower.LureOrb als Ziel-/Schuss-
		  punkt). WICHTIG: RaidService.tickTowers() sucht aktuell fest
		  nach einem Part namens "LureOrb" für den Feuer-/Effekt-Ursprung
		  (siehe src/server/RaidService.lua Zeile ~425) - dieser Name ist
		  bewusst hier NICHT dupliziert (Spezifikation verlangt
		  "SlowPulseCore"), der Code-Agent muss also entweder zusätzlich
		  "LureOrb" suchen oder die Turm-Ursprungs-Suche generalisieren
		  (z. B. Fallback-Liste ["LureOrb", "SlowPulseCore", "EelHead"]).
		- Attachment "MuzzlePoint" an SlowPulseCore -> Ursprungspunkt für
		  Verlangsamungs-/Puls-Effekte, analog zu AnglerfishTower.MuzzlePoint.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
		HINWEIS: Verwendet :UnionAsync() für den Korallenring - muss daher
		serverseitig bzw. in Studio mit CSG-Rechten ausgeführt werden.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 1.5, -80) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = buildingsFolder:FindFirstChild("CoralBarrier")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "CoralBarrier"
model.Parent = buildingsFolder

local CORAL_COLOR = Color3.fromRGB(255, 140, 120)
local TEAL_GLOW = Color3.fromRGB(80, 230, 210)

-- 1) Fundament (identische Form/Maße wie AnglerfishTower.Base für Grid-Kompatibilität)
local base = newPart("Base", Vector3.new(7, 1.2, 7), ORIGIN, Color3.fromRGB(70, 74, 82), Enum.Material.Slate, model)
base.Shape = Enum.PartType.Cylinder
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))

-- 2) Gerundeter Sockel-Aufbau in Korallenfarbe ------------------------------------
local mound = newPart(
	"CoralMound",
	Vector3.new(4.6, 1.4, 4.6),
	ORIGIN * CFrame.new(0, 1.3, 0),
	CORAL_COLOR,
	Enum.Material.SmoothPlastic,
	model
)
mound.Shape = Enum.PartType.Cylinder
mound.CFrame = ORIGIN * CFrame.new(0, 1.3, 0) * CFrame.Angles(0, 0, math.rad(90))

-- 3) Ring aus verschweißten Korallenspitzen (CSG-Union, analog BroodPool_Basic-Ring)
local spikeParts = {}
local SPIKE_COUNT = 8
local RING_RADIUS = 2.6
for i = 1, SPIKE_COUNT do
	local angle = math.rad(360 / SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	local spikeCFrame = ORIGIN * CFrame.new(offset + Vector3.new(0, 2.0, 0)) * CFrame.Angles(0, angle, 0)
	local spike = newPart("CoralSpikePiece" .. i, Vector3.new(0.6, 1.8, 0.6), spikeCFrame, CORAL_COLOR, Enum.Material.SmoothPlastic, workspace)
	table.insert(spikeParts, spike)
end

local ringUnionOk, coralRing = pcall(function()
	local primarySpike = table.remove(spikeParts, 1)
	return primarySpike:UnionAsync(spikeParts)
end)

if ringUnionOk and coralRing then
	coralRing.Name = "CoralRing"
	coralRing.Color = CORAL_COLOR
	coralRing.Material = Enum.Material.SmoothPlastic
	coralRing.Anchored = true
	coralRing.CanCollide = false
	coralRing.Parent = model
else
	warn("[Abyssara] CoralBarrier: CoralRing-CSG-Union fehlgeschlagen, verwende ungeschweißte Einzelspitzen.")
	for _, spike in ipairs(spikeParts) do
		spike.Anchored = true
		spike.CanCollide = false
		spike.Parent = model
	end
end

-- 4) Neon-türkisene Spitzen-Tips (kleine, unverbundene Glow-Akzente je Spike) -------
for i = 1, SPIKE_COUNT do
	local angle = math.rad(360 / SPIKE_COUNT * (i - 1))
	local offset = Vector3.new(math.cos(angle) * RING_RADIUS, 0, math.sin(angle) * RING_RADIUS)
	local tipCFrame = ORIGIN * CFrame.new(offset + Vector3.new(0, 2.95, 0))
	local tip = newPart("SpikeTip" .. i, Vector3.new(0.35, 0.35, 0.35), tipCFrame, TEAL_GLOW, Enum.Material.Neon, model)
	tip.Shape = Enum.PartType.Ball
	tip.CanCollide = false
end

-- 5) Zentraler Verlangsamungs-Puls-Kern (LureOrb-Äquivalent) ------------------------
local slowPulseCore = newPart(
	"SlowPulseCore",
	Vector3.new(1.4, 1.4, 1.4),
	ORIGIN * CFrame.new(0, 3.4, 0),
	TEAL_GLOW,
	Enum.Material.Neon,
	model
)
slowPulseCore.Shape = Enum.PartType.Ball
slowPulseCore.CanCollide = false

local muzzlePoint = Instance.new("Attachment")
muzzlePoint.Name = "MuzzlePoint"
muzzlePoint.Parent = slowPulseCore

model.PrimaryPart = base
model:SetAttribute("BuildingType", "CoralBarrier")
model:SetAttribute("Stage", 1)

print("[Abyssara] CoralBarrier erzeugt unter Workspace.Assets.Buildings")
