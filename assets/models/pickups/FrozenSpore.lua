--[[
	Abyssara – Deep Tide Tycoon
	Asset-Typ: Aufhebbares Welt-Pickup (Event-Variante, mit Thaw-Puzzle)
	Name: FrozenSpore ("Frozen Spore" – Frozen Current, Abschnitt 1.3: "must
	be 'thawed' by standing near it 3s before collecting, worth 4x value")
	Beschreibung:
		Variante von GlowSporePickup mit einem 3-Zustands-Auftau-Visual
		(icy shell -> cracked -> open), das der Code-Agent über
		Transparency-Toggle der drei benannten Zustands-Modelle steuert,
		während der Spieler 3s in der Nähe steht (siehe HeldItemConfig-
		Muster in PickupSpawner.lua für den bestehenden Prompt-/Distanz-
		Check, den der Code-Agent hier um einen Timer erweitert).

	NAMENSKONVENTION FÜR SPÄTEREN CODE-AGENTEN (siehe auch
	assets/models/pickups/GlowSporePickup.lua):
		- Model.PrimaryPart = "Body" (unsichtbarer Anker-Kern, immer
		  vorhanden/nicht getoggelt) -> Ansatzpunkt für PickupSpawner
		  (Positionierung) und HeldItemService (Halte-Attachment/Skalierung).
		- Attachment "PulseAttachment" an Body -> Idle-Schwebe-/Puls-
		  Animation.
		- model:SetAttribute("PickupKind", "FrozenSpore")
		- model:SetAttribute("Event", "FrozenCurrent")
		- model:SetAttribute("ThawStates", "IcyShellState,CrackedState,OpenState")
		  -> kommaseparierte, GEORDNETE Liste der drei Zustands-Modellnamen
		  (Reihenfolge = Auftau-Fortschritt). Der Code-Agent schaltet den
		  Fortschritt um, indem er GENAU EIN Zustands-Modell auf
		  Transparency = 0 (alle seine Parts) setzt und die anderen beiden
		  auf Transparency = 1 setzt (kein Destroy - alle drei Modelle
		  bleiben permanent vorhanden, nur Sichtbarkeit wechselt).
		- Zustands-Modelle (jeweils ein Model unter dem Pickup-Model, mit
		  eigenem "StateBase"-Part als Zentrum):
			1. "IcyShellState" (Start-Zustand, sichtbar) - geschlossene,
			   blau-transluzente Eishülle um den Sporen-Kern.
			2. "CrackedState" (Zwischen-Zustand, unsichtbar) - Eishülle mit
			   sichtbaren Rissen (mehrere schmale Neon-Spalten).
			3. "OpenState" (Endzustand, unsichtbar) - Eishülle vollständig
			   aufgebrochen, Sporen-Kern frei sichtbar/leuchtend, danach
			   erst regulär aufhebbar (Wert 4x, siehe Design-Dokument
			   Abschnitt 1.3 - die 4x-Multiplikation selbst ist
			   Gameplay-Logik und NICHT Teil dieses Buildscripts).
		- Wird von PickupSpawner analog zu GlowSporePickup aus
		  ReplicatedStorage.AssetTemplates.Pickups.FrozenSpore geklont;
		  dieses Buildscript erzeugt nur EIN Muster-Modell unter
		  Workspace.Assets.Pickups.

	AUSFÜHRUNG:
		In der Roblox Studio Command Bar ausführen, oder temporär in ein
		Script unter ServerScriptService einfügen und einmal laufen lassen.
		Reine Geometrie-Erzeugung, keine Gameplay-Logik. Idempotent.
]]

local Workspace = game:GetService("Workspace")

-- // Konfiguration -------------------------------------------------------
local ORIGIN = CFrame.new(12, 4, -115) -- Vor Ausführung anpassen für gewünschte Position
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

local function newPart(name, size, cframe, color, material, parent, transparency)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Transparency = transparency or 0
	part.Anchored = true
	part.CanCollide = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local assetsFolder = getOrCreateFolder(Workspace, "Assets")
local pickupsFolder = getOrCreateFolder(assetsFolder, "Pickups")

local previous = pickupsFolder:FindFirstChild("FrozenSpore")
if previous then
	previous:Destroy()
end

local model = Instance.new("Model")
model.Name = "FrozenSpore"
model.Parent = pickupsFolder

-- 1) Sporen-Kern (Body, immer vorhanden, unsichtbarer Anker) -------------------
local body = newPart("Body", Vector3.new(1.4, 1.4, 1.4), ORIGIN, Color3.fromRGB(150, 220, 255), Enum.Material.Neon, model)
body.Shape = Enum.PartType.Ball
body.Transparency = 1 -- der Kern selbst bleibt bis "OpenState" unsichtbar (verdeckt von der Hülle)

