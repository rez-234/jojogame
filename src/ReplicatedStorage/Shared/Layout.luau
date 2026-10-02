--!strict
-- Deterministic placement of every major feature along the route: towns,
-- checkpoints, boss arenas, landmarks, herds and flattened building pads.
-- Positions are XZ only (Y = 0); HeightField supplies heights.

local Config = require(script.Parent.Config)
local Route = require(script.Parent.Route)

export type Town = {
	Index: number,
	Name: string,
	Kind: string, -- "Start", "Town", "City"
	Stage: number,
	Dist0: number,
	Dist1: number,
	HalfWidth: number,
	Center: Vector3,
	Spawn: Vector3,
}

export type Checkpoint = {
	Index: number,
	Dist: number,
	Name: string,
	Position: Vector3,
	Tangent: Vector3,
}

export type Arena = {
	Stage: number,
	Center: Vector3,
	Radius: number,
	Dist: number,
	BossIndex: number,
}

export type Landmark = {
	Stage: number,
	Kind: string,
	Dist: number,
	Lateral: number,
	Position: Vector3,
	Facing: Vector3,
}

export type Flat = {
	A: Vector3,
	B: Vector3,
	Radius: number,
	Fall: number,
	-- Height offset relative to the trail height at the flat.
	Raise: number,
	-- Follow the trail grade instead of holding one height (town streets).
	Follow: boolean?,
}

export type Herd = {
	Stage: number,
	Center: Vector3,
}

export type Zone = {
	Stage: number,
	Dist0: number,
	Dist1: number,
	Level: number,
}

local Layout = {}

Layout.StartDist = Config.Map.StartOffset
Layout.FinishDist = Route.Length - 140

