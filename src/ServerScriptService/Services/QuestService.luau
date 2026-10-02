--!strict
-- Daily quests (rolled once per day per player) and town quest boards
-- (each board offers a few quests a day; players can hold a limited number).
-- Progress comes from Signals.Quest fired by the other services.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local Config = require(ReplicatedStorage.Shared.Config)
local QuestData = require(ReplicatedStorage.Shared.QuestData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local LevelService = require(script.Parent.LevelService)
local Signals = require(script.Parent.Signals)
local Net = require(script.Parent.Net)

local QuestService = {}

local function today(): number
	return math.floor(os.time() / 86400)
end

local function pickFrom(pool: { QuestData.Quest }, count: number, seed: number): { QuestData.Quest }
	local rng = Random.new(seed)
	local list = table.clone(pool)
	local picked = {}
	for _ = 1, math.min(count, #list) do
		local i = rng:NextInteger(1, #list)
		table.insert(picked, list[i])
		table.remove(list, i)
	end
	return picked
end

local function ensureDaily(player: Player, profile: Types.Profile)
	local day = today()
	if profile.Quests.Day == day then
		return
	end
	profile.Quests.Day = day
	profile.Quests.Daily = {}
	for _, q in pickFrom(QuestData.Pool("Daily", profile.Level), Config.Economy.DailyQuestCount, day * 7919 + player.UserId % 100000) do
		table.insert(profile.Quests.Daily, { Id = q.Id, Progress = 0, Claimed = false })
	end
	DataService.MarkDirty(player)
end

function QuestService.BoardOffers(town: number, level: number): { QuestData.Quest }
	return pickFrom(QuestData.Pool("Board", level), Config.Economy.BoardQuestCount, today() * 131 + town * 17)
end

local function nearBoard(player: Player, town: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, board in CollectionService:GetTagged("SBR_QuestBoard") do
		if board:IsA("BasePart") and board:GetAttribute("Town") == town and (board.Position - root.Position).Magnitude < 30 then
			return true
		end
	end
	return false
end

local function grantReward(player: Player, quest: QuestData.Quest)
	local r = quest.Reward
	if r.Cash then
		DataService.AddCash(player, r.Cash)
		Net.Notify(player, "Cash", { Amount = r.Cash })
	end
	if r.XP then
		LevelService.AddXP(player, r.XP, quest.Name)
	end
	if r.Items then
		for item, amount in r.Items do
			DataService.AddItem(player, item, amount)
			local data = ItemData.Items[item]
			Net.Notify(player, "Loot", { Item = item, Name = if data then data.Name else item, Amount = amount })
		end
	end
	DataService.AddCounter(player, "QuestsCompleted", 1)
end

local function record(player: Player, event: string, amount: number)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	ensureDaily(player, profile)
	local changed = false
	local function advance(list: { Types.QuestState })
		for _, state in list do
			local q = QuestData.Quests[state.Id]
			if q and q.Event == event and not state.Claimed and state.Progress < q.Amount then
				state.Progress = math.min(q.Amount, state.Progress + amount)
				changed = true
				if state.Progress >= q.Amount then
					Net.Notify(player, "QuestDone", { Id = q.Id, Name = q.Name })
				end
			end
		end
	end
	advance(profile.Quests.Daily)
	advance(profile.Quests.Board)
	if changed then
		DataService.MarkDirty(player)
	end
end

function QuestService.Init()
	Signals.Quest:Connect(record)

	DataService.OnLoaded(function(player, profile)
		ensureDaily(player, profile)
	end)

	Net.OnRequest("BoardOffers", function(player: Player, town: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsNumber(town, 1, 99) then
			return Net.Fail("Bad request")
		end
		local offers = {}
		for _, q in QuestService.BoardOffers(math.floor(town), profile.Level) do
			local taken = false
			for _, s in profile.Quests.Board do
				if s.Id == q.Id then
					taken = true
				end
			end
			table.insert(offers, { Id = q.Id, Taken = taken })
		end
		return Net.Ok({ Town = town, Offers = offers, Near = nearBoard(player, math.floor(town)) })
	end)

	Net.OnRequest("AcceptQuest", function(player: Player, town: any, questId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsNumber(town, 1, 99) or not Net.IsString(questId) then
			return Net.Fail("Bad request")
		end
		local t = math.floor(town)
		if not nearBoard(player, t) then
			return Net.Fail("Read the quest board in town to take quests")
		end
		local offered = false
		for _, q in QuestService.BoardOffers(t, profile.Level) do
			if q.Id == questId then
				offered = true
			end
		end
		if not offered then
			return Net.Fail("That quest is not on this board today")
		end
		local activeCount = 0
		for _, s in profile.Quests.Board do
			if s.Id == questId then
				return Net.Fail("You already have that quest")
			end
			if not s.Claimed then
				activeCount += 1
			end
		end
		if activeCount >= Config.Economy.BoardQuestCount then
			return Net.Fail("You can hold " .. Config.Economy.BoardQuestCount .. " board quests at once")
		end
		table.insert(profile.Quests.Board, { Id = questId, Progress = 0, Claimed = false, Town = t })
		DataService.MarkDirty(player)
		return Net.Ok()
	end)

	Net.OnRequest("ClaimQuest", function(player: Player, questId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(questId) then
			return Net.Fail("Bad request")
		end
		local q = QuestData.Quests[questId]
		if not q then
			return Net.Fail("Unknown quest")
		end
		for _, s in profile.Quests.Daily do
			if s.Id == questId and not s.Claimed then
				if s.Progress < q.Amount then
					return Net.Fail("Not finished yet")
				end
				s.Claimed = true
				grantReward(player, q)
				DataService.MarkDirty(player)
				return Net.Ok()
			end
		end
		for i, s in profile.Quests.Board do
			if s.Id == questId and not s.Claimed then
				if s.Progress < q.Amount then
					return Net.Fail("Not finished yet")
				end
				table.remove(profile.Quests.Board, i)
				grantReward(player, q)
				DataService.MarkDirty(player)
				return Net.Ok()
			end
		end
		return Net.Fail("Nothing to claim")
	end)

	Net.OnRequest("AbandonQuest", function(player: Player, questId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(questId) then
			return Net.Fail("Bad request")
		end
		for i, s in profile.Quests.Board do
			if s.Id == questId then
				table.remove(profile.Quests.Board, i)
				DataService.MarkDirty(player)
				return Net.Ok()
			end
		end
		return Net.Fail("You do not have that quest")
	end)
end

return QuestService
