--!strict
-- Server wide events so services can react to each other without requiring
-- each other in a circle. Payloads are passed by reference.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)

local Signals = {
	-- (attacker, target, hit, damageDealt, result) where result is "Hit" or "Blocked".
	Hit = Signal.new() :: Signal.Signal<any, any, any, number, string>,
	-- (killer, victim) with Combatant tables; killer can be nil.
	Killed = Signal.new() :: Signal.Signal<any, any>,
	-- (user, move)
	MoveUsed = Signal.new() :: Signal.Signal<any, any>,
	-- (player, newLevel)
	LevelUp = Signal.new() :: Signal.Signal<Player, number>,
	-- (player) after stat points are spent
	StatsChanged = Signal.new() :: Signal.Signal<Player>,
	-- (player, family, moveId, tierIndex)
	MasteryTier = Signal.new() :: Signal.Signal<Player, string, string, number>,
	-- (player) whenever the active Stand id or skin changes
	StandChanged = Signal.new() :: Signal.Signal<Player>,
	-- (player, event, amount) quest progress, see QuestData events
	Quest = Signal.new() :: Signal.Signal<Player, string, number>,
	-- (player, zoneInfo, previousZoneInfo)
	ZoneChanged = Signal.new() :: Signal.Signal<Player, any, any>,
	-- (player, character) after the character is positioned and set up
	CharacterReady = Signal.new() :: Signal.Signal<Player, Model>,
}

return Signals
