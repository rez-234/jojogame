--!strict
-- Enemy decision making: patrol, chase, attack and retreat, with leashing.
-- Works for foot soldiers, Stand users and bosses. Mounted riders use the
-- horse steering in RiderBrain below.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local StandData = require(ReplicatedStorage.Shared.StandData)
local HorseMotor = require(ReplicatedStorage.Shared.HorseMotor)
local Net = require(script.Parent.Net)
local Combatants = require(script.Parent.Combatants)
local Hitbox = require(script.Parent.Hitbox)
local CombatService = require(script.Parent.CombatService)
local Moves = require(script.Parent.Moves)

type Combatant = Combatants.Combatant

local NPCBrain = {}

export type Brain = {
	Home: Vector3,
	State: string, -- "Patrol", "Chase", "Retreat", "Return"
	Target: Combatant?,
	Moves: { string },
	Ranged: boolean,
	MeleeDamage: number,
	AggroRange: number,
	LeashRange: number,
	NextPatrol: number,
	PatrolPoint: Vector3?,
	NextAttack: number,
	NextMove: number,
	RetreatUntil: number,
	Retreated: boolean,
	MoveCooldownMult: number,
	Passive: boolean,
}

function NPCBrain.new(home: Vector3, moves: { string }, ranged: boolean, meleeDamage: number): Brain
	return {
		Home = home,
		State = "Patrol",
		Target = nil,
		Moves = moves,
		Ranged = ranged,
		MeleeDamage = meleeDamage,
		AggroRange = Config.NPC.AggroRange,
		LeashRange = Config.NPC.LeashRange,
		NextPatrol = 0,
		PatrolPoint = nil,
		NextAttack = 0,
		NextMove = os.clock() + math.random() * 2,
		RetreatUntil = 0,
		Retreated = false,
		MoveCooldownMult = 1.35,
		Passive = false,
	}
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Nearest player this NPC may attack.
function NPCBrain.FindTarget(c: Combatant, range: number, from: Vector3?): Combatant?
	local origin = from or c.Root.Position
	local best: Combatant? = nil
	local bestDist = range
	for _, player in Players:GetPlayers() do
		local pc = Combatants.ForPlayer(player)
		if pc and Hitbox.CanHarm(c, pc) then
			local d = (pc.Root.Position - origin).Magnitude
			if d < bestDist then
				best = pc
				bestDist = d
			end
		end
	end
	return best
end

local function validTarget(c: Combatant, brain: Brain, t: Combatant?): boolean
	if not t or not Combatants.IsAlive(t) or not Hitbox.CanHarm(c, t) then
		return false
	end
	if (t.Root.Position - brain.Home).Magnitude > brain.LeashRange then
		return false
	end
	return true
end

local function faceTowards(c: Combatant, point: Vector3)
	if c.Mounted or c.Root.Anchored then
		return
	end
	local p = c.Root.Position
	local dir = flat(point - p)
	if dir.Magnitude > 0.1 then
		c.Root.CFrame = CFrame.lookAt(p, p + dir)
	end
end

function NPCBrain.Melee(c: Combatant, target: Combatant, damage: number)
	c.PunchIndex = c.PunchIndex % 3 + 1
	local finisher = c.PunchIndex == 3
	Net.FX("Punch", { Model = c.Model, Index = c.PunchIndex, Stand = c.StandSummoned })
	CombatService.Damage(c, target, {
		Damage = damage,
		Stun = if finisher then Config.Combat.HeavyStun * 0.7 else Config.Combat.HitStun,
		Knockback = if finisher then 26 else 0,
		KnockDir = target.Root.Position - c.Root.Position,
		Source = "Punch",
	})
end

-- Range a move needs to be worth using.
local function moveReach(move: StandData.Move): number
	if move.Kind == "Projectile" then
		return math.min(move.Range or 60, 70)
	elseif move.Kind == "Blast" then
		return if (move.Range or 0) > 0 then (move.Range :: number) else (move.Radius or 10)
	elseif move.Kind == "Dash" or move.Kind == "Teleport" then
		return move.Distance or 30
	elseif move.Kind == "Pull" or move.Kind == "Line" then
		return move.Range or 30
	elseif move.Kind == "Heal" or move.Kind == "Buff" or move.Kind == "Counter" or move.Kind == "TimeStop" or move.Kind == "Erase" or move.Kind == "Rewind" then
		return 25
	end
	return (move.Range or 6) + 2
end

