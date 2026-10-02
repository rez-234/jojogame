--!strict
-- Server authoritative combat: the damage pipeline (counters, blocking, Stand
-- durability, crits, mounted damage split), stun with a combo limiter,
-- knockback, damage over time effects, punches, blocking, dodging, time stop,
-- erasing and rewinding. Every client input is validated here.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local StandData = require(ReplicatedStorage.Shared.StandData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Net = require(script.Parent.Net)
local Signals = require(script.Parent.Signals)
local Combatants = require(script.Parent.Combatants)
local Hitbox = require(script.Parent.Hitbox)
local MasteryService = require(script.Parent.MasteryService)

type Combatant = Combatants.Combatant

local CombatService = {}

export type HitInfo = {
	Damage: number,
	Stun: number?,
	Knockback: number?,
	KnockDir: Vector3?,
	GuardBreak: boolean?,
	Unblockable: boolean?,
	Effect: string?,
	EffectPower: number?,
	EffectDuration: number?,
	MoveId: string?,
	Family: string?,
	Source: string?,
	Color: Color3?,
	NoCounter: boolean?,
	IsDot: boolean?,
	Ranged: boolean?,
}

-- Hooks other services fill in to avoid circular requires.
CombatService.Hooks = {
	-- (rider, damage, attacker) called when a mounted fighter is hit.
	MountedHit = nil :: ((Combatant, number, Combatant?) -> ())?,
	-- (fighter) called when a Stand breaks so StandService can unsummon it.
	StandBreak = nil :: ((Combatant) -> ())?,
	-- (fighter) called when a time stop or stun should end a mount.
	Dismount = nil :: ((Combatant) -> ())?,
}

local KILL_CREDIT_WINDOW = 15
local HISTORY_SECONDS = 8
local HISTORY_RATE = 0.2

local function stand(c: Combatant): StandData.Stand?
	return StandData.Get(c.StandId)
end

-- Stun with the combo limiter: total stun inside the window is capped, then
-- the target gets a short window of stun immunity.
function CombatService.Stun(c: Combatant, seconds: number, force: boolean?)
	if seconds <= 0 or c.Dead then
		return
	end
	local now = os.clock()
	if not force then
		if now < c.ComboImmuneUntil then
			return
		end
		if now - c.ComboStart > Config.Combat.ComboWindow then
			c.ComboStart = now
			c.ComboStun = 0
		end
		local allowed = Config.Combat.MaxComboStun - c.ComboStun
		if seconds >= allowed then
			seconds = math.max(0, allowed)
			c.ComboImmuneUntil = now + seconds + Config.Combat.ComboImmunity
			c.ComboStun = 0
			c.ComboStart = now
			Net.FX("ComboBreak", { Model = c.Model })
		else
			c.ComboStun += seconds
		end
	end
	if seconds <= 0 then
		return
	end
	c.StunUntil = math.max(c.StunUntil, now + seconds)
	if c.Blocking then
		c.Blocking = false
	end
	Combatants.ApplyMovement(c)
end

function CombatService.Knockback(c: Combatant, velocity: Vector3)
	if velocity.Magnitude < 1 or c.Dead then
		return
	end
	if c.Player then
		Net.FXTo(c.Player, "Knockback", { V = velocity, T = Config.Combat.KnockbackDecay })
		return
	end
	if c.Mounted or c.Root.Anchored then
		return
	end
	local root = c.Root
	local att = root:FindFirstChild("RootAttachment") :: Attachment?
	if not att then
		local a = Instance.new("Attachment")
		a.Name = "RootAttachment"
		a.Parent = root
		att = a
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "Knockback"
	lv.Attachment0 = att
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.VectorVelocity = velocity + Vector3.new(0, math.min(velocity.Magnitude * 0.25, 20), 0)
	lv.MaxForce = root.AssemblyMass * 3000
	lv.Parent = root
	task.delay(Config.Combat.KnockbackDecay, function()
		lv:Destroy()
	end)
end

function CombatService.Heal(c: Combatant, amount: number)
	if c.Dead or amount <= 0 then
		return
	end
	local h = c.Humanoid
	local before = h.Health
	h.Health = math.min(h.MaxHealth, h.Health + amount)
	if h.Health > before then
		Net.FX("Heal", { Model = c.Model, Amount = math.floor(h.Health - before) })
	end
end

function CombatService.HealOverTime(c: Combatant, total: number, duration: number)
	local steps = math.max(1, math.floor(duration / 0.5))
	task.spawn(function()
		for _ = 1, steps do
			if c.Dead then
				return
			end
			CombatService.Heal(c, total / steps)
			task.wait(0.5)
		end
	end)
end

function CombatService.BreakStand(c: Combatant)
	local now = os.clock()
	c.StandDurability = 0
	c.StandBrokenUntil = now + Config.Stand.BreakCooldown
	c.Blocking = false
	CombatService.Stun(c, Config.Stand.BreakStun, true)
	Net.FX("StandBreak", { Model = c.Model })
	local hook = CombatService.Hooks.StandBreak
	if hook then
		hook(c)
	end
end

local function applyEffect(attacker: Combatant?, target: Combatant, name: string, power: number, duration: number)
	local now = os.clock()
	local existing = target.Effects[name]
	local p = power
	if attacker and name ~= "Slow" and name ~= "Silence" then
		p *= attacker.DamageMult
	end
	if existing and now < existing.Until then
		existing.Until = math.max(existing.Until, now + duration)
		existing.Power = math.max(existing.Power, p)
		existing.Source = attacker
	else
		target.Effects[name] = { Until = now + duration, Power = p, NextTick = now + 1, Source = attacker }
	end
	Net.FX("Effect", { Model = target.Model, Name = name, Duration = duration })
	Combatants.ApplyMovement(target)
end

local function inFront(target: Combatant, fromPos: Vector3): boolean
	local toAttacker = fromPos - target.Root.Position
	toAttacker = Vector3.new(toAttacker.X, 0, toAttacker.Z)
	if toAttacker.Magnitude < 0.1 then
		return true
	end
	local look = Combatants.Look(target)
	local cos = look:Dot(toAttacker.Unit)
	return cos >= math.cos(math.rad(Config.Combat.BlockAngle / 2))
end

-- The full damage pipeline. Returns damage dealt and "Hit", "Blocked",
-- "Countered" or "Miss".
function CombatService.Damage(attacker: Combatant?, target: Combatant, hit: HitInfo): (number, string)
	if not Hitbox.CanHarm(attacker, target) then
		return 0, "Miss"
	end
	local now = os.clock()
	if now < target.IFrameUntil then
		Net.FX("Dodged", { Model = target.Model })
		return 0, "Miss"
	end

	-- Counter stance turns the hit around.
	local counter = target.Counter
	if counter and now < counter.Until and attacker and not hit.NoCounter and not hit.IsDot then
		target.Counter = nil
		Net.FX("Counter", { Model = target.Model, Target = attacker.Model, Color = counter.Move.Color })
		local move = counter.Move
		local dir = attacker.Root.Position - target.Root.Position
		CombatService.Damage(target, attacker, {
			Damage = move.Damage * counter.Mult,
			Stun = move.Stun,
			Unblockable = true,
			NoCounter = true,
			Knockback = 30,
			KnockDir = dir,
			MoveId = move.Id,
			Family = target.Family,
			Source = move.Name,
			Color = move.Color,
		})
		return 0, "Countered"
	end

	local damage = hit.Damage
	local result = "Hit"
	local fromPos = if attacker then attacker.Root.Position else target.Root.Position + (hit.KnockDir or Vector3.zero) * -5

	-- Blocking.
	if target.Blocking and not hit.Unblockable and not hit.IsDot and inFront(target, fromPos) then
		if hit.GuardBreak then
			target.Blocking = false
			damage *= 0.5
			Net.FX("GuardBreak", { Model = target.Model })
			CombatService.Stun(target, Config.Combat.GuardBreakStun, true)
		else
			local blocked = damage * (1 - Config.Combat.BlockDamageMult)
			damage *= Config.Combat.BlockDamageMult
			result = "Blocked"
			local cost = blocked * Config.Combat.BlockDurabilityCost
			if target.StandSummoned then
				target.StandDurability -= cost
				if target.StandDurability <= 0 then
					CombatService.BreakStand(target)
				end
			else
				target.Stamina -= cost
				if target.Stamina <= 0 then
					target.Stamina = 0
					target.Blocking = false
					Net.FX("GuardBreak", { Model = target.Model })
					CombatService.Stun(target, Config.Combat.GuardBreakStun, true)
				end
			end
		end
	end

	-- Critical hits from Stand precision.
	local crit = false
	if attacker and result == "Hit" and hit.Family and not hit.IsDot then
		local s = stand(attacker)
		if s then
			local chance = Progression.GradeValue(Config.Stand.PrecisionGrades, s.Stats.Precision)
			if math.random() < chance then
				crit = true
				damage *= Config.Stand.CritMultiplier
			end
		end
	end

	-- Riders share damage with their horse.
	if target.Mounted and not hit.IsDot then
		local hook = CombatService.Hooks.MountedHit
		if hook then
			hook(target, damage, attacker)
		end
		damage *= Config.Combat.MountedDamageTakenMult
	end

	damage = math.max(0, damage)
	local before = target.Humanoid.Health
	target.Humanoid:TakeDamage(damage)
	local dealt = before - target.Humanoid.Health
	if dealt <= 0 and damage > 0 and target.Model:FindFirstChildOfClass("ForceField") then
		return 0, "Miss"
	end

	if attacker then
		target.LastAttacker = attacker
		target.LastAttackTime = now
		target.LastHitMove = hit.Source
		target.Contributors[attacker] = (target.Contributors[attacker] or 0) + dealt
		attacker.Data.LastCombat = now
	end
	target.Data.LastCombat = now

	if result == "Hit" then
		if hit.Stun and hit.Stun > 0 then
			CombatService.Stun(target, hit.Stun)
		end
		if hit.Knockback and hit.Knockback > 0 then
			local dir = hit.KnockDir or (target.Root.Position - fromPos)
			dir = Vector3.new(dir.X, 0, dir.Z)
			if dir.Magnitude > 1e-3 then
				CombatService.Knockback(target, dir.Unit * hit.Knockback)
			end
		end
		if hit.Effect and hit.EffectDuration then
			applyEffect(attacker, target, hit.Effect, hit.EffectPower or 1, hit.EffectDuration)
		end
	end

	if dealt >= Config.Combat.DamageNumberThreshold or result ~= "Hit" then
		Net.FX("Hit", {
			Model = target.Model,
			P = target.Root.Position,
			D = math.floor(dealt + 0.5),
			B = result == "Blocked",
			C = crit,
			Col = hit.Color,
			Dot = hit.IsDot,
		})
	end
	Signals.Hit:Fire(attacker, target, hit, dealt, result)
	return dealt, result
end

-- Freezes everyone near the user except the user.
function CombatService.TimeStop(user: Combatant, radius: number, duration: number): number
	local now = os.clock()
	local caught = 0
	for _, c in Combatants.All() do
		if c ~= user and Combatants.IsAlive(c) and (c.Root.Position - user.Root.Position).Magnitude <= radius then
			-- Holders of their own time stop move halve the effect.
			local resist = false
			local s = stand(c)
			if s then
				for _, id in s.Moves do
					local m = StandData.GetMove(id)
					if m and m.Kind == "TimeStop" then
						resist = true
					end
				end
			end
			local d = if resist then duration * 0.5 else duration
			c.TimeStoppedUntil = math.max(c.TimeStoppedUntil, now + d)
			c.Blocking = false
			if not c.Root.Anchored then
				c.Root.Anchored = true
				c.Data.TimeStopAnchored = true
			end
			Combatants.ApplyMovement(c)
			if Hitbox.CanHarm(user, c) then
				caught += 1
			end
		end
	end
	Net.FX("TimeStop", { Model = user.Model, Center = user.Root.Position, Radius = radius, Duration = duration })
	return caught
end

function CombatService.Erase(user: Combatant, duration: number)
	local now = os.clock()
	user.ErasedUntil = now + duration
	user.IFrameUntil = math.max(user.IFrameUntil, now + duration)
	Net.FX("Erase", { Model = user.Model, Duration = duration })
end

function CombatService.Rewind(user: Combatant, seconds: number, healFraction: number)
	local target = os.clock() - seconds
	local best: Combatants.HistoryEntry? = nil
	for _, entry in user.History do
		if not best or math.abs(entry.Time - target) < math.abs(best.Time - target) then
			best = entry
		end
	end
	local from = user.Root.Position
	if best then
		local h = user.Humanoid
		if best.Health > h.Health then
			h.Health = math.min(h.MaxHealth, h.Health + (best.Health - h.Health) * healFraction)
		end
		if not user.Mounted then
			user.Model:PivotTo(best.CFrame)
		end
	end
	user.StunUntil = 0
	user.Effects = {}
	user.IFrameUntil = os.clock() + 0.4
	Combatants.ApplyMovement(user)
	Net.FX("Rewind", { Model = user.Model, From = from, To = user.Root.Position })
end

-- Credits a kill when a fighter dies.
function CombatService.Track(c: Combatant)
	c.Humanoid.Died:Connect(function()
		if c.Dead then
			return
		end
		c.Dead = true
		c.Blocking = false
		local killer: Combatant? = nil
		if c.LastAttacker and os.clock() - c.LastAttackTime < KILL_CREDIT_WINDOW then
			killer = c.LastAttacker
		end
		Signals.Killed:Fire(killer, c)
	end)
end

-- Player punches. The aim point is only used for direction.
local function onPunch(player: Player, aim: any)
	local c = Combatants.ForPlayer(player)
	if not c or not Combatants.IsAlive(c) or Combatants.IsStunned(c) or Combatants.IsBusy(c) or c.Blocking then
		return
	end
	local now = os.clock()
	local s = stand(c)
	local standUp = c.StandSummoned and s ~= nil
	local speedGrade = if standUp and s then Progression.GradeValue(Config.Stand.SpeedGrades, s.Stats.Speed) else 1
	local tier = if standUp then MasteryService.Tier(player, c.Family, StandData.PunchMoveId) else MasteryService.Tier(nil, nil, StandData.PunchMoveId)
	local cooldown = Config.Combat.PunchCooldown / speedGrade * (1 - tier.Speed)
	if now - c.LastPunch < cooldown * 0.85 then
		return
	end
	if now - c.LastPunch > Config.Combat.PunchComboReset then
		c.PunchIndex = 0
	end
	c.PunchIndex = c.PunchIndex % Config.Combat.PunchComboLength + 1
	c.LastPunch = now
	local finisher = c.PunchIndex == Config.Combat.PunchComboLength

	local dir = Combatants.Look(c)
	if Net.IsVector(aim) then
		local flat = Vector3.new((aim :: Vector3).X - c.Root.Position.X, 0, (aim :: Vector3).Z - c.Root.Position.Z)
		if flat.Magnitude > 0.5 and flat.Magnitude < Config.Combat.MaxAimDistance then
			dir = flat.Unit
		end
	end
	local range = Config.Combat.PunchRange + (if standUp then 2.5 else 0)
	local damage = Config.Combat.PunchDamage * c.DamageMult
	local color: Color3? = nil
	if standUp and s then
		damage *= Progression.GradeValue(Config.Stand.PowerGrades, s.Stats.Power) * (1 + tier.Damage)
		color = s.PunchColor
		if tier.Index == #Config.Mastery.Tiers then
			color = Config.Mastery.PerfectedColor
		end
	end
	if finisher then
		damage *= 1.6
	end
	Net.FX("Punch", { Model = c.Model, Index = c.PunchIndex, Stand = standUp, Color = color })
	if c.StandModel then
		c.StandModel:SetAttribute("Pose", "Punch")
		c.StandModel:SetAttribute("PoseAt", workspace:GetServerTimeNow())
	end
	local targets = Hitbox.Forward(c.Root.Position - dir * 0.5, dir, range + 0.5, 5, 6, c)
	Hitbox.SortByDistance(targets, c.Root.Position)
	for i, t in targets do
		if i > 3 then
			break
		end
		CombatService.Damage(c, t, {
			Damage = damage,
			Stun = if finisher then Config.Combat.HeavyStun else Config.Combat.HitStun,
			Knockback = if finisher then Config.Combat.FinisherKnockback else 0,
			KnockDir = dir,
			MoveId = StandData.PunchMoveId,
			Family = if standUp then c.Family else nil,
			Source = "Punch",
			Color = color,
		})
	end
end

local function onBlock(player: Player, on: any)
	local c = Combatants.ForPlayer(player)
	if not c or not Combatants.IsAlive(c) then
		return
	end
	local want = on == true
	if want and (Combatants.IsStunned(c) or Combatants.IsBusy(c) or c.Mounted) then
		return
	end
	if c.Blocking == want then
		return
	end
	c.Blocking = want
	c.BlockStarted = os.clock()
	if c.StandModel then
		c.StandModel:SetAttribute("Pose", if want then "Block" else "Idle")
		c.StandModel:SetAttribute("PoseAt", workspace:GetServerTimeNow())
	end
	Combatants.ApplyMovement(c)
end

local function onDodge(player: Player, direction: any)
	local c = Combatants.ForPlayer(player)
	if not c or not Combatants.IsAlive(c) or Combatants.IsStunned(c) or c.Mounted then
		return
	end
	if Combatants.Cooldown(c, "Dodge") > 0 or c.Stamina < Config.Combat.DodgeStaminaCost then
		return
	end
	local dir = Combatants.Look(c)
	if Net.IsVector(direction, 2) then
		local d = Vector3.new((direction :: Vector3).X, 0, (direction :: Vector3).Z)
		if d.Magnitude > 0.1 then
			dir = d.Unit
		end
	end
	c.Stamina -= Config.Combat.DodgeStaminaCost
	c.Blocking = false
	Combatants.SetCooldown(c, "Dodge", Config.Combat.DodgeCooldown)
	c.IFrameUntil = os.clock() + Config.Combat.DodgeIFrames
	Net.FXTo(player, "Dash", { Dir = dir, Distance = Config.Combat.DodgeDistance, Duration = 0.22 })
	Net.FX("Dodge", { Model = c.Model, Dir = dir })
	Combatants.ApplyMovement(c)
end

local function setAttr(inst: Instance, name: string, value: any)
	if inst:GetAttribute(name) ~= value then
		inst:SetAttribute(name, value)
	end
end

-- Effects, regeneration, movement and replicated status, ten times a second.
local function tick(dt: number)
	local now = os.clock()
	-- Snapshot, since damage can spawn or remove fighters mid loop.
	for _, c in table.clone(Combatants.All()) do
		if c.Dead then
			continue
		end
		-- Damage over time and bombs.
		for name, e in c.Effects do
			if now >= e.Until then
				c.Effects[name] = nil
				if name == "Bomb" then
					local attacker = e.Source
					Net.FX("Explosion", { P = c.Root.Position, Radius = 8 })
					for _, t in Hitbox.Sphere(c.Root.Position, 8, attacker) do
						CombatService.Damage(attacker, t, {
							Damage = e.Power,
							Stun = 0.6,
							Knockback = 35,
							KnockDir = t.Root.Position - c.Root.Position,
							Unblockable = true,
							NoCounter = true,
							Source = "Bomb",
						})
					end
					if attacker ~= c and Hitbox.CanHarm(attacker, c) then
						-- The bomb carrier always takes the blast.
						CombatService.Damage(attacker, c, { Damage = e.Power, Stun = 0.6, Unblockable = true, NoCounter = true, Source = "Bomb" })
					end
				end
			elseif (name == "Burn" or name == "Bleed" or name == "Spin") and now >= e.NextTick then
				e.NextTick = now + 1
				CombatService.Damage(e.Source, c, { Damage = e.Power, Unblockable = true, NoCounter = true, IsDot = true, Source = name })
			end
		end
		-- Time stop ends.
		if c.Data.TimeStopAnchored and now >= c.TimeStoppedUntil then
			c.Data.TimeStopAnchored = nil
			c.Root.Anchored = false
		end
		-- Counter stance expiry.
		if c.Counter and now >= c.Counter.Until then
			c.Counter = nil
		end
		-- Stamina and Stand durability.
		if not c.Blocking then
			c.Stamina = math.min(c.StaminaMax, c.Stamina + Config.Combat.PlayerStaminaRegen * dt)
			if now >= c.StandBrokenUntil then
				c.StandDurability = math.min(c.StandMaxDurability, c.StandDurability + Config.Stand.DurabilityRegen * dt)
			end
		end
		-- History for rewinds.
		if now - (c.Data.LastHistory or 0) >= HISTORY_RATE then
			c.Data.LastHistory = now
			table.insert(c.History, { Time = now, CFrame = c.Root.CFrame, Health = c.Humanoid.Health })
			while #c.History > 0 and now - c.History[1].Time > HISTORY_SECONDS do
				table.remove(c.History, 1)
			end
		end
		Combatants.ApplyMovement(c)
		local m = c.Model
		setAttr(m, "Stunned", Combatants.IsStunned(c))
		setAttr(m, "Blocking", c.Blocking)
		setAttr(m, "TimeStopped", now < c.TimeStoppedUntil)
		if c.Player then
			setAttr(m, "Stamina", math.floor(c.Stamina))
			setAttr(m, "StaminaMax", math.floor(c.StaminaMax))
			setAttr(m, "StandDurability", math.floor(math.max(0, c.StandDurability)))
			setAttr(m, "StandMaxDurability", math.floor(c.StandMaxDurability))
			setAttr(m, "StandBroken", now < c.StandBrokenUntil)
			setAttr(m, "Silenced", Combatants.HasEffect(c, "Silence"))
		end
	end
end

function CombatService.Init()
	Net.OnAction("Punch", onPunch)
	Net.OnAction("Block", onBlock)
	Net.OnAction("Dodge", onDodge)
	Players.PlayerRemoving:Connect(function(player)
		local c = Combatants.ForPlayer(player)
		if c then
			Combatants.Unregister(c.Model)
		end
	end)
end

function CombatService.Start()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc >= 0.1 then
			local step = acc
			acc = 0
			tick(step)
		end
	end)
end

return CombatService
