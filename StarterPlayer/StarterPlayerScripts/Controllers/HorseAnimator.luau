--!strict
-- Procedural animation for every horse near the camera: gait leg cycles,
-- body bob and rocking, head nod, tail sway, breathing, ear flicks, grazing,
-- rearing, jumping, landing squash, hoof dust and hoof sounds. It also poses
-- riders sitting in a saddle. Horse joints are built world aligned, so a
-- Transform of CFrame.Angles(a, 0, 0) on a hip swings that leg forward.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Joints = require(script.Parent.Joints)
local HorseController = require(script.Parent.HorseController)

local HorseAnimator = {}

type Gait = {
	Stride: number,
	Duty: number,
	Amp: number,
	Knee: number,
	Bob: number,
	BobFreq: number,
	Pitch: number,
	Nod: number,
	NodFreq: number,
	Neck: number,
	Offsets: { [string]: number },
	Volume: number,
	Dust: number,
}

local GAITS: { [string]: Gait } = {
	Idle = { Stride = 10, Duty = 1, Amp = 0, Knee = 0, Bob = 0, BobFreq = 2, Pitch = 0, Nod = 0, NodFreq = 1, Neck = 0, Offsets = { FL = 0, FR = 0, BL = 0, BR = 0 }, Volume = 0, Dust = 0 },
	Walk = { Stride = 11, Duty = 0.62, Amp = 0.32, Knee = 0.55, Bob = 0.05, BobFreq = 2, Pitch = 0.015, Nod = 0.07, NodFreq = 2, Neck = -0.04, Offsets = { BL = 0, FL = 0.25, BR = 0.5, FR = 0.75 }, Volume = 0.22, Dust = 0 },
	Trot = { Stride = 22, Duty = 0.5, Amp = 0.42, Knee = 0.9, Bob = 0.16, BobFreq = 2, Pitch = 0.01, Nod = 0.03, NodFreq = 2, Neck = 0.05, Offsets = { FL = 0, BR = 0, FR = 0.5, BL = 0.5 }, Volume = 0.35, Dust = 1 },
	Canter = { Stride = 34, Duty = 0.45, Amp = 0.58, Knee = 1.05, Bob = 0.22, BobFreq = 1, Pitch = 0.07, Nod = 0.12, NodFreq = 1, Neck = -0.05, Offsets = { BL = 0, BR = 0.3, FL = 0.3, FR = 0.55 }, Volume = 0.45, Dust = 2 },
	Gallop = { Stride = 46, Duty = 0.38, Amp = 0.72, Knee = 1.25, Bob = 0.3, BobFreq = 1, Pitch = 0.1, Nod = 0.16, NodFreq = 1, Neck = -0.18, Offsets = { BL = 0, BR = 0.1, FL = 0.42, FR = 0.52 }, Volume = 0.6, Dust = 4 },
}
local GAIT_ORDER = { "Idle", "Walk", "Trot", "Canter", "Gallop" }
local LEGS = { "FL", "FR", "BL", "BR" }
local MAX_DISTANCE = 260
local NEAR_DISTANCE = 120
local SOUND_DISTANCE = 90

type Entry = {
	Model: Model,
	Root: BasePart,
	Scale: number,
	Cache: Joints.Cache,
	Phase: number,
	Gait: string,
	Blend: { Amp: number, Knee: number, Bob: number, Pitch: number, Nod: number, Neck: number },
	LegPhase: { [string]: number },
	Hooves: { [string]: BasePart },
	PrevVY: number,
	Air: number,
	Squash: number,
	Exertion: number,
	Graze: number,
	EarNext: number,
	EarStart: number,
	EarSide: number,
	SwishNext: number,
	SwishStart: number,
	Seed: number,
	Accum: number,
	Hoof: Sound?,
	Land: Sound?,
	LastStep: number,
}

local entries: { [Model]: Entry } = {}
local riderCaches: { [Model]: Joints.Cache } = setmetatable({}, { __mode = "k" }) :: any
local camera = workspace.CurrentCamera

