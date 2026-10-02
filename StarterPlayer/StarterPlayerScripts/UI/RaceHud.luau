--!strict
-- Race UI: the lobby card, the start countdown, the live race panel with
-- stage, position, timer, splits and the leading riders, and the results
-- board. Standings are shared with the route bar and minimap for markers.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Route = require(ReplicatedStorage.Shared.Route)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Util = require(ReplicatedStorage.Shared.Util)
local Signal = require(ReplicatedStorage.Shared.Signal)
local Kit = require(script.Parent.Kit)
local Feed = require(script.Parent.Feed)
local State = require(script.Parent.Parent.Controllers.State)

local RaceHud = {}

local C = Kit.Colors
local S = Kit.Space
local player = Players.LocalPlayer

export type Row = { Name: string, UserId: number?, Dist: number, Place: number, Finished: boolean, Rival: boolean }

RaceHud.Active = false
RaceHud.Rows = {} :: { Row }
RaceHud.Changed = Signal.new() :: Signal.Signal<>

local screen: ScreenGui
local lobby: Frame
local lobbyText: TextLabel
local countdown: TextLabel
local countdownScale: UIScale
local panel: Frame
local stageLabel: TextLabel
local placeLabel: TextLabel
local timerLabel: TextLabel
local limitLabel: TextLabel
local splitLabel: TextLabel
local nextLabel: TextLabel
local leaders: Frame
local results: Frame
local resultsList: ScrollingFrame

local startedAt = 0
local limit = 0
local nextCheckpoint = 1
local lobbyEndsAt = 0
local lobbyCount = 0
local finished = false

local function formatClock(seconds: number): string
	local m = math.floor(seconds / 60)
	local s = seconds - m * 60
	return string.format("%02d:%04.1f", m, s)
end

local function showCountdown(text: string)
	countdown.Text = text
	countdown.Visible = true
	countdownScale.Scale = 1.5
	TweenService:Create(countdownScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

local function build()
	screen = Kit.Screen("SBR_Race", 3)

	lobby = Kit.Panel({
		Name = "Lobby",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S.L, 0.45, 0),
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = screen,
	})
	Kit.Padding(S.M).Parent = lobby
	Kit.List(S.S).Parent = lobby
	Kit.Heading("Race lobby", 18, { LayoutOrder = 1, Parent = lobby })
	lobbyText = Kit.Paragraph("", { LayoutOrder = 2, Parent = lobby })
	Kit.Button("Leave lobby", "Ghost", function()
		State.Request("LeaveRace")
		lobby.Visible = false
	end, { LayoutOrder = 3, Parent = lobby })

	countdown = Kit.Label("", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.32),
		Size = UDim2.fromOffset(400, 120),
		FontFace = Kit.Fonts.Sign,
		TextSize = 96,
		TextColor3 = C.Paper,
		TextXAlignment = Enum.TextXAlignment.Center,
		Visible = false,
		Parent = screen,
	})
	local stroke = Kit.Stroke(C.Ink, 4)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = countdown
	countdownScale = Kit.new("UIScale", { Parent = countdown })

	panel = Kit.Panel({
		Name = "Race",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, S.L, 0.45, 0),
		Size = UDim2.fromOffset(260, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = screen,
	})
	Kit.Padding(S.M).Parent = panel
	Kit.List(S.XS).Parent = panel
	stageLabel = Kit.Heading("", 18, { LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd, Parent = panel })
	local big = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 40), LayoutOrder = 2, Parent = panel })
	placeLabel = Kit.Label("", { FontFace = Kit.Fonts.Sign, TextSize = 32, Size = UDim2.fromScale(0.45, 1), TextColor3 = C.Accent, Parent = big })
	timerLabel = Kit.Label("00:00.0", { FontFace = Kit.Fonts.Numbers, TextSize = 26, Size = UDim2.fromScale(0.55, 1), Position = UDim2.fromScale(0.45, 0), TextXAlignment = Enum.TextXAlignment.Right, Parent = big })
	limitLabel = Kit.Label("", { FontFace = Kit.Fonts.Numbers, TextSize = Kit.Text.Small, TextColor3 = C.InkSoft, TextXAlignment = Enum.TextXAlignment.Right, LayoutOrder = 3, Parent = panel })
	nextLabel = Kit.Label("", { TextSize = Kit.Text.Small, LayoutOrder = 4, Parent = panel })
	splitLabel = Kit.Label("", { FontFace = Kit.Fonts.Numbers, TextSize = Kit.Text.Small, TextColor3 = C.InkSoft, LayoutOrder = 5, Parent = panel })
	Kit.Rule({ LayoutOrder = 6, Parent = panel })
	leaders = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 7, Parent = panel }, { Kit.List(2) })

	results = Kit.Panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(420, 380),
		Visible = false,
		ZIndex = 5,
		Parent = screen,
	})
	Kit.Padding(S.L).Parent = results
	Kit.Heading("Race results", Kit.Text.Title, { Size = UDim2.new(1, 0, 0, 30), ZIndex = 6, Parent = results })
	resultsList = Kit.Scroll({ Position = UDim2.fromOffset(0, 38), Size = UDim2.new(1, 0, 1, -84), ZIndex = 6, Parent = results }, 2)
	Kit.Button("Close", "Secondary", function()
		results.Visible = false
	end, { AnchorPoint = Vector2.new(1, 1), Position = UDim2.fromScale(1, 1), ZIndex = 6, Parent = results })
