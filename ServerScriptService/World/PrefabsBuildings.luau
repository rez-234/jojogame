--!strict
-- Procedural western buildings. Every builder takes a seeded Random, a ground
-- CFrame whose -Z faces the street, and a parent. Sizes, colors and trims are
-- varied from the Random so no two buildings match.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local PartUtil = require(ReplicatedStorage.Builders.PartUtil)
local Style = require(ReplicatedStorage.Shared.Style)

local Buildings = {}

type Ctx = {
	rng: Random,
	cf: CFrame,
	model: Model,
}

export type BuildingInfo = {
	Model: Model,
	Door: CFrame, -- world CFrame just outside the front door, facing out
	Inside: CFrame, -- world CFrame at the interior center
	Width: number,
	Depth: number,
}

local WOOD = Enum.Material.WoodPlanks
local WALL_T = 0.6
local FLOOR_Y = 0.8

local WALL_COLORS = {
	Color3.fromRGB(150, 112, 78),
	Color3.fromRGB(122, 88, 60),
	Color3.fromRGB(176, 146, 108),
	Color3.fromRGB(110, 84, 64),
	Color3.fromRGB(160, 132, 102),
	Color3.fromRGB(196, 178, 146),
	Color3.fromRGB(132, 104, 84),
	Color3.fromRGB(150, 74, 58),
	Color3.fromRGB(96, 104, 92),
}
local TRIM_COLORS = {
	Color3.fromRGB(230, 220, 196),
	Color3.fromRGB(70, 50, 38),
	Color3.fromRGB(120, 46, 38),
	Color3.fromRGB(60, 72, 66),
	Color3.fromRGB(214, 196, 150),
}
local ROOF_COLORS = {
	Color3.fromRGB(84, 62, 46),
	Color3.fromRGB(96, 52, 40),
	Color3.fromRGB(70, 66, 60),
	Color3.fromRGB(110, 86, 60),
}
local BRICK_COLORS = {
	Color3.fromRGB(150, 70, 52),
	Color3.fromRGB(122, 60, 48),
	Color3.fromRGB(160, 120, 96),
	Color3.fromRGB(110, 100, 94),
}

local function pick<T>(rng: Random, list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function P(ctx: Ctx, name: string, size: Vector3, lcf: CFrame, color: Color3, material: Enum.Material?, decor: boolean?, shape: Enum.PartType?): Part
	return PartUtil.part({
		Name = name,
		Size = size,
		CFrame = ctx.cf * lcf,
		Color = color,
		Material = material or WOOD,
		Decor = decor,
		Shape = shape,
		Parent = ctx.model,
	})
end

local function W(ctx: Ctx, name: string, size: Vector3, lcf: CFrame, color: Color3, material: Enum.Material?, decor: boolean?): WedgePart
	return PartUtil.wedge({
		Name = name,
		Size = size,
		CFrame = ctx.cf * lcf,
		Color = color,
		Material = material or WOOD,
		Decor = decor,
		Parent = ctx.model,
	})
end

local function newCtx(rng: Random, cf: CFrame, parent: Instance, name: string): Ctx
	local model = PartUtil.model(name, parent)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return { rng = rng, cf = cf, model = model }
end

-- Writes a sign on the street side of a part.
function Buildings.sign(part: BasePart, text: string, textColor: Color3?, face: Enum.NormalId?)
	local gui = Instance.new("SurfaceGui")
	gui.Name = "Sign"
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 1
	gui.MaxDistance = 220
	gui.Parent = part
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.FontFace = Style.Fonts.Sign
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = textColor or Style.Colors.Paper
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.12, 0)
	pad.PaddingBottom = UDim.new(0.12, 0)
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.Parent = label
end

type Opening = { Center: number, Width: number, Bottom: number, Top: number, Window: boolean }

-- A straight wall along local X from x0 to x1 at depth z, with openings.
local function wall(ctx: Ctx, x0: number, x1: number, z: number, y0: number, height: number, color: Color3, material: Enum.Material, openings: { Opening }, alongZ: boolean?, trim: Color3?)
	table.sort(openings, function(a, b)
		return a.Center < b.Center
	end)
	local function seg(a: number, b: number, ya: number, yb: number)
		if b - a < 0.05 or yb - ya < 0.05 then
			return
		end
		local mid = (a + b) / 2
		local size = Vector3.new(b - a, yb - ya, WALL_T)
		local lcf = CFrame.new(mid, (ya + yb) / 2, z)
		if alongZ then
			size = Vector3.new(WALL_T, yb - ya, b - a)
			lcf = CFrame.new(z, (ya + yb) / 2, mid)
		end
		P(ctx, "Wall", size, lcf, color, material)
	end
	local cursor = x0
	for _, o in openings do
		local a = o.Center - o.Width / 2
		local b = o.Center + o.Width / 2
		seg(cursor, a, y0, y0 + height)
		seg(a, b, y0, y0 + o.Bottom)
		seg(a, b, y0 + o.Top, y0 + height)
		if o.Window then
			local h = o.Top - o.Bottom
			local glassSize = Vector3.new(o.Width, h, 0.12)
			local glassCF = CFrame.new(o.Center, y0 + (o.Bottom + o.Top) / 2, z)
			if alongZ then
				glassSize = Vector3.new(0.12, h, o.Width)
				glassCF = CFrame.new(z, y0 + (o.Bottom + o.Top) / 2, o.Center)
			end
			local glass = P(ctx, "Window", glassSize, glassCF, Color3.fromRGB(40, 46, 50), Enum.Material.Glass)
			glass.Transparency = 0.35
			local t = trim or Color3.fromRGB(230, 220, 196)
			local frameSize = if alongZ then Vector3.new(WALL_T + 0.2, 0.25, o.Width + 0.5) else Vector3.new(o.Width + 0.5, 0.25, WALL_T + 0.2)
			local sillCF = if alongZ then CFrame.new(z, y0 + o.Bottom - 0.1, o.Center) else CFrame.new(o.Center, y0 + o.Bottom - 0.1, z)
			local headCF = if alongZ then CFrame.new(z, y0 + o.Top + 0.1, o.Center) else CFrame.new(o.Center, y0 + o.Top + 0.1, z)
			P(ctx, "Sill", frameSize, sillCF, t, WOOD, true)
			P(ctx, "Lintel", frameSize, headCF, t, WOOD, true)
			local mullionSize = if alongZ then Vector3.new(0.2, h, 0.15) else Vector3.new(0.15, h, 0.2)
			P(ctx, "Mullion", mullionSize, glassCF, t, WOOD, true)
		end
		cursor = b
	end
	seg(cursor, x1, y0, y0 + height)
