--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Event-Kosmetik-Dekoration (Plot-Baufeld)
	Name: MagmaVent ("Magma Vent" – Volcanic Vent Shop-Item, Abschnitt 1.3:
	"glowing crack + rising embers, 4x2x4 studs")
	Beschreibung:
		Glühender Riss im Boden mit aufsteigenden Ember-Partikeln. Kaufbar im
		Volcanic-Vent-Event-Shop für 70 Ember Shards.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (siehe assets/models/README.md):
		- Model.PrimaryPart = "Base" (Sockel-/Rissboden-Part)
		- model:SetAttribute("DecorationId", "MagmaVent")
		- model:SetAttribute("Event", "VolcanicVent")
		- Footprint 4x2x4 Studs (< 15 Stud Baufeld-Durchmesser), passt auf
		  EIN BuildField.
		- Wird unter Workspace.Assets.Decorations abgelegt.
		- "EmberEmitter" (ParticleEmitter an Attachment "EmberPoint") steht
		  bereit für den Code-Agenten, ist aber bereits aktiv (rein
		  dekorativ, low-rate) - siehe Handy-Performance-Konvention.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein
		Script unter ServerScriptService einfügen und einmal laufen lassen.
		Reine Geometrie-Erzeugung, keine Gameplay-Logik. Idempotent.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(48, 0.5, -100) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = decorationsFolder:FindFirstChild("MagmaVent")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "MagmaVent"
model.Parent = decorationsFolder

-- 1) Rissboden-Basis (dunkles Vulkangestein) -------------------------------------
local base = newPart("Base", Vector3.new(4, 0.6, 4), ORIGIN, Color3.fromRGB(40, 25, 20), Enum.Material.Rock, model)
base.CanCollide = true

-- 2) Glühender Riss (schmale Neon-Spalte quer über den Sockel) ------------------
local crack = newPart(
	"GlowCrack",
	Vector3.new(3.4, 0.15, 0.6),
	ORIGIN * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, math.rad(20), 0),
	Color3.fromRGB(255, 120, 30),
	Enum.Material.Neon,
	model
)

local crackBranch = newPart(
	"GlowCrackBranch",
	Vector3.new(1.6, 0.15, 0.4),
	ORIGIN * CFrame.new(0.6, 0.35, 0.6) * CFrame.Angles(0, math.rad(-40), 0),
	Color3.fromRGB(255, 140, 40),
	Enum.Material.Neon,
	model
)

-- 3) Umliegende, aufgebrochene Gesteinsbrocken (CSG-Optik ohne teure Union) -----
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 20)
	local rock = newPart(
		"RockChunk" .. i,
		Vector3.new(0.9, 0.7, 0.9),
		ORIGIN * CFrame.new(math.cos(angle) * 1.6, 0.55, math.sin(angle) * 1.6) * CFrame.Angles(math.rad(10 * i), math.rad(20 * i), 0),
		Color3.fromRGB(50, 32, 26),
		Enum.Material.Rock,
		model
	)
	rock.CanCollide = true
end

-- 4) Ember-Partikelemitter (aufsteigende Glut) -----------------------------------
local emberAttachment = Instance.new("Attachment")
emberAttachment.Name = "EmberPoint"
emberAttachment.Position = Vector3.new(0, 0.4, 0)
emberAttachment.Parent = crack

local emberEmitter = Instance.new("ParticleEmitter")
emberEmitter.Name = "EmberEmitter"
emberEmitter.Color = ColorSequence.new(Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 90, 20))
emberEmitter.Size = NumberSequence.new(0.25, 0.05)
emberEmitter.Transparency = NumberSequence.new(0.2, 1)
emberEmitter.Lifetime = NumberRange.new(1.2, 2)
emberEmitter.Speed = NumberRange.new(2, 4)
emberEmitter.Rate = 6
emberEmitter.SpreadAngle = Vector2.new(15, 15)
emberEmitter.Parent = emberAttachment

-- 5) Glühlicht -----------------------------------------------------------------
local light = Instance.new("PointLight")
light.Name = "VentGlow"
light.Color = Color3.fromRGB(255, 130, 40)
light.Range = 14
light.Brightness = 2.5
light.Shadows = false
light.Parent = crack

model.PrimaryPart = base
model:SetAttribute("DecorationId", "MagmaVent")
model:SetAttribute("Event", "VolcanicVent")

print("[Abyssara] MagmaVent erzeugt unter Workspace.Assets.Decorations")
