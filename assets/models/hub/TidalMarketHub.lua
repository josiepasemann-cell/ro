--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Hub-Welt
	Name: TidalMarketHub

	Auftrag: GDD Abschnitt 4 ("Hub-Welt 'Tidal Market': Handelsdock,
	NPC-Händlern, Leaderboard-Anzeigen, Portalen zu den Trench-Zonen") und
	Abschnitt 8 ("Hub-Welt 'Tidal Market': zentrale Marktplatz-Struktur mit
	Handelsdock, NPC-Ständen, Portal-Toren zu den 4 Zonen").

	WELTPLATZIERUNG (wichtig – bitte vor Änderungen lesen):
		Aus PlotRegistry.lua (nur gelesen, nicht verändert) geht hervor, dass
		Spieler-Plot-Slots bei (0,0,0) beginnen und sich in einem Raster mit
		SLOT_SPACING = 200 Studs über x:[0, 1800+] / z:[0, 1800+ pro Zeile]
		ausbreiten (siehe `slotOrigin`/`SLOTS_PER_ROW` dort). Gleichzeitig
		sind alle vier Zonen-Terrain-Chunks (assets/models/terrain/*.lua,
		nur gelesen) rund um den Weltursprung (0,0,0) in einem Radius von
		ca. 170 Studs angeordnet (ORIGIN-Kommentare "Portal-Richtung: ... =
		Richtung Hub" deuten ursprünglich auf (0,0,0) als Hub-Standort hin).
		Das würde den Hub jedoch direkt mit Plot-Slot #1 UND dem
		Zonen-Chunk-Cluster überlappen lassen – ein Platzkonflikt zwischen
		zwei bereits bestehenden, hier nicht änderbaren Systemen.

		PRAGMATISCHE LÖSUNG (dokumentiert, siehe auch README "hub"-Abschnitt):
			Der Hub wird bewusst an einer eigenen, kollisionsfreien Stelle
			gebaut (ORIGIN unten, weit entfernt sowohl vom Plot-Raster
			[x/z >= 0] als auch vom Zonen-Cluster [Radius ~170 um (0,0,0)]).
			Zonen-Portale und der "Weg zu den Plots" sind hier bewusst
			**logische Teleport-Punkte**, keine physisch begehbaren
			Verbindungen zur echten Zonen-Geometrie oder zum echten
			Plot-Raster: PlotRegistry selbst weist jedem Spieler ohnehin
			einen zur Laufzeit wechselnden Welt-Slot zu ("Jeder Spieler kann
			je nach freiem Welt-Slot bei JEDEM Join an einer anderen
			Weltposition landen" – siehe dortiger Kommentar), ein fester
			Fußweg wäre also so oder so hinfällig. Der Code-Agent verbindet
			ZonePortal-Attribute (siehe unten) und den optionalen
			"PlotGate"-Interactable mit echter Teleport-Logik
			(z. B. `HumanoidRootPart.CFrame = ...` oder `TeleportService`
			für separate Zonen-Places).

	Angewandte Design-Prinzipien (siehe terrain-design-notes.md – dieselben
	8 Prinzipien wurden hier für die Hub-Welt angewandt):
		1. Verticality – zentrale Landmark ragt ~48 Studs auf, Handelsdock
		   und Aussichtspunkte auf leicht erhöhten Podesten.
		2. Landmarks – "Leuchtturm-Koralle" (Landmark) in der Platzmitte,
		   klar lesbar aus jeder Blickrichtung.
		3. Sichtachsen – 4 freigehaltene Gassen von der Platzmitte zu den
		   4 Zonenportalen (N/O/S/W), plus die "Plot-Straße" nach außen.
		4. Silhouetten-Lesbarkeit – große, eindeutige Blockformen (Podeste,
		   Torbögen, Leaderboard-Monolith) statt kleinteiligem Klimbim.
		5. Farbpalette/Kontrast – dunkler Tiefsee-Basalt-Grund als Bühne für
		   kräftige Neon-Akzente (Cyan/Magenta/Giftgrün/Neonorange/Violett),
		   auf Wunsch der Nutzerin bewusst grell, aber je Struktur auf 1-2
		   Leitfarben beschränkt (Lesbarkeit).
		6. Deko-Dichte-Rhythmus – dichte Deko/Licht-Taschen um Landmark und
		   Stände, ruhige, offene Platzfläche dazwischen (Bewegungsraum für
		   viele gleichzeitige Spieler).
		7. Wegführung Enge/Weite – enge Portal-Torbögen öffnen sich auf den
		   weiten, offenen Marktplatz.
		8. Performance – CSG (`UnionAsync`/`SubtractAsync`) für Landmark,
		   Torbögen und Podeste statt vieler Einzelteile; PartCount bewusst
		   im niedrigen dreistelligen Bereich (~220) für Mobile-Performance.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-/UI-AGENTEN:
		- Model.PrimaryPart = "HubBase" (die Marktplatz-Grundfläche)
		- Model-Attribute (auf "TidalMarketHub" selbst): "HubName" = "TidalMarket"
		- Interactable-Unterstrukturen (jeweils eigenes Unter-Model mit
		  PrimaryPart = "Base" und Attribut "Interactable"):
			- "ShopStand"        -> Interactable = "Shop"
			- "GachaStation"     -> Interactable = "Gacha"
			- "TradeDock"        -> Interactable = "Trade"
			- "LeaderboardBoard" -> Interactable = "Leaderboard"
			- "QuestBoard"       -> Interactable = "Quests"
		  Jede dieser Unter-Modelle besitzt zusätzlich ein Attachment
		  "InteractionPoint" (Stehpunkt/Ausrichtung für spätere Prompt-UI)
		  sowie – bei ShopStand/GachaStation/LeaderboardBoard – eine flache,
		  unbeschriftete "DisplayPanel"-Fläche (Part) als Ziel für eine
		  spätere SurfaceGui (UI-Agent).
		- 4 Zonenportale (eigene Unter-Modelle "Portal_<Zone>", PrimaryPart
		  = "Base"), Attribute: "ZonePortal" = "SunZone" | "TwilightZone" |
		  "MidnightZone" | "HadalDepths", "RequiredLevel" = 1 | 10 | 25 | 45.
		  Jedes Portal besitzt ein Attachment "TeleportPoint" (Zielanker/
		  Stehpunkt vor dem Tor) für die spätere Teleport-Logik.
		- Zusätzlich (über die im Auftrag genannten Interactables hinaus,
		  optionaler Bonus-Hook): "PlotGate"-Unter-Model am äußeren Ende der
		  Plot-Straße, Attribut "Interactable" = "PlotGate" – markiert den
		  symbolischen "Weg zum eigenen Habitat", der Code-Agent kann hier
		  optional PlotRegistry.AssignPlot()+Teleport verdrahten.
		- SpawnLocations: 6 Stück, benannt "HubSpawn1".."HubSpawn6",
		  `Neutral = true`, rund um die Landmark bzw. nahe der Plot-Straße
		  verteilt (viele gleichzeitige Joins ohne Stapelung).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein
		Script unter ServerScriptService einfügen und einmal laufen lassen.
		Reine Geometrie-Erzeugung, keine Gameplay-Logik. Idempotent:
		vorhandenes "TidalMarketHub"-Modell wird vor dem Neubau entfernt.
		Nach dem Bauen: Play-Test-Session einmal speichern (Studio ->
		File -> Save), damit `WorldSetup.server.lua` den Hub im echten
		Live-Spiel vorfindet (siehe Kopfkommentar dort – analog zum
		AssetTemplateSetup-Muster für Plot/Gebäude-Vorlagen).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
-- Bewusst weit weg vom Plot-Raster (x/z >= 0, siehe PlotRegistry.lua) und
-- vom Zonen-Chunk-Cluster (Radius ~170 um (0,0,0), siehe terrain/*.lua).
local ORIGIN = CFrame.new(-500, 0, -500)
local PLAZA_RADIUS = 110
local PLAZA_THICKNESS = 4
local RANDOM_SEED = 9001
local LANDMARK_HEIGHT = 48
local PORTAL_RING_RADIUS = 92
local STAND_RING_RADIUS = 58
-- // ----------------------------------------------------------------------

local rng = Random.new(RANDOM_SEED)
local PLAZA_TOP_Y = PLAZA_THICKNESS / 2

-- Grelle Biolumineszenz-Neon-Palette (dunkler Tiefseegrund als Kontrastbühne)
local NEON = {
	Cyan = Color3.fromRGB(70, 245, 255),
	Magenta = Color3.fromRGB(255, 60, 220),
	ToxicGreen = Color3.fromRGB(140, 255, 60),
	NeonOrange = Color3.fromRGB(255, 140, 30),
	Violet = Color3.fromRGB(170, 80, 255),
}

local DARK_BASALT = Color3.fromRGB(24, 26, 34)
local DARK_BASALT_ALT = Color3.fromRGB(30, 32, 42)
local STONE_TRIM = Color3.fromRGB(58, 60, 72)

-- // Hilfsfunktionen ------------------------------------------------------
local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
		folder = Instance.new("Folder")
		folder.Name = name
		folder.Parent = parent
	end
	return folder
end

local function newPart(name, size, cframe, color, material, parent, canCollide)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = canCollide ~= false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function newNeon(name, size, cframe, color, parent, canCollide)
	local part = newPart(name, size, cframe, color, Enum.Material.Neon, parent, canCollide)
	return part
end

local function newWedge(name, size, cframe, color, material, parent)
	local wedge = Instance.new("WedgePart")
	wedge.Name = name
	wedge.Size = size
	wedge.CFrame = cframe
	wedge.Color = color
	wedge.Material = material
	wedge.Anchored = true
	wedge.CanCollide = true
	wedge.TopSurface = Enum.SurfaceType.Smooth
	wedge.BottomSurface = Enum.SurfaceType.Smooth
	wedge.Parent = parent
	return wedge
end

local function unionParts(name, parts, color, material, parent)
	local base = table.remove(parts, 1)
	local result = base:UnionAsync(parts)
	result.Name = name
	result.Color = color
	result.Material = material
	result.Anchored = true
	result.CanCollide = true
	result.TopSurface = Enum.SurfaceType.Smooth
	result.BottomSurface = Enum.SurfaceType.Smooth
	result.Parent = parent
	return result
end

local function newAttachment(name, parent, position)
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position or Vector3.new(0, 0, 0)
	attachment.Parent = parent
	return attachment
end

local function newPointLight(parent, color, brightness, range)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness or 2
	light.Range = range or 16
	light.Shadows = false
	light.Parent = parent
	return light
end

-- // Root-Setup ------------------------------------------------------------
local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local hubFolder = getOrCreateFolder(assetsFolder, "Hub")

local previous = hubFolder:FindFirstChild("TidalMarketHub")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TidalMarketHub"
model.Parent = hubFolder

-- 1) Marktplatz-Grundfläche: dunkler Basalt-Rundplatz ----------------------
local base = Instance.new("Part")
base.Name = "HubBase"
base.Shape = Enum.PartType.Cylinder
base.Size = Vector3.new(PLAZA_THICKNESS, PLAZA_RADIUS * 2, PLAZA_RADIUS * 2)
base.CFrame = ORIGIN * CFrame.Angles(0, 0, math.rad(90))
base.Color = DARK_BASALT
base.Material = Enum.Material.Basalt
base.Anchored = true
base.CanCollide = true
base.TopSurface = Enum.SurfaceType.Smooth
base.BottomSurface = Enum.SurfaceType.Smooth
base.Parent = model

-- Dashed Neon-Lichtring am Platzrand (billige, performante "Leuchtturm"-Kontur)
local RIM_DASH_COUNT = 28
for i = 1, RIM_DASH_COUNT do
	local angle = (i / RIM_DASH_COUNT) * math.pi * 2
	local x = math.cos(angle) * (PLAZA_RADIUS - 3)
	local z = math.sin(angle) * (PLAZA_RADIUS - 3)
	local color = ({ NEON.Cyan, NEON.Magenta, NEON.Violet })[(i % 3) + 1]
	local dash = newNeon(
		"RimDash" .. i,
		Vector3.new(3.2, 0.6, 1.4),
		ORIGIN * CFrame.new(x, PLAZA_TOP_Y + 0.3, z) * CFrame.Angles(0, -angle, 0),
		color,
		model,
		false
	)
end

-- 2) Zentrale Landmark: "Leuchtturm-Koralle" (Riesenqualle + Korallenturm) -
local landmarkCFrame = ORIGIN * CFrame.new(0, PLAZA_TOP_Y, 0)

-- Stamm: gestapelte, sich verjüngende CSG-Union-Tiers (Korallenturm)
local trunkParts = {}
local trunkTiers = 5
local currentY = 0
local trunkBaseWidth = 11
for tier = 1, trunkTiers do
	local shrink = 1 - (tier - 1) * 0.16
	local w = trunkBaseWidth * shrink
	local h = LANDMARK_HEIGHT * 0.11
	local rotY = (tier % 2 == 0) and 18 or -18
	local tierCFrame = landmarkCFrame * CFrame.new(0, currentY + h / 2, 0) * CFrame.Angles(0, math.rad(rotY), 0)
	local tierPart = Instance.new("Part")
	tierPart.Name = "TrunkTier" .. tier
	tierPart.Size = Vector3.new(w, h, w)
	tierPart.CFrame = tierCFrame
	tierPart.Anchored = true
	tierPart.Parent = model
	table.insert(trunkParts, tierPart)
	currentY += h
end
local trunk = unionParts("LandmarkTrunk", trunkParts, STONE_TRIM, Enum.Material.Rock, model)

-- Glühender Kern-Riss im Stamm (vertikaler Neon-Streifen, Sichtachse nach oben)
newNeon(
	"TrunkCoreGlow",
	Vector3.new(1.4, LANDMARK_HEIGHT * 0.55, 1.4),
	landmarkCFrame * CFrame.new(0, LANDMARK_HEIGHT * 0.3, trunkBaseWidth * 0.42),
	NEON.Cyan,
	model,
	false
)

-- Riesenqualle als Krone: Hauptglocke (Neon) + hängende Tentakel in 3 Neon-Farben
local bellCFrame = landmarkCFrame * CFrame.new(0, currentY + 6, 0)
local bell = Instance.new("Part")
bell.Name = "JellyBell"
bell.Shape = Enum.PartType.Ball
bell.Size = Vector3.new(20, 13, 20)
bell.CFrame = bellCFrame
bell.Color = NEON.Cyan
bell.Material = Enum.Material.Neon
bell.Anchored = true
bell.CanCollide = false
bell.Parent = model
newPointLight(bell, NEON.Cyan, 4, 60)

local TENTACLE_COLORS = { NEON.Magenta, NEON.Violet, NEON.ToxicGreen, NEON.NeonOrange }
local TENTACLE_COUNT = 10
for i = 1, TENTACLE_COUNT do
	local angle = (i / TENTACLE_COUNT) * math.pi * 2
	local radius = 7.5
	local tx = math.cos(angle) * radius
	local tz = math.sin(angle) * radius
	local segH = rng:NextNumber(9, 15)
	local color = TENTACLE_COLORS[((i - 1) % #TENTACLE_COLORS) + 1]
	local tentacle = newNeon(
		"Tentacle" .. i,
		Vector3.new(0.9, segH, 0.9),
		bellCFrame * CFrame.new(tx, -segH / 2 - 5, tz) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, math.rad(rng:NextNumber(-8, 8))),
		color,
		model,
		false
	)
end

-- Kleine schwebende Satelliten-Glühkugeln um die Krone (Deko-Dichte-Tasche)
for i = 1, 6 do
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(9, 14)
	local satColor = TENTACLE_COLORS[rng:NextInteger(1, #TENTACLE_COLORS)]
	local sat = Instance.new("Part")
	sat.Name = "JellySatellite" .. i
	sat.Shape = Enum.PartType.Ball
	sat.Size = Vector3.new(1.6, 1.6, 1.6)
	sat.CFrame = bellCFrame * CFrame.new(math.cos(angle) * radius, rng:NextNumber(-2, 5), math.sin(angle) * radius)
	sat.Color = satColor
	sat.Material = Enum.Material.Neon
	sat.Anchored = true
	sat.CanCollide = false
	sat.Parent = model
end

-- 3) Interactable-Unterstände (Ring um die Landmark) -----------------------
local function newStandBase(name, position, color)
	local standModel = Instance.new("Model")
	standModel.Name = name
	standModel.Parent = model

	local standCFrame = landmarkCFrame * CFrame.new(position.X, 0, position.Z)
	local standBase = newPart(
		"Base",
		Vector3.new(10, 1.2, 8),
		standCFrame * CFrame.new(0, PLAZA_TOP_Y - PLAZA_TOP_Y + 0.6, 0),
		DARK_BASALT_ALT,
		Enum.Material.Basalt,
		standModel
	)

	-- Trimm-Kante (Neon) am Podest
	newNeon("BaseTrim", Vector3.new(10.3, 0.25, 8.3), standCFrame * CFrame.new(0, 1.2, 0), color, standModel, false)

	standModel.PrimaryPart = standBase
	return standModel, standCFrame, standBase
end

local function addRoofCanopy(standModel, standCFrame, color, postColor)
	-- 4 Stützpfosten + geneigtes Dach (2 Wedges), typische Marktstand-Silhouette
	local postH = 6.5
	local postOffsets = { Vector3.new(-4, 0, -3), Vector3.new(4, 0, -3), Vector3.new(-4, 0, 3), Vector3.new(4, 0, 3) }
	for i, offset in ipairs(postOffsets) do
		newPart(
			"Post" .. i,
			Vector3.new(0.6, postH, 0.6),
			standCFrame * CFrame.new(offset.X, 1.8 + postH / 2, offset.Z),
			postColor,
			Enum.Material.Metal,
			standModel
		)
	end
	local roofY = 1.8 + postH + 0.6
	newWedge(
		"RoofLeft",
		Vector3.new(5.2, 2.4, 9),
		standCFrame * CFrame.new(-2.6, roofY, 0) * CFrame.Angles(0, math.rad(90), 0),
		color,
		Enum.Material.SmoothPlastic,
		standModel
	)
	newWedge(
		"RoofRight",
		Vector3.new(5.2, 2.4, 9),
		standCFrame * CFrame.new(2.6, roofY, 0) * CFrame.Angles(0, math.rad(-90), 0),
		color,
		Enum.Material.SmoothPlastic,
		standModel
	)
	newNeon("RoofGlowSeam", Vector3.new(0.4, 0.4, 9), standCFrame * CFrame.new(0, roofY + 1.3, 0), color, standModel, false)
end

-- 3a) Shop-Stand (Interactable = "Shop") -----------------------------------
do
	local standModel, standCFrame = newStandBase("ShopStand", Vector3.new(-STAND_RING_RADIUS * 0.7, 0, -STAND_RING_RADIUS * 0.55), NEON.NeonOrange)
	addRoofCanopy(standModel, standCFrame, NEON.NeonOrange, STONE_TRIM)

	local counter = newPart("Counter", Vector3.new(9, 2.4, 2), standCFrame * CFrame.new(0, 1.8 + 1.2, 3.6), DARK_BASALT_ALT, Enum.Material.Basalt, standModel)
	newNeon("CounterTrim", Vector3.new(9.2, 0.3, 2.2), standCFrame * CFrame.new(0, 3.1, 3.6), NEON.NeonOrange, standModel, false)

	local displayPanel = newPart("DisplayPanel", Vector3.new(6, 3.4, 0.2), standCFrame * CFrame.new(0, 6.6, -2.9), Color3.fromRGB(10, 10, 14), Enum.Material.SmoothPlastic, standModel, false)

	newAttachment("InteractionPoint", standModel.Base, Vector3.new(0, 2, 5))
	newPointLight(counter, NEON.NeonOrange, 2.5, 18)

	standModel:SetAttribute("Interactable", "Shop")
end

-- 3b) Mystery-Egg-Gacha-Station (Interactable = "Gacha") -------------------
do
	local standModel, standCFrame = newStandBase("GachaStation", Vector3.new(STAND_RING_RADIUS * 0.75, 0, -STAND_RING_RADIUS * 0.4), NEON.Violet)

	-- Runder Sockel + 3 gestufte Podeste für Ei-Modelle (Platz, keine Eier selbst)
	local pedestal = Instance.new("Part")
	pedestal.Name = "GachaPedestal"
	pedestal.Shape = Enum.PartType.Cylinder
	pedestal.Size = Vector3.new(4, 7, 7)
	pedestal.CFrame = standCFrame * CFrame.new(0, 1.8 + 2, 0) * CFrame.Angles(0, 0, math.rad(90))
	pedestal.Color = STONE_TRIM
	pedestal.Material = Enum.Material.Basalt
	pedestal.Anchored = true
	pedestal.Parent = standModel

	newNeon("PedestalRing", Vector3.new(0.5, 7.4, 7.4), standCFrame * CFrame.new(0, 1.8 + 2, 0) * CFrame.Angles(0, 0, math.rad(90)), NEON.Violet, standModel, false)

	local eggSlotPositions = { Vector3.new(0, 0, 0), Vector3.new(-3.2, 0, -2), Vector3.new(3.2, 0, -2) }
	for i, pos in ipairs(eggSlotPositions) do
		local slotBase = newPart(
			"EggSlotBase" .. i,
			Vector3.new(1.6, 0.4, 1.6),
			standCFrame * CFrame.new(pos.X, 1.8 + 4.2 + 0.2, pos.Z),
			DARK_BASALT_ALT,
			Enum.Material.Basalt,
			standModel,
			false
		)
		newAttachment("EggDisplaySlot" .. i, slotBase, Vector3.new(0, 0.5, 0))
	end

	local displayPanel = newPart("DisplayPanel", Vector3.new(5, 3, 0.2), standCFrame * CFrame.new(0, 9.5, 0), Color3.fromRGB(10, 10, 14), Enum.Material.SmoothPlastic, standModel, false)
	newAttachment("InteractionPoint", standModel.Base, Vector3.new(0, 2, 5))
	newPointLight(pedestal, NEON.Violet, 3, 20)

	standModel:SetAttribute("Interactable", "Gacha")
end

-- 3c) Handelsdock (Interactable = "Trade") ----------------------------------
do
	local dockModel = Instance.new("Model")
	dockModel.Name = "TradeDock"
	dockModel.Parent = model

	local dockCFrame = landmarkCFrame * CFrame.new(-STAND_RING_RADIUS * 0.15, 0, STAND_RING_RADIUS * 1.05)
	local dockBase = newPart("Base", Vector3.new(10, 1.4, 22), dockCFrame * CFrame.new(0, 0.7, 6), Color3.fromRGB(70, 58, 44), Enum.Material.WoodPlanks, dockModel)
	newNeon("DockEdgeL", Vector3.new(0.4, 0.3, 22), dockCFrame * CFrame.new(-5, 1.5, 6), NEON.ToxicGreen, dockModel, false)
	newNeon("DockEdgeR", Vector3.new(0.4, 0.3, 22), dockCFrame * CFrame.new(5, 1.5, 6), NEON.ToxicGreen, dockModel, false)

	-- 2 Handelspodeste (Spieler stehen sich beim sicheren 2-Spieler-Trade gegenüber)
	for i, zOff in ipairs({ 9, 21 }) do
		local podium = Instance.new("Part")
		podium.Name = "TradePodium" .. i
		podium.Shape = Enum.PartType.Cylinder
		podium.Size = Vector3.new(2, 3.2, 3.2)
		podium.CFrame = dockCFrame * CFrame.new(0, 0.7 + 1.6, zOff) * CFrame.Angles(0, 0, math.rad(90))
		podium.Color = DARK_BASALT_ALT
		podium.Material = Enum.Material.Basalt
		podium.Anchored = true
		podium.Parent = dockModel
		newNeon("PodiumRing" .. i, Vector3.new(2.2, 3.4, 3.4), podium.CFrame, NEON.ToxicGreen, dockModel, false)
	end

	-- Mooring-Pfosten mit Glühlaternen säumen das Dock (Deko-Dichte)
	for i, zOff in ipairs({ 3, 15, 27 }) do
		for _, side in ipairs({ -1, 1 }) do
			local postCFrame = dockCFrame * CFrame.new(side * 5.3, 2.2, zOff)
			newPart("MooringPost" .. i .. tostring(side), Vector3.new(0.8, 4.4, 0.8), postCFrame, Color3.fromRGB(60, 50, 40), Enum.Material.Wood, dockModel)
			local lantern = Instance.new("Part")
			lantern.Name = "Lantern" .. i .. tostring(side)
			lantern.Shape = Enum.PartType.Ball
			lantern.Size = Vector3.new(1, 1, 1)
			lantern.CFrame = postCFrame * CFrame.new(0, 2.6, 0)
			lantern.Color = NEON.ToxicGreen
			lantern.Material = Enum.Material.Neon
			lantern.Anchored = true
			lantern.CanCollide = false
			lantern.Parent = dockModel
			newPointLight(lantern, NEON.ToxicGreen, 2, 14)
		end
	end

	newAttachment("InteractionPoint", dockBase, Vector3.new(0, 2, 9))
	dockModel.PrimaryPart = dockBase
	dockModel:SetAttribute("Interactable", "Trade")
end

-- 3d) Leaderboard-Tafel (Interactable = "Leaderboard") ----------------------
do
	local standModel, standCFrame = newStandBase("LeaderboardBoard", Vector3.new(-STAND_RING_RADIUS * 0.85, 0, STAND_RING_RADIUS * 0.35), NEON.Cyan)

	local monolithH = 12
	local monolith = newPart(
		"Monolith",
		Vector3.new(1.4, monolithH, 9),
		standCFrame * CFrame.new(0, 1.8 + monolithH / 2, 0),
		DARK_BASALT_ALT,
		Enum.Material.Basalt,
		standModel
	)
	newNeon("MonolithFrame", Vector3.new(0.2, monolithH + 0.4, 9.3), standCFrame * CFrame.new(-0.75, 1.8 + monolithH / 2, 0), NEON.Cyan, standModel, false)

	-- Platz für SurfaceGui (UI-Agent): eine glatte, nach vorn zeigende Fläche
	local displayPanel = newPart(
		"DisplayPanel",
		Vector3.new(0.3, monolithH - 1.4, 8.2),
		standCFrame * CFrame.new(0.86, 1.8 + monolithH / 2, 0),
		Color3.fromRGB(8, 10, 14),
		Enum.Material.SmoothPlastic,
		standModel,
		false
	)

	newAttachment("InteractionPoint", standModel.Base, Vector3.new(0, 2, 5))
	newPointLight(monolith, NEON.Cyan, 2.5, 20)

	standModel:SetAttribute("Interactable", "Leaderboard")
end

-- 3e) Quest-Brett (Interactable = "Quests") ---------------------------------
do
	local standModel, standCFrame = newStandBase("QuestBoard", Vector3.new(STAND_RING_RADIUS * 0.2, 0, STAND_RING_RADIUS * 0.95), NEON.ToxicGreen)

	local postL = newPart("PostL", Vector3.new(0.7, 6.5, 0.7), standCFrame * CFrame.new(-3.2, 1.8 + 3.25, 0), STONE_TRIM, Enum.Material.Metal, standModel)
	local postR = newPart("PostR", Vector3.new(0.7, 6.5, 0.7), standCFrame * CFrame.new(3.2, 1.8 + 3.25, 0), STONE_TRIM, Enum.Material.Metal, standModel)
	local boardPanel = newPart(
		"DisplayPanel",
		Vector3.new(7, 4.6, 0.3),
		standCFrame * CFrame.new(0, 1.8 + 5.4, 0),
		Color3.fromRGB(46, 36, 26),
		Enum.Material.WoodPlanks,
		standModel,
		false
	)
	newNeon("BoardFrame", Vector3.new(7.3, 4.9, 0.15), standCFrame * CFrame.new(0, 1.8 + 5.4, -0.2), NEON.ToxicGreen, standModel, false)

	newAttachment("InteractionPoint", standModel.Base, Vector3.new(0, 2, 4))
	newPointLight(boardPanel, NEON.ToxicGreen, 2, 16)

	standModel:SetAttribute("Interactable", "Quests")
end

-- 4) Zonenportale (4x, Ring am Platzrand, N/O/S/W) --------------------------
local PORTAL_DEFS = {
	{
		Zone = "SunZone",
		DisplayName = "Sonnenzone",
		RequiredLevel = 1,
		Angle = math.rad(0),
		Color = NEON.NeonOrange,
	},
	{
		Zone = "TwilightZone",
		DisplayName = "Dämmerzone",
		RequiredLevel = 10,
		Angle = math.rad(90),
		Color = NEON.Cyan,
	},
	{
		Zone = "MidnightZone",
		DisplayName = "Mitternachtszone",
		RequiredLevel = 25,
		Angle = math.rad(180),
		Color = NEON.Magenta,
	},
	{
		Zone = "HadalDepths",
		DisplayName = "Hadal-Tiefe",
		RequiredLevel = 45,
		Angle = math.rad(270),
		Color = NEON.Violet,
	},
}

for _, def in ipairs(PORTAL_DEFS) do
	local portalModel = Instance.new("Model")
	portalModel.Name = "Portal_" .. def.Zone
	portalModel.Parent = model

	local px = math.cos(def.Angle) * PORTAL_RING_RADIUS
	local pz = math.sin(def.Angle) * PORTAL_RING_RADIUS
	-- Torbogen schaut von der Platzmitte nach außen (facing = Winkel + 180°,
	-- damit die Vorderseite Richtung Platzmitte zeigt)
	local portalCFrame = landmarkCFrame * CFrame.new(px, 0, pz) * CFrame.Angles(0, def.Angle + math.pi / 2, 0)

	local pillarH = 11
	local pillarL = Instance.new("Part")
	pillarL.Size = Vector3.new(2.4, pillarH, 2.4)
	pillarL.CFrame = portalCFrame * CFrame.new(-5, pillarH / 2, 0)
	pillarL.Anchored = true
	pillarL.Parent = portalModel

	local pillarR = Instance.new("Part")
	pillarR.Size = Vector3.new(2.4, pillarH, 2.4)
	pillarR.CFrame = portalCFrame * CFrame.new(5, pillarH / 2, 0)
	pillarR.Anchored = true
	pillarR.Parent = portalModel

	local lintel = Instance.new("Part")
	lintel.Size = Vector3.new(12.4, 2.6, 2.4)
	lintel.CFrame = portalCFrame * CFrame.new(0, pillarH + 1.3, 0)
	lintel.Anchored = true
	lintel.Parent = portalModel

	local arch = unionParts("PortalArch", { pillarL, pillarR, lintel }, STONE_TRIM, Enum.Material.Basalt, portalModel)

	-- Glühendes Portal-"Gate" (flache, leicht transparente Neon-Scheibe)
	local gate = Instance.new("Part")
	gate.Name = "Base"
	gate.Shape = Enum.PartType.Cylinder
	gate.Size = Vector3.new(0.6, 9.5, 9.5)
	gate.CFrame = portalCFrame * CFrame.new(0, pillarH / 2 + 0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
	gate.Color = def.Color
	gate.Material = Enum.Material.Neon
	gate.Transparency = 0.25
	gate.Anchored = true
	gate.CanCollide = false
	gate.Parent = portalModel
	newPointLight(gate, def.Color, 3.5, 26)

	-- Zonentafel über dem Torbogen mit Anzeigename + Level-Hinweis
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ZoneLabel"
	billboard.Size = UDim2.new(0, 200, 0, 50)
	billboard.StudsOffset = Vector3.new(0, pillarH + 3.4, 0)
	billboard.AlwaysOnTop = false
	billboard.Parent = gate

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.65, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.TextColor3 = def.Color
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextScaled = true
	nameLabel.Text = def.DisplayName
	nameLabel.Parent = billboard

	local levelLabel = Instance.new("TextLabel")
	levelLabel.Name = "LevelLabel"
	levelLabel.Size = UDim2.new(1, 0, 0.35, 0)
	levelLabel.Position = UDim2.new(0, 0, 0.65, 0)
	levelLabel.BackgroundTransparency = 1
	levelLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	levelLabel.Font = Enum.Font.Gotham
	levelLabel.TextScaled = true
	levelLabel.Text = "Level " .. tostring(def.RequiredLevel) .. "+"
	levelLabel.Parent = billboard

	-- Kurze, freigehaltene Sichtachse: 2 Bodenmarkierungen leiten den Blick
	-- vom Portal zur Platzmitte (Design-Prinzip 3 & 7)
	for step = 1, 2 do
		local dist = PORTAL_RING_RADIUS - step * 18
		local lx = math.cos(def.Angle) * dist
		local lz = math.sin(def.Angle) * dist
		newNeon(
			"LaneMarker_" .. def.Zone .. step,
			Vector3.new(2.2, 0.3, 2.2),
			landmarkCFrame * CFrame.new(lx, PLAZA_TOP_Y + 0.15, lz),
			def.Color,
			model,
			false
		)
	end

	newAttachment("TeleportPoint", gate, Vector3.new(0, 0, 1.5))

	portalModel.PrimaryPart = gate
	portalModel:SetAttribute("ZonePortal", def.Zone)
	portalModel:SetAttribute("RequiredLevel", def.RequiredLevel)
end

-- 5) Plot-Straße: leuchtender, symbolischer Weg zu den Spieler-Plots -------
-- (siehe Kopfkommentar: physisch nicht mit dem echten, laufzeit-dynamischen
-- Plot-Raster aus PlotRegistry verbunden - rein visuelle Wegführung, endet
-- an einem "PlotGate"-Interactable-Hook für den Code-Agenten.)
do
	local roadModel = Instance.new("Model")
	roadModel.Name = "PlotRoad"
	roadModel.Parent = model

	local roadDir = Vector3.new(1, 0, 1).Unit
	local roadStartDist = PLAZA_RADIUS + 4
	local roadSegments = 12
	local roadSegmentGap = 9
	for i = 1, roadSegments do
		local dist = roadStartDist + (i - 1) * roadSegmentGap
		local fade = 1 - (i / roadSegments) * 0.6 -- Segmente werden zum Ende hin schmaler
		local pos = landmarkCFrame.Position + roadDir * dist
		newNeon(
			"RoadDash" .. i,
			Vector3.new(3 * fade, 0.3, 1.4 * fade),
			CFrame.new(pos.X, PLAZA_TOP_Y + 0.15, pos.Z) * CFrame.Angles(0, -math.atan2(roadDir.Z, roadDir.X), 0),
			NEON.ToxicGreen,
			roadModel,
			false
		)
	end

	-- PlotGate: kleiner Torbogen am äußeren Ende der Straße
	local gateDist = roadStartDist + roadSegments * roadSegmentGap + 6
	local gatePos = landmarkCFrame.Position + roadDir * gateDist
	local gateCFrame = CFrame.new(gatePos) * CFrame.Angles(0, -math.atan2(roadDir.Z, roadDir.X), 0)

	local gateModel = Instance.new("Model")
	gateModel.Name = "PlotGate"
	gateModel.Parent = model

	local gPillarL = Instance.new("Part")
	gPillarL.Size = Vector3.new(1.6, 7, 1.6)
	gPillarL.CFrame = gateCFrame * CFrame.new(-3.5, 3.5, 0)
	gPillarL.Anchored = true
	gPillarL.Parent = gateModel

	local gPillarR = Instance.new("Part")
	gPillarR.Size = Vector3.new(1.6, 7, 1.6)
	gPillarR.CFrame = gateCFrame * CFrame.new(3.5, 3.5, 0)
	gPillarR.Anchored = true
	gPillarR.Parent = gateModel

	local gLintel = Instance.new("Part")
	gLintel.Size = Vector3.new(8.6, 1.6, 1.6)
	gLintel.CFrame = gateCFrame * CFrame.new(0, 7.3, 0)
	gLintel.Anchored = true
	gLintel.Parent = gateModel

	local gateArch = unionParts("Base", { gPillarL, gPillarR, gLintel }, STONE_TRIM, Enum.Material.Basalt, gateModel)
	newNeon("GateGlow", Vector3.new(8.8, 0.3, 1.8), gateCFrame * CFrame.new(0, 7.3, 0), NEON.ToxicGreen, gateModel, false)
	newAttachment("InteractionPoint", gateArch, Vector3.new(0, 0, 1.5))

	gateModel.PrimaryPart = gateArch
	gateModel:SetAttribute("Interactable", "PlotGate")
end

-- 6) SpawnLocations (6x, verteilt um die Landmark / nahe Plot-Straße) ------
local SPAWN_ANGLES = { 20, 70, 130, 200, 250, 310 }
for i, deg in ipairs(SPAWN_ANGLES) do
	local angle = math.rad(deg)
	local radius = 34
	local sx = math.cos(angle) * radius
	local sz = math.sin(angle) * radius

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn" .. i
	spawn.Size = Vector3.new(6, 1, 6)
	spawn.CFrame = landmarkCFrame * CFrame.new(sx, 0.5, sz)
	spawn.Color = DARK_BASALT_ALT
	spawn.Material = Enum.Material.Basalt
	spawn.Anchored = true
	spawn.CanCollide = true
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = model
	newNeon("SpawnRing" .. i, Vector3.new(6.3, 0.15, 6.3), spawn.CFrame * CFrame.new(0, 0.55, 0), NEON.Cyan, model, false)
end

-- 7) Zusätzliche Deko-Taschen (dichte/offene Rhythmus, Kelp/Kristall-Akzente)
local DECO_COLORS = { NEON.Cyan, NEON.Magenta, NEON.ToxicGreen, NEON.NeonOrange, NEON.Violet }
for i = 1, 16 do
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = rng:NextNumber(70, PLAZA_RADIUS - 6)
	local px = math.cos(angle) * radius
	local pz = math.sin(angle) * radius
	local height = rng:NextNumber(2, 5)
	local coral = Instance.new("Part")
	coral.Name = "PlazaCoralAccent" .. i
	coral.Shape = Enum.PartType.Cylinder
	coral.Size = Vector3.new(height, 0.7, 0.7)
	coral.CFrame = landmarkCFrame * CFrame.new(px, PLAZA_TOP_Y + height / 2, pz) * CFrame.Angles(0, 0, math.rad(90))
	coral.Color = DECO_COLORS[rng:NextInteger(1, #DECO_COLORS)]
	coral.Material = Enum.Material.Neon
	coral.Anchored = true
	coral.CanCollide = false
	coral.Parent = model
end

model.PrimaryPart = base
model:SetAttribute("HubName", "TidalMarket")

print("[Abyssara] TidalMarketHub erzeugt unter Workspace.Assets.Hub (ORIGIN = " .. tostring(ORIGIN.Position) .. ")")
