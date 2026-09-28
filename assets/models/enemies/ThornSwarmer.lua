--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Raid-Gegner
	Name: ThornSwarmer ("Dornschwarmer")
	Ersetzt ShadowKraken als TemplateName für RaidConfig.EnemyId "Swarmer".
	Beschreibung:
		Kleiner, kompakter Seeigel-Fisch-Hybrid mit radial abstehenden
		Dornstacheln, dunkles Türkis, orange Glow-Augen. Rundliche,
		kompakte Silhouette kommuniziert "zahlreich und lästig" -
		passend zur Schwarm-Rolle.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (Hauptkörper) -> für serverseitige
		  Bewegungs-/Angriffssteuerung (analog zu HumanoidRootPart).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-/
		  Bedrohungs-Puls-Animation.
		- "Mantle", "Eye1", "Eye2" vorhanden -> RaidService.applyEnemyVisual()
		  überschreibt Body/Mantle.Color mit definition.BodyColor und
		  Eye1/Eye2.Color mit definition.EyeColor zur Laufzeit. Hier
		  verwendete Farben sind daher nur Vorschau-Platzhalter.
		- model:SetAttribute("EnemyTier") -> "Trash" (Schwarm-Einheit).
		- model:SetAttribute("Zone") -> Ziel-Zone, in der der Gegner auftaucht.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(15, 4, -60) -- Vor Ausführung anpassen für gewünschte Position
local ENEMY_TIER = "Trash"
local ZONE = "TwilightZone"
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

local previous = enemiesFolder:FindFirstChild("ThornSwarmer")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "ThornSwarmer"
model.Parent = enemiesFolder

local SKIN_COLOR = Color3.fromRGB(30, 90, 95)
local ACCENT_COLOR = Color3.fromRGB(20, 65, 70)
local EYE_COLOR = Color3.fromRGB(255, 150, 60)

-- 1) Hauptkörper: kompakte, gedrungene Kugel --------------------------------------
local body = newPart("Body", Vector3.new(2.0, 2.0, 2.5), ORIGIN, SKIN_COLOR, Enum.Material.SmoothPlastic, model)
body.Shape = Enum.PartType.Ball

-- 2) Kleiner Mantel-Buckel oben (leicht dunkler) -----------------------------------
local mantleCFrame = ORIGIN * CFrame.new(0, 0.7, 0)
local mantle = newPart("Mantle", Vector3.new(1.2, 0.9, 1.2), mantleCFrame, ACCENT_COLOR, Enum.Material.SmoothPlastic, model)
mantle.Shape = Enum.PartType.Ball

-- 3) Glühende Augen ----------------------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local eyeCFrame = ORIGIN * CFrame.new(side * 0.6, 0.2, -1.1)
	local eye = newPart("Eye" .. i, Vector3.new(0.4, 0.4, 0.4), eyeCFrame, EYE_COLOR, Enum.Material.Neon, model)
	eye.Shape = Enum.PartType.Ball
end

-- 4) Radial abstehende Dornstacheln (6 Stück, rundum verteilt) ---------------------
for t = 1, 6 do
	local angle = math.rad(360 / 6 * (t - 1))
	local dir = Vector3.new(math.cos(angle), math.sin(angle) * 0.6, math.sin(angle))
	local thornCFrame = ORIGIN * CFrame.new(dir * 1.3) * CFrame.Angles(0, angle, math.rad(90))
	local thorn = Instance.new("WedgePart")
	thorn.Name = "Thorn" .. t
	thorn.Size = Vector3.new(0.2, 0.9, 0.3)
	thorn.CFrame = thornCFrame
	thorn.Color = ACCENT_COLOR
	thorn.Material = Enum.Material.SmoothPlastic
	thorn.Anchored = true
	thorn.CanCollide = false
	thorn.TopSurface = Enum.SurfaceType.Smooth
	thorn.BottomSurface = Enum.SurfaceType.Smooth
	thorn.Parent = model
end

-- 4b) Zweiter, kürzerer Dornenring (versetzt) für mehr Silhouetten-Dichte --------
for t = 1, 6 do
	local angle = math.rad(360 / 6 * (t - 1) + 30)
	local dir = Vector3.new(math.cos(angle), math.sin(angle) * 0.4, math.sin(angle))
	local thornCFrame = ORIGIN * CFrame.new(dir * 0.95) * CFrame.new(0, 0.35, 0) * CFrame.Angles(0, angle, math.rad(90))
	local thorn = Instance.new("WedgePart")
	thorn.Name = "SmallThorn" .. t
	thorn.Size = Vector3.new(0.14, 0.55, 0.2)
	thorn.CFrame = thornCFrame
	thorn.Color = EYE_COLOR
	thorn.Material = Enum.Material.Neon
	thorn.Anchored = true
	thorn.CanCollide = false
	thorn.TopSurface = Enum.SurfaceType.Smooth
	thorn.BottomSurface = Enum.SurfaceType.Smooth
	thorn.Parent = model
end

-- 4c) Kleine Kiefer-/Mundplatte vorn, gut sichtbar unter den Augen -----------------
local jaw = newPart("Jaw", Vector3.new(0.7, 0.35, 0.4), ORIGIN * CFrame.new(0, -0.3, -1.05), ACCENT_COLOR, Enum.Material.SmoothPlastic, model)

-- 4d) Kleine Heckflosse (stabilisiert die Schwarm-Silhouette von hinten) ----------
local tailFin = Instance.new("WedgePart")
tailFin.Name = "TailFin"
tailFin.Size = Vector3.new(0.15, 0.9, 0.7)
tailFin.CFrame = ORIGIN * CFrame.new(0, 0.1, 1.0) * CFrame.Angles(0, math.rad(90), 0)
tailFin.Color = ACCENT_COLOR
tailFin.Material = Enum.Material.SmoothPlastic
tailFin.Anchored = true
tailFin.CanCollide = false
tailFin.TopSurface = Enum.SurfaceType.Smooth
tailFin.BottomSurface = Enum.SurfaceType.Smooth
tailFin.Parent = model

-- 5) Idle-/Bedrohungs-Puls-Attachment -------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("EnemyTier", ENEMY_TIER)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("EnemyName", "Dornschwarmer")

print("[Abyssara] ThornSwarmer created under Workspace.Assets.Enemies")
