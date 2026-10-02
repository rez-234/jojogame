--!strict
-- Procedural plants and rock formations. Trunks and large rocks collide;
-- foliage, small rocks and tumbleweeds are decorative.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local PartUtil = require(ReplicatedStorage.Builders.PartUtil)

local Nature = {}

local function model(name: string, parent: Instance): Model
	local m = PartUtil.model(name, parent)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return m
end

local function part(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, decor: boolean, shape: Enum.PartType?): Part
	return PartUtil.part({
		Name = name,
		Size = size,
		CFrame = cf,
		Color = color,
		Material = material,
		Decor = decor,
		Shape = shape,
		Parent = m,
	})
end

local function cyl(m: Model, name: string, a: Vector3, b: Vector3, d: number, color: Color3, material: Enum.Material, decor: boolean): Part
	return PartUtil.cylinderBetween(a, b, d, { Name = name, Color = color, Material = material, Decor = decor, Parent = m })
end

function Nature.buildCactus(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Cactus", parent)
	local green = PartUtil.vary(rng, Color3.fromRGB(86, 120, 70), 0.06)
	local h = rng:NextNumber(6, 13)
	local d = rng:NextNumber(1.3, 2)
	local base = cf.Position
	cyl(m, "Trunk", base - Vector3.new(0, 1, 0), base + Vector3.new(0, h, 0), d, green, Enum.Material.Grass, false)
	part(m, "Top", Vector3.one * d, CFrame.new(base + Vector3.new(0, h, 0)), green, Enum.Material.Grass, true, Enum.PartType.Ball)
	local arms = rng:NextInteger(0, 3)
	for _ = 1, arms do
		local a = rng:NextNumber(0, math.pi * 2)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local y = rng:NextNumber(h * 0.3, h * 0.65)
		local out = rng:NextNumber(1.5, 2.6)
		local up = rng:NextNumber(2, 4.5)
		local elbow = base + Vector3.new(0, y, 0) + dir * out
		cyl(m, "Arm", base + Vector3.new(0, y, 0), elbow, d * 0.7, green, Enum.Material.Grass, true)
		cyl(m, "ArmUp", elbow, elbow + Vector3.new(0, up, 0), d * 0.7, green, Enum.Material.Grass, true)
		part(m, "ArmTop", Vector3.one * d * 0.7, CFrame.new(elbow + Vector3.new(0, up, 0)), green, Enum.Material.Grass, true, Enum.PartType.Ball)
	end
	if rng:NextNumber() < 0.3 then
		part(m, "Flower", Vector3.new(0.5, 0.5, 0.5), CFrame.new(base + Vector3.new(0, h + d * 0.45, 0)), Color3.fromRGB(230, 120, 140), Enum.Material.SmoothPlastic, true, Enum.PartType.Ball)
	end
	return m
end

function Nature.buildRock(rng: Random, cf: CFrame, parent: Instance, scale: number?, color: Color3?): Model
	local m = model("Rock", parent)
	local s = (scale or 1) * rng:NextNumber(2.5, 8)
	local base = color or Color3.fromRGB(130, 120, 110)
	local count = rng:NextInteger(2, 4)
	for i = 1, count do
		local size = Vector3.new(s * rng:NextNumber(0.6, 1.2), s * rng:NextNumber(0.4, 0.9), s * rng:NextNumber(0.6, 1.2))
		local offset = Vector3.new(rng:NextNumber(-0.4, 0.4) * s, size.Y * 0.3, rng:NextNumber(-0.4, 0.4) * s)
		local rot = CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, math.pi * 2), rng:NextNumber(-0.4, 0.4))
		local p = part(m, "Rock", size, cf * CFrame.new(offset) * rot, PartUtil.vary(rng, base, 0.05), Enum.Material.Rock, s < 3.5)
		if i == 1 and rng:NextNumber() < 0.5 then
			p.Material = Enum.Material.Slate
		end
	end
	return m
end

