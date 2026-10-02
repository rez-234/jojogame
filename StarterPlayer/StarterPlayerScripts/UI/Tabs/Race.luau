--!strict
-- Race tab: how the Steel Ball Run works, joining or leaving the next race,
-- your best total and stage times, and the stages along the way.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Route = require(ReplicatedStorage.Shared.Route)
local Util = require(ReplicatedStorage.Shared.Util)
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)

local Race = {}
Race.Name = "Race"

local C = Kit.Colors

local raceState: any = nil

function Race.OnOpen(ctx: any)
	local result = State.Request("RaceState")
	if result.Ok then
		raceState = result.Data
		ctx.Rerender()
	end
end

local STATE_TEXT: { [string]: string } = {
	Idle = "No race is running. Join and one starts after a short lobby.",
	Lobby = "Riders are signing up for the next race.",
	Starting = "The race is about to start.",
	Running = "A race is underway.",
	Ending = "The last race just finished.",
}

function Race.Render(page: ScrollingFrame, ctx: any)
	local profile = State.Profile
	if not profile then
		Kit.Paragraph("Loading...", { Parent = page })
		return
	end

	local now = Kit.Section({ LayoutOrder = 1, Parent = page })
	Kit.Heading("The Steel Ball Run", Kit.Text.Title, { LayoutOrder = 0, Parent = now })
	Kit.Paragraph(
		string.format(
			"From the San Diego beach to New York in %d stages. Rival riders push hard and fight dirty. Clearing a checkpoint pays $%d; the top five finishers split the purse and the winner takes home Stand Arrows.",
			#Route.Stages,
			Config.Race.StageCash
		),
		{ LayoutOrder = 1, Parent = now }
	)
	if raceState then
		Kit.Paragraph(STATE_TEXT[raceState.State] or "", { LayoutOrder = 2, FontFace = Kit.Fonts.BodyBold, Parent = now })
		local buttons = Kit.ButtonRow({ LayoutOrder = 3, Parent = now })
		if raceState.InLobby then
			Kit.Button("Leave the lobby", "Secondary", function()
				ctx.Do("LeaveRace", "You left the lobby.")
				Race.OnOpen(ctx)
			end, { Size = UDim2.fromOffset(170, 34), LayoutOrder = 1, Parent = buttons })
		elseif raceState.Racing then
			Kit.Button("Retire from the race", "Ghost", function()
				ctx.Do("LeaveRace", "You retired from the race.")
				Race.OnOpen(ctx)
			end, { Size = UDim2.fromOffset(190, 34), LayoutOrder = 1, Parent = buttons })
		else
			local join = Kit.Button("Join the next race", "Primary", function()
				ctx.Do("JoinRace", nil)
				Race.OnOpen(ctx)
			end, { Size = UDim2.fromOffset(190, 34), LayoutOrder = 1, Parent = buttons })
			join.SetEnabled(raceState.State == "Idle" or raceState.State == "Lobby")
		end
	else
		Kit.Paragraph("Checking the race office...", { LayoutOrder = 2, TextColor3 = C.InkSoft, Parent = now })
	end

	local record = Kit.Section({ LayoutOrder = 2, Parent = page })
	Kit.Heading("Your record", Kit.Text.Label, { LayoutOrder = 0, Parent = record })
	Kit.Row("Races won", tostring(profile.Race.Wins), { LayoutOrder = 1, Parent = record })
	Kit.Row("Races finished", tostring(profile.Race.Finishes), { LayoutOrder = 2, Parent = record })
	Kit.Row("Best total", if profile.Race.BestTotal then Util.formatTime(profile.Race.BestTotal) else "none yet", { LayoutOrder = 3, Parent = record })

	local stages = Kit.Section({ LayoutOrder = 3, Parent = page })
	Kit.Heading("Stages", Kit.Text.Label, { LayoutOrder = 0, Parent = stages })
	for i, stage in Route.Stages do
		local best = profile.Race.BestStages[stage.Id]
		local _, value = Kit.Row(string.format("%d. %s, %s", i, stage.Name, stage.Region), if best then Util.formatTime(best) else "no time", { LayoutOrder = i, Parent = stages })
		value.TextColor3 = if best then C.Ink else C.InkSoft
	end
end

return Race
