--!strict
-- Procedural props, bridges and frontier structures.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local PartUtil = require(ReplicatedStorage.Builders.PartUtil)
local Config = require(ReplicatedStorage.Shared.Config)
local Buildings = require(script.Parent.PrefabsBuildings)

local Props = {}

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

local function wheel(m: Model, center: CFrame, radius: number, color: Color3)
	part(m, "Wheel", Vector3.new(0.35, radius * 2, radius * 2), center, color:Lerp(Color3.new(), 0.2), WOOD, true, Enum.PartType.Cylinder)
	part(m, "Rim", Vector3.new(0.4, radius * 2 + 0.2, radius * 2 + 0.2), center, Color3.fromRGB(60, 58, 56), Enum.Material.Metal, true, Enum.PartType.Cylinder).Transparency = 0.6
	for k = 0, 5 do
		part(m, "Spoke", Vector3.new(0.2, radius * 1.9, 0.15), center * CFrame.Angles(k * math.pi / 6, 0, 0), color, WOOD, true)
	end
	part(m, "Hub", Vector3.new(0.6, 0.6, 0.6), center, Color3.fromRGB(60, 58, 56), Enum.Material.Metal, true, Enum.PartType.Cylinder)
end

function Props.buildWagon(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Wagon", parent)
	local color = PartUtil.vary(rng, Color3.fromRGB(130, 96, 66), 0.05)
	local broken = rng:NextNumber() < 0.35
	local tilt = if broken then CFrame.Angles(0, 0, math.rad(12)) else CFrame.identity
	local body = cf * tilt
	part(m, "Bed", Vector3.new(5, 0.4, 10), body * CFrame.new(0, 2.6, 0), color, WOOD)
	for _, s in { -1, 1 } do
		part(m, "Side", Vector3.new(0.3, 1.6, 10), body * CFrame.new(s * 2.4, 3.6, 0), color, WOOD)
	end
	part(m, "Back", Vector3.new(5, 1.6, 0.3), body * CFrame.new(0, 3.6, 4.9), color, WOOD)
	part(m, "Front", Vector3.new(5, 1.6, 0.3), body * CFrame.new(0, 3.6, -4.9), color, WOOD)
	for _, s in { -1, 1 } do
		for _, z in { -3.4, 3.4 } do
			if not (broken and s == 1 and z > 0) then
				wheel(m, body * CFrame.new(s * 2.8, 1.8, z), 1.8, color)
			end
		end
	end
	if rng:NextNumber() < 0.6 then
		-- Canvas cover over hoops.
		local canvas = Color3.fromRGB(224, 214, 190)
		for k = 0, 5 do
			local a0 = k / 6 * math.pi
			local a1 = (k + 1) / 6 * math.pi
			local p0 = Vector3.new(math.cos(a0) * 2.5, 4.4 + math.sin(a0) * 2.8, 0)
			local p1 = Vector3.new(math.cos(a1) * 2.5, 4.4 + math.sin(a1) * 2.8, 0)
			local mid = (p0 + p1) / 2
			local width = (p1 - p0).Magnitude
			local x = (p1 - p0).Unit
			local panel = CFrame.fromMatrix(mid, x, Vector3.zAxis:Cross(x))
			part(m, "Canvas", Vector3.new(width + 0.1, 0.12, 9.6), body * panel, canvas, Enum.Material.Fabric, true)
		end
	else
		for i = 1, rng:NextInteger(1, 3) do
			Buildings.barrelAt({ rng = rng, cf = body * CFrame.new(rng:NextNumber(-1.2, 1.2), 2.8, -3 + i * 2), model = m }, CFrame.identity, rng)
		end
	end
	cyl(m, "Tongue", (body * CFrame.new(0, 1.8, -5)).Position, (body * CFrame.new(0, 0.5, -9.5)).Position, 0.4, color, WOOD, true)
	return m
end

function Props.buildLantern(_rng: Random, cf: CFrame, parent: Instance, lit: boolean?): Model
	local m = model("Lantern", parent)
	local metal = Color3.fromRGB(50, 46, 42)
	part(m, "Base", Vector3.new(0.8, 0.2, 0.8), cf * CFrame.new(0, 0.1, 0), metal, Enum.Material.Metal, true)
	local glass = part(m, "Glass", Vector3.new(0.6, 0.9, 0.6), cf * CFrame.new(0, 0.65, 0), Color3.fromRGB(255, 210, 130), Enum.Material.Neon, true)
	glass.Transparency = 0.25
	part(m, "Cap", Vector3.new(0.85, 0.25, 0.85), cf * CFrame.new(0, 1.2, 0), metal, Enum.Material.Metal, true)
	part(m, "Handle", Vector3.new(0.6, 0.5, 0.1), cf * CFrame.new(0, 1.55, 0), metal, Enum.Material.Metal, true)
	if lit ~= false then
		local light = PartUtil.light(glass, Color3.fromRGB(255, 190, 110), 16, 1.2)
		light.Enabled = true
		CollectionService:AddTag(glass, "SBR_NightLight")
	end
	return m
end

function Props.buildLampPost(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("LampPost", parent)
	local metal = Color3.fromRGB(40, 40, 44)
	cyl(m, "Post", cf.Position, cf.Position + Vector3.new(0, 11, 0), 0.5, metal, Enum.Material.Metal)
	part(m, "Arm", Vector3.new(0.3, 0.3, 2.4), cf * CFrame.new(0, 10.8, -1), metal, Enum.Material.Metal, true)
	Props.buildLantern(rng, cf * CFrame.new(0, 8.8, -2), m)
	return m
end

function Props.buildBarrel(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Barrel", parent)
	Buildings.barrelAt({ rng = rng, cf = cf, model = m }, CFrame.identity, rng)
	return m
end

function Props.buildCrate(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Crates", parent)
	local ctx = { rng = rng, cf = cf, model = m }
	Buildings.crateAt(ctx, CFrame.identity, rng)
	if rng:NextNumber() < 0.5 then
		Buildings.crateAt(ctx, CFrame.new(rng:NextNumber(-0.3, 0.3), 2.2, 0) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0), rng)
	end
	return m
end

function Props.buildFence(rng: Random, a: Vector3, b: Vector3, parent: Instance): Model
	local m = model("Fence", parent)
	local color = PartUtil.vary(rng, Color3.fromRGB(140, 110, 80), 0.05)
	local length = (b - a).Magnitude
	local posts = math.max(2, math.floor(length / 5) + 1)
	local dir = (b - a).Unit
	local prev: Vector3? = nil
	for i = 0, posts - 1 do
		local p = a + dir * (i * length / (posts - 1))
		cyl(m, "Post", p - Vector3.new(0, 1, 0), p + Vector3.new(0, 3.6, 0), 0.45, color)
		if prev then
			for _, y in { 1.3, 2.8 } do
				local up = Vector3.new(0, y, 0)
				cyl(m, "Rail", prev + up, p + up, 0.25, color, WOOD, true)
			end
		end
		prev = p
	end
	return m
end

function Props.buildHitchingPost(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("HitchingPost", parent)
	local color = PartUtil.vary(rng, Color3.fromRGB(120, 90, 64), 0.05)
	for _, x in { -2.5, 2.5 } do
		part(m, "Post", Vector3.new(0.5, 3.6, 0.5), cf * CFrame.new(x, 1.8, 0), color)
	end
	part(m, "Rail", Vector3.new(6, 0.4, 0.4), cf * CFrame.new(0, 3.4, 0), color)
	part(m, "Ring", Vector3.new(0.1, 0.6, 0.6), cf * CFrame.new(1, 3.0, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(90, 90, 96), Enum.Material.Metal, true, Enum.PartType.Cylinder)
	return m
end

function Props.buildTrough(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Trough", parent)
	local color = PartUtil.vary(rng, Color3.fromRGB(110, 80, 56), 0.05)
	part(m, "Box", Vector3.new(5, 1.6, 2), cf * CFrame.new(0, 0.8, 0), color)
	part(m, "Water", Vector3.new(4.5, 0.2, 1.5), cf * CFrame.new(0, 1.55, 0), Color3.fromRGB(70, 110, 120), Enum.Material.Glass, true).Transparency = 0.2
	return m
end

function Props.buildWell(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Well", parent)
	local stone = PartUtil.vary(rng, Color3.fromRGB(140, 130, 120), 0.04)
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		part(m, "Stone", Vector3.new(1.4, 2.4, 1.1), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.2, -2.2), stone, Enum.Material.Cobblestone)
	end
	part(m, "Water", Vector3.new(0.2, 3.8, 3.8), cf * CFrame.new(0, 1.0, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(40, 60, 70), Enum.Material.Glass, true, Enum.PartType.Cylinder)
	local wood = Color3.fromRGB(110, 80, 56)
	for _, x in { -2.3, 2.3 } do
		part(m, "Upright", Vector3.new(0.4, 5, 0.4), cf * CFrame.new(x, 3.5, 0), wood)
	end
	part(m, "Axle", Vector3.new(5, 0.4, 0.4), cf * CFrame.new(0, 5.2, 0), wood, WOOD, true, Enum.PartType.Cylinder)
	for _, s in { -1, 1 } do
		part(m, "Roof", Vector3.new(6, 0.25, 2.6), cf * CFrame.new(0, 6.5, s * 1.1) * CFrame.Angles(math.rad(s * 30), 0, 0), Color3.fromRGB(96, 70, 50), WOOD, true)
	end
	part(m, "Bucket", Vector3.new(0.8, 0.9, 0.8), cf * CFrame.new(0, 3.6, 0), Color3.fromRGB(100, 76, 54), WOOD, true)
	return m
end

function Props.buildWaterTower(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("WaterTower", parent)
	local wood = PartUtil.vary(rng, Color3.fromRGB(120, 92, 66), 0.05)
	local h = rng:NextNumber(14, 18)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			cyl(m, "Leg", cf.Position + Vector3.new(sx * 3.4, -1, sz * 3.4), cf.Position + Vector3.new(sx * 2.6, h, sz * 2.6), 0.7, wood)
		end
	end
	for _, y in { h * 0.35, h * 0.7 } do
		for k = 0, 3 do
			local rot = CFrame.Angles(0, k * math.pi / 2, 0)
			part(m, "Brace", Vector3.new(0.25, 0.25, 6.4), cf * rot * CFrame.new(3, y, 0), wood, WOOD, true)
		end
	end
	part(m, "Platform", Vector3.new(8.5, 0.5, 8.5), cf * CFrame.new(0, h + 0.25, 0), wood)
	part(m, "Tank", Vector3.new(8, 8, 8), cf * CFrame.new(0, h + 4.5, 0) * CFrame.Angles(0, 0, math.rad(90)), wood, WOOD, false, Enum.PartType.Cylinder)
	for _, y in { 1.5, 4.5, 7.5 } do
		part(m, "Band", Vector3.new(0.3, 8.2, 8.2), cf * CFrame.new(0, h + y, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 58, 56), Enum.Material.Metal, true, Enum.PartType.Cylinder)
	end
	for _, s in { -1, 1 } do
		PartUtil.wedge({
			Name = "Roof",
			Size = Vector3.new(9, 3, 4.5),
			CFrame = cf * CFrame.new(0, h + 10, s * 2.25) * CFrame.Angles(0, if s > 0 then math.pi else 0, 0),
			Color = Color3.fromRGB(80, 60, 46),
			Material = WOOD,
			Decor = true,
			Parent = m,
		})
	end
	cyl(m, "Spout", cf.Position + Vector3.new(4, h + 2, 0), cf.Position + Vector3.new(6, h - 3, 0), 0.6, Color3.fromRGB(60, 58, 56), Enum.Material.Metal, true)
	return m
end

function Props.buildWindmill(rng: Random, cf: CFrame, parent: Instance): (Model, BasePart?)
	local m = model("Windmill", parent)
	local wood = PartUtil.vary(rng, Color3.fromRGB(130, 104, 78), 0.05)
	local h = rng:NextNumber(24, 32)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			cyl(m, "Leg", cf.Position + Vector3.new(sx * 3, -1, sz * 3), cf.Position + Vector3.new(sx * 0.6, h, sz * 0.6), 0.5, wood)
		end
	end
	for i = 1, 4 do
		local y = h * i / 5
		local half = 3 - 2.4 * i / 5
		for k = 0, 3 do
			local rot = CFrame.Angles(0, k * math.pi / 2, 0)
			part(m, "Brace", Vector3.new(0.2, 0.2, half * 2), cf * rot * CFrame.new(half, y, 0), wood, WOOD, true)
		end
	end
	part(m, "Head", Vector3.new(1.4, 1.4, 3), cf * CFrame.new(0, h + 0.5, 0), Color3.fromRGB(70, 66, 62), Enum.Material.Metal, true)
	part(m, "Vane", Vector3.new(0.15, 3, 4), cf * CFrame.new(0, h + 1, 3.4), Color3.fromRGB(150, 50, 40), Enum.Material.Metal, true)
	local rotorCF = cf * CFrame.new(0, h + 0.5, -1.8)
	local hub = part(m, "Rotor", Vector3.new(0.6, 1.2, 1.2), rotorCF * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(70, 66, 62), Enum.Material.Metal, true, Enum.PartType.Cylinder)
	-- Blades are welded to the hub; the client spins the hub locally.
	hub.Anchored = true
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2
		local blade = part(m, "Blade", Vector3.new(0.9, 4.2, 0.1), rotorCF * CFrame.Angles(0, 0, a) * CFrame.new(0, 2.9, -0.1) * CFrame.Angles(0, math.rad(20), 0), Color3.fromRGB(220, 214, 200), Enum.Material.Metal, true)
		blade.Anchored = false
		PartUtil.weld(hub, blade)
	end
	CollectionService:AddTag(hub, "SBR_Spinner")
	part(m, "Tank", Vector3.new(4, 6, 6), cf * CFrame.new(5, 2, 4) * CFrame.Angles(0, 0, math.rad(90)), wood, WOOD, false, Enum.PartType.Cylinder)
	return m, hub
end

function Props.buildCamp(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Camp", parent)
	-- Fire ring.
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		part(m, "FireStone", Vector3.new(0.9, 0.6, 0.9), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.3, -1.4), Color3.fromRGB(110, 104, 98), Enum.Material.Rock, true)
	end
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		local p = (cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.3, -0.8)).Position
		cyl(m, "Log", p, cf.Position + Vector3.new(0, 1, 0), 0.35, Color3.fromRGB(80, 56, 40), Enum.Material.Wood, true)
	end
	local ember = part(m, "Embers", Vector3.new(1.2, 0.3, 1.2), cf * CFrame.new(0, 0.3, 0), Color3.fromRGB(255, 120, 50), Enum.Material.Neon, true)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 7
	fire.Parent = ember
	PartUtil.light(ember, Color3.fromRGB(255, 150, 80), 20, 2)
	-- Tent.
	local tentCF = cf * CFrame.new(rng:NextNumber(-6, -4), 0, rng:NextNumber(3, 5)) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0)
	local canvas = PartUtil.vary(rng, Color3.fromRGB(214, 200, 170), 0.05)
	for _, s in { -1, 1 } do
		part(m, "Tent", Vector3.new(0.15, 4.6, 6), tentCF * CFrame.new(s * 1.6, 1.9, 0) * CFrame.Angles(0, 0, math.rad(s * 38)), canvas, Enum.Material.Fabric)
	end
	part(m, "Bedroll", Vector3.new(1.4, 0.4, 4), cf * CFrame.new(4, 0.2, 1) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0), Color3.fromRGB(120, 40, 36), Enum.Material.Fabric, true)
	cyl(m, "Seat", (cf * CFrame.new(-1.5, 0.5, -3)).Position, (cf * CFrame.new(1.5, 0.5, -3.2)).Position, 1, Color3.fromRGB(96, 70, 50), Enum.Material.Wood)
	return m
end

function Props.buildQuestBoard(rng: Random, cf: CFrame, parent: Instance, townIndex: number): Model
	local m = model("QuestBoard", parent)
	local wood = PartUtil.vary(rng, Color3.fromRGB(110, 80, 56), 0.05)
	for _, x in { -2.8, 2.8 } do
		part(m, "Post", Vector3.new(0.5, 7, 0.5), cf * CFrame.new(x, 3.5, 0), wood)
	end
	local board = part(m, "Board", Vector3.new(6, 4, 0.3), cf * CFrame.new(0, 4.4, 0), wood:Lerp(Color3.new(), 0.25))
	part(m, "Roof", Vector3.new(7, 0.3, 1.6), cf * CFrame.new(0, 6.9, -0.2) * CFrame.Angles(math.rad(-15), 0, 0), Color3.fromRGB(80, 60, 46), WOOD, true)
	local header = part(m, "Header", Vector3.new(5.6, 0.9, 0.1), cf * CFrame.new(0, 6.1, -0.2), Color3.fromRGB(46, 34, 26), WOOD, true)
	Buildings.sign(header, "QUESTS")
	for i = 0, 3 do
		part(m, "Notice", Vector3.new(1.2, 1.5, 0.05), cf * CFrame.new(-2 + i * 1.35, 4.3 + (i % 2) * 0.3, -0.18) * CFrame.Angles(0, 0, rng:NextNumber(-0.08, 0.08)), Color3.fromRGB(226, 214, 180), Enum.Material.SmoothPlastic, true)
	end
	board:SetAttribute("Town", townIndex)
	CollectionService:AddTag(board, "SBR_QuestBoard")
	return m
end

function Props.buildBench(rng: Random, cf: CFrame, parent: Instance): Model
	local m = model("Bench", parent)
	local wood = PartUtil.vary(rng, Color3.fromRGB(120, 90, 64), 0.05)
	part(m, "Seat", Vector3.new(5, 0.3, 1.4), cf * CFrame.new(0, 1.6, 0), wood)
	part(m, "Back", Vector3.new(5, 1.2, 0.2), cf * CFrame.new(0, 2.6, 0.6), wood, WOOD, true)
	for _, x in { -2.1, 2.1 } do
		part(m, "Leg", Vector3.new(0.3, 1.6, 1.2), cf * CFrame.new(x, 0.8, 0), wood, WOOD, true)
	end
	return m
end

function Props.buildMileMarker(cf: CFrame, parent: Instance, mile: number): Model
	local m = model("MileMarker", parent)
	local wood = Color3.fromRGB(140, 110, 80)
	part(m, "Post", Vector3.new(0.6, 5, 0.6), cf * CFrame.new(0, 2.5, 0), wood)
	local plate = part(m, "Plate", Vector3.new(2.4, 1.2, 0.2), cf * CFrame.new(0, 4.2, -0.4), Color3.fromRGB(230, 220, 196), WOOD, true)
	Buildings.sign(plate, "MILE " .. mile, Color3.fromRGB(46, 34, 26))
	local back = part(m, "PlateBack", Vector3.new(2.4, 1.2, 0.2), cf * CFrame.new(0, 4.2, 0.4), Color3.fromRGB(230, 220, 196), WOOD, true)
	Buildings.sign(back, "MILE " .. mile, Color3.fromRGB(46, 34, 26), Enum.NormalId.Back)
	return m
end

-- Wooden road bridge from a to b (deck endpoints on the banks).
function Props.buildBridge(rng: Random, a: Vector3, b: Vector3, width: number, waterY: number, parent: Instance): Model
	local m = model("Bridge", parent)
	local wood = PartUtil.vary(rng, Color3.fromRGB(120, 92, 66), 0.04)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local deckCF = CFrame.lookAt((a + b) / 2, b)
	part(m, "Deck", Vector3.new(width, 0.8, length), deckCF, wood, WOOD)
	-- Planks across the deck for texture.
	for i = 0, math.floor(length / 2) do
		local p = a + dir * (i * 2 + 1) + Vector3.new(0, 0.45, 0)
		part(m, "Plank", Vector3.new(width, 0.12, 1.6), CFrame.lookAt(p, p + dir), wood:Lerp(Color3.new(), 0.08 * (i % 3)), WOOD, true)
	end
	local right = dir:Cross(Vector3.yAxis)
	local spans = math.max(2, math.floor(length / 14))
	for i = 0, spans do
		local p = a + dir * (i * length / spans)
		for _, s in { -1, 1 } do
			local top = p + right * s * (width / 2 - 0.4)
			cyl(m, "Pile", top + Vector3.new(0, 0.3, 0), Vector3.new(top.X, waterY - 14, top.Z), 1.1, wood:Lerp(Color3.new(), 0.2))
			cyl(m, "RailPost", top, top + Vector3.new(0, 3.5, 0), 0.4, wood, WOOD, true)
		end
	end
	for _, s in { -1, 1 } do
		local off = right * s * (width / 2 - 0.4) + Vector3.new(0, 3.3, 0)
		cyl(m, "Rail", a + off, b + off, 0.35, wood)
		local mid = Vector3.new(0, -1.3, 0)
		cyl(m, "MidRail", a + off + mid, b + off + mid, 0.25, wood, WOOD, true)
	end
	return m
end

-- Railway trestle across a valley: deck at deckY from a to b.
function Props.buildTrestle(rng: Random, a: Vector3, b: Vector3, groundY: (Vector3) -> number, parent: Instance): Model
	local m = model("Trestle", parent)
	local wood = PartUtil.vary(rng, Color3.fromRGB(110, 84, 60), 0.04)
	local length = (b - a).Magnitude
	local dir = (b - a).Unit
	local right = dir:Cross(Vector3.yAxis)
	part(m, "Deck", Vector3.new(7, 1, length), CFrame.lookAt((a + b) / 2, b), wood, WOOD)
	local bents = math.max(2, math.floor(length / 10))
	for i = 0, bents do
		local p = a + dir * (i * length / bents)
		local gy = groundY(p) - 2
		local h = p.Y - gy
		if h > 1 then
			for _, s in { -1, 1 } do
				local top = p + right * s * 2.6
				local foot = Vector3.new(top.X, gy, top.Z) + right * s * (h * 0.12)
				cyl(m, "Bent", top, foot, 0.8, wood)
			end
			-- Cross bracing every few studs of height.
			local levels = math.floor(h / 8)
			for k = 1, levels do
				local y = p.Y - k * 8
				local w = 2.6 + (k * 8) * 0.12
				part(m, "Cross", Vector3.new(w * 2, 0.4, 0.4), CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(p.X, y, p.Z) + right) * CFrame.Angles(0, math.rad(90), 0), wood, WOOD, true)
			end
		end
	end
	-- Rails and ties.
	local metal = Color3.fromRGB(70, 66, 64)
	for _, s in { -1, 1 } do
		local off = right * s * 1.6 + Vector3.new(0, 0.7, 0)
		cyl(m, "Rail", a + off, b + off, 0.25, metal, Enum.Material.Metal, true)
	end
	for i = 0, math.floor(length / 2.5) do
		local p = a + dir * (i * 2.5) + Vector3.new(0, 0.55, 0)
		part(m, "Tie", Vector3.new(5, 0.3, 0.8), CFrame.lookAt(p, p + dir), Color3.fromRGB(80, 60, 44), WOOD, true)
	end
	return m
end

-- Checkpoint gate spanning the trail.
function Props.buildGate(cf: CFrame, parent: Instance, title: string, subtitle: string?): Model
	local m = model("CheckpointGate", parent)
	local wood = Color3.fromRGB(110, 80, 56)
	local half = Config.Map.TrailHalfWidth + 5
	for _, s in { -1, 1 } do
		part(m, "Pillar", Vector3.new(1.6, 16, 1.6), cf * CFrame.new(s * half, 7, 0), wood)
		part(m, "PillarCap", Vector3.new(2.2, 0.6, 2.2), cf * CFrame.new(s * half, 15.2, 0), Color3.fromRGB(80, 60, 44), WOOD, true)
		part(m, "Flag", Vector3.new(0.1, 2, 3), cf * CFrame.new(s * half, 17, 1.5), Color3.fromRGB(150, 44, 34), Enum.Material.Fabric, true)
		cyl(m, "FlagPole", (cf * CFrame.new(s * half, 15.4, 0)).Position, (cf * CFrame.new(s * half, 18.4, 0)).Position, 0.2, Color3.fromRGB(60, 58, 56), Enum.Material.Metal, true)
	end
	part(m, "Beam", Vector3.new(half * 2 + 2, 1.2, 1.2), cf * CFrame.new(0, 13.6, 0), wood)
	local banner = part(m, "Banner", Vector3.new(half * 1.7, 3.4, 0.2), cf * CFrame.new(0, 11.3, 0), Color3.fromRGB(230, 220, 196), Enum.Material.Fabric, true)
	local text = if subtitle then title .. "\n" .. subtitle else title
	Buildings.sign(banner, text, Color3.fromRGB(46, 34, 26), Enum.NormalId.Front)
	Buildings.sign(banner, text, Color3.fromRGB(46, 34, 26), Enum.NormalId.Back)
	return m
end

return Props