function Nature.buildMesa(rng: Random, cf: CFrame, parent: Instance, scale: number?): Model
	local m = model("Mesa", parent)
	local s = (scale or 1) * rng:NextNumber(0.8, 1.3)
	local radius = 22 * s
	local height = rng:NextNumber(40, 70) * s
	local layers = rng:NextInteger(3, 5)
	local colors = {
		Color3.fromRGB(176, 96, 62),
		Color3.fromRGB(196, 120, 76),
		Color3.fromRGB(160, 86, 58),
		Color3.fromRGB(206, 140, 90),
	}
	local base = cf.Position
	local y = -6
	for i = 1, layers do
		local h = height / layers
		local r = radius * (1.15 - i * 0.07) * rng:NextNumber(0.92, 1.05)
		local c = colors[(i - 1) % #colors + 1]
		-- Each layer is a slightly rotated cylinder so the edges look eroded.
		for k = 1, 2 do
			local rot = CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
			part(m, "Layer", Vector3.new(h + (if k == 2 then 0.5 else 0), r * 2 * (if k == 2 then 0.9 else 1), r * 2 * (if k == 2 then 1.05 else 1)), CFrame.new(base + Vector3.new(0, y + h / 2, 0)) * rot * CFrame.Angles(0, 0, math.rad(90)), c, Enum.Material.Sandstone, false, Enum.PartType.Cylinder)
		end
		y += h
	end
	-- Talus slope at the foot.
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local p = base + Vector3.new(math.cos(a) * radius * 1.05, 0, math.sin(a) * radius * 1.05)
		part(m, "Talus", Vector3.new(rng:NextNumber(5, 10), rng:NextNumber(3, 7), rng:NextNumber(5, 10)) * s, CFrame.new(p) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), a, rng:NextNumber(-0.3, 0.3)), Color3.fromRGB(170, 100, 66), Enum.Material.Sandstone, false)
	end
	part(m, "Cap", Vector3.new(2, radius * 1.6, radius * 1.6), CFrame.new(base + Vector3.new(0, y + 1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 80, 52), Enum.Material.Sandstone, false, Enum.PartType.Cylinder)
	return m
end

local function foliageCluster(m: Model, rng: Random, center: Vector3, radius: number, color: Color3, count: number)
	for _ = 1, count do
		local offset = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.5, 0.7), rng:NextNumber(-1, 1)) * radius * 0.6
		local r = radius * rng:NextNumber(0.7, 1.1)
		part(m, "Leaves", Vector3.new(r * 1.4, r * 1.1, r * 1.4), CFrame.new(center + offset), PartUtil.vary(rng, color, 0.06), Enum.Material.LeafyGrass, true, Enum.PartType.Ball)
	end
end

function Nature.buildTree(rng: Random, cf: CFrame, parent: Instance, scale: number?): Model
	local m = model("Tree", parent)
	local s = (scale or 1) * rng:NextNumber(0.8, 1.35)
	local base = cf.Position
	local h = 12 * s
	local trunkColor = PartUtil.vary(rng, Color3.fromRGB(96, 70, 50), 0.05)
	local lean = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * s
	local top = base + Vector3.new(0, h, 0) + lean
	cyl(m, "Trunk", base - Vector3.new(0, 1, 0), top, 1.6 * s, trunkColor, Enum.Material.Wood, false)
	local leaf = PartUtil.vary(rng, Color3.fromRGB(86, 118, 60), 0.08)
	for _ = 1, 3 do
		local a = rng:NextNumber(0, math.pi * 2)
		local branchEnd = top + Vector3.new(math.cos(a) * 4 * s, rng:NextNumber(-1, 2) * s, math.sin(a) * 4 * s)
		cyl(m, "Branch", top - Vector3.new(0, 2 * s, 0), branchEnd, 0.7 * s, trunkColor, Enum.Material.Wood, true)
		foliageCluster(m, rng, branchEnd, 4 * s, leaf, 2)
	end
	foliageCluster(m, rng, top + Vector3.new(0, 2 * s, 0), 5.5 * s, leaf, 3)
	return m
end

