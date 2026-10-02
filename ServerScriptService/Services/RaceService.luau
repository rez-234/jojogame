--!strict
-- The Steel Ball Run itself: a lobby at the San Diego start line, a start
-- countdown, checkpoint timing per stage, live standings, rival riders with
-- rubber banding who attack racers with their Stands, rewards and records.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Route = require(ReplicatedStorage.Shared.Route)
local Layout = require(ReplicatedStorage.Shared.Layout)
local HeightField = require(ReplicatedStorage.Shared.HeightField)
local NPCData = require(ReplicatedStorage.Shared.NPCData)
local HorseData = require(ReplicatedStorage.Shared.HorseData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Net)
local Signals = require(script.Parent.Signals)
local Combatants = require(script.Parent.Combatants)
local HorseService = require(script.Parent.HorseService)
local CharacterService = require(script.Parent.CharacterService)
local LevelService = require(script.Parent.LevelService)
local SkinService = require(script.Parent.SkinService)
local NPCService = require(script.Parent.NPCService)
local NPCBrain = require(script.Parent.NPCBrain)

type Combatant = Combatants.Combatant

local RaceService = {}

local R = Config.Race

type Racer = {
	Name: string,
	Player: Player?,
	Rival: any?,
	UserId: number,
	Next: number, -- next checkpoint index
	Splits: { number },
	Dist: number,
	Finished: boolean,
	FinishTime: number?,
	Place: number?,
	Lane: number,
	LastAttack: number,
}

local raceEvent: RemoteEvent
local state = "Idle" -- "Idle", "Lobby", "Starting", "Running", "Ending"
local lobby: { [Player]: boolean } = {}
local racers: { Racer } = {}
local startedAt = 0
local lobbyEndsAt = 0
local finishCount = 0

local function broadcast(kind: string, data: any)
	for _, r in racers do
		if r.Player and r.Player.Parent then
			raceEvent:FireClient(r.Player, kind, data)
		end
	end
end

local function lobbyBroadcast(kind: string, data: any)
	for player in lobby do
		if player.Parent then
			raceEvent:FireClient(player, kind, data)
		end
	end
end

local function racerFor(player: Player): Racer?
	for _, r in racers do
		if r.Player == player then
			return r
		end
	end
	return nil
end

function RaceService.IsRacing(player: Player): boolean
	return racerFor(player) ~= nil and (state == "Starting" or state == "Running")
end

local function gridCFrame(slot: number): CFrame
	local row = math.floor((slot - 1) / 4)
	local col = (slot - 1) % 4
	local d = Layout.StartDist - 8 - row * 10
	local lateral = (col - 1.5) * 5
	local p, t = Route.OffsetPoint(d, lateral)
	local y = HeightField.Surface(p.X, p.Z)
	local pos = Vector3.new(p.X, y, p.Z)
	return CFrame.lookAt(pos, pos + t)
end

local function elapsed(): number
	return os.clock() - startedAt
end

-- Live order: finishers by time, then by distance along the route.
local function standings(): { Racer }
	local list = table.clone(racers)
	table.sort(list, function(a, b)
		if a.Finished ~= b.Finished then
			return a.Finished
		end
		if a.Finished and b.Finished then
			return (a.FinishTime or 0) < (b.FinishTime or 0)
		end
		return a.Dist > b.Dist
	end)
	return list
end

local function bestHumanDist(): number
	local best = 0
	for _, r in racers do
		if r.Player and not r.Finished then
			best = math.max(best, r.Dist)
		end
	end
	return best
end

-- Rival control on horseback.
local function rivalControl(racer: Racer, info: NPCData.Rival)
	return function(entry: any, sh: any, _dt: number)
		local c = entry.C :: Combatant
		if state ~= "Running" then
			return { Throttle = 0, Steer = 0, Gallop = false, Jump = false, TargetSpeed = 0 }
		end
		if racer.Finished then
			return { Throttle = 0, Steer = 0, Gallop = false, Jump = false, TargetSpeed = 0 }
		end
		local pos = c.Root.Position
		local d = Route.Project(pos)
		local ahead = Route.OffsetPoint(math.min(Route.Length, d + 30), racer.Lane)
		local heading = Vector3.new(ahead.X - pos.X, 0, ahead.Z - pos.Z)
		-- Rubber band against the best human racer.
		local diff = d - bestHumanDist()
		local band = 1 - R.RubberBandStrength * math.clamp(diff / R.RubberBandRange, -1, 1)
		local speed = R.RivalBaseSpeed * info.SpeedMult * band
		speed = math.min(speed, sh.Motor.Stats.Gallop * 1.15)
		sh.Motor.SpeedLimit = speed
		return { Throttle = 0, Steer = 0, Gallop = true, Jump = false, TargetSpeed = speed, TargetHeading = heading }
	end
