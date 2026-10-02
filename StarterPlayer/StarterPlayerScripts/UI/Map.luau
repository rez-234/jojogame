--!strict
-- The route progress bar across the top of the screen and the minimap in the
-- top right corner. The bar shows how far along the whole trail you are,
-- stage boundaries, checkpoints and, during a race, every rider. The minimap
-- is drawn north up from the shared route data with towns, checkpoints,
-- boss arenas, landmarks, other riders and your horse.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Route = require(ReplicatedStorage.Shared.Route)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Kit = require(script.Parent.Kit)
local RaceHud = require(script.Parent.RaceHud)
local State = require(script.Parent.Parent.Controllers.State)

local Map = {}

local C = Kit.Colors
local S = Kit.Space
local player = Players.LocalPlayer

local BAR_WIDTH = 560
local MAP_SIZE = 190
local STUDS_PER_PIXEL = 4
local ROUTE_STEP = 40

local LANDMARK_NAMES: { [string]: string } = {
	Lighthouse = "Lighthouse",
	RockArch = "Rock Arch",
	GiantMesa = "Mesa",
	Waterfall = "Falls",
	WindmillFarm = "Windmills",
	GreatSequoia = "Sequoia",
	TrestleBridge = "Trestle",
	OldFort = "Fort",
	ClockTower = "Clock Tower",
}

-- Route bar ---------------------------------------------------------------------------

local stageLabel: TextLabel
local percentLabel: TextLabel
local barFill: Frame
local barTrack: Frame
local youMarker: Frame
local riderMarkers: { Frame } = {}

local function diamond(parent: Instance, size: number, color: Color3, z: number?): Frame
	return Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Rotation = 45,
		Size = UDim2.fromOffset(size, size),
		ZIndex = z or 2,
		Parent = parent,
	})
end

local function buildBar(screen: ScreenGui)
	local panel = Kit.Panel({
		Name = "RouteBar",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, S.L),
		Size = UDim2.fromOffset(BAR_WIDTH, 62),
		Parent = screen,
	})
	Kit.Padding(S.S, S.M).Parent = panel
	Kit.new("UISizeConstraint", { MaxSize = Vector2.new(BAR_WIDTH, 62), Parent = panel })
	panel.Size = UDim2.new(0.4, 0, 0, 62)
	stageLabel = Kit.Label("", { FontFace = Kit.Fonts.Heading, TextSize = 15, Size = UDim2.new(0.7, 0, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd, Parent = panel })
	percentLabel = Kit.Label("", { FontFace = Kit.Fonts.Numbers, TextSize = 13, TextColor3 = C.InkSoft, Size = UDim2.new(0.3, 0, 0, 18), Position = UDim2.fromScale(0.7, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = panel })
	barTrack = Kit.new("Frame", {
		BackgroundColor3 = C.Track,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 0, 0, 28),
		Size = UDim2.new(1, 0, 0, 8),
		Parent = panel,
	}, { Kit.Corner(2) })
	barFill = Kit.new("Frame", { BackgroundColor3 = C.Brass, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = barTrack }, { Kit.Corner(2) })
	-- Stage boundaries.
	for i = 2, #Route.Stages do
		local frac = Route.StageStartDist(Route.Stages[i]) / Route.Length
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Ink,
			BorderSizePixel = 0,
			Position = UDim2.new(frac, 0, 0.5, 0),
			Size = UDim2.fromOffset(2, 14),
			ZIndex = 2,
			Parent = barTrack,
		})
	end
	-- Towns as small squares under the bar.
	for _, town in Layout.Towns do
		local frac = ((town.Dist0 + town.Dist1) / 2) / Route.Length
		Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			BackgroundColor3 = C.Leather,
			BorderSizePixel = 0,
			Position = UDim2.new(frac, 0, 1, 3),
			Size = UDim2.fromOffset(4, 4),
			Parent = barTrack,
		})
	end
	for _, cp in Layout.Checkpoints do
		local d = diamond(barTrack, 7, C.Brass, 3)
		d.Position = UDim2.new(cp.Dist / Route.Length, 0, 0.5, 0)
	end
	youMarker = diamond(barTrack, 12, C.Accent, 5)
	local stroke = Kit.Stroke(C.Paper, 1)
	stroke.Parent = youMarker
end

