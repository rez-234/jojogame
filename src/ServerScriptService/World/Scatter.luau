--!strict
-- Scatters biome props on a jittered grid. Props are placed by raycasting onto
-- the generated terrain and never land on the trail, in towns, in water or on
-- steep slopes. Each grid row is grouped into its own Model chunk.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtil = require(ReplicatedStorage.Builders.PartUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Route = require(ReplicatedStorage.Shared.Route)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Nature = require(script.Parent.PrefabsNature)
local Props = require(script.Parent.PrefabsProps)
local Buildings = require(script.Parent.PrefabsBuildings)
local HeightField = require(ReplicatedStorage.Shared.HeightField)

local Scatter = {}

local CELL = 34
-- Expected props per cell for a stage density of 1.0.
local DENSITY = 0.09
local MAX_SLOPE = 30

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Include
params.FilterDescendantsInstances = { workspace.Terrain }
params.IgnoreWater = false

type Placer = (Random, CFrame, Instance) -> Instance?

local PLACERS: { [string]: Placer } = {
	Cactus = function(rng, cf, parent)
		return Nature.buildCactus(rng, cf, parent)
	end,
	Rock = function(rng, cf, parent)
		return Nature.buildRock(rng, cf, parent)
	end,
	Mesa = function(rng, cf, parent)
		return Nature.buildMesa(rng, cf, parent)
	end,
	Tree = function(rng, cf, parent)
		return Nature.buildTree(rng, cf, parent)
	end,
	Pine = function(rng, cf, parent)
		return Nature.buildPine(rng, cf, parent)
	end,
	DeadTree = function(rng, cf, parent)
		return Nature.buildDeadTree(rng, cf, parent)
	end,
	Tumbleweed = function(rng, cf, parent)
		return Nature.buildTumbleweed(rng, cf, parent)
	end,
	Palm = function(rng, cf, parent)
		return Nature.buildPalm(rng, cf, parent)
	end,
	Reeds = function(rng, cf, parent)
		return Nature.buildReeds(rng, cf, parent)
	end,
	Haystack = function(rng, cf, parent)
		return Nature.buildHaystack(rng, cf, parent)
	end,
	Driftwood = function(rng, cf, parent)
		return Nature.buildDriftwood(rng, cf, parent)
	end,
	Wagon = function(rng, cf, parent)
		return Props.buildWagon(rng, cf, parent)
	end,
	Camp = function(rng, cf, parent)
		return Props.buildCamp(rng, cf, parent)
	end,
	Lantern = function(rng, cf, parent)
		return Props.buildLantern(rng, cf, parent)
	end,
	Fence = function(rng, cf, parent)
		local a = cf.Position
		local b = (cf * CFrame.new(rng:NextNumber(14, 30), 0, 0)).Position
		return Props.buildFence(rng, a, b, parent)
	end,
	Farm = function(rng, cf, parent)
		local m = PartUtil.model("Farmstead", parent)
		Buildings.buildHouse(rng, cf, m)
		Nature.buildHaystack(rng, cf * CFrame.new(14, 0, 4), m)
		Props.buildWindmill(rng, cf * CFrame.new(-14, 0, 10), m)
		return m
	end,
}

-- Props that need clearance from the trail (big footprint).
local CLEARANCE: { [string]: number } = {
	Mesa = 140,
	Farm = 60,
	Camp = 30,
	Wagon = 24,
	Fence = 24,
	Pine = 16,
	Tree = 16,
}

-- Props that may also sit in shallow water or on the shore.
local WET_OK: { [string]: boolean } = { Reeds = true, Driftwood = true }

local function nearFlat(x: number, z: number, margin: number): boolean
	for _, flat in Layout.FlatsNear(x) do
		local d = Layout.SegmentDistance(x, z, flat.A, flat.B)
		if d < flat.Radius + margin then
			return true
		end
	end
	return false
end

function Scatter.Build(parent: Instance, onProgress: ((number) -> ())?)
	local folder = PartUtil.folder("Props", parent)
	local rng = Random.new(Config.Map.Seed * 7 + 1)
	local half = Config.Map.CorridorHalfWidth - 150
	local x = Route.MinX
	local rowIndex = 0
	local placed = 0
	-- Sorted kind list per stage so iteration order is deterministic.
	local stageKinds: { [number]: { { Kind: string, Weight: number } } } = {}
	for _, stage in Route.Stages do
		local list = {}
		for kind, w in stage.Props do
			table.insert(list, { Kind = kind, Weight = w })
		end
		table.sort(list, function(a, b)
			return a.Kind < b.Kind
		end)
		stageKinds[stage.Index] = list
	end
	while x < Route.MaxX do
		local row = PartUtil.model("PropChunk", folder)
		row.ModelStreamingMode = Enum.ModelStreamingMode.Default
		local zc = Route.ZAt(x)
		local stage = Route.StageAtX(x)
		local total = 0
		for _, entry in stageKinds[stage.Index] do
			total += entry.Weight
		end
		local z = zc - half
		while z < zc + half do
			local expected = total * DENSITY
			local count = math.floor(expected) + (if rng:NextNumber() < expected % 1 then 1 else 0)
			for _ = 1, count do
				local px = x + rng:NextNumber(0, CELL)
				local pz = z + rng:NextNumber(0, CELL)
				-- Weighted pick by stage.
				local roll = rng:NextNumber() * total
				local kind: string? = nil
				for _, entry in stageKinds[stage.Index] do
					roll -= entry.Weight
					if roll <= 0 then
						kind = entry.Kind
						break
					end
				end
				if kind then
					local dist = Route.DistanceFromTrail(px, pz)
					local clearance = Config.Map.TrailHalfWidth + 8 + (CLEARANCE[kind] or 0)
					if dist > clearance and not nearFlat(px, pz, 12) then
						local hit = workspace:Raycast(Vector3.new(px, 1500, pz), Vector3.new(0, -3000, 0), params)
						if hit then
							local slope = math.deg(math.acos(math.clamp(hit.Normal.Y, -1, 1)))
							local wet = hit.Material == Enum.Material.Water
							if slope <= MAX_SLOPE and (not wet or WET_OK[kind]) then
								local yaw = rng:NextNumber(0, math.pi * 2)
								local cf: CFrame
								if kind == "Rock" or kind == "Tumbleweed" or kind == "Driftwood" then
									-- Align to the surface normal.
									local up = hit.Normal
									local fwd = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
									local rightVec = fwd:Cross(up).Unit
									local look = up:Cross(rightVec).Unit
									cf = CFrame.fromMatrix(hit.Position, rightVec, up, -look)
								else
									cf = CFrame.new(hit.Position) * CFrame.Angles(0, yaw, 0)
								end
								local placer = PLACERS[kind]
								if placer then
									placer(rng, cf, row)
									placed += 1
								end
							end
						end
					end
				end
			end
			z += CELL
		end
		x += CELL
		rowIndex += 1
		if rowIndex % 2 == 0 then
			if onProgress then
				onProgress((x - Route.MinX) / (Route.MaxX - Route.MinX))
			end
			task.wait()
		end
	end
	-- Palms and driftwood along the beach.
	local beach = PartUtil.model("Shoreline", folder)
	for i = 0, 40 do
		local pz = Route.ZAt(Route.MinX) - 300 + i * 15
		local shore = HeightField.ShoreX(pz)
		local px = shore + rng:NextNumber(30, 120)
		local hit = workspace:Raycast(Vector3.new(px, 500, pz), Vector3.new(0, -1000, 0), params)
		if hit and hit.Material ~= Enum.Material.Water and Route.DistanceFromTrail(px, pz) > 20 and not nearFlat(px, pz, 8) then
			if i % 3 == 0 then
				Nature.buildPalm(rng, CFrame.new(hit.Position), beach)
			else
				Nature.buildDriftwood(rng, CFrame.new(hit.Position), beach)
			end
		end
	end
	return folder, placed
end

return Scatter
