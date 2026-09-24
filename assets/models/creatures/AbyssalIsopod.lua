--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: AbyssalIsopod ("Abgrund-Assel")
	Rarity (Platzhalter): Rare
	Beschreibung:
		Segmentierter, ovaler Körper aus 4 leicht versetzten, blockigen
		Segmenten, blass graviolett, mit leuchtender Unterseiten-Naht (Neon,
		cyan). Zone: HadalDepths.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (mittleres Hauptsegment) -> für
		  Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Einroll-/Ausroll-Animation (4s-Zyklus, Teile "Segment1"..
		  "Segment4" markieren die zu rotierenden Segmente).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-5, 6, 90) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Rare"
local ZONE = "HadalDepths"
local SEGMENT_COUNT = 4
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
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("AbyssalIsopod")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "AbyssalIsopod"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(90, 80, 110)
local SEAM_COLOR = Color3.fromRGB(120, 200, 255)

-- 1) 4 gestapelte, leicht versetzte Körpersegmente -----------------------------------
local body
local segmentZ = {-1.3, -0.4, 0.5, 1.4}
local segmentWidth = {2.4, 3.0, 2.9, 2.2}
for i = 1, SEGMENT_COUNT do
	local segment = newPart(
		"Segment" .. i,
		Vector3.new(segmentWidth[i], 1.6, 1.0),
		ORIGIN * CFrame.new(0, 0, segmentZ[i]),
		BODY_COLOR,
		Enum.Material.SmoothPlastic,
		model
	)
	if i == 2 then
		body = segment
		body.Name = "Body"
	end
end

-- 2) Leuchtende Unterseiten-Naht (durchgehender Neon-Streifen) ------------------------
newPart("UndersideSeam", Vector3.new(2.2, 0.2, 3.6), ORIGIN * CFrame.new(0, -0.85, 0), SEAM_COLOR, Enum.Material.Neon, model)

-- 3) Idle-Puls-Attachment -----------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Abyssal Isopod")

print("[Abyssara] AbyssalIsopod created under Workspace.Assets.Creatures")
