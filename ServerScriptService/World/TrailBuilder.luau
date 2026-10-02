--!strict
-- Wheel ruts, mile markers, the river bridge and the invisible boundary that
-- keeps riders inside the playable band. Runs after the terrain exists so it
-- can raycast onto the real surface.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtil = require(ReplicatedStorage.Builders.PartUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Route = require(ReplicatedStorage.Shared.Route)
local Layout = require(ReplicatedStorage.Shared.Layout)
local HeightField = require(ReplicatedStorage.Shared.HeightField)
local Props = require(script.Parent.PrefabsProps)

local TrailBuilder = {}

local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { workspace.Terrain }
terrainOnly.IgnoreWater = true

function TrailBuilder.GroundAt(x: number, z: number): (number, Vector3)
	local result = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -4000, 0), terrainOnly)
	if result then
		return result.Position.Y, result.Normal
	end
	return HeightField.Surface(x, z), Vector3.yAxis
end

local function inBridge(d: number): boolean
	local r = Layout.River
	return math.abs(d - r.Dist) < r.HalfWidth + r.BankWidth + 14
end

function TrailBuilder.Build(parent: Instance, onProgress: ((number) -> ())?)
	local folder = PartUtil.folder("Trail", parent)
	local ruts = PartUtil.folder("Ruts", folder)
	local seg = Config.Map.RutSegmentLength
	local total = Route.Length
	local rutColor = Color3.fromRGB(150, 122, 92)
	local d = 0
	local count = 0
	local chunkModel = PartUtil.model("RutChunk", ruts)
	while d < total - seg do
		if not inBridge(d + seg / 2) then
			local a = Route.PointAt(d)
			local b = Route.PointAt(d + seg)
			local _, t = Route.PointAt(d + seg / 2)
			local right = t:Cross(Vector3.yAxis)
			for _, side in { -1, 1 } do
				local off = right * side * 2.6
				local ya = TrailBuilder.GroundAt(a.X + off.X, a.Z + off.Z)
				local yb = TrailBuilder.GroundAt(b.X + off.X, b.Z + off.Z)
				local pa = Vector3.new(a.X + off.X, ya + 0.06, a.Z + off.Z)
				local pb = Vector3.new(b.X + off.X, yb + 0.06, b.Z + off.Z)
				PartUtil.beamBetween(pa, pb, 1.1, 0.12, {
					Name = "Rut",
					Color = rutColor,
					Material = Enum.Material.Ground,
					Decor = true,
					Parent = chunkModel,
				})
			end
		end
		d += seg
		count += 1
		if count % 40 == 0 then
			chunkModel = PartUtil.model("RutChunk", ruts)
			if onProgress then
				onProgress(d / total * 0.6)
			end
			task.wait()
		end
	end

	-- Mile markers on alternating sides.
	local markers = PartUtil.folder("MileMarkers", folder)
	local mile = 1
	local md = Config.Map.MileMarkerSpacing
	while md < total - 50 do
		if not inBridge(md) and not Layout.TownAt((Route.PointAt(md))) then
			local side = if mile % 2 == 0 then 1 else -1
			local p, t = Route.OffsetPoint(md, side * (Config.Map.TrailHalfWidth + 3))
			local y = TrailBuilder.GroundAt(p.X, p.Z)
			local pos = Vector3.new(p.X, y, p.Z)
			Props.buildMileMarker(CFrame.lookAt(pos, pos - t), markers, mile)
		end
		mile += 1
		md += Config.Map.MileMarkerSpacing
	end
	if onProgress then
		onProgress(0.7)
	end

	-- Bridge over the river.
	local river = Layout.River
	local reach = river.HalfWidth + river.BankWidth + 12
	local deckA = Route.PointAt(river.Dist - reach)
	local deckB = Route.PointAt(river.Dist + reach)
	local deckY = HeightField.TrailHeight(river.CenterX) + 0.4
	Props.buildBridge(
		Random.new(Config.Map.Seed + 3),
		Vector3.new(deckA.X, deckY, deckA.Z),
		Vector3.new(deckB.X, deckY, deckB.Z),
		Config.Map.TrailHalfWidth * 2 + 4,
		HeightField.TrailHeight(river.CenterX) - river.WaterDrop,
		folder
	)

	-- Invisible walls along the band edges and at the ocean.
	local walls = PartUtil.folder("Boundary", folder)
	local step = 96
	local wd = 0
	while wd < total do
		local p0, _ = Route.PointAt(wd)
		local p1, _ = Route.PointAt(math.min(total, wd + step))
		for _, side in { -1, 1 } do
			local _, t0 = Route.PointAt(wd)
			local _, t1 = Route.PointAt(math.min(total, wd + step))
			local a = p0 + t0:Cross(Vector3.yAxis) * side * (Config.Map.CorridorHalfWidth - 20)
			local b = p1 + t1:Cross(Vector3.yAxis) * side * (Config.Map.CorridorHalfWidth - 20)
			local mid = (a + b) / 2
			local wall = PartUtil.part({
				Name = "Wall",
				Size = Vector3.new(4, 1200, (b - a).Magnitude + 8),
				CFrame = CFrame.lookAt(mid, b),
				Transparency = 1,
				Anchored = true,
				CanCollide = true,
				Parent = walls,
			})
			wall.CanQuery = false
			wall.CanTouch = false
			wall.CastShadow = false
		end
		wd += step
	end
	local startP = Route.PointAt(0)
	for _, x in { Route.MinX - Config.Map.OceanWidth + 40, Route.MaxX + 30 } do
		local wall = PartUtil.part({
			Name = "EndWall",
			Size = Vector3.new(4, 1200, Config.Map.CorridorHalfWidth * 2 + 200),
			CFrame = CFrame.new(x, 0, if x < 0 then startP.Z else Route.ZAt(Route.MaxX)),
			Transparency = 1,
			Anchored = true,
			CanCollide = true,
			Parent = walls,
		})
		wall.CanQuery = false
		wall.CanTouch = false
	end
	if onProgress then
		onProgress(1)
	end
	return folder
end

return TrailBuilder
