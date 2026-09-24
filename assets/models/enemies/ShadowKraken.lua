--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Raid-Gegner (Platzhalter-Modell)
	Name: ShadowKraken ("Schattenkrake")
	Beschreibung:
		Bedrohlicher, deutlich größerer Trench-Raid-Gegner: dunkler,
		schattiger Körper mit bedrohlichen roten Glow-Augen und 8 langen,
		peitschenartigen Tentakeln. Dient als Platzhalter-Gegner-Modell für
		das Trench-Raid-System (Abschnitt 3 & 9 des GDD).

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für serverseitige
		  Bewegungs-/Angriffssteuerung (analog zu HumanoidRootPart).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-/
		  Bedrohungs-Puls-Animation.
		- model:SetAttribute("EnemyTier") -> Platzhalter-Einstufung
		  ("Trash"/"Elite"/"Boss"), hier "Elite" als Startwert.
		- model:SetAttribute("Zone") -> Ziel-Zone, in der der Gegner auftaucht.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 8, 90) -- Vor Ausführung anpassen für gewünschte Position
local ENEMY_TIER = "Elite"
local ZONE = "TwilightZone"
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

local previous = enemiesFolder:FindFirstChild("ShadowKraken")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ShadowKraken"
model.Parent = enemiesFolder

local SKIN_COLOR = Color3.fromRGB(20, 18, 26)
local ACCENT_COLOR = Color3.fromRGB(35, 30, 45)
local EYE_COLOR = Color3.fromRGB(255, 40, 60)

-- 1) Hauptkörper (deutlich größer als normale Kreaturen) ------------------------
local body = newPart("Body", Vector3.new(4.5, 4.0, 4.5), ORIGIN, SKIN_COLOR, Enum.Material.Slate, model)
body.Shape = Enum.PartType.Ball

-- 2) Mantel-Auswölbung oben (leicht dunklerer Buckel) -----------------------------
local mantleCFrame = ORIGIN * CFrame.new(0, 1.6, -0.4)
newPart("Mantle", Vector3.new(3.2, 2.2, 3.2), mantleCFrame, ACCENT_COLOR, Enum.Material.Slate, model).Shape =
	Enum.PartType.Ball

-- 3) Bedrohliche Glow-Augen ---------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 1.1, 0.4, 2.0)
	local eye = newPart("Eye" .. i, Vector3.new(0.7, 0.7, 0.7), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
end

-- 4) 8 lange, peitschenartige Tentakel (je 4 Segmente, radial verteilt) ------------
for t = 1, TENTACLE_COUNT do
	local angle = math.rad(360 / TENTACLE_COUNT * (t - 1))
	local baseOffset = Vector3.new(math.cos(angle) * 1.8, -1.8, math.sin(angle) * 1.8)
	local armCFrame = ORIGIN * CFrame.new(baseOffset) * CFrame.Angles(0, angle, math.rad(-95))

	local currentCFrame = armCFrame
	for seg = 1, 4 do
		local segLength = 2.0 - seg * 0.25
		local width = 0.75 - seg * 0.14
		local curl = math.rad(10 + seg * 4)

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

-- 5) Idle-/Bedrohungs-Puls-Attachment -------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("EnemyTier", ENEMY_TIER)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("EnemyName", "Schattenkrake")

print("[Abyssara] ShadowKraken erzeugt unter Workspace.Assets.Enemies")
