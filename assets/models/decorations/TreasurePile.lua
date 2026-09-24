--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Event-Kosmetik-Dekoration (Plot-Baufeld)
	Name: TreasurePile ("Treasure Pile" – Treasure Tide Shop-Item, Abschnitt
	1.3: "gold coin/chest cluster")
	Beschreibung:
		Häufchen aus goldenen Münzen mit einer halb geöffneten Schatztruhe.
		Kaufbar im Treasure-Tide-Event-Shop für 60 Doubloons.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (siehe assets/models/README.md):
		- Model.PrimaryPart = "Base" (Sockel-Part)
		- model:SetAttribute("DecorationId", "TreasurePile")
		- model:SetAttribute("Event", "TreasureTide")
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
local ORIGIN = CFrame.new(60, 0.5, -100) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = decorationsFolder:FindFirstChild("TreasurePile")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TreasurePile"
model.Parent = decorationsFolder

-- 1) Sockel-Base --------------------------------------------------------------
local base = newPart("Base", Vector3.new(4, 0.5, 4), ORIGIN, Color3.fromRGB(210, 200, 160), Enum.Material.Sand, model)
base.CanCollide = true

-- 2) Truhe (Korpus + angewinkelter Deckel) --------------------------------------
local chestBody = newPart(
	"ChestBody",
	Vector3.new(2, 1.1, 1.4),
	ORIGIN * CFrame.new(-0.6, 0.8, 0),
	Color3.fromRGB(120, 75, 35),
	Enum.Material.Wood,
	model
)
chestBody.CanCollide = true

local chestLid = newPart(
	"ChestLid",
	Vector3.new(2, 0.25, 1.5),
	ORIGIN * CFrame.new(-0.6, 1.5, -0.55) * CFrame.Angles(math.rad(-55), 0, 0),
	Color3.fromRGB(140, 90, 45),
	Enum.Material.Wood,
	model
)

local chestTrim = newPart(
	"ChestTrim",
	Vector3.new(2.05, 0.15, 1.45),
	ORIGIN * CFrame.new(-0.6, 1.05, 0),
	Color3.fromRGB(230, 190, 70),
	Enum.Material.Metal,
	model
)

-- 3) Münzhaufen (gestapelte, leicht rotierte flache Zylinder) -------------------
for i = 1, 10 do
	local angle = math.rad(36 * i)
	local radius = 0.6 + (i % 3) * 0.25
	local coin = newPart(
		"Coin" .. i,
		Vector3.new(0.15, 0.55, 0.55),
		ORIGIN * CFrame.new(0.8 + math.cos(angle) * radius, 0.35 + (i % 4) * 0.12, math.sin(angle) * radius)
			* CFrame.Angles(0, angle, math.rad(90)),
		Color3.fromRGB(255, 215, 90),
		Enum.Material.Metal,
		model
	)
	coin.Shape = Enum.PartType.Cylinder
end

-- 4) Glänzende Neon-Akzente (Funkeln aus der Truhe) ------------------------------
for i = 1, 3 do
	local sparkle = newPart(
		"Sparkle" .. i,
		Vector3.new(0.25, 0.25, 0.25),
		ORIGIN * CFrame.new(-0.6 + 0.3 * (i - 2), 1.65 + i * 0.1, -0.1),
		Color3.fromRGB(255, 240, 180),
		Enum.Material.Neon,
		model
	)
	sparkle.Shape = Enum.PartType.Ball
end

-- 5) Glühlicht -------------------------------------------------------------------
local light = Instance.new("PointLight")
light.Name = "GoldGlow"
light.Color = Color3.fromRGB(255, 220, 130)
light.Range = 10
light.Brightness = 1.8
light.Shadows = false
light.Parent = chestTrim

model.PrimaryPart = base
model:SetAttribute("DecorationId", "TreasurePile")
model:SetAttribute("Event", "TreasureTide")

print("[Abyssara] TreasurePile created under Workspace.Assets.Decorations")
