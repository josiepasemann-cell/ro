--!strict
--[[
	PoseLibrary.lua
	Ort: ReplicatedStorage.CharacterAnimation.PoseLibrary

	Reine Funktionen (keine Instances, kein State), die für einen gegebenen
	Zyklus-Phasenwinkel bzw. Pose-Parameter CFrame-Offsets pro Gelenk liefern.
	Die Offsets werden vom ProceduralAnimator mit dem Rest-C0 jedes Motor6D
	multipliziert: joint.C0 = RestC0[name] * offsets[name]

	Kanonische Gelenknamen (siehe RigJoints.lua):
	Root, Waist, Neck,
	LeftShoulder, LeftElbow, LeftWrist, RightShoulder, RightElbow, RightWrist,
	LeftHip, LeftKnee, LeftAnkle, RightHip, RightKnee, RightAnkle
]]

local CFrameNew = CFrame.new
local CFrameAngles = CFrame.Angles
local IDENTITY = CFrame.identity

export type PoseOffsets = { [string]: CFrame }

local PoseLibrary = {}

local function angles(rx: number, ry: number, rz: number): CFrame
	return CFrameAngles(rx, ry, rz)
end

--- Idle: Atmen (Brustkorb + Kopf), sanftes Schweben im Unterwasser-Setting.
function PoseLibrary.Idle(t: number, breatheAmp: number, underwaterAmp: number, underwaterSpeed: number): PoseOffsets
	local breathe = math.sin(t) * breatheAmp
	local hover = math.sin(t * underwaterSpeed + 1.4) * underwaterAmp
	local swayArm = math.sin(t * 0.5) * 0.035

	return {
		Root = CFrameNew(0, hover * 0.5, 0),
		Waist = angles(breathe * 0.6, 0, 0),
		Neck = angles(-breathe * 0.3, math.sin(t * 0.35) * 0.05, 0),
		LeftShoulder = angles(0, 0, -0.06 + swayArm),
		RightShoulder = angles(0, 0, 0.06 - swayArm),
		LeftHip = IDENTITY,
		RightHip = IDENTITY,
	}
end

--[[
	Locomotion (Gehen/Rennen, gleiche Formel, unterschiedliche Amplituden):
	phase: fortlaufender Winkel, an zurückgelegte Distanz gekoppelt (kein Moonwalk)
	legSwing/armSwing: Amplituden in Radiant
	bob: vertikaler Körper-Bob in Studs
	hipSway: seitliche Hüftrotation
	lean: Vorwärtsneigung des Oberkörpers (v.a. beim Rennen)
	useElbowsKnees: false bei R6 (keine Ellbogen/Knie-Gelenke)
]]
function PoseLibrary.Locomotion(
	phase: number,
	legSwing: number,
	armSwing: number,
	bob: number,
	hipSway: number,
	lean: number,
	useElbowsKnees: boolean
): PoseOffsets
	local legL = math.sin(phase) * legSwing
	local legR = math.sin(phase + math.pi) * legSwing
	local armL = math.sin(phase + math.pi) * armSwing -- Gegenpendel zum Bein
	local armR = math.sin(phase) * armSwing

	-- Bob: zwei Zyklen pro Schrittzyklus (Doppelschritt = beide Füße unten)
	local bobOffset = math.abs(math.sin(phase)) * bob
	local sway = math.sin(phase) * hipSway

	local offsets: PoseOffsets = {
		Root = CFrameNew(0, bobOffset, 0) * angles(lean, 0, 0),
		Waist = angles(lean * 0.5, sway * 0.4, sway * 0.5),
		Neck = angles(-lean * 0.4, 0, -sway * 0.3),

		LeftShoulder = angles(armL, 0, 0.05),
		RightShoulder = angles(armR, 0, -0.05),

		LeftHip = angles(legL, 0, -sway * 0.2),
		RightHip = angles(legR, 0, sway * 0.2),
	}

	if useElbowsKnees then
		-- Ellbogen beugen sich beim Vorschwingen des Arms (natürlicher Pendel statt Stab-Arm)
		local elbowL = math.max(0, math.sin(phase + math.pi)) * (armSwing * 0.9)
		local elbowR = math.max(0, math.sin(phase)) * (armSwing * 0.9)
		-- Knie beugen sich beim Anheben des Beins
		local kneeL = math.max(0, -math.sin(phase)) * (legSwing * 1.3)
		local kneeR = math.max(0, -math.sin(phase + math.pi)) * (legSwing * 1.3)

		offsets.LeftElbow = angles(-elbowL, 0, 0)
		offsets.RightElbow = angles(-elbowR, 0, 0)
		offsets.LeftKnee = angles(kneeL, 0, 0)
		offsets.RightKnee = angles(kneeR, 0, 0)
		offsets.LeftAnkle = angles(-legL * 0.5, 0, 0)
		offsets.RightAnkle = angles(-legR * 0.5, 0, 0)
	end

	return offsets
end

