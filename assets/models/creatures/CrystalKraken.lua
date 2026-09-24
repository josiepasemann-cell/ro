--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: CrystalKraken ("Kristallkrake")
	Rarity (Platzhalter): Legendary
	Beschreibung:
		Kleiner, stilisierter Kraken mit halbtransparentem Kristall-Kopf
		(Material.Glass, violett) und 6 sich verjüngenden, leicht gebogenen
		Tentakelarmen. Höchste Rarity-Stufe des MVP-Sets. Zone: TwilightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Kristall-Kopf) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/
		  Schwebeanimation.
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-22, 6, 60) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Legendary"
local ZONE = "TwilightZone"
local TENTACLE_COUNT = 6
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

local previous = creaturesFolder:FindFirstChild("CrystalKraken")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "CrystalKraken"
model.Parent = creaturesFolder

local CRYSTAL_COLOR = Color3.fromRGB(180, 110, 255)
local GLOW_COLOR = Color3.fromRGB(200, 140, 255)

-- 1) Kristall-Kopf (halbtransparentes Glas) -------------------------------------
local body = newPart("Body", Vector3.new(2.4, 2.4, 2.4), ORIGIN, CRYSTAL_COLOR, Enum.Material.Glass, model)
body.Shape = Enum.PartType.Ball
body.Transparency = 0.2

-- 2) Innerer Glow-Kern -------------------------------------------------------------
local core = newPart("GlowCore", Vector3.new(1.0, 1.0, 1.0), ORIGIN, GLOW_COLOR, Enum.Material.Neon, model)
core.Shape = Enum.PartType.Ball

-- 3) Zwei Augen ----------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.7, 0.3, 1.0)
	local eye = newPart("Eye" .. i, Vector3.new(0.4, 0.4, 0.4), eyeCFrame, Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
end

-- 4) 6 Tentakelarme, radial verteilt, aus 3 sich verjüngenden Segmenten je Arm ------
for t = 1, TENTACLE_COUNT do
	local angle = math.rad(60 * (t - 1))
	local baseOffset = Vector3.new(math.cos(angle) * 1.0, -1.0, math.sin(angle) * 1.0)
	local armCFrame = ORIGIN * CFrame.new(baseOffset) * CFrame.Angles(0, angle, math.rad(-100))

	local currentCFrame = armCFrame
	for seg = 1, 3 do
		local segLength = 1.3 - seg * 0.15
		local width = 0.55 - seg * 0.12
		local curl = math.rad(18)

		currentCFrame = currentCFrame * CFrame.Angles(curl, 0, 0) * CFrame.new(0, segLength / 2, 0)

		newPart(
			"Tentacle" .. t .. "_Segment" .. seg,
			Vector3.new(width, segLength, width),
			currentCFrame,
			CRYSTAL_COLOR,
			Enum.Material.Glass,
			model
		)

		currentCFrame = currentCFrame * CFrame.new(0, segLength / 2, 0)
	end

	-- Leuchtende Saugnapf-Spitze am Ende jedes Arms
	local tip = newPart(
		"TentacleTip" .. t,
		Vector3.new(0.3, 0.3, 0.3),
		currentCFrame,
		GLOW_COLOR,
		Enum.Material.Neon,
		model
	)
	tip.Shape = Enum.PartType.Ball
end

-- 5) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Crystal Kraken")

print("[Abyssara] CrystalKraken created under Workspace.Assets.Creatures")
