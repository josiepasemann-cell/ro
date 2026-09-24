--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GlowRay ("Leuchtrochen") - freie 6. Kreatur des MVP-Sets
	Rarity (Platzhalter): Uncommon
	Beschreibung:
		Flacher, rautenförmiger Rochenkörper (per CSG-Union aus zwei
		Keil-Parts "verschmolzen") mit dünnem Peitschenschwanz und
		leuchtendem Kantenrand. Zone: SunZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (der Rautenkörper) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/Schwebeanimation.
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(12, 5, 60) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Uncommon"
local ZONE = "SunZone"
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

local previous = creaturesFolder:FindFirstChild("GlowRay")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowRay"
model.Parent = creaturesFolder

local RAY_COLOR = Color3.fromRGB(120, 150, 255)
local GLOW_COLOR = Color3.fromRGB(140, 220, 255)

-- 1) Rautenkörper per CSG-Union aus zwei Wedge-Parts -------------------------
local wedgeFrontCFrame = ORIGIN * CFrame.new(0, 0, 1.4)
local wedgeFront = Instance.new("WedgePart")
wedgeFront.Name = "WedgeFront"
wedgeFront.Size = Vector3.new(3.2, 0.6, 2.8)
wedgeFront.CFrame = wedgeFrontCFrame * CFrame.Angles(0, math.rad(180), 0)
wedgeFront.Color = RAY_COLOR
wedgeFront.Material = Enum.Material.SmoothPlastic
wedgeFront.Anchored = true
wedgeFront.Parent = Workspace

local wedgeBackCFrame = ORIGIN * CFrame.new(0, 0, -1.4)
local wedgeBack = Instance.new("WedgePart")
wedgeBack.Name = "WedgeBack"
wedgeBack.Size = Vector3.new(3.2, 0.6, 2.8)
wedgeBack.CFrame = wedgeBackCFrame
wedgeBack.Color = RAY_COLOR
wedgeBack.Material = Enum.Material.SmoothPlastic
wedgeBack.Anchored = true
wedgeBack.Parent = Workspace

local body = wedgeFront:UnionAsync({ wedgeBack })
body.Name = "Body"
body.Color = RAY_COLOR
body.Material = Enum.Material.SmoothPlastic
body.Anchored = true
body.CanCollide = false
body.Parent = model

-- 2) Leuchtender Kantenrand (dünner Ring unter dem Körper) -------------------
local rim = newPart("GlowRim", Vector3.new(3.4, 0.12, 3.0), ORIGIN * CFrame.new(0, -0.28, 0), GLOW_COLOR, Enum.Material.Neon, model)
rim.Transparency = 0.1

-- 3) Peitschenschwanz (3 sich verjüngende Segmente) --------------------------
local currentCFrame = ORIGIN * CFrame.new(0, 0, -2.6)
for i = 1, 3 do
	local segLength = 1.4 - i * 0.15
	local width = 0.35 - i * 0.06
	currentCFrame = currentCFrame * CFrame.new(0, 0, -segLength / 2)
	newPart("TailSegment" .. i, Vector3.new(width, width, segLength), currentCFrame, RAY_COLOR, Enum.Material.SmoothPlastic, model)
	currentCFrame = currentCFrame * CFrame.new(0, 0, -segLength / 2)
end

-- 4) Zwei kleine Augen (Glow) --------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.5, 0.15, 1.3)
	local eye = newPart("Eye" .. i, Vector3.new(0.25, 0.25, 0.25), eyeCFrame, Color3.fromRGB(20, 20, 25), Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
end

-- 5) Idle-Puls-Attachment -----------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Leuchtrochen")

print("[Abyssara] GlowRay erzeugt unter Workspace.Assets.Creatures")
