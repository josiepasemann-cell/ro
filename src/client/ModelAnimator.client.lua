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

local ModelAnimationTags = require(ReplicatedStorage:WaitForChild("ModelAnimation"):WaitForChild("ModelAnimationTags"))
local IdleSway = require(ReplicatedStorage:WaitForChild("ModelAnimation"):WaitForChild("IdleSway"))
local RaidRemotes = require(ReplicatedStorage:WaitForChild("RaidRemotes"))
local RaidConfig = require(ReplicatedStorage:WaitForChild("RaidConfig"))
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

local raidVisualState: { [Model]: { BaseTransparency: { [BasePart]: number } } } = {}

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
		state = { BaseTransparency = captureBaseTransparency(model) }
		raidVisualState[model] = state
	end

	local dyingAt = model:GetAttribute(ModelAnimationTags.ATTR_DYING_AT)
	if typeof(dyingAt) == "number" then
		local elapsed = now - dyingAt
		local t = math.clamp(elapsed / DEATH_FX_SECONDS, 0, 1)
		applyUniformFade(model, state.BaseTransparency, 1 - t)
		local shrink = 1 - 0.5 * t
		model:PivotTo(model:GetPivot() * CFrame.new())
		pcall(function()
			model:ScaleTo(shrink)
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

	local allowTowerFX = not Settings.ShouldSkipFX()
	for model, entry in pairs(towerEntries) do
		if not model.Parent then
			unregisterTower(model)
			continue
		end
		updateTowerEntry(entry, dt, now, allowTowerFX)
	end
end)
