--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Kreatur
	Name: TrenchWisp ("Grabenwisp")
	Rarity (Platzhalter): Uncommon
	Beschreibung:
		Kleiner, tropfenförmiger Körper, fast transluzent (Glass), mit
		blassem cyanfarbenem Innen-Glow-Kern (Neon). Keine sichtbaren
		Flossen - wirkt wie ein treibendes Licht. Zone: HadalDepths.

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

-- 1) Tropfenförmiger Körper (Glass, halbtransparent) ------------------------------
local body = newPart("Body", Vector3.new(1.3, 1.5, 1.3), ORIGIN, BODY_COLOR, Enum.Material.Glass, model)
body.Shape = Enum.PartType.Ball
body.Transparency = 0.4

-- Verjüngte Spitze unten (Tropfenform)
local tip = Instance.new("WedgePart")
tip.Name = "Tip"
tip.Size = Vector3.new(0.5, 0.7, 1.3)
tip.CFrame = ORIGIN * CFrame.new(0, -0.9, 0) * CFrame.Angles(math.rad(-90), 0, 0)
tip.Color = BODY_COLOR
tip.Material = Enum.Material.Glass
tip.Transparency = 0.4
tip.Anchored = true
tip.CanCollide = false
tip.Parent = model

-- 2) Innerer Glow-Kern -----------------------------------------------------------------
local core = newPart("GlowCore", Vector3.new(0.5, 0.5, 0.5), ORIGIN, GLOW_COLOR, Enum.Material.Neon, model)
core.Shape = Enum.PartType.Ball

-- 3) Idle-Puls-Attachment ----------------------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

model.PrimaryPart = body
model:SetAttribute("Rarity", RARITY)
model:SetAttribute("Zone", ZONE)
model:SetAttribute("CreatureName", "Trench Wisp")

print("[Abyssara] TrenchWisp created under Workspace.Assets.Creatures")
