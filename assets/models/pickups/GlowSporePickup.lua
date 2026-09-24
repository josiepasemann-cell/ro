--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Aufhebbares Welt-Pickup
	Name: GlowSporePickup ("Glow Spore")
	Beschreibung:
		Kleine, leuchtende Bioluminiszenz-Spore-Kugel (GDD Abschnitt 3:
		"Sammelt 'Glow Spores' / Bioluminiszenz-Ressourcen von platzierten
		Kreaturen-Ständen"), die PickupSpawner periodisch und begrenzt auf
		jedem Spieler-Plot spawnt. Wird über ein serverseitig angebrachtes
		ProximityPrompt aufgehoben und landet danach sichtbar in der Hand des
		Spielers (siehe HeldItemService).

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (siehe auch
	assets/models/README.md - dieses Pickup-Unterverzeichnis ergänzt die
	dortige Konvention um einen eigenen, analogen Fall):
		- Model.PrimaryPart = "Body" (der leuchtende Sporen-Kern) -> Ansatz-
		  punkt für PickupSpawner (Positionierung) und HeldItemService
		  (Halte-Attachment/Skalierung).
		- Attachment "PulseAttachment" an Body -> optionaler Ansatzpunkt für
		  eine künftige Idle-Schwebe-/Puls-Animation, identisch zum
		  Kreaturen-Konzept in assets/models/creatures/*.lua.
		- model:SetAttribute("PickupKind", "GlowSpore") -> Platzhalter-
		  Kennzeichnung, PickupSpawner setzt zusätzlich zur Laufzeit
		  "OwnerUserId" auf JEDER geklonten Instanz (Besitz-Validierung).

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein
		Script unter ServerScriptService einfügen und einmal laufen lassen.
		Reine Geometrie-Erzeugung, keine Gameplay-Logik. Wiederholtes
		Ausführen ist sicher (idempotent). PickupSpawner klont diese Vorlage
		anschließend beliebig oft zur Laufzeit - dieses Buildscript selbst
		erzeugt nur EIN Muster-Modell.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(0, 4, -20) -- Vor Ausführung anpassen für gewünschte Position
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

local previous = pickupsFolder:FindFirstChild("GlowSporePickup")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "GlowSporePickup"
model.Parent = pickupsFolder

-- 1) Sporen-Kern (Body) -------------------------------------------------------
local body = newPart("Body", Vector3.new(1.4, 1.4, 1.4), ORIGIN, Color3.fromRGB(120, 245, 255), Enum.Material.Neon, model)
body.Shape = Enum.PartType.Ball

-- 2) Äußere Glashülle (leichtes Glimmen/Tiefe) --------------------------------
local shell = newPart(
	"OuterShell",
	Vector3.new(2.0, 2.0, 2.0),
	ORIGIN,
	Color3.fromRGB(180, 250, 255),
	Enum.Material.Glass,
	model
)
shell.Shape = Enum.PartType.Ball
shell.Transparency = 0.55

-- 3) Drei kleine umlaufende Glimmer-Partikel-Anker (rein geometrisch) --------
for i = 1, 3 do
	local angle = math.rad(120 * (i - 1))
	local offset = Vector3.new(math.cos(angle) * 1.1, math.sin(angle * 0.5) * 0.4, math.sin(angle) * 1.1)
	local speck = newPart(
		"GlimmerSpeck" .. i,
		Vector3.new(0.25, 0.25, 0.25),
		ORIGIN * CFrame.new(offset),
		Color3.fromRGB(210, 255, 255),
		Enum.Material.Neon,
		model
	)
	speck.Shape = Enum.PartType.Ball
end

-- 4) Idle-Puls-Attachment ---------------------------------------------------
local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

-- 5) Punktlicht für sichtbares Glühen im Dunkeln -----------------------------
local glowLight = Instance.new("PointLight")
glowLight.Name = "GlowSporeLight"
glowLight.Color = Color3.fromRGB(150, 240, 255)
glowLight.Range = 10
glowLight.Brightness = 2
glowLight.Parent = body

model.PrimaryPart = body
model:SetAttribute("PickupKind", "GlowSpore")

print("[Abyssara] GlowSporePickup created under Workspace.Assets.Pickups")