local function xz(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

-- Checkpoints sit on every stage boundary, then the finish line.
local checkpoints: { Checkpoint } = {}
for i = 1, #Route.Stages - 1 do
	local stage = Route.Stages[i]
	local d = Route.StageEndDist(stage)
	local p, t = Route.PointAt(d)
	table.insert(checkpoints, {
		Index = i,
		Dist = d,
		Name = Route.Stages[i + 1].Name,
		Position = p,
		Tangent = t,
	})
end
do
	local p, t = Route.PointAt(Layout.FinishDist)
	table.insert(checkpoints, {
		Index = #checkpoints + 1,
		Dist = Layout.FinishDist,
		Name = "Finish",
		Position = p,
		Tangent = t,
	})
end
Layout.Checkpoints = checkpoints

local TOWN_NAMES = {
	"Yuma",
	"Kayenta",
	"Silverton",
	"Dodge City",
	"Kansas City",
	"St. Louis",
	"Indianapolis",
}

local towns: { Town } = {}
local function addTown(name: string, kind: string, d0: number, d1: number, halfWidth: number)
	local mid = (d0 + d1) / 2
	local center = Route.PointAt(mid)
	local spawn = Route.OffsetPoint(d0 + 30, 0)
	table.insert(towns, {
		Index = #towns + 1,
		Name = name,
		Kind = kind,
		Stage = Route.StageAtDist(mid).Index,
		Dist0 = d0,
		Dist1 = d1,
		HalfWidth = halfWidth,
		Center = center,
		Spawn = spawn,
	})
end

addTown("San Diego", "Start", Layout.StartDist + 60, Layout.StartDist + 340, 70)
for i, name in TOWN_NAMES do
	local cp = checkpoints[i]
	addTown(name, "Town", cp.Dist + 50, cp.Dist + 300, 66)
end
do
	local frontier = Route.Stages[8]
	local s0, s1 = Route.StageStartDist(frontier), Route.StageEndDist(frontier)
	addTown("Columbus", "Town", s0 + (s1 - s0) * 0.38, s0 + (s1 - s0) * 0.38 + 220, 60)
	addTown("Pittsburgh", "Town", s0 + (s1 - s0) * 0.72, s0 + (s1 - s0) * 0.72 + 220, 60)
end
addTown("New York", "City", Route.Length - 720, Route.Length - 10, 120)
Layout.Towns = towns

-- One boss arena near the end of each stage, off the trail.
local arenas: { Arena } = {}
for i, stage in Route.Stages do
	local d
	if i == #Route.Stages then
		d = Route.StageStartDist(stage) + 220
	else
		d = Route.StageEndDist(stage) - 420
	end
	local side = if i % 2 == 0 then 1 else -1
	local center = Route.OffsetPoint(d, side * 150)
	table.insert(arenas, {
		Stage = i,
		Center = center,
		Radius = 56,
		Dist = d,
		BossIndex = i,
	})
end
Layout.Arenas = arenas

Layout.PvPArena = {
	Center = (Route.OffsetPoint(Layout.StartDist + 200, -210)),
	Radius = 72,
}

local function stageMid(i: number, frac: number): number
	local s = Route.Stages[i]
	local a, b = Route.StageStartDist(s), Route.StageEndDist(s)
	return a + (b - a) * frac
end

local landmarks: { Landmark } = {}
local function addLandmark(stage: number, kind: string, d: number, lateral: number)
	local p, t = Route.OffsetPoint(d, lateral)
	table.insert(landmarks, {
		Stage = stage,
		Kind = kind,
		Dist = d,
		Lateral = lateral,
		Position = p,
		Facing = t,
	})
end
addLandmark(1, "Lighthouse", 40, 150)
addLandmark(2, "RockArch", stageMid(2, 0.5), 0)
addLandmark(3, "GiantMesa", stageMid(3, 0.45), 230)
addLandmark(4, "Waterfall", stageMid(4, 0.55), -150)
addLandmark(5, "WindmillFarm", stageMid(5, 0.4), 150)
addLandmark(6, "GreatSequoia", stageMid(6, 0.5), 60)
addLandmark(7, "TrestleBridge", 0, 0) -- position replaced below once the river is known
addLandmark(8, "OldFort", stageMid(8, 0.2), -170)
addLandmark(9, "ClockTower", Route.Length - 360, 60)
Layout.Landmarks = landmarks

-- The river crosses the trail in stage 7, running roughly north to south.
local riverStage = Route.Stages[7]
local riverDist = stageMid(7, 0.45)
local riverPoint = Route.PointAt(riverDist)
Layout.River = {
	Dist = riverDist,
	CenterX = riverPoint.X,
	HalfWidth = 40,
	BankWidth = 34,
	Depth = 16,
	-- Water surface sits this far below the trail height at the crossing.
	WaterDrop = 9,
	Stage = riverStage.Index,
}

function Layout.RiverCenterX(z: number): number
	local r = Layout.River
	return r.CenterX + math.noise(z / 220, Config.Map.Seed * 0.21, 9.1) * 60 + math.noise(z / 70, 3.3, 1.7) * 8
end

do
	-- A railway trestle a little upstream of the trail bridge.
	local lm = landmarks[7]
	local p, t = Route.OffsetPoint(riverDist, -130)
	lm.Dist = riverDist
	lm.Lateral = -130
	lm.Position = Vector3.new(Layout.RiverCenterX(p.Z), 0, p.Z)
	lm.Facing = t
end

-- The waterfall feeds a small pool.
do
	local lm = landmarks[4]
	Layout.Pools = {
		{ Center = lm.Position, Radius = 30, Drop = 6 },
	}
end

local herds: { Herd } = {}
for i = 1, #Route.Stages - 1 do
	for k, frac in { 0.3, 0.7 } do
		local side = if (i + k) % 2 == 0 then 1 else -1
		table.insert(herds, {
			Stage = i,
			Center = (Route.OffsetPoint(stageMid(i, frac), side * 185)),
		})
	end
end
Layout.Herds = herds

-- PvE zones: each stage minus its towns.
local zones: { Zone } = {}
for i, stage in Route.Stages do
	local a, b = Route.StageStartDist(stage), Route.StageEndDist(stage)
	local cuts: { { number } } = {}
	for _, town in towns do
		if town.Dist1 > a and town.Dist0 < b then
			table.insert(cuts, { town.Dist0 - 40, town.Dist1 + 40 })
		end
	end
	if i == 1 then
		table.insert(cuts, { 0, Layout.StartDist + 420 })
	end
	table.sort(cuts, function(p, q)
		return p[1] < q[1]
	end)
	local cursor = a
	for _, cut in cuts do
		if cut[1] - cursor > 200 then
			table.insert(zones, { Stage = i, Dist0 = cursor, Dist1 = cut[1], Level = stage.EnemyLevel })
		end
		cursor = math.max(cursor, cut[2])
	end
	if b - cursor > 200 then
		table.insert(zones, { Stage = i, Dist0 = cursor, Dist1 = b, Level = stage.EnemyLevel })
	end
end
Layout.Zones = zones

-- Flattened pads used by the heightfield.
local flats: { Flat } = {}
for _, town in towns do
	-- Towns follow the trail, so split each into short straight pieces.
	local pieces = math.max(1, math.ceil((town.Dist1 - town.Dist0) / 60))
	for k = 0, pieces - 1 do
		local d0 = town.Dist0 + (town.Dist1 - town.Dist0) * k / pieces
		local d1 = town.Dist0 + (town.Dist1 - town.Dist0) * (k + 1) / pieces
		table.insert(flats, {
			A = (Route.PointAt(d0)),
			B = (Route.PointAt(d1)),
			Radius = town.HalfWidth,
			Fall = 60,
			Raise = 0,
			Follow = true,
		})
	end
end
for _, arena in arenas do
	table.insert(flats, { A = arena.Center, B = arena.Center, Radius = arena.Radius + 8, Fall = 50, Raise = 0 })
end
table.insert(flats, {
	A = Layout.PvPArena.Center,
	B = Layout.PvPArena.Center,
	Radius = Layout.PvPArena.Radius + 10,
	Fall = 50,
	Raise = 0,
})
for _, lm in landmarks do
	if lm.Kind == "WindmillFarm" or lm.Kind == "OldFort" or lm.Kind == "Lighthouse" then
		table.insert(flats, { A = lm.Position, B = lm.Position, Radius = 46, Fall = 40, Raise = 0 })
	end
end
-- Start grandstand pad.
table.insert(flats, {
	A = (Route.PointAt(Layout.StartDist - 40)),
	B = (Route.PointAt(Layout.StartDist + 60)),
	Radius = 46,
	Fall = 40,
	Raise = 0,
})
Layout.Flats = flats

-- Spatial bucket of flats by X for quick lookup.
local BUCKET = 256
local flatBuckets: { [number]: { Flat } } = {}
for _, f in flats do
	local minX = math.min(f.A.X, f.B.X) - f.Radius - f.Fall
	local maxX = math.max(f.A.X, f.B.X) + f.Radius + f.Fall
	for bx = math.floor(minX / BUCKET), math.floor(maxX / BUCKET) do
		flatBuckets[bx] = flatBuckets[bx] or {}
		table.insert(flatBuckets[bx], f)
	end
end

local EMPTY: { Flat } = {}
function Layout.FlatsNear(x: number): { Flat }
	return flatBuckets[math.floor(x / BUCKET)] or EMPTY
end

-- Distance from point P to segment AB in XZ, and the parameter along AB.
function Layout.SegmentDistance(px: number, pz: number, a: Vector3, b: Vector3): (number, number)
	local abx, abz = b.X - a.X, b.Z - a.Z
	local len2 = abx * abx + abz * abz
	local t = 0
	if len2 > 1e-6 then
		t = math.clamp(((px - a.X) * abx + (pz - a.Z) * abz) / len2, 0, 1)
	end
	local cx, cz = a.X + abx * t, a.Z + abz * t
	return math.sqrt((px - cx) ^ 2 + (pz - cz) ^ 2), t
end

function Layout.TownAt(pos: Vector3): Town?
	local d, lateral = Route.Project(pos)
	for _, town in towns do
		if d >= town.Dist0 - 10 and d <= town.Dist1 + 10 and math.abs(lateral) <= town.HalfWidth + 10 then
			return town
		end
	end
	return nil
end

function Layout.NearestTownBefore(d: number): Town
	local best = towns[1]
	for _, town in towns do
		if town.Dist0 <= d then
			best = town
		end
	end
	return best
end

function Layout.ArenaAt(pos: Vector3): Arena?
	for _, arena in arenas do
		if (xz(pos) - arena.Center).Magnitude <= arena.Radius then
			return arena
		end
	end
	return nil
end

function Layout.InPvPArena(pos: Vector3): boolean
	return (xz(pos) - Layout.PvPArena.Center).Magnitude <= Layout.PvPArena.Radius
end

function Layout.ZoneAtDist(d: number): Zone?
	for _, z in zones do
		if d >= z.Dist0 and d <= z.Dist1 then
			return z
		end
	end
	return nil
end

return Layout
