--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Script: ModelAnimator (LocalScript)
	Zuständigkeit:
		Zentraler, EINZIGER client-seitiger Renderer für serverseitig
		"logisch" bewegte Modelle (siehe docs/animation-system.md) - macht
		die Bewegung dieser Modelle auf jedem Client flüssig/ruckelfrei,
		OHNE dass der Server jeden Tick `Model:PivotTo()` aufrufen muss
		(anchored Parts werden von Roblox beim Replizieren NICHT
		interpoliert - ein Server-Tick von 5-10 Hz sah deshalb sichtbar
		ruckelig aus).

		Entdeckt seine Modelle rein über `CollectionService`-Tags (siehe
		ModelAnimationTags) - funktioniert unabhängig von Ordnerpfad/
		Build-Reihenfolge/Streaming:

		1) `ModelAnimationTags.DISPLAY_CREATURE` (CreatureDisplayService):
		   frei wandernde Plot-Anzeige-Kreaturen. Chase/Lerp zur
		   server-publizierten `ATTR_TARGET_POSITION` + Idle-Bob/Flossen-
		   Sway (IdleSway-Modul) + Blickrichtung aus der eigenen
		   Bewegungsrichtung.
		2) `ModelAnimationTags.RAID_ENEMY` (RaidService): Raid-Gegner.
		   Identisches Chase/Lerp-Prinzip (schnellere Aufhol-Rate, Kampf
		   braucht sichtbar genauere Positionstreue) + Spawn-Einwachs-Fade +
		   Sterbe-Auflöse/Schrumpf (ATTR_DYING_AT) + CoralBarrier-
		   Verlangsamungs-Optik (ATTR_SLOWED, trägere Idle-Wobble) + Boss
		   (Attribut "IsBoss", siehe RaidService.applyEnemyVisual) bekommt
		   schwerere/größere Bob-Amplitude.
		3) `ModelAnimationTags.RAID_TOWER` (RaidService.collectTowerRuntimes):
		   platzierte Kampftürme - dauerhafter, dezenter Idle-Glow-Puls
		   (PointLight-Brightness-Wobble) + Muzzle-Flash/Recoil, ausgelöst
		   über `RaidRemotes.EnemyHit` (trägt jetzt ein `Tower`-Modell-Feld,
		   siehe RaidService-Änderung).
		4) `ModelAnimationTags.PICKUP_IDLE` (PickupSpawner/AbilityService):
		   Weltpickups (Glow/Toxic/Frozen Spore, Sunken Chest). Idle-Bob/Spin
		   NUR der dekorativen Kind-Parts (IdleSway.ApplyStationary - der
		   PrimaryPart, der das ProximityPrompt trägt, bleibt ortsfest, siehe
		   Auftrag). Sobald `ATTR_COLLECTED_AT` gesetzt ist (Sunken-Chest-
		   Öffnen/Spore-Magnet-Auto-Collect, Belohnung bereits gewertet),
		   fliegt das GANZE Modell zum Sammler (`ATTR_COLLECTOR_USER_ID`) und
		   schrumpft, statt einfach zu verschwinden - zu diesem Zeitpunkt ist
		   das Prompt bereits verbraucht/deaktiviert, ein Bewegen ist sicher.
		5) `ModelAnimationTags.BUILDING_PLACED` (PlacementService): Pop-in
		   beim Platzieren/Modell-Tausch-Upgrade (neue Modell-Instanz), kurzer
		   Highlight-Flash bei einem reinen Attribut-Update auf derselben
		   Instanz (Fail-Soft-Akzent-Upgrade), Schrumpfen beim Verkauf
		   (`ATTR_SOLD_AT`).
		6) `ModelAnimationTags.HUB_EGG` (GachaServer): die 3 Schau-Eier an der
		   Mystery-Egg-Station - rein statisches Idle-Wobble (IdleSway) um
		   ihre feste Slot-Position, der Server bewegt sie nie.

		EIN gemeinsamer `RunService.PreSimulation`-Loop für ALLE drei
		Kategorien (Auftrag: "no per-model connections") + Distanz-LOD
		(Full/Reduced/Off, identisches Stufenmuster zu
		BuddyClient.client.lua) + `UIKit.Settings.ShouldSkipFX()`/
		`GetReducedEffects()`-Respekt (Idle-Sway/Flash/Trail-Kosten
		entfallen dann, Kernbewegung bleibt für Lesbarkeit erhalten).

		Zeitbasis: `Workspace:GetServerTimeNow()` für ALLE serverseitig
		gesetzten Zeitstempel-Attribute (SpawnedAt/DyingAt) - siehe Auftrag
		"use workspace:GetServerTimeNow() for shared time so all clients
		agree". Die Chase/Lerp-Bewegung selbst braucht keine Zeitbasis-
		Synchronisation (rein lokale Annäherung an den jeweils aktuellsten
		Attribut-Wert, identisches Prinzip zu BuddyClient.client.lua).

	Rojo-Einhängepunkt:
		src/client/ModelAnimator.client.lua ->
		StarterPlayer.StarterPlayerScripts.ModelAnimator
]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ModelAnimationTags = require(ReplicatedStorage:WaitForChild("ModelAnimation"):WaitForChild("ModelAnimationTags"))
local IdleSway = require(ReplicatedStorage:WaitForChild("ModelAnimation"):WaitForChild("IdleSway"))
local RaidRemotes = require(ReplicatedStorage:WaitForChild("RaidRemotes"))
local RaidConfig = require(ReplicatedStorage:WaitForChild("RaidConfig"))
local HeldItemConfig = require(ReplicatedStorage:WaitForChild("HeldItemConfig"))
local BuildingConfig = require(ReplicatedStorage:WaitForChild("BuildingConfig"))
local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))