function Nature.buildPine(rng: Random, cf: CFrame, parent: Instance, scale: number?): Model
	local m = model("Pine", parent)
	local s = (scale or 1) * rng:NextNumber(0.8, 1.5)
	local base = cf.Position
	local h = 22 * s
	cyl(m, "Trunk", base - Vector3.new(0, 1, 0), base + Vector3.new(0, h, 0), 1.3 * s, PartUtil.vary(rng, Color3.fromRGB(90, 62, 46), 0.05), Enum.Material.Wood, false)
	local green = PartUtil.vary(rng, Color3.fromRGB(54, 86, 60), 0.06)
	local tiers = 5
	for i = 0, tiers - 1 do
		local t = i / tiers
		local y = h * (0.28 + t * 0.68)
		local r = 6.5 * s * (1 - t * 0.78)
		local tierH = 5 * s * (1 - t * 0.35)
		-- Two crossed square cones read as a round pine from every angle.
		for k = 0, 1 do
			local rot = CFrame.Angles(0, k * math.pi / 4 + rng:NextNumber(0, 0.3), 0)
			for q = 0, 3 do
				local qrot = CFrame.Angles(0, q * math.pi / 2, 0)
				PartUtil.wedge({
					Name = "Needles",
					Size = Vector3.new(r * 2, tierH, r),
					CFrame = CFrame.new(base + Vector3.new(0, y, 0)) * rot * qrot * CFrame.new(0, 0, -r / 2),
					Color = green,
					Material = Enum.Material.LeafyGrass,
					Decor = true,
					Parent = m,
				})
			end
		end
	end
	if rng:NextNumber() < 0.15 then
		part(m, "Snowcap", Vector3.new(2.5, 1.2, 2.5) * s, CFrame.new(base + Vector3.new(0, h * 0.95, 0)), Color3.fromRGB(240, 244, 248), Enum.Material.Snow, true, Enum.PartType.Ball)
	end
	return m
end

function Nature.buildDeadTree(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("DeadTree", parent)
	local base = cf.Position
	local color = PartUtil.vary(rng, Color3.fromRGB(110, 96, 82), 0.06)
	local h = rng:NextNumber(7, 13)
	local top = base + Vector3.new(rng:NextNumber(-1.5, 1.5), h, rng:NextNumber(-1.5, 1.5))
	cyl(m, "Trunk", base - Vector3.new(0, 1, 0), top, rng:NextNumber(0.9, 1.4), color, Enum.Material.Wood, false)
	local function branch(from: Vector3, dir: Vector3, length: number, width: number, depth: number)
		local to = from + dir * length
		cyl(m, "Branch", from, to, width, color, Enum.Material.Wood, true)
		if depth > 0 then
			for _ = 1, 2 do
				local nd = (dir + Vector3.new(rng:NextNumber(-0.8, 0.8), rng:NextNumber(0, 0.6), rng:NextNumber(-0.8, 0.8))).Unit
				branch(to, nd, length * 0.6, width * 0.65, depth - 1)
			end
		end
	end
	for _ = 1, rng:NextInteger(2, 3) do
		local dir = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(0.3, 1), rng:NextNumber(-1, 1)).Unit
		branch(base + Vector3.new(0, h * rng:NextNumber(0.5, 0.9), 0), dir, rng:NextNumber(3, 5), 0.6, 2)
	end
	return m
end

