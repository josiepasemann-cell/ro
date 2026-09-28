--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: CrystalKraken ("Kristallkrake")
	Rarity (Platzhalter): Legendary
	Beschreibung:
		Kleiner, stilisierter Kraken mit halbtransparentem Kristall-Kopf
		(Material.Glass, violett, Ellipsoid), sichtbarem Glow-Kern, Zackenkrone
		zwischen Kopf und Tentakeln, und 6 sich verjüngenden, gebogenen
		Tentakelarmen mit leuchtenden Saugnapf-Spitzen. Zone: TwilightZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Kristall-Kopf) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/
		  Schwebeanimation.
		- Teile "Tentacle1_Segment1".."Tentacle6_Segment1" starten mit dem
		  Präfix "Tentacle", werden also von IdleSway automatisch geschwenkt.
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

local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
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
local CRYSTAL_DARK = Color3.fromRGB(120, 70, 190)
local GLOW_COLOR = Color3.fromRGB(200, 140, 255)

-- 1) Kristall-Kopf (halbtransparentes Glas, Ellipsoid) ---------------------------
local body = newBall("Body", Vector3.new(2.4, 2.5, 2.4), ORIGIN, CRYSTAL_COLOR, Enum.Material.Glass, model)
body.Transparency = 0.2

-- 2) Innerer Glow-Kern -------------------------------------------------------------
newBall("GlowCore", Vector3.new(1.1, 1.1, 1.1), ORIGIN, GLOW_COLOR, Enum.Material.Neon, model)

-- 3) Zackenkrone auf dem Kopf, in die Kopfkuppel eingebettet ------------------------
for i = 1, 5 do
	local angle = math.rad(72 * (i - 1))
	local radius = 0.75
	local crownCFrame = ORIGIN * CFrame.new(math.cos(angle) * radius, 1.05, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0)
	local crown = Instance.new("WedgePart")
	crown.Name = "Crown" .. i
	crown.Size = Vector3.new(0.3, 0.55, 0.3)
	crown.CFrame = crownCFrame
	crown.Color = CRYSTAL_DARK
	crown.Material = Enum.Material.Glass
	crown.Transparency = 0.1
	crown.Anchored = true
	crown.CanCollide = false
	crown.Parent = model
end

-- 4) Zwei Augen ----------------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.7, 0.3, 1.05)
	newBall("Eye" .. i, Vector3.new(0.42, 0.42, 0.42), eyeCFrame, Color3.fromRGB(255, 255, 255), Enum.Material.Neon, model)
end

-- 5) Mantelsaum zwischen Kopf und Tentakelkranz, verbindet beide sauber --------------
newBall("MantleSkirt", Vector3.new(2.6, 0.9, 2.6), ORIGIN * CFrame.new(0, -1.0, 0), CRYSTAL_DARK, Enum.Material.Glass, model).Transparency = 0.15

-- 6) 6 Tentakelarme, radial verteilt, aus 3 sich verjüngenden, überlappenden
--    Segmenten je Arm ------------------------------------------------------------
local SEG_OVERLAP = 0.22
for t = 1, TENTACLE_COUNT do
	local angle = math.rad(60 * (t - 1))
	local radius = 1.0
	local baseOffset = Vector3.new(math.cos(angle) * radius, -1.3, math.sin(angle) * radius)
	local armCFrame = ORIGIN * CFrame.new(baseOffset) * CFrame.Angles(0, angle, math.rad(-100))

	local currentCFrame = armCFrame
	local prevHalf = 0.1
	for seg = 1, 3 do
		local segLength = 1.3 - seg * 0.15
		local width = 0.55 - seg * 0.12
		local half = segLength / 2
		local curl = math.rad(16)

		currentCFrame = currentCFrame * CFrame.Angles(curl, 0, 0) * CFrame.new(0, prevHalf + half - SEG_OVERLAP, 0)

		newPart(
			"Tentacle" .. t .. "_Segment" .. seg,
			Vector3.new(width, segLength, width),
			currentCFrame,
			CRYSTAL_COLOR,
			Enum.Material.Glass,
			model
		)

		prevHalf = half
	end

	-- Leuchtende Saugnapf-Spitze am Ende jedes Arms
	local tipCFrame = currentCFrame * CFrame.new(0, prevHalf + 0.15 - SEG_OVERLAP, 0)
	newBall(
		"TentacleTip" .. t,
		Vector3.new(0.34, 0.34, 0.34),
		tipCFrame,
		GLOW_COLOR,
		Enum.Material.Neon,
		model
	)
end

-- 7) Idle-Puls-Attachment ------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Crystal Kraken")

print("[Abyssara] CrystalKraken created under Workspace.Assets.Creatures")