--- Anticipation: kurzes Einknicken direkt vor dem Absprung (0 = Boden, 1 = volle Einknickung)
function PoseLibrary.Anticipation(intensity: number): PoseOffsets
	local crouch = intensity * 0.35
	return {
		Root = CFrameNew(0, -intensity * 0.18, 0),
		Waist = angles(crouch * 0.6, 0, 0),
		LeftHip = angles(-crouch, 0, 0),
		RightHip = angles(-crouch, 0, 0),
		LeftKnee = angles(crouch * 1.6, 0, 0),
		RightKnee = angles(crouch * 1.6, 0, 0),
		LeftShoulder = angles(-crouch * 0.8, 0, 0.1),
		RightShoulder = angles(-crouch * 0.8, 0, -0.1),
	}
end

--- Absprung-Streckung: Körper streckt sich beim Verlassen des Bodens
function PoseLibrary.JumpRise(intensity: number): PoseOffsets
	return {
		Root = CFrameNew(0, intensity * 0.12, 0),
		Waist = angles(-intensity * 0.15, 0, 0),
		LeftHip = angles(intensity * 0.3, 0, 0),
		RightHip = angles(intensity * 0.3, 0, 0),
		LeftKnee = angles(-intensity * 0.1, 0, 0),
		RightKnee = angles(-intensity * 0.1, 0, 0),
		LeftShoulder = angles(-intensity * 1.4, 0, 0.15),
		RightShoulder = angles(-intensity * 1.4, 0, -0.15),
		Neck = angles(-intensity * 0.15, 0, 0),
	}
end

--- Tuck in der Luft (Apex-Gefühl): Knie leicht angezogen, Arme balancieren
function PoseLibrary.AirTuck(t: number, intensity: number): PoseOffsets
	local wobble = math.sin(t * 3) * 0.05 * intensity
	return {
		Waist = angles(intensity * 0.08, wobble, 0),
		LeftHip = angles(intensity * 0.55, 0, wobble),
		RightHip = angles(intensity * 0.55, 0, -wobble),
		LeftKnee = angles(intensity * 0.9, 0, 0),
		RightKnee = angles(intensity * 0.9, 0, 0),
		LeftShoulder = angles(-intensity * 0.5, 0, 0.3 + wobble),
		RightShoulder = angles(-intensity * 0.5, 0, -0.3 - wobble),
		Neck = angles(intensity * 0.1, 0, 0),
	}
end

--- Fall-Pose: Beine strecken sich nach unten (Bracing), Arme leicht ausgestreckt
function PoseLibrary.Fall(intensity: number): PoseOffsets
	return {
		Root = CFrameNew(0, -intensity * 0.05, 0),
		Waist = angles(-intensity * 0.1, 0, 0),
		LeftHip = angles(-intensity * 0.2, 0, 0),
		RightHip = angles(-intensity * 0.2, 0, 0),
		LeftKnee = angles(intensity * 0.25, 0, 0),
		RightKnee = angles(intensity * 0.25, 0, 0),
		LeftShoulder = angles(-intensity * 0.9, 0, 0.35),
		RightShoulder = angles(-intensity * 0.9, 0, -0.35),
		LeftElbow = angles(-intensity * 0.3, 0, 0),
		RightElbow = angles(-intensity * 0.3, 0, 0),
		Neck = angles(-intensity * 0.2, 0, 0),
	}
end

--- Landungs-Squash: squash (0..1) = wie stark gestaucht, federt via ProceduralAnimator zurück auf 0
function PoseLibrary.LandSquash(squash: number): PoseOffsets
	return {
		Root = CFrameNew(0, -squash * 0.28, 0),
		Waist = angles(squash * 0.5, 0, 0),
		LeftHip = angles(-squash * 0.9, 0, 0),
		RightHip = angles(-squash * 0.9, 0, 0),
		LeftKnee = angles(squash * 1.5, 0, 0),
		RightKnee = angles(squash * 1.5, 0, 0),
		LeftAnkle = angles(-squash * 0.4, 0, 0),
		RightAnkle = angles(-squash * 0.4, 0, 0),
		LeftShoulder = angles(squash * 0.5, 0, 0.1),
		RightShoulder = angles(squash * 0.5, 0, -0.1),
	}
end

--- Trage-Pose einhändig: rechter Arm hält ein Item vor dem Körper, linker Arm frei
function PoseLibrary.CarryOneHand(): PoseOffsets
	return {
		RightShoulder = angles(-1.55, 0, -0.25),
		RightElbow = angles(-1.3, 0, 0),
	}
end

--- Trage-Pose zweihändig: beide Arme halten Item vor dem Körper
function PoseLibrary.CarryTwoHand(): PoseOffsets
	return {
		LeftShoulder = angles(-1.5, 0, 0.3),
		RightShoulder = angles(-1.5, 0, -0.3),
		LeftElbow = angles(-1.2, 0, 0),
		RightElbow = angles(-1.2, 0, 0),
	}
end

return PoseLibrary