-- Tries to use one ready move against the target. Returns true if it did.
function NPCBrain.TryMove(c: Combatant, brain: Brain, target: Combatant, power: number?): boolean
	local now = os.clock()
	if now < brain.NextMove or #brain.Moves == 0 then
		return false
	end
	local dist = (target.Root.Position - c.Root.Position).Magnitude
	local options = {}
	for _, id in brain.Moves do
		local move = StandData.GetMove(id)
		if move and Combatants.Cooldown(c, id) <= 0 and dist <= moveReach(move) then
			if move.Kind == "Heal" or move.Kind == "Rewind" then
				if c.Humanoid.Health < c.Humanoid.MaxHealth * 0.6 then
					table.insert(options, move)
				end
			else
				table.insert(options, move)
			end
		end
	end
	if #options == 0 then
		return false
	end
	local move = options[math.random(1, #options)]
	local ctx = Moves.NPCContext(move, power)
	Combatants.SetCooldown(c, move.Id, move.Cooldown * brain.MoveCooldownMult)
	brain.NextMove = now + 1.2 + math.random() * 1.2
	faceTowards(c, target.Root.Position)
	local lead = target.Root.Position + target.Root.AssemblyLinearVelocity * math.clamp(dist / 160, 0, 0.6)
	Moves.Execute(c, move, lead, ctx)
	return true
end

-- One decision step for a foot NPC.
function NPCBrain.Think(c: Combatant, brain: Brain)
	if not Combatants.IsAlive(c) or Combatants.IsStunned(c) or Combatants.IsBusy(c) then
		return
	end
	local now = os.clock()
	local h = c.Humanoid
	local pos = c.Root.Position

	if brain.Passive then
		return
	end

	-- Leash home and heal.
	local fromHome = (pos - brain.Home).Magnitude
	if brain.State == "Return" then
		if fromHome < 8 then
			brain.State = "Patrol"
			h.Health = h.MaxHealth
			brain.Retreated = false
		else
			h:MoveTo(brain.Home)
			return
		end
	end
	if fromHome > brain.LeashRange then
		brain.State = "Return"
		brain.Target = nil
		h:MoveTo(brain.Home)
		return
	end

	if not validTarget(c, brain, brain.Target) then
		brain.Target = NPCBrain.FindTarget(c, brain.AggroRange)
	end
	local target = brain.Target

	-- Retreat once when badly hurt.
	if target and not brain.Retreated and h.Health < h.MaxHealth * Config.NPC.RetreatHealthFraction then
		brain.Retreated = true
		brain.RetreatUntil = now + Config.NPC.RetreatDuration
		brain.State = "Retreat"
	end
	if brain.State == "Retreat" then
		if now < brain.RetreatUntil and target then
			local away = flat(pos - target.Root.Position)
			if away.Magnitude < 0.1 then
				away = Vector3.new(1, 0, 0)
			end
			h:MoveTo(pos + away.Unit * 20)
			return
		end
		brain.State = "Chase"
	end

	if not target then
		brain.State = "Patrol"
		if now >= brain.NextPatrol or not brain.PatrolPoint then
			local a = math.random() * math.pi * 2
			local r = math.random() * Config.NPC.PatrolRadius
			brain.PatrolPoint = brain.Home + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			brain.NextPatrol = now + 4 + math.random() * 5
		end
		if brain.PatrolPoint then
			h:MoveTo(brain.PatrolPoint)
		end
		return
	end

	brain.State = "Chase"
	local tpos = target.Root.Position
	local dist = (tpos - pos).Magnitude
	if NPCBrain.TryMove(c, brain, target) then
		return
	end
	if brain.Ranged then
		if dist < 14 then
			h:MoveTo(pos + flat(pos - tpos).Unit * 10)
		elseif dist > 32 then
			h:MoveTo(tpos)
		else
			-- Strafe around the target.
			local side = flat(pos - tpos):Cross(Vector3.yAxis)
			if side.Magnitude > 0.1 then
				h:MoveTo(pos + side.Unit * (if math.random() < 0.5 then 6 else -6))
			end
		end
	else
		if dist > Config.NPC.AttackRange - 1 then
			h:MoveTo(tpos - flat(tpos - pos).Unit * 2.5)
		else
			h:MoveTo(pos)
		end
	end
	if dist <= Config.NPC.AttackRange and now >= brain.NextAttack then
		brain.NextAttack = now + 0.9 + math.random() * 0.4
		faceTowards(c, tpos)
		NPCBrain.Melee(c, target, brain.MeleeDamage)
	end
end

-- Steering for mounted NPCs: chase a target on horseback and shoot.
function NPCBrain.RiderControl(c: Combatant, brain: Brain, motor: HorseMotor.State, desiredSpeed: () -> number): HorseMotor.Input?
	if not Combatants.IsAlive(c) then
		return { Throttle = 0, Steer = 0, Gallop = false, Jump = false, TargetSpeed = 0 }
	end
	if Combatants.IsStunned(c) then
		return { Throttle = 0, Steer = 0, Gallop = false, Jump = false, TargetSpeed = motor.Speed * 0.9 }
	end
	local target = brain.Target
	if not target or not Combatants.IsAlive(target) then
		return { Throttle = 0, Steer = 0, Gallop = false, Jump = false, TargetSpeed = 0 }
	end
	local to = target.Root.Position - c.Root.Position
	local heading = flat(to)
	local dist = heading.Magnitude
	local speed = desiredSpeed()
	if dist < 18 then
		-- Ride alongside rather than through the target.
		local side = heading:Cross(Vector3.yAxis).Unit
		heading = target.Root.CFrame.LookVector + side * 0.4
		speed = math.max(target.Root.AssemblyLinearVelocity.Magnitude, motor.Stats.Trot)
	end
	return { Throttle = 0, Steer = 0, Gallop = true, Jump = false, TargetSpeed = speed, TargetHeading = heading }
end

return NPCBrain