local pulseAttachment = Instance.new("Attachment")
pulseAttachment.Name = "PulseAttachment"
pulseAttachment.Parent = body

local glowLight = Instance.new("PointLight")
glowLight.Name = "FrozenSporeLight"
glowLight.Color = Color3.fromRGB(190, 230, 255)
glowLight.Range = 10
glowLight.Brightness = 1.6
glowLight.Shadows = false
glowLight.Parent = body

-- 2) Zustand 1: IcyShellState (Start, sichtbar) ---------------------------------
local icyShellState = Instance.new("Model")
icyShellState.Name = "IcyShellState"
icyShellState.Parent = model

local icyBase = newPart(
	"StateBase",
	Vector3.new(2.1, 2.1, 2.1),
	ORIGIN,
	Color3.fromRGB(190, 225, 250),
	Enum.Material.Ice,
	icyShellState,
	0
)
icyBase.Shape = Enum.PartType.Ball

local icyInner = newPart(
	"IcySheen",
	Vector3.new(1.7, 1.7, 1.7),
	ORIGIN,
	Color3.fromRGB(220, 245, 255),
	Enum.Material.Glass,
	icyShellState,
	0.4
)
icyInner.Shape = Enum.PartType.Ball
icyShellState.PrimaryPart = icyBase

-- 3) Zustand 2: CrackedState (Zwischenschritt, zunächst unsichtbar) ------------
local crackedState = Instance.new("Model")
crackedState.Name = "CrackedState"
crackedState.Parent = model

local crackedBase = newPart(
	"StateBase",
	Vector3.new(2.1, 2.1, 2.1),
	ORIGIN,
	Color3.fromRGB(190, 225, 250),
	Enum.Material.Ice,
	crackedState,
	1
)
crackedBase.Shape = Enum.PartType.Ball

for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 15)
	local crackLine = newPart(
		"CrackLine" .. i,
		Vector3.new(0.1, 1.5, 0.1),
		ORIGIN * CFrame.new(math.cos(angle) * 0.9, 0, math.sin(angle) * 0.9) * CFrame.Angles(0, angle, math.rad(20)),
		Color3.fromRGB(150, 220, 255),
		Enum.Material.Neon,
		crackedState,
		1
	)
end
crackedState.PrimaryPart = crackedBase

-- 4) Zustand 3: OpenState (aufgebrochen, zunächst unsichtbar) ------------------
local openState = Instance.new("Model")
openState.Name = "OpenState"
openState.Parent = model

local openBase = newPart(
	"StateBase",
	Vector3.new(0.4, 0.4, 0.4),
	ORIGIN,
	Color3.fromRGB(220, 245, 255),
	Enum.Material.Neon,
	openState,
	1
)
openBase.Shape = Enum.PartType.Ball

-- 4 auseinandergebrochene Eisschalen-Splitter um den freien Kern -----------------
for i = 1, 4 do
	local angle = math.rad(90 * (i - 1) + 45)
	local shard = newPart(
		"ShellShard" .. i,
		Vector3.new(0.9, 0.9, 0.15),
		ORIGIN * CFrame.new(math.cos(angle) * 1.6, math.sin(angle * 0.5) * 0.5, math.sin(angle) * 1.6)
			* CFrame.Angles(math.rad(20 * i), angle, 0),
		Color3.fromRGB(200, 235, 255),
		Enum.Material.Glass,
		openState,
		1
	)
end
openState.PrimaryPart = openBase

-- 5) Attribute -----------------------------------------------------------------
model.PrimaryPart = body
model:SetAttribute("PickupKind", "FrozenSpore")
model:SetAttribute("Event", "FrozenCurrent")
model:SetAttribute("ThawStates", "IcyShellState,CrackedState,OpenState")

print("[Abyssara] FrozenSpore erzeugt unter Workspace.Assets.Pickups")