local Settings = UIKit.Settings

-- // Tuning ---------------------------------------------------------------------

-- Chase/Lerp (identisches Prinzip zu BuddyClient.client.lua): je größer der
-- Abstand zwischen gerenderter und Ziel-Position, desto schneller das
-- "Aufholen"; jenseits von SNAP_DISTANCE_STUDS wird sofort geschnappt (z. B.
-- direkt nach einem Despawn/Respawn oder einer großen Server-Korrektur).
local DISPLAY_CHASE_BASE_RATE = 3.5
local RAID_CHASE_BASE_RATE = 9 -- Kampf braucht sichtbar genauere Positionstreue als reines Ambiente
local CATCHUP_REFERENCE_DISTANCE_STUDS = 8
local MAX_CATCHUP_MULTIPLIER = 4
local SNAP_DISTANCE_STUDS = 40

local MIN_MOVE_FOR_YAW_STUDS = 0.03
local YAW_TURN_RATE = 7

-- Distanz-LOD (identisches Stufenmuster zu BuddyClient.client.lua).
local LOD_FULL_DISTANCE_STUDS = 70
local LOD_REDUCED_DISTANCE_STUDS = 150
local LOD_RECOMPUTE_INTERVAL = 0.35
local LOD_UPDATE_INTERVAL: { [string]: number } = {
	Full = 0,
	Reduced = 0.1,
	Off = 0.5,
}

local BOSS_BOB_SCALE = 1.6
local SLOWED_BOB_SCALE = 0.45

local SPAWN_FX_SECONDS = RaidConfig.SPAWN_FX_SECONDS
local DEATH_FX_SECONDS = RaidConfig.DEATH_FX_SECONDS

local TOWER_PULSE_SPEED = 1.4
local RECOIL_DISTANCE_STUDS = 0.35
local RECOIL_DURATION_SECONDS = 0.12
local FLASH_DURATION_SECONDS = 0.1

local PICKUP_COLLECT_FX_SECONDS = HeldItemConfig.CollectFxSeconds
local PICKUP_COLLECT_TARGET_HEIGHT_OFFSET = 2 -- studs above the collector's HumanoidRootPart

