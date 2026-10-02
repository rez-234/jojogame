--!strict
-- Shared progression math so the server and the UI always agree.

local Config = require(script.Parent.Config)
local StandData = require(script.Parent.StandData)
local HorseData = require(script.Parent.HorseData)
local Types = require(script.Parent.Types)

local Progression = {}

function Progression.XPForLevel(level: number): number
	return math.floor(Config.Level.XPBase * level ^ Config.Level.XPExponent)
end

function Progression.MaxHealth(profile: Types.Profile): number
	return Config.Level.BaseHealth + profile.Stats.Health * Config.Level.HealthPerPoint + (profile.Level - 1) * 2
end

function Progression.PowerMult(profile: Types.Profile): number
	return 1 + profile.Stats.Power * Config.Level.PowerPerPoint
end

function Progression.SpeedMult(profile: Types.Profile): number
	return 1 + profile.Stats.Speed * Config.Level.SpeedPerPoint
end

function Progression.StaminaMax(profile: Types.Profile): number
	return Config.Combat.PlayerStaminaMax + profile.Stats.Stamina * Config.Level.StaminaPerPoint
end

function Progression.IsUnlocked(level: number, key: string): boolean
	for _, unlock in Config.Level.Unlocks do
		if unlock.Key == key then
			return level >= unlock.Level
		end
	end
	return true
end

function Progression.UnlockLevel(key: string): number
	for _, unlock in Config.Level.Unlocks do
		if unlock.Key == key then
			return unlock.Level
		end
	end
	return 1
end

export type TierInfo = {
	Index: number,
	Name: string,
	XP: number,
	Damage: number,
	Cooldown: number,
	Speed: number,
	ExtraHits: number,
	NextXP: number?,
}

function Progression.MasteryTier(xp: number): TierInfo
	local tiers = Config.Mastery.Tiers
	local index = 1
	for i, tier in tiers do
		if xp >= tier.XP then
			index = i
		end
	end
	local tier = tiers[index]
	local nextTier = tiers[index + 1]
	return {
		Index = index,
		Name = tier.Name,
		XP = tier.XP,
		Damage = tier.Damage,
		Cooldown = tier.Cooldown,
		Speed = tier.Speed,
		ExtraHits = tier.ExtraHits,
		NextXP = if nextTier then nextTier.XP else nil,
	}
end

function Progression.MasteryXP(profile: Types.Profile, family: string, moveId: string): number
	local fam = profile.Mastery[family]
	return if fam then fam[moveId] or 0 else 0
end

function Progression.StandDurability(stand: StandData.Stand): number
	return Config.Stand.BaseDurability + (stand.Stats.Durability - 1) * Config.Stand.DurabilityPerStatGrade
end

function Progression.GradeValue(list: { number }, grade: number): number
	return list[math.clamp(grade, 1, #list)]
end

export type RequirementStatus = {
	Text: string,
	Met: boolean,
	Have: number,
	Need: number,
}

-- Evolution check used both for validation and the UI.
function Progression.EvolutionStatus(profile: Types.Profile, stand: StandData.Stand): (boolean, { RequirementStatus })
	local evo = stand.Evolution
	if not evo then
		return false, {}
	end
	local list: { RequirementStatus } = {}
	local all = true
	local evolutionKey = if stand.Stage >= 2 then "RequiemEvolution" else "Evolution"
	local unlockLevel = Progression.UnlockLevel(evolutionKey)
	local levelNeed = math.max(evo.Level, unlockLevel)
	local levelMet = profile.Level >= levelNeed
	table.insert(list, { Text = "Reach level " .. levelNeed, Met = levelMet, Have = profile.Level, Need = levelNeed })
	all = all and levelMet
	for _, r in evo.Requirements do
		local have = 0
		if r.Kind == "Item" then
			have = profile.Items[r.Id] or 0
		elseif r.Kind == "Counter" then
			have = profile.Counters[r.Id] or 0
		end
		local met = have >= r.Amount
		table.insert(list, { Text = r.Text, Met = met, Have = have, Need = r.Amount })
		all = all and met
	end
	return all, list
end

-- Horses
function Progression.HorseXPForLevel(level: number): number
	return math.floor(Config.Horse.XPCurveBase * level ^ Config.Horse.XPCurveExponent)
end

export type HorseStats = {
	Walk: number,
	Trot: number,
	Canter: number,
	Gallop: number,
	Acceleration: number,
	StaminaMax: number,
	JumpPower: number,
	TurnRate: number,
	MaxHealth: number,
}

function Progression.HorseStats(horse: Types.OwnedHorse): HorseStats
	local breed = HorseData.Breeds[horse.Breed] or HorseData.Breeds.Mustang
	local lv = horse.Level - 1
	local speed = breed.Speed * (1 + lv * Config.Horse.SpeedPerLevel)
	local stamina = breed.Stamina * (1 + lv * Config.Horse.StaminaPerLevel)
	local accel = breed.Acceleration * (1 + lv * Config.Horse.AccelerationPerLevel)
	local h = Config.Horse
	return {
		Walk = h.WalkSpeed * speed,
		Trot = h.TrotSpeed * speed,
		Canter = h.CanterSpeed * speed,
		Gallop = h.GallopSpeed * speed,
		Acceleration = h.BaseAcceleration * accel,
		StaminaMax = h.StaminaMax * stamina,
		JumpPower = h.BaseJumpPower * breed.JumpPower,
		TurnRate = h.BaseTurnRate * breed.Turning,
		MaxHealth = breed.Durability + lv * 3,
	}
end

function Progression.BreedStats(breedId: string): HorseStats
	return Progression.HorseStats({
		Id = "",
		Breed = breedId,
		Name = "",
		Level = 1,
		XP = 0,
		Health = -1,
		Coat = 1,
		ManeColor = 1,
		Pattern = "",
		Cosmetics = { Saddle = "Brown", Blanket = "Red", Mane = "Classic", Shoes = "Iron" },
	})
end

-- Elo style ranked change for the winner.
function Progression.RankedDelta(winner: number, loser: number): number
	local expected = 1 / (1 + 10 ^ ((loser - winner) / 400))
	return math.max(1, math.floor(Config.PvP.RankedK * (1 - expected) + 0.5))
end

return Progression
