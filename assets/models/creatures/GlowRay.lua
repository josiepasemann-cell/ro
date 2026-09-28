--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GlowRay ("Leuchtrochen") - freie 6. Kreatur des MVP-Sets
	Rarity (Platzhalter): Uncommon
	Beschreibung:
		Flacher, rundlich-cartoonhafter Rochenkörper (breiter, abgeflachter
		Ellipsoid statt scharfkantiger CSG-Raute) mit großen, überlappenden
		"Flügel"-Flossen an den Seiten, heller Rückenzeichnung, dunklerer
		Unterseite, kleinen Kiemenschlitz-Punkten, einem dünnen, sich
		verjüngenden Peitschenschwanz mit Giftstachel-Spitze, leuchtendem
		Unterseiten-Glow und großen niedlichen Kulleraugen. Zone: SunZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (der Rochenkörper) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für Idle-Puls-/Schwebeanimation.
		- Teile "SideFin1"/"SideFin2" werden von IdleSway automatisch geschwenkt.
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

local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

local function newCartoonEye(name, cframe, eyeSize, parent)
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.55, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), Color3.fromRGB(20, 20, 30), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
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
local RAY_TOP = Color3.fromRGB(95, 125, 230)
local BELLY_COLOR = Color3.fromRGB(190, 205, 255)
local GLOW_COLOR = Color3.fromRGB(140, 220, 255)

-- 1) Rundlicher, abgeflachter Rochenkörper (breiter Ellipsoid statt CSG-Raute) -
local body = newBall("Body", Vector3.new(3.0, 0.6, 2.7), ORIGIN, RAY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1b) Countershading: dunklere Rückenkuppel oben, hellere Bauchunterseite ----
newBall("BackDome", Vector3.new(2.0, 0.4, 1.9), ORIGIN * CFrame.new(0, 0.28, 0), RAY_TOP, Enum.Material.SmoothPlastic, model)
newBall("Belly", Vector3.new(2.5, 0.28, 2.1), ORIGIN * CFrame.new(0, -0.28, 0), BELLY_COLOR, Enum.Material.SmoothPlastic, model)

-- 1c) Leuchtender Unterseiten-Glow (breiter, flacher Neon-Ellipsoid, tief
--     eingebettet für einen sanften Rand-Schimmer statt hartem Ring) --------
local rim = newBall("GlowRim", Vector3.new(3.15, 0.16, 2.85), ORIGIN * CFrame.new(0, -0.32, 0), GLOW_COLOR, Enum.Material.Neon, model)
rim.Transparency = 0.25

-- 2) Zwei große "Flügel"-Flossen an den Seiten: je 2 überlappende, flache
--    Ellipsen fächerartig aufgestellt für eine natürliche Flossenform -------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	local wingCFrame = ORIGIN * CFrame.new(side * 1.75, 0.05, 0.1) * CFrame.Angles(0, 0, math.rad(side * -14))
	local wing = newBall("SideFin" .. i, Vector3.new(1.5, 0.28, 1.7), wingCFrame, RAY_COLOR, Enum.Material.SmoothPlastic, model)
	local wingTip = newBall("SideFin" .. i .. "Tip", Vector3.new(0.9, 0.2, 1.1), wingCFrame * CFrame.new(side * 0.75, -0.02, -0.15) * CFrame.Angles(0, 0, math.rad(side * -10)), GLOW_COLOR, Enum.Material.Neon, model)
	wingTip.Transparency = 0.3
end

-- 3) Vier abgerundete Randbuckel an den Rochen-"Ecken" (cartoony statt spitz) -
local tipOffsets = { { 1.35, 0 }, { -1.35, 0 }, { 0, 1.55 }, { 0, -1.45 } }
for i, off in ipairs(tipOffsets) do
	newBall("EdgeBump" .. i, Vector3.new(0.55, 0.24, 0.7), ORIGIN * CFrame.new(off[1] * 0.85, -0.02, off[2] * 0.78), RAY_COLOR, Enum.Material.SmoothPlastic, model)
end

-- 4) Rückenzeichnung: helle Neon-Sprenkel ---------------------------------------
local spotOffsets = { { 0.55, 0.55 }, { -0.55, 0.55 }, { 0.45, -0.35 }, { -0.45, -0.35 }, { 0, 1.0 } }
for i, off in ipairs(spotOffsets) do
	newBall("Spot" .. i, Vector3.new(0.22, 0.14, 0.22), ORIGIN * CFrame.new(off[1], 0.32, off[2]), GLOW_COLOR, Enum.Material.Neon, model)
end

-- 5) Kleine Kiemenschlitz-Punkte auf der Unterseite -----------------------------
for i = 1, 5 do
	local x = -0.7 + (i - 1) * 0.35
	newBall("GillSlit" .. i, Vector3.new(0.1, 0.06, 0.3), ORIGIN * CFrame.new(x, -0.34, 0.85), Color3.fromRGB(60, 65, 100), Enum.Material.SmoothPlastic, model)
end

-- 6) Peitschenschwanz: 3 sich verjüngende, überlappende Ellipsen-Segmente ------
local currentCFrame = ORIGIN * CFrame.new(0, 0, -1.15)
local prevHalfZ = 0.28
for i = 1, 3 do
	local segLength = 1.1 - i * 0.12
	local width = 0.3 - i * 0.06
	local halfZ = segLength / 2
	local overlap = 0.2
	currentCFrame = currentCFrame * CFrame.new(0, 0, -(prevHalfZ + halfZ - overlap))
	newBall("TailSegment" .. i, Vector3.new(width, width, segLength), currentCFrame, RAY_COLOR, Enum.Material.SmoothPlastic, model)
	prevHalfZ = halfZ
end

-- Kleine Giftstachel-Spitze (hartes Detail, daher WedgePart) an der Schwanzspitze
local barbCFrame = currentCFrame * CFrame.new(0, 0, -(prevHalfZ + 0.14 - 0.12))
local barb = Instance.new("WedgePart")
barb.Name = "TailTip"
barb.Size = Vector3.new(0.16, 0.16, 0.42)
barb.CFrame = barbCFrame
barb.Color = Color3.fromRGB(230, 230, 235)
barb.Material = Enum.Material.SmoothPlastic
barb.Anchored = true
barb.CanCollide = false
barb.Parent = model

-- 7) Große niedliche Kulleraugen ------------------------------------------------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 0.55, 0.2, 1.15), Vector3.new(0.42, 0.42, 0.26), model)
end

-- 8) Idle-Puls-Attachment -----------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Glow Ray")

print("[Abyssara] GlowRay created under Workspace.Assets.Creatures")
