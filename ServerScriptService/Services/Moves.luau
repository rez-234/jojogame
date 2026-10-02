--!strict
-- Runs Stand moves on the server, one handler per move kind. Both players and
-- NPCs use this module; mastery only applies when the context has a family
-- and the user is a player.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local StandData = require(ReplicatedStorage.Shared.StandData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Net = require(script.Parent.Net)
local Signals = require(script.Parent.Signals)
local Combatants = require(script.Parent.Combatants)
local Hitbox = require(script.Parent.Hitbox)
local CombatService = require(script.Parent.CombatService)
local Projectiles = require(script.Parent.Projectiles)
local MasteryService = require(script.Parent.MasteryService)

type Combatant = Combatants.Combatant
type Move = StandData.Move

local Moves = {}

export type Context = {
	Family: string?,
	Tier: Progression.TierInfo,
	-- Damage multiplier on top of the user's own DamageMult.
	Power: number,
	Range: number,
	Speed: number,
	Color: Color3,
}

local IN_COMBAT = 8

function Moves.NPCContext(move: Move, power: number?): Context
	return {
		Family = nil,
		Tier = Progression.MasteryTier(0),
		Power = power or 1,
		Range = 1,
		Speed = 1,
		Color = move.Color,
	}
end

local function inCombat(user: Combatant): boolean
	return os.clock() - (user.Data.LastCombat or 0) < IN_COMBAT
end

local function recordUse(user: Combatant, move: Move, ctx: Context)
	if user.Player and ctx.Family then
		MasteryService.RecordUse(user.Player, ctx.Family, move.Id)
	end
end

local function aimDirection(user: Combatant, aim: Vector3?): Vector3
	if aim then
		local flat = Vector3.new(aim.X - user.Root.Position.X, 0, aim.Z - user.Root.Position.Z)
		if flat.Magnitude > 0.5 then
			return flat.Unit
		end
	end
	return Combatants.Look(user)
end

-- Turns NPCs toward the attack (players face by their own controls).
local function face(user: Combatant, dir: Vector3)
	if user.IsNPC and not user.Mounted and not user.Root.Anchored then
		local p = user.Root.Position
		user.Root.CFrame = CFrame.lookAt(p, p + dir)
	end
end

local function pose(user: Combatant, name: string, duration: number)
	local stand = user.StandModel
	if stand then
		stand:SetAttribute("Pose", name)
		stand:SetAttribute("PoseAt", workspace:GetServerTimeNow())
		stand:SetAttribute("PoseDuration", duration)
	end
end

local function busy(user: Combatant, seconds: number, speedMult: number)
	user.BusyUntil = math.max(user.BusyUntil, os.clock() + seconds)
	user.BusySpeed = speedMult
	Combatants.ApplyMovement(user)
end

local function interrupted(user: Combatant): boolean
	return not Combatants.IsAlive(user) or os.clock() < user.StunUntil or os.clock() < user.TimeStoppedUntil
end

local function hitInfo(user: Combatant, move: Move, ctx: Context, mult: number?): CombatService.HitInfo
	return {
		Damage = move.Damage * ctx.Power * user.DamageMult * (mult or 1),
		Stun = move.Stun,
		Knockback = move.Knockback,
		GuardBreak = move.GuardBreak,
		Unblockable = move.Unblockable,
		Effect = move.Effect,
		EffectPower = move.EffectPower,
		EffectDuration = move.EffectDuration,
		MoveId = move.Id,
		Family = ctx.Family,
		Source = move.Name,
		Color = ctx.Color,
	}
end

local function windupTime(move: Move, ctx: Context, default: number): number
	return (move.Windup or default) * (1 - ctx.Tier.Speed) / ctx.Speed
end

local Handlers: { [string]: (Combatant, Move, Vector3?, Context) -> () } = {}

Handlers.Barrage = function(user, move, aim, ctx)
	local hits = (move.Hits or 10) + ctx.Tier.ExtraHits
	local interval = (move.Interval or 0.1) * (1 - ctx.Tier.Speed) / ctx.Speed
	local duration = hits * interval
	local dir = aimDirection(user, aim)
	face(user, dir)
	busy(user, duration, 0.35)
	pose(user, "Barrage", duration)
	Net.FX("Barrage", { Model = user.Model, Duration = duration, Color = ctx.Color })
	local range = (move.Range or 6) * ctx.Range
	local width = move.Width or 6
	for i = 1, hits do
		if interrupted(user) then
			pose(user, "Idle", 0)
			Net.FX("BarrageEnd", { Model = user.Model })
			user.BusyUntil = 0
			Combatants.ApplyMovement(user)
			return
		end
		local last = i == hits
		local info = hitInfo(user, move, ctx)
		if last then
			info.Knockback = 28
			info.KnockDir = dir
			info.Stun = (move.Stun or 0.25) + 0.3
		else
			info.Effect = if i % 4 == 0 then move.Effect else nil
		end
		for _, t in Hitbox.Forward(user.Root.Position, dir, range, width, 6, user) do
			CombatService.Damage(user, t, info)
		end
		task.wait(interval)
	end
	pose(user, "Idle", 0)
end

Handlers.Heavy = function(user, move, aim, ctx)
	local dir = aimDirection(user, aim)
	face(user, dir)
	local windup = windupTime(move, ctx, 0.4)
	busy(user, windup + 0.25, 0.2)
	pose(user, "Heavy", windup + 0.35)
	Net.FX("Windup", { Model = user.Model, T = windup, Color = ctx.Color })
	task.wait(windup)
	if interrupted(user) then
		return
	end
	local range = (move.Range or 7) * ctx.Range
	local width = move.Width or 5
	local center = user.Root.Position + dir * (range / 2)
	Net.FX("Heavy", { Model = user.Model, P = center, Dir = dir, Range = range, Color = ctx.Color })
	local targets = Hitbox.Forward(user.Root.Position - dir * 0.5, dir, range + 0.5, width, 6, user)
	for _, t in targets do
		local info = hitInfo(user, move, ctx)
		info.KnockDir = dir
		local dealt, result = CombatService.Damage(user, t, info)
		if move.Heal and dealt > 0 and result == "Hit" then
			CombatService.Heal(user, move.Heal * ctx.Power)
		end
	end
end

Handlers.Line = function(user, move, aim, ctx)
	local dir = aimDirection(user, aim)
	face(user, dir)
	local windup = windupTime(move, ctx, 0.3)
	busy(user, windup + 0.2, 0.2)
	pose(user, "Point", windup + 0.4)
	Net.FX("Windup", { Model = user.Model, T = windup, Color = ctx.Color })
	task.wait(windup)
	if interrupted(user) then
		return
	end
	local range = (move.Range or 20) * ctx.Range
	local from = user.Root.Position + Vector3.new(0, 1, 0)
	local to = Hitbox.ClampPath(from, dir, range, 0)
	local length = (to - from).Magnitude
	Net.FX("Line", { From = from, To = to, Width = move.Width or 2.5, Color = ctx.Color })
	for _, t in Hitbox.Forward(user.Root.Position, dir, length, move.Width or 2.5, 5, user) do
		local info = hitInfo(user, move, ctx)
		info.KnockDir = dir
		CombatService.Damage(user, t, info)
	end
end

Handlers.Projectile = function(user, move, aim, ctx)
	local count = (move.Count or 1)
	if count > 1 then
		count += math.floor(ctx.Tier.ExtraHits / 2)
	end
	local base: Vector3
	if aim then
		local from = user.Root.Position + Vector3.new(0, 1.5, 0)
		local to = aim - from
		base = if to.Magnitude > 1 then to.Unit else Combatants.Look(user)
		-- Keep shots roughly level so they do not dive into the ground.
		base = Vector3.new(base.X, math.clamp(base.Y, -0.35, 0.35), base.Z).Unit
	else
		base = Combatants.Look(user)
	end
	face(user, Vector3.new(base.X, 0, base.Z))
	local windup = windupTime(move, ctx, 0.15)
	busy(user, windup + 0.1 + count * 0.05, 0.6)
	pose(user, "Point", windup + 0.3)
	Net.FX("Windup", { Model = user.Model, T = windup, Color = ctx.Color })
	task.wait(windup)
	if interrupted(user) then
		return
	end
	local spread = math.rad(move.Spread or 0)
	local speed = (move.Speed or 150) * (1 + ctx.Tier.Speed)
	local range = (move.Range or 100) * ctx.Range
	for k = 1, count do
		local offset = if count > 1 then spread * ((k - 1) / (count - 1) - 0.5) else 0
		local dir = (CFrame.fromAxisAngle(Vector3.yAxis, offset) * base)
		local origin = user.Root.Position + Vector3.new(0, 1.5, 0) + Vector3.new(dir.X, 0, dir.Z).Unit * 2
		local info = hitInfo(user, move, ctx)
		info.Ranged = true
		info.KnockDir = dir
		Projectiles.Fire({
			Owner = user,
			Origin = origin,
			Direction = dir,
			Speed = speed,
			Range = range,
			Radius = move.Radius or 1,
			Homing = move.Homing,
			Shape = move.Shape,
			Color = ctx.Color,
			OnHit = function(target)
				CombatService.Damage(user, target, info)
			end,
		})
		if count > 1 and move.Spread and move.Spread < 8 then
			task.wait(0.06)
		end
	end
end

Handlers.Blast = function(user, move, aim, ctx)
	local range = (move.Range or 0) * ctx.Range
	local center = user.Root.Position
	if range > 0 and aim then
		local to = Vector3.new(aim.X - center.X, 0, aim.Z - center.Z)
		if to.Magnitude > range then
			to = to.Unit * range
		end
		center += to
	end
	local ground = Hitbox.GroundBelow(center + Vector3.new(0, 20, 0), 80)
	if ground then
		center = ground
	end
	local radius = move.Radius or 10
	local delay = (move.Delay or 0.5) * (1 - ctx.Tier.Speed)
	face(user, aimDirection(user, center))
	busy(user, math.min(delay, 0.6), 0.4)
	pose(user, "Point", 0.6)
	Net.FX("Blast", { P = center, Radius = radius, Delay = delay, Sh = move.Shape or "Explosion", Color = ctx.Color, Model = user.Model })
	task.wait(delay)
	if not Combatants.IsAlive(user) then
		return
	end
	Net.FX("BlastHit", { P = center, Radius = radius, Sh = move.Shape or "Explosion", Color = ctx.Color })
	for _, t in Hitbox.Sphere(center + Vector3.new(0, 2, 0), radius, user) do
		local info = hitInfo(user, move, ctx)
		info.KnockDir = t.Root.Position - center
		CombatService.Damage(user, t, info)
	end
end

Handlers.Dash = function(user, move, aim, ctx)
	if user.Mounted then
		return
	end
	local dir = aimDirection(user, aim)
	face(user, dir)
	local start = user.Root.Position
	local distance = (move.Distance or 30) * ctx.Range
	local finish = Hitbox.ClampPath(start, dir, distance, 2.5)
	local length = (finish - start).Magnitude
	local duration = 0.28
	busy(user, duration + 0.1, 1)
	pose(user, "Dash", duration + 0.2)
	user.IFrameUntil = math.max(user.IFrameUntil, os.clock() + 0.15)
	Net.FX("DashTrail", { Model = user.Model, From = start, To = finish, Color = ctx.Color })
	if user.Player then
		Net.FXTo(user.Player, "Dash", { Dir = dir, Distance = length, Duration = duration })
	else
		local steps = 7
		for k = 1, steps do
			if not Combatants.IsAlive(user) then
				return
			end
			local p = start:Lerp(finish, k / steps)
			user.Root.CFrame = CFrame.lookAt(p, p + dir)
			task.wait(duration / steps)
		end
	end
	if length < 1 then
		return
	end
	local mid = (start + finish) / 2
	local cf = CFrame.lookAt(mid, finish)
	local targets = Hitbox.Box(cf, Vector3.new(move.Width or 5, 6, length + 3), user)
	for _, t in targets do
		local side = (t.Root.Position - mid)
		local info = hitInfo(user, move, ctx)
		info.KnockDir = Vector3.new(side.X, 0, side.Z) + dir * 2
		CombatService.Damage(user, t, info)
	end
end

Handlers.Pull = function(user, move, aim, ctx)
	local dir = aimDirection(user, aim)
	face(user, dir)
	local windup = windupTime(move, ctx, 0.2)
	busy(user, windup + 0.3, 0.3)
	pose(user, "Point", windup + 0.4)
	task.wait(windup)
	if interrupted(user) then
		return
	end
	local range = (move.Range or 40) * ctx.Range
	local from = user.Root.Position
	local targets = Hitbox.Forward(from, dir, range, move.Width or 4, 6, user)
	Hitbox.SortByDistance(targets, from)
	local target = targets[1]
	local reach = if target then target.Root.Position else Hitbox.ClampPath(from, dir, range, 0)
	Net.FX("Pull", { From = from, To = reach, Color = ctx.Color, Model = user.Model })
	if not target then
		return
	end
	local info = hitInfo(user, move, ctx)
	info.Knockback = 0
	local _, result = CombatService.Damage(user, target, info)
	if result == "Hit" and target.Mounted then
		-- Ropes and hooks drag riders out of the saddle.
		local dismount = CombatService.Hooks.Dismount
		if dismount then
			dismount(target)
		end
		return
	end
	if result == "Hit" and not target.Mounted then
		local dest = user.Root.Position + dir * 4
		local delta = dest - target.Root.Position
		local flat = Vector3.new(delta.X, 0, delta.Z)
		CombatService.Knockback(target, flat / Config.Combat.KnockbackDecay * 0.8)
	end
end

Handlers.Heal = function(user, move, _aim, ctx)
	local amount = (move.Heal or 30) * (1 + ctx.Tier.Damage)
	local radius = move.Radius or 20
	busy(user, 0.4, 0.5)
	pose(user, "Heal", 0.8)
	Net.FX("HealPulse", { P = user.Root.Position, Radius = radius, Color = ctx.Color })
	local healed = false
	for _, c in Combatants.All() do
		if Combatants.IsAlive(c) and (c.Root.Position - user.Root.Position).Magnitude <= radius then
			local friendly = c == user or (c.IsNPC == user.IsNPC and not Hitbox.CanHarm(user, c))
			if friendly and c.Humanoid.Health < c.Humanoid.MaxHealth then
				CombatService.Heal(c, amount)
				healed = true
			end
		end
	end
	if healed then
		recordUse(user, move, ctx)
	end
end

Handlers.Teleport = function(user, move, aim, ctx)
	if user.Mounted then
		return
	end
	local dir = aimDirection(user, aim)
	local start = user.Root.Position
	local distance = (move.Distance or 40) * ctx.Range
	if aim then
		distance = math.min(distance, (Vector3.new(aim.X, start.Y, aim.Z) - start).Magnitude)
	end
	local target = Hitbox.ClampPath(start + Vector3.new(0, 1.5, 0), dir, distance, 3)
	local ground = Hitbox.GroundBelow(target + Vector3.new(0, 6, 0), 40)
	local finish = if ground then ground + Vector3.new(0, 3, 0) else target
	user.IFrameUntil = math.max(user.IFrameUntil, os.clock() + 0.3)
	user.Model:PivotTo(CFrame.lookAt(finish, finish + dir))
	Net.FX("Teleport", { Model = user.Model, From = start, To = finish, Color = ctx.Color })
	if inCombat(user) then
		recordUse(user, move, ctx)
	end
end

Handlers.TimeStop = function(user, move, _aim, ctx)
	local duration = (move.Duration or 2) * (1 + ctx.Tier.Speed)
	busy(user, 0.5, 0)
	pose(user, "TimeStop", 0.8)
	local caught = CombatService.TimeStop(user, move.Radius or 120, duration)
	Projectiles.Freeze(user, os.clock() + duration)
	if caught > 0 then
		recordUse(user, move, ctx)
	end
end

Handlers.Erase = function(user, move, _aim, ctx)
	local duration = (move.Duration or 2) * (1 + ctx.Tier.Speed)
	CombatService.Erase(user, duration)
	pose(user, "Erase", duration)
	if inCombat(user) then
		recordUse(user, move, ctx)
	end
end

Handlers.Counter = function(user, move, _aim, ctx)
	local duration = (move.Duration or 1.2) * (1 + ctx.Tier.Speed)
	user.Counter = { Until = os.clock() + duration, Move = move, Mult = ctx.Power * user.DamageMult }
	pose(user, "Counter", duration)
	busy(user, duration, 0.3)
	Net.FX("CounterStance", { Model = user.Model, Duration = duration, Color = ctx.Color })
end

Handlers.Rewind = function(user, move, _aim, ctx)
	pose(user, "Rewind", 0.8)
	CombatService.Rewind(user, move.Duration or 5, move.Heal or 0.5)
	if inCombat(user) then
		recordUse(user, move, ctx)
	end
end

Handlers.Buff = function(user, move, _aim, ctx)
	local duration = (move.Duration or 8) * (1 + ctx.Tier.Speed)
	user.SpeedBuff = { Until = os.clock() + duration, Power = move.EffectPower or 0.3 }
	Combatants.ApplyMovement(user)
	pose(user, "Buff", 0.8)
	Net.FX("Buff", { Model = user.Model, Duration = duration, Color = ctx.Color })
	task.delay(duration, function()
		if user.SpeedBuff and os.clock() >= user.SpeedBuff.Until then
			user.SpeedBuff = nil
			Combatants.ApplyMovement(user)
		end
	end)
	if inCombat(user) then
		recordUse(user, move, ctx)
	end
end

-- Runs a move. Cooldowns and validation are the caller's job.
function Moves.Execute(user: Combatant, move: Move, aim: Vector3?, ctx: Context)
	local handler = Handlers[move.Kind]
	if not handler then
		warn("[Moves] no handler for kind", move.Kind)
		return
	end
	Signals.MoveUsed:Fire(user, move)
	Net.FX("MoveUsed", { Model = user.Model, Move = move.Id, Color = ctx.Color })
	task.spawn(function()
		local ok, err = pcall(handler :: any, user, move, aim, ctx)
		if not ok then
			warn("[Moves]", move.Id, "failed:", err)
		end
	end)
end

-- Effective cooldown for a move after mastery and speed buffs.
function Moves.Cooldown(user: Combatant, move: Move, ctx: Context): number
	local cd = move.Cooldown * (1 - ctx.Tier.Cooldown)
	if user.SpeedBuff and os.clock() < user.SpeedBuff.Until then
		cd /= 1 + user.SpeedBuff.Power
	end
	return cd
end

return Moves