end

local function rowLabel(parent: Instance, left: string, right: string, highlight: boolean, order: number, z: number?)
	local row = Kit.new("Frame", {
		BackgroundColor3 = if highlight then C.ParchmentDark else C.Parchment,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = order,
		ZIndex = z or 1,
		Parent = parent,
	}, { Kit.Padding(0, S.XS) })
	Kit.Label(left, { Size = UDim2.fromScale(0.68, 1), TextSize = Kit.Text.Small, FontFace = if highlight then Kit.Fonts.BodyBold else Kit.Fonts.Body, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = z or 1, Parent = row })
	Kit.Label(right, { Size = UDim2.fromScale(0.32, 1), Position = UDim2.fromScale(0.68, 0), TextSize = Kit.Text.Small, FontFace = Kit.Fonts.Numbers, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = z or 1, Parent = row })
end

local function refreshLeaders()
	Kit.Clear(leaders)
	local rows = RaceHud.Rows
	local mine: Row? = nil
	for _, r in rows do
		if r.UserId == player.UserId then
			mine = r
		end
	end
	for i, r in rows do
		if i <= 5 or r == mine then
			local gap = if r.Finished then "done" else string.format("%d ft", math.floor((Layout.FinishDist - r.Dist) + 0.5))
			rowLabel(leaders, string.format("%d. %s", r.Place, r.Name), gap, r == mine, i)
		end
	end
	if mine then
		placeLabel.Text = string.format("%s / %d", Util.ordinal(mine.Place), #rows)
	end
end

local handlers: { [string]: (any) -> () } = {}

handlers.Lobby = function(d)
	lobby.Visible = true
	lobbyEndsAt = os.clock() + (tonumber(d.EndsIn) or 0)
	lobbyCount = tonumber(d.Count) or 1
end

handlers.Countdown = function(d)
	lobby.Visible = false
	results.Visible = false
	finished = false
	nextCheckpoint = 1
	local t = math.floor(tonumber(d.T) or 5)
	task.spawn(function()
		for i = t, 1, -1 do
			showCountdown(tostring(i))
			task.wait(1)
		end
	end)
end

handlers.Go = function(d)
	showCountdown("Go")
	task.delay(1, function()
		countdown.Visible = false
	end)
	RaceHud.Active = true
	startedAt = os.clock()
	limit = tonumber(d.Limit) or 1200
	panel.Visible = true
	stageLabel.Text = tostring(d.Stage or Route.Stages[1].Name)
	splitLabel.Text = ""
	RaceHud.Changed:Fire()
end

handlers.Checkpoint = function(d)
	local index = tonumber(d.Index) or 1
	nextCheckpoint = index + 1
	local split = tonumber(d.Split) or 0
	local stageTime = tonumber(d.StageTime) or 0
	splitLabel.Text = string.format("Split %s, stage %s", formatClock(split), formatClock(stageTime))
	if d.Next then
		stageLabel.Text = tostring(d.Next)
		Feed.Toast(string.format("Checkpoint %d cleared in %s. Next stage: %s.", index, formatClock(stageTime), tostring(d.Next)), "Good")
	end
end

handlers.Standings = function(d)
	if type(d.Rows) ~= "table" then
		return
	end
	local rows: { Row } = {}
	for _, r in d.Rows do
		table.insert(rows, {
			Name = tostring(r.Name),
			UserId = tonumber(r.UserId),
			Dist = tonumber(r.Dist) or 0,
			Place = tonumber(r.Place) or 0,
			Finished = r.Finished == true,
			Rival = r.Rival == true,
		})
	end
	RaceHud.Rows = rows
	refreshLeaders()
	RaceHud.Changed:Fire()
end

handlers.Notice = function(d)
	Feed.Toast(tostring(d.Text or ""), "Info")
end

handlers.Finished = function(d)
	finished = true
	local cash = tonumber(d.Cash) or 0
	Feed.Banner(
		"Finished " .. Util.ordinal(tonumber(d.Place) or 0),
		string.format("Time %s. Earned $%s.", formatClock(tonumber(d.Time) or 0), Util.formatNumber(cash)),
		4.5
	)
	timerLabel.Text = formatClock(tonumber(d.Time) or 0)
end

handlers.End = function(d)
	RaceHud.Active = false
	panel.Visible = false
	Kit.Clear(resultsList)
	if type(d.Results) == "table" then
		for i, r in d.Results do
			local time = if r.Finished and r.Time then formatClock(tonumber(r.Time) or 0) else "did not finish"
			rowLabel(resultsList, string.format("%d. %s", tonumber(r.Place) or i, tostring(r.Name)), time, r.Name == player.DisplayName or r.Name == player.Name, i, 6)
		end
	end
	results.Visible = true
	RaceHud.Rows = {}
	RaceHud.Changed:Fire()
	task.delay(20, function()
		results.Visible = false
	end)
end

handlers.Left = function()
	RaceHud.Active = false
	lobby.Visible = false
	panel.Visible = false
	countdown.Visible = false
	RaceHud.Rows = {}
	RaceHud.Changed:Fire()
end

local function step()
	if lobby.Visible then
		local left = math.max(0, lobbyEndsAt - os.clock())
		lobbyText.Text = string.format("%d %s signed up. The race starts in %s at the San Diego start line.", lobbyCount, if lobbyCount == 1 then "rider" else "riders", Util.formatTime(left))
	end
	if not RaceHud.Active then
		return
	end
	local elapsed = os.clock() - startedAt
	if not finished then
		timerLabel.Text = formatClock(elapsed)
	end
	limitLabel.Text = "Time left " .. Util.formatTime(math.max(0, limit - elapsed))
	local _, _, root = State.Character()
	local cp = Layout.Checkpoints[nextCheckpoint]
	if root and cp and not finished then
		local d = Route.Project(root.Position)
		nextLabel.Text = string.format("%s in %s ft", if cp.Name == "Finish" then "Finish line" else "Checkpoint", Util.formatNumber(math.max(0, math.floor(cp.Dist - d))))
	else
		nextLabel.Text = ""
	end
end

function RaceHud.Init()
	build()
	Remotes.Event("Race").OnClientEvent:Connect(function(kind: string, data: any)
		local handler = handlers[kind]
		if handler then
			local ok, err = pcall(handler :: any, if type(data) == "table" then data else {})
			if not ok then
				warn("[RaceHud] " .. kind .. ": " .. tostring(err))
			end
		end
	end)
	RunService.RenderStepped:Connect(step)
end

return RaceHud