end

export type ShellParams = {
	Name: string,
	Width: number,
	Depth: number,
	StoryHeight: number,
	Floors: number,
	WallColor: Color3,
	TrimColor: Color3,
	RoofColor: Color3,
	WallMaterial: Enum.Material?,
	Roof: string, -- "Gable", "Flat", "None"
	FalseFront: number?, -- extra facade height above the roof line
	Porch: boolean?,
	Balcony: boolean?,
	DoorWidth: number?,
	DoorHeight: number?,
	Sign: string?,
	WindowsPerSide: number?,
	NoBackWall: boolean?,
}

local function shell(ctx: Ctx, p: ShellParams): BuildingInfo
	local rng = ctx.rng
	local w, d = p.Width, p.Depth
	local hs = p.StoryHeight
	local floors = p.Floors
	local wallH = hs * floors
	local mat = p.WallMaterial or WOOD
	local doorW = p.DoorWidth or 4.5
	local doorH = p.DoorHeight or 7.5

	-- Foundation and floor.
	P(ctx, "Foundation", Vector3.new(w + 0.8, 5, d + 0.8), CFrame.new(0, FLOOR_Y - 2.9, d / 2), Color3.fromRGB(96, 88, 80), Enum.Material.Slate)
	P(ctx, "Floor", Vector3.new(w, 0.4, d), CFrame.new(0, FLOOR_Y - 0.2, d / 2), p.WallColor:Lerp(Color3.fromRGB(80, 60, 44), 0.5), WOOD)

	local windows = p.WindowsPerSide or (if w >= 14 then 2 else 1)
	-- Front wall.
	for f = 1, floors do
		local y0 = FLOOR_Y + (f - 1) * hs
		local openings: { Opening } = {}
		if f == 1 then
			table.insert(openings, { Center = 0, Width = doorW, Bottom = 0, Top = math.min(doorH, hs - 0.6), Window = false })
			local off = (w / 2 + doorW / 2) / 2
			if w - doorW > 7 then
				table.insert(openings, { Center = -off, Width = math.min(3.2, off - doorW / 2 - 0.5), Bottom = 2.6, Top = math.min(6.6, hs - 1), Window = true })
				table.insert(openings, { Center = off, Width = math.min(3.2, off - doorW / 2 - 0.5), Bottom = 2.6, Top = math.min(6.6, hs - 1), Window = true })
			end
		else
			for k = 1, windows + 1 do
				local cx = -w / 2 + k * w / (windows + 2)
				local o: Opening = { Center = cx, Width = 2.6, Bottom = 2.2, Top = math.min(6.2, hs - 1), Window = true }
				if p.Balcony and k == math.ceil((windows + 1) / 2) then
					o = { Center = cx, Width = 3.2, Bottom = 0, Top = math.min(7, hs - 0.8), Window = false }
				end
				table.insert(openings, o)
			end
		end
		wall(ctx, -w / 2, w / 2, WALL_T / 2, y0, hs, p.WallColor, mat, openings, false, p.TrimColor)
		-- Back wall.
		if not p.NoBackWall then
			local back: { Opening } = {}
			for k = 1, windows do
				table.insert(back, { Center = -w / 2 + k * w / (windows + 1), Width = 2.6, Bottom = 2.6, Top = math.min(6.2, hs - 1), Window = true })
			end
			wall(ctx, -w / 2, w / 2, d - WALL_T / 2, y0, hs, p.WallColor, mat, back, false, p.TrimColor)
		end
		-- Side walls.
		for _, side in { -1, 1 } do
			local sideOpenings: { Opening } = {}
			local count = math.max(1, math.floor(d / 8))
			for k = 1, count do
				table.insert(sideOpenings, { Center = WALL_T + k * (d - 2 * WALL_T) / (count + 1), Width = 2.6, Bottom = 2.6, Top = math.min(6.2, hs - 1), Window = true })
			end
			wall(ctx, WALL_T, d - WALL_T, side * (w / 2 - WALL_T / 2), y0, hs, p.WallColor, mat, sideOpenings, true, p.TrimColor)
		end
		if f > 1 then
			P(ctx, "UpperFloor", Vector3.new(w - WALL_T * 2, 0.35, d - WALL_T * 2), CFrame.new(0, y0 - 0.17, d / 2), p.WallColor:Lerp(Color3.fromRGB(80, 60, 44), 0.5), WOOD)
		end
		-- Trim band between floors.
		P(ctx, "Band", Vector3.new(w + 0.3, 0.3, 0.3), CFrame.new(0, y0 + hs - 0.15, -0.05), p.TrimColor, WOOD, true)
	end
	-- Corner posts.
	for _, sx in { -1, 1 } do
		for _, z in { 0.1, d - 0.1 } do
			P(ctx, "Corner", Vector3.new(0.5, wallH, 0.5), CFrame.new(sx * (w / 2 - 0.05), FLOOR_Y + wallH / 2, z), p.TrimColor, WOOD, true)
		end
	end

	local topY = FLOOR_Y + wallH
	-- Roof.
	if p.Roof == "Gable" then
		local rise = math.min(w * 0.35, 7)
		local over = 1
		for _, side in { -1, 1 } do
			W(ctx, "Roof", Vector3.new(d + over * 2, rise, w / 2 + over), CFrame.new(side * (w / 4 + over / 2), topY + rise / 2, d / 2) * CFrame.Angles(0, -side * math.pi / 2, 0), p.RoofColor, Enum.Material.WoodPlanks)
			for _, z in { WALL_T / 2, d - WALL_T / 2 } do
				W(ctx, "Gable", Vector3.new(WALL_T, rise, w / 2), CFrame.new(side * w / 4, topY + rise / 2, z) * CFrame.Angles(0, -side * math.pi / 2, 0), p.WallColor, mat)
			end
		end
		P(ctx, "Ridge", Vector3.new(0.5, 0.5, d + over * 2), CFrame.new(0, topY + rise + 0.1, d / 2), p.TrimColor, WOOD, true)
	elseif p.Roof == "Flat" then
		P(ctx, "Roof", Vector3.new(w + 0.4, 0.5, d + 0.4), CFrame.new(0, topY + 0.25, d / 2), p.RoofColor, Enum.Material.Slate)
		P(ctx, "Cornice", Vector3.new(w + 1.2, 0.6, 0.9), CFrame.new(0, topY + 0.6, 0), p.TrimColor, WOOD, true)
		for _, side in { -1, 1 } do
			P(ctx, "Parapet", Vector3.new(0.5, 1, d), CFrame.new(side * (w / 2), topY + 0.9, d / 2), p.WallColor, mat)
		end
		P(ctx, "Parapet", Vector3.new(w, 1, 0.5), CFrame.new(0, topY + 0.9, d), p.WallColor, mat)
	end

	-- False front facade with a sign board.
	if p.FalseFront and p.FalseFront > 0 then
		local fh = p.FalseFront + (if p.Roof == "Gable" then math.min(w * 0.35, 7) else 0)
		P(ctx, "Facade", Vector3.new(w + 0.4, fh, WALL_T), CFrame.new(0, topY + fh / 2, WALL_T / 2), p.WallColor, mat)
		P(ctx, "FacadeCap", Vector3.new(w + 1.2, 0.6, 1.2), CFrame.new(0, topY + fh + 0.3, WALL_T / 2), p.TrimColor, WOOD, true)
		for _, side in { -1, 1 } do
			P(ctx, "Bracket", Vector3.new(0.4, 1.2, 0.8), CFrame.new(side * (w / 2 - 0.3), topY + fh - 0.3, -0.1), p.TrimColor, WOOD, true)
		end
		if rng:NextNumber() < 0.5 then
			-- Stepped top.
			P(ctx, "Step", Vector3.new(w * 0.5, 1.4, WALL_T), CFrame.new(0, topY + fh + 0.7, WALL_T / 2), p.WallColor, mat)
			P(ctx, "StepCap", Vector3.new(w * 0.5 + 0.8, 0.4, 1.0), CFrame.new(0, topY + fh + 1.5, WALL_T / 2), p.TrimColor, WOOD, true)
		end
	end
	if p.Sign then
		local signY = if p.FalseFront and p.FalseFront > 0 then topY + 1.7 else FLOOR_Y + hs - 1.2
		local board = P(ctx, "SignBoard", Vector3.new(math.min(w - 2, #p.Sign * 1.2 + 2), 1.9, 0.25), CFrame.new(0, signY, -0.15), p.TrimColor:Lerp(Color3.fromRGB(40, 30, 24), 0.75), WOOD, true)
		Buildings.sign(board, p.Sign, p.TrimColor:Lerp(Color3.new(1, 1, 1), 0.4))
	end

	-- Porch, boardwalk and porch roof.
	if p.Porch then
		local pd = 4.5
		P(ctx, "Boardwalk", Vector3.new(w + 1.5, 0.4, pd), CFrame.new(0, FLOOR_Y - 0.2, -pd / 2), Color3.fromRGB(120, 90, 62), WOOD)
		P(ctx, "Step", Vector3.new(4, 0.4, 1), CFrame.new(0, FLOOR_Y * 0.4 - 0.2, -pd - 0.5), Color3.fromRGB(110, 82, 56), WOOD)
		local postH = hs - 0.4
		local posts = math.max(2, math.floor(w / 6) + 1)
		for i = 0, posts - 1 do
			local x = -w / 2 - 0.4 + i * (w + 0.8) / (posts - 1)
			P(ctx, "PorchPost", Vector3.new(0.45, postH, 0.45), CFrame.new(x, FLOOR_Y + postH / 2, -pd + 0.3), p.TrimColor, WOOD)
		end
		if p.Balcony and floors > 1 then
			P(ctx, "Balcony", Vector3.new(w + 1.5, 0.4, pd), CFrame.new(0, FLOOR_Y + hs, -pd / 2), Color3.fromRGB(120, 90, 62), WOOD)
			P(ctx, "Rail", Vector3.new(w + 1.5, 0.25, 0.25), CFrame.new(0, FLOOR_Y + hs + 3, -pd + 0.15), p.TrimColor, WOOD)
			for i = 0, math.floor(w / 1.2) do
				local x = -w / 2 - 0.6 + i * 1.2
				P(ctx, "Baluster", Vector3.new(0.15, 3, 0.15), CFrame.new(x, FLOOR_Y + hs + 1.5, -pd + 0.15), p.TrimColor, WOOD, true)
			end
		else
			P(ctx, "PorchRoof", Vector3.new(w + 2, 0.3, pd + 0.6), CFrame.new(0, FLOOR_Y + postH + 0.15, -pd / 2) * CFrame.Angles(math.rad(-6), 0, 0), p.RoofColor, WOOD)
		end
	end

	-- An open door panel so the doorway reads clearly.
	local hingeX = -doorW / 2
	P(ctx, "Door", Vector3.new(0.2, math.min(doorH, hs - 0.6) - 0.2, doorW / 2), CFrame.new(hingeX + 0.1, FLOOR_Y + (math.min(doorH, hs - 0.6)) / 2, WALL_T + doorW / 4), p.WallColor:Lerp(Color3.fromRGB(50, 34, 24), 0.5), WOOD, true)

	return {
		Model = ctx.model,
		Door = ctx.cf * CFrame.new(0, FLOOR_Y, -(if p.Porch then 5.5 else 1.5)) * CFrame.Angles(0, math.pi, 0),
		Inside = ctx.cf * CFrame.new(0, FLOOR_Y, d / 2),
		Width = w,
		Depth = d,
	}
end

local function table_(ctx: Ctx, x: number, z: number)
	local wood = Color3.fromRGB(110, 76, 50)
	P(ctx, "TableTop", Vector3.new(0.25, 3, 3), CFrame.new(x, FLOOR_Y + 2.6, z) * CFrame.Angles(0, 0, math.rad(90)), wood, WOOD, false, Enum.PartType.Cylinder)
	P(ctx, "TableLeg", Vector3.new(0.4, 2.5, 0.4), CFrame.new(x, FLOOR_Y + 1.25, z), wood, WOOD, true)
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2
		local sx, sz = x + math.cos(a) * 2.3, z + math.sin(a) * 2.3
		P(ctx, "Stool", Vector3.new(0.25, 1.3, 1.3), CFrame.new(sx, FLOOR_Y + 1.6, sz) * CFrame.Angles(0, 0, math.rad(90)), wood, WOOD, false, Enum.PartType.Cylinder)
		P(ctx, "StoolLeg", Vector3.new(0.25, 1.5, 0.25), CFrame.new(sx, FLOOR_Y + 0.75, sz), wood, WOOD, true)
	end
end

function Buildings.buildSaloon(rng: Random, cf: CFrame, parent: Instance): BuildingInfo
	local ctx = newCtx(rng, cf, parent, "Saloon")
	local w = rng:NextInteger(20, 24)
	local d = rng:NextInteger(20, 24)
	local info = shell(ctx, {
		Name = "Saloon",
		Width = w,
		Depth = d,
		StoryHeight = 9,
		Floors = 2,
		WallColor = PartUtil.vary(rng, pick(rng, WALL_COLORS), 0.05),
		TrimColor = pick(rng, TRIM_COLORS),
		RoofColor = pick(rng, ROOF_COLORS),
		Roof = "Flat",
		FalseFront = 4,
		Porch = true,
		Balcony = true,
		DoorWidth = 5,
		Sign = "SALOON",
	})
	-- Swinging doors.
	for _, s in { -1, 1 } do
		P(ctx, "BatDoor", Vector3.new(2.2, 3.2, 0.15), CFrame.new(s * 1.3, FLOOR_Y + 3.4, 0.3) * CFrame.Angles(0, math.rad(s * 20), 0), Color3.fromRGB(120, 80, 50), WOOD, true)
	end
	-- Bar counter, shelves and bottles.
	local barZ = d - 5
	P(ctx, "Bar", Vector3.new(w * 0.6, 3.6, 1.6), CFrame.new(-w * 0.15, FLOOR_Y + 1.8, barZ), Color3.fromRGB(96, 60, 38), WOOD)
	P(ctx, "BarTop", Vector3.new(w * 0.6 + 0.4, 0.25, 2), CFrame.new(-w * 0.15, FLOOR_Y + 3.7, barZ), Color3.fromRGB(70, 44, 28), WOOD)
	for shelf = 0, 1 do
		local y = FLOOR_Y + 4.5 + shelf * 1.6
		P(ctx, "Shelf", Vector3.new(w * 0.55, 0.2, 1), CFrame.new(-w * 0.15, y, d - 1.2), Color3.fromRGB(96, 60, 38), WOOD, true)
		for i = 0, 9 do
			local bottleColor = pick(rng, { Color3.fromRGB(60, 90, 50), Color3.fromRGB(120, 70, 40), Color3.fromRGB(150, 140, 120), Color3.fromRGB(80, 40, 30) })
			local b = P(ctx, "Bottle", Vector3.new(0.9, 0.4, 0.4), CFrame.new(-w * 0.15 - w * 0.25 + i * w * 0.055, y + 0.55, d - 1.2) * CFrame.Angles(0, 0, math.rad(90)), bottleColor, Enum.Material.Glass, true, Enum.PartType.Cylinder)
			b.Transparency = 0.2
		end
	end
	P(ctx, "Mirror", Vector3.new(w * 0.3, 2.4, 0.15), CFrame.new(-w * 0.15, FLOOR_Y + 7.8, d - WALL_T - 0.1), Color3.fromRGB(180, 190, 196), Enum.Material.Glass, true)
	table_(ctx, w * 0.22, d * 0.35)
	table_(ctx, -w * 0.25, d * 0.3)
	table_(ctx, w * 0.25, d * 0.62)
	-- Piano.
	P(ctx, "Piano", Vector3.new(4.5, 4, 1.8), CFrame.new(w / 2 - 3, FLOOR_Y + 2, d - 2), Color3.fromRGB(46, 30, 22), WOOD)
	P(ctx, "Keys", Vector3.new(4, 0.15, 0.8), CFrame.new(w / 2 - 3, FLOOR_Y + 2.6, d - 3.2), Color3.fromRGB(236, 230, 214), Enum.Material.SmoothPlastic, true)
	local lamp = P(ctx, "Chandelier", Vector3.new(0.3, 2.4, 2.4), CFrame.new(0, FLOOR_Y + 8, d / 2) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 48, 30), Enum.Material.Metal, true, Enum.PartType.Cylinder)
	PartUtil.light(lamp, Color3.fromRGB(255, 196, 120), 22, 1.4)
	return info
end

function Buildings.buildGeneralStore(rng: Random, cf: CFrame, parent: Instance): BuildingInfo
	local ctx = newCtx(rng, cf, parent, "GeneralStore")
	local w = rng:NextInteger(15, 18)
	local d = rng:NextInteger(16, 19)
	local info = shell(ctx, {
		Name = "GeneralStore",
		Width = w,
		Depth = d,
		StoryHeight = 10,
		Floors = 1,
		WallColor = PartUtil.vary(rng, pick(rng, WALL_COLORS), 0.05),
		TrimColor = pick(rng, TRIM_COLORS),
		RoofColor = pick(rng, ROOF_COLORS),
		Roof = "Gable",
		FalseFront = 2.5,
		Porch = true,
		Sign = "GENERAL STORE",
	})
	P(ctx, "Counter", Vector3.new(w * 0.6, 3.4, 1.4), CFrame.new(0, FLOOR_Y + 1.7, d - 5), Color3.fromRGB(110, 76, 50), WOOD)
	for shelf = 0, 2 do
		P(ctx, "Shelf", Vector3.new(w - 3, 0.2, 1.2), CFrame.new(0, FLOOR_Y + 2 + shelf * 1.8, d - 1.3), Color3.fromRGB(96, 66, 44), WOOD, true)
		for i = 0, 6 do
			local c = pick(rng, { Color3.fromRGB(180, 150, 100), Color3.fromRGB(140, 60, 40), Color3.fromRGB(70, 90, 110), Color3.fromRGB(210, 200, 170) })
			P(ctx, "Goods", Vector3.new(0.9, 1, 0.9), CFrame.new(-w / 2 + 2.5 + i * (w - 5) / 6, FLOOR_Y + 2.6 + shelf * 1.8, d - 1.3), c, Enum.Material.Fabric, true)
		end
	end
	for _, s in { -1, 1 } do
		Buildings.barrelAt(ctx, CFrame.new(s * (w / 2 - 1), FLOOR_Y, -1.6), rng)
		Buildings.crateAt(ctx, CFrame.new(s * (w / 2 - 2.6), FLOOR_Y, -1.2) * CFrame.Angles(0, rng:NextNumber(-0.3, 0.3), 0), rng)
	end
	local merchant = P(ctx, "MerchantSpot", Vector3.new(1, 1, 1), CFrame.new(0, FLOOR_Y + 0.5, d - 3.6), Color3.new(), WOOD, true)
	merchant.Transparency = 1
	CollectionService:AddTag(merchant, "SBR_Merchant")
	return info
end

function Buildings.buildStable(rng: Random, cf: CFrame, parent: Instance): BuildingInfo
	local ctx = newCtx(rng, cf, parent, "Stable")
	local w = rng:NextInteger(22, 26)
	local d = rng:NextInteger(22, 26)
	local barnRed = pick(rng, { Color3.fromRGB(130, 48, 38), Color3.fromRGB(110, 70, 50), Color3.fromRGB(150, 112, 78) })
	local info = shell(ctx, {
		Name = "Stable",
		Width = w,
		Depth = d,
		StoryHeight = 11,
		Floors = 1,
		WallColor = PartUtil.vary(rng, barnRed, 0.04),
		TrimColor = Color3.fromRGB(230, 220, 196),
		RoofColor = pick(rng, ROOF_COLORS),
		Roof = "Gable",
		DoorWidth = 8,
		DoorHeight = 9,
		Sign = "STABLE",
		WindowsPerSide = 1,
	})
	-- Cross bracing on the big door panels.
	for _, s in { -1, 1 } do
		local x = s * 6
		P(ctx, "BarnDoor", Vector3.new(4, 8.6, 0.3), CFrame.new(x, FLOOR_Y + 4.3, -0.3), Color3.fromRGB(110, 60, 44), WOOD)
		P(ctx, "Brace", Vector3.new(0.3, 9.4, 0.2), CFrame.new(x, FLOOR_Y + 4.3, -0.5) * CFrame.Angles(0, 0, math.rad(s * 25)), Color3.fromRGB(230, 220, 196), WOOD, true)
	end
	-- Stalls.
	local stalls = 4
	for i = 0, stalls - 1 do
		local z = 5 + i * (d - 8) / stalls
		for _, s in { -1, 1 } do
			P(ctx, "Stall", Vector3.new(w * 0.32, 4, 0.3), CFrame.new(s * (w / 2 - w * 0.16 - 0.6), FLOOR_Y + 2, z), Color3.fromRGB(110, 80, 56), WOOD)
			P(ctx, "Hay", Vector3.new(2.4, 1.4, 1.6), CFrame.new(s * (w / 2 - 2), FLOOR_Y + 0.7, z + 2.5), Color3.fromRGB(212, 180, 100), Enum.Material.Grass, true)
		end
	end
	P(ctx, "Trough", Vector3.new(1.4, 1.2, d - 8), CFrame.new(0, FLOOR_Y + 0.6, d / 2 + 1), Color3.fromRGB(96, 70, 50), WOOD)
	P(ctx, "TroughWater", Vector3.new(1.0, 0.2, d - 8.4), CFrame.new(0, FLOOR_Y + 1.15, d / 2 + 1), Color3.fromRGB(70, 110, 120), Enum.Material.Glass, true)
	-- Hay loft door.
	P(ctx, "LoftDoor", Vector3.new(3.5, 3, 0.3), CFrame.new(0, FLOOR_Y + 13.3, -0.1), Color3.fromRGB(110, 60, 44), WOOD, true)

	-- Dealer and heal markers in front of the stable.
	local dealer = P(ctx, "DealerSpot", Vector3.new(1, 1, 1), CFrame.new(-w / 2 + 2, FLOOR_Y + 0.5, -3), Color3.new(), WOOD, true)
	dealer.Transparency = 1
	CollectionService:AddTag(dealer, "SBR_HorseDealer")
	local healer = P(ctx, "HealStation", Vector3.new(3, 1.2, 1.4), CFrame.new(w / 2 - 2.5, FLOOR_Y + 0.6, -3), Color3.fromRGB(96, 70, 50), WOOD)
	P(ctx, "HealWater", Vector3.new(2.6, 0.2, 1.0), CFrame.new(w / 2 - 2.5, FLOOR_Y + 1.15, -3), Color3.fromRGB(70, 110, 120), Enum.Material.Glass, true)
	CollectionService:AddTag(healer, "SBR_HealStation")

	-- Paddock fence beside the barn.
	local fenceColor = Color3.fromRGB(140, 110, 80)
	local px = w / 2 + 9
	for _, seg in { { Vector3.new(px - 7, 0, -2), Vector3.new(px + 7, 0, -2) }, { Vector3.new(px + 7, 0, -2), Vector3.new(px + 7, 0, d - 2) }, { Vector3.new(px - 7, 0, d - 2), Vector3.new(px + 7, 0, d - 2) } } do
		Buildings.fenceRun(ctx, seg[1], seg[2], fenceColor)
	end
	return info
end

function Buildings.buildHouse(rng: Random, cf: CFrame, parent: Instance): BuildingInfo
	local ctx = newCtx(rng, cf, parent, "House")
	local w = rng:NextInteger(10, 14)
	local d = rng:NextInteger(11, 15)
	local wallColor = PartUtil.vary(rng, pick(rng, WALL_COLORS), 0.06)
	local info = shell(ctx, {
		Name = "House",
		Width = w,
		Depth = d,
		StoryHeight = 8,
		Floors = 1,
		WallColor = wallColor,
		TrimColor = pick(rng, TRIM_COLORS),
		RoofColor = pick(rng, ROOF_COLORS),
		Roof = "Gable",
		Porch = rng:NextNumber() < 0.6,
		DoorWidth = 3.6,
	})
	-- Chimney.
	local cx = (if rng:NextNumber() < 0.5 then -1 else 1) * (w / 2 - 1.2)
	P(ctx, "Chimney", Vector3.new(1.6, 12, 1.6), CFrame.new(cx, FLOOR_Y + 6, d - 2), Color3.fromRGB(120, 76, 60), Enum.Material.Brick)
	-- Shutters.
	for _, s in { -1, 1 } do
		P(ctx, "Shutter", Vector3.new(0.15, 3.6, 1.4), CFrame.new(s * (w / 2 + 0.05), FLOOR_Y + 4.4, d * 0.35), wallColor:Lerp(Color3.new(), 0.35), WOOD, true)
	end
	-- Bed and table.
	P(ctx, "Bed", Vector3.new(3, 1.4, 6), CFrame.new(-w / 2 + 2.4, FLOOR_Y + 0.7, d - 4), Color3.fromRGB(180, 160, 130), Enum.Material.Fabric)
	table_(ctx, w / 4, d / 2)
	return info
end

function Buildings.buildBank(rng: Random, cf: CFrame, parent: Instance): BuildingInfo
	local ctx = newCtx(rng, cf, parent, "Bank")
	local w = rng:NextInteger(16, 19)
	local d = rng:NextInteger(17, 20)
	local brick = rng:NextNumber() < 0.6
	local info = shell(ctx, {
		Name = "Bank",
		Width = w,
		Depth = d,
		StoryHeight = 11,
		Floors = 1,
		WallColor = if brick then pick(rng, BRICK_COLORS) else Color3.fromRGB(200, 190, 170),
		WallMaterial = if brick then Enum.Material.Brick else Enum.Material.Limestone,
		TrimColor = Color3.fromRGB(226, 216, 196),
		RoofColor = Color3.fromRGB(80, 76, 72),
		Roof = "Flat",
		FalseFront = 1.5,
		DoorWidth = 4,
		Sign = "BANK",
	})
	for _, s in { -1, 1 } do
		P(ctx, "Column", Vector3.new(10.4, 1.2, 1.2), CFrame.new(s * 3.4, FLOOR_Y + 5.2, -0.8) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(226, 216, 196), Enum.Material.Marble, false, Enum.PartType.Cylinder)
	end
	P(ctx, "Steps", Vector3.new(9, 0.5, 2), CFrame.new(0, FLOOR_Y - 0.25, -1.4), Color3.fromRGB(200, 196, 186), Enum.Material.Marble)
	P(ctx, "Vault", Vector3.new(6, 7, 3.5), CFrame.new(0, FLOOR_Y + 3.5, d - 2.4), Color3.fromRGB(70, 72, 76), Enum.Material.DiamondPlate)
	P(ctx, "VaultWheel", Vector3.new(0.3, 2.2, 2.2), CFrame.new(0, FLOOR_Y + 3.5, d - 4.25) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(190, 160, 80), Enum.Material.Metal, true, Enum.PartType.Cylinder)
	P(ctx, "TellerCounter", Vector3.new(w - 4, 3.6, 1.2), CFrame.new(0, FLOOR_Y + 1.8, d * 0.45), Color3.fromRGB(96, 60, 38), WOOD)
	for i = -2, 2 do
		P(ctx, "Bars", Vector3.new(0.12, 3, 0.12), CFrame.new(i * (w - 5) / 5, FLOOR_Y + 5.1, d * 0.45), Color3.fromRGB(190, 160, 80), Enum.Material.Metal, true)
	end
	return info
end

function Buildings.buildSheriffOffice(rng: Random, cf: CFrame, parent: Instance): BuildingInfo
	local ctx = newCtx(rng, cf, parent, "SheriffOffice")
	local w = rng:NextInteger(13, 16)
	local d = rng:NextInteger(15, 18)
	local info = shell(ctx, {
		Name = "SheriffOffice",
		Width = w,
		Depth = d,
		StoryHeight = 9.5,
		Floors = 1,
		WallColor = PartUtil.vary(rng, pick(rng, WALL_COLORS), 0.05),
		TrimColor = pick(rng, TRIM_COLORS),
		RoofColor = pick(rng, ROOF_COLORS),
		Roof = "Flat",
		FalseFront = 3,
		Porch = true,
		Sign = "SHERIFF",
	})
	-- Jail cell with bars.
	local cellW = w * 0.45
	local cellZ = d - 4
	for i = 0, math.floor(cellW / 0.7) do
		P(ctx, "CellBar", Vector3.new(0.18, 7.5, 0.18), CFrame.new(w / 2 - cellW + i * 0.7, FLOOR_Y + 3.75, cellZ - 3), Color3.fromRGB(60, 60, 64), Enum.Material.Metal)
	end
	P(ctx, "Cot", Vector3.new(cellW - 1.5, 1, 2.4), CFrame.new(w / 2 - cellW / 2, FLOOR_Y + 0.5, d - 2), Color3.fromRGB(140, 130, 110), Enum.Material.Fabric)
	P(ctx, "Desk", Vector3.new(4, 2.6, 2.2), CFrame.new(-w / 4, FLOOR_Y + 1.3, d / 2 - 1), Color3.fromRGB(96, 60, 38), WOOD)
	-- Wanted posters out front.
	for i = 0, 2 do
		Buildings.posterAt(ctx, CFrame.new(-w / 2 + 1.6 + i * 1.8, FLOOR_Y + 4.5, -0.05), rng)
	end
	return info
end

function Buildings.buildHotel(rng: Random, cf: CFrame, parent: Instance): BuildingInfo
	local ctx = newCtx(rng, cf, parent, "Hotel")
	local w = rng:NextInteger(20, 24)
	local d = rng:NextInteger(16, 19)
	local floors = rng:NextInteger(2, 3)
	local info = shell(ctx, {
		Name = "Hotel",
		Width = w,
		Depth = d,
		StoryHeight = 8.5,
		Floors = floors,
		WallColor = PartUtil.vary(rng, pick(rng, WALL_COLORS), 0.05),
		TrimColor = pick(rng, TRIM_COLORS),
		RoofColor = pick(rng, ROOF_COLORS),
		Roof = "Flat",
		FalseFront = 2,
		Porch = true,
		Balcony = true,
		Sign = "HOTEL",
		WindowsPerSide = 3,
	})
	P(ctx, "Desk", Vector3.new(6, 3.4, 1.6), CFrame.new(w / 4, FLOOR_Y + 1.7, d - 4), Color3.fromRGB(96, 60, 38), WOOD)
	P(ctx, "Rug", Vector3.new(6, 0.08, 9), CFrame.new(0, FLOOR_Y + 0.04, d / 2), Color3.fromRGB(130, 40, 36), Enum.Material.Fabric, true)
	return info
end

function Buildings.buildBlacksmith(rng: Random, cf: CFrame, parent: Instance): BuildingInfo
	local ctx = newCtx(rng, cf, parent, "Blacksmith")
	local w = rng:NextInteger(14, 17)
	local d = rng:NextInteger(12, 15)
	local wood = PartUtil.vary(rng, Color3.fromRGB(110, 80, 56), 0.05)
	P(ctx, "Foundation", Vector3.new(w + 0.8, 5, d + 0.8), CFrame.new(0, FLOOR_Y - 2.9, d / 2), Color3.fromRGB(96, 88, 80), Enum.Material.Slate)
	P(ctx, "Floor", Vector3.new(w, 0.4, d), CFrame.new(0, FLOOR_Y - 0.2, d / 2), Color3.fromRGB(80, 74, 68), Enum.Material.Slate)
	local h = 9
	for _, sx in { -1, 1 } do
		for _, z in { 0.4, d / 2, d - 0.4 } do
			P(ctx, "Post", Vector3.new(0.7, h, 0.7), CFrame.new(sx * (w / 2 - 0.4), FLOOR_Y + h / 2, z), wood, WOOD)
		end
	end
	-- Back wall only; the shop is open to the street.
	P(ctx, "BackWall", Vector3.new(w, h, WALL_T), CFrame.new(0, FLOOR_Y + h / 2, d - WALL_T / 2), wood, WOOD)
	for _, side in { -1, 1 } do
		W(ctx, "Roof", Vector3.new(d + 2, 3.5, w / 2 + 1), CFrame.new(side * (w / 4 + 0.5), FLOOR_Y + h + 1.75, d / 2) * CFrame.Angles(0, -side * math.pi / 2, 0), pick(rng, ROOF_COLORS), WOOD)
	end
	local signBoard = P(ctx, "SignBoard", Vector3.new(9, 1.8, 0.25), CFrame.new(0, FLOOR_Y + h - 1.2, 0.2), Color3.fromRGB(46, 34, 26), WOOD, true)
	Buildings.sign(signBoard, "BLACKSMITH")
	-- Forge with fire.
	P(ctx, "Forge", Vector3.new(4.5, 3.4, 3.5), CFrame.new(-w / 4, FLOOR_Y + 1.7, d - 3), Color3.fromRGB(120, 70, 56), Enum.Material.Brick)
	local coals = P(ctx, "Coals", Vector3.new(3, 0.3, 2.4), CFrame.new(-w / 4, FLOOR_Y + 3.5, d - 3), Color3.fromRGB(255, 110, 40), Enum.Material.Neon, true)
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 140, 60)
	fire.SecondaryColor = Color3.fromRGB(255, 60, 20)
	fire.Parent = coals
	PartUtil.light(coals, Color3.fromRGB(255, 140, 70), 18, 2)
	P(ctx, "Hood", Vector3.new(4, 2.5, 3), CFrame.new(-w / 4, FLOOR_Y + 7.2, d - 3), Color3.fromRGB(60, 56, 54), Enum.Material.Metal, true)
	P(ctx, "Flue", Vector3.new(1.2, 6, 1.2), CFrame.new(-w / 4, FLOOR_Y + 10.5, d - 3), Color3.fromRGB(60, 56, 54), Enum.Material.Metal, true)
	-- Anvil.
	P(ctx, "AnvilBase", Vector3.new(1.2, 2.2, 1.2), CFrame.new(w / 6, FLOOR_Y + 1.1, d / 2), Color3.fromRGB(80, 60, 44), WOOD)
	P(ctx, "Anvil", Vector3.new(2.6, 0.9, 1.1), CFrame.new(w / 6, FLOOR_Y + 2.65, d / 2), Color3.fromRGB(50, 50, 54), Enum.Material.Metal)
	W(ctx, "AnvilHorn", Vector3.new(0.8, 0.6, 1.2), CFrame.new(w / 6 - 1.9, FLOOR_Y + 2.8, d / 2) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(50, 50, 54), Enum.Material.Metal, true)
	P(ctx, "Quench", Vector3.new(2.4, 1.6, 1.6), CFrame.new(w / 3, FLOOR_Y + 0.8, d - 2), Color3.fromRGB(96, 70, 50), WOOD)
	-- Horseshoes on the wall.
	for i = 0, 4 do
		P(ctx, "Horseshoe", Vector3.new(0.6, 0.15, 0.6), CFrame.new(-w / 2 + 2 + i * 1.2, FLOOR_Y + 5, d - WALL_T - 0.1) * CFrame.Angles(math.rad(90), 0, 0), Color3.fromRGB(90, 90, 96), Enum.Material.Metal, true)
	end
	return {
		Model = ctx.model,
		Door = ctx.cf * CFrame.new(0, FLOOR_Y, -1.5) * CFrame.Angles(0, math.pi, 0),
		Inside = ctx.cf * CFrame.new(0, FLOOR_Y, d / 2),
		Width = w,
		Depth = d,
	}
end

function Buildings.buildBrick(rng: Random, cf: CFrame, parent: Instance, label: string?): BuildingInfo
	local ctx = newCtx(rng, cf, parent, "BrickBuilding")
	local w = rng:NextInteger(16, 24)
	local d = rng:NextInteger(16, 22)
	local floors = rng:NextInteger(3, 5)
	return shell(ctx, {
		Name = "BrickBuilding",
		Width = w,
		Depth = d,
		StoryHeight = 8,
		Floors = floors,
		WallColor = PartUtil.vary(rng, pick(rng, BRICK_COLORS), 0.04),
		WallMaterial = Enum.Material.Brick,
		TrimColor = Color3.fromRGB(220, 212, 196),
		RoofColor = Color3.fromRGB(70, 66, 64),
		Roof = "Flat",
		Sign = label,
		WindowsPerSide = 3,
		Porch = false,
	})
end

function Buildings.buildClockTower(rng: Random, cf: CFrame, parent: Instance): (Model, { Part })
	local ctx = newCtx(rng, cf, parent, "ClockTower")
	local stone = Color3.fromRGB(176, 166, 150)
	local w = 14
	local h = 58
	P(ctx, "Base", Vector3.new(w + 4, 3, w + 4), CFrame.new(0, 1.5, 0), Color3.fromRGB(150, 142, 130), Enum.Material.Cobblestone)
	-- Hollow tower shaft with an arched entry on each side.
	for _, side in { -1, 1 } do
		P(ctx, "Shaft", Vector3.new(1.6, h, w), CFrame.new(side * (w / 2 - 0.8), 3 + h / 2, 0), stone, Enum.Material.Limestone)
		P(ctx, "Shaft", Vector3.new(w - 3.2, h - 12, 1.6), CFrame.new(0, 15 + (h - 12) / 2, side * (w / 2 - 0.8)), stone, Enum.Material.Limestone)
		P(ctx, "Lintel", Vector3.new(w - 3.2, 2, 1.6), CFrame.new(0, 12, side * (w / 2 - 0.8)), stone:Lerp(Color3.new(), 0.1), Enum.Material.Limestone)
	end
	for k = 1, 3 do
		P(ctx, "Band", Vector3.new(w + 0.8, 0.8, w + 0.8), CFrame.new(0, 3 + k * h / 4, 0), Color3.fromRGB(150, 140, 126), Enum.Material.Limestone, true)
	end
	-- Belfry and spire.
	local topY = 3 + h
	P(ctx, "Belfry", Vector3.new(w + 1, 1.2, w + 1), CFrame.new(0, topY + 0.6, 0), Color3.fromRGB(150, 140, 126), Enum.Material.Limestone)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			P(ctx, "BelfryPost", Vector3.new(1.4, 8, 1.4), CFrame.new(sx * (w / 2 - 0.7), topY + 5, sz * (w / 2 - 0.7)), stone, Enum.Material.Limestone)
		end
	end
	P(ctx, "Bell", Vector3.new(3.5, 3.5, 3.5), CFrame.new(0, topY + 5, 0), Color3.fromRGB(180, 140, 70), Enum.Material.Metal, true, Enum.PartType.Ball)
	P(ctx, "Cap", Vector3.new(w + 1.4, 1, w + 1.4), CFrame.new(0, topY + 9.5, 0), Color3.fromRGB(70, 80, 76), Enum.Material.Slate)
	for _, side in { -1, 1 } do
		W(ctx, "Spire", Vector3.new(w + 1.4, 12, w / 2 + 0.7), CFrame.new(side * (w / 4 + 0.35), topY + 16, 0) * CFrame.Angles(0, -side * math.pi / 2, 0), Color3.fromRGB(70, 92, 84), Enum.Material.Slate)
	end
	-- Clock faces on all four sides with hands the server turns.
	local hands: { Part } = {}
	local faceY = 3 + h * 0.82
	for i = 0, 3 do
		local rot = CFrame.Angles(0, i * math.pi / 2, 0)
		local faceCF = rot * CFrame.new(0, faceY, -w / 2 - 0.25)
		P(ctx, "ClockRim", Vector3.new(0.4, 9.4, 9.4), faceCF * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(60, 50, 40), Enum.Material.Metal, true, Enum.PartType.Cylinder)
		P(ctx, "ClockFace", Vector3.new(0.5, 8.6, 8.6), faceCF * CFrame.new(0, 0, -0.05) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(240, 232, 214), Enum.Material.SmoothPlastic, true, Enum.PartType.Cylinder)
		for k = 0, 11 do
			local a = k / 12 * math.pi * 2
			P(ctx, "Tick", Vector3.new(0.25, if k % 3 == 0 then 1 else 0.6, 0.1), faceCF * CFrame.new(0, 0, -0.32) * CFrame.Angles(0, 0, -a) * CFrame.new(0, 3.6, 0), Color3.fromRGB(40, 32, 26), Enum.Material.SmoothPlastic, true)
		end
		local hour = P(ctx, "HourHand", Vector3.new(0.35, 2.4, 0.1), faceCF * CFrame.new(0, 1.1, -0.38), Color3.fromRGB(30, 24, 20), Enum.Material.Metal, true)
		local minute = P(ctx, "MinuteHand", Vector3.new(0.25, 3.4, 0.1), faceCF * CFrame.new(0, 1.6, -0.42), Color3.fromRGB(30, 24, 20), Enum.Material.Metal, true)
		hour:SetAttribute("Pivot", ctx.cf * faceCF * CFrame.new(0, 0, -0.38))
		minute:SetAttribute("Pivot", ctx.cf * faceCF * CFrame.new(0, 0, -0.42))
		table.insert(hands, hour)
		table.insert(hands, minute)
	end
	return ctx.model, hands
end

-- Small props used by buildings. They take a Ctx so they inherit its CFrame.
function Buildings.barrelAt(ctx: Ctx, lcf: CFrame, rng: Random)
	local color = PartUtil.vary(rng, Color3.fromRGB(120, 82, 52), 0.05)
	P(ctx, "Barrel", Vector3.new(3, 2.2, 2.2), lcf * CFrame.new(0, 1.5, 0) * CFrame.Angles(0, 0, math.rad(90)), color, WOOD, false, Enum.PartType.Cylinder)
	for _, y in { 0.5, 2.5 } do
		P(ctx, "Hoop", Vector3.new(0.2, 2.3, 2.3), lcf * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(60, 60, 62), Enum.Material.Metal, true, Enum.PartType.Cylinder)
	end
end

function Buildings.crateAt(ctx: Ctx, lcf: CFrame, rng: Random)
	local s = rng:NextNumber(1.8, 2.6)
	local color = PartUtil.vary(rng, Color3.fromRGB(160, 124, 84), 0.06)
	P(ctx, "Crate", Vector3.new(s, s, s), lcf * CFrame.new(0, s / 2, 0), color, WOOD)
	P(ctx, "Slat", Vector3.new(s + 0.05, 0.25, 0.25), lcf * CFrame.new(0, s / 2, -s / 2) * CFrame.Angles(0, 0, math.rad(45)), color:Lerp(Color3.new(), 0.3), WOOD, true)
end

function Buildings.posterAt(ctx: Ctx, lcf: CFrame, rng: Random)
	local poster = P(ctx, "Poster", Vector3.new(1.5, 2, 0.06), lcf, Color3.fromRGB(226, 210, 170), Enum.Material.SmoothPlastic, true)
	local names = { "D. BRANDO", "MAGENTA", "WEKAPIPO", "GYRO Z.", "J. JOESTAR", "LUCY S.", "AXL RO", "HOT PANTS" }
	local reward = rng:NextInteger(2, 50) * 100
	Buildings.sign(poster, "WANTED\n" .. names[rng:NextInteger(1, #names)] .. "\n$" .. reward, Color3.fromRGB(46, 34, 26))
end

function Buildings.fenceRun(ctx: Ctx, a: Vector3, b: Vector3, color: Color3)
	local length = (b - a).Magnitude
	local posts = math.max(2, math.floor(length / 4) + 1)
	local dir = (b - a).Unit
	for i = 0, posts - 1 do
		local p = a + dir * (i * length / (posts - 1))
		P(ctx, "FencePost", Vector3.new(0.4, 3.6, 0.4), CFrame.new(p + Vector3.new(0, 1.8, 0)), color, WOOD)
	end
	local mid = (a + b) / 2
	for _, y in { 1.2, 2.6 } do
		local up = Vector3.new(0, y, 0)
		P(ctx, "FenceRail", Vector3.new(0.25, 0.35, length), CFrame.lookAt(mid + up, b + up), color, WOOD)
	end
end

return Buildings
