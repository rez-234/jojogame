--!strict
-- Stats tab: level and XP, stat points to spend, what each stat gives, the
-- unlock ladder and a record of the ride so far.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Util = require(ReplicatedStorage.Shared.Util)
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)

local Stats = {}
Stats.Name = "Stats"

local C = Kit.Colors

local STATS = {
	{ Key = "Health", Text = "Health", Describe = function(points: number): string
		return string.format("+%d max health", points * Config.Level.HealthPerPoint)
	end },
	{ Key = "Power", Text = "Power", Describe = function(points: number): string
		return string.format("+%.1f%% damage", points * Config.Level.PowerPerPoint * 100)
	end },
	{ Key = "Speed", Text = "Speed", Describe = function(points: number): string
		return string.format("+%.1f%% move speed", points * Config.Level.SpeedPerPoint * 100)
	end },
	{ Key = "Stamina", Text = "Stamina", Describe = function(points: number): string
		return string.format("+%d max stamina", math.floor(points * Config.Level.StaminaPerPoint))
	end },
}

local RECORD = {
	{ Key = "NPCKills", Text = "Outlaws defeated" },
	{ Key = "BossKills", Text = "Bosses defeated" },
	{ Key = "StagesFinished", Text = "Race stages finished" },
	{ Key = "RacesWon", Text = "Races won" },
	{ Key = "Tamed", Text = "Horses tamed" },
	{ Key = "QuestsCompleted", Text = "Quests completed" },
	{ Key = "Distance", Text = "Distance ridden (ft)" },
}

function Stats.Render(page: ScrollingFrame, ctx: any)
	local profile = State.Profile
	if not profile then
		Kit.Paragraph("Loading your saddlebag...", { Parent = page })
		return
	end

	local level = Kit.Section({ LayoutOrder = 1, Parent = page })
	Kit.Heading("Level " .. profile.Level, Kit.Text.Title, { LayoutOrder = 1, Parent = level })
	local need = Progression.XPForLevel(profile.Level)
	local bar = Kit.Bar(C.XP, 18, { LayoutOrder = 2, Parent = level })
	if profile.Level >= Config.Level.MaxLevel then
		bar.Set(1, "Max level")
	else
		bar.Set(profile.XP / math.max(1, need), string.format("%s / %s XP", Util.formatNumber(profile.XP), Util.formatNumber(need)))
	end
	Kit.Paragraph(
		if profile.StatPoints > 0
			then string.format("You have %d stat points to spend. Each level gives %d.", profile.StatPoints, Config.Level.StatPointsPerLevel)
			else string.format("No points to spend. Each level gives %d.", Config.Level.StatPointsPerLevel),
		{ LayoutOrder = 3, TextColor3 = if profile.StatPoints > 0 then C.Accent else C.InkSoft, FontFace = Kit.Fonts.BodyBold, Parent = level }
	)

	local stats = Kit.Section({ LayoutOrder = 2, Parent = page })
	Kit.Heading("Stats", Kit.Text.Label, { LayoutOrder = 0, Parent = stats })
	for i, stat in STATS do
		local points = (profile.Stats :: any)[stat.Key] or 0
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = i, Parent = stats })
		Kit.Label(stat.Text, { FontFace = Kit.Fonts.BodyBold, Size = UDim2.new(0, 110, 1, 0), Parent = row })
		Kit.Label(tostring(points), { FontFace = Kit.Fonts.Numbers, Size = UDim2.new(0, 50, 1, 0), Position = UDim2.fromOffset(110, 0), Parent = row })
		Kit.Label(stat.Describe(points), { TextColor3 = C.InkSoft, Size = UDim2.new(1, -340, 1, 0), Position = UDim2.fromOffset(160, 0), Parent = row })
		local plusOne = Kit.Button("+1", "Secondary", function()
			ctx.Do("SpendStat", nil, stat.Key, 1)
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -78, 0.5, 0), Size = UDim2.fromOffset(64, 30), Parent = row })
		local plusFive = Kit.Button("+5", "Secondary", function()
			ctx.Do("SpendStat", nil, stat.Key, math.min(5, profile.StatPoints))
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(64, 30), Parent = row })
		plusOne.SetEnabled(profile.StatPoints >= 1)
		plusFive.SetEnabled(profile.StatPoints >= 2)
	end
	Kit.Rule({ LayoutOrder = 10, Parent = stats })
	local _, maxHealth = Kit.Row("Max health", "", { LayoutOrder = 11, Parent = stats })
	maxHealth.Text = tostring(Progression.MaxHealth(profile))
	local _, staminaMax = Kit.Row("Max stamina", "", { LayoutOrder = 12, Parent = stats })
	staminaMax.Text = tostring(math.floor(Progression.StaminaMax(profile)))
	local _, power = Kit.Row("Damage multiplier", "", { LayoutOrder = 13, Parent = stats })
	power.Text = string.format("x%.2f", Progression.PowerMult(profile))
	local _, speed = Kit.Row("Speed multiplier", "", { LayoutOrder = 14, Parent = stats })
	speed.Text = string.format("x%.2f", Progression.SpeedMult(profile))

	local unlocks = Kit.Section({ LayoutOrder = 3, Parent = page })
	Kit.Heading("Unlocks", Kit.Text.Label, { LayoutOrder = 0, Parent = unlocks })
	for i, unlock in Config.Level.Unlocks do
		local done = profile.Level >= unlock.Level
		local _, value = Kit.Row(unlock.Text, if done then "Open" else "Level " .. unlock.Level, { LayoutOrder = i, Parent = unlocks })
		value.TextColor3 = if done then C.Good else C.InkSoft
	end

	local record = Kit.Section({ LayoutOrder = 4, Parent = page })
	Kit.Heading("Record", Kit.Text.Label, { LayoutOrder = 0, Parent = record })
	for i, entry in RECORD do
		Kit.Row(entry.Text, Util.formatNumber(profile.Counters[entry.Key] or 0), { LayoutOrder = i, Parent = record })
	end
	Kit.Row("Best race time", if profile.Race.BestTotal then Util.formatTime(profile.Race.BestTotal) else "none yet", { LayoutOrder = 20, Parent = record })
	Kit.Row("Ranked rating", tostring(profile.Ranked), { LayoutOrder = 21, Parent = record })
end

return Stats
