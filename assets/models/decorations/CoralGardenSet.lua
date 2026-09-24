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

	-- 3 kleine Fronds pro Cluster (Neon-Kegelform via WedgePart-Stapel)
	for j = 1, 3 do
		local angle = math.rad(120 * (j - 1))
		local height = 1.0 + (j % 2) * 0.5
		local frond = newPart(
			"Frond" .. j,
			Vector3.new(0.3, height, 0.3),
			clusterCFrame * CFrame.new(math.cos(angle) * 0.35, height / 2 + 0.2, math.sin(angle) * 0.35)
				* CFrame.Angles(math.rad(10), 0, 0),
			color,
			Enum.Material.Neon,
			clusterModel
		)
		frond.Shape = Enum.PartType.Cylinder
		frond.CFrame = frond.CFrame * CFrame.Angles(0, 0, math.rad(90))
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

print("[Abyssara] CoralGardenSet erzeugt unter Workspace.Assets.Decorations")