local function speedThresholds(scale: number): (number, number, number, number)
	local h = Config.Horse
	return 1.5, (h.WalkSpeed + h.TrotSpeed) / 2 * scale, (h.TrotSpeed + h.CanterSpeed) / 2 * scale, (h.CanterSpeed + h.GallopSpeed) / 2 * scale
end

local function gaitForSpeed(speed: number, scale: number): string
	local idle, walk, trot, canter = speedThresholds(scale)
	if speed < idle then
		return "Idle"
	elseif speed < walk then
		return "Walk"
	elseif speed < trot then
		return "Trot"
	elseif speed < canter then
		return "Canter"
	end
	return "Gallop"
end

local function add(model: Instance)
	if not model:IsA("Model") or entries[model] then
		return
	end
	local root = model.PrimaryPart or model:FindFirstChild("Root") :: BasePart?
	if not root then
		return
	end
	local scaleAttr = model:GetAttribute("Scale")
	local hooves: { [string]: BasePart } = {}
	for _, leg in LEGS do
		local hoof = model:FindFirstChild(leg .. "Hoof")
		if hoof and hoof:IsA("BasePart") then
			hooves[leg] = hoof
		end
	end
	local seed = math.random() * 100
	entries[model] = {
		Model = model,
		Root = root,
		Scale = if type(scaleAttr) == "number" then scaleAttr else 1,
		Cache = {},
		Phase = math.random(),
		Gait = "Idle",
		Blend = { Amp = 0, Knee = 0, Bob = 0, Pitch = 0, Nod = 0, Neck = 0 },
		LegPhase = { FL = 0, FR = 0, BL = 0, BR = 0 },
		Hooves = hooves,
		PrevVY = 0,
		Air = 0,
		Squash = 0,
		Exertion = 0,
		Graze = 0,
		EarNext = os.clock() + 1 + math.random() * 4,
		EarStart = -10,
		EarSide = 1,
		SwishNext = os.clock() + 2 + math.random() * 5,
		SwishStart = -10,
		Seed = seed,
		Accum = 0,
		Hoof = root:FindFirstChild("Hoof") :: Sound?,
		Land = nil,
		LastStep = 0,
	}
end

local function remove(model: Instance)
	if model:IsA("Model") then
		entries[model] = nil
	end
end

-- Stance moves the hoof back along the ground, swing lifts it forward.
local function legAngles(p: number, duty: number, amp: number, knee: number): (number, number)
	if duty >= 1 then
		return 0, 0
	end
	if p < duty then
		local s = p / duty
		return amp * (1 - 2 * s), 0
	end
	local s = (p - duty) / (1 - duty)
	local e = s * s * (3 - 2 * s)
	return amp * (-1 + 2 * e), math.sin(math.pi * s) * knee
end

local function set(entry: Entry, name: string, target: CFrame, alpha: number)
	local m = Joints.Find(entry.Model, entry.Cache, name)
	if m then
		m.Transform = m.Transform:Lerp(target, alpha)
	end
end

local function damp(current: number, target: number, rate: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-rate * dt))
end

local function footfall(entry: Entry, leg: string, gait: Gait, dist: number, gaitName: string)
	local hoof = entry.Hooves[leg]
	if hoof and gait.Dust > 0 and dist < NEAR_DISTANCE then
		local attachment = hoof:FindFirstChild("Dust")
		local emitter = attachment and attachment:FindFirstChild("Dust")
		if emitter and emitter:IsA("ParticleEmitter") then
			emitter:Emit(gait.Dust)
		end
	end
	local sound = entry.Hoof
	if sound and dist < SOUND_DISTANCE and gait.Volume > 0 then
		local now = os.clock()
		-- Gallop footfalls come fast; thin them so the clip is not cut off constantly.
		local minGap = if gaitName == "Gallop" then 0.09 else 0.05
		if now - entry.LastStep >= minGap then
			entry.LastStep = now
			sound.Volume = gait.Volume * (1 - dist / SOUND_DISTANCE * 0.6)
			sound.PlaybackSpeed = 0.85 + math.random() * 0.25
			sound.TimePosition = 0
			sound:Play()
		end
	end
