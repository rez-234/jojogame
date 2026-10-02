--!strict
-- Quests tab: today's daily quests, the board quests you hold, and the
-- offers on a town's quest board when you open it from the board itself.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local QuestData = require(ReplicatedStorage.Shared.QuestData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Util = require(ReplicatedStorage.Shared.Util)
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)

local Quests = {}
Quests.Name = "Quests"

local C = Kit.Colors

local board: any = nil
local boardTown: number? = nil

function Quests.OnOpen(ctx: any)
	local town = tonumber(ctx.Args.Town)
	boardTown = town
	board = nil
	if town then
		local result = State.Request("BoardOffers", town)
		if result.Ok then
			board = result.Data
			ctx.Rerender()
		end
	end
end

local function rewardText(q: QuestData.Quest): string
	local parts = {}
	local r = q.Reward
	if r.Cash then
		table.insert(parts, "$" .. Util.formatNumber(r.Cash))
	end
	if r.XP then
		table.insert(parts, Util.formatNumber(r.XP) .. " XP")
	end
	if r.Items then
		for id, amount in r.Items do
			local item = ItemData.Items[id]
			table.insert(parts, string.format("%s x%d", if item then item.Name else id, amount))
		end
	end
	return "Reward: " .. table.concat(parts, ", ")
end

local function questCard(parent: Instance, ctx: any, q: QuestData.Quest, progress: number?, claimed: boolean, order: number, canAbandon: boolean, offerTown: number?)
	local section = Kit.Section({ LayoutOrder = order, Parent = parent })
	local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = section })
	Kit.Label(q.Name, { FontFace = Kit.Fonts.Heading, TextSize = 17, Size = UDim2.fromScale(0.65, 1), Parent = top })
	local done = progress ~= nil and progress >= q.Amount
	Kit.Label(if claimed then "Claimed" elseif done then "Ready to claim" else "", {
		FontFace = Kit.Fonts.BodyBold,
		TextColor3 = if claimed then C.InkSoft else C.Good,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.fromScale(0.35, 1),
		Position = UDim2.fromScale(0.65, 0),
		Parent = top,
	})
	Kit.Paragraph(q.Text, { LayoutOrder = 2, Parent = section })
	if progress then
		local bar = Kit.Bar(C.Leather, 14, { LayoutOrder = 3, Parent = section })
		bar.Set(progress / math.max(1, q.Amount), string.format("%s / %s", Util.formatNumber(math.min(progress, q.Amount)), Util.formatNumber(q.Amount)))
	end
	Kit.Label(rewardText(q), { LayoutOrder = 4, TextSize = 14, TextColor3 = C.InkSoft, Parent = section })
	local buttons = Kit.ButtonRow({ LayoutOrder = 5, Parent = section })
	if offerTown then
		Kit.Button("Take quest", "Primary", function()
			local ok = ctx.Do("AcceptQuest", "Quest taken.", offerTown, q.Id)
			if ok then
				Quests.OnOpen(ctx)
			end
		end, { Size = UDim2.fromOffset(130, 32), LayoutOrder = 1, Parent = buttons })
	elseif not claimed then
		local claim = Kit.Button("Claim", "Primary", function()
			ctx.Do("ClaimQuest", "Reward claimed.", q.Id)
		end, { Size = UDim2.fromOffset(110, 32), LayoutOrder = 1, Parent = buttons })
		claim.SetEnabled(done)
		if canAbandon then
			Kit.Button("Abandon", "Ghost", function()
				ctx.Do("AbandonQuest", nil, q.Id)
			end, { Size = UDim2.fromOffset(110, 32), LayoutOrder = 2, Parent = buttons })
		end
	else
		buttons:Destroy()
	end
end

function Quests.Render(page: ScrollingFrame, ctx: any)
	local profile = State.Profile
	if not profile then
		Kit.Paragraph("Loading...", { Parent = page })
		return
	end
	local order = 0
	local function nextOrder(): number
		order += 1
		return order
	end

	-- Town board offers.
	if boardTown then
		local town = Layout.Towns[boardTown]
		Kit.Heading((if town then town.Name else "Town") .. " quest board", Kit.Text.Label, { LayoutOrder = nextOrder(), Parent = page })
		if not board then
			Kit.Paragraph("Reading the board...", { LayoutOrder = nextOrder(), TextColor3 = C.InkSoft, Parent = page })
		elseif not board.Near then
			Kit.Paragraph("Stand by the board to take its quests.", { LayoutOrder = nextOrder(), TextColor3 = C.InkSoft, Parent = page })
		else
			local any = false
			for _, offer in board.Offers do
				local q = QuestData.Quests[offer.Id]
				if q and not offer.Taken then
					any = true
					questCard(page, ctx, q, nil, false, nextOrder(), false, boardTown)
				end
			end
			if not any then
				Kit.Paragraph("You have taken everything on this board today.", { LayoutOrder = nextOrder(), TextColor3 = C.InkSoft, Parent = page })
			end
		end
	end

	Kit.Heading("Daily quests", Kit.Text.Label, { LayoutOrder = nextOrder(), Parent = page })
	Kit.Paragraph("New ones every day at midnight UTC.", { LayoutOrder = nextOrder(), TextSize = 14, TextColor3 = C.InkSoft, Parent = page })
	for _, s in profile.Quests.Daily do
		local q = QuestData.Quests[s.Id]
		if q then
			questCard(page, ctx, q, s.Progress, s.Claimed, nextOrder(), false, nil)
		end
	end

	Kit.Heading(string.format("Board quests (%d / %d)", #profile.Quests.Board, Config.Economy.BoardQuestCount), Kit.Text.Label, { LayoutOrder = nextOrder(), Parent = page })
	if #profile.Quests.Board == 0 then
		Kit.Paragraph("Every town has a quest board. Walk up to it and press E.", { LayoutOrder = nextOrder(), TextColor3 = C.InkSoft, Parent = page })
	end
	for _, s in profile.Quests.Board do
		local q = QuestData.Quests[s.Id]
		if q then
			questCard(page, ctx, q, s.Progress, s.Claimed, nextOrder(), true, nil)
		end
	end
end

return Quests