local BUILDING_POP_FX_SECONDS = 0.3
local BUILDING_FLASH_FX_SECONDS = 0.25
local BUILDING_SELL_FX_SECONDS = BuildingConfig.SELL_FX_SECONDS

local HUB_EGG_INTENSITY_SCALE = 0.6 -- gentler wobble than a free-swimming creature

-- // Gemeinsamer Chase-Zustand (DISPLAY_CREATURE + RAID_ENEMY) -----------------

type ChaseKind = "Display" | "RaidEnemy"

type ChaseEntry = {
	Model: Model,
	Kind: ChaseKind,
	Sway: IdleSway.SwayState?,
	Position: Vector3,
	Yaw: number,
	AccumulatedDt: number,
	LOD: "Full" | "Reduced" | "Off",
	-- RAID_ENEMY-spezifisch:
	SpawnedAt: number?,
	Alive: boolean,
}

local chaseEntries: { [Model]: ChaseEntry } = {}

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

local function readTargetPosition(model: Model): Vector3?
	local value = model:GetAttribute(ModelAnimationTags.ATTR_TARGET_POSITION)
	if typeof(value) == "Vector3" then
		return value
	end
	return nil
end

local function registerChaseEntry(model: Model, kind: ChaseKind)
	if chaseEntries[model] then
		return
	end
	if not model.PrimaryPart then
		task.defer(function()
			if model.Parent and model.PrimaryPart and not chaseEntries[model] then
				registerChaseEntry(model, kind)
			end
		end)
		return
	end

	local startPosition = readTargetPosition(model) or model:GetPivot().Position
	local entry: ChaseEntry = {
		Model = model,
		Kind = kind,
		Sway = IdleSway.BuildState(model),
		Position = startPosition,
		Yaw = 0,
		AccumulatedDt = 0,
		LOD = "Full",
		SpawnedAt = if kind == "RaidEnemy" then model:GetAttribute(ModelAnimationTags.ATTR_SPAWNED_AT) :: number? else nil,
		Alive = true,
	}
	chaseEntries[model] = entry

	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			chaseEntries[model] = nil
		end
	end)
end

local function unregisterChaseEntry(model: Model)
	chaseEntries[model] = nil
end

local function updateChaseEntry(entry: ChaseEntry, dt: number, now: number)
	local model = entry.Model
	local target = readTargetPosition(model)
	if not target then
		return
	end

	local baseRate = if entry.Kind == "RaidEnemy" then RAID_CHASE_BASE_RATE else DISPLAY_CHASE_BASE_RATE
	local toTarget = target - entry.Position
	local distance = toTarget.Magnitude

	if distance > SNAP_DISTANCE_STUDS then
		entry.Position = target
	elseif distance > 0.001 then
		local catchup = 1 + math.clamp(distance / CATCHUP_REFERENCE_DISTANCE_STUDS, 0, MAX_CATCHUP_MULTIPLIER)
		local alpha = 1 - math.exp(-baseRate * catchup * dt)
		entry.Position += toTarget * alpha
	end

	local planar = Vector3.new(toTarget.X, 0, toTarget.Z)
	if planar.Magnitude > MIN_MOVE_FOR_YAW_STUDS then
		local targetYaw = math.atan2(planar.X, planar.Z)
		local yawDelta = (targetYaw - entry.Yaw + math.pi) % (2 * math.pi) - math.pi
		entry.Yaw += yawDelta * math.clamp(YAW_TURN_RATE * dt, 0, 1)
	end

	local basePivot = CFrame.new(entry.Position) * CFrame.Angles(0, entry.Yaw, 0)

	-- Raid-Spawn-Einwachs-/Einblend-Skalierung (Model:ScaleTo ist bereits vom
	-- Server für die Gegnergröße gesetzt, hier wird zusätzlich rein optisch
	-- über die Bob-Intensität + Transparency "eingeblendet").
	local allowFX = not Settings.ShouldSkipFX() and entry.LOD ~= "Off"
	local intensityScale = 1
	if entry.Kind == "RaidEnemy" then
		if model:GetAttribute("IsBoss") == true then
			intensityScale *= BOSS_BOB_SCALE
		end
		if model:GetAttribute(ModelAnimationTags.ATTR_SLOWED) == true then
			intensityScale *= SLOWED_BOB_SCALE
		end
	end

	if entry.Sway and entry.LOD ~= "Off" then
		IdleSway.Apply(entry.Sway, basePivot, now, allowFX, intensityScale)
	elseif entry.LOD ~= "Off" then
		model:PivotTo(basePivot)
	end