end

local function landed(entry: Entry, impact: number, dist: number)
	entry.Squash = math.clamp(impact / 60, 0.25, 1)
	if dist < NEAR_DISTANCE then
		for _, hoof in entry.Hooves do
			local attachment = hoof:FindFirstChild("Dust")
			local emitter = attachment and attachment:FindFirstChild("Dust")
			if emitter and emitter:IsA("ParticleEmitter") then
				emitter:Emit(5)
			end
		end
	end
	if dist < SOUND_DISTANCE then
		local sound = entry.Land
		if not sound then
			local s = Instance.new("Sound")
			s.Name = "LandThud"
			s.SoundId = Config.Sounds.Land
			s.RollOffMaxDistance = 120
			s.Parent = entry.Root
			entry.Land = s
			sound = s
		end
		local snd = sound :: Sound
		snd.Volume = 0.4 + entry.Squash * 0.4
		snd.PlaybackSpeed = 0.7
		snd:Play()
	end
end

local function animate(entry: Entry, dt: number, now: number, serverNow: number, dist: number)
	local root = entry.Root
	local scale = entry.Scale
	local vel = root.AssemblyLinearVelocity
	local speed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	local vy = vel.Y
	if root.Anchored then
		speed = 0
		vy = 0
	end

	-- Gait: the local rider's motor knows best, others go by speed.
	local motor = HorseController.Motor
	local gaitName: string
	local grounded: boolean
	if motor and motor.Model == entry.Model then
		gaitName = if motor.Speed < 1 then "Idle" else motor.Gait
		grounded = motor.Grounded or motor.Swimming
		vy = motor.VY
	else
		gaitName = gaitForSpeed(speed, scale)
		grounded = vy > -10 and vy < 8
	end
	local gait = GAITS[gaitName] or GAITS.Idle
	entry.Gait = gaitName

	-- Blend gait parameters so changes of gait are not a snap.
	local b = entry.Blend
	b.Amp = damp(b.Amp, gait.Amp, 6, dt)
	b.Knee = damp(b.Knee, gait.Knee, 6, dt)
	b.Bob = damp(b.Bob, gait.Bob, 5, dt)
	b.Pitch = damp(b.Pitch, gait.Pitch, 5, dt)
	b.Nod = damp(b.Nod, gait.Nod, 5, dt)
	b.Neck = damp(b.Neck, gait.Neck, 4, dt)

	if gaitName ~= "Idle" then
		local freq = math.max(0.6, speed / (gait.Stride * scale))
		entry.Phase = (entry.Phase + freq * dt) % 1
	end
	local phase = entry.Phase
	local tau = math.pi * 2

	-- Exertion builds while galloping and drives heavier breathing at rest.
	local exertTarget = if gaitName == "Gallop" then 1 elseif gaitName == "Canter" then 0.5 else 0
	entry.Exertion = damp(entry.Exertion, exertTarget, if exertTarget > entry.Exertion then 0.25 else 0.12, dt)

	-- Air and landing.
	if not grounded then
		entry.Air = damp(entry.Air, 1, 10, dt)
	else
		entry.Air = damp(entry.Air, 0, 12, dt)
	end
	if entry.PrevVY < -18 and vy > -4 then
		landed(entry, -entry.PrevVY, dist)
	end
	entry.PrevVY = vy
	entry.Squash = damp(entry.Squash, 0, 7, dt)

	-- Grazing.
	local graze = entry.Model:GetAttribute("Graze") == true and speed < 1
	entry.Graze = damp(entry.Graze, if graze then 1 else 0, 2.5, dt)

	-- Rearing.
	local rear = 0
	local rearAt = entry.Model:GetAttribute("RearAt")
	if type(rearAt) == "number" then
		local t = serverNow - rearAt
		if t >= 0 and t < 1.6 then
			if t < 0.35 then
				rear = math.sin(t / 0.35 * math.pi / 2)
			elseif t < 1.1 then
				rear = 1
			else
				rear = math.cos((t - 1.1) / 0.5 * math.pi / 2)
			end
		end
	end

	local alpha = 1 - math.exp(-20 * dt)
	local air = entry.Air
	local squash = entry.Squash

	-- Legs.
	for _, leg in LEGS do
		local front = leg == "FL" or leg == "FR"
		local p = (phase + (gait.Offsets[leg] or 0)) % 1
		local prev = entry.LegPhase[leg]
		if gaitName ~= "Idle" and grounded and p < prev then
			footfall(entry, leg, gait, dist, gaitName)
		end
		entry.LegPhase[leg] = p
		local hip, knee = legAngles(p, gait.Duty, b.Amp, b.Knee)
		-- Jump pose: forelegs tucked, hind legs trailing.
		if front then
			hip = hip * (1 - air) + 0.7 * air
			knee = knee * (1 - air) + 1.5 * air
		else
			hip = hip * (1 - air) - 0.6 * air
			knee = knee * (1 - air) + 0.2 * air
		end
		-- Landing squash bends every knee.
		knee += squash * (if front then 0.5 else 0.35)
		-- Rearing: forelegs paw the air, hind legs stay planted.
		if rear > 0 then
			if front then
				local paw = math.sin(now * 9 + (if leg == "FL" then 0 else math.pi)) * 0.3
				hip = hip * (1 - rear) + (0.9 + paw) * rear
				knee = knee * (1 - rear) + (1.4 - paw) * rear
			else
				hip = hip * (1 - rear) - 0.75 * rear
				knee = knee * (1 - rear) + 0.15 * rear
			end
		end
		-- Grazing: forelegs splay a touch.
		if front then
			hip -= entry.Graze * 0.12
		end
		set(entry, leg .. "Hip", CFrame.Angles(hip, 0, 0), alpha)
		set(entry, leg .. "Knee", CFrame.Angles(if front then -knee else knee * 0.8, 0, 0), alpha)
	end

	-- Body: bob, rocking, breathing, squash and rear.
	local breathRate = 1.5 + entry.Exertion * 2.6
	local breath = math.sin(now * breathRate + entry.Seed) * (0.02 + entry.Exertion * 0.05)
	local bobY = b.Bob * math.sin(tau * phase * gait.BobFreq)
	local pitch = b.Pitch * math.sin(tau * phase + math.pi / 2) * (1 - air)
	local body = CFrame.new(0, (bobY * (1 - air) + breath - squash * 0.45) * scale, 0) * CFrame.Angles(pitch - air * 0.08, 0, 0)
	if rear > 0 then
		-- Pivot around the hind hooves so they stay on the ground.
		local pivot = Vector3.new(0, -Config.Horse.HipHeight * scale, 1.95 * scale)
		body = body * CFrame.new(pivot) * CFrame.Angles(0.8 * rear, 0, 0) * CFrame.new(-pivot)
	end
	set(entry, "TorsoJoint", body, alpha)

	-- Neck and head: nod with the gait, graze, look around, lift when rearing.
	local nod = b.Nod * math.sin(tau * phase * gait.NodFreq + 0.6)
	local idleLook = math.sin(now * 0.23 + entry.Seed) * 0.22 * (1 - math.min(1, speed / 10))
	local chew = math.sin(now * 5) * 0.05 * entry.Graze
	local neckPitch = b.Neck + nod - entry.Graze * 1.25 + rear * 0.45 - air * 0.12 + breath * 0.5
	set(entry, "NeckJoint", CFrame.Angles(neckPitch, idleLook * 0.5, 0), alpha)
	set(entry, "HeadJoint", CFrame.Angles(-entry.Graze * 0.45 + chew + rear * 0.2, idleLook, 0), alpha)

	-- Ears: random flicks, pinned back at a gallop.
	if now >= entry.EarNext then
		entry.EarStart = now
		entry.EarSide = if math.random() < 0.5 then -1 else 1
		entry.EarNext = now + 2 + math.random() * 5
	end
	local flickT = (now - entry.EarStart) / 0.3
	local flick = if flickT >= 0 and flickT < 1 then math.sin(flickT * math.pi) * 0.65 else 0
	local pinned = if gaitName == "Gallop" then 0.45 else 0
	for _, side in { -1, 1 } do
		local f = if side == entry.EarSide then flick else 0
		set(entry, if side < 0 then "EarLJoint" else "EarRJoint", CFrame.Angles(pinned + f * 0.6, 0, side * f * 0.5), alpha)
	end

	-- Tail: lifts with speed, sways, and swishes at flies when idle.
	if now >= entry.SwishNext then
		entry.SwishStart = now
		entry.SwishNext = now + 3 + math.random() * 6
	end
	local swishT = (now - entry.SwishStart) / 1.1
	local swish = if swishT >= 0 and swishT < 1 then math.sin(swishT * math.pi) * 0.5 else 0
	local lift = math.clamp(speed / (Config.Horse.GallopSpeed * scale), 0, 1) * 0.6 + air * 0.2
	for i = 1, 4 do
		local sway = math.sin(now * (1.3 + swish * 6) + i * 0.7 + entry.Seed) * (0.08 + swish)
		local flow = math.sin(tau * phase + i * 0.9) * 0.08 * lift
		set(entry, "Tail" .. i .. "Joint", CFrame.Angles(-lift * (if i == 1 then 1 else 0.35) + flow, sway, 0), alpha)
	end
