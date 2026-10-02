--!strict
-- Server hit detection. Boxes and spheres use spatial queries limited to
-- registered fighters; line of sight uses raycasts against the map.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Zones = require(ReplicatedStorage.Shared.Zones)
local Combatants = require(script.Parent.Combatants)

type Combatant = Combatants.Combatant

local Hitbox = {}

local overlap = OverlapParams.new()
overlap.FilterType = Enum.RaycastFilterType.Include
overlap.FilterDescendantsInstances = {}
overlap.RespectCanCollide = false

local function refreshFilter()
	overlap.FilterDescendantsInstances = table.clone(Combatants.Models()) :: { any }
end
Combatants.OnListChanged(refreshFilter)

local worldRay = RaycastParams.new()
worldRay.FilterType = Enum.RaycastFilterType.Exclude
worldRay.IgnoreWater = true

-- Rule for player versus player damage, set by PvPService.
local playerRule: (Combatant, Combatant) -> boolean = function()
	return false
end

function Hitbox.SetPlayerRule(fn: (Combatant, Combatant) -> boolean)
	playerRule = fn
end

-- Cached zone safety per player character, refreshed by CharacterService.
local safeCache: { [Model]: boolean } = {}

function Hitbox.SetSafe(model: Model, safe: boolean)
	safeCache[model] = safe
end

function Hitbox.IsSafe(c: Combatant): boolean
	local cached = safeCache[c.Model]
	if cached ~= nil then
		return cached
	end
	return Zones.Classify(c.Root.Position).Safe
end

-- Whether attacker may damage target at all.
function Hitbox.CanHarm(attacker: Combatant?, target: Combatant): boolean
	if not Combatants.IsAlive(target) then
		return false
	end
	if attacker == target then
		return false
	end
	if Combatants.IsErased(target) then
		return false
	end
	if attacker == nil then
		return true
	end
	if attacker.IsNPC and target.IsNPC then
		-- Race rivals and outlaws never fight each other.
		return false
	end
	if attacker.IsNPC and not target.IsNPC then
		return not Hitbox.IsSafe(target) and os.clock() >= target.ProtectedUntil
	end
	if not attacker.IsNPC and target.IsNPC then
		return target.Data.Passive ~= true
	end
	return playerRule(attacker, target)
end

local function collect(parts: { BasePart }, attacker: Combatant?, filter: ((Combatant) -> boolean)?): { Combatant }
	local seen: { [Combatant]: boolean } = {}
	local list: { Combatant } = {}
	for _, part in parts do
		local c = Combatants.FromPart(part)
		if c and not seen[c] then
			seen[c] = true
			if Hitbox.CanHarm(attacker, c) and (filter == nil or filter(c)) then
				table.insert(list, c)
			end
		end
	end
	return list
end

function Hitbox.Box(cf: CFrame, size: Vector3, attacker: Combatant?, filter: ((Combatant) -> boolean)?): { Combatant }
	local parts = workspace:GetPartBoundsInBox(cf, size, overlap)
	return collect(parts, attacker, filter)
end

function Hitbox.Sphere(center: Vector3, radius: number, attacker: Combatant?, filter: ((Combatant) -> boolean)?): { Combatant }
	local parts = workspace:GetPartBoundsInRadius(center, radius, overlap)
	return collect(parts, attacker, filter)
end

-- A box from a point out along a direction (for lines, heavies and dashes).
function Hitbox.Forward(origin: Vector3, direction: Vector3, length: number, width: number, height: number, attacker: Combatant?): { Combatant }
	local dir = Vector3.new(direction.X, 0, direction.Z)
	if dir.Magnitude < 1e-3 then
		dir = Vector3.new(0, 0, -1)
	end
	dir = dir.Unit
	local center = origin + dir * (length / 2)
	local cf = CFrame.lookAt(center, center + dir)
	return Hitbox.Box(cf, Vector3.new(width, height, length), attacker)
end

-- Sorts targets by distance from a point, nearest first.
function Hitbox.SortByDistance(list: { Combatant }, from: Vector3)
	table.sort(list, function(a, b)
		return (a.Root.Position - from).Magnitude < (b.Root.Position - from).Magnitude
	end)
end

-- Raycast against the static world (map and terrain), ignoring fighters.
function Hitbox.WorldRay(origin: Vector3, direction: Vector3): RaycastResult?
	local ignore: { Instance } = table.clone(Combatants.Models()) :: { any }
	local horses = workspace:FindFirstChild("Horses")
	if horses then
		table.insert(ignore, horses)
	end
	local stands = workspace:FindFirstChild("Stands")
	if stands then
		table.insert(ignore, stands)
	end
	local fx = workspace:FindFirstChild("ServerFX")
	if fx then
		table.insert(ignore, fx)
	end
	worldRay.FilterDescendantsInstances = ignore
	return workspace:Raycast(origin, direction, worldRay)
end

-- Clear path check between two points.
function Hitbox.LineOfSight(a: Vector3, b: Vector3): boolean
	return Hitbox.WorldRay(a, b - a) == nil
end

-- Farthest reachable point along a direction before hitting the world.
function Hitbox.ClampPath(origin: Vector3, direction: Vector3, distance: number, padding: number): Vector3
	local dir = if direction.Magnitude > 1e-3 then direction.Unit else Vector3.new(0, 0, -1)
	local hit = Hitbox.WorldRay(origin, dir * distance)
	if hit then
		return origin + dir * math.max(0, (hit.Position - origin).Magnitude - padding)
	end
	return origin + dir * distance
end

-- Ground height below a point, or nil.
function Hitbox.GroundBelow(p: Vector3, depth: number?): Vector3?
	local hit = Hitbox.WorldRay(p + Vector3.new(0, 4, 0), Vector3.new(0, -(depth or 60), 0))
	return if hit then hit.Position else nil
end

return Hitbox
