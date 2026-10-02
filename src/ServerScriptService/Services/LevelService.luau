--!strict
-- Player XP, levels and stat points. XP comes from every activity; the curve
-- and the per-point bonuses live in Config.Level.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local DataService = require(script.Parent.DataService)
local Signals = require(script.Parent.Signals)
local Net = require(script.Parent.Net)

local LevelService = {}

local STATS = { Health = true, Power = true, Speed = true, Stamina = true }

function LevelService.AddXP(player: Player, amount: number, reason: string?)
	local profile = DataService.Get(player)
	if not profile or amount <= 0 then
		return
	end
	if profile.Level >= Config.Level.MaxLevel then
		return
	end
	local gained = math.floor(amount + 0.5)
	profile.XP += gained
	local newUnlocks = {}
	local leveled = false
	while profile.Level < Config.Level.MaxLevel and profile.XP >= Progression.XPForLevel(profile.Level) do
		profile.XP -= Progression.XPForLevel(profile.Level)
		profile.Level += 1
		profile.StatPoints += Config.Level.StatPointsPerLevel
		leveled = true
		for _, unlock in Config.Level.Unlocks do
			if unlock.Level == profile.Level then
				profile.Unlocked[unlock.Key] = true
				table.insert(newUnlocks, unlock.Text)
			end
		end
		Signals.LevelUp:Fire(player, profile.Level)
	end
	if profile.Level >= Config.Level.MaxLevel then
		profile.XP = 0
	end
	DataService.MarkDirty(player)
	Net.Notify(player, "XP", { Amount = gained, Reason = reason })
	if leveled then
		Net.Notify(player, "LevelUp", { Level = profile.Level, Unlocks = newUnlocks, Points = profile.StatPoints })
	end
end

function LevelService.Init()
	Net.OnRequest("SpendStat", function(player: Player, stat: any, amount: any)
		local profile = DataService.Get(player)
		if not profile then
			return Net.Fail("Profile not loaded")
		end
		if type(stat) ~= "string" or not STATS[stat] then
			return Net.Fail("Unknown stat")
		end
		local n = if Net.IsNumber(amount, 1, 100) then math.floor(amount) else 1
		if profile.StatPoints < n then
			return Net.Fail("Not enough stat points")
		end
		profile.StatPoints -= n
		local stats = profile.Stats :: any
		stats[stat] += n
		DataService.MarkDirty(player)
		Signals.StatsChanged:Fire(player)
		return Net.Ok()
	end)
end

return LevelService
