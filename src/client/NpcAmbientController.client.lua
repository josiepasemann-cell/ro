--!strict
--[[
	Abyssara – Deep Tide Tycoon
	Script: NpcAmbientController (LocalScript)
	Responsibility:
		Cheap procedural idle animation + speech bubbles for the hub NPCs
		built by assets/models/npcs/*.lua (Shopkeeper "Shelly", Egg Keeper
		"Inky", Quest Giver "Captain Finn", Trader "Splash", Guide "Bubbles").
		Purely cosmetic/client-local, no gameplay authority, no remotes.

		Discovers NPCs via the CollectionService tag "NpcAmbient" (added by
		every npcs/*.lua buildscript) anywhere under Workspace, so it works
		regardless of exact folder path or build order.

		Per NPC, every frame:
			1. Whole-model bob (gentle vertical float) + sway (gentle yaw
			   rocking), applied rigidly via Model:PivotTo so every part
			   (including undecorated static bits like legs/tentacles/fins)
			   moves together without needing individual welds/Motor6Ds.
			2. On top of that rigid pose, "Head" is turned to look at the
			   nearest player within HEAD_TURN_RANGE studs (smoothly
			   blended, clamped to a believable yaw cone) - or back to its
			   neutral rest pose if nobody is close.
			3. "ArmL"/"ArmR" (or tentacles/fins, same naming) get a subtle
			   idle sway, plus an occasional bigger "wave" gesture when a
			   player newly walks into range.
			4. "Eye1"/"Eye2" blink periodically (brief transparency flicker).
			5. A BillboardGui speech bubble above each NPC cycles through a
			   handful of short, kid-friendly English lines.

		Distance LOD: NPCs farther than LOD_FREEZE_DISTANCE studs from the
		camera stop animating entirely (speech bubble hidden too) until the
		camera comes back into range - negligible cost either way with only
		a handful of hub NPCs, but keeps the pattern consistent with
		CharacterAnimator.client.lua's LOD approach for future-proofing.

		Respects UIKit.Settings reduced-effects (docs/ui-kit.md): when
		enabled, bob/sway/blink/wave (the "idle pulsing"-style motion) are
		skipped entirely. The cheap head-turn and the speech bubble text
		cycling (informational, not a flashy effect) keep running so the
		hub still feels readable and helpful for accessibility/low-end
		players.

	Rojo mount point:
		src/client/NpcAmbientController.client.lua ->
		StarterPlayer.StarterPlayerScripts.NpcAmbientController
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local UIKit = require(ReplicatedStorage:WaitForChild("UIKit"))
local Theme = UIKit.Theme
local Settings = UIKit.Settings

local NPC_TAG = "NpcAmbient"

-- // Tuning -------------------------------------------------------------------
local LOD_FREEZE_DISTANCE = 120 -- studs from the camera; beyond this, animation + bubble freeze
local LOD_UPDATE_INTERVAL = 0.5 -- seconds between camera-distance re-checks
local HEAD_TURN_RANGE = 20 -- studs; nearest player within this range gets looked at
local HEAD_TURN_MAX_YAW = math.rad(65) -- clamp so the head can't spin unnaturally far
local HEAD_TURN_SPEED = 6 -- higher = snappier head turning
local BOB_HEIGHT = 0.18 -- studs
local BOB_SPEED = 1.1 -- radians/sec
local SWAY_ANGLE = math.rad(4)
local SWAY_SPEED = 0.7
local ARM_IDLE_SWING = math.rad(8)
local ARM_IDLE_SPEED = 1.4
local WAVE_DURATION = 1.0 -- seconds
local WAVE_ANGLE = math.rad(38)
local WAVE_COOLDOWN_MIN = 14 -- seconds between spontaneous idle waves
local WAVE_COOLDOWN_MAX = 24
local BLINK_INTERVAL_MIN = 3
local BLINK_INTERVAL_MAX = 7
local BLINK_DURATION = 0.12
local SPEECH_LINE_DURATION = 4.5 -- seconds per line
local SPEECH_BUBBLE_MAX_DISTANCE = 55 -- studs; BillboardGui.MaxDistance

-- // Speech lines (English, short + kid-friendly, keyed by NpcId) ------------
local SPEECH_LINES: { [string]: { string } } = {
	Guide = {
		"Welcome to Tidal Market! I'll show you around.",
		"Check out the Shop for cool gear and daily deals!",
		"The Quest Board has fresh tasks every day!",
		"Portals lead to four wild zones. Level up to dive deeper!",
		"Lost? I'm always floating right here.",
		"Have fun exploring Abyssara!",
	},
	Shopkeeper = {
		"Welcome to my stand! Take a look around.",
		"Fresh decorations and gamepasses, just for you!",
		"New deals every day, so come back often!",
		"Psst... the Best Value card is totally worth it!",
		"Earn Tide Coins by collecting Glow Spores!",
	},
	EggKeeper = {
		"Mystery Eggs hide rare creatures inside...",
		"I've guarded these eggs for many, many tides.",
		"The odds are always shown before you open one. Fair and square!",
		"Some eggs glow brighter than others... wonder why?",
		"Legendary creatures are rare, but not impossible!",
	},
	QuestGiver = {
		"Ahoy, diver! I've got three tasks for you today.",
		"Finish quests to earn Tide Coins, Shards, and XP!",
		"Fresh quests appear every day at midnight.",
		"Don't forget to claim your daily reward!",
		"Together we can finish any mission, sailor's honor!",
	},
	Trader = {
		"Welcome to the Trade Dock! Trade safely with friends.",
		"Both sides must confirm, no funny business here!",
		"Show off your rarest creatures and let's trade!",
		"I make sure every trade is fair for both divers.",
		"Bring a friend and let's swap some creatures!",
	},
}
local DEFAULT_SPEECH_LINES = { "Hi there, diver!" }

-- // Types ---------------------------------------------------------------------
type Record = {
	Model: Model,
	Body: BasePart,
	Head: BasePart?,
	Eye1: BasePart?,
	Eye2: BasePart?,
	ArmL: BasePart?,
	ArmR: BasePart?,
	RestPivot: CFrame,
	HeadRestOffset: CFrame?,
	ArmLRestOffset: CFrame?,
	ArmRRestOffset: CFrame?,
	Seed: number,
	HeadYaw: number,
	WasPlayerNear: boolean,
	WaveTimer: number,
	WaveCooldown: number,
	IsWaving: boolean,
	WaveElapsed: number,
	BlinkTimer: number,
	IsBlinking: boolean,
	BlinkElapsed: number,
	Eye1Transparency: number,
	Eye2Transparency: number,
	Lines: { string },
	LineIndex: number,
	LineTimer: number,
	Billboard: BillboardGui,
	SpeechLabel: TextLabel,
	Frozen: boolean,
}

local records: { [Model]: Record } = {}
local lodTimer = 0

-- // Helpers --------------------------------------------------------------------

local function getCameraPosition(): Vector3
	local camera = workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position
	end
	return Vector3.new()
end

local function findNearestPlayerRoot(position: Vector3, maxDistance: number): (Vector3?, number)
	local bestDistance = maxDistance
	local bestPosition: Vector3? = nil
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local distance = (root.Position - position).Magnitude
			if distance <= bestDistance then
				bestDistance = distance
				bestPosition = root.Position
			end
		end
	end
	return bestPosition, bestDistance
end

local function createSpeechBubble(body: BasePart, model: Model): (BillboardGui, TextLabel)
	local heightAttribute = model:GetAttribute("SpeechHeight")
	local height = (typeof(heightAttribute) == "number") and heightAttribute or 4.5

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "SpeechBubble"
	billboard.Size = UDim2.fromOffset(220, 56)
	billboard.StudsOffset = Vector3.new(0, height, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = SPEECH_BUBBLE_MAX_DISTANCE
	billboard.Adornee = body
	billboard.Parent = body

	local bubble = Instance.new("Frame")
	bubble.Name = "Bubble"
	bubble.Size = UDim2.fromScale(1, 1)
	bubble.BackgroundColor3 = Theme.Background.PanelLight
	bubble.BackgroundTransparency = 0.08
	Theme.ApplyCorner(bubble, UDim.new(0, 12))
	local stroke = Theme.ApplyStroke(bubble, Theme.Neon.Cyan, 2)
	stroke.Transparency = 0.25
	bubble.Parent = billboard

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, -10, 0, 16)
	nameLabel.Position = UDim2.fromOffset(5, 3)
	nameLabel.Font = Theme.Font.BodyBold
	nameLabel.TextColor3 = Theme.Neon.Yellow
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextScaled = true
	nameLabel.Text = tostring(model:GetAttribute("DisplayName") or model.Name)
	nameLabel.Parent = bubble
	local nameConstraint = Instance.new("UITextSizeConstraint")
	nameConstraint.MinTextSize = 9
	nameConstraint.MaxTextSize = 13
	nameConstraint.Parent = nameLabel

	local speechLabel = Instance.new("TextLabel")
	speechLabel.Name = "SpeechLabel"
	speechLabel.BackgroundTransparency = 1
	speechLabel.Size = UDim2.new(1, -10, 1, -20)
	speechLabel.Position = UDim2.fromOffset(5, 19)
	speechLabel.Font = Theme.Font.Body
	speechLabel.TextColor3 = Theme.Text.Primary
	speechLabel.TextWrapped = true
	speechLabel.TextScaled = true
	speechLabel.Text = ""
	speechLabel.Parent = bubble
	local speechConstraint = Instance.new("UITextSizeConstraint")
	speechConstraint.MinTextSize = 9
	speechConstraint.MaxTextSize = 14
	speechConstraint.Parent = speechLabel

	return billboard, speechLabel
end

local function findPart(model: Model, name: string): BasePart?
	local child = model:FindFirstChild(name)
	if child and child:IsA("BasePart") then
		return child
	end
	return nil
end

local function registerNpc(model: Model)
	if records[model] then
		return
	end
	local body = model.PrimaryPart or findPart(model, "Body")
	if not body then
		return
	end

	local restPivot = model:GetPivot()
	local head = findPart(model, "Head")
	local armL = findPart(model, "ArmL")
	local armR = findPart(model, "ArmR")
	local eye1 = findPart(model, "Eye1")
	local eye2 = findPart(model, "Eye2")

	local npcId = tostring(model:GetAttribute("NpcId") or model.Name)
	local lines = SPEECH_LINES[npcId] or DEFAULT_SPEECH_LINES

	local billboard, speechLabel = createSpeechBubble(body, model)

	local record: Record = {
		Model = model,
		Body = body,
		Head = head,
		Eye1 = eye1,
		Eye2 = eye2,
		ArmL = armL,
		ArmR = armR,
		RestPivot = restPivot,
		HeadRestOffset = head and restPivot:ToObjectSpace(head.CFrame) or nil,
		ArmLRestOffset = armL and restPivot:ToObjectSpace(armL.CFrame) or nil,
		ArmRRestOffset = armR and restPivot:ToObjectSpace(armR.CFrame) or nil,
		Seed = math.random() * 1000,
		HeadYaw = 0,
		WasPlayerNear = false,
		WaveTimer = math.random() * (WAVE_COOLDOWN_MAX - WAVE_COOLDOWN_MIN) + WAVE_COOLDOWN_MIN,
		WaveCooldown = WAVE_COOLDOWN_MIN,
		IsWaving = false,
		WaveElapsed = 0,
		BlinkTimer = math.random() * (BLINK_INTERVAL_MAX - BLINK_INTERVAL_MIN) + BLINK_INTERVAL_MIN,
		IsBlinking = false,
		BlinkElapsed = 0,
		Eye1Transparency = eye1 and eye1.Transparency or 0,
		Eye2Transparency = eye2 and eye2.Transparency or 0,
		Lines = lines,
		LineIndex = 1,
		LineTimer = 0,
		Billboard = billboard,
		SpeechLabel = speechLabel,
		Frozen = false,
	}
	records[model] = record
end

local function unregisterNpc(model: Model)
	local record = records[model]
	if not record then
		return
	end
	records[model] = nil
end

-- // Per-frame update -----------------------------------------------------------

local function updateSpeech(record: Record, dt: number)
	record.LineTimer -= dt
	if record.LineTimer <= 0 then
		record.LineTimer = SPEECH_LINE_DURATION
		record.LineIndex = (record.LineIndex % #record.Lines) + 1
		record.SpeechLabel.Text = record.Lines[record.LineIndex]
	elseif record.SpeechLabel.Text == "" then
		record.SpeechLabel.Text = record.Lines[record.LineIndex]
	end
end

local function updateBlink(record: Record, dt: number, allowFX: boolean)
	if not allowFX or (not record.Eye1 and not record.Eye2) then
		return
	end
	if record.IsBlinking then
		record.BlinkElapsed += dt
		if record.BlinkElapsed >= BLINK_DURATION then
			record.IsBlinking = false
			if record.Eye1 then
				record.Eye1.Transparency = record.Eye1Transparency
			end
			if record.Eye2 then
				record.Eye2.Transparency = record.Eye2Transparency
			end
		end
		return
	end
	record.BlinkTimer -= dt
	if record.BlinkTimer <= 0 then
		record.BlinkTimer = BLINK_INTERVAL_MIN + math.random() * (BLINK_INTERVAL_MAX - BLINK_INTERVAL_MIN)
		record.IsBlinking = true
		record.BlinkElapsed = 0
		if record.Eye1 then
			record.Eye1.Transparency = 1
		end
		if record.Eye2 then
			record.Eye2.Transparency = 1
		end
	end
end

local function updateArms(record: Record, currentPivot: CFrame, now: number, dt: number, allowFX: boolean)
	if record.IsWaving then
		record.WaveElapsed += dt
		if record.WaveElapsed >= WAVE_DURATION then
			record.IsWaving = false
		end
	end

	local waveT = record.IsWaving and math.sin((record.WaveElapsed / WAVE_DURATION) * math.pi) or 0

	if record.ArmR and record.ArmRRestOffset then
		local idle = allowFX and math.sin(now * ARM_IDLE_SPEED + record.Seed) * ARM_IDLE_SWING or 0
		local wave = waveT * WAVE_ANGLE
		record.ArmR.CFrame = currentPivot * record.ArmRRestOffset * CFrame.Angles(0, 0, -(idle + wave))
	end
	if record.ArmL and record.ArmLRestOffset then
		local idle = allowFX and math.sin(now * ARM_IDLE_SPEED + record.Seed + math.pi) * ARM_IDLE_SWING or 0
		record.ArmL.CFrame = currentPivot * record.ArmLRestOffset * CFrame.Angles(0, 0, idle)
	end
end

local function updateHeadTurn(record: Record, currentPivot: CFrame, dt: number, nearestPlayerPos: Vector3?)
	if not record.Head or not record.HeadRestOffset then
		return
	end

	local targetYaw = 0
	if nearestPlayerPos then
		local headWorldPos = (currentPivot * record.HeadRestOffset).Position
		local toPlayer = nearestPlayerPos - headWorldPos
		local flat = Vector3.new(toPlayer.X, 0, toPlayer.Z)
		if flat.Magnitude > 0.05 then
			-- Yaw of the player relative to the model's own forward direction.
			local forward = currentPivot.LookVector
			local forwardFlat = Vector3.new(forward.X, 0, forward.Z)
			if forwardFlat.Magnitude > 0.001 then
				forwardFlat = forwardFlat.Unit
				local dirFlat = flat.Unit
				local dot = math.clamp(forwardFlat:Dot(dirFlat), -1, 1)
				local cross = forwardFlat.X * dirFlat.Z - forwardFlat.Z * dirFlat.X
				local angle = math.acos(dot)
				targetYaw = math.clamp(cross < 0 and angle or -angle, -HEAD_TURN_MAX_YAW, HEAD_TURN_MAX_YAW)
			end
		end
	end

	local alpha = math.clamp(HEAD_TURN_SPEED * dt, 0, 1)
	record.HeadYaw += (targetYaw - record.HeadYaw) * alpha
	record.Head.CFrame = currentPivot * record.HeadRestOffset * CFrame.Angles(0, record.HeadYaw, 0)
end

local function updateRecord(record: Record, dt: number, now: number, cameraPos: Vector3, recomputeLod: boolean)
	if recomputeLod then
		local distance = (record.Body.Position - cameraPos).Magnitude
		record.Frozen = distance > LOD_FREEZE_DISTANCE
		record.Billboard.Enabled = not record.Frozen
	end

	if record.Frozen then
		return
	end

	local allowFX = not Settings.ShouldSkipFX()

	-- 1) Whole-model bob + sway (rigid transform, moves every part together)
	local currentPivot = record.RestPivot
	if allowFX then
		local bob = math.sin(now * BOB_SPEED + record.Seed) * BOB_HEIGHT
		local sway = math.sin(now * SWAY_SPEED + record.Seed * 0.5) * SWAY_ANGLE
		currentPivot = record.RestPivot * CFrame.new(0, bob, 0) * CFrame.Angles(0, sway, 0)
		record.Model:PivotTo(currentPivot)
	end

	-- 2) Nearest player lookup (head-turn always active; it's cheap + helpful)
	local nearestPlayerPos = select(1, findNearestPlayerRoot(record.Body.Position, HEAD_TURN_RANGE))
	local playerNear = nearestPlayerPos ~= nil
	if playerNear and not record.WasPlayerNear and allowFX and not record.IsWaving then
		record.IsWaving = true
		record.WaveElapsed = 0
	end
	record.WasPlayerNear = playerNear

	updateHeadTurn(record, currentPivot, dt, nearestPlayerPos)

	if allowFX then
		-- 3) Idle arm sway + occasional spontaneous wave (even with nobody around)
		if not record.IsWaving then
			record.WaveTimer -= dt
			if record.WaveTimer <= 0 then
				record.WaveTimer = WAVE_COOLDOWN_MIN + math.random() * (WAVE_COOLDOWN_MAX - WAVE_COOLDOWN_MIN)
				record.IsWaving = true
				record.WaveElapsed = 0
			end
		end
		updateArms(record, currentPivot, now, dt, true)
		-- 4) Blink
		updateBlink(record, dt, true)
	elseif record.ArmL or record.ArmR then
		updateArms(record, currentPivot, now, dt, false)
	end

	-- 5) Speech bubble text cycling (kept even under reduced effects)
	updateSpeech(record, dt)
end

-- // Discovery -------------------------------------------------------------------

for _, instance in CollectionService:GetTagged(NPC_TAG) do
	if instance:IsA("Model") then
		registerNpc(instance)
	end
end

CollectionService:GetInstanceAddedSignal(NPC_TAG):Connect(function(instance: Instance)
	if instance:IsA("Model") then
		registerNpc(instance)
	end
end)

CollectionService:GetInstanceRemovedSignal(NPC_TAG):Connect(function(instance: Instance)
	if instance:IsA("Model") then
		unregisterNpc(instance)
	end
end)

-- // Main loop --------------------------------------------------------------------

RunService.Heartbeat:Connect(function(dt: number)
	local now = os.clock()
	lodTimer += dt
	local recomputeLod = lodTimer >= LOD_UPDATE_INTERVAL
	local cameraPos = Vector3.new()
	if recomputeLod then
		lodTimer = 0
		cameraPos = getCameraPosition()
	end

	for model, record in pairs(records) do
		if not model.Parent then
			unregisterNpc(model)
			continue
		end
		updateRecord(record, dt, now, cameraPos, recomputeLod)
	end
end)