end

local function spawnRivals()
	local list = table.clone(NPCData.Rivals)
	Util.shuffle(Random.new(), list)
	for k = 1, math.min(R.Rivals, #list) do
		local info = list[k]
		local slot = #racers + 1
		local cf = gridCFrame(slot)
		local racer: Racer = {
			Name = info.Name,
			Player = nil,
			Rival = nil,
			UserId = -k,
			Next = 1,
			Splits = {},
			Dist = Layout.StartDist,
			Finished = false,
			Lane = ((slot - 1) % 4 - 1.5) * 5,
			LastAttack = 0,
		}
		local level = 10
		local entry = NPCService.SpawnRider({
			Name = info.Name,
			Outfit = info.Outfit,
			Health = 400,
			Level = level,
			Breed = info.Breed,
			At = cf,
			Moves = info.Moves,
			Stand = info.Stand,
			Passive = true,
			Control = rivalControl(racer, info),
		})
		if entry then
			entry.C.Model:SetAttribute("Rival", true)
			racer.Rival = entry
			table.insert(racers, racer)
		end
	end
end

local function removeRivals()
	for _, r in racers do
		if r.Rival then
			NPCService.Remove(r.Rival)
			r.Rival = nil
		end
	end
end

local function freezeHorse(player: Player, frozen: boolean)
	local horse = HorseService.Active(player)
	local root = horse and horse.PrimaryPart
	if root then
		root.Anchored = frozen
		if not frozen and HorseService.IsMounted(player) then
			pcall(function()
				root:SetNetworkOwner(player)
			end)
		end
	end
end

local function startRace()
	state = "Starting"
	racers = {}
	finishCount = 0
	local slot = 0
	for player in lobby do
		local c = Combatants.ForPlayer(player)
		if player.Parent and c and Combatants.IsAlive(c) then
			slot += 1
			local racer: Racer = {
				Name = player.DisplayName,
				Player = player,
				Rival = nil,
				UserId = player.UserId,
				Next = 1,
				Splits = {},
				Dist = Layout.StartDist,
				Finished = false,
				Lane = ((slot - 1) % 4 - 1.5) * 5,
				LastAttack = 0,
			}
			table.insert(racers, racer)
			c.Data.Racing = true
			if HorseService.IsMounted(player) then
				HorseService.Dismount(player, false)
			end
			local cf = gridCFrame(slot)
			CharacterService.Teleport(player, cf * CFrame.new(3.5, 0, 0))
			task.spawn(function()
				local horse = HorseService.SpawnAt(player, cf.Position, cf.LookVector)
				if horse then
					task.wait(0.2)
					HorseService.Mount(player)
					task.wait(0.1)
					freezeHorse(player, true)
				end
			end)
		end
	end
	lobby = {}
	if #racers == 0 then
		state = "Idle"
		return
	end
	spawnRivals()
	broadcast("Countdown", { T = R.StartCountdown, Racers = #racers })
	task.delay(R.StartCountdown, function()
		if state ~= "Starting" then
			return
		end
		state = "Running"
		startedAt = os.clock()
		for _, r in racers do
			if r.Player then
				freezeHorse(r.Player, false)
				HorseService.ResetSanity(r.Player)
			end
		end
		broadcast("Go", { Stage = Route.Stages[1].Name, Limit = R.TimeLimitMinutes * 60 })
	end)
end

local function rewardFinisher(r: Racer, humanPlace: number)
	local player = r.Player
	if not player then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local place = r.Place or 99
	local cash = (R.PlacementCash[place] or 0) + R.FinishCash
	DataService.AddCash(player, cash)
	Net.Notify(player, "Cash", { Amount = cash })
	LevelService.AddXP(player, Config.XP.RaceFinish * (if place <= 3 then 1.5 else 1), "Finished the race")
	profile.Race.Finishes += 1
	local total = r.FinishTime or 0
	if not profile.Race.BestTotal or total < profile.Race.BestTotal then
		profile.Race.BestTotal = total
	end
	if place == 1 then
		profile.Race.Wins += 1
		DataService.AddCounter(player, "RacesWon", 1)
		DataService.AddItem(player, "Arrow", R.WinArrows)
		HorseService.AddHorseXP(player, Config.Horse.XPPerRaceWin)
		if math.random() < R.WinHorseChance then
			local options = {}
			for _, id in HorseData.Order do
				local breed = HorseData.Breeds[id]
				if breed.Rarity == "Rare" or breed.Rarity == "Epic" or breed.Rarity == "Legendary" then
					table.insert(options, id)
				end
			end
			HorseService.Grant(player, options[math.random(1, #options)], "Race")
		end
	elseif place <= 3 then
		DataService.AddItem(player, "Arrow", R.PodiumArrows)
	end
	if place <= 3 then
		SkinService.GrantRandom(player, "Race")
	end
	Signals.Quest:Fire(player, "RaceFinish", 1)
	DataService.MarkDirty(player)
	raceEvent:FireClient(player, "Finished", { Place = place, Time = total, HumanPlace = humanPlace, Cash = cash })
end

local function endRace()
	if state == "Ending" or state == "Idle" then
		return
	end
	state = "Ending"
	local results = {}
	for i, r in standings() do
		table.insert(results, { Name = r.Name, Place = i, Time = r.FinishTime, Finished = r.Finished, Rival = r.Player == nil })
	end
	broadcast("End", { Results = results })
	for _, r in racers do
		if r.Player then
			local c = Combatants.ForPlayer(r.Player)
			if c then
				c.Data.Racing = nil
			end
		end
	end
	task.delay(10, function()
		removeRivals()
		racers = {}
		state = "Idle"
	end)
end

local function passCheckpoint(r: Racer, cpIndex: number)
	local now = elapsed()
	r.Splits[cpIndex] = now
	r.Next = cpIndex + 1
	local cp = Layout.Checkpoints[cpIndex]
	local isFinish = cpIndex == #Layout.Checkpoints
	local stageTime = now - (if cpIndex > 1 then r.Splits[cpIndex - 1] or 0 else 0)
	local stage = Route.Stages[cpIndex]
	if r.Player then
		local player = r.Player
		local profile = DataService.Get(player)
		if profile and stage then
			local best = profile.Race.BestStages[stage.Id]
			if not best or stageTime < best then
				profile.Race.BestStages[stage.Id] = stageTime
			end
			DataService.AddCash(player, R.StageCash)
			LevelService.AddXP(player, Config.XP.RaceStage, stage.Name .. " stage")
			DataService.AddCounter(player, "StagesFinished", 1)
			Signals.Quest:Fire(player, "StageFinish", 1)
		end
		raceEvent:FireClient(player, "Checkpoint", {
			Index = cpIndex,
			Name = cp.Name,
			Split = now,
			StageTime = stageTime,
			Next = if isFinish then nil else Route.Stages[cpIndex + 1].Name,
		})
	end
	if isFinish then
		r.Finished = true
		r.FinishTime = now
		finishCount += 1
		r.Place = finishCount
		if r.Player then
			local humanPlace = 0
			for _, other in racers do
				if other.Player and other.Finished then
					humanPlace += 1
				end
			end
			rewardFinisher(r, humanPlace)
		end
		broadcast("Notice", { Text = r.Name .. " finished " .. Util.ordinal(r.Place :: number) .. " in " .. Util.formatTime(now) })
	end
end

local function tickRunning()
	if elapsed() > R.TimeLimitMinutes * 60 then
		broadcast("Notice", { Text = "Time is up." })
		endRace()
		return
	end
	local humansLeft = 0
	for _, r in racers do
		local root: BasePart? = nil
		if r.Player then
			local character = r.Player.Character
			root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not r.Player.Parent then
				r.Finished = true
			end
		elseif r.Rival then
			root = r.Rival.C.Root
		end
		if root and not r.Finished then
			local d, lateral = Route.Project(root.Position)
			r.Dist = d
			local cp = Layout.Checkpoints[r.Next]
			if cp and d >= cp.Dist - 2 and math.abs(lateral) < R.CheckpointRadius + 20 then
				passCheckpoint(r, r.Next)
			end
		end
		if r.Player and not r.Finished then
			humansLeft += 1
		end
		-- Rivals harass nearby racers.
		if r.Rival and not r.Finished and os.clock() - r.LastAttack > R.RivalAttackInterval then
			r.LastAttack = os.clock()
			local c = r.Rival.C :: Combatant
			local target = NPCBrain.FindTarget(c, R.RivalAttackRange)
			if target and target.Data.Racing and math.random() < R.RivalAttackChance then
				local brain = r.Rival.Brain
				brain.Target = target
				brain.NextMove = 0
				NPCBrain.TryMove(c, brain, target)
			end
		end
	end
	if humansLeft == 0 then
		endRace()
		return
	end
	local list = standings()
	local rows = {}
	for i, r in list do
		table.insert(rows, { Name = r.Name, UserId = r.UserId, Dist = math.floor(r.Dist), Place = i, Finished = r.Finished, Rival = r.Player == nil })
	end
	broadcast("Standings", { Rows = rows, Elapsed = elapsed(), Length = Layout.FinishDist, Start = Layout.StartDist })
end

local function join(player: Player)
	if state ~= "Idle" and state ~= "Lobby" then
		Net.Toast(player, "A race is underway. Join the next one.", "Bad")
		return
	end
	if lobby[player] then
		return
	end
	lobby[player] = true
	if state == "Idle" then
		state = "Lobby"
		lobbyEndsAt = os.clock() + R.LobbyCountdown
	end
	local count = 0
	for _ in lobby do
		count += 1
	end
	lobbyBroadcast("Lobby", { Count = count, EndsIn = math.max(0, lobbyEndsAt - os.clock()) })
	Net.Toast(player, "You joined the race. Head to the start line.", "Good")
end

local function leave(player: Player)
	if lobby[player] then
		lobby[player] = nil
		raceEvent:FireClient(player, "Left", {})
	end
	local r = racerFor(player)
	if r and not r.Finished then
		r.Finished = true
		r.FinishTime = nil
		raceEvent:FireClient(player, "Left", {})
		local c = Combatants.ForPlayer(player)
		if c then
			c.Data.Racing = nil
		end
	end
end

function RaceService.Init()
	raceEvent = Remotes.Event("Race")
	Net.OnRequest("JoinRace", function(player: Player)
		join(player)
		return Net.Ok()
	end)
	Net.OnRequest("LeaveRace", function(player: Player)
		leave(player)
		return Net.Ok()
	end)
	Net.OnRequest("RaceState", function(player: Player)
		local count = 0
		for _ in lobby do
			count += 1
		end
		return Net.Ok({ State = state, InLobby = lobby[player] == true, Racing = racerFor(player) ~= nil, LobbyCount = count, EndsIn = math.max(0, lobbyEndsAt - os.clock()) })
	end)
	Players.PlayerRemoving:Connect(leave)

	-- Racers who die respawn at their last checkpoint.
	CharacterService.Hooks.SpawnOverride = function(player)
		local r = racerFor(player)
		if r and state == "Running" and not r.Finished and r.Next > 1 then
			local cp = Layout.Checkpoints[r.Next - 1]
			local p, t = Route.OffsetPoint(cp.Dist + 6, 0)
			local y = HeightField.Surface(p.X, p.Z)
			return CFrame.lookAt(Vector3.new(p.X, y, p.Z), Vector3.new(p.X, y, p.Z) + t)
		end
		return nil
	end
	Signals.CharacterReady:Connect(function(player)
		local r = racerFor(player)
		local c = Combatants.ForPlayer(player)
		if r and c and state == "Running" and not r.Finished then
			c.Data.Racing = true
		end
	end)
end

function RaceService.Start()
	-- "Join the race" prompt on the start line.
	for _, pad in CollectionService:GetTagged("SBR_StartSpawn") do
		if pad:IsA("BasePart") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Join the race"
			prompt.ObjectText = "Steel Ball Run"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
			prompt.MaxActivationDistance = 14
			prompt.RequiresLineOfSight = false
			prompt.Style = Enum.ProximityPromptStyle.Custom
			prompt.Parent = pad
			prompt.Triggered:Connect(join)
		end
	end
	task.spawn(function()
		while true do
			task.wait(R.ProgressInterval)
			if state == "Lobby" then
				local count = 0
				for player in lobby do
					if player.Parent then
						count += 1
					else
						lobby[player] = nil
					end
				end
				if count == 0 then
					state = "Idle"
				elseif os.clock() >= lobbyEndsAt and count >= R.MinPlayers then
					startRace()
				end
			elseif state == "Running" then
				tickRunning()
			end
		end
	end)
end

return RaceService
