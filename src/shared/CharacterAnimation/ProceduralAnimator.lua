--[[
	ProceduralAnimator.lua
	Ort: ReplicatedStorage.CharacterAnimation.ProceduralAnimator

	Herzstück des Animationssystems: eine Instanz pro sichtbarem Charakter,
	die pro Frame die Motor6D.C0-Transforms setzt (rein kosmetisch, repliziert
	NICHT über das Netzwerk - deshalb animiert JEDER Client selbst JEDEN
	Charakter, den er sieht, basierend auf replizierten Humanoid-/Positions-
	daten). Das ersetzt den klassischen Animation-Track-Workflow vollständig,
	sofern in AnimationConfig keine Override-IDs gesetzt sind.

	Zustände: Idle, Walk, Run, Jump (Anticipation+Rise), Fall, Land
]]

local RigJoints = require(script.Parent:WaitForChild("RigJoints"))
local PoseLibrary = require(script.Parent:WaitForChild("PoseLibrary"))
local Spring = require(script.Parent:WaitForChild("Spring"))
local AnimationConfig = require(script.Parent:WaitForChild("AnimationConfig"))

export type LODLevel = "Full" | "Reduced" | "Off"

local ProceduralAnimator = {}
ProceduralAnimator.__index = ProceduralAnimator

export type ProceduralAnimatorT = typeof(setmetatable(
	{} :: {
		Character: Model,
		Humanoid: Humanoid,
		RootPart: BasePart,
		Rig: RigJoints.RigData,

		LOD: LODLevel,

		Phase: number,
		LastPosition: Vector3,

		IdleWeight: any,
		WalkWeight: any,
		RunWeight: any,
		AirWeight: any,
		LandWeight: any,
		CarryWeight: any,

		LeanSpring: any,
		HeadLookSpring: any,

		LandSquash: any,
		FallStartVelocityY: number,
		WasInAir: boolean,
		PrevState: Enum.HumanoidStateType,

		FootCycleSign: number,
		IdleClock: number,

		OverriddenSlots: { [string]: boolean },
		Animator: Animator?,
		Tracks: { [string]: AnimationTrack },
		ActiveOverrideSlot: string?,

		EffectsPool: any,
	},
	ProceduralAnimator
))

local EPS = 1e-3

local function isOverrideActive(self: ProceduralAnimatorT, slot: string): boolean
	return self.OverriddenSlots[slot] == true
end

local function loadOverrideTracks(self: ProceduralAnimatorT)
	self.OverriddenSlots = {}
	self.Tracks = {}

	local hasAnyOverride = false
	for slot in pairs({ Idle = true, Walk = true, Run = true, Jump = true, Fall = true, Land = true }) do
		if AnimationConfig.GetOverride(slot) then
			hasAnyOverride = true
			break
		end
	end
	if not hasAnyOverride then
		return
	end

	local ok, animator = pcall(function()
		return self.Humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", self.Humanoid)
	end)
	if not ok or not animator then
		return
	end
	self.Animator = animator :: Animator

	for _, slot in ipairs({ "Idle", "Walk", "Run", "Jump", "Fall", "Land" }) do
		local id = AnimationConfig.GetOverride(slot)
		if id then
			local anim = Instance.new("Animation")
			anim.AnimationId = id
			local success, track = pcall(function()
				return (self.Animator :: Animator):LoadAnimation(anim)
			end)
			if success and track then
				track.Priority = AnimationConfig.OverridePriority
				track.Looped = (slot == "Idle" or slot == "Walk" or slot == "Run")
				self.Tracks[slot] = track
				self.OverriddenSlots[slot] = true
			end
			anim:Destroy()
		end
	end
end

function ProceduralAnimator.new(character: Model, effectsPool: any?): ProceduralAnimatorT?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not humanoid or not rootPart or not rootPart:IsA("BasePart") then
		return nil
	end

	local rig = RigJoints.Get(character, humanoid)
	if not rig then
		return nil
	end

	local self = setmetatable({}, ProceduralAnimator) :: any
	self.Character = character
	self.Humanoid = humanoid
	self.RootPart = rootPart
	self.Rig = rig

	self.LOD = "Full"

	self.Phase = 0
	self.LastPosition = rootPart.Position

	local wSpeed = AnimationConfig.WeightSpringSpeed
	local wDamp = AnimationConfig.WeightSpringDamping
	self.IdleWeight = Spring.new(1, wSpeed, wDamp)
	self.WalkWeight = Spring.new(0, wSpeed, wDamp)
	self.RunWeight = Spring.new(0, wSpeed, wDamp)
	self.AirWeight = Spring.new(0, wSpeed, wDamp)
	self.LandWeight = Spring.new(0, wSpeed, wDamp)
	self.CarryWeight = Spring.new(0, AnimationConfig.CarryBlendSpeed, AnimationConfig.CarryBlendDamping)

	self.LeanSpring = Spring.new(0, AnimationConfig.LeanSpringSpeed, AnimationConfig.LeanSpringDamping)
	self.HeadLookSpring = Spring.new(0, 8, 1)

	self.LandSquash = Spring.new(0, AnimationConfig.LandSquashSpeed, AnimationConfig.LandSquashDamping)
	self.FallStartVelocityY = 0
	self.WasInAir = false
	self.PrevState = humanoid:GetState()

	self.FootCycleSign = 1
	self.IdleClock = 0

	self.OverriddenSlots = {}
	self.Animator = nil
	self.Tracks = {}
	self.ActiveOverrideSlot = nil

	self.EffectsPool = effectsPool

	loadOverrideTracks(self)

	return self