end

-- Pose every rider sitting in a saddle, bouncing with the horse's gait.
local function poseRiders()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local seat = humanoid and humanoid.SeatPart
		if character and seat and seat.Name == "Saddle" and seat.Parent then
			local horse = seat.Parent :: Instance
			local entry = if horse:IsA("Model") then entries[horse] else nil
			local bounce = 0
			local lean = 0
			if entry then
				bounce = math.sin(math.pi * 2 * entry.Phase * (GAITS[entry.Gait] or GAITS.Idle).BobFreq)
				lean = if entry.Gait == "Gallop" then 0.25 elseif entry.Gait == "Canter" then 0.12 else 0
			end
			local cache = riderCaches[character]
			if not cache then
				cache = {}
				riderCaches[character] = cache
			end
			Joints.RiderPose(character, cache, bounce)
			local names = Joints.NamesFor(character)
			local waistName = names.Waist
			if waistName then
				local waist = Joints.Find(character, cache, waistName)
				if waist then
					Joints.SetLocal(waist, CFrame.Angles(-lean + bounce * 0.03, 0, 0))
				end
			end
		end
	end
end

function HorseAnimator.Init()
	for _, model in CollectionService:GetTagged("SBR_Horse") do
		add(model)
	end
	CollectionService:GetInstanceAddedSignal("SBR_Horse"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("SBR_Horse"):Connect(remove)

	local frame = 0
	RunService.PreSimulation:Connect(function(dt: number)
		frame += 1
		local now = os.clock()
		local serverNow = workspace:GetServerTimeNow()
		local camPos = camera.CFrame.Position
		for model, entry in entries do
			if not model.Parent or not entry.Root.Parent then
				entries[model] = nil
				continue
			end
			local dist = (entry.Root.Position - camPos).Magnitude
			if dist > MAX_DISTANCE then
				continue
			end
			entry.Accum += dt
			-- Far horses update every other frame.
			if dist > NEAR_DISTANCE and frame % 2 == 0 then
				continue
			end
			local step = math.min(entry.Accum, 0.1)
			entry.Accum = 0
			animate(entry, step, now, serverNow, dist)
		end
		poseRiders()
	end)
end

-- Gait of a horse as last animated (used by the horse HUD for remote horses).
function HorseAnimator.GaitOf(model: Model): string?
	local entry = entries[model]
	return if entry then entry.Gait else nil
end

HorseAnimator.GaitOrder = GAIT_ORDER

return HorseAnimator
