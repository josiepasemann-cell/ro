--[[
	RigJoints.lua
	Ort: ReplicatedStorage.CharacterAnimation.RigJoints

	Findet die Motor6D-Gelenke eines Charakter-Rigs (R15 oder vereinfacht R6)
	und bildet sie auf kanonische Namen ab, die PoseLibrary/ProceduralAnimator
	nutzen. Liefert außerdem die Rest-C0-CFrames (Ausgangspose), auf die alle
	Offsets multipliziert werden.
]]

export type RigType = "R15" | "R6"

export type RigData = {
	RigType: RigType,
	UseElbowsKnees: boolean,
	Joints: { [string]: Motor6D },
	RestC0: { [string]: CFrame },
}

local RigJoints = {}

-- kanonischer Name -> { Elternteil-Name im Rig, Motor6D-Name }
local R15_MAP = {
	Root = { "LowerTorso", "Root" },
	Waist = { "UpperTorso", "Waist" },
	Neck = { "Head", "Neck" },
	LeftShoulder = { "LeftUpperArm", "LeftShoulder" },
	LeftElbow = { "LeftLowerArm", "LeftElbow" },
	LeftWrist = { "LeftHand", "LeftWrist" },
	RightShoulder = { "RightUpperArm", "RightShoulder" },
	RightElbow = { "RightLowerArm", "RightElbow" },
	RightWrist = { "RightHand", "RightWrist" },
	LeftHip = { "LeftUpperLeg", "LeftHip" },
	LeftKnee = { "LeftLowerLeg", "LeftKnee" },
	LeftAnkle = { "LeftFoot", "LeftAnkle" },
	RightHip = { "RightUpperLeg", "RightHip" },
	RightKnee = { "RightLowerLeg", "RightKnee" },
	RightAnkle = { "RightFoot", "RightAnkle" },
}

local R6_MAP = {
	Root = { "Torso", "RootJoint" },
	Neck = { "Head", "Neck" },
	LeftShoulder = { "Left Arm", "Left Shoulder" },
	RightShoulder = { "Right Arm", "Right Shoulder" },
	LeftHip = { "Left Leg", "Left Hip" },
	RightHip = { "Right Leg", "Right Hip" },
}

local function collect(character: Model, map: { [string]: { string } }): { [string]: Motor6D }?
	local joints: { [string]: Motor6D } = {}
	for canonical, info in pairs(map) do
		local partName, motorName = info[1], info[2]
		local part = character:FindFirstChild(partName)
		if not part or not part:IsA("BasePart") then
			return nil
		end
		local motor = part:FindFirstChild(motorName)
		if not motor or not motor:IsA("Motor6D") then
			return nil
		end
		joints[canonical] = motor
	end
	return joints
end

--- Versucht, alle Gelenke zu finden. Gibt nil zurück, falls das Rig noch
--- nicht vollständig geladen ist (Aufrufer sollte es später erneut versuchen).
function RigJoints.Get(character: Model, humanoid: Humanoid): RigData?
	local isR15 = humanoid.RigType == Enum.HumanoidRigType.R15

	if isR15 then
		local joints = collect(character, R15_MAP)
		if joints then
			local restC0: { [string]: CFrame } = {}
			for name, motor in pairs(joints) do
				restC0[name] = motor.C0
			end
			return {
				RigType = "R15",
				UseElbowsKnees = true,
				Joints = joints,
				RestC0 = restC0,
			}
		end
		return nil
	end

	local joints = collect(character, R6_MAP)
	if joints then
		local restC0: { [string]: CFrame } = {}
		for name, motor in pairs(joints) do
			restC0[name] = motor.C0
		end
		return {
			RigType = "R6",
			UseElbowsKnees = false,
			Joints = joints,
			RestC0 = restC0,
		}
	end

	return nil
end

return RigJoints
