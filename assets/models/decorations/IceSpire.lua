--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Event-Kosmetik-Dekoration (Plot-Baufeld)
	Name: IceSpire ("Ice Spire" – Frozen Current Shop-Item, Abschnitt 1.3:
	"translucent blue crystal spike cluster")
	Beschreibung:
		Cluster aus translucenten, blauen Eiskristallspitzen unterschiedlicher
		Höhe auf einem vereisten Sockel. Kaufbar im Frozen-Current-Event-Shop
		für 65 Frost Shards.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (siehe assets/models/README.md):
		- Model.PrimaryPart = "Base" (Sockel-Part)
		- model:SetAttribute("DecorationId", "IceSpire")
		- model:SetAttribute("Event", "FrozenCurrent")
		- Footprint klein (< 15 Stud Baufeld-Durchmesser), passt auf EIN
		  BuildField.
		- Wird unter Workspace.Assets.Decorations abgelegt.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein
		Script unter ServerScriptService einfügen und einmal laufen lassen.
		Reine Geometrie-Erzeugung, keine Gameplay-Logik. Idempotent.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(36, 1, -100) -- Vor Ausführung anpassen für gewünschte Position
-- // ----------------------------------------------------------------------

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

local previous = decorationsFolder:FindFirstChild("IceSpire")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "IceSpire"
model.Parent = decorationsFolder

-- 1) Vereister Sockel ------------------------------------------------------------
local base = newPart("Base", Vector3.new(4, 0.6, 4), ORIGIN, Color3.fromRGB(200, 220, 235), Enum.Material.Ice, model)
base.CanCollide = true

-- 2) Kristallspitzen-Cluster (5 Spikes unterschiedlicher Höhe/Position) ---------
local spikeOffsets = {
	{ pos = Vector3.new(0, 0, 0), height = 5.5, width = 1.4 },
	{ pos = Vector3.new(-1.2, 0, -0.8), height = 3.4, width = 0.9 },
	{ pos = Vector3.new(1.3, 0, -0.5), height = 2.8, width = 0.8 },
	{ pos = Vector3.new(-0.8, 0, 1.2), height = 3.9, width = 1.0 },
	{ pos = Vector3.new(1.0, 0, 1.1), height = 2.3, width = 0.7 },
}

for i, spec in ipairs(spikeOffsets) do
	local spike = newPart(
		"IceSpike" .. i,
		Vector3.new(spec.width, spec.height, spec.width),
		ORIGIN * CFrame.new(spec.pos.X, spec.height / 2 + 0.3, spec.pos.Z) * CFrame.Angles(math.rad((i % 2 == 0) and 4 or -4), math.rad(15 * i), 0),
		Color3.fromRGB(150, 210, 245),
		Enum.Material.Glass,
		model
	)
	spike.Transparency = 0.35

	local core = newPart(
		"IceSpikeCore" .. i,
		Vector3.new(spec.width * 0.35, spec.height * 0.8, spec.width * 0.35),
		spike.CFrame,
		Color3.fromRGB(200, 245, 255),
		Enum.Material.Neon,
		model
	)
	core.Transparency = 0.1
end

-- 3) Ambient-Glühlicht -------------------------------------------------------------
local light = Instance.new("PointLight")
light.Name = "IceGlow"
light.Color = Color3.fromRGB(180, 230, 255)
light.Range = 12
light.Brightness = 2
light.Shadows = false
light.Parent = base

model.PrimaryPart = base
model:SetAttribute("DecorationId", "IceSpire")
model:SetAttribute("Event", "FrozenCurrent")

print("[Abyssara] IceSpire created under Workspace.Assets.Decorations")
