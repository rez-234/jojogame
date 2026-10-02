--!strict
-- The race route: a smooth curve from the San Diego beach to New York,
-- compressed along X. The curve is monotonic in X so any world position maps
-- to a single nearest stretch of trail cheaply.

local Config = require(script.Parent.Config)
local Util = require(script.Parent.Util)

export type Stage = {
	Index: number,
	Id: string,
	Name: string,
	Region: string,
	StartFrac: number,
	EndFrac: number,
	Kind: string,
	TrailBase: number,
	Amp: number,
	Freq: number,
	Octaves: number,
	SurfaceA: Enum.Material,
	SurfaceB: Enum.Material,
	Cliff: Enum.Material,
	FogColor: Color3,
	FogDensity: number,
	Haze: number,
	Tint: Color3,
	WindVolume: number,
	EnemyLevel: number,
	Props: { [string]: number },
}

export type Sample = {
	X: number,
	Z: number,
	Dist: number,
	Tangent: Vector3,
}

local Route = {}

-- Waypoints as (fraction of route length, north/south offset as a multiple of RouteMeander).
local WAYPOINTS: { { number } } = {
	{ 0.00, 0.00 }, -- San Diego beach
	{ 0.05, 0.10 },
	{ 0.11, 0.32 }, -- Arizona desert
	{ 0.18, 0.18 },
	{ 0.24, -0.20 }, -- Monument Valley
	{ 0.31, -0.35 },
	{ 0.37, -0.05 }, -- Rocky Mountains
	{ 0.43, 0.22 },
	{ 0.50, 0.10 }, -- Kansas plains
	{ 0.57, -0.15 },
	{ 0.63, -0.05 }, -- Forest
	{ 0.69, 0.18 },
	{ 0.74, 0.12 }, -- Mississippi crossing
	{ 0.80, -0.10 },
	{ 0.87, -0.22 }, -- Frontier towns
	{ 0.93, 0.02 },
	{ 1.00, 0.00 }, -- New York
}

