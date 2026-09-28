--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: TrenchWisp ("Grabenwisp")
	Rarity (Platzhalter): Uncommon
	Beschreibung:
		Kleiner, tropfenförmiger Körper, fast transluzent (Glass), mit
		blassem cyanfarbenem Innen-Glow-Kern (Neon), umgebender äußerer
		Glimm-Aura und mehreren kleinen umlaufenden Lichtpartikeln. Keine
		sichtbaren Flossen - wirkt wie ein treibendes Licht. Zone: HadalDepths.

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

-- 1) Tropfenförmiger Körper (Glass, halbtransparent, Ellipsoid) -------------------
local body = newBall("Body", Vector3.new(1.3, 1.5, 1.3), ORIGIN, BODY_COLOR, Enum.Material.Glass, model)
body.Transparency = 0.4

-- Verjüngte Spitze unten (Tropfenform), tief in den Körper eingebettet
local tip = Instance.new("WedgePart")
tip.Name = "Tip"
tip.Size = Vector3.new(0.5, 0.8, 1.3)
tip.CFrame = ORIGIN * CFrame.new(0, -0.75, 0) * CFrame.Angles(math.rad(-90), 0, 0)
tip.Color = BODY_COLOR
tip.Material = Enum.Material.Glass
tip.Transparency = 0.4
tip.Anchored = true
tip.CanCollide = false
tip.Parent = model

-- 2) Innerer Glow-Kern -----------------------------------------------------------------
local core = newBall("GlowCore", Vector3.new(0.55, 0.55, 0.55), ORIGIN, GLOW_COLOR, Enum.Material.Neon, model)

-- 3) Äußere Glimm-Aura (großzügig um den Körper, sehr transparent) ---------------------
local aura = newBall("GlimmerAura", Vector3.new(1.9, 2.1, 1.9), ORIGIN, GLOW_COLOR, Enum.Material.Neon, model)
aura.Transparency = 0.75
aura.CanCollide = false

-- 4) Kleine umlaufende Lichtpartikel (Glow-Fünkchen) -----------------------------------
for i = 1, 5 do
	local angle = math.rad(72 * (i - 1))
	local radius = 0.85
	local speckCFrame = ORIGIN * CFrame.new(math.cos(angle) * radius, 0.15 * ((i % 2 == 0) and 1 or -1), math.sin(angle) * radius)
	newBall("GlimmerSpeck" .. i, Vector3.new(0.14, 0.14, 0.14), speckCFrame, GLOW_COLOR, Enum.Material.Neon, model)
end

-- 5) Idle-Puls-Attachment ----------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Trench Wisp")

print("[Abyssara] TrenchWisp created under Workspace.Assets.Creatures")