function Nature.buildTumbleweed(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Tumbleweed", parent)
	local r = rng:NextNumber(1.2, 2.2)
	local center = cf.Position + Vector3.new(0, r, 0)
	local color = PartUtil.vary(rng, Color3.fromRGB(150, 124, 84), 0.05)
	local core = part(m, "Core", Vector3.one * r * 1.2, CFrame.new(center), color, Enum.Material.Grass, true, Enum.PartType.Ball)
	core.Transparency = 0.5
	for _ = 1, 9 do
		local a = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit * r
		cyl(m, "Twig", center - a, center + a, 0.12, color, Enum.Material.Wood, true)
	end
	m.PrimaryPart = core
	CollectionService:AddTag(m, "SBR_Tumbleweed")
	return m
end

function Nature.buildPalm(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Palm", parent)
	local base = cf.Position
	local h = rng:NextNumber(14, 22)
	local bend = Vector3.new(rng:NextNumber(-3, 3), 0, rng:NextNumber(-3, 3))
	local prev = base - Vector3.new(0, 1, 0)
	local segments = 6
	local trunkColor = PartUtil.vary(rng, Color3.fromRGB(140, 110, 80), 0.05)
	for i = 1, segments do
		local t = i / segments
		local p = base + Vector3.new(0, h * t, 0) + bend * (t * t)
		cyl(m, "Trunk", prev, p, 1.3 - t * 0.4, trunkColor, Enum.Material.Wood, i > 2)
		prev = p
	end
	local green = PartUtil.vary(rng, Color3.fromRGB(80, 120, 60), 0.06)
	for i = 0, 6 do
		local a = i / 7 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local dir = Vector3.new(math.cos(a), -0.35, math.sin(a))
		local mid = prev + dir * 3.2
		PartUtil.part({
			Name = "Frond",
			Size = Vector3.new(1.8, 0.15, 7),
			CFrame = CFrame.lookAt(mid, mid + dir),
			Color = green,
			Material = Enum.Material.LeafyGrass,
			Decor = true,
			Parent = m,
		})
	end
	for _ = 1, 3 do
		part(m, "Coconut", Vector3.one * 0.8, CFrame.new(prev + Vector3.new(rng:NextNumber(-0.6, 0.6), -0.6, rng:NextNumber(-0.6, 0.6))), Color3.fromRGB(96, 70, 44), Enum.Material.SmoothPlastic, true, Enum.PartType.Ball)
	end
	return m
end

function Nature.buildReeds(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Reeds", parent)
	local base = cf.Position
	for _ = 1, rng:NextInteger(6, 12) do
		local p = base + Vector3.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		local h = rng:NextNumber(2.5, 5)
		local tip = p + Vector3.new(rng:NextNumber(-0.5, 0.5), h, rng:NextNumber(-0.5, 0.5))
		cyl(m, "Reed", p - Vector3.new(0, 0.5, 0), tip, 0.15, PartUtil.vary(rng, Color3.fromRGB(110, 130, 70), 0.06), Enum.Material.Grass, true)
		if rng:NextNumber() < 0.4 then
			part(m, "Cattail", Vector3.new(0.3, 0.8, 0.3), CFrame.new(tip), Color3.fromRGB(96, 66, 44), Enum.Material.Fabric, true)
		end
	end
	return m
end

function Nature.buildHaystack(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Haystack", parent)
	local color = PartUtil.vary(rng, Color3.fromRGB(214, 180, 100), 0.05)
	if rng:NextNumber() < 0.5 then
		local r = rng:NextNumber(3, 4.5)
		part(m, "Stack", Vector3.new(r * 2, r * 2, r * 2), cf * CFrame.new(0, r * 0.6, 0), color, Enum.Material.Grass, false, Enum.PartType.Ball)
		part(m, "Top", Vector3.new(r, r, r), cf * CFrame.new(0, r * 1.5, 0), color:Lerp(Color3.new(1, 1, 1), 0.08), Enum.Material.Grass, true, Enum.PartType.Ball)
	else
		for i = 0, rng:NextInteger(2, 4) do
			part(m, "Bale", Vector3.new(4, 2, 2.4), cf * CFrame.new((i % 2) * 4 - 2, 1 + math.floor(i / 2) * 2, 0) * CFrame.Angles(0, rng:NextNumber(-0.1, 0.1), 0), color, Enum.Material.Grass, false)
		end
	end
	return m
end

function Nature.buildDriftwood(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Driftwood", parent)
	local base = cf.Position
	local a = rng:NextNumber(0, math.pi * 2)
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	local len = rng:NextNumber(4, 9)
	cyl(m, "Log", base - dir * len / 2 + Vector3.new(0, 0.4, 0), base + dir * len / 2 + Vector3.new(0, 0.6, 0), rng:NextNumber(0.6, 1.1), Color3.fromRGB(176, 160, 140), Enum.Material.Wood, true)
	return m
end

function Nature.buildSequoia(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("GreatSequoia", parent)
	local base = cf.Position
	local h = 120
	local trunkColor = Color3.fromRGB(120, 66, 46)
	cyl(m, "Trunk", base - Vector3.new(0, 4, 0), base + Vector3.new(0, h, 0), 14, trunkColor, Enum.Material.Wood, false)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local root = base + Vector3.new(math.cos(a) * 8, 0, math.sin(a) * 8)
		cyl(m, "Buttress", base + Vector3.new(math.cos(a) * 3, 10, math.sin(a) * 3), root + Vector3.new(math.cos(a) * 3, -1, math.sin(a) * 3), 4, trunkColor, Enum.Material.Wood, false)
	end
	-- A hollow in the trunk players can stand in.
	part(m, "Hollow", Vector3.new(6, 10, 3), CFrame.new(base + Vector3.new(0, 5, -6.6)), Color3.fromRGB(30, 20, 16), Enum.Material.Wood, true)
	local green = Color3.fromRGB(58, 88, 52)
	for i = 0, 9 do
		local y = h * (0.45 + i * 0.06)
		local r = 26 * (1 - i * 0.08)
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2 + i * 0.6
			local p = base + Vector3.new(math.cos(a) * r * 0.5, y, math.sin(a) * r * 0.5)
			part(m, "Canopy", Vector3.new(r, r * 0.35, r), CFrame.new(p), PartUtil.vary(rng, green, 0.05), Enum.Material.LeafyGrass, true, Enum.PartType.Ball)
		end
	end
	return m
end

return Nature