end

-- // Raid-Gegner: Spawn-Einwachs + Sterbe-Auflösung (Transparency/Scale) -------

local raidVisualState: { [Model]: { BaseTransparency: { [BasePart]: number }, BaseScale: number } } = {}

local function captureBaseTransparency(model: Model): { [BasePart]: number }
	local map: { [BasePart]: number } = {}
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			map[descendant] = descendant.Transparency
		end
	end
	return map
end

local function applyUniformFade(model: Model, base: { [BasePart]: number }, revealAlpha: number)
	-- revealAlpha 0 = voll unsichtbar, 1 = normale (Basis-)Transparenz.
	for part, baseTransparency in pairs(base) do
		if part.Parent then
			part.Transparency = 1 - (1 - baseTransparency) * math.clamp(revealAlpha, 0, 1)
		end
	end
end

local function updateRaidEnemyVisualFx(entry: ChaseEntry, now: number)
	local model = entry.Model
	local state = raidVisualState[model]
	if not state then
		local baseScale = 1
		pcall(function()
			baseScale = (model :: any):GetScale()
		end)
		state = { BaseTransparency = captureBaseTransparency(model), BaseScale = baseScale }
		raidVisualState[model] = state
	end

	local dyingAt = model:GetAttribute(ModelAnimationTags.ATTR_DYING_AT)
	if typeof(dyingAt) == "number" then
		local elapsed = now - dyingAt
		local t = math.clamp(elapsed / DEATH_FX_SECONDS, 0, 1)
		applyUniformFade(model, state.BaseTransparency, 1 - t)
		pcall(function()
			(model :: any):ScaleTo(state.BaseScale * (1 - 0.5 * t))
		end)
		return
	end

	local spawnedAt = entry.SpawnedAt
	if typeof(spawnedAt) == "number" then
		local elapsed = now - spawnedAt
		if elapsed < SPAWN_FX_SECONDS then
			local t = math.clamp(elapsed / SPAWN_FX_SECONDS, 0, 1)
			applyUniformFade(model, state.BaseTransparency, t)
			return
		elseif elapsed < SPAWN_FX_SECONDS + 0.05 then
			-- Einwachs-Fenster gerade abgeschlossen - Basiswerte final wiederherstellen.
			applyUniformFade(model, state.BaseTransparency, 1)
		end
	end
end

-- // Discovery: DISPLAY_CREATURE + RAID_ENEMY -----------------------------------

local function onTaggedAdded(kind: ChaseKind)
	return function(instance: Instance)
		if instance:IsA("Model") then
			registerChaseEntry(instance, kind)
		end
	end
end

local function onTaggedRemoved(instance: Instance)
	if instance:IsA("Model") then
		unregisterChaseEntry(instance)
		raidVisualState[instance] = nil
	end
end

CollectionService:GetInstanceAddedSignal(ModelAnimationTags.DISPLAY_CREATURE):Connect(onTaggedAdded("Display"))
CollectionService:GetInstanceRemovedSignal(ModelAnimationTags.DISPLAY_CREATURE):Connect(onTaggedRemoved)
for _, instance in ipairs(CollectionService:GetTagged(ModelAnimationTags.DISPLAY_CREATURE)) do
	onTaggedAdded("Display")(instance)
end

CollectionService:GetInstanceAddedSignal(ModelAnimationTags.RAID_ENEMY):Connect(onTaggedAdded("RaidEnemy"))
CollectionService:GetInstanceRemovedSignal(ModelAnimationTags.RAID_ENEMY):Connect(onTaggedRemoved)
for _, instance in ipairs(CollectionService:GetTagged(ModelAnimationTags.RAID_ENEMY)) do
	onTaggedAdded("RaidEnemy")(instance)
