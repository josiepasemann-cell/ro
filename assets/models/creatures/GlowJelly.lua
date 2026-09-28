--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: GlowJelly ("Glühqualle")
	Rarity (Platzhalter): Common
	Beschreibung:
		Kleine, transluzente Qualle mit gewölbter Glocke (halbtransparentes
		Neon-Glas), gekräuseltem Glockensaum, kurzen dicken Mundarmen und
		vielen dünnen, geschwungenen Tentakeln. Zone: SunZone.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN:
		- Model.PrimaryPart = "Body" (die Glocke) -> für Bewegungssteuerung.
		- Attachment "PulseAttachment" an Body -> Ansatzpunkt für die
		  Idle-Puls-/Skalierungs-Animation durch den Code-Agenten.
		- Teile "Tentacle1".."Tentacle8" werden von IdleSway automatisch geschwenkt.
		- model:GetAttribute("Rarity") -> String, steuert später Glow-Farbe/Partikel.
		- model:GetAttribute("Zone") -> Herkunfts-Zone (Platzhalter).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein Script unter
		ServerScriptService einfügen und einmal laufen lassen. Reine Geometrie-Erzeugung,
		keine Gameplay-Logik. Wiederholtes Ausführen ist sicher (idempotent).
]]

local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 6, 60) -- Vor Ausführung anpassen für gewünschte Position
local RARITY = "Common"
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

-- Block-Part + SpecialMesh(Sphere)-Kind, damit eine nicht-uniforme Size zu
-- einem Ellipsoid gestreckt wird (ein Part mit Shape=Ball rendert IMMER als
-- Kugel mit der KLEINSTEN Achse als Durchmesser, siehe docs/previews/README.md).
local function newBall(name, size, cframe, color, material, parent)
	local part = newPart(name, size, cframe, color, material, parent)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = part
	return part
end

-- Textur-Instanz mit projektweiter "TextureKey"-Konvention (siehe
-- assets/textures/README.md, sobald vorhanden). Texture bleibt bis zum
-- PNG-Upload leer ("") - ein Runtime-Skript blendet ungefüllte
-- KeyedTexture-Instanzen aus. Nur auf Block-Part-Flächen sinnvoll, Kugeln/
-- Ellipsoide bekommen stattdessen passende Materials.
local function addKeyedTexture(part, key, face, color, transparency, studsU, studsV)
	local tex = Instance.new("Texture")
	tex.Name = "Tex_" .. key
	tex.Texture = ""
	tex.Face = face
	tex.StudsPerTileU = studsU or 3
	tex.StudsPerTileV = studsV or studsU or 3
	tex.Color3 = color
	tex.Transparency = transparency or 0
	tex:SetAttribute("TextureKey", key)
	CollectionService:AddTag(tex, "KeyedTexture")
	tex.Parent = part
	return tex
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local creaturesFolder = getOrCreateFolder(assetsFolder, "Creatures")

local previous = creaturesFolder:FindFirstChild("GlowJelly")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowJelly"
model.Parent = creaturesFolder

local BELL_COLOR = Color3.fromRGB(150, 230, 255)
local BELL_TOP = Color3.fromRGB(110, 200, 240)
local GLOW_COLOR = Color3.fromRGB(90, 240, 255)
local ARM_COLOR = Color3.fromRGB(200, 245, 255)

-- 1) Glocke (Körper, Ellipsoid via SpecialMesh) -----------------------------
local body = newBall("Body", Vector3.new(2.6, 1.9, 2.6), ORIGIN, BELL_COLOR, Enum.Material.Glass, model)
body.Transparency = 0.25

-- 1b) Countershading: dunklerer Scheitel oben, tief in die Glocke eingebettet
newBall("BellCrown", Vector3.new(1.6, 0.9, 1.6), ORIGIN * CFrame.new(0, 0.55, 0), BELL_TOP, Enum.Material.Glass, model).Transparency = 0.3