end

function ProceduralAnimator.SetLOD(self: ProceduralAnimatorT, level: LODLevel)
	self.LOD = level
end

local function combine(base: { [string]: CFrame }, pose: PoseLibrary.PoseOffsets, weight: number)
	if weight <= EPS then
		return
	end
	for name, offset in pairs(pose) do
		local existing = base[name]
		if existing then
			base[name] = existing:Lerp(existing * offset, weight)
		else
			base[name] = CFrame.identity:Lerp(offset, weight)
		end
	end
end

local IDENTITY_POSE_KEYS = {
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"LeftElbow",
	"LeftWrist",
	"RightShoulder",
	"RightElbow",
	"RightWrist",
	"LeftHip",
	"LeftKnee",
	"LeftAnkle",
	"RightHip",
	"RightKnee",
	"RightAnkle",
}

local function playOverrideTrack(self: ProceduralAnimatorT, slot: string?)
	if self.ActiveOverrideSlot == slot then
		return
	end
	if self.ActiveOverrideSlot then
		local prev = self.Tracks[self.ActiveOverrideSlot]
		if prev then
			prev:Stop(0.15)
		end
	end
	self.ActiveOverrideSlot = slot
	if slot then
		local track = self.Tracks[slot]
		if track then
			track:Play(0.15)
		end
	end
end