end

-- // Raid-Türme: Idle-Glow-Puls + Muzzle-Flash/Recoil --------------------------

type TowerEntry = {
	Model: Model,
	MuzzlePart: BasePart,
	RestOffset: CFrame,
	Light: PointLight?,
	BaseBrightness: number,
	Seed: number,
	RecoilTimer: number,
	FlashTimer: number,
}

local towerEntries: { [Model]: TowerEntry } = {}

local function findMuzzlePart(model: Model): BasePart?
	local attachment = model:FindFirstChild("MuzzlePoint", true)
	if attachment and attachment:IsA("Attachment") and attachment.Parent and attachment.Parent:IsA("BasePart") then
		return attachment.Parent :: BasePart
	end
	for _, name in ipairs({ "LureOrb", "SlowPulseCore", "EelHead" }) do
		local part = model:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			return part
		end
	end
	return model.PrimaryPart
end

local function registerTower(model: Model)
	if towerEntries[model] then
		return
	end
	local muzzle = findMuzzlePart(model)
	if not muzzle then
		return
	end
	local rootPivot = model:GetPivot()
	towerEntries[model] = {
		Model = model,
		MuzzlePart = muzzle,
		RestOffset = rootPivot:ToObjectSpace(muzzle.CFrame),
		Light = muzzle:FindFirstChildWhichIsA("PointLight"),
		BaseBrightness = (muzzle:FindFirstChildWhichIsA("PointLight") :: PointLight?) and (muzzle:FindFirstChildWhichIsA("PointLight") :: PointLight).Brightness or 0,
		Seed = math.random() * 1000,
		RecoilTimer = 0,
		FlashTimer = 0,
	}
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			towerEntries[model] = nil
		end
	end)
end

local function unregisterTower(model: Model)
	towerEntries[model] = nil
end

CollectionService:GetInstanceAddedSignal(ModelAnimationTags.RAID_TOWER):Connect(function(instance)
	if instance:IsA("Model") then
		registerTower(instance)
	end
end)
CollectionService:GetInstanceRemovedSignal(ModelAnimationTags.RAID_TOWER):Connect(function(instance)
	if instance:IsA("Model") then
		unregisterTower(instance)
	end
end)
for _, instance in ipairs(CollectionService:GetTagged(ModelAnimationTags.RAID_TOWER)) do
	if instance:IsA("Model") then
		registerTower(instance)
	end
end

RaidRemotes.EnemyHit.OnClientEvent:Connect(function(payload)
	if not payload or typeof(payload.Tower) ~= "Instance" then
		return
	end
	local tower = payload.Tower :: Model
	local entry = towerEntries[tower]
	if entry then
		entry.RecoilTimer = RECOIL_DURATION_SECONDS
		entry.FlashTimer = FLASH_DURATION_SECONDS
	end
end)

local function updateTowerEntry(entry: TowerEntry, dt: number, now: number, allowFX: boolean)
	if not entry.MuzzlePart.Parent then
		return
	end

	local recoilOffset = CFrame.new()
	if entry.RecoilTimer > 0 then
		entry.RecoilTimer = math.max(0, entry.RecoilTimer - dt)
		local t = entry.RecoilTimer / RECOIL_DURATION_SECONDS
		recoilOffset = CFrame.new(0, 0, RECOIL_DISTANCE_STUDS * t)
	end

	if allowFX then
		local pulse = 0.5 + 0.5 * math.sin(now * TOWER_PULSE_SPEED + entry.Seed)
		if entry.Light then
			local flashBoost = if entry.FlashTimer > 0 then 3 else 0
			(entry.Light :: PointLight).Brightness = entry.BaseBrightness * (0.6 + 0.4 * pulse) + flashBoost
		end
	elseif entry.Light then
		(entry.Light :: PointLight).Brightness = entry.BaseBrightness
	end

	if entry.FlashTimer > 0 then
		entry.FlashTimer = math.max(0, entry.FlashTimer - dt)
	end

	local rootPivot = entry.Model:GetPivot()
	entry.MuzzlePart.CFrame = rootPivot * entry.RestOffset * recoilOffset
