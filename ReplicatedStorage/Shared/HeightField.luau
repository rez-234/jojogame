--!strict
-- Deterministic terrain height function. Everything that needs the ground
-- height (terrain generation, placement, NPC paths) uses this, so the world is
-- identical every time for a given seed.

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)
local Route = require(script.Parent.Route)
local Layout = require(script.Parent.Layout)

local HeightField = {}

local SEED = Config.Map.Seed
local HALF = Config.Map.CorridorHalfWidth
local TRAIL_HALF = Config.Map.TrailHalfWidth
local TRAIL_BLEND = Config.Map.TrailBlendWidth

-- Smooth trail height: stage base heights blended across boundaries.
local TRAIL_STEP = 16
local trailTable: { number } = {}
do
	local count = math.floor(Config.Map.RouteLength / TRAIL_STEP) + 3
	local raw: { number } = {}
	for i = 1, count do
		local x = Route.MinX + (i - 2) * TRAIL_STEP
		local s = Route.StageAtX(x)
		raw[i] = s.TrailBase
	end
	-- Box blur repeatedly for a gentle grade.
	local radius = 24
	local current = raw
	for _ = 1, 3 do
		local out: { number } = {}
		local sum = 0
		local window = 0
		for i = 1, count do
			sum += current[i]
			window += 1
			if i - (2 * radius + 1) >= 1 then
				sum -= current[i - (2 * radius + 1)]
				window -= 1
			end
			local center = i - radius
			if center >= 1 then
				out[center] = sum / window
			end
		end
		for i = count - radius + 1, count do
			out[i] = out[i] or current[i]
		end
		current = out
	end
	for i = 1, count do
		local x = Route.MinX + (i - 2) * TRAIL_STEP
		trailTable[i] = current[i] + math.noise(x / 330, SEED * 0.07, 2.5) * 5
	end
end

