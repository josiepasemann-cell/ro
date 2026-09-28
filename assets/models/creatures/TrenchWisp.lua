--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: TrenchWisp ("Grabenwisp")
	Rarity (Platzhalter): Uncommon
	Beschreibung:
		Kleiner, cartoonhaft niedlicher Irrlicht-Geist: tropfenförmiger
		Hauptkörper (fast transluzentes Glass) mit einem sich verjüngenden
		Kometenschweif aus 3 Ellipsen-Segmenten, großen leuchtenden
		Kulleraugen und kleinem Lächeln, blassem cyanfarbenem Innen-Glow-
		Kern, umgebender äußerer Glimm-Aura, 3 dünnen, geschwungenen
		Wisp-Schweif-Tentakeln (je 2 Ellipsen-Segmente) und mehreren kleinen
		umlaufenden Lichtpartikeln. Zone: HadalDepths.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" -> für Bewegungssteuerung (langsamer
		  Random-Walk-Schwebeflug wird vom Code-Agenten ergänzt).
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Flacker-Animation (Helligkeit ±20% alle 1,5s, Teil "GlowCore"
		  markiert den zu animierenden Kern).
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(-15, 6, 90) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Uncommon"
local ZONE = "HadalDepths"
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

local function newCartoonEye(name, cframe, eyeSize, pupilColor, parent)
	newBall(name, eyeSize, cframe, Color3.fromRGB(255, 255, 255), Enum.Material.SmoothPlastic, parent)
	newBall(name .. "Pupil", eyeSize * 0.5, cframe * CFrame.new(0, 0, -eyeSize.Z * 0.3), pupilColor, Enum.Material.Neon, parent)
	newBall(name .. "Glint", eyeSize * 0.2, cframe * CFrame.new(eyeSize.X * 0.15, eyeSize.Y * 0.2, -eyeSize.Z * 0.42), Color3.fromRGB(255, 255, 255), Enum.Material.Neon, parent)
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("TrenchWisp")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "TrenchWisp"
model.Parent = creaturesFolder

local BODY_COLOR = Color3.fromRGB(140, 220, 235)
local GLOW_COLOR = Color3.fromRGB(150, 255, 240)

-- 1) Tropfenförmiger Hauptkörper (Glass, halbtransparent, cartoonhaft rund) ----
local body = newBall("Body", Vector3.new(1.5, 1.6, 1.5), ORIGIN, BODY_COLOR, Enum.Material.Glass, model)
body.Transparency = 0.2

-- 1b) Sich verjüngender Kometenschweif unten (3 Ellipsen-Segmente statt
--     einem einzelnen Keil - bricht die reine Kugelsilhouette auf) ------------
local tailCFrame = ORIGIN * CFrame.new(0, -0.8, 0)
local prevHalf = 0.15
for i = 1, 3 do
	local h = 0.42 - i * 0.08
	tailCFrame = tailCFrame * CFrame.new(0, -(prevHalf + h - 0.14), 0)
	local tailPart = newBall("Tip" .. (i == 1 and "" or i), Vector3.new(0.7 - i * 0.14, h * 2, 0.7 - i * 0.14), tailCFrame, BODY_COLOR, Enum.Material.Glass, model)
	tailPart.Transparency = 0.4
	prevHalf = h
end

-- 2) Innerer Glow-Kern -----------------------------------------------------------------
newBall("GlowCore", Vector3.new(0.5, 0.5, 0.5), ORIGIN, GLOW_COLOR, Enum.Material.Neon, model)

-- 2b) Niedliches Cartoon-Gesicht: große leuchtende Kulleraugen + Lächeln -----------
for i = 1, 2 do
	local side = (i == 1) and 1 or -1
	newCartoonEye("Eye" .. i, ORIGIN * CFrame.new(side * 0.32, 0.15, -0.62), Vector3.new(0.32, 0.32, 0.2), Color3.fromRGB(20, 60, 60), model)
end
newBall("Smile", Vector3.new(0.32, 0.08, 0.14), ORIGIN * CFrame.new(0, -0.18, -0.68) * CFrame.Angles(0, 0, math.rad(180)), Color3.fromRGB(30, 60, 65), Enum.Material.SmoothPlastic, model)

-- 3) Äußere Glimm-Aura (großzügig um den Körper, sehr transparent) ---------------------
local aura = newBall("GlimmerAura", Vector3.new(1.8, 1.95, 1.8), ORIGIN, GLOW_COLOR, Enum.Material.Neon, model)
aura.Transparency = 0.88
aura.CanCollide = false

-- 4) 3 dünne, geschwungene Wisp-Schweif-Tentakel (je 2 sich verjüngende
--    Ellipsen-Segmente), trailen locker nach hinten/unten ---------------------------
for i = 1, 3 do
	local angle = math.rad(120 * (i - 1) + 30)
	local radius = 0.55
	local baseCFrame = ORIGIN * CFrame.new(math.cos(angle) * radius, -0.3, math.sin(angle) * radius) * CFrame.Angles(math.rad(35), angle, 0)
	local seg1 = newBall("Tentacle" .. i, Vector3.new(0.16, 0.55, 0.16), baseCFrame * CFrame.new(0, -0.24, 0), GLOW_COLOR, Enum.Material.Neon, model)
	seg1.Transparency = 0.2
	local seg2CFrame = baseCFrame * CFrame.new(0, -0.5, 0) * CFrame.Angles(math.rad(14 * ((i % 2 == 0) and 1 or -1)), 0, 0)
	local seg2 = newBall("TentacleTip" .. i, Vector3.new(0.1, 0.5, 0.1), seg2CFrame * CFrame.new(0, -0.22, 0), GLOW_COLOR, Enum.Material.Neon, model)
	seg2.Transparency = 0.15
end

-- 5) Kleine umlaufende Lichtpartikel (Glow-Fünkchen) -----------------------------------
for i = 1, 5 do
	local angle = math.rad(72 * (i - 1))
	local radius = 0.9
	local speckCFrame = ORIGIN * CFrame.new(math.cos(angle) * radius, 0.15 * ((i % 2 == 0) and 1 or -1), math.sin(angle) * radius)
	newBall("GlimmerSpeck" .. i, Vector3.new(0.14, 0.14, 0.14), speckCFrame, GLOW_COLOR, Enum.Material.Neon, model)
end

-- 6) Idle-Puls-Attachment ----------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Trench Wisp")

print("[Abyssara] TrenchWisp created under Workspace.Assets.Creatures")
