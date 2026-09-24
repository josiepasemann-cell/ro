--[[
	BuddyClient.client.lua
	Ort: StarterPlayer.StarterPlayerScripts (via Rojo aus src/client)

	Zuständigkeit:
		Rein KOSMETISCHER, client-lokaler Renderer für ALLE sichtbaren
		Buddy-Modelle (eigene UND fremde Spieler, siehe docs/buddy.md) -
		erstellt/entsorgt pro Buddy-Modell (`CollectionService`-Tag
		"PlayerBuddy", von BuddyService serverseitig gesetzt) einen
		Follow-/Bob-/Flair-Zustand und ruft JEDEN Frame (bzw. gedrosselt,
		siehe LOD) `Model:PivotTo(...)` rein LOKAL auf - identisches
		Prinzip zu CharacterAnimator.client.lua (Motor6D.C0 wird dort auch
		nur lokal gesetzt, nie repliziert).

		WARUM CLIENT-GETRIEBEN (siehe BuddyService-Kopfkommentar
		"Bewegungs-Architektur" + docs/buddy.md für die volle Begründung):
		Das Ziel, dem gefolgt wird (die HumanoidRootPart-CFrame des
		Buddy-Besitzers), repliziert bereits kostenlos über das normale
		Charakter-Replikationssystem - ein zusätzlicher Server-Tick-Loop,
		der die Buddy-Position selbst berechnet und repliziert (wie
		CreatureDisplayService es für frei wandernde Plot-Kreaturen tut),
		wäre hier reine Redundanz. Jeder Client berechnet also selbst, wo
		der Buddy gerade sein sollte, inkl. sanftem "Aufholen" bei großem
		Abstand und Teleport-Snap bei SEHR großem Abstand (z. B. direkt
		nach TravelService.PivotTo).

		LOD (Auftrag: "with distance LOD", identisches Prinzip zu
		CharacterAnimator.client.lua): Buddys in Kamera-Nähe werden jeden
		Frame aktualisiert (Full), mittlere Distanz gedrosselt (Reduced),
		sehr weit entfernte kaum noch (Off) - hält die Kosten selbst bei
		vielen gleichzeitig sichtbaren Spielern (+ deren Buddys) klein
		genug fürs Handy.

	Rarity-Flair (Auftrag Punkt 3): Legendary/Mythic-Buddys bekommen einen
		dezenten `Trail` (billig, vom Engine-Renderer aus den Attachment-
		Positionen über Zeit erzeugt, KEIN Pro-Frame-Skriptkosten) plus
		einen gepoolten, seltenen Funkeln-Partikel-Burst (siehe
		SPARKLE_POOL_SIZE unten) - beide respektieren
		`UIKit.Settings.GetReducedEffects()`.

	Nameplate (Auftrag Punkt 4): kleines `BillboardGui` mit Kreaturen-Namen
		in Rarity-Farbe, per Tastenkürzel (V) clientseitig ein-/
		ausblendbar (BEWUSSTE VEREINFACHUNG statt eines UI-Toggles im
		Optionsmenü - es gibt aktuell keine Erweiterungsstelle für
		zusätzliche Toggles in MainMenuController.buildSettingsPanel, ein
		eigenes Options-UI hinzuzufügen wäre außerhalb des Auftragsumfangs
		dieses Systems (`MainMenuController.client.lua` gehört nicht zu
		diesem Auftrag). Identisches "Tastenkürzel statt Options-Panel"-
		Prinzip wie CharacterAnimator's Sprint-Taste).

	Zwei-Hand-Trage-Konflikt (Auftrag Punkt 5, HeldItemService.CarryPose):
		Der Buddy folgt HINTER/NEBEN der Schulter, der Zwei-Hand-Trage-Pose
		(Arme nach VORNE, siehe PoseLibrary.CarryTwoHand) ist das nicht im
		Weg - er wird deshalb NICHT ausgeblendet (Auftrag: "only if it
		visually clips - otherwise keep it"). Als günstige Sicherheits-
		Marge (falls ein künftiges, sehr breites Trage-Item doch in die
		Buddy-Zone hineinragt) wird der Folge-Abstand während `CarryPose ==
		"TwoHand"` minimal vergrößert, siehe TWO_HAND_EXTRA_BACK_OFFSET.

	Rojo-Einhängepunkt:
		src/client/BuddyClient.client.lua ->
		StarterPlayer.StarterPlayerScripts.BuddyClient
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BuddyRemotes = require(ReplicatedStorage:WaitForChild("BuddyRemotes"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Theme = UIKit.Theme
local Settings = UIKit.Settings

local BUDDY_TAG = BuddyRemotes.BUDDY_TAG

-- // Konfiguration -------------------------------------------------------------

-- Lokaler Zielpunkt relativ zur HumanoidRootPart-CFrame des Besitzers:
-- X = rechts, Y = hoch (Schulterhöhe über dem Wurzelpunkt), Z = hinten
-- (Roblox-Vorwärtsrichtung ist -Z, positives Z ist also "hinter dem
-- Charakter").
local FOLLOW_OFFSET_LOCAL = Vector3.new(2.6, 1.0, 3.0)
local TWO_HAND_EXTRA_BACK_OFFSET = 1.4 -- siehe Kopfkommentar "Zwei-Hand-Trage-Konflikt"

local BOB_AMPLITUDE_STUDS = 0.35
local BOB_SPEED_MIN, BOB_SPEED_MAX = 1.4, 2.0

-- Exponentielle Annäherung an die Zielposition (siehe updateEntry) - je
-- größer der Abstand, desto schneller das "Aufholen" (CATCHUP_*), ab
-- SNAP_DISTANCE_STUDS wird stattdessen sofort geschnappt (z. B. direkt
-- nach einem TravelService-Teleport).
local FOLLOW_BASE_RATE = 5.5
local CATCHUP_REFERENCE_DISTANCE_STUDS = 10
local MAX_CATCHUP_MULTIPLIER = 4
local SNAP_DISTANCE_STUDS = 45

local MIN_MOVE_FOR_YAW_STUDS = 0.02
local YAW_TURN_RATE = 8 -- Anteil der Winkeldifferenz, der je Sekunde "eingeholt" wird

-- LOD (siehe Kopfkommentar) - Distanzschwellen bewusst identisch bemessen
-- zu CharacterAnimator.client.lua's Rig-LOD, da beide dieselbe Kamera-
-- Blickfeld-Heuristik teilen.
local LOD_FULL_DISTANCE_STUDS = 55
local LOD_REDUCED_DISTANCE_STUDS = 130
local LOD_RECOMPUTE_INTERVAL = 0.3
local LOD_UPDATE_INTERVAL: { [string]: number } = {
	Full = 0,
	Reduced = 0.12,
	Off = 0.6,
}

local RARE_FLAIR_RARITIES: { [string]: boolean } = { Legendary = true, Mythic = true }
local SPARKLE_POOL_SIZE = 10
local SPARKLE_EMIT_INTERVAL_SECONDS = 1.4

local NAMEPLATE_MAX_DISTANCE_STUDS = 60

-- // Rarity-Farbe (identisches Fallback-Prinzip zu CodexUIController.rarityColorFor) --

local function rarityColor(rarity: any): Color3
	if typeof(rarity) == "string" and table.find(Theme.RarityOrder, rarity) then
		return (Theme.Rarity :: any)[rarity]
	end
	return Theme.Text.Secondary
end

-- // Gepooltes Funkeln-Partikelsystem (siehe Kopfkommentar "Rarity-Flair") -----
-- Identisches Grundprinzip zu src/shared/CharacterAnimation/EffectsPool.lua
-- (fester Pool aus unsichtbaren, ankerbaren Parts + ParticleEmitter,
-- round-robin wiederverwendet statt pro Emit neu erzeugt/zerstört) - hier
-- bewusst eigenständig statt jenes Moduls requiret, da EffectsPool laut
-- eigenem Kopfkommentar ausschließlich für CharacterAnimator.client.lua
-- gedacht ist.

local sparkleFolder = Instance.new("Folder")
sparkleFolder.Name = "BuddySparkleFX"
sparkleFolder.Parent = Workspace

local sparkleParts: { BasePart } = {}
local sparkleEmitters: { ParticleEmitter } = {}
local sparkleCursor = 1

for i = 1, SPARKLE_POOL_SIZE do
	local part = Instance.new("Part")
	part.Name = "BuddySparkle" .. i
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.Transparency = 1
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.Massless = true
	part.Parent = sparkleFolder

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds" -- Platzhalter, siehe EffectsPool.lua-Konvention
	emitter.Enabled = false
	emitter.Rate = 0
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Speed = NumberRange.new(0.5, 1.8)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.LightEmission = 0.6
	emitter.Parent = part

	sparkleParts[i] = part
	sparkleEmitters[i] = emitter
end

local function emitSparkle(position: Vector3, color: Color3)
	if Settings.GetReducedEffects() then
		return
	end
	local index = sparkleCursor
	sparkleCursor = (sparkleCursor % SPARKLE_POOL_SIZE) + 1

	local part = sparkleParts[index]
	local emitter = sparkleEmitters[index]
	part.CFrame = CFrame.new(position)
	emitter.Color = ColorSequence.new(color)
	emitter:Emit(10)
end

-- // Nameplate-Sichtbarkeit (Tastenkürzel-Toggle, siehe Kopfkommentar) ---------

local nameplatesEnabled = true
local activeBillboards: { [BillboardGui]: true } = {}

local function applyNameplateVisibility()
	for billboard in pairs(activeBillboards) do
		billboard.Enabled = nameplatesEnabled
	end
end

-- // Laufzeit-Zustand -----------------------------------------------------------

type BuddyEntry = {
	Model: Model,
	PrimaryPart: BasePart,
	OwnerUserId: number,
	Position: Vector3,
	Yaw: number,
	BobPhase: number,
	BobSpeed: number,
	AccumulatedDt: number,
	LOD: "Full" | "Reduced" | "Off",
	IsRareFlair: boolean,
	FlairColor: Color3,
	SparkleTimer: number,
	Billboard: BillboardGui?,
	Trail: Trail?,
}

local activeEntries: { [Model]: BuddyEntry } = {}
local rng = Random.new()

local function getCameraPosition(): Vector3
	local camera = Workspace.CurrentCamera
	return camera and camera.CFrame.Position or Vector3.new()
end

local function computeLOD(distance: number): "Full" | "Reduced" | "Off"
	if distance <= LOD_FULL_DISTANCE_STUDS then
		return "Full"
	elseif distance <= LOD_REDUCED_DISTANCE_STUDS then
		return "Reduced"
	end
	return "Off"
end

local function buildNameplate(entry: BuddyEntry, creatureName: string, rarity: any)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BuddyNameplate"
	billboard.Size = UDim2.fromOffset(150, 32)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.4, 0)
	billboard.MaxDistance = NAMEPLATE_MAX_DISTANCE_STUDS
	billboard.AlwaysOnTop = false
	billboard.Enabled = nameplatesEnabled
	billboard.Parent = entry.PrimaryPart

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Theme.Font.BodyBold
	label.TextColor3 = rarityColor(rarity)
	label.TextStrokeTransparency = 0.3
	label.TextStrokeColor3 = Theme.Text.Stroke
	label.TextScaled = true
	label.Text = creatureName
	label.Parent = billboard

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MinTextSize = 10
	constraint.MaxTextSize = 20
	constraint.Parent = label

	activeBillboards[billboard] = true
	entry.Billboard = billboard
end

local function buildRareFlair(entry: BuddyEntry)
	local part = entry.PrimaryPart

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "BuddyTrailAttachment0"
	attachment0.Position = Vector3.new(0, 0.2, 0)
	attachment0.Parent = part

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "BuddyTrailAttachment1"
	attachment1.Position = Vector3.new(0, -0.2, 0)
	attachment1.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Color = ColorSequence.new(entry.FlairColor)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.5
	trail.MinLength = 0.05
	trail.WidthScale = NumberSequence.new(0.6)
	trail.Enabled = not Settings.GetReducedEffects()
	trail.Parent = part

	entry.Trail = trail
end

local function cleanupEntry(model: Model)
	local entry = activeEntries[model]
	if not entry then
		return
	end
	activeEntries[model] = nil
	if entry.Billboard then
		activeBillboards[entry.Billboard] = nil
	end
	-- Billboard/Trail/Attachments sind Kinder des Modells und werden mit
	-- diesem zusammen aufgeräumt (Destroy() vom Server ODER Streaming-Out) -
	-- hier ist nichts weiter zu zerstören, nur die Buchführung zu löschen.
end

local function createEntry(model: Model)
	if activeEntries[model] then
		return
	end

	local primaryPart = model.PrimaryPart
	if not primaryPart then
		return
	end

	local ownerUserId = model:GetAttribute("OwnerUserId")
	if typeof(ownerUserId) ~= "number" then
		return
	end

	local rarity = model:GetAttribute("Rarity")
	local creatureName = model:GetAttribute("CreatureName")
	if typeof(creatureName) ~= "string" or creatureName == "" then
		creatureName = model:GetAttribute("CreatureId")
	end
	if typeof(creatureName) ~= "string" or creatureName == "" then
		creatureName = model.Name
	end

	local startPosition = model:GetPivot().Position

	local entry: BuddyEntry = {
		Model = model,
		PrimaryPart = primaryPart,
		OwnerUserId = ownerUserId,
		Position = startPosition,
		Yaw = 0,
		BobPhase = rng:NextNumber() * math.pi * 2,
		BobSpeed = rng:NextNumber(BOB_SPEED_MIN, BOB_SPEED_MAX),
		AccumulatedDt = 0,
		LOD = "Full",
		IsRareFlair = RARE_FLAIR_RARITIES[rarity] == true,
		FlairColor = rarityColor(rarity),
		SparkleTimer = rng:NextNumber() * SPARKLE_EMIT_INTERVAL_SECONDS,
		Billboard = nil,
		Trail = nil,
	}

	activeEntries[model] = entry

	buildNameplate(entry, creatureName :: string, rarity)
	if entry.IsRareFlair then
		buildRareFlair(entry)
	end

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanupEntry(model)
		end
	end)
end

local function onBuddyAdded(instance: Instance)
	if not instance:IsA("Model") then
		return
	end
	local model = instance :: Model
	if model.PrimaryPart then
		createEntry(model)
		return
	end
	-- PrimaryPart evtl. noch nicht repliziert (Streaming) - kurz nachfassen.
	task.defer(function()
		if model.Parent and model.PrimaryPart then
			createEntry(model)
		end
	end)
end

local function onBuddyRemoved(instance: Instance)
	if instance:IsA("Model") then
		cleanupEntry(instance :: Model)
	end
end

CollectionService:GetInstanceAddedSignal(BUDDY_TAG):Connect(onBuddyAdded)
CollectionService:GetInstanceRemovedSignal(BUDDY_TAG):Connect(onBuddyRemoved)
for _, instance in ipairs(CollectionService:GetTagged(BUDDY_TAG)) do
	onBuddyAdded(instance)
end

-- // Pro-Frame-Follow-Update ----------------------------------------------------

local function updateEntry(entry: BuddyEntry, dt: number)
	local ownerPlayer = Players:GetPlayerByUserId(entry.OwnerUserId)
	local character = ownerPlayer and ownerPlayer.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then
		-- Besitzer-Charakter (noch) nicht vorhanden/gestreamt: Buddy bleibt
		-- an der letzten bekannten Position stehen, kein Fehler.
		return
	end

	local offset = FOLLOW_OFFSET_LOCAL
	local carryPose = (character :: Model):GetAttribute("CarryPose")
	if carryPose == "TwoHand" then
		offset = offset + Vector3.new(0, 0, TWO_HAND_EXTRA_BACK_OFFSET)
	end

	local bobY = math.sin(os.clock() * entry.BobSpeed + entry.BobPhase) * BOB_AMPLITUDE_STUDS
	local desired = ((root :: BasePart).CFrame * CFrame.new(offset)).Position + Vector3.new(0, bobY, 0)

	local toDesired = desired - entry.Position
	local distance = toDesired.Magnitude

	if distance > SNAP_DISTANCE_STUDS then
		entry.Position = desired
	else
		local catchup = 1 + math.clamp(distance / CATCHUP_REFERENCE_DISTANCE_STUDS, 0, MAX_CATCHUP_MULTIPLIER)
		local alpha = 1 - math.exp(-FOLLOW_BASE_RATE * catchup * dt)
		entry.Position += toDesired * alpha
	end

	-- Blickrichtung folgt der EIGENEN Bewegungsrichtung des Buddys (nicht
	-- zwingend identisch zur Blickrichtung des Besitzers) - identisches
	-- Prinzip zu CreatureDisplayService.tickSlot (LastYaw aus Bewegungsdelta).
	local planar = Vector3.new(toDesired.X, 0, toDesired.Z)
	if planar.Magnitude > MIN_MOVE_FOR_YAW_STUDS then
		local targetYaw = math.atan2(planar.X, planar.Z)
		local yawDelta = (targetYaw - entry.Yaw + math.pi) % (2 * math.pi) - math.pi
		entry.Yaw += yawDelta * math.clamp(YAW_TURN_RATE * dt, 0, 1)
	end

	entry.Model:PivotTo(CFrame.new(entry.Position) * CFrame.Angles(0, entry.Yaw, 0))

	if entry.IsRareFlair and entry.LOD == "Full" then
		entry.SparkleTimer += dt
		if entry.SparkleTimer >= SPARKLE_EMIT_INTERVAL_SECONDS then
			entry.SparkleTimer = 0
			emitSparkle(entry.Position, entry.FlairColor)
		end
	end
end

local lodTimer = 0

RunService.PreSimulation:Connect(function(dt: number)
	lodTimer += dt
	local recompute = lodTimer >= LOD_RECOMPUTE_INTERVAL
	if recompute then
		lodTimer = 0
	end
	local camPos = recompute and getCameraPosition() or nil

	for model, entry in pairs(activeEntries) do
		if not model.Parent then
			cleanupEntry(model)
			continue
		end

		if recompute and camPos then
			entry.LOD = computeLOD((entry.Position - camPos).Magnitude)
		end

		entry.AccumulatedDt += dt
		local interval = LOD_UPDATE_INTERVAL[entry.LOD] or 0
		if entry.AccumulatedDt < interval then
			continue
		end
		local effectiveDt = entry.AccumulatedDt
		entry.AccumulatedDt = 0

		updateEntry(entry, effectiveDt)
	end
end)

-- // Reduzierte Effekte live nachziehen (Trail-Sichtbarkeit) -------------------

Settings.Changed:Connect(function(key: string, value: any)
	if key ~= "ReducedEffects" then
		return
	end
	for _, entry in pairs(activeEntries) do
		if entry.Trail then
			entry.Trail.Enabled = not (value == true)
		end
	end
end)

-- // Nameplate-Toggle (Tastenkürzel "V", siehe Kopfkommentar) ------------------

local function handleToggleNameplates(_actionName: string, inputState: Enum.UserInputState)
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	nameplatesEnabled = not nameplatesEnabled
	applyNameplateVisibility()
	return Enum.ContextActionResult.Pass
end

ContextActionService:BindAction("AbyssaraToggleBuddyNames", handleToggleNameplates, true, Enum.KeyCode.V)
ContextActionService:SetTitle("AbyssaraToggleBuddyNames", "Buddy Names")
ContextActionService:SetPosition("AbyssaraToggleBuddyNames", UDim2.new(0.75, 0, 0.55, 0))