end

-- // Pickups: Stationary-Idle-Bob/Spin + "fliegt zum Sammler + schrumpft" ------

type PickupEntry = {
	Model: Model,
	PrimaryPart: BasePart,
	Sway: IdleSway.StationaryState?,
	Collecting: boolean,
	FlyStartPosition: Vector3?,
	FlyStartClock: number?,
}

local pickupEntries: { [Model]: PickupEntry } = {}

local function registerPickup(model: Model)
	if pickupEntries[model] then
		return
	end
	if not model.PrimaryPart then
		task.defer(function()
			if model.Parent and model.PrimaryPart and not pickupEntries[model] then
				registerPickup(model)
			end
		end)
		return
	end

	pickupEntries[model] = {
		Model = model,
		PrimaryPart = model.PrimaryPart,
		Sway = IdleSway.BuildStationaryState(model),
		Collecting = false,
		FlyStartPosition = nil,
		FlyStartClock = nil,
	}
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			pickupEntries[model] = nil
		end
	end)
end

local function unregisterPickup(model: Model)
	pickupEntries[model] = nil
end

local function resolveCollectorTargetPosition(model: Model, fallback: Vector3): Vector3
	local collectorUserId = model:GetAttribute(ModelAnimationTags.ATTR_COLLECTOR_USER_ID)
	if typeof(collectorUserId) ~= "number" then
		return fallback
	end
	local collector = Players:GetPlayerByUserId(collectorUserId)
	local character = collector and collector.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and (root :: BasePart):IsA("BasePart") then
		return (root :: BasePart).Position + Vector3.new(0, PICKUP_COLLECT_TARGET_HEIGHT_OFFSET, 0)
	end
	return fallback
end

local function updatePickupEntry(entry: PickupEntry, now: number, allowFX: boolean)
	local model = entry.Model
	local collectedAt = model:GetAttribute(ModelAnimationTags.ATTR_COLLECTED_AT)

	if typeof(collectedAt) == "number" then
		if not entry.Collecting then
			entry.Collecting = true
			entry.FlyStartPosition = entry.PrimaryPart.Position
			entry.FlyStartClock = now
		end

		local elapsed = now - (entry.FlyStartClock :: number)
		local t = math.clamp(elapsed / PICKUP_COLLECT_FX_SECONDS, 0, 1)
		local eased = t * t -- ease-in: langsam los, schneller Richtung Sammler

		local target = resolveCollectorTargetPosition(model, entry.FlyStartPosition :: Vector3)
		local newPosition = (entry.FlyStartPosition :: Vector3):Lerp(target, eased)
		model:PivotTo(CFrame.new(newPosition))

		pcall(function()
			(model :: any):ScaleTo(math.max(1 - eased, 0.05))
		end)
		return
	end

	if entry.Sway then
		IdleSway.ApplyStationary(entry.Sway, now, allowFX)
	end
end

CollectionService:GetInstanceAddedSignal(ModelAnimationTags.PICKUP_IDLE):Connect(function(instance)
	if instance:IsA("Model") then
		registerPickup(instance)
	end
end)
CollectionService:GetInstanceRemovedSignal(ModelAnimationTags.PICKUP_IDLE):Connect(function(instance)
	if instance:IsA("Model") then
		unregisterPickup(instance)
	end
end)
for _, instance in ipairs(CollectionService:GetTagged(ModelAnimationTags.PICKUP_IDLE)) do
	if instance:IsA("Model") then
		registerPickup(instance)
	end
end

-- // Gebäude: Pop-in beim Platzieren/Upgrade-Modell-Tausch, Flash beim Fail-
-- Soft-Akzent-Upgrade, Schrumpfen beim Verkauf --------------------------------

