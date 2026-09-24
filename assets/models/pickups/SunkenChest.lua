--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Aufhebbares Welt-Pickup (Event-Variante)
	Name: SunkenChest ("Sunken Chest" – Treasure Tide, Abschnitt 1.3)
	Beschreibung:
		Gold-recolorte Variante von `GlowSporePickup.lua` (siehe dort für den
		vollständigen Pickup-Vertrag). Spawnt laut Design-Dokument einmal pro
		Stunde Event-Laufzeit auf jedem Spieler-Plot, ist wie GlowSporePickup
		über ein ProximityPrompt aufhebbar und liefert einen fixen
		Tide-Coin-Betrag plus garantierte Event-Währung.

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (identisch zu
	assets/models/pickups/GlowSporePickup.lua, siehe auch
	assets/models/README.md):
		- Model.PrimaryPart = "Body" (leuchtender Kern) -> Ansatzpunkt für
		  PickupSpawner (Positionierung) und HeldItemService (Halte-
		  Attachment/Skalierung).
		- Attachment "PulseAttachment" an Body -> Idle-Schwebe-/Puls-
		  Animation, identisch zum GlowSporePickup-Konzept.
		- model:SetAttribute("PickupKind", "SunkenChest") -> eigener Kind-
		  Wert (NICHT "GlowSpore"), damit PickupSpawner/HeldItemService den
		  Event-Reward-Pfad (150 Tide Coins + garantierte Event-Währung)
		  vom normalen Glow-Spore-Pfad unterscheiden kann.
		- model:SetAttribute("Event", "TreasureTide")
		- PickupSpawner klont diese Vorlage analog zu GlowSporePickup aus
		  ReplicatedStorage.AssetTemplates.Pickups.SunkenChest; dieses
		  Buildscript erzeugt nur EIN Muster-Modell unter
		  Workspace.Assets.Pickups.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein
		Script unter ServerScriptService einfügen und einmal laufen lassen.
		Reine Geometrie-Erzeugung, keine Gameplay-Logik. Idempotent.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 4, -115) -- Vor Ausführung anpassen für gewünschte Position
-- // ----------------------------------------------------------------------

local function getOrCreateFolder(parent, name)
	local folder = parent:FindFirstChild(name)
	if not folder or not folder:IsA("Folder") then
		if folder then
			folder:Destroy()
		end
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
local pickupsFolder = getOrCreateFolder(assetsFolder, "Pickups")

local previous = pickupsFolder:FindFirstChild("SunkenChest")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "SunkenChest"
model.Parent = pickupsFolder

-- 1) Truhen-Körper als leuchtender Kern (Body) ---------------------------------
-- Gold-recolorte Variante des GlowSporePickup-Kugel-Kerns: hier stattdessen
-- eine kleine, kompakte Truhenform, damit "Body" weiterhin ein einzelnes
-- Part bleibt (Vertrag: PrimaryPart = Body, für Placement/Halte-Logik).
local body = newPart("Body", Vector3.new(1.6, 1.2, 1.2), ORIGIN, Color3.fromRGB(230, 190, 70), Enum.Material.Neon, model)

-- 2) Deckel-Akzent (rein visuell, kein eigener PrimaryPart) --------------------
local lid = newPart(
	"ChestLidAccent",
	Vector3.new(1.6, 0.3, 1.3),
	ORIGIN * CFrame.new(0, 0.7, 0) * CFrame.Angles(math.rad(-20), 0, 0),
	Color3.fromRGB(255, 225, 130),
	Enum.Material.Metal,
	model
)

-- 3) Äußere Glashülle (Glimmen/Tiefe, analog GlowSporePickup) ------------------
local shell = newPart(
	"OuterShell",
	Vector3.new(2.1, 1.8, 1.8),
	ORIGIN,
	Color3.fromRGB(255, 235, 180),
	Enum.Material.Glass,
	model
)
shell.Shape = Enum.PartType.Ball
shell.Transparency = 0.6

-- 4) Drei umlaufende Glimmer-Partikel-Anker (Gold-Funken) ----------------------
for i = 1, 3 do
	local angle = math.rad(120 * (i - 1))
	local offset = Vector3.new(math.cos(angle) * 1.1, math.sin(angle * 0.5) * 0.4, math.sin(angle) * 1.1)
	local speck = newPart(
		"GlimmerSpeck" .. i,
		Vector3.new(0.25, 0.25, 0.25),
		ORIGIN * CFrame.new(offset),
		Color3.fromRGB(255, 240, 190),
		Enum.Material.Neon,
		model
	)
	speck.Shape = Enum.PartType.Ball
end

-- 5) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

-- 6) Punktlicht für sichtbares Glühen im Dunkeln -----------------------------
local glowLight = Instance.new("PointLight")
glowLight.Name = "SunkenChestLight"
glowLight.Color = Color3.fromRGB(255, 220, 140)
glowLight.Range = 10
glowLight.Brightness = 2.2
glowLight.Shadows = false
glowLight.Parent = body

model.PrimaryPart = body
model:SetAttribute("PickupKind", "SunkenChest")
model:SetAttribute("Event", "TreasureTide")

print("[Abyssara] SunkenChest erzeugt unter Workspace.Assets.Pickups")
