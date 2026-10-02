--!strict
-- Animates every summoned Stand from the Pose, PoseAt and PoseDuration
-- attributes the server sets: a floating idle, jabs, barrages, heavy swings,
-- pointing, dashing, guarding and the signature poses. Stand joints are world
-- aligned, so a shoulder Transform of CFrame.Angles(rad(90), 0, 0) swings
-- that arm straight forward.

local RunService = game:GetService("RunService")

local Joints = require(script.Parent.Joints)

local StandAnimator = {}

type Entry = {
	Model: Model,
	Root: BasePart,
	Cache: Joints.Cache,
	Pose: string,
	PoseStart: number,
	Duration: number,
	PunchIndex: number,
	Seed: number,
	Scale: number,
	Conn: RBXScriptConnection,
}

local DEFAULT_DURATION: { [string]: number } = {
	Punch = 0.32,
	Heavy = 0.8,
	Point = 0.6,
	Dash = 0.5,
	Heal = 0.8,
	TimeStop = 0.8,
	Erase = 2,
	Counter = 1.5,
	Rewind = 0.8,
	Buff = 0.8,
	Barrage = 2,
}

local entries: { [Model]: Entry } = {}
local camera = workspace.CurrentCamera

local function readPose(entry: Entry)
	local model = entry.Model
	local pose = model:GetAttribute("Pose")
	local at = model:GetAttribute("PoseAt")
	local duration = model:GetAttribute("PoseDuration")
	local name = if type(pose) == "string" then pose else "Idle"
	entry.Pose = name
	entry.PoseStart = if type(at) == "number" then at else workspace:GetServerTimeNow()
	if name == "Punch" then
		-- Punches never set a duration; alternate arms on each one.
		entry.Duration = DEFAULT_DURATION.Punch
		entry.PunchIndex += 1
	elseif type(duration) == "number" and duration > 0 then
		entry.Duration = duration
	else
		entry.Duration = DEFAULT_DURATION[name] or 0.6
	end
end

local function add(model: Instance)
	if not model:IsA("Model") or entries[model] then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChild("Root") :: BasePart?
	if not root then
		return
	end
	local entry: Entry = {
		Model = model,
		Root = root,
		Cache = {},
		Pose = "Idle",
		PoseStart = 0,
		Duration = 0,
		PunchIndex = 0,
		Seed = math.random() * 10,
		Scale = model:GetScale(),
		Conn = nil :: any,
	}
	entry.Conn = model:GetAttributeChangedSignal("PoseAt"):Connect(function()
		readPose(entry)
	end)
	readPose(entry)
	entries[model] = entry
end

local function remove(model: Instance)
	if model:IsA("Model") then
		local entry = entries[model]
		if entry then
			entry.Conn:Disconnect()
			entries[model] = nil
		end
	end
end

type Pose = { [string]: CFrame }

local function idlePose(t: number, seed: number, scale: number): Pose
	local float = math.sin(t * 2.2 + seed) * 0.25 * scale
	local sway = math.sin(t * 1.1 + seed) * 0.05
	return {
		Waist = CFrame.new(0, float, 0) * CFrame.Angles(0.05 + sway, 0, 0),
		Neck = CFrame.Angles(0, math.sin(t * 0.4 + seed) * 0.15, 0),
		LShoulder = CFrame.Angles(0.35 + sway, 0, -0.15),
		RShoulder = CFrame.Angles(0.35 - sway, 0, 0.15),
		LElbow = CFrame.Angles(1.1, 0, 0),
		RElbow = CFrame.Angles(1.1, 0, 0),
		LHip = CFrame.Angles(-0.15 + sway, 0, -0.05),
		RHip = CFrame.Angles(0.1 - sway, 0, 0.05),
		LKnee = CFrame.Angles(-0.35, 0, 0),
		RKnee = CFrame.Angles(-0.5, 0, 0),
		JawJoint = CFrame.Angles(-0.05 - math.max(0, math.sin(t * 0.7 + seed)) * 0.1, 0, 0),
	}
end

local function arm(pose: Pose, side: string, shoulder: CFrame, elbow: CFrame)
	pose[side .. "Shoulder"] = shoulder
	pose[side .. "Elbow"] = elbow
end

