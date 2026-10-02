--!strict
-- Writes the landscape into Terrain with WriteVoxels, chunk by chunk, from the
-- deterministic HeightField. Materials are painted by stage, slope, height and
-- distance to water and trail.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Route = require(ReplicatedStorage.Shared.Route)
local HeightField = require(ReplicatedStorage.Shared.HeightField)

local TerrainGen = {}

local RES = Config.Map.VoxelResolution
local CHUNK = Config.Map.ChunkSize
local COLS = CHUNK // RES
local HALF = Config.Map.CorridorHalfWidth
local SEED = Config.Map.Seed

local M = Enum.Material

local function setColors(terrain: Terrain)
	terrain:SetMaterialColor(M.Sand, Color3.fromRGB(214, 190, 146))
	terrain:SetMaterialColor(M.Sandstone, Color3.fromRGB(184, 104, 66))
	terrain:SetMaterialColor(M.Salt, Color3.fromRGB(222, 206, 178))
	terrain:SetMaterialColor(M.Limestone, Color3.fromRGB(206, 194, 168))
	terrain:SetMaterialColor(M.Rock, Color3.fromRGB(122, 112, 104))
	terrain:SetMaterialColor(M.Slate, Color3.fromRGB(96, 98, 94))
	terrain:SetMaterialColor(M.Grass, Color3.fromRGB(116, 132, 74))
	terrain:SetMaterialColor(M.LeafyGrass, Color3.fromRGB(88, 112, 62))
	terrain:SetMaterialColor(M.Ground, Color3.fromRGB(134, 104, 74))
	terrain:SetMaterialColor(M.Mud, Color3.fromRGB(96, 78, 60))
	terrain:SetMaterialColor(M.Snow, Color3.fromRGB(236, 240, 244))
	terrain:SetMaterialColor(M.Cobblestone, Color3.fromRGB(150, 140, 128))
	terrain.WaterColor = Color3.fromRGB(58, 96, 106)
	terrain.WaterTransparency = 0.6
	terrain.WaterReflectance = 0.3
	terrain.WaterWaveSize = 0.12
	terrain.WaterWaveSpeed = 8
end

local function surfaceMaterial(x: number, z: number, h: number, slope: number, dist: number, water: number?): Enum.Material
	local a, b, t = Route.StageBlend(x, 200)
	-- Dithered blend between neighboring stages.
	local stage = if Util.hash01(math.floor(x / 4), math.floor(z / 4), 7) < t then b else a
	local wobble = math.noise(x / 9, z / 9, SEED + 1) * 1.5
	if dist < Config.Map.TrailHalfWidth + wobble then
		return if stage.Kind == "City" then M.Cobblestone else M.Ground
	end
	if dist < Config.Map.TrailHalfWidth + 3 + wobble and math.noise(x / 5, z / 5, SEED + 2) > 0 then
		return M.Ground
	end
	if water and h < water + 2.5 then
		return if stage.Kind == "Beach" then M.Sand else M.Mud
	end
	if stage.Kind == "Mountain" and h > Config.Map.SnowLine + math.noise(x / 40, z / 40, SEED + 3) * 25 then
		return if slope > 50 then M.Rock else M.Snow
	end
	if slope > 44 then
		return stage.Cliff
	end
	if slope > 32 then
		return if math.noise(x / 20, z / 20, SEED + 4) > 0 then stage.Cliff else stage.SurfaceB
	end
	local patch = math.noise(x / 70, z / 70, SEED + 5) + math.noise(x / 17, z / 17, SEED + 6) * 0.35
	if stage.Kind == "Beach" then
		local shore = HeightField.ShoreX(z)
		if x < shore + 260 then
			return M.Sand
		end
	end
	if stage.Kind == "City" then
		return if patch > 0.25 then M.Ground else M.Grass
	end
	return if patch > 0.2 then stage.SurfaceB else stage.SurfaceA
end

local function deepMaterial(x: number): Enum.Material
	local stage = Route.StageAtX(x)
	if stage.Kind == "Desert" or stage.Kind == "Canyon" then
		return M.Sandstone
	end
	return M.Rock
end

local function subMaterial(surface: Enum.Material): Enum.Material
	if surface == M.Grass or surface == M.LeafyGrass then
		return M.Ground
	elseif surface == M.Sand or surface == M.Salt then
		return M.Sandstone
	elseif surface == M.Snow then
		return M.Rock
	end
	return surface
end