local function easeOutBack(t: number): number
	local c1 = 1.70158
	local c3 = c1 + 1
	local x = t - 1
	return 1 + c3 * x * x * x + c1 * x * x
end

type BuildingEntry = {
	Model: Model,
	BaseScale: number,
	PopStartClock: number,
	LastPlacedAt: number?,
	FlashUntilClock: number,
	Highlight: Highlight?,
	SoldStartClock: number?,
}

local buildingEntries: { [Model]: BuildingEntry } = {}

local function ensureBuildingHighlight(model: Model): Highlight
	local existing = model:FindFirstChild("__AnimHighlight")
	if existing and existing:IsA("Highlight") then
		return existing
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "__AnimHighlight"
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 1
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Parent = model
	return highlight
end

local function registerBuilding(model: Model)
	if buildingEntries[model] then
		return
	end
	local baseScale = 1
	pcall(function()
		baseScale = (model :: any):GetScale()
	end)
	buildingEntries[model] = {
		Model = model,
		BaseScale = baseScale,
		PopStartClock = os.clock(),
		LastPlacedAt = model:GetAttribute(ModelAnimationTags.ATTR_PLACED_AT) :: number?,
		FlashUntilClock = 0,
		Highlight = nil,
		SoldStartClock = nil,
	}
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			buildingEntries[model] = nil
		end
	end)
end

local function unregisterBuilding(model: Model)
	buildingEntries[model] = nil
end

local function updateBuildingEntry(entry: BuildingEntry, now: number, allowFX: boolean)
	local model = entry.Model

	local soldAt = model:GetAttribute(ModelAnimationTags.ATTR_SOLD_AT)
	if typeof(soldAt) == "number" then
		if not entry.SoldStartClock then
			entry.SoldStartClock = os.clock()
		end
		local soldStartClock = entry.SoldStartClock :: number
		local t = math.clamp((os.clock() - soldStartClock) / BUILDING_SELL_FX_SECONDS, 0, 1)
		pcall(function()
			(model :: any):ScaleTo(entry.BaseScale * (1 - t))
		end)
		return
	end

	-- Pop-in: rein client-lokal getaktet (ab dem Moment, in dem DIESER
	-- Client das Tag entdeckt hat) statt über den Server-Zeitstempel - so
	-- spielt die Animation für jeden Client sauber ab seinem eigenen
	-- Entdeckungszeitpunkt, unabhängig von Replikations-/Streaming-Latenz.
	local popElapsed = os.clock() - entry.PopStartClock
	if popElapsed < BUILDING_POP_FX_SECONDS then
		local t = math.clamp(popElapsed / BUILDING_POP_FX_SECONDS, 0, 1)
		local factor = if allowFX then easeOutBack(t) else t
		pcall(function()
			(model :: any):ScaleTo(entry.BaseScale * math.max(factor, 0.05))
		end)
	else
		local placedAt = model:GetAttribute(ModelAnimationTags.ATTR_PLACED_AT)
		if typeof(placedAt) == "number" and placedAt ~= entry.LastPlacedAt then
			entry.LastPlacedAt = placedAt
			if allowFX then
				entry.FlashUntilClock = os.clock() + BUILDING_FLASH_FX_SECONDS
			end
		end
	end

	if allowFX then
		if not entry.Highlight then
			entry.Highlight = ensureBuildingHighlight(model)
		end
		local highlight = entry.Highlight :: Highlight
		if entry.FlashUntilClock > os.clock() then
			highlight.Enabled = true
			highlight.FillTransparency = 0.45
			highlight.OutlineTransparency = 0.2
		elseif highlight.Enabled then
			highlight.Enabled = false
		end
	elseif entry.Highlight then
		entry.Highlight.Enabled = false
	end
end