local function actionPose(entry: Entry, pose: Pose, e: number, t: number)
	local name = entry.Pose
	local d = entry.Duration
	local scale = entry.Scale
	local float = math.sin(t * 2.2 + entry.Seed) * 0.12 * scale
	if name == "Punch" then
		local k = math.clamp(e / d, 0, 1)
		local ext = math.sin(k * math.pi)
		local side = if entry.PunchIndex % 2 == 0 then "R" else "L"
		local other = if side == "R" then "L" else "R"
		local twist = if side == "R" then 0.3 else -0.3
		arm(pose, side, CFrame.Angles(0.35 + 1.25 * ext, 0, 0), CFrame.Angles(1.1 * (1 - ext), 0, 0))
		arm(pose, other, CFrame.Angles(0.25, 0, 0), CFrame.Angles(1.6, 0, 0))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(-0.1 * ext, twist * ext, 0)
		pose.JawJoint = CFrame.Angles(-0.6 * ext, 0, 0)
		pose.Neck = CFrame.Angles(-0.45 * ext, 0, 0)
	elseif name == "Barrage" then
		local wave = math.sin(e * 16 * math.pi)
		local r = math.max(0, wave)
		local l = math.max(0, -wave)
		local jitter = math.sin(e * 37) * 0.25
		arm(pose, "R", CFrame.Angles(1.15 + r * 0.45, jitter, -jitter * 0.5), CFrame.Angles(1.4 * (1 - r), 0, 0))
		arm(pose, "L", CFrame.Angles(1.15 + l * 0.45, -jitter, jitter * 0.5), CFrame.Angles(1.4 * (1 - l), 0, 0))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(-0.15, wave * 0.12, 0)
		pose.JawJoint = CFrame.Angles(-0.4 - r * 0.3, 0, 0)
		pose.Neck = CFrame.Angles(-0.2, 0, 0)
	elseif name == "Heavy" then
		local windup = d * 0.65
		if e < windup then
			local w = math.clamp(e / windup, 0, 1)
			arm(pose, "R", CFrame.Angles(-0.7 * w, 0, 0.3 * w), CFrame.Angles(1.2, 0, 0))
			arm(pose, "L", CFrame.Angles(0.6, 0, -0.2), CFrame.Angles(1.2, 0, 0))
			pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(0.1 * w, -0.45 * w, 0)
			pose.Neck = CFrame.Angles(0.15 * w, 0, 0)
		else
			local k = math.clamp((e - windup) / math.max(0.05, d - windup), 0, 1)
			local s = math.sin(math.min(1, k * 2) * math.pi / 2)
			arm(pose, "R", CFrame.Angles(1.65 * s, 0, 0), CFrame.Angles(0.1, 0, 0))
			arm(pose, "L", CFrame.Angles(0.2, 0, 0), CFrame.Angles(1.5, 0, 0))
			pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(-0.25 * s, 0.4 * s, 0)
			pose.Neck = CFrame.Angles(-0.5 * s, 0, 0)
			pose.JawJoint = CFrame.Angles(-0.7 * s, 0, 0)
		end
	elseif name == "Point" then
		arm(pose, "R", CFrame.Angles(1.5, 0, 0), CFrame.Angles(0.05, 0, 0))
		arm(pose, "L", CFrame.Angles(0.2, 0, -0.1), CFrame.Angles(0.8, 0, 0))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(0, 0.15, 0)
		pose.JawJoint = CFrame.Angles(-0.5, 0, 0)
	elseif name == "Dash" then
		arm(pose, "R", CFrame.Angles(-0.6, 0, 0.2), CFrame.Angles(0.3, 0, 0))
		arm(pose, "L", CFrame.Angles(-0.6, 0, -0.2), CFrame.Angles(0.3, 0, 0))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(-0.55, 0, 0)
		pose.LHip = CFrame.Angles(-0.6, 0, 0)
		pose.RHip = CFrame.Angles(-0.4, 0, 0)
		pose.Neck = CFrame.Angles(0.3, 0, 0)
	elseif name == "Heal" then
		arm(pose, "R", CFrame.Angles(1.2, 0, 0.35), CFrame.Angles(0.3, 0, 0))
		arm(pose, "L", CFrame.Angles(1.2, 0, -0.35), CFrame.Angles(0.3, 0, 0))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(0.05, 0, 0)
	elseif name == "TimeStop" then
		local k = math.clamp(e / 0.25, 0, 1)
		arm(pose, "R", CFrame.Angles(0.2, 0, 1.3 * k), CFrame.Angles(0.2, 0, 0))
		arm(pose, "L", CFrame.Angles(0.2, 0, -1.3 * k), CFrame.Angles(0.2, 0, 0))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(0.15 * k, 0, 0)
		pose.Neck = CFrame.Angles(0.3 * k, 0, 0)
	elseif name == "Erase" then
		arm(pose, "R", CFrame.Angles(0.9, 0, 0.1), CFrame.Angles(0.8, 0, 0))
		arm(pose, "L", CFrame.Angles(0.9, 0, -0.1), CFrame.Angles(0.8, 0, 0))
		pose.Neck = CFrame.Angles(-0.2, 0, 0)
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(-0.1, 0, 0)
	elseif name == "Counter" then
		arm(pose, "R", CFrame.Angles(1.3, 0, -0.5), CFrame.Angles(1.7, 0, 0))
		arm(pose, "L", CFrame.Angles(1.3, 0, 0.5), CFrame.Angles(1.7, 0, 0))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(-0.05, 0, 0)
	elseif name == "Rewind" then
		arm(pose, "R", CFrame.Angles(0.3, 0, 1.0), CFrame.Angles(0.4, 0, 0))
		arm(pose, "L", CFrame.Angles(0.3, 0, -1.0), CFrame.Angles(0.4, 0, 0))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(0, -e * 8, 0)
	elseif name == "Buff" then
		local k = math.clamp(e / 0.2, 0, 1)
		arm(pose, "R", CFrame.Angles(0, 0, 1.5 * k), CFrame.Angles(0, 0, 1.5 * k))
		arm(pose, "L", CFrame.Angles(0, 0, -1.5 * k), CFrame.Angles(0, 0, -1.5 * k))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(0.1 * k, 0, 0)
		pose.Neck = CFrame.Angles(0.2 * k, 0, 0)
	elseif name == "Block" then
		arm(pose, "R", CFrame.Angles(1.7, 0, -0.4), CFrame.Angles(1.4, 0, 0))
		arm(pose, "L", CFrame.Angles(1.7, 0, 0.4), CFrame.Angles(1.4, 0, 0))
		pose.Waist = CFrame.new(0, float, 0) * CFrame.Angles(-0.12, 0, 0)
		pose.Neck = CFrame.Angles(-0.15, 0, 0)
	end