-- Every chunk origin (X, Z) that overlaps the playable band or the ocean.
local function chunkList(): { Vector2 }
	local list: { Vector2 } = {}
	local x0 = math.floor((Route.MinX - Config.Map.OceanWidth) / CHUNK) * CHUNK
	local x1 = math.ceil(Route.MaxX / CHUNK) * CHUNK + CHUNK
	local x = x0
	while x < x1 do
		local zA = Route.ZAt(math.clamp(x, Route.MinX, Route.MaxX))
		local zB = Route.ZAt(math.clamp(x + CHUNK, Route.MinX, Route.MaxX))
		local zMin = math.min(zA, zB) - HALF
		local zMax = math.max(zA, zB) + HALF
		local z = math.floor(zMin / CHUNK) * CHUNK
		while z < zMax do
			table.insert(list, Vector2.new(x, z))
			z += CHUNK
		end
		x += CHUNK
	end
	return list
end

local function writeChunk(terrain: Terrain, origin: Vector2)
	local x0, z0 = origin.X, origin.Y
	-- Heights on a grid with a one cell border for slope estimates.
	local heights: { { number } } = {}
	local waters: { { number? } } = {}
	local dists: { { number } } = {}
	local minH, maxH = math.huge, -math.huge
	for i = 0, COLS + 1 do
		local row: { number } = {}
		local wrow: { number? } = {}
		local drow: { number } = {}
		for k = 0, COLS + 1 do
			local cx = x0 + (i - 0.5) * RES
			local cz = z0 + (k - 0.5) * RES
			local h = HeightField.Surface(cx, cz)
			row[k] = h
			if i >= 1 and i <= COLS and k >= 1 and k <= COLS then
				local w = HeightField.WaterLevel(cx, cz)
				wrow[k] = w
				drow[k] = Route.DistanceFromTrail(cx, cz)
				minH = math.min(minH, h)
				maxH = math.max(maxH, h, w or -math.huge)
			end
		end
		heights[i] = row
		waters[i] = wrow
		dists[i] = drow
	end

	local yMin = math.floor((minH - Config.Map.BedrockDepth) / RES) * RES
	local yMax = math.ceil((maxH + RES) / RES) * RES
	local ny = math.max(1, (yMax - yMin) // RES)

	local materials: { { { Enum.Material } } } = table.create(COLS)
	local occupancy: { { { number } } } = table.create(COLS)
	for i = 1, COLS do
		local matX: { { Enum.Material } } = table.create(ny)
		local occX: { { number } } = table.create(ny)
		for j = 1, ny do
			matX[j] = table.create(COLS, M.Air)
			occX[j] = table.create(COLS, 0)
		end
		materials[i] = matX
		occupancy[i] = occX
	end

	local deep = deepMaterial(x0 + CHUNK / 2)
	for i = 1, COLS do
		for k = 1, COLS do
			local h = heights[i][k]
			local cx = x0 + (i - 0.5) * RES
			local cz = z0 + (k - 0.5) * RES
			local dx = (heights[i + 1][k] - heights[i - 1][k]) / (2 * RES)
			local dz = (heights[i][k + 1] - heights[i][k - 1]) / (2 * RES)
			local slope = math.deg(math.atan(math.sqrt(dx * dx + dz * dz)))
			local water = waters[i][k]
			local surface = surfaceMaterial(cx, cz, h, slope, dists[i][k], water)
			local sub = subMaterial(surface)
			for j = 1, ny do
				local bottom = yMin + (j - 1) * RES
				local occ = math.clamp((h - bottom) / RES, 0, 1)
				if occ > 0 then
					local depth = h - (bottom + RES)
					local mat = surface
					if depth > 6 then
						mat = deep
					elseif depth > 2 then
						mat = sub
					end
					materials[i][j][k] = mat
					occupancy[i][j][k] = math.max(occ, 0.05)
				end
				if water and bottom < water and occ < 0.5 then
					materials[i][j][k] = M.Water
					occupancy[i][j][k] = 1
				end
			end
		end
	end

	local region = Region3.new(Vector3.new(x0, yMin, z0), Vector3.new(x0 + CHUNK, yMin + ny * RES, z0 + CHUNK))
	terrain:WriteVoxels(region, RES, materials, occupancy)
end

function TerrainGen.Generate(onProgress: ((number) -> ())?)
	local terrain = workspace.Terrain
	terrain:Clear()
	setColors(terrain)
	local chunks = chunkList()
	local perYield = Config.Map.ChunksPerYield
	for index, origin in chunks do
		writeChunk(terrain, origin)
		if index % perYield == 0 then
			if onProgress then
				onProgress(index / #chunks)
			end
			task.wait()
		end
	end
	if onProgress then
		onProgress(1)
	end
end

return TerrainGen
