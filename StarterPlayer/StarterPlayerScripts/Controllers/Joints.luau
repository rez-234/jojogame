--!strict
-- Helpers for posing Motor6D joints procedurally on R6, R15 and built rigs.
-- Rotations are given in the parent part's frame and converted into joint
-- space, so the same pose works whatever C0 rotation a rig uses.

local Joints = {}

export type Cache = { [string]: Motor6D | false }

function Joints.Find(model: Model, cache: Cache, name: string): Motor6D?
	local cached = cache[name]
	if cached == false then
		return nil
	elseif cached ~= nil then
		return cached :: Motor6D
	end
	local found = model:FindFirstChild(name, true)
	if found and found:IsA("Motor6D") then
		cache[name] = found
		return found
	end
	cache[name] = false
	return nil
end

-- Sets a joint so the child rotates by `rotation` expressed in the parent frame.
function Joints.SetLocal(motor: Motor6D, rotation: CFrame, offset: Vector3?)
	local c0 = motor.C0.Rotation
	local t = c0:Inverse() * rotation * c0
	if offset then
		t = CFrame.new(c0:Inverse() * offset) * t
	end
	motor.Transform = t
end

-- Blends a joint toward a target pose with exponential smoothing.
function Joints.Blend(motor: Motor6D, rotation: CFrame, alpha: number, offset: Vector3?)
	local c0 = motor.C0.Rotation
	local target = c0:Inverse() * rotation * c0
	if offset then
		target = CFrame.new(c0:Inverse() * offset) * target
	end
	motor.Transform = motor.Transform:Lerp(target, math.clamp(alpha, 0, 1))
end

-- Joint names for limbs on R6 and R15 characters.
Joints.R15 = {
	LeftHip = "LeftHip",
	RightHip = "RightHip",
	LeftKnee = "LeftKnee",
	RightKnee = "RightKnee",
	LeftShoulder = "LeftShoulder",
	RightShoulder = "RightShoulder",
	LeftElbow = "LeftElbow",
	RightElbow = "RightElbow",
	Waist = "Waist",
	Neck = "Neck",
}
Joints.R6 = {
	LeftHip = "Left Hip",
	RightHip = "Right Hip",
	LeftShoulder = "Left Shoulder",
	RightShoulder = "Right Shoulder",
	Neck = "Neck",
}

function Joints.NamesFor(model: Model): { [string]: string }
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
		return Joints.R15
	end
	return Joints.R6
end

-- The riding pose: thighs forward and apart, knees bent, hands on the reins.
function Joints.RiderPose(model: Model, cache: Cache, bounce: number)
	local names = Joints.NamesFor(model)
	local function set(key: string, rot: CFrame)
		local name = names[key]
		if name then
			local m = Joints.Find(model, cache, name)
			if m then
				Joints.SetLocal(m, rot)
			end
		end
	end
	set("LeftHip", CFrame.Angles(0.5 + bounce * 0.05, 0, -0.5))
	set("RightHip", CFrame.Angles(0.5 + bounce * 0.05, 0, 0.5))
	set("LeftKnee", CFrame.Angles(-0.8, 0, 0))
	set("RightKnee", CFrame.Angles(-0.8, 0, 0))
	set("LeftShoulder", CFrame.Angles(0.75 + bounce * 0.08, 0, 0.12))
	set("RightShoulder", CFrame.Angles(0.75 + bounce * 0.08, 0, -0.12))
	set("LeftElbow", CFrame.Angles(0.55, 0, 0))
	set("RightElbow", CFrame.Angles(0.55, 0, 0))
end

return Joints
