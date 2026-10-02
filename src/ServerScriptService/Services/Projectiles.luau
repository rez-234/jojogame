--!strict
-- Server simulated projectiles. The server owns the path and the hits;
-- clients draw the projectile from the spawn message and receive position
-- corrections for homing shots and when a projectile ends.

local RunService = game:GetService("RunService")

local Net = require(script.Parent.Net)
local Combatants = require(script.Parent.Combatants)
local Hitbox = require(script.Parent.Hitbox)

type Combatant = Combatants.Combatant

local Projectiles = {}

export type Spec = {
	Owner: Combatant,
	Origin: Vector3,
	Direction: Vector3,
	Speed: number,
	Range: number,
	Radius: number,
	Homing: number?,
	Shape: string?,
	Color: Color3,
	OnHit: (Combatant, Vector3) -> (),
	-- Called where the projectile ends without hitting anyone.
	OnExpire: ((Vector3) -> ())?,
}

type Live = {
	Id: number,
	Spec: Spec,
	Position: Vector3,
	Direction: Vector3,
	Traveled: number,
	FrozenUntil: number,
	LastSync: number,
	Target: Combatant?,
}

local live: { Live } = {}
local nextId = 0

local function finish(p: Live, position: Vector3, didHit: boolean)
	Net.FX("ProjEnd", { Id = p.Id, P = position, Hit = didHit, Sh = p.Spec.Shape })
end

function Projectiles.Fire(spec: Spec): number
	nextId += 1
	local dir = if spec.Direction.Magnitude > 1e-3 then spec.Direction.Unit else Vector3.new(0, 0, -1)
	local p: Live = {
		Id = nextId,
		Spec = spec,
		Position = spec.Origin,
		Direction = dir,
		Traveled = 0,
		FrozenUntil = 0,
		LastSync = os.clock(),
		Target = nil,
	}
	table.insert(live, p)
	Net.FX("Proj", {
		Id = p.Id,
		O = spec.Origin,
		D = dir,
		S = spec.Speed,
		R = spec.Range,
		Sh = spec.Shape or "Ball",
		C = spec.Color,
		Rad = spec.Radius,
	})
	return p.Id
end

-- Pauses every projectile not fired by the given owner (time stop).
function Projectiles.Freeze(except: Combatant, untilTime: number)
	for _, p in live do
		if p.Spec.Owner ~= except then
			p.FrozenUntil = math.max(p.FrozenUntil, untilTime)
		end
	end
end

local function pickTarget(p: Live): Combatant?
	local best: Combatant? = nil
	local bestDist = 45
	for _, c in Combatants.All() do
		if Hitbox.CanHarm(p.Spec.Owner, c) then
			local to = c.Root.Position - p.Position
			local dist = to.Magnitude
			if dist < bestDist and dist > 0.1 and to.Unit:Dot(p.Direction) > 0.3 then
				best = c
				bestDist = dist
			end
		end
	end
	return best
end

local function step(dt: number)
	local now = os.clock()
	local i = 1
	while i <= #live do
		local p = live[i]
		local spec = p.Spec
		local done = false
		if now < p.FrozenUntil then
			i += 1
			continue
		end
		-- Homing turns toward the nearest valid target ahead.
		if spec.Homing and spec.Homing > 0 then
			if not p.Target or not Combatants.IsAlive(p.Target) or Combatants.IsErased(p.Target) then
				p.Target = pickTarget(p)
			end
			local target = p.Target
			if target then
				local want = (target.Root.Position - p.Position).Unit
				local angle = math.acos(math.clamp(p.Direction:Dot(want), -1, 1))
				local maxTurn = spec.Homing * dt
				if angle > 1e-3 then
					local t = math.min(1, maxTurn / angle)
					p.Direction = p.Direction:Lerp(want, t).Unit
				end
			end
			if now - p.LastSync > 0.1 then
				p.LastSync = now
				Net.FX("ProjMove", { Id = p.Id, P = p.Position, D = p.Direction })
			end
		end
		local move = p.Direction * spec.Speed * dt
		local nextPos = p.Position + move
		-- World collision along the segment.
		local wall = Hitbox.WorldRay(p.Position, move)
		if wall then
			nextPos = wall.Position
			done = true
		end
		-- Fighters near the segment end.
		local hits = Hitbox.Sphere(nextPos, spec.Radius + 1.5, spec.Owner)
		if #hits == 0 and move.Magnitude > spec.Radius * 2 then
			-- Fast projectiles also check the midpoint so they cannot skip targets.
			hits = Hitbox.Sphere(p.Position + move * 0.5, spec.Radius + 1.5, spec.Owner)
		end
		if #hits > 0 then
			Hitbox.SortByDistance(hits, p.Position)
			local target = hits[1]
			local ok, err = pcall(spec.OnHit :: any, target, nextPos)
			if not ok then
				warn("[Projectiles] OnHit failed:", err)
			end
			finish(p, nextPos, true)
			table.remove(live, i)
			continue
		end
		p.Traveled += move.Magnitude
		p.Position = nextPos
		if done or p.Traveled >= spec.Range or not spec.Owner.Model.Parent then
			if spec.OnExpire then
				local ok, err = pcall(spec.OnExpire :: any, p.Position)
				if not ok then
					warn("[Projectiles] OnExpire failed:", err)
				end
			end
			finish(p, p.Position, false)
			table.remove(live, i)
			continue
		end
		i += 1
	end
end

function Projectiles.Start()
	RunService.Heartbeat:Connect(step)
end

return Projectiles