local function stepBar(root: BasePart?)
	if not root then
		return
	end
	local d = Route.Project(root.Position)
	local frac = d / Route.Length
	barFill.Size = UDim2.fromScale(frac, 1)
	youMarker.Position = UDim2.new(frac, 0, 0.5, 0)
	local stage = Route.StageAtDist(d)
	stageLabel.Text = string.format("%s, %s", stage.Name, stage.Region)
	percentLabel.Text = string.format("%d%% to New York", math.floor(frac * 100))

	-- Race riders.
	local rows = RaceHud.Rows
	local count = 0
	for _, r in rows do
		if r.UserId ~= player.UserId then
			count += 1
			local marker = riderMarkers[count]
			if not marker then
				marker = Kit.new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					BorderSizePixel = 0,
					Size = UDim2.fromOffset(6, 6),
					ZIndex = 4,
					Parent = barTrack,
				}, { Kit.Corner(3) })
				riderMarkers[count] = marker
			end
			marker.Visible = true
			marker.BackgroundColor3 = if r.Rival then C.Ink else C.InkSoft
			marker.Position = UDim2.new(math.clamp(r.Dist / Route.Length, 0, 1), 0, 0.5, 0)
		end
	end
	for i = count + 1, #riderMarkers do
		riderMarkers[i].Visible = false
	end
end

-- Minimap ---------------------------------------------------------------------------------

local mapFrame: Frame
local canvas: Frame
local segmentPool: { Frame } = {}
local routePoints: { Vector3 } = {}
type Marker = { Frame: Frame, World: Vector3, Label: TextLabel? }
local staticMarkers: { Marker } = {}
local dynamicPool: { Frame } = {}
local heading: Frame
local coordLabel: TextLabel

local function toMap(world: Vector3, center: Vector3): (number, number)
	return (world.X - center.X) / STUDS_PER_PIXEL + MAP_SIZE / 2, (world.Z - center.Z) / STUDS_PER_PIXEL + MAP_SIZE / 2
end

local function addStatic(world: Vector3, color: Color3, size: number, label: string?, shape: string?)
	local frame = if shape == "Diamond" then diamond(canvas, size, color, 3) else Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size, size),
		ZIndex = 3,
		Parent = canvas,
	}, if shape == "Dot" then { Kit.Corner(size) } else nil)
	local text: TextLabel? = nil
	if label then
		text = Kit.Label(label, {
			AnchorPoint = Vector2.new(0.5, 0),
			TextSize = 11,
			FontFace = Kit.Fonts.BodyBold,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.fromOffset(100, 12),
			ZIndex = 4,
			Parent = canvas,
		})
	end
	table.insert(staticMarkers, { Frame = frame, World = world, Label = text })
end

local function buildMinimap(screen: ScreenGui)
	mapFrame = Kit.Panel({
		Name = "Minimap",
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S.L, 0, S.L),
		Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE + 20),
		BackgroundColor3 = C.ParchmentDark,
		Parent = screen,
	})
	canvas = Kit.new("Frame", {
		BackgroundColor3 = C.ParchmentDark,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE),
		ClipsDescendants = true,
		Parent = mapFrame,
	})
	coordLabel = Kit.Label("", {
		Position = UDim2.fromOffset(0, MAP_SIZE),
		Size = UDim2.new(1, 0, 0, 20),
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		FontFace = Kit.Fonts.Numbers,
		BackgroundColor3 = C.Parchment,
		BackgroundTransparency = 0,
		Parent = mapFrame,
	})
	Kit.Label("N", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 2),
		Size = UDim2.fromOffset(16, 16),
		FontFace = Kit.Fonts.Heading,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		ZIndex = 8,
		Parent = canvas,
	})

	-- Route polyline samples.
	local d = 0
	while d <= Route.Length do
		local p = Route.PointAt(d)
		table.insert(routePoints, p)
		d += ROUTE_STEP
	end

	for _, town in Layout.Towns do
		addStatic(town.Center, C.Leather, 10, town.Name, "Square")
	end
	for _, cp in Layout.Checkpoints do
		addStatic(cp.Position, C.Brass, 8, nil, "Diamond")
	end
	for _, arena in Layout.Arenas do
		addStatic(arena.Center, C.Accent, 9, "Boss", "Square")
	end
	for _, lm in Layout.Landmarks do
		addStatic(lm.Position, C.InkSoft, 6, LANDMARK_NAMES[lm.Kind], "Dot")
	end
	addStatic(Layout.PvPArena.Center, C.Accent, 8, "Arena", "Diamond")

	-- You: a diamond with a heading needle.
	heading = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(MAP_SIZE / 2, MAP_SIZE / 2),
		Size = UDim2.fromOffset(14, 2),
		ZIndex = 6,
		Parent = canvas,
	})
	local you = diamond(canvas, 10, C.Accent, 7)
	you.Position = UDim2.fromOffset(MAP_SIZE / 2, MAP_SIZE / 2)
	Kit.Stroke(C.Paper, 1).Parent = you