end

local function animate(entry: Entry, dt: number, t: number, serverNow: number)
	local pose = idlePose(t, entry.Seed, entry.Scale)
	local e = serverNow - entry.PoseStart
	local active = entry.Pose ~= "Idle" and (entry.Pose == "Block" or e <= entry.Duration)
	if active then
		actionPose(entry, pose, math.max(0, e), t)
	end
	local alpha = 1 - math.exp(-(if active then 30 else 12) * dt)
	for name, target in pose do
		local m = Joints.Find(entry.Model, entry.Cache, name)
		if m then
			m.Transform = m.Transform:Lerp(target, alpha)
		end
	end
	for i = 1, 3 do
		local m = Joints.Find(entry.Model, entry.Cache, "Tail" .. i .. "Joint")
		if m then
			m.Transform = m.Transform:Lerp(CFrame.Angles(math.sin(t * 1.5 + i) * 0.15, math.sin(t + i * 0.8) * 0.25, 0), alpha)
		end
	end
	local tail4 = Joints.Find(entry.Model, entry.Cache, "Tail4Joint")
	if tail4 then
		tail4.Transform = tail4.Transform:Lerp(CFrame.Angles(0, math.sin(t + 3.2) * 0.3, 0), alpha)
	end
end

function StandAnimator.Init()
	task.spawn(function()
		local folder = workspace:WaitForChild("Stands", math.huge) :: Instance
		for _, child in folder:GetChildren() do
			add(child)
		end
		folder.ChildAdded:Connect(add)
		folder.ChildRemoved:Connect(remove)
	end)
	RunService.PreSimulation:Connect(function(dt: number)
		local t = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		local camPos = camera.CFrame.Position
		for model, entry in entries do
			if not model.Parent then
				remove(model)
				continue
			end
			if (entry.Root.Position - camPos).Magnitude < 300 then
				animate(entry, math.min(dt, 0.1), t, serverNow)
			end
		end
	end)
end

-- The Stand model a character has summoned, if it is streamed in.
function StandAnimator.StandOf(character: Model): Model?
	for model in entries do
		local owner = model:FindFirstChild("Owner")
		if owner and owner:IsA("ObjectValue") and owner.Value == character then
			return model
		end
	end
	return nil
end

return StandAnimator