local function c3(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

Route.Stages = {
	{
		Index = 1,
		Id = "Beach",
		Name = "San Diego Beach",
		Region = "California",
		StartFrac = 0.0,
		EndFrac = 0.08,
		Kind = "Beach",
		TrailBase = 14,
		Amp = 10,
		Freq = 1 / 260,
		Octaves = 3,
		SurfaceA = Enum.Material.Sand,
		SurfaceB = Enum.Material.Limestone,
		Cliff = Enum.Material.Sandstone,
		FogColor = c3(214, 196, 170),
		FogDensity = 0.28,
		Haze = 1.2,
		Tint = c3(255, 236, 214),
		WindVolume = 0.35,
		EnemyLevel = 1,
		Props = { Palm = 0.5, Rock = 0.6, Driftwood = 0.8, Tumbleweed = 0.1 },
	},
	{
		Index = 2,
		Id = "Desert",
		Name = "Arizona Desert",
		Region = "Arizona",
		StartFrac = 0.08,
		EndFrac = 0.2,
		Kind = "Desert",
		TrailBase = 30,
		Amp = 22,
		Freq = 1 / 420,
		Octaves = 4,
		SurfaceA = Enum.Material.Sand,
		SurfaceB = Enum.Material.Salt,
		Cliff = Enum.Material.Sandstone,
		FogColor = c3(226, 190, 140),
		FogDensity = 0.34,
		Haze = 2.2,
		Tint = c3(255, 228, 196),
		WindVolume = 0.5,
		EnemyLevel = 4,
		Props = { Cactus = 1.2, Rock = 0.8, DeadTree = 0.25, Tumbleweed = 0.6, Wagon = 0.05, Camp = 0.04 },
	},
	{
		Index = 3,
		Id = "Canyon",
		Name = "Monument Valley",
		Region = "Utah",
		StartFrac = 0.2,
		EndFrac = 0.33,
		Kind = "Canyon",
		TrailBase = 40,
		Amp = 34,
		Freq = 1 / 300,
		Octaves = 4,
		SurfaceA = Enum.Material.Sandstone,
		SurfaceB = Enum.Material.Sand,
		Cliff = Enum.Material.Rock,
		FogColor = c3(214, 150, 110),
		FogDensity = 0.3,
		Haze = 2.0,
		Tint = c3(255, 220, 190),
		WindVolume = 0.55,
		EnemyLevel = 9,
		Props = { Rock = 1.4, Cactus = 0.4, DeadTree = 0.3, Mesa = 0.06, Tumbleweed = 0.4, Camp = 0.03 },
	},
	{
		Index = 4,
		Id = "Mountain",
		Name = "Rocky Mountain Pass",
		Region = "Colorado",
		StartFrac = 0.33,
		EndFrac = 0.46,
		Kind = "Mountain",
		TrailBase = 120,
		Amp = 200,
		Freq = 1 / 520,
		Octaves = 5,
		SurfaceA = Enum.Material.Grass,
		SurfaceB = Enum.Material.Slate,
		Cliff = Enum.Material.Rock,
		FogColor = c3(196, 206, 214),
		FogDensity = 0.36,
		Haze = 1.4,
		Tint = c3(232, 240, 255),
		WindVolume = 0.8,
		EnemyLevel = 15,
		Props = { Pine = 2.0, Rock = 1.0, DeadTree = 0.2 },
	},
	{
		Index = 5,
		Id = "Plains",
		Name = "Kansas Plains",
		Region = "Kansas",
		StartFrac = 0.46,
		EndFrac = 0.59,
		Kind = "Plains",
		TrailBase = 36,
		Amp = 12,
		Freq = 1 / 600,
		Octaves = 3,
		SurfaceA = Enum.Material.Grass,
		SurfaceB = Enum.Material.Ground,
		Cliff = Enum.Material.Ground,
		FogColor = c3(222, 214, 182),
		FogDensity = 0.26,
		Haze = 1.0,
		Tint = c3(255, 246, 222),
		WindVolume = 0.45,
		EnemyLevel = 21,
		Props = { Tree = 0.35, Fence = 0.4, Rock = 0.2, Haystack = 0.5, Farm = 0.05, Wagon = 0.05 },
	},
	{
		Index = 6,
		Id = "Forest",
		Name = "Great Forest",
		Region = "Missouri",
		StartFrac = 0.59,
		EndFrac = 0.71,
		Kind = "Forest",
		TrailBase = 44,
		Amp = 26,
		Freq = 1 / 340,
		Octaves = 4,
		SurfaceA = Enum.Material.LeafyGrass,
		SurfaceB = Enum.Material.Mud,
		Cliff = Enum.Material.Rock,
		FogColor = c3(150, 168, 140),
		FogDensity = 0.42,
		Haze = 1.6,
		Tint = c3(236, 248, 228),
		WindVolume = 0.3,
		EnemyLevel = 27,
		Props = { Tree = 2.4, Pine = 0.9, Rock = 0.4, Camp = 0.03, DeadTree = 0.1 },
	},
	{
		Index = 7,
		Id = "River",
		Name = "Mississippi Crossing",
		Region = "Illinois",
		StartFrac = 0.71,
		EndFrac = 0.8,
		Kind = "River",
		TrailBase = 22,
		Amp = 14,
		Freq = 1 / 380,
		Octaves = 3,
		SurfaceA = Enum.Material.Grass,
		SurfaceB = Enum.Material.Mud,
		Cliff = Enum.Material.Ground,
		FogColor = c3(184, 196, 196),
		FogDensity = 0.38,
		Haze = 1.4,
		Tint = c3(240, 248, 255),
		WindVolume = 0.35,
		EnemyLevel = 33,
		Props = { Tree = 1.0, Rock = 0.4, Reeds = 1.2, Fence = 0.1 },
	},
	{
		Index = 8,
		Id = "Frontier",
		Name = "Frontier Towns",
		Region = "Ohio",
		StartFrac = 0.8,
		EndFrac = 0.93,
		Kind = "Frontier",
		TrailBase = 34,
		Amp = 16,
		Freq = 1 / 420,
		Octaves = 3,
		SurfaceA = Enum.Material.Ground,
		SurfaceB = Enum.Material.Grass,
		Cliff = Enum.Material.Rock,
		FogColor = c3(206, 196, 176),
		FogDensity = 0.3,
		Haze = 1.2,
		Tint = c3(255, 240, 220),
		WindVolume = 0.4,
		EnemyLevel = 40,
		Props = { Tree = 0.6, Fence = 0.5, Rock = 0.3, Wagon = 0.08, Haystack = 0.2, DeadTree = 0.15 },
	},
	{
		Index = 9,
		Id = "City",
		Name = "New York",
		Region = "New York",
		StartFrac = 0.93,
		EndFrac = 1.0,
		Kind = "City",
		TrailBase = 18,
		Amp = 8,
		Freq = 1 / 400,
		Octaves = 2,
		SurfaceA = Enum.Material.Grass,
		SurfaceB = Enum.Material.Cobblestone,
		Cliff = Enum.Material.Rock,
		FogColor = c3(180, 176, 172),
		FogDensity = 0.34,
		Haze = 1.0,
		Tint = c3(246, 240, 236),
		WindVolume = 0.2,
		EnemyLevel = 46,
		Props = { Tree = 0.3, Lantern = 0.3 },
	},
} :: { Stage }

local LENGTH = Config.Map.RouteLength
local X0 = -LENGTH / 2
local X1 = LENGTH / 2

Route.MinX = X0
Route.MaxX = X1

-- Monotone cubic (Fritsch-Carlson) interpolation of the waypoint offsets.
local wx: { number } = {}
local wz: { number } = {}
for i, w in WAYPOINTS do
	wx[i] = X0 + w[1] * LENGTH
	wz[i] = w[2] * Config.Map.RouteMeander
end
local n = #wx
local slopes: { number } = {}
for i = 1, n - 1 do
	slopes[i] = (wz[i + 1] - wz[i]) / (wx[i + 1] - wx[i])
end
local tangents: { number } = {}
tangents[1] = slopes[1]
tangents[n] = slopes[n - 1]
for i = 2, n - 1 do
	if slopes[i - 1] * slopes[i] <= 0 then
		tangents[i] = 0
	else
		tangents[i] = (slopes[i - 1] + slopes[i]) / 2
	end
end
for i = 1, n - 1 do
	if slopes[i] == 0 then
		tangents[i] = 0
		tangents[i + 1] = 0
	else
		local a = tangents[i] / slopes[i]
		local b = tangents[i + 1] / slopes[i]
		local s = a * a + b * b
		if s > 9 then
			local tau = 3 / math.sqrt(s)
			tangents[i] = tau * a * slopes[i]
			tangents[i + 1] = tau * b * slopes[i]
		end
	end
end

local function baseZ(x: number): number
	if x <= wx[1] then
		return wz[1]
	elseif x >= wx[n] then
		return wz[n]
	end
	local i = 1
	while i < n - 1 and x > wx[i + 1] do
		i += 1
	end
	local h = wx[i + 1] - wx[i]
	local t = (x - wx[i]) / h
	local t2, t3 = t * t, t * t * t
	local h00 = 2 * t3 - 3 * t2 + 1
	local h10 = t3 - 2 * t2 + t
	local h01 = -2 * t3 + 3 * t2
	local h11 = t3 - t2
	return h00 * wz[i] + h10 * h * tangents[i] + h01 * wz[i + 1] + h11 * h * tangents[i + 1]
end

-- Small extra wiggle so the trail does not look drawn with a ruler.
local function wiggle(x: number): number
	local edge = Util.smoothstep(X0, X0 + 300, x) * (1 - Util.smoothstep(X1 - 300, X1, x))
	return math.noise(x / 260, Config.Map.Seed * 0.13, 4.2) * 70 * edge
end

function Route.ZAt(x: number): number
	return baseZ(x) + wiggle(x)
end

-- Dense samples, evenly spaced in X.
local SPACING = Config.Map.RouteSampleSpacing
local samples: { Sample } = {}
do
	local dist = 0
	local prevX, prevZ = X0, Route.ZAt(X0)
	local count = math.floor(LENGTH / SPACING) + 1
	for i = 1, count do
		local x = X0 + (i - 1) * SPACING
		local z = Route.ZAt(x)
		if i > 1 then
			dist += math.sqrt((x - prevX) ^ 2 + (z - prevZ) ^ 2)
		end
		samples[i] = { X = x, Z = z, Dist = dist, Tangent = Vector3.new(1, 0, 0) }
		prevX, prevZ = x, z
	end
	for i = 1, count do
		local a = samples[math.max(1, i - 1)]
		local b = samples[math.min(count, i + 1)]
		samples[i].Tangent = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
	end
end

Route.Samples = samples
Route.Length = samples[#samples].Dist

local function sampleIndexForX(x: number): number
	return Util.clamp(math.floor((x - X0) / SPACING) + 1, 1, #samples)
end

-- Returns distance along the route and signed lateral offset (positive = right of travel).
function Route.Project(pos: Vector3): (number, number)
	local base = sampleIndexForX(pos.X)
	local bestI, bestD = base, math.huge
	for i = math.max(1, base - 6), math.min(#samples, base + 6) do
		local s = samples[i]
		local d = (pos.X - s.X) ^ 2 + (pos.Z - s.Z) ^ 2
		if d < bestD then
			bestD, bestI = d, i
		end
	end
	local s = samples[bestI]
	local rel = Vector3.new(pos.X - s.X, 0, pos.Z - s.Z)
	local along = rel:Dot(s.Tangent)
	local right = s.Tangent:Cross(Vector3.yAxis)
	local lateral = rel:Dot(right)
	return Util.clamp(s.Dist + along, 0, Route.Length), lateral
end

-- Unsigned distance from the trail centerline (XZ only).
function Route.DistanceFromTrail(x: number, z: number): number
	local _, lateral = Route.Project(Vector3.new(x, 0, z))
	return math.abs(lateral)
end

local function indexForDist(d: number): number
	d = Util.clamp(d, 0, Route.Length)
	local lo, hi = 1, #samples
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if samples[mid].Dist <= d then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

-- XZ point (Y = 0) and flat tangent at a distance along the route.
function Route.PointAt(d: number): (Vector3, Vector3)
	local i = indexForDist(d)
	local a = samples[i]
	local b = samples[math.min(#samples, i + 1)]
	local span = b.Dist - a.Dist
	local t = if span > 0 then Util.clamp((d - a.Dist) / span, 0, 1) else 0
	local x = Util.lerp(a.X, b.X, t)
	local z = Util.lerp(a.Z, b.Z, t)
	local tangent = a.Tangent:Lerp(b.Tangent, t)
	return Vector3.new(x, 0, z), tangent.Unit
end

-- XZ point offset sideways from the trail. Positive offset is to the right of travel.
function Route.OffsetPoint(d: number, lateral: number): (Vector3, Vector3)
	local p, t = Route.PointAt(d)
	local right = t:Cross(Vector3.yAxis)
	return p + right * lateral, t
end

function Route.DistAtFrac(frac: number): number
	local x = X0 + frac * LENGTH
	return samples[sampleIndexForX(x)].Dist
end

function Route.FracAtX(x: number): number
	return Util.clamp((x - X0) / LENGTH, 0, 1)
end

function Route.StageAtX(x: number): Stage
	local f = Route.FracAtX(x)
	for _, s in Route.Stages do
		if f < s.EndFrac then
			return s
		end
	end
	return Route.Stages[#Route.Stages]
end

function Route.StageAtDist(d: number): Stage
	local p = Route.PointAt(d)
	return Route.StageAtX(p.X)
end

-- Returns the two stages around x and the blend factor toward the next one.
function Route.StageBlend(x: number, blendWidth: number): (Stage, Stage, number)
	local f = Route.FracAtX(x)
	local stages = Route.Stages
	for i, s in stages do
		if f < s.EndFrac or i == #stages then
			local boundaryX = X0 + s.EndFrac * LENGTH
			local startX = X0 + s.StartFrac * LENGTH
			if i < #stages and x > boundaryX - blendWidth then
				local t = Util.smoothstep(boundaryX - blendWidth, boundaryX + blendWidth, x)
				return s, stages[i + 1], t
			elseif i > 1 and x < startX + blendWidth then
				local t = Util.smoothstep(startX - blendWidth, startX + blendWidth, x)
				return stages[i - 1], s, t
			end
			return s, s, 0
		end
	end
	return stages[#stages], stages[#stages], 0
end

function Route.StageStartDist(stage: Stage): number
	return Route.DistAtFrac(stage.StartFrac)
end

function Route.StageEndDist(stage: Stage): number
	return Route.DistAtFrac(stage.EndFrac)
end

return Route