CollectionService:GetInstanceAddedSignal(ModelAnimationTags.BUILDING_PLACED):Connect(function(instance)
	if instance:IsA("Model") then
		registerBuilding(instance)
	end
end)
CollectionService:GetInstanceRemovedSignal(ModelAnimationTags.BUILDING_PLACED):Connect(function(instance)
	if instance:IsA("Model") then
		unregisterBuilding(instance)
	end
end)
for _, instance in ipairs(CollectionService:GetTagged(ModelAnimationTags.BUILDING_PLACED)) do
	if instance:IsA("Model") then
		registerBuilding(instance)
	end
end

-- // Hub-Mystery-Eggs: statisches Idle-Wobble ----------------------------------

type HubEggEntry = {
	Model: Model,
	Sway: IdleSway.SwayState?,
	RestPivot: CFrame,
}

local hubEggEntries: { [Model]: HubEggEntry } = {}

local function registerHubEgg(model: Model)
	if hubEggEntries[model] then
		return
	end
	if not model.PrimaryPart then
		task.defer(function()
			if model.Parent and model.PrimaryPart and not hubEggEntries[model] then
				registerHubEgg(model)
			end
		end)
		return
	end
	hubEggEntries[model] = {
		Model = model,
		Sway = IdleSway.BuildState(model),
		RestPivot = model:GetPivot(),
	}
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			hubEggEntries[model] = nil
		end
	end)
end

local function unregisterHubEgg(model: Model)
	hubEggEntries[model] = nil
end

CollectionService:GetInstanceAddedSignal(ModelAnimationTags.HUB_EGG):Connect(function(instance)
	if instance:IsA("Model") then
		registerHubEgg(instance)
	end
end)
CollectionService:GetInstanceRemovedSignal(ModelAnimationTags.HUB_EGG):Connect(function(instance)
	if instance:IsA("Model") then
		unregisterHubEgg(instance)
	end
end)
for _, instance in ipairs(CollectionService:GetTagged(ModelAnimationTags.HUB_EGG)) do
	if instance:IsA("Model") then
		registerHubEgg(instance)
	end
end

-- // Haupt-Loop -------------------------------------------------------------------

local lodTimer = 0

RunService.PreSimulation:Connect(function(dt: number)
	local now = Workspace:GetServerTimeNow()
	lodTimer += dt
	local recomputeLod = lodTimer >= LOD_RECOMPUTE_INTERVAL
	local cameraPos = Vector3.new()
	if recomputeLod then
		lodTimer = 0
		cameraPos = getCameraPosition()
	end

	for model, entry in pairs(chaseEntries) do
		if not model.Parent then
			unregisterChaseEntry(model)
			raidVisualState[model] = nil
			continue
		end

		if recomputeLod then
			entry.LOD = computeLOD((entry.Position - cameraPos).Magnitude)
		end

		entry.AccumulatedDt += dt
		local interval = LOD_UPDATE_INTERVAL[entry.LOD] or 0
		if entry.AccumulatedDt < interval then
			continue
		end
		local effectiveDt = entry.AccumulatedDt
		entry.AccumulatedDt = 0

		updateChaseEntry(entry, effectiveDt, now)
		if entry.Kind == "RaidEnemy" then
			updateRaidEnemyVisualFx(entry, now)
		end
	end

	local allowFX = not Settings.ShouldSkipFX()

	for model, entry in pairs(towerEntries) do
		if not model.Parent then
			unregisterTower(model)
			continue
		end
		updateTowerEntry(entry, dt, now, allowFX)
	end

	for model, entry in pairs(pickupEntries) do
		if not model.Parent then
			unregisterPickup(model)
			continue
		end
		updatePickupEntry(entry, now, allowFX)
	end

	for model, entry in pairs(buildingEntries) do
		if not model.Parent then
			unregisterBuilding(model)
			continue
		end
		updateBuildingEntry(entry, now, allowFX)
	end

	for model, entry in pairs(hubEggEntries) do
		if not model.Parent then
			unregisterHubEgg(model)
			continue
		end
		if entry.Sway then
			IdleSway.Apply(entry.Sway, entry.RestPivot, now, allowFX, HUB_EGG_INTENSITY_SCALE)
		end
	end
end)