end

local function segment(i: number): Frame
	local seg = segmentPool[i]
	if not seg then
		seg = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundColor3 = C.Leather,
			BorderSizePixel = 0,
			ZIndex = 2,
			Parent = canvas,
		})
		segmentPool[i] = seg
	end
	return seg
end

local function dynamicDot(i: number): Frame
	local dot = dynamicPool[i]
	if not dot then
		dot = Kit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(7, 7),
			ZIndex = 5,
			Parent = canvas,
		}, { Kit.Corner(4) })
		dynamicPool[i] = dot
	end
	return dot
end

local function stepMinimap(root: BasePart?)
	if not root then
		return
	end
	local center = root.Position
	local half = MAP_SIZE / 2 * STUDS_PER_PIXEL * 1.5

	-- Route segments near the player.
	local used = 0
	local d = Route.Project(center)
	local first = math.max(1, math.floor((d - half) / ROUTE_STEP))
	local last = math.min(#routePoints - 1, math.ceil((d + half) / ROUTE_STEP) + 1)
	for i = first, last do
		local a = routePoints[i]
		local b = routePoints[i + 1]
		local ax, ay = toMap(a, center)
		local bx, by = toMap(b, center)
		local dx, dy = bx - ax, by - ay
		local len = math.sqrt(dx * dx + dy * dy)
		if len > 0.1 then
			used += 1
			local seg = segment(used)
			seg.Visible = true
			seg.Position = UDim2.fromOffset((ax + bx) / 2, (ay + by) / 2)
			seg.Size = UDim2.fromOffset(len + 1, 4)
			seg.Rotation = math.deg(math.atan2(dy, dx))
		end
	end
	for i = used + 1, #segmentPool do
		segmentPool[i].Visible = false
	end

	for _, m in staticMarkers do
		local x, y = toMap(m.World, center)
		local inside = x > -40 and x < MAP_SIZE + 40 and y > -40 and y < MAP_SIZE + 40
		m.Frame.Visible = inside
		m.Frame.Position = UDim2.fromOffset(x, y)
		local label = m.Label
		if label then
			label.Visible = inside
			label.Position = UDim2.fromOffset(x, y + 6)
		end
	end

	-- Other players and your horse.
	local count = 0
	for _, other in Players:GetPlayers() do
		if other ~= player then
			local character = other.Character
			local r = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r then
				local x, y = toMap(r.Position, center)
				if x > 0 and x < MAP_SIZE and y > 0 and y < MAP_SIZE then
					count += 1
					local dot = dynamicDot(count)
					dot.Visible = true
					dot.BackgroundColor3 = if character and character:GetAttribute("PvP") == true then C.Accent else C.Ink
					dot.Position = UDim2.fromOffset(x, y)
				end
			end
		end
	end
	local horses = workspace:FindFirstChild("Horses")
	if horses and not State.Horse then
		for _, horse in horses:GetChildren() do
			if horse:IsA("Model") and horse:GetAttribute("OwnerId") == player.UserId and horse.PrimaryPart then
				local x, y = toMap(horse.PrimaryPart.Position, center)
				count += 1
				local dot = dynamicDot(count)
				dot.Visible = true
				dot.BackgroundColor3 = C.LeatherLight
				dot.Position = UDim2.fromOffset(math.clamp(x, 4, MAP_SIZE - 4), math.clamp(y, 4, MAP_SIZE - 4))
			end
		end
	end
	for i = count + 1, #dynamicPool do
		dynamicPool[i].Visible = false
	end

	-- Heading from the camera, so the needle points where you look.
	local look = workspace.CurrentCamera.CFrame.LookVector
	heading.Rotation = math.deg(math.atan2(look.Z, look.X))
	coordLabel.Text = string.format("%d ft along the trail", math.floor(d))
end

function Map.Init(screen: ScreenGui)
	buildBar(screen)
	buildMinimap(screen)
	local accum = 0
	RunService.RenderStepped:Connect(function(dt: number)
		accum += dt
		if accum < 1 / 30 then
			return
		end
		accum = 0
		local _, _, root = State.Character()
		stepBar(root)
		stepMinimap(root)
	end)
end

return Map