-- 2) Innerer Glow-Kern, gut in die Glocke eingebettet -----------------------
newBall("GlowCore", Vector3.new(1.2, 0.9, 1.2), ORIGIN * CFrame.new(0, -0.1, 0), GLOW_COLOR, Enum.Material.Neon, model)

-- 2b) Vier kleine Membran-Patches (JellyMembrane-Textur) auf der Glockenoberfläche,
--     tief genug eingebettet um sicher mit Body zu überlappen -----------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 20)
	local radius = 1.1
	local patchCFrame = ORIGIN * CFrame.new(math.cos(angle) * radius, 0.1, math.sin(angle) * radius) * CFrame.Angles(0, -angle, 0)
	local patch = newPart("MembranePatch" .. i, Vector3.new(0.7, 0.9, 0.3), patchCFrame, BELL_COLOR, Enum.Material.Glass, model)
	patch.Transparency = 0.3
	addKeyedTexture(patch, "JellyMembrane", Enum.NormalId.Front, GLOW_COLOR, 0.2, 2, 2)
end

-- 3) Gekräuselter Glockensaum (8 kleine Wedges rund um den unteren Rand) ----
for i = 1, 8 do
	local angle = math.rad(45 * (i - 1))
	local radius = 1.15
	local frillCFrame = ORIGIN * CFrame.new(math.cos(angle) * radius, -0.75, math.sin(angle) * radius)
		* CFrame.Angles(0, -angle, 0)
		* CFrame.Angles(math.rad(30), 0, 0)
	local frill = Instance.new("WedgePart")
	frill.Name = "Frill" .. i
	frill.Size = Vector3.new(0.55, 0.5, 0.15)
	frill.CFrame = frillCFrame
	frill.Color = (i % 2 == 0) and BELL_COLOR or ARM_COLOR
	frill.Material = Enum.Material.Glass
	frill.Transparency = 0.2
	frill.Anchored = true
	frill.CanCollide = false
	frill.Parent = model
end

-- 4) 4 dicke Mundarme, direkt unter der Glockenmitte -------------------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 45)
	local radius = 0.35
	local offset = Vector3.new(math.cos(angle) * radius, -1.1, math.sin(angle) * radius)
	local arm = newPart(
		"OralArm" .. i,
		Vector3.new(0.28, 1.3, 0.28),
		ORIGIN * CFrame.new(offset) * CFrame.Angles(math.rad(6 * i), 0, 0),
		ARM_COLOR,
		Enum.Material.Neon,
		model
	)
	arm.Transparency = 0.15
end

-- 5) 8 dünne, geschwungene Tentakel (2 Segmente je Tentakel) -----------------
for i = 1, 8 do
	local angle = math.rad(45 * (i - 1))
	local radius = 1.0
	local baseOffset = Vector3.new(math.cos(angle) * radius, -0.65, math.sin(angle) * radius)
	local baseCFrame = ORIGIN * CFrame.new(baseOffset)

	local seg1Length = 1.3 + (i % 2) * 0.3
	local seg1CFrame = baseCFrame * CFrame.new(0, -seg1Length / 2, 0)
	local seg1 = newPart("Tentacle" .. i, Vector3.new(0.18, seg1Length, 0.18), seg1CFrame, BELL_COLOR, Enum.Material.Neon, model)
	seg1.Transparency = 0.15

	local seg2Length = 1.1 + (i % 3) * 0.25
	local seg2CFrame = baseCFrame * CFrame.new(0, -seg1Length, 0) * CFrame.Angles(math.rad(10 * ((i % 2 == 0) and 1 or -1)), 0, 0) * CFrame.new(0, -seg2Length / 2, 0)
	local seg2 = newPart("TentacleTip" .. i, Vector3.new(0.12, seg2Length, 0.12), seg2CFrame, GLOW_COLOR, Enum.Material.Neon, model)
	seg2.Transparency = 0.1
end

-- 6) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Glow Jelly")

print("[Abyssara] GlowJelly created under Workspace.Assets.Creatures")
