--!strict
-- Lays out each town along its stretch of trail, which doubles as main street.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local PartUtil = require(ReplicatedStorage.Builders.PartUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Route = require(ReplicatedStorage.Shared.Route)
local Layout = require(ReplicatedStorage.Shared.Layout)
local HeightField = require(ReplicatedStorage.Shared.HeightField)
local Buildings = require(script.Parent.PrefabsBuildings)
local Props = require(script.Parent.PrefabsProps)
local Nature = require(script.Parent.PrefabsNature)

local TownBuilder = {}

local STREET_EDGE = Config.Map.TrailHalfWidth + 7

type Builder = (Random, CFrame, Instance) -> Buildings.BuildingInfo

-- Ground CFrame at (d, lateral) with -Z facing the street.
local function lotFrame(d: number, lateral: number): CFrame
	local p, t = Route.OffsetPoint(d, lateral)
	local y = HeightField.Surface(p.X, p.Z)
	local right = t:Cross(Vector3.yAxis)
	local side = if lateral >= 0 then 1 else -1
	local pos = Vector3.new(p.X, y, p.Z)
	return CFrame.lookAt(pos, pos - right * side)
end

-- Props along the street edge in front of a building.
local function streetFurniture(rng: Random, _town: Layout.Town, d: number, side: number, parent: Instance)
	local cf = lotFrame(d, side * (STREET_EDGE - 1.5))
	local roll = rng:NextNumber()
	if roll < 0.35 then
		Props.buildHitchingPost(rng, cf, parent)
		Props.buildTrough(rng, cf * CFrame.new(5, 0, 0.5), parent)
	elseif roll < 0.55 then
		Props.buildLampPost(rng, cf, parent)
	elseif roll < 0.7 then
		Props.buildBarrel(rng, cf * CFrame.new(rng:NextNumber(-2, 2), 0, 0), parent)
		Props.buildCrate(rng, cf * CFrame.new(rng:NextNumber(2, 4), 0, 0.5) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), parent)
	elseif roll < 0.85 then
		Props.buildBench(rng, cf * CFrame.Angles(0, math.pi, 0), parent)
	end
end

local function frontierTown(town: Layout.Town, rng: Random, parent: Instance)
	local required: { { Builder } } = {
		{ Buildings.buildSaloon, Buildings.buildBank, Buildings.buildHotel },
		{ Buildings.buildStable, Buildings.buildGeneralStore, Buildings.buildSheriffOffice, Buildings.buildBlacksmith },
	}
	for sideIndex, side in { -1, 1 } do
		local queue = required[sideIndex]
		local cursor = town.Dist0 + 16
		local index = 1
		while cursor < town.Dist1 - 14 do
			local builder: Builder = queue[index] or Buildings.buildHouse
			-- Build at a temporary frame first to learn the width, then place.
			local lot = lotFrame(cursor + 12, side * STREET_EDGE)
			local info = builder(rng, lot, parent)
			local half = info.Width / 2
			local placed = lotFrame(cursor + half, side * STREET_EDGE)
			info.Model:PivotTo(placed * lot:Inverse() * info.Model:GetPivot())
			streetFurniture(rng, town, cursor + half, side, parent)
			cursor += info.Width + rng:NextNumber(3, 7)
			if builder == Buildings.buildStable then
				cursor += 18 -- room for the paddock
			end
			index += 1
		end
	end
	-- Quest board and well in the middle of town, water tower behind it.
	local mid = (town.Dist0 + town.Dist1) / 2
	Props.buildQuestBoard(rng, lotFrame(mid - 6, -(STREET_EDGE - 3)) * CFrame.Angles(0, math.pi, 0), parent, town.Index)
	Props.buildWell(rng, lotFrame(mid + 10, STREET_EDGE - 4), parent)
	Props.buildWaterTower(rng, lotFrame(mid, (STREET_EDGE + 38)), parent)
	for _ = 1, 4 do
		local d = rng:NextNumber(town.Dist0, town.Dist1)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		Props.buildWagon(rng, lotFrame(d, side * (STREET_EDGE + rng:NextNumber(30, 45))) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), parent)
	end
	-- Fence lines behind the lots.
	for _, side in { -1, 1 } do
		local d = town.Dist0
		while d < town.Dist1 - 20 do
			local a = lotFrame(d, side * (town.HalfWidth - 4)).Position
			local b = lotFrame(d + 20, side * (town.HalfWidth - 4)).Position
			if rng:NextNumber() < 0.7 then
				Props.buildFence(rng, a, b, parent)
			end
			d += 20
		end
	end
end