function HeightField.TrailHeight(x: number): number
	local f = (x - Route.MinX) / TRAIL_STEP + 2
	local i = math.floor(f)
	local t = f - i
	local a = trailTable[math.clamp(i, 1, #trailTable)]
	local b = trailTable[math.clamp(i + 1, 1, #trailTable)]
	return a + (b - a) * t
end

local function terrace(h: number, step: number): number
	local k = h / step
	local base = math.floor(k)
	local frac = k - base
	return (base + Util.smoothstep(0.7, 1, frac)) * step
end

-- Height relative to the trail for one stage's landscape.
local function stageRelative(stage: Route.Stage, x: number, z: number, dist: number): number
	local n = Util.fbm(x * stage.Freq, z * stage.Freq, stage.Octaves, SEED + stage.Index * 101)
	local kind = stage.Kind
	local away = Util.smoothstep(30, 220, dist)
	if kind == "Beach" then
		local dunes = math.noise(x / 46, z / 90, SEED + 3) * 3
		return stage.Amp * n * 0.6 * away + dunes
	elseif kind == "Desert" then
		local dunes = math.abs(math.noise(x / 80, z / 55, SEED + 5)) * 10
		return stage.Amp * n * away + dunes * away
	elseif kind == "Canyon" then
		local m = Util.fbm(x / 380, z / 380, 3, SEED + 77)
		local plateau = Util.smoothstep(0.05, 0.25, m) * 85
		local walls = Util.smoothstep(55, 95, dist) * 50
		local h = (plateau + walls) * away + stage.Amp * 0.35 * n
		return terrace(math.max(h, 0), 15)
	elseif kind == "Mountain" then
		local ridge = Util.ridged(x / 520, z / 520, 5, SEED + 31)
		return stage.Amp * ridge * Util.smoothstep(25, 300, dist) + 18 * n
	elseif kind == "City" then
		return stage.Amp * n * away
	end
	return stage.Amp * n * (0.35 + 0.65 * away)
end

local function shoreX(z: number): number
	return Route.MinX - 50 + math.noise(z / 160, SEED * 0.3, 7.7) * 34
end

-- Natural landscape height before flats and water carving.
local function naturalHeight(x: number, z: number, trailH: number, dist: number): number
	local a, b, t = Route.StageBlend(x, 260)
	local rel = stageRelative(a, x, z, dist)
	if t > 0 and b ~= a then
		rel = Util.lerp(rel, stageRelative(b, x, z, dist), t)
	end
	local h = trailH + rel

	-- Rugged walls along the edge of the playable band.
	local edge = Util.smoothstep(HALF - 150, HALF - 15, dist)
	if edge > 0 then
		local wall = Config.Map.BoundaryWallHeight * (0.7 + 0.3 * math.noise(x / 90, z / 90, SEED + 11))
		h = math.max(h, trailH + wall * edge)
	end
	return h
end

-- Final surface height (Y of the ground) at an XZ point.
function HeightField.Surface(x: number, z: number): number
	local trailH = HeightField.TrailHeight(x)
	local dist = Route.DistanceFromTrail(x, z)
	local h = naturalHeight(x, z, trailH, dist)

	-- Flatten the trail corridor.
	local w = Util.smoothstep(TRAIL_HALF + 2, TRAIL_HALF + TRAIL_BLEND, dist)
	h = Util.lerp(trailH, h, w)

	-- Building pads, arenas and town streets.
	for _, flat in Layout.FlatsNear(x) do
		local d, t = Layout.SegmentDistance(x, z, flat.A, flat.B)
		local reach = flat.Radius + flat.Fall
		if d < reach then
			local fx = if flat.Follow then x else Util.lerp(flat.A.X, flat.B.X, t)
			local flatH = HeightField.TrailHeight(fx) + flat.Raise
			h = Util.lerp(flatH, h, Util.smoothstep(flat.Radius, reach, d))
		end
	end

	-- Ocean west of the start.
	local sx = shoreX(z)
	if x < sx + 160 then
		local seabed = Config.Map.SeaLevel - 28
		h = Util.lerp(seabed, h, Util.smoothstep(sx - 90, sx + 160, x))
	end

	-- River channel.
	local river = Layout.River
	if math.abs(x - river.CenterX) < 400 then
		local dr = math.abs(x - Layout.RiverCenterX(z))
		local reach = river.HalfWidth + river.BankWidth
		if dr < reach then
			local water = HeightField.TrailHeight(river.CenterX) - river.WaterDrop
			local bed = water - river.Depth
			local carved = Util.lerp(bed, h, Util.smoothstep(river.HalfWidth * 0.55, reach, dr))
			h = math.min(h, carved)
		end
	end

	-- Waterfall pool.
	for _, pool in Layout.Pools do
		local dp = math.sqrt((x - pool.Center.X) ^ 2 + (z - pool.Center.Z) ^ 2)
		local reach = pool.Radius + 40
		if dp < reach then
			local bed = HeightField.TrailHeight(pool.Center.X) - pool.Drop
			h = Util.lerp(bed, h, Util.smoothstep(pool.Radius * 0.7, reach, dp))
		end
	end

	return h
end

-- Water surface height at a point, or nil if the point is not in water.
function HeightField.WaterLevel(x: number, z: number): number?
	local sx = shoreX(z)
	if x < sx + 40 then
		return Config.Map.SeaLevel
	end
	local river = Layout.River
	if math.abs(x - river.CenterX) < 400 then
		local dr = math.abs(x - Layout.RiverCenterX(z))
		if dr < river.HalfWidth + river.BankWidth then
			return HeightField.TrailHeight(river.CenterX) - river.WaterDrop
		end
	end
	for _, pool in Layout.Pools do
		local dp = math.sqrt((x - pool.Center.X) ^ 2 + (z - pool.Center.Z) ^ 2)
		if dp < pool.Radius + 10 then
			return HeightField.TrailHeight(pool.Center.X) - 1
		end
	end
	return nil
end

function HeightField.ShoreX(z: number): number
	return shoreX(z)
end

-- 3D point on the trail at a route distance.
function HeightField.TrailPoint(d: number): (Vector3, Vector3)
	local p, t = Route.PointAt(d)
	return Vector3.new(p.X, HeightField.TrailHeight(p.X), p.Z), t
end

function HeightField.Ground(p: Vector3): Vector3
	return Vector3.new(p.X, HeightField.Surface(p.X, p.Z), p.Z)
end

-- Approximate slope in degrees from finite differences.
function HeightField.Slope(x: number, z: number): number
	local e = 3
	local hx = HeightField.Surface(x + e, z) - HeightField.Surface(x - e, z)
	local hz = HeightField.Surface(x, z + e) - HeightField.Surface(x, z - e)
	local grad = math.sqrt(hx * hx + hz * hz) / (2 * e)
	return math.deg(math.atan(grad))
end

return HeightField
