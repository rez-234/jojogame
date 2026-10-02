--!strict
-- Horse locomotion shared by the rider's client (player horses) and the
-- server (rivals, outlaw mounts, wild herds). It drives the LinearVelocity and
-- AlignOrientation made by HorseBuilder: gait speeds with acceleration,
-- stamina, steering that tightens at speed, ground following from hoof
-- raycasts, slope limits, jumping with gravity and swimming.

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)
local Progression = require(script.Parent.Progression)

local HorseMotor = {}

export type Input = {
	Throttle: number,
	Steer: number,
	Gallop: boolean,
	Jump: boolean,
	-- 1 walk, 2 trot, 3 canter: the cruising gait while W is held.
	Cruise: number?,
	-- AI control: when set these replace throttle and steer.
	TargetSpeed: number?,
	TargetHeading: Vector3?,
}

export type State = {
	Model: Model,
	Root: BasePart,
	Velocity: LinearVelocity,
	Align: AlignOrientation,
	Stats: Progression.HorseStats,
	Speed: number,
	Yaw: number,
	Pitch: number,
	Roll: number,
	VY: number,
	Grounded: boolean,
	AirTime: number,
	Stamina: number,
	Exhausted: boolean,
	Gait: string,
	Hip: number,
	Scale: number,
	Params: RaycastParams,
	Swimming: boolean,
	LandedAt: number,
	UseStamina: boolean,
	SpeedLimit: number?,
}

local H = Config.Horse

function HorseMotor.RayParams(): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	local list: { Instance } = { workspace.Terrain }
	local map = workspace:FindFirstChild("Map")
	if map then
		table.insert(list, map)
	end
	params.FilterDescendantsInstances = list
	params.IgnoreWater = false
	return params
end

function HorseMotor.new(model: Model, stats: Progression.HorseStats, useStamina: boolean): State
	local root = model.PrimaryPart :: BasePart
	local scaleAttr = model:GetAttribute("Scale")
	local scale = if type(scaleAttr) == "number" then scaleAttr else 1
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	return {
		Model = model,
		Root = root,
		Velocity = root:FindFirstChild("Velocity") :: LinearVelocity,
		Align = root:FindFirstChild("Align") :: AlignOrientation,
		Stats = stats,
		Speed = 0,
		Yaw = yaw,
		Pitch = 0,
		Roll = 0,
		VY = 0,
		Grounded = true,
		AirTime = 0,
		Stamina = stats.StaminaMax,
		Exhausted = false,
		Gait = "Idle",
		Hip = (H.HipHeight + 0.1) * scale,
		Scale = scale,
		Params = HorseMotor.RayParams(),
		Swimming = false,
		LandedAt = 0,
		UseStamina = useStamina,
		SpeedLimit = nil,
	}
end

function HorseMotor.Enable(state: State, on: boolean)
	local root = state.Root
	if on then
		local mass = root.AssemblyMass
		state.Velocity.MaxForce = mass * workspace.Gravity * 8 + 20000
		state.Align.MaxTorque = mass * 4000 + 50000
		state.Align.Responsiveness = 30
		state.Velocity.VectorVelocity = Vector3.zero
	else
		state.Velocity.MaxForce = 0
		state.Align.MaxTorque = 0
		state.Velocity.VectorVelocity = Vector3.zero
	end
end

-- Ground height at a point under the horse, and whether it is water.
local function probe(state: State, at: Vector3): (number?, boolean)
	local origin = at + Vector3.new(0, state.Hip + 3, 0)
	local hit = workspace:Raycast(origin, Vector3.new(0, -(state.Hip + 60), 0), state.Params)
	if not hit then
		return nil, false
	end
	return hit.Position.Y, hit.Material == Enum.Material.Water
end

function HorseMotor.GaitFor(stats: Progression.HorseStats, speed: number): string
	local s = math.abs(speed)
	if s < 1 then
		return "Idle"
	elseif speed < 0 then
		return "Walk"
	elseif s <= stats.Walk * 1.15 then
		return "Walk"
	elseif s <= stats.Trot * 1.1 then
		return "Trot"
	elseif s <= stats.Canter * 1.05 then
		return "Canter"
	end
	return "Gallop"
