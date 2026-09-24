--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Raid-Gegner (Boss)
	Name: TrenchWardenBoss ("Der Tiefenfürst")
	Ersetzt ShadowKraken als TemplateName für RaidConfig.EnemyId "TrenchWarden"
	(Boss). Visueller Auszahlungspunkt für das "Der Tiefenfürst"-Arena-
	Landmark in MidnightZoneTerrainChunk.lua.
	Beschreibung:
		Turmhohe Kraken-Fürst-Silhouette, nahezu schwarzer Körper, 8 lange
		und dickere Tentakel (länger/wuchtiger als der alte ShadowKraken-
		Platzhalter), glühende rote Kronendorn-Cluster auf dem Kopf, größte
		Glow-Augen im Spiel, PointLight für dramatische Arena-Beleuchtung.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für serverseitige
		  Bewegungs-/Angriffssteuerung (analog zu HumanoidRootPart).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-/
		  Bedrohungs-Puls-Animation.
		- "Mantle", "Eye1", "Eye2" vorhanden -> RaidService.applyEnemyVisual()
		  überschreibt Body/Mantle.Color mit definition.BodyColor und
		  Eye1/Eye2.Color mit definition.EyeColor zur Laufzeit. Hier
		  verwendete Farben sind daher nur Vorschau-Platzhalter.
		- model:SetAttribute("EnemyTier") -> "Boss".
		- model:SetAttribute("Zone") -> Ziel-Zone, in der der Boss auftaucht
		  (Standard hier: "MidnightZone").
		- PointLight "CrownLight" an CrownSpike1 -> reine Deko-Beleuchtung
		  für die Boss-Arena, keine Gameplay-Logik.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(45, 10, -60) -- Vor Ausführung anpassen für gewünschte Position
local ENEMY_TIER = "Boss"
local ZONE = "MidnightZone"
local TENTACLE_COUNT = 8
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
local enemiesFolder = getOrCreateFolder(assetsFolder, "Enemies")

local previous = enemiesFolder:FindFirstChild("TrenchWardenBoss")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TrenchWardenBoss"
model.Parent = enemiesFolder

local SKIN_COLOR = Color3.fromRGB(15, 10, 15)
local ACCENT_COLOR = Color3.fromRGB(28, 20, 30)
local EYE_COLOR = Color3.fromRGB(255, 20, 30)
local CROWN_COLOR = Color3.fromRGB(255, 30, 40)

-- 1) Hauptkörper (turmhoch, deutlich größer als IronMawBrute) --------------------
local body = newPart("Body", Vector3.new(7.0, 6.5, 7.0), ORIGIN, SKIN_COLOR, Enum.Material.Slate, model)
body.Shape = Enum.PartType.Ball

-- 2) Mantel-Auswölbung oben ----------------------------------------------------------
local mantleCFrame = ORIGIN * CFrame.new(0, 2.6, -0.6)
newPart("Mantle", Vector3.new(5.0, 3.4, 5.0), mantleCFrame, ACCENT_COLOR, Enum.Material.Slate, model).Shape =
	Enum.PartType.Ball

-- 3) Größte Glow-Augen im Spiel -------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 1.8, 0.6, 3.2)
	local eye = newPart("Eye" .. i, Vector3.new(1.2, 1.2, 1.2), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
end

-- 4) Kronendorn-Cluster auf dem Kopf (5 Neon-Dornen) -------------------------------
local crownLight
for c = 1, 5 do
	local angle = math.rad(-60 + (c - 1) * 30)
	local crownCFrame = ORIGIN * CFrame.new(0, 3.4, 1.0) * CFrame.Angles(0, angle, math.rad(90)) * CFrame.new(0, 0, 1.0)
	local spike = newPart("CrownSpike" .. c, Vector3.new(0.5, 2.0, 0.5), crownCFrame, CROWN_COLOR, Enum.Material.Neon, model)
	if c == 1 then
		local pointLight = Instance.new("PointLight")
		pointLight.Name = "CrownLight"
		pointLight.Color = CROWN_COLOR
		pointLight.Range = 24
		pointLight.Brightness = 3
		pointLight.Shadows = false
		pointLight.Parent = spike
		crownLight = pointLight
	end
end

-- 5) 8 lange, dicke, peitschenartige Tentakel (je 3 Segmente, radial verteilt) -----
for t = 1, TENTACLE_COUNT do
	local angle = math.rad(360 / TENTACLE_COUNT * (t - 1))
	local baseOffset = Vector3.new(math.cos(angle) * 2.8, -2.8, math.sin(angle) * 2.8)
	local armCFrame = ORIGIN * CFrame.new(baseOffset) * CFrame.Angles(0, angle, math.rad(-95))

	local currentCFrame = armCFrame
	for seg = 1, 3 do
		local segLength = 3.4 - seg * 0.4
		local width = 1.3 - seg * 0.22
		local curl = math.rad(10 + seg * 5)

		currentCFrame = currentCFrame * CFrame.Angles(curl, 0, 0) * CFrame.new(0, segLength / 2, 0)

		newPart(
			"Tentacle" .. t .. "_Segment" .. seg,
			Vector3.new(width, segLength, width),
			currentCFrame,
			seg % 2 == 0 and SKIN_COLOR or ACCENT_COLOR,
			Enum.Material.Slate,
			model
		)

		currentCFrame = currentCFrame * CFrame.new(0, segLength / 2, 0)
	end
end

-- 6) Idle-/Bedrohungs-Puls-Attachment -------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("EnemyTier", ENEMY_TIER)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("EnemyName", "Der Tiefenfürst")

print("[Abyssara] TrenchWardenBoss erzeugt unter Workspace.Assets.Enemies")