local function city(town: Layout.Town, rng: Random, parent: Instance)
	local clock = Layout.Landmarks[9]
	local plazaD = clock.Dist
	local plazaSide = if clock.Lateral >= 0 then 1 else -1
	local signs = { "HOTEL", "BANK", "THEATRE", "GAZETTE", "TAILOR", "PHARMACY", "TELEGRAPH", "OPERA", "MARKET", "CLUB" }
	for _, side in { -1, 1 } do
		for row = 0, 1 do
			local offset = STREET_EDGE + row * 34
			local cursor = town.Dist0 + 30
			while cursor < town.Dist1 - 30 do
				local inPlaza = side == plazaSide and math.abs(cursor - plazaD) < 46
				if inPlaza then
					cursor += 8
				else
					local label = if row == 0 and rng:NextNumber() < 0.5 then signs[rng:NextInteger(1, #signs)] else nil
					local lot = lotFrame(cursor + 10, side * offset)
					local info = Buildings.buildBrick(rng, lot, parent, label)
					local half = info.Width / 2
					local placed = lotFrame(cursor + half, side * offset)
					info.Model:PivotTo(placed * lot:Inverse() * info.Model:GetPivot())
					if row == 0 and rng:NextNumber() < 0.6 then
						Props.buildLampPost(rng, lotFrame(cursor + half, side * (STREET_EDGE - 2)), parent)
					end
					cursor += info.Width + rng:NextNumber(0.5, 2)
				end
			end
		end
	end
	-- Plaza with the clock tower, trees and benches.
	local plazaCenter = lotFrame(plazaD, plazaSide * 50)
	PartUtil.part({
		Name = "Plaza",
		Size = Vector3.new(80, 1, 80),
		CFrame = plazaCenter * CFrame.new(0, -0.4, 0),
		Color = Color3.fromRGB(170, 160, 146),
		Material = Enum.Material.Cobblestone,
		Parent = parent,
	})
	local tower, hands = Buildings.buildClockTower(rng, plazaCenter * CFrame.new(0, 0, 12), parent)
	tower:SetAttribute("Landmark", "ClockTower")
	for _, hand in hands do
		CollectionService:AddTag(hand, "SBR_ClockHand")
	end
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = plazaCenter * CFrame.new(math.cos(a) * 30, 0, math.sin(a) * 30 - 4)
		if i % 2 == 0 then
			Nature.buildTree(rng, p, parent, 0.8)
		else
			Props.buildBench(rng, CFrame.lookAt(p.Position, plazaCenter.Position), parent)
			Props.buildLampPost(rng, p * CFrame.new(3, 0, 0), parent)
		end
	end
	Props.buildQuestBoard(rng, plazaCenter * CFrame.new(-14, 0, -24), parent, town.Index)
	-- Stable and store on the edge of the city.
	Buildings.buildStable(rng, lotFrame(town.Dist0 + 6, -plazaSide * (STREET_EDGE + 70)), parent)
	Buildings.buildGeneralStore(rng, lotFrame(town.Dist0 + 48, -plazaSide * (STREET_EDGE + 70)), parent)
end

function TownBuilder.Build(parent: Instance, onProgress: ((number) -> ())?)
	local folder = PartUtil.folder("Towns", parent)
	for i, town in Layout.Towns do
		local rng = Random.new(Config.Map.Seed * 31 + i)
		local townFolder = PartUtil.folder(town.Name, folder)
		townFolder:SetAttribute("Town", town.Index)
		if town.Kind == "City" then
			city(town, rng, townFolder)
		else
			frontierTown(town, rng, townFolder)
		end
		-- Respawn point at the town entrance.
		local spawnCF = lotFrame(town.Dist0 + 30, 0)
		local spawnPart = PartUtil.part({
			Name = "TownSpawn",
			Size = Vector3.new(6, 1, 6),
			CFrame = spawnCF * CFrame.new(0, -0.45, 0),
			Transparency = 1,
			Decor = true,
			Parent = townFolder,
		})
		spawnPart:SetAttribute("Town", town.Index)
		CollectionService:AddTag(spawnPart, "SBR_TownSpawn")
		-- Town name sign at both ends.
		for _, d in { town.Dist0 - 8, town.Dist1 + 8 } do
			local cf = lotFrame(d, STREET_EDGE + 2)
			PartUtil.part({ Name = "TownSignPost", Size = Vector3.new(0.6, 7, 0.6), CFrame = cf * CFrame.new(0, 3.5, 0), Color = Color3.fromRGB(110, 80, 56), Material = Enum.Material.WoodPlanks, Parent = townFolder })
			local board = PartUtil.part({ Name = "TownSign", Size = Vector3.new(0.3, 2, 8), CFrame = cf * CFrame.new(0, 6, 0), Color = Color3.fromRGB(46, 34, 26), Material = Enum.Material.WoodPlanks, Decor = true, Parent = townFolder })
			Buildings.sign(board, town.Name:upper(), Color3.fromRGB(236, 230, 216), Enum.NormalId.Left)
			Buildings.sign(board, town.Name:upper(), Color3.fromRGB(236, 230, 216), Enum.NormalId.Right)
		end
		if onProgress then
			onProgress(i / #Layout.Towns)
		end
		task.wait()
	end
	return folder
end

return TownBuilder
