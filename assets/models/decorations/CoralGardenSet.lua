--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Event-Kosmetik-Dekoration (Plot-Baufeld)
	Name: CoralGardenSet ("Coral Garden" – Bioluminescent Bloom Shop-Item,
	Abschnitt 1.3: "3 kleine leuchtende Korallen-Cluster")
	Beschreibung:
		Set aus 3 kleinen, farbwechselnden Korallenclustern, gemeinsam auf
		einem einzigen Sockel angeordnet, damit das gesamte Set EIN Baufeld
		belegt (wie ein normales Dekorations-Item). Kaufbar im Bloom-Event-
		Shop für 65 Bloom Dust.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (siehe assets/models/README.md):
		- Model.PrimaryPart = "Base" (gemeinsamer Sockel für das ganze Set)
		- model:SetAttribute("DecorationId", "CoralGardenSet")
		- model:SetAttribute("Event", "BioluminescentBloom")
		- Die 3 Cluster heißen "Cluster1".."Cluster3" (jeweils ein Model mit
		  eigenem PrimaryPart "ClusterBase") - falls der Code-Agent sie
		  später einzeln pulsieren lassen will.
		- Footprint klein (< 15 Stud Baufeld-Durchmesser), passt auf EIN
		  BuildField trotz 3 Clustern.
		- Wird unter Workspace.Assets.Decorations abgelegt.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein
		Script unter ServerScriptService einfügen und einmal laufen lassen.
		Reine Geometrie-Erzeugung, keine Gameplay-Logik. Idempotent.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(24, 0.5, -100) -- Vor Ausführung anpassen für gewünschte Position
-- // ----------------------------------------------------------------------

local CLUSTER_COLORS = {
	Color3.fromRGB(255, 90, 200),
	Color3.fromRGB(90, 220, 255),
	Color3.fromRGB(170, 255, 90),
}

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

-- Oval/egg-shaped "ball" helper: a Part with Shape=Ball only ever renders as
-- a sphere using its SMALLEST axis as diameter (Roblox does not stretch
-- balls). For elongated shapes we use a plain Block with a child SpecialMesh
-- (MeshType=Sphere), which Roblox stretches to Size * Scale - this keeps the
-- part's own Size/CFrame as the true collision/connectivity footprint while
-- letting the mesh render the intended ellipsoid.
local function newOvalPart(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 1)
	mesh.Parent = part
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local decorationsFolder = getOrCreateFolder(assetsFolder, "Decorations")

local previous = decorationsFolder:FindFirstChild("CoralGardenSet")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "CoralGardenSet"
model.Parent = decorationsFolder

-- 1) Gemeinsamer Sockel ---------------------------------------------------------
local base = newPart("Base", Vector3.new(5, 0.5, 5), ORIGIN, Color3.fromRGB(210, 200, 160), Enum.Material.Sand, model)
base.CanCollide = true

-- 2) Drei kleine Korallen-Cluster ------------------------------------------------
local clusterOffsets = {
	Vector3.new(-1.6, 0, -1.2),
	Vector3.new(1.5, 0, -0.6),
	Vector3.new(0, 0, 1.7),
}

for i = 1, 3 do
	local clusterModel = Instance.new("Model")
	clusterModel.Name = "Cluster" .. i
	clusterModel.Parent = model

	local clusterCFrame = ORIGIN * CFrame.new(clusterOffsets[i])
	local color = CLUSTER_COLORS[i]

	local clusterBase = newPart(
		"ClusterBase",
		Vector3.new(0.8, 0.4, 0.8),
		clusterCFrame,
		Color3.fromRGB(150, 130, 100),
		Enum.Material.Slate,
		clusterModel
	)

	-- 3 kleine Fronds pro Cluster: je 2 gestapelte, sich überlappende
	-- Kugelsegmente, die sich zur Spitze hin verjüngen (kein Cylinder-
	-- Achsen-Bug mehr, jedes Segment überlappt das darunterliegende UND
	-- die ClusterBase direkt).
	for j = 1, 3 do
		local angle = math.rad(120 * (j - 1))
		local baseHeight = 0.55 + (j % 2) * 0.3
		local frondX = math.cos(angle) * 0.35
		local frondZ = math.sin(angle) * 0.35

		newOvalPart(
			"Frond" .. j,
			Vector3.new(0.34, baseHeight, 0.34),
			clusterCFrame * CFrame.new(frondX, baseHeight / 2 + 0.05, frondZ),
			color,
			Enum.Material.Neon,
			clusterModel
		)

		local tipHeight = baseHeight * 0.75
		newOvalPart(
			"Frond" .. j .. "Tip",
			Vector3.new(0.22, tipHeight, 0.22),
			clusterCFrame * CFrame.new(frondX, baseHeight + tipHeight / 2 - 0.12, frondZ) * CFrame.Angles(math.rad(8 * j), math.rad(angle * 20), 0),
			color,
			Enum.Material.Neon,
			clusterModel
		)
	end

	-- Ein paar kleine Kiesel/Polypen am Fuß jedes Clusters für mehr Lebendigkeit
	for k = 1, 2 do
		local angle = math.rad(120 * k + 40)
		newPart(
			"Pebble" .. k,
			Vector3.new(0.22, 0.16, 0.22),
			clusterCFrame * CFrame.new(math.cos(angle) * 0.42, 0.1, math.sin(angle) * 0.42),
			Color3.fromRGB(190, 178, 150),
			Enum.Material.Slate,
			clusterModel
		).Shape = Enum.PartType.Ball
	end

	local light = Instance.new("PointLight")
	light.Name = "ClusterGlow"
	light.Color = color
	light.Range = 8
	light.Brightness = 1.8
	light.Shadows = false
	light.Parent = clusterBase

	clusterModel.PrimaryPart = clusterBase
end

model.PrimaryPart = base
model:SetAttribute("DecorationId", "CoralGardenSet")
model:SetAttribute("Event", "BioluminescentBloom")

print("[Abyssara] CoralGardenSet created under Workspace.Assets.Decorations")
