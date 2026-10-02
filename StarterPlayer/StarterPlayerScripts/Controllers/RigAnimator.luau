--!strict
-- Procedural animation for NPC rigs (bandits, bosses, rivals, townsfolk):
-- walk and run cycles from velocity, idle breathing and glances, a riding
-- pose for mounted NPCs, guard and stagger poses from combat attributes.
-- It also plays short punch swings on any character, players included, when
-- they punch without a Stand out.

local RunService = game:GetService("RunService")

local Joints = require(script.Parent.Joints)

local RigAnimator = {}

type Entry = {
	Model: Model,
	Root: BasePart,
	Humanoid: Humanoid?,
	Cache: Joints.Cache,
	Phase: number,
	Seed: number,
	Townsfolk: boolean,
}

type Swing = {
	Start: number,
	Duration: number,
	Index: number,
	Cache: Joints.Cache,
}

local entries: { [Model]: Entry } = {}
local swings: { [Model]: Swing } = {}
local camera = workspace.CurrentCamera

local function add(model: Instance)
	if not model:IsA("Model") or entries[model] then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	entries[model] = {
		Model = model,
		Root = root,
		Humanoid = model:FindFirstChildOfClass("Humanoid"),
		Cache = {},
		Phase = math.random(),
		Seed = math.random() * 20,
		Townsfolk = model:GetAttribute("Townsfolk") == true,
	}
end

local function remove(model: Instance)
	if model:IsA("Model") then
		entries[model] = nil
	end
end

local function watchFolder(name: string)
	task.spawn(function()
		local folder = workspace:WaitForChild(name, math.huge) :: Instance
		for _, child in folder:GetChildren() do
			add(child)
		end
		folder.ChildAdded:Connect(function(child)
			-- Parts stream in after the model itself; give them a frame.
			task.defer(add, child)
		end)
		folder.ChildRemoved:Connect(remove)
	end)
end

local function setJoint(entry: Entry, names: { [string]: string }, key: string, rot: CFrame, alpha: number)
	local name = names[key]
	if not name then
		return
	end
	local m = Joints.Find(entry.Model, entry.Cache, name)
	if m then
		Joints.Blend(m, rot, alpha)
	end
end

local function animate(entry: Entry, dt: number, t: number)
	local model = entry.Model
	local names = Joints.NamesFor(model)
	local alpha = 1 - math.exp(-14 * dt)
	if model:GetAttribute("Mounted") == true then
		Joints.RiderPose(model, entry.Cache, math.sin(t * 6 + entry.Seed))
		return
	end
	local humanoid = entry.Humanoid
	if humanoid and humanoid.Health <= 0 then
		return
	end
	local vel = entry.Root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local stride = math.clamp(speed / 16, 0, 1.2)
	if speed > 0.5 then
		entry.Phase = (entry.Phase + speed / 7 * dt) % 1
	end
	local swing = math.sin(entry.Phase * math.pi * 2)
	local breathe = math.sin(t * 1.6 + entry.Seed) * 0.04

	local hipAmp = 0.75 * stride
	local armAmp = 0.65 * stride
	local stunned = model:GetAttribute("Stunned") == true
	local blocking = model:GetAttribute("Blocking") == true

	if stunned then
		setJoint(entry, names, "Neck", CFrame.Angles(-0.45, math.sin(t * 3) * 0.2, 0), alpha)
		setJoint(entry, names, "LeftShoulder", CFrame.Angles(-0.2, 0, -0.35), alpha)
		setJoint(entry, names, "RightShoulder", CFrame.Angles(-0.2, 0, 0.35), alpha)
	elseif blocking then
		setJoint(entry, names, "Neck", CFrame.Angles(-0.1, 0, 0), alpha)
		setJoint(entry, names, "LeftShoulder", CFrame.Angles(1.6, 0, 0.5), alpha)
		setJoint(entry, names, "RightShoulder", CFrame.Angles(1.6, 0, -0.5), alpha)
	else
		local glance = if entry.Townsfolk or speed < 1 then math.sin(t * 0.3 + entry.Seed) * 0.5 else 0
		setJoint(entry, names, "Neck", CFrame.Angles(breathe * 0.5, glance, 0), alpha)
		-- Townsfolk talk with their hands now and then.
		local gesture = if entry.Townsfolk then math.max(0, math.sin(t * 0.5 + entry.Seed)) ^ 4 else 0
		setJoint(entry, names, "LeftShoulder", CFrame.Angles(-swing * armAmp + breathe, 0, -0.05 - breathe), alpha)
		setJoint(entry, names, "RightShoulder", CFrame.Angles(swing * armAmp + breathe + gesture * 1.1, 0, 0.05 + breathe - gesture * 0.3), alpha)
	end
	setJoint(entry, names, "LeftHip", CFrame.Angles(swing * hipAmp, 0, 0), alpha)
	setJoint(entry, names, "RightHip", CFrame.Angles(-swing * hipAmp, 0, 0), alpha)
	setJoint(entry, names, "LeftKnee", CFrame.Angles(-math.max(0, swing) * stride, 0, 0), alpha)
	setJoint(entry, names, "RightKnee", CFrame.Angles(-math.max(0, -swing) * stride, 0, 0), alpha)
end

-- A punch swing on top of whatever else animates the arm this frame.
local function applySwing(model: Model, swing: Swing, now: number): boolean
	local k = (now - swing.Start) / swing.Duration
	if k >= 1 then
		return false
	end
	local ext = math.sin(math.clamp(k, 0, 1) * math.pi)
	local names = Joints.NamesFor(model)
	local right = swing.Index % 2 == 1
	local shoulderName = if right then names.RightShoulder else names.LeftShoulder
	local elbowName = if right then names.RightElbow else names.LeftElbow
	local shoulder = shoulderName and Joints.Find(model, swing.Cache, shoulderName)
	if shoulder then
		local spread = if right then -0.25 else 0.25
		-- The finisher (fourth hit) is an uppercut.
		local lift = if swing.Index % 4 == 0 then 0.5 else 0
		Joints.SetLocal(shoulder, CFrame.Angles((1.55 + lift) * ext, 0, spread * ext))
	end
	local elbow = elbowName and Joints.Find(model, swing.Cache, elbowName)
	if elbow then
		Joints.SetLocal(elbow, CFrame.Angles(0.9 * (1 - ext), 0, 0))
	end
	return true
end

function RigAnimator.Punch(model: Model, index: number?)
	local existing = swings[model]
	swings[model] = {
		Start = os.clock(),
		Duration = 0.26,
		Index = index or 1,
		Cache = if existing then existing.Cache else {},
	}
end

function RigAnimator.Init()
	watchFolder("NPCs")
	watchFolder("Townsfolk")
	RunService.PreSimulation:Connect(function(dt: number)
		local t = os.clock()
		local camPos = camera.CFrame.Position
		local step = math.min(dt, 0.1)
		for model, entry in entries do
			if not model.Parent or not entry.Root.Parent then
				entries[model] = nil
				continue
			end
			if (entry.Root.Position - camPos).Magnitude < 220 then
				animate(entry, step, t)
			end
		end
		for model, swing in swings do
			if not model.Parent or not applySwing(model, swing, t) then
				swings[model] = nil
			end
		end
	end)
end

return RigAnimator
