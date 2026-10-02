--!strict
-- The taming minigame for wild horses. A marker sweeps back and forth along
-- a bar; press E, Space, click or tap while it is inside the band. Each
-- round narrows the time to react. The server keeps the authoritative clock,
-- so the marker is drawn from server time.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Kit = require(script.Parent.Kit)
local Feed = require(script.Parent.Feed)
local State = require(script.Parent.Parent.Controllers.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)

local TameGame = {}

local C = Kit.Colors
local S = Kit.Space

local panel: Frame
local title: TextLabel
local roundLabel: TextLabel
local status: TextLabel
local track: Frame
local band: Frame
local needleFrame: Frame
local pips: { Frame } = {}
local pipRow: Frame

type Round = { Round: number, Rounds: number, Center: number, Width: number, Period: number, StartAt: number }
local current: Round? = nil
local active = false
local pressedThisRound = false
local sessionToken = 0

local function needle(t: number, period: number): number
	if t < 0 then
		return 0
	end
	local x = (t % (2 * period)) / period
	return if x > 1 then 2 - x else x
end

local function build(screen: ScreenGui)
	panel = Kit.Panel({
		Name = "Tame",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.62),
		Size = UDim2.fromOffset(440, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = screen,
	})
	Kit.Padding(S.L).Parent = panel
	Kit.List(S.S, false, Enum.HorizontalAlignment.Center).Parent = panel
	title = Kit.Heading("", Kit.Text.Title, { TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1, Parent = panel })
	roundLabel = Kit.Label("", { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.InkSoft, LayoutOrder = 2, Parent = panel })
	track = Kit.new("Frame", {
		BackgroundColor3 = C.Track,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 30),
		LayoutOrder = 3,
		Parent = panel,
	}, { Kit.Corner(2) })
	band = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundColor3 = C.Good,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0.3, 1),
		Parent = track,
	})
	needleFrame = Kit.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundColor3 = C.Paper,
		BorderSizePixel = 0,
		Position = UDim2.fromScale(0, 0.5),
		Size = UDim2.new(0, 6, 1, 10),
		ZIndex = 3,
		Parent = track,
	}, { Kit.Stroke(C.Ink, 2) })
	pipRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 12), LayoutOrder = 4, Parent = panel }, { Kit.List(S.S, true, Enum.HorizontalAlignment.Center) })
	status = Kit.Label("", { TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.Fonts.BodyBold, LayoutOrder = 5, Parent = panel })
	local press = Kit.Button("Calm", "Primary", function()
		InputController.TamePressed:Fire()
	end, { LayoutOrder = 6, Parent = panel })
	press.Instance.Visible = UserInputService.TouchEnabled
end

local function setPips(total: number, done: number)
	for _, p in pips do
		p:Destroy()
	end
	pips = {}
	for i = 1, total do
		local pip = Kit.new("Frame", {
			BackgroundColor3 = if i <= done then C.Good else C.ParchmentDark,
			BorderSizePixel = 0,
			Size = UDim2.fromOffset(28, 10),
			LayoutOrder = i,
			Parent = pipRow,
		}, { Kit.Corner(2) })
		table.insert(pips, pip)
	end
end

local function finish(text: string, tone: string)
	status.Text = text
	status.TextColor3 = if tone == "Good" then C.Good else C.Accent
	current = nil
	active = false
	local token = sessionToken
	task.delay(1.4, function()
		if token == sessionToken then
			panel.Visible = false
			State.Taming = false
		end
	end)
end

local handlers: { [string]: (any) -> () } = {}

handlers.TameStart = function(d)
	sessionToken += 1
	active = true
	State.Taming = true
	panel.Visible = true
	title.Text = "Calm the " .. tostring(d.Breed or "horse")
	roundLabel.Text = string.format("%s. Press E, Space or click inside the green band.", tostring(d.Rarity or "Common"))
	status.Text = "Easy now..."
	status.TextColor3 = C.InkSoft
	setPips(tonumber(d.Rounds) or 3, 0)
	-- If the server never answers, close after a while.
	local token = sessionToken
	task.delay(30, function()
		if token == sessionToken and active then
			finish("It wandered off.", "Bad")
		end
	end)
end

handlers.TameRound = function(d)
	current = {
		Round = tonumber(d.Round) or 1,
		Rounds = tonumber(d.Rounds) or 3,
		Center = tonumber(d.Center) or 0.5,
		Width = tonumber(d.Width) or 0.3,
		Period = math.max(0.2, tonumber(d.Period) or 1),
		StartAt = tonumber(d.StartAt) or workspace:GetServerTimeNow(),
	}
	pressedThisRound = false
	local r = current :: Round
	band.Position = UDim2.fromScale(r.Center, 0)
	band.Size = UDim2.fromScale(r.Width, 1)
	band.BackgroundColor3 = C.Good
	status.Text = string.format("Round %d of %d", r.Round, r.Rounds)
	status.TextColor3 = C.Ink
	setPips(r.Rounds, r.Round - 1)
end

handlers.TameHit = function(d)
	band.BackgroundColor3 = C.Brass
	local round = tonumber(d.Round) or 1
	setPips(#pips, round)
end

handlers.TameResult = function(d)
	if d.Success then
		setPips(#pips, #pips)
		finish("It trusts you now.", "Good")
	else
		finish("It reared up and bolted.", "Bad")
		Feed.Toast("The horse bolted. Give it a little time before trying again.", "Bad")
	end
end

function TameGame.Init(screen: ScreenGui)
	build(screen)
	Remotes.Event("Horse").OnClientEvent:Connect(function(kind: string, data: any)
		local handler = handlers[kind]
		if handler then
			handler(if type(data) == "table" then data else {})
		end
	end)
	InputController.TamePressed:Connect(function()
		if not active or not current or pressedThisRound then
			return
		end
		local r = current :: Round
		if workspace:GetServerTimeNow() < r.StartAt - 0.1 then
			return
		end
		pressedThisRound = true
		State.Action("TamePress")
	end)
	RunService.RenderStepped:Connect(function()
		local r = current
		if not panel.Visible or not r then
			return
		end
		local t = workspace:GetServerTimeNow() - r.StartAt
		if t < 0 then
			needleFrame.Position = UDim2.fromScale(0, 0.5)
			status.Text = "Get ready"
			return
		end
		if status.Text == "Get ready" then
			status.Text = string.format("Round %d of %d", r.Round, r.Rounds)
		end
		needleFrame.Position = UDim2.fromScale(needle(t, r.Period), 0.5)
	end)
end

return TameGame