end

function HorseMotor.Step(state: State, dt: number, input: Input)
	dt = math.min(dt, 0.1)
	local stats = state.Stats
	local root = state.Root
	local pos = root.Position
	local yawCF = CFrame.Angles(0, state.Yaw, 0)
	local forward = yawCF.LookVector
	local half = 2.0 * state.Scale

	-- Ground probes at the front and back hooves and the middle.
	local frontY, frontWet = probe(state, pos + forward * half)
	local backY, backWet = probe(state, pos - forward * half)
	local midY, midWet = probe(state, pos)
	local aheadY = probe(state, pos + forward * (half + 3 + math.max(0, state.Speed) * 0.12))
	local groundY = midY or frontY or backY
	state.Swimming = midWet or (frontWet and backWet)

	-- Target speed.
	local allowedMax: number
	if state.Exhausted then
		allowedMax = stats.Trot
	elseif input.Gallop then
		allowedMax = stats.Gallop
	else
		allowedMax = stats.Canter
	end
	if state.Swimming then
		allowedMax = math.min(allowedMax, stats.Trot * 0.6)
	end
	if state.SpeedLimit then
		allowedMax = math.min(allowedMax, state.SpeedLimit)
	end

	local target = 0
	local rate = H.CoastDeceleration
	if input.TargetSpeed then
		target = math.clamp(input.TargetSpeed, -H.ReverseSpeed, allowedMax)
		rate = if target > state.Speed then stats.Acceleration else H.BrakeDeceleration * 0.6
	elseif input.Throttle > 0.1 then
		local cruise = input.Cruise or 3
		local cruiseSpeed = if cruise <= 1 then stats.Walk elseif cruise == 2 then stats.Trot else stats.Canter
		local want = if input.Gallop and not state.Exhausted then stats.Gallop else cruiseSpeed
		target = math.min(want, allowedMax) * math.clamp(input.Throttle, 0, 1)
		rate = if target > state.Speed then stats.Acceleration else H.CoastDeceleration
	elseif input.Throttle < -0.1 then
		if state.Speed > 1.5 then
			target = 0
			rate = H.BrakeDeceleration
		else
			target = -H.ReverseSpeed
			rate = stats.Acceleration
		end
	end
	if not state.Grounded then
		-- Little control in the air.
		rate *= 0.15
	end
	if state.Speed < target then
		state.Speed = math.min(target, state.Speed + rate * dt)
	else
		state.Speed = math.max(target, state.Speed - rate * dt)
	end

	-- Slope limit: refuse to climb walls.
	if aheadY and groundY and state.Speed > 0 then
		local rise = aheadY - groundY
		local run = half + 3 + math.max(0, state.Speed) * 0.12 - 0
		local slope = math.deg(math.atan2(rise, run))
		if slope > H.MaxClimbSlope then
			state.Speed = math.min(state.Speed, 3)
		end
	end

	-- Blocked by a wall or building: bleed off speed.
	local actual = root.AssemblyLinearVelocity
	local actualForward = actual:Dot(forward)
	if state.Speed > 8 and actualForward < state.Speed * 0.45 and state.Grounded then
		state.Speed = Util.lerp(state.Speed, math.max(actualForward, 0), math.min(1, dt * 6))
	end

	-- Steering, slower at high speed.
	local speedFrac = math.clamp(math.abs(state.Speed) / math.max(stats.Gallop, 1), 0, 1)
	local turnRate = stats.TurnRate * Util.lerp(1, H.HighSpeedTurnFactor, speedFrac)
	local steer = 0
	if input.TargetHeading then
		local h = input.TargetHeading
		if Vector3.new(h.X, 0, h.Z).Magnitude > 1e-3 then
			local want = math.atan2(-h.X, -h.Z)
			local diff = (want - state.Yaw + math.pi) % (2 * math.pi) - math.pi
			local maxTurn = turnRate * 1.4 * dt
			state.Yaw += math.clamp(diff, -maxTurn, maxTurn)
			steer = math.clamp(diff * 2, -1, 1)
		end
	else
		steer = math.clamp(input.Steer, -1, 1)
		state.Yaw -= steer * turnRate * dt
	end

	-- Stamina and gait.
	local gait = HorseMotor.GaitFor(stats, state.Speed)
	state.Gait = gait
	if state.UseStamina then
		local delta = 0
		if gait == "Idle" then
			delta = H.IdleRegen
		elseif gait == "Walk" then
			delta = H.WalkRegen
		elseif gait == "Trot" then
			delta = H.TrotRegen
		elseif gait == "Canter" then
			delta = -H.CanterDrain
		else
			delta = -H.GallopDrain
		end
		if state.Swimming then
			delta = math.min(delta, -H.CanterDrain)
		end
		state.Stamina = math.clamp(state.Stamina + delta * dt, 0, stats.StaminaMax)
		if state.Stamina <= 0 then
			state.Exhausted = true
		elseif state.Exhausted and state.Stamina >= H.ExhaustedThreshold then
			state.Exhausted = false
		end
	end

	-- Vertical motion: follow the ground, jump and fall.
	local targetY = if groundY then groundY + state.Hip else nil
	if state.Swimming and groundY then
		targetY = groundY + state.Hip * 0.45
	end
	if targetY then
		local above = pos.Y - targetY
		if state.Grounded then
			if above > 2.5 + state.Hip * 0.3 then
				state.Grounded = false
				state.AirTime = 0
				state.VY = math.min(state.VY, 0)
			else
				state.VY = math.clamp(-above * 14, -70, 55)
			end
		end
		if input.Jump and state.Grounded and not state.Swimming then
			local cost = if state.UseStamina then 8 else 0
			if state.Stamina >= cost then
				state.Stamina -= cost
				state.Grounded = false
				state.AirTime = 0
				state.VY = stats.JumpPower
			end
		end
		if not state.Grounded then
			state.AirTime += dt
			state.VY -= workspace.Gravity * dt
			if state.VY <= 0 and pos.Y + state.VY * dt <= targetY + 0.1 then
				state.Grounded = true
				if state.AirTime > 0.25 then
					state.LandedAt = os.clock()
				end
				state.VY = 0
			end
		end
	else
		state.Grounded = false
		state.AirTime += dt
		state.VY -= workspace.Gravity * dt
	end
	state.VY = math.max(state.VY, -150)

	-- Body pitch from the hooves and a slight lean into turns.
	local wantPitch = 0
	if frontY and backY and state.Grounded then
		wantPitch = math.atan2(frontY - backY, half * 2)
	elseif not state.Grounded then
		wantPitch = math.clamp(state.VY / 120, -0.35, 0.35)
	end
	state.Pitch = Util.damp(state.Pitch, math.clamp(wantPitch, -0.6, 0.6), 8, dt)
	state.Roll = Util.damp(state.Roll, steer * speedFrac * 0.12, 6, dt)

	local horizontal = forward * state.Speed
	state.Velocity.VectorVelocity = Vector3.new(horizontal.X, state.VY, horizontal.Z)
	state.Align.CFrame = yawCF * CFrame.Angles(state.Pitch, 0, state.Roll)
end

-- Places a horse on the ground at a position facing a direction.
function HorseMotor.PlaceOnGround(model: Model, position: Vector3, facing: Vector3, params: RaycastParams?)
	local p = params or HorseMotor.RayParams()
	local scaleAttr = model:GetAttribute("Scale")
	local scale = if type(scaleAttr) == "number" then scaleAttr else 1
	local hip = (H.HipHeight + 0.1) * scale
	local hit = workspace:Raycast(position + Vector3.new(0, 40, 0), Vector3.new(0, -200, 0), p)
	local y = if hit then hit.Position.Y + hip else position.Y + hip
	local flat = Vector3.new(facing.X, 0, facing.Z)
	if flat.Magnitude < 1e-3 then
		flat = Vector3.new(0, 0, -1)
	end
	local at = Vector3.new(position.X, y, position.Z)
	model:PivotTo(CFrame.lookAt(at, at + flat.Unit))
end

return HorseMotor
