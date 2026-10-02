--!strict
-- Arena tab: open world duels on or off, the ranked one on one queue, your
-- rating and record, and the leaderboards for this server and everyone.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)

local Arena = {}
Arena.Name = "Arena"

local C = Kit.Colors

local board: any = nil
local queued = false

function Arena.OnOpen(ctx: any)
	local result = State.Request("Leaderboard")
	if result.Ok then
		board = result.Data
		ctx.Rerender()
	end
end

local function boardList(parent: Instance, title: string, rows: { any }, order: number, showLevel: boolean)
	local section = Kit.Section({ LayoutOrder = order, Parent = parent })
	Kit.Heading(title, Kit.Text.Label, { LayoutOrder = 0, Parent = section })
	if #rows == 0 then
		Kit.Paragraph("No ranked riders yet.", { LayoutOrder = 1, TextColor3 = C.InkSoft, Parent = section })
		return
	end
	for i, row in rows do
		if i > 10 then
			break
		end
		local right = tostring(row.Ranked)
		if showLevel and row.Level then
			right = string.format("Lv %d   %s", row.Level, right)
		end
		Kit.Row(string.format("%d. %s", i, tostring(row.Name)), right, { LayoutOrder = i, Parent = section })
	end
end

function Arena.Render(page: ScrollingFrame, ctx: any)
	local profile = State.Profile
	if not profile then
		Kit.Paragraph("Loading...", { Parent = page })
		return
	end

	local duels = Kit.Section({ LayoutOrder = 1, Parent = page })
	Kit.Heading("Open world duels", Kit.Text.Label, { LayoutOrder = 0, Parent = duels })
	Kit.Paragraph(
		"With duels on, other riders who also have duels on can fight you anywhere outside towns. Towns are always safe, and new arrivals are protected for a few seconds.",
		{ LayoutOrder = 1, Parent = duels }
	)
	local status = Kit.Label(if profile.PvPEnabled then "Duels are on" else "Duels are off", { LayoutOrder = 2, FontFace = Kit.Fonts.BodyBold, Parent = duels })
	status.TextColor3 = if profile.PvPEnabled then C.Accent else C.InkSoft
	Kit.Button(if profile.PvPEnabled then "Turn duels off" else "Turn duels on", if profile.PvPEnabled then "Secondary" else "Primary", function()
		State.Action("PvPToggle")
	end, { LayoutOrder = 3, Size = UDim2.fromOffset(170, 34), Parent = duels })

	local ranked = Kit.Section({ LayoutOrder = 2, Parent = page })
	Kit.Heading("Ranked arena", Kit.Text.Label, { LayoutOrder = 0, Parent = ranked })
	Kit.Row("Your rating", tostring(profile.Ranked), { LayoutOrder = 1, Parent = ranked })
	Kit.Row("Wins and losses", string.format("%d / %d", profile.ArenaWins, profile.ArenaLosses), { LayoutOrder = 2, Parent = ranked })
	Kit.Paragraph(
		string.format("One on one in the ring outside San Diego. A match lasts up to %d seconds. Win to gain rating; the gain is larger against stronger riders.", Config.PvP.ArenaMaxTime),
		{ LayoutOrder = 3, TextSize = 14, TextColor3 = C.InkSoft, Parent = ranked }
	)
	local unlocked = Progression.IsUnlocked(profile.Level, "PvPArena")
	local queue = Kit.Button(if queued then "Leave the queue" else "Find a match", if queued then "Secondary" else "Primary", function()
		local ok, data = ctx.Do("QueueArena", nil)
		if ok and type(data) == "table" then
			queued = data.Queued == true
			ctx.Rerender()
		end
	end, { LayoutOrder = 4, Size = UDim2.fromOffset(170, 34), Parent = ranked })
	queue.SetEnabled(unlocked)
	if not unlocked then
		Kit.Paragraph("The arena opens at level " .. Progression.UnlockLevel("PvPArena") .. ".", { LayoutOrder = 5, TextColor3 = C.Accent, Parent = ranked })
	elseif queued then
		Kit.Paragraph("Waiting for an opponent. You can keep riding while you wait.", { LayoutOrder = 5, TextColor3 = C.InkSoft, Parent = ranked })
	end

	if not board then
		Kit.Paragraph("Loading the leaderboard...", { LayoutOrder = 3, TextColor3 = C.InkSoft, Parent = page })
		return
	end
	boardList(page, "This server", board.Server or {}, 3, true)
	boardList(page, "All riders", board.Global or {}, 4, false)
end

return Arena
