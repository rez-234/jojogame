--!strict
-- One unique landmark per stage, plus the start line, checkpoint gates,
-- finish arch, boss arenas and the ranked PvP arena.

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

local Landmarks = {}

local WOOD = Enum.Material.WoodPlanks

local function model(name: string, parent: Instance): Model
	local m = PartUtil.model(name, parent)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return m
end

local function part(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, decor: boolean?, shape: Enum.PartType?): Part
	return PartUtil.part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material or WOOD,
		Decor = decor,
		Shape = shape,
		Parent = m,
	})
end

local function cyl(m: Model, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material?, decor: boolean?): Part
	return PartUtil.cylinderBetween(a, b, d, { Name = name, Color = color, Material = material or WOOD, Decor = decor, Parent = m })
end

-- Ground CFrame on the trail at distance d, facing along the route.
local function trailFrame(d: number, lateral: number?): CFrame
	local p, t = Route.OffsetPoint(d, lateral or 0)
	local y = HeightField.Surface(p.X, p.Z)
	return CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(p.X, y, p.Z) + t)
end
Landmarks.TrailFrame = trailFrame

function Landmarks.buildStartLine(parent: Instance): Model
	local m = model("StartLine", parent)
	local cf = trailFrame(Layout.StartDist)
	local half = Config.Map.TrailHalfWidth + 6
	-- Painted line and banner.
	part(m, "Line", Vector3.new(half * 2, 0.1, 1.4), cf * CFrame.new(0, 0.1, 0), Color3.fromRGB(236, 230, 216), Enum.Material.SmoothPlastic, true)
	for i = 0, 11 do
		if i % 2 == 0 then
			part(m, "Check", Vector3.new(half * 2 / 12, 0.12, 0.7), cf * CFrame.new(-half + (i + 0.5) * half * 2 / 12, 0.12, -0.35), Color3.fromRGB(30, 26, 22), Enum.Material.SmoothPlastic, true)
			part(m, "Check", Vector3.new(half * 2 / 12, 0.12, 0.7), cf * CFrame.new(-half + (i + 1.5) * half * 2 / 12, 0.12, 0.35), Color3.fromRGB(30, 26, 22), Enum.Material.SmoothPlastic, true)
		end
	end
	Props.buildGate(cf * CFrame.Angles(0, math.pi, 0), m, "STEEL BALL RUN", "SAN DIEGO START")
	-- Grandstand beside the line.
	local standCF = cf * CFrame.new(half + 14, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	local wood = Color3.fromRGB(140, 108, 76)
	for row = 0, 5 do
		part(m, "Tier", Vector3.new(40, 1, 3), standCF * CFrame.new(0, 1 + row * 1.6, row * 3), wood, WOOD)
		part(m, "Riser", Vector3.new(40, row * 1.6 + 0.5, 3), standCF * CFrame.new(0, (row * 1.6 + 0.5) / 2, row * 3), wood:Lerp(Color3.new(), 0.25), WOOD)
	end
	for _, x in { -20, -10, 0, 10, 20 } do
		part(m, "Post", Vector3.new(0.8, 18, 0.8), standCF * CFrame.new(x, 9, 17), wood, WOOD)
		part(m, "FrontPost", Vector3.new(0.6, 15, 0.6), standCF * CFrame.new(x, 7.5, -1.5), wood, WOOD, true)
	end
	part(m, "Roof", Vector3.new(42, 0.6, 21), standCF * CFrame.new(0, 17, 7.5) * CFrame.Angles(math.rad(8), 0, 0), Color3.fromRGB(150, 44, 34), Enum.Material.Fabric)
	for i = 0, 7 do
		local stripe = if i % 2 == 0 then Color3.fromRGB(236, 230, 216) else Color3.fromRGB(150, 44, 34)
		part(m, "Valance", Vector3.new(5, 1.4, 0.15), standCF * CFrame.new(-17.5 + i * 5, 15.3, -2.1), stripe, Enum.Material.Fabric, true)
	end
	-- Bunting poles along the start straight.
	for k = 1, 6 do
		for _, s in { -1, 1 } do
			local p = trailFrame(Layout.StartDist + k * 20 - 70, s * (half + 2))
			cyl(m, "BuntingPole", p.Position, p.Position + Vector3.new(0, 9, 0), 0.35, Color3.fromRGB(110, 80, 56))
			part(m, "Pennant", Vector3.new(0.1, 1.6, 2.2), p * CFrame.new(0, 8.2, 1.1), if k % 2 == 0 then Color3.fromRGB(150, 44, 34) else Color3.fromRGB(230, 220, 196), Enum.Material.Fabric, true)
		end
	end
	local spawnPad = part(m, "StartSpawn", Vector3.new(8, 1, 8), cf * CFrame.new(0, -0.4, -10), Color3.new(), Enum.Material.SmoothPlastic, true)
	spawnPad.Transparency = 1
	CollectionService:AddTag(spawnPad, "SBR_StartSpawn")
	return m
end

function Landmarks.buildCheckpointGate(cp: Layout.Checkpoint, parent: Instance): Model
	local cf = trailFrame(cp.Dist) * CFrame.Angles(0, math.pi, 0)
	local title = if cp.Name == "Finish" then "FINISH" else "CHECKPOINT " .. cp.Index
	local sub = if cp.Name == "Finish" then "NEW YORK" else cp.Name:upper()
	local gate = Props.buildGate(cf, parent, title, sub)
	gate:SetAttribute("Checkpoint", cp.Index)
	return gate
end

function Landmarks.buildFinishArch(parent: Instance): Model
	local m = model("FinishArch", parent)
	local cf = trailFrame(Layout.FinishDist)
	local stone = Color3.fromRGB(200, 192, 176)
	local half = Config.Map.TrailHalfWidth + 8
	for _, s in { -1, 1 } do
		part(m, "Pier", Vector3.new(6, 30, 6), cf * CFrame.new(s * (half + 3), 15, 0), stone, Enum.Material.Limestone)
		part(m, "PierCap", Vector3.new(7, 1.2, 7), cf * CFrame.new(s * (half + 3), 30.6, 0), stone:Lerp(Color3.new(), 0.1), Enum.Material.Limestone, true)
	end
	-- Arch built from segments.
	local segments = 12
	local radius = half + 3
	for i = 0, segments - 1 do
		local a0 = i / segments * math.pi
		local a1 = (i + 1) / segments * math.pi
		local p0 = cf * CFrame.new(math.cos(a0) * radius, 30 + math.sin(a0) * 10, 0)
		local p1 = cf * CFrame.new(math.cos(a1) * radius, 30 + math.sin(a1) * 10, 0)
		PartUtil.beamBetween(p0.Position, p1.Position, 6, 3.5, { Name = "Arch", Color = stone, Material = Enum.Material.Limestone, Parent = m })
	end
	local banner = part(m, "Banner", Vector3.new(half * 1.6, 4, 0.3), cf * CFrame.new(0, 24, 0), Color3.fromRGB(150, 44, 34), Enum.Material.Fabric, true)
	Buildings.sign(banner, "FINISH", Color3.fromRGB(236, 230, 216), Enum.NormalId.Front)
	Buildings.sign(banner, "FINISH", Color3.fromRGB(236, 230, 216), Enum.NormalId.Back)
	return m
end

function Landmarks.buildLighthouse(lm: Layout.Landmark, parent: Instance): Model
	local m = model("Lighthouse", parent)
	local ground = HeightField.Surface(lm.Position.X, lm.Position.Z)
	local base = Vector3.new(lm.Position.X, ground, lm.Position.Z)
	local h = 48
	local segments = 6
	for i = 0, segments - 1 do
		local y0 = i * h / segments
		local r = 9 - i * 0.7
		local color = if i % 2 == 0 then Color3.fromRGB(236, 232, 222) else Color3.fromRGB(150, 44, 34)
		part(m, "Tower", Vector3.new(h / segments, r * 2, r * 2), CFrame.new(base + Vector3.new(0, y0 + h / segments / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.Material.Concrete, false, Enum.PartType.Cylinder)
	end
	part(m, "Gallery", Vector3.new(1, 13, 13), CFrame.new(base + Vector3.new(0, h + 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(50, 50, 54), Enum.Material.Metal, false, Enum.PartType.Cylinder)
	local lamp = part(m, "Lamp", Vector3.new(5, 7, 7), CFrame.new(base + Vector3.new(0, h + 3.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(255, 230, 170), Enum.Material.Neon, true, Enum.PartType.Cylinder)
	lamp.Transparency = 0.3
	local light = Instance.new("SpotLight")
	light.Range = 60
	light.Angle = 50
	light.Brightness = 4
	light.Color = Color3.fromRGB(255, 230, 170)
	light.Face = Enum.NormalId.Front
	light.Parent = lamp
	CollectionService:AddTag(lamp, "SBR_Spinner")
	CollectionService:AddTag(lamp, "SBR_NightLight")
	part(m, "Dome", Vector3.new(8, 4, 8), CFrame.new(base + Vector3.new(0, h + 8, 0)), Color3.fromRGB(50, 50, 54), Enum.Material.Metal, true, Enum.PartType.Ball)
	part(m, "Door", Vector3.new(4, 7, 0.4), CFrame.new(base + Vector3.new(0, 3.5, -8.6)), Color3.fromRGB(70, 50, 36), WOOD, true)
	-- Keeper's cottage.
	Buildings.buildHouse(Random.new(Config.Map.Seed + 5), CFrame.lookAt(base + Vector3.new(20, 0, 6), base + Vector3.new(20, 0, -10)), m)
	return m
end

function Landmarks.buildRockArch(lm: Layout.Landmark, parent: Instance): Model
	local m = model("RockArch", parent)
	local d = lm.Dist
	local rng = Random.new(Config.Map.Seed + 77)
	local color = Color3.fromRGB(190, 110, 70)
	local cf = trailFrame(d)
	local half = 26
	local height = 46
	-- Legs.
	for _, s in { -1, 1 } do
		for k = 0, 4 do
			local y = k * 10
			local w = 18 - k * 1.5
			part(m, "Leg", Vector3.new(w, 11, w * 0.8), cf * CFrame.new(s * (half + w / 2 - 4 + k * 0.8), y + 4, 0) * CFrame.Angles(rng:NextNumber(-0.08, 0.08), rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.08, 0.08)), PartUtil.vary(rng, color, 0.04), Enum.Material.Sandstone)
		end
	end
	-- Span.
	local segments = 14
	for i = 0, segments do
		local t = i / segments
		local x = -half - 6 + t * (half + 6) * 2
		local y = height + math.sin(t * math.pi) * 6
		part(m, "Span", Vector3.new(8, 9 - math.sin(t * math.pi) * 3, 12), cf * CFrame.new(x, y, 0) * CFrame.Angles(rng:NextNumber(-0.05, 0.05), 0, rng:NextNumber(-0.1, 0.1)), PartUtil.vary(rng, color, 0.04), Enum.Material.Sandstone)
	end
	return m
end

function Landmarks.buildGiantMesa(lm: Layout.Landmark, parent: Instance): Model
	local ground = HeightField.Surface(lm.Position.X, lm.Position.Z)
	local m = Nature.buildMesa(Random.new(Config.Map.Seed + 12), CFrame.new(lm.Position.X, ground, lm.Position.Z), parent, 2.6)
	m.Name = "GiantMesa"
	return m
end

function Landmarks.buildWaterfall(lm: Layout.Landmark, parent: Instance): Model
	local m = model("Waterfall", parent)
	local rng = Random.new(Config.Map.Seed + 33)
	local pool = Layout.Pools[1]
	local center = pool.Center
	local poolY = HeightField.TrailHeight(center.X) - 1
	-- Cliff behind the pool, on the side away from the trail.
	local d, lateral = Route.Project(center)
	local _, tangent = Route.PointAt(d)
	local away = tangent:Cross(Vector3.yAxis) * (if lateral >= 0 then 1 else -1)
	local cliffBase = center + away * (pool.Radius + 6)
	local cliffCF = CFrame.lookAt(Vector3.new(cliffBase.X, poolY, cliffBase.Z), Vector3.new(center.X, poolY, center.Z))
	local rock = Color3.fromRGB(110, 106, 102)
	for i = -3, 3 do
		local h = 60 + rng:NextNumber(-8, 8) - math.abs(i) * 4
		part(m, "Cliff", Vector3.new(12, h, 16), cliffCF * CFrame.new(i * 10, h / 2 - 8, 6) * CFrame.Angles(rng:NextNumber(-0.06, 0.06), rng:NextNumber(-0.15, 0.15), rng:NextNumber(-0.06, 0.06)), PartUtil.vary(rng, rock, 0.04), Enum.Material.Rock)
	end
	-- Falling water sheets.
	local water = Color3.fromRGB(160, 200, 214)
	for k = 0, 2 do
		local sheet = part(m, "Fall", Vector3.new(10 - k * 2, 52, 0.6), cliffCF * CFrame.new(0, 20, -2.2 - k * 0.5), water, Enum.Material.Glass, true)
		sheet.Transparency = 0.25 + k * 0.15
	end
	local foam = part(m, "Foam", Vector3.new(14, 1.2, 8), cliffCF * CFrame.new(0, 0.6, -5), Color3.fromRGB(236, 244, 248), Enum.Material.SmoothPlastic, true)
	foam.Transparency = 0.3
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = Config.Textures.Smoke
	mist.Color = ColorSequence.new(Color3.fromRGB(236, 244, 248))
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 9) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	mist.Lifetime = NumberRange.new(2, 3)
	mist.Rate = 12
	mist.Speed = NumberRange.new(2, 5)
	mist.SpreadAngle = Vector2.new(70, 70)
	mist.Parent = foam
	local sound = Instance.new("Sound")
	sound.SoundId = Config.Sounds.Water
	sound.Looped = true
	sound.Volume = 0.6
	sound.PlaybackSpeed = 0.6
	sound.RollOffMaxDistance = 140
	sound.Parent = foam
	sound:Play()
	for _ = 1, 6 do
		local p = cliffCF * Vector3.new(rng:NextNumber(-40, 40), 0, rng:NextNumber(14, 26))
		Nature.buildPine(rng, CFrame.new(p.X, HeightField.Surface(p.X, p.Z), p.Z), m, 0.9)
	end
	return m
end

function Landmarks.buildWindmillFarm(lm: Layout.Landmark, parent: Instance): Model
	local m = model("WindmillFarm", parent)
	local rng = Random.new(Config.Map.Seed + 21)
	local ground = HeightField.Surface(lm.Position.X, lm.Position.Z)
	local base = Vector3.new(lm.Position.X, ground, lm.Position.Z)
	local facing = CFrame.lookAt(base, base - lm.Facing:Cross(Vector3.yAxis))
	Buildings.buildHouse(rng, facing * CFrame.new(-14, 0, 6), m)
	Buildings.buildStable(rng, facing * CFrame.new(16, 0, 4), m)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local p = base + Vector3.new(math.cos(a) * 34, 0, math.sin(a) * 34)
		local gy = HeightField.Surface(p.X, p.Z)
		Props.buildWindmill(rng, CFrame.new(p.X, gy, p.Z) * CFrame.Angles(0, rng:NextNumber(0, 0.4), 0), m)
	end
	for k = 0, 3 do
		Nature.buildHaystack(rng, facing * CFrame.new(-6 + k * 5, 0, -14), m)
	end
	Props.buildWaterTower(rng, facing * CFrame.new(0, 0, 22), m)
	return m
end

function Landmarks.buildSequoia(lm: Layout.Landmark, parent: Instance): Model
	local ground = HeightField.Surface(lm.Position.X, lm.Position.Z)
	return Nature.buildSequoia(Random.new(Config.Map.Seed + 9), CFrame.new(lm.Position.X, ground, lm.Position.Z), parent)
end

function Landmarks.buildTrestleBridge(lm: Layout.Landmark, parent: Instance): Model
	local river = Layout.River
	local center = lm.Position
	local deckY = HeightField.TrailHeight(river.CenterX) + 14
	local span = river.HalfWidth + river.BankWidth + 60
	local a = Vector3.new(center.X - span, deckY, center.Z)
	local b = Vector3.new(center.X + span, deckY, center.Z)
	return Props.buildTrestle(Random.new(Config.Map.Seed + 41), a, b, function(p: Vector3): number
		return HeightField.Surface(p.X, p.Z)
	end, parent)
end

function Landmarks.buildOldFort(lm: Layout.Landmark, parent: Instance): Model
	local m = model("OldFort", parent)
	local rng = Random.new(Config.Map.Seed + 55)
	local ground = HeightField.Surface(lm.Position.X, lm.Position.Z)
	local base = Vector3.new(lm.Position.X, ground, lm.Position.Z)
	local wood = Color3.fromRGB(120, 92, 66)
	local half = 30
	-- Palisade of sharpened logs with a gate facing the trail.
	local toTrail = -lm.Facing:Cross(Vector3.yAxis) * (if lm.Lateral > 0 then 1 else -1)
	local frame = CFrame.lookAt(base, base + toTrail)
	for side = 0, 3 do
		local rot = frame * CFrame.Angles(0, side * math.pi / 2, 0)
		for i = -half, half, 2 do
			local isGate = side == 0 and math.abs(i) <= 4
			if not isGate then
				local p = (rot * CFrame.new(i, 0, -half)).Position
				local h = 12 + rng:NextNumber(-1, 1)
				cyl(m, "Log", p - Vector3.new(0, 2, 0), p + Vector3.new(0, h, 0), 1.9, PartUtil.vary(rng, wood, 0.04), Enum.Material.Wood)
				part(m, "Point", Vector3.new(1.4, 1.4, 1.4), CFrame.new(p + Vector3.new(0, h + 0.4, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)), wood, Enum.Material.Wood, true)
			end
		end
		-- Corner tower.
		local corner = (rot * CFrame.new(half, 0, -half)).Position
		for _, sx in { -1, 1 } do
			for _, sz in { -1, 1 } do
				cyl(m, "TowerLeg", corner + Vector3.new(sx * 3, -1, sz * 3), corner + Vector3.new(sx * 3, 18, sz * 3), 1, wood)
			end
		end
		part(m, "TowerDeck", Vector3.new(8, 0.6, 8), CFrame.new(corner + Vector3.new(0, 16, 0)), wood)
		part(m, "TowerRoof", Vector3.new(9, 0.5, 9), CFrame.new(corner + Vector3.new(0, 22, 0)), Color3.fromRGB(80, 60, 46), WOOD, true)
	end
	Buildings.buildHouse(rng, frame * CFrame.new(-12, 0, 10) * CFrame.Angles(0, math.pi, 0), m)
	Buildings.buildSheriffOffice(rng, frame * CFrame.new(12, 0, 10) * CFrame.Angles(0, math.pi, 0), m)
	Props.buildWell(rng, frame * CFrame.new(0, 0, 0), m)
	cyl(m, "FlagPole", base, base + Vector3.new(0, 26, 0), 0.4, Color3.fromRGB(70, 66, 64), Enum.Material.Metal)
	part(m, "Flag", Vector3.new(0.1, 4, 6), CFrame.new(base + Vector3.new(0, 23.5, 3)), Color3.fromRGB(150, 44, 34), Enum.Material.Fabric, true)
	return m
end

-- Circular boss arena: a flattened ring of rocks with torches and a spawn pad.
function Landmarks.buildBossArena(arena: Layout.Arena, parent: Instance): Model
	local m = model("BossArena" .. arena.Stage, parent)
	local rng = Random.new(Config.Map.Seed + arena.Stage * 13)
	local ground = HeightField.Surface(arena.Center.X, arena.Center.Z)
	local center = Vector3.new(arena.Center.X, ground, arena.Center.Z)
	local stage = Route.Stages[arena.Stage]
	local rockColor = if stage.Kind == "Canyon" or stage.Kind == "Desert" then Color3.fromRGB(180, 110, 72) else Color3.fromRGB(120, 114, 108)
	local count = 18
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		-- Leave a gap toward the trail.
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * arena.Radius
		local dTrail = Route.DistanceFromTrail(p.X, p.Z)
		if dTrail > 120 or (i % 6 ~= 0) then
			local gy = HeightField.Surface(p.X, p.Z)
			local h = rng:NextNumber(6, 14)
			part(m, "Standing", Vector3.new(rng:NextNumber(3, 5), h, rng:NextNumber(3, 5)), CFrame.new(p.X, gy + h / 2 - 1, p.Z) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), a, rng:NextNumber(-0.1, 0.1)), PartUtil.vary(rng, rockColor, 0.04), Enum.Material.Rock)
		end
		if i % 3 == 0 then
			local tp = center + Vector3.new(math.cos(a + 0.17), 0, math.sin(a + 0.17)) * (arena.Radius - 4)
			local gy = HeightField.Surface(tp.X, tp.Z)
			cyl(m, "Torch", Vector3.new(tp.X, gy - 1, tp.Z), Vector3.new(tp.X, gy + 6, tp.Z), 0.5, Color3.fromRGB(80, 60, 44), Enum.Material.Wood)
			local flame = part(m, "Flame", Vector3.new(0.8, 0.8, 0.8), CFrame.new(tp.X, gy + 6.4, tp.Z), Color3.fromRGB(255, 140, 60), Enum.Material.Neon, true)
			local fire = Instance.new("Fire")
			fire.Size = 2
			fire.Heat = 5
			fire.Parent = flame
			PartUtil.light(flame, Color3.fromRGB(255, 150, 80), 18, 1.6)
		end
	end
	local pad = part(m, "BossSpawn", Vector3.new(6, 0.4, 6), CFrame.new(center + Vector3.new(0, 0.2, 0)), Color3.fromRGB(60, 50, 44), Enum.Material.Slate, true)
	pad.Transparency = 1
	pad:SetAttribute("Stage", arena.Stage)
	CollectionService:AddTag(pad, "SBR_BossSpawn")
	-- A sign at the entrance.
	local d, lateral = Route.Project(center)
	local side = if lateral > 0 then 1 else -1
	local signCF = trailFrame(d, side * (Config.Map.TrailHalfWidth + 6))
	part(m, "SignPost", Vector3.new(0.6, 6, 0.6), signCF * CFrame.new(0, 3, 0), Color3.fromRGB(110, 80, 56), WOOD)
	local board = part(m, "SignBoard", Vector3.new(5, 1.6, 0.25), signCF * CFrame.new(0, 5.2, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(46, 34, 26), WOOD, true)
	Buildings.sign(board, "DANGER", Color3.fromRGB(236, 230, 216), Enum.NormalId.Front)
	Buildings.sign(board, "DANGER", Color3.fromRGB(236, 230, 216), Enum.NormalId.Back)
	return m
end

function Landmarks.buildPvPArena(parent: Instance): Model
	local m = model("RankedArena", parent)
	local info = Layout.PvPArena
	local ground = HeightField.Surface(info.Center.X, info.Center.Z)
	local center = Vector3.new(info.Center.X, ground, info.Center.Z)
	local wood = Color3.fromRGB(130, 100, 72)
	part(m, "Floor", Vector3.new(1, info.Radius * 2 - 6, info.Radius * 2 - 6), CFrame.new(center + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(196, 170, 130), Enum.Material.Sand, false, Enum.PartType.Cylinder)
	local count = 36
	for i = 0, count - 1 do
		local a = i / count * math.pi * 2
		local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (info.Radius - 2)
		if i ~= 0 then
			part(m, "Wall", Vector3.new(info.Radius * 2 * math.pi / count + 0.4, 6, 1.2), CFrame.lookAt(p + Vector3.new(0, 3, 0), center + Vector3.new(0, 3, 0)), wood, WOOD)
		end
		-- Spectator tiers outside the wall.
		for row = 1, 3 do
			local q = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (info.Radius - 2 + row * 3)
			part(m, "Tier", Vector3.new(info.Radius * 2 * math.pi / count * (1 + row * 0.08) + 0.6, 1, 3), CFrame.lookAt(q + Vector3.new(0, 4 + row * 2, 0), center + Vector3.new(0, 4 + row * 2, 0)), wood:Lerp(Color3.new(), 0.15), WOOD)
		end
	end
	for k = 1, 2 do
		local a = if k == 1 then math.rad(90) else math.rad(270)
		local pad = part(m, "ArenaPad" .. k, Vector3.new(6, 0.3, 6), CFrame.new(center + Vector3.new(math.cos(a), 0, math.sin(a)) * (info.Radius * 0.55) + Vector3.new(0, 0.95, 0)), Color3.fromRGB(150, 44, 34), Enum.Material.Fabric, true)
		pad:SetAttribute("Slot", k)
		CollectionService:AddTag(pad, "SBR_ArenaPad")
	end
	local signCF = CFrame.lookAt(center + Vector3.new(info.Radius + 6, 0, 0), center)
	local board = part(m, "SignBoard", Vector3.new(14, 3, 0.4), signCF * CFrame.new(0, 14, 0), Color3.fromRGB(46, 34, 26), WOOD)
	Buildings.sign(board, "RANKED ARENA", Color3.fromRGB(236, 230, 216), Enum.NormalId.Back)
	return m
end

function Landmarks.build(lm: Layout.Landmark, parent: Instance): Instance?
	if lm.Kind == "Lighthouse" then
		return Landmarks.buildLighthouse(lm, parent)
	elseif lm.Kind == "RockArch" then
		return Landmarks.buildRockArch(lm, parent)
	elseif lm.Kind == "GiantMesa" then
		return Landmarks.buildGiantMesa(lm, parent)
	elseif lm.Kind == "Waterfall" then
		return Landmarks.buildWaterfall(lm, parent)
	elseif lm.Kind == "WindmillFarm" then
		return Landmarks.buildWindmillFarm(lm, parent)
	elseif lm.Kind == "GreatSequoia" then
		return Landmarks.buildSequoia(lm, parent)
	elseif lm.Kind == "TrestleBridge" then
		return Landmarks.buildTrestleBridge(lm, parent)
	elseif lm.Kind == "OldFort" then
		return Landmarks.buildOldFort(lm, parent)
	end
	-- The clock tower is part of the city layout.
	return nil
end

return Landmarks
