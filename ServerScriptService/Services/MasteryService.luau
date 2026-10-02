--!strict
-- Per-move mastery. XP is earned only when a move lands on a valid target,
-- with diminishing returns for hitting the same target over and over inside
-- a time window. Tiers raise damage, cut cooldowns, speed moves up and add
-- extra hits. Saved per Stand family per move.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Config = require(ReplicatedStorage.Shared.Config)
local StandData = require(ReplicatedStorage.Shared.StandData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local DataService = require(script.Parent.DataService)
local Signals = require(script.Parent.Signals)
local Net = require(script.Parent.Net)

local MasteryService = {}

type Recent = { Count: number, First: number }

-- recent[player][family/move][targetKey]
local recent: { [Player]: { [string]: { [any]: Recent } } } = {}

local NOVICE = Progression.MasteryTier(0)

function MasteryService.Tier(player: Player?, family: string?, moveId: string): Progression.TierInfo
	if not player or not family then
		return NOVICE
	end
	local profile = DataService.Get(player)
	if not profile then
		return NOVICE
	end
	return Progression.MasteryTier(Progression.MasteryXP(profile, family, moveId))
end

-- True when any move of this family has reached the top tier.
function MasteryService.AnyPerfected(player: Player, family: string): boolean
	local profile = DataService.Get(player)
	if not profile then
		return false
	end
	local moves = profile.Mastery[family]
	if not moves then
		return false
	end
	local top = Config.Mastery.Tiers[#Config.Mastery.Tiers].XP
	for _, xp in moves do
		if xp >= top then
			return true
		end
	end
	return false
end

-- Base XP for one landed hit of a move. Long cooldown moves give more per hit,
-- multi-hit moves give less per hit so every move levels at a similar pace.
local function baseXP(moveId: string): number
	if moveId == StandData.PunchMoveId then
		return Config.Mastery.XPPerHit * 0.5
	end
	local move = StandData.GetMove(moveId)
	if not move then
		return Config.Mastery.XPPerHit
	end
	local cooldownFactor = math.clamp(move.Cooldown / 6, 0.5, 3)
	local hits = math.max(move.Hits or 1, move.Count or 1)
	return Config.Mastery.XPPerHit * cooldownFactor / math.sqrt(hits)
end

local function award(player: Player, family: string, moveId: string, targetKey: any)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local now = os.clock()
	local key = family .. "/" .. moveId
	local perPlayer = recent[player]
	if not perPlayer then
		perPlayer = {}
		recent[player] = perPlayer
	end
	local perMove = perPlayer[key]
	if not perMove then
		perMove = {}
		perPlayer[key] = perMove
	end
	local r: Recent = perMove[targetKey] or { Count = 0, First = now }
	if now - r.First > Config.Mastery.SameTargetWindow then
		r = { Count = 0, First = now }
	end
	perMove[targetKey] = r
	local factor = math.max(Config.Mastery.MinFactor, (1 - Config.Mastery.SameTargetFalloff) ^ r.Count)
	r.Count += 1

	local fam = profile.Mastery[family]
	if not fam then
		fam = {}
		profile.Mastery[family] = fam
	end
	local before = fam[moveId] or 0
	local after = before + baseXP(moveId) * factor
	fam[moveId] = after
	local oldTier = Progression.MasteryTier(before)
	local newTier = Progression.MasteryTier(after)
	DataService.MarkDirty(player)
	if newTier.Index > oldTier.Index then
		local moveName = if moveId == StandData.PunchMoveId then "Punch" else ((StandData.GetMove(moveId) or {}) :: any).Name or moveId
		Net.Notify(player, "Mastery", { Family = family, Move = moveId, MoveName = moveName, Tier = newTier.Index, TierName = newTier.Name })
		Signals.MasteryTier:Fire(player, family, moveId, newTier.Index)
		if newTier.Index == #Config.Mastery.Tiers then
			-- Perfected changes the Stand's look.
			Signals.StandChanged:Fire(player)
		end
	end
end

-- Called for every landed hit of a mastery tracked move.
function MasteryService.RecordHit(player: Player, family: string, moveId: string, target: Model)
	award(player, family, moveId, target)
end

-- Utility moves (time stop, heal, teleports, buffs) count when used in a fight.
function MasteryService.RecordUse(player: Player, family: string, moveId: string)
	award(player, family, moveId, "utility")
end

function MasteryService.Init()
	Players.PlayerRemoving:Connect(function(player)
		recent[player] = nil
	end)
	Signals.Hit:Connect(function(attacker, target, hit, _damage, result)
		if result ~= "Hit" or not attacker or not attacker.Player then
			return
		end
		if hit.Family and hit.MoveId and not hit.IsDot then
			MasteryService.RecordHit(attacker.Player, hit.Family, hit.MoveId, target.Model)
		end
	end)
end

return MasteryService
