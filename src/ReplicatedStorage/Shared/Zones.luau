--!strict
-- Classifies a world position: town (safe), wild PvE zone, boss arena or PvP arena.

local Route = require(script.Parent.Route)
local Layout = require(script.Parent.Layout)

export type ZoneInfo = {
	Kind: string, -- "Town", "Wild", "Boss", "Arena", "Start"
	Name: string,
	Safe: boolean,
	Stage: number,
	Level: number,
	Town: Layout.Town?,
	Arena: Layout.Arena?,
	Dist: number,
	Lateral: number,
}

local Zones = {}

function Zones.Classify(pos: Vector3): ZoneInfo
	local d, lateral = Route.Project(pos)
	local stage = Route.StageAtDist(d)
	if Layout.InPvPArena(pos) then
		return {
			Kind = "Arena",
			Name = "Ranked Arena",
			Safe = false,
			Stage = stage.Index,
			Level = 0,
			Dist = d,
			Lateral = lateral,
		}
	end
	local town = Layout.TownAt(pos)
	if town then
		return {
			Kind = "Town",
			Name = town.Name,
			Safe = true,
			Stage = stage.Index,
			Level = 0,
			Town = town,
			Dist = d,
			Lateral = lateral,
		}
	end
	if d < Layout.StartDist + 60 and math.abs(lateral) < 60 then
		return {
			Kind = "Start",
			Name = "Start Line",
			Safe = true,
			Stage = 1,
			Level = 0,
			Dist = d,
			Lateral = lateral,
		}
	end
	local arena = Layout.ArenaAt(pos)
	if arena then
		return {
			Kind = "Boss",
			Name = stage.Name .. " Arena",
			Safe = false,
			Stage = stage.Index,
			Level = stage.EnemyLevel + 6,
			Arena = arena,
			Dist = d,
			Lateral = lateral,
		}
	end
	return {
		Kind = "Wild",
		Name = stage.Name,
		Safe = false,
		Stage = stage.Index,
		Level = stage.EnemyLevel,
		Dist = d,
		Lateral = lateral,
	}
end

return Zones