function ProceduralAnimator.Update(self: ProceduralAnimatorT, dt: number)
	if self.LOD == "Off" then
		return
	end

	local humanoid = self.Humanoid
	local rootPart = self.RootPart
	if not rootPart.Parent then
		return
	end

	local state = humanoid:GetState()
	local velocity = rootPart.AssemblyLinearVelocity
	local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude

	local underwater = AnimationConfig.UnderwaterFlairEnabled
	local dragFactor = underwater and AnimationConfig.UnderwaterDragFactor or 1

	-- ===== Zustandsklassifikation =====
	local inAir = state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping
	local isRising = state == Enum.HumanoidStateType.Jumping or (inAir and velocity.Y > 1)
	local landedNow = self.WasInAir and not inAir

	local sprintFlag = humanoid:GetAttribute("Sprinting") == true
	local isRunning = (not inAir)
		and horizontalSpeed > 1.2
		and (sprintFlag or horizontalSpeed > AnimationConfig.RunSpeedThreshold)
	local isWalking = (not inAir) and horizontalSpeed > 1.2 and not isRunning
	local isIdle = (not inAir) and horizontalSpeed <= 1.2

	-- ===== Phase: an tatsächlich zurückgelegte horizontale Distanz gekoppelt =====
	local planarDelta = Vector3.new(rootPart.Position.X - self.LastPosition.X, 0, rootPart.Position.Z - self.LastPosition.Z).Magnitude
	self.LastPosition = rootPart.Position
	if not inAir then
		self.Phase += (planarDelta / AnimationConfig.StrideLength) * (2 * math.pi) * dragFactor
		self.Phase = self.Phase % (2 * math.pi)
	end
	self.IdleClock += dt * AnimationConfig.IdleBreatheSpeed * dragFactor

	-- ===== Ziel-Gewichte =====
	self.IdleWeight:SetTarget(isIdle and 1 or 0)
	self.WalkWeight:SetTarget(isWalking and 1 or 0)
	self.RunWeight:SetTarget(isRunning and 1 or 0)
	self.AirWeight:SetTarget(inAir and 1 or 0)

	if landedNow then
		local impactSpeed = math.clamp(
			math.abs(self.FallStartVelocityY),
			AnimationConfig.MinFallSpeedForImpact,
			AnimationConfig.MaxFallSpeedForImpact
		)
		local intensity = (impactSpeed - AnimationConfig.MinFallSpeedForImpact)
			/ (AnimationConfig.MaxFallSpeedForImpact - AnimationConfig.MinFallSpeedForImpact)
		self.LandSquash:Snap(math.clamp(0.3 + intensity * 0.7, 0.3, 1))
		self.LandWeight:Snap(1)
		self.LandWeight:SetTarget(0)

		if self.LOD == "Full" and AnimationConfig.LandingFXEnabled and self.EffectsPool then
			local groundOffset = humanoid.HipHeight + rootPart.Size.Y / 2
			self.EffectsPool:EmitAt(rootPart.Position - Vector3.new(0, groundOffset, 0), "Landing")
		end
	end
	if inAir then
		self.FallStartVelocityY = velocity.Y
	end
	self.WasInAir = inAir

	local idleW = self.IdleWeight:Update(dt)
	local walkW = self.WalkWeight:Update(dt)
	local runW = self.RunWeight:Update(dt)
	local airW = self.AirWeight:Update(dt)
	local landSquashV = self.LandSquash:Update(dt)
	self.LandWeight:Update(dt)

	-- ===== Lean (Vorwärtsneigung beim Rennen, skaliert mit Geschwindigkeit) =====
	local runLeanTarget = math.clamp(horizontalSpeed / AnimationConfig.SprintSpeed, 0, 1) * AnimationConfig.RunLean * runW
	self.LeanSpring:SetTarget(runLeanTarget)
	local lean = self.LeanSpring:Update(dt)

	-- ===== Kopf leicht in Bewegungsrichtung (Differenz Blickrichtung vs. Zielrichtung) =====
	local moveDirection = humanoid.MoveDirection
	local headLookTarget = 0
	if moveDirection.Magnitude > 0.1 then
		local lookVector = rootPart.CFrame.LookVector
		local flatMove = Vector3.new(moveDirection.X, 0, moveDirection.Z)
		local flatLook = Vector3.new(lookVector.X, 0, lookVector.Z)
		if flatMove.Magnitude > 0.05 and flatLook.Magnitude > 0.05 then
			flatMove = flatMove.Unit
			flatLook = flatLook.Unit
			local cross = flatLook.X * flatMove.Z - flatLook.Z * flatMove.X
			local dot = math.clamp(flatLook:Dot(flatMove), -1, 1)
			local angle = math.acos(dot) * (cross < 0 and -1 or 1)
			headLookTarget = math.clamp(angle, -0.8, 0.8) * AnimationConfig.HeadLookStrength
		end
	end
	self.HeadLookSpring:SetTarget(headLookTarget)
	local headLook = self.HeadLookSpring:Update(dt)

	-- ===== Pose-Zusammensetzung =====
	local pose: { [string]: CFrame } = {}

	if idleW > EPS and not isOverrideActive(self, "Idle") then
		local idlePose = PoseLibrary.Idle(
			self.IdleClock,
			AnimationConfig.IdleBreatheAmp,
			underwater and AnimationConfig.UnderwaterHoverAmp or 0,
			AnimationConfig.UnderwaterHoverSpeed
		)
		combine(pose, idlePose, idleW)
	end

	if (walkW > EPS and not isOverrideActive(self, "Walk")) or (runW > EPS and not isOverrideActive(self, "Run")) then
		if walkW > EPS and not isOverrideActive(self, "Walk") then
			local walkPose = PoseLibrary.Locomotion(
				self.Phase,
				AnimationConfig.WalkLegSwing,
				AnimationConfig.WalkArmSwing,
				AnimationConfig.WalkBob,
				AnimationConfig.HipSway,
				0,
				self.Rig.UseElbowsKnees
			)
			combine(pose, walkPose, walkW)
		end
		if runW > EPS and not isOverrideActive(self, "Run") then
			local runPose = PoseLibrary.Locomotion(
				self.Phase,
				AnimationConfig.RunLegSwing,
				AnimationConfig.RunArmSwing,
				AnimationConfig.RunBob,
				AnimationConfig.HipSway * 1.4,
				lean,
				self.Rig.UseElbowsKnees
			)
			combine(pose, runPose, runW)
		end
	end

	if airW > EPS and not (isOverrideActive(self, "Jump") or isOverrideActive(self, "Fall")) then
		if isRising then
			local risePose = PoseLibrary.JumpRise(math.clamp(velocity.Y / 25, 0, 1))
			combine(pose, risePose, airW)
			local tuckPose = PoseLibrary.AirTuck(self.IdleClock, AnimationConfig.AirTuck)
			combine(pose, tuckPose, airW * 0.4)
		else
			local fallIntensity = math.clamp(-velocity.Y / 40, 0, 1) * AnimationConfig.FallBrace
			local fallPose = PoseLibrary.Fall(fallIntensity)
			combine(pose, fallPose, airW)
		end
	end

	if landSquashV > EPS and not isOverrideActive(self, "Land") then
		local landPose = PoseLibrary.LandSquash(math.clamp(landSquashV, 0, 1))
		combine(pose, landPose, math.clamp(landSquashV, 0, 1))
	end

	-- Head-Look additiv einmischen (unabhängig vom Zustand, sofern kein Override aktiv ist)
	if math.abs(headLook) > EPS and not isOverrideActive(self, "Idle") then
		local neckOffset = pose.Neck or CFrame.identity
		pose.Neck = neckOffset * CFrame.Angles(0, headLook, 0)
	end

	-- ===== Carry-Pose Override (Arme) =====
	local carryAttr = self.Character:GetAttribute("CarryPose")
	self.CarryWeight:SetTarget((carryAttr == "OneHand" or carryAttr == "TwoHand") and 1 or 0)
	local carryW = self.CarryWeight:Update(dt)
	if carryW > EPS then
		local carryPose = carryAttr == "TwoHand" and PoseLibrary.CarryTwoHand() or PoseLibrary.CarryOneHand()
		-- Arme werden komplett auf die Trage-Pose überschrieben statt addiert (klares, stabiles Tragebild)
		for name, offset in pairs(carryPose) do
			pose[name] = CFrame.identity:Lerp(offset, carryW)
		end
	end

	-- ===== Anwenden auf Motor6Ds =====
	local reduced = self.LOD == "Reduced"
	local restC0 = self.Rig.RestC0
	local joints = self.Rig.Joints

	for _, name in ipairs(IDENTITY_POSE_KEYS) do
		local motor = joints[name]
		if motor then
			if reduced and (name == "LeftElbow" or name == "RightElbow" or name == "LeftKnee" or name == "RightKnee" or name == "LeftAnkle" or name == "RightAnkle" or name == "LeftWrist" or name == "RightWrist") then
				-- Im reduzierten LOD werden Endgliedmaßen ausgelassen (Performance), Hauptgelenke bleiben lebendig
				continue
			end
			local offset = pose[name]
			local rest = restC0[name]
			if offset then
				motor.C0 = rest * offset
			elseif motor.C0 ~= rest then
				motor.C0 = rest
			end
		end
	end

	-- ===== Override-Tracks synchronisieren (falls konfiguriert) =====
	local activeSlot: string? = nil
	if isOverrideActive(self, "Land") and landSquashV > 0.05 then
		activeSlot = "Land"
	elseif isOverrideActive(self, "Jump") and inAir and isRising then
		activeSlot = "Jump"
	elseif isOverrideActive(self, "Fall") and inAir and not isRising then
		activeSlot = "Fall"
	elseif isOverrideActive(self, "Run") and isRunning then
		activeSlot = "Run"
	elseif isOverrideActive(self, "Walk") and isWalking then
		activeSlot = "Walk"
	elseif isOverrideActive(self, "Idle") and isIdle then
		activeSlot = "Idle"
	end
	if next(self.Tracks) ~= nil then
		playOverrideTrack(self, activeSlot)
	end

	-- ===== Schritt-FX beim Rennen (Full-LOD, gepoolt) =====
	if self.LOD == "Full" and AnimationConfig.FootstepFXEnabled and self.EffectsPool and isRunning and horizontalSpeed > AnimationConfig.FootstepFXMinSpeed then
		local sign = math.sign(math.sin(self.Phase))
		if sign ~= 0 and sign ~= self.FootCycleSign then
			self.FootCycleSign = sign
			-- Bevorzugt das Fußgelenk (R15) für eine präzise Bodenposition, sonst Hüfte (R6) als Näherung.
			local footJoint = sign > 0 and (joints.RightAnkle or joints.RightHip) or (joints.LeftAnkle or joints.LeftHip)
			if footJoint and footJoint.Part1 then
				local part1 = footJoint.Part1
				local footPos = part1.Position - Vector3.new(0, part1.Size.Y / 2, 0)
				self.EffectsPool:EmitAt(footPos, "Footstep")
			end
		end
	end

	self.PrevState = state
end

function ProceduralAnimator.Destroy(self: ProceduralAnimatorT)
	for _, track in pairs(self.Tracks) do
		pcall(function()
			track:Stop(0)
			track:Destroy()
		end)
	end
	table.clear(self.Tracks)

	-- Gelenke in Rest-Pose zurücksetzen, falls das Modell (z.B. für Vorschau/Inventar) weiterlebt
	for name, motor in pairs(self.Rig.Joints) do
		local rest = self.Rig.RestC0[name]
		if rest then
			pcall(function()
				motor.C0 = rest
			end)
		end
	end
end

return ProceduralAnimator
