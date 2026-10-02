--!strict
-- Quest templates for daily quests and town quest boards.
-- Event names match what QuestService.Record is called with.

export type Reward = {
	Cash: number?,
	XP: number?,
	Items: { [string]: number }?,
}

export type Quest = {
	Id: string,
	Name: string,
	Text: string,
	Event: string, -- "NPCKill", "PvPKill", "BossKill", "Ride", "StageFinish", "RaceFinish", "MoveHit", "Tame", "ArenaWin"
	Amount: number,
	Reward: Reward,
	Pool: string, -- "Daily" or "Board"
	MinLevel: number,
}

local QuestData = {}

QuestData.Quests = {
	D_Outlaws = {
		Id = "D_Outlaws",
		Name = "Thin the Herd",
		Text = "Defeat 15 enemies on the trail.",
		Event = "NPCKill",
		Amount = 15,
		Reward = { Cash = 400, XP = 400 },
		Pool = "Daily",
		MinLevel = 1,
	},
	D_Ride = {
		Id = "D_Ride",
		Name = "Long Haul",
		Text = "Ride 6,000 studs on horseback.",
		Event = "Ride",
		Amount = 6000,
		Reward = { Cash = 350, XP = 300 },
		Pool = "Daily",
		MinLevel = 1,
	},
	D_Moves = {
		Id = "D_Moves",
		Name = "Practice Makes Perfect",
		Text = "Land 120 Stand move hits.",
		Event = "MoveHit",
		Amount = 120,
		Reward = { Cash = 300, XP = 450 },
		Pool = "Daily",
		MinLevel = 1,
	},
	D_Stage = {
		Id = "D_Stage",
		Name = "Checkpoint Runner",
		Text = "Finish 2 race stages.",
		Event = "StageFinish",
		Amount = 2,
		Reward = { Cash = 500, XP = 500 },
		Pool = "Daily",
		MinLevel = 1,
	},
	D_PvP = {
		Id = "D_PvP",
		Name = "Duelist",
		Text = "Win 2 fights against other riders.",
		Event = "PvPKill",
		Amount = 2,
		Reward = { Cash = 600, XP = 600, Items = { Bandage = 3 } },
		Pool = "Daily",
		MinLevel = 5,
	},
	D_Boss = {
		Id = "D_Boss",
		Name = "Head Hunter",
		Text = "Defeat a stage boss.",
		Event = "BossKill",
		Amount = 1,
		Reward = { Cash = 800, XP = 900, Items = { Arrow = 1 } },
		Pool = "Daily",
		MinLevel = 12,
	},
	D_Arena = {
		Id = "D_Arena",
		Name = "Ranked Rider",
		Text = "Win a ranked arena match.",
		Event = "ArenaWin",
		Amount = 1,
		Reward = { Cash = 500, XP = 500 },
		Pool = "Daily",
		MinLevel = 5,
	},
	D_Tame = {
		Id = "D_Tame",
		Name = "Horse Whisperer",
		Text = "Tame a wild horse.",
		Event = "Tame",
		Amount = 1,
		Reward = { Cash = 400, XP = 300, Items = { Feed = 2 } },
		Pool = "Daily",
		MinLevel = 1,
	},
	B_Bandits = {
		Id = "B_Bandits",
		Name = "Wanted: Bandits",
		Text = "Clear 8 outlaws near town.",
		Event = "NPCKill",
		Amount = 8,
		Reward = { Cash = 250, XP = 250 },
		Pool = "Board",
		MinLevel = 1,
	},
	B_Courier = {
		Id = "B_Courier",
		Name = "Mail Run",
		Text = "Ride 2,500 studs.",
		Event = "Ride",
		Amount = 2500,
		Reward = { Cash = 200, XP = 150 },
		Pool = "Board",
		MinLevel = 1,
	},
	B_Training = {
		Id = "B_Training",
		Name = "Sparring Partner",
		Text = "Land 50 Stand move hits.",
		Event = "MoveHit",
		Amount = 50,
		Reward = { Cash = 150, XP = 250 },
		Pool = "Board",
		MinLevel = 1,
	},
	B_Bounty = {
		Id = "B_Bounty",
		Name = "Bounty: Stage Boss",
		Text = "Defeat the boss of any stage.",
		Event = "BossKill",
		Amount = 1,
		Reward = { Cash = 700, XP = 700 },
		Pool = "Board",
		MinLevel = 12,
	},
	B_Race = {
		Id = "B_Race",
		Name = "Sign the Ledger",
		Text = "Finish a full race.",
		Event = "RaceFinish",
		Amount = 1,
		Reward = { Cash = 900, XP = 900, Items = { Arrow = 1 } },
		Pool = "Board",
		MinLevel = 1,
	},
	B_Wrangler = {
		Id = "B_Wrangler",
		Name = "Wrangler",
		Text = "Tame 2 wild horses.",
		Event = "Tame",
		Amount = 2,
		Reward = { Cash = 500, XP = 400 },
		Pool = "Board",
		MinLevel = 1,
	},
} :: { [string]: Quest }

function QuestData.Pool(pool: string, level: number): { Quest }
	local list = {}
	for _, q in QuestData.Quests do
		if q.Pool == pool and q.MinLevel <= level then
			table.insert(list, q)
		end
	end
	table.sort(list, function(a, b)
		return a.Id < b.Id
	end)
	return list
end

return QuestData
