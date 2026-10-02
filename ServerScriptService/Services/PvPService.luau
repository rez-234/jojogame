--!strict
-- Player versus player: the open world toggle, safe zones and spawn
-- protection, the ranked 1v1 arena queue with Elo ratings, the kill feed and
-- the global ranked leaderboard.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Layout = require(ReplicatedStorage.Shared.Layout)
local HeightField = require(ReplicatedStorage.Shared.HeightField)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Net)
local Signals = require(script.Parent.Signals)
local Combatants = require(script.Parent.Combatants)
local Hitbox = require(script.Parent.Hitbox)
local HorseService = require(script.Parent.HorseService)
local CharacterService = require(script.Parent.CharacterService)
local LevelService = require(script.Parent.LevelService)

type Combatant = Combatants.Combatant

local PvPService = {}

type Match = {
	Id: number,
	A: Player,
	B: Player,
	Live: boolean,
	StartedAt: number,
	Over: boolean,
}

local queue: { Player } = {}
local matches: { [Player]: Match } = {}
local nextMatchId = 0
local pads: { [number]: CFrame } = {}
local leaderboard: { { Name: string, Ranked: number } } = {}
local rankedStore: OrderedDataStore? = nil
local nameCache: { [number]: string } = {}

local function profileOf(c: Combatant): any
	return if c.Player then DataService.Get(c.Player) else nil
end

-- Damage rule between two players.
local function canFight(a: Combatant, b: Combatant): boolean
	local pa, pb = a.Player, b.Player
	if not pa or not pb then
		return false
	end
	local ma, mb = matches[pa], matches[pb]
	if ma and ma == mb then
		return ma.Live
	end
	if ma or mb then
		return false
	end
	local now = os.clock()
	if now < a.ProtectedUntil or now < b.ProtectedUntil then
		return false
	end
	if Hitbox.IsSafe(a) or Hitbox.IsSafe(b) then
		return false
	end
	local profA, profB = profileOf(a), profileOf(b)
	return profA ~= nil and profB ~= nil and profA.PvPEnabled == true and profB.PvPEnabled == true
end

local function onToggle(player: Player)
	local profile = DataService.Get(player)
	local c = Combatants.ForPlayer(player)
	if not profile or not c then
		return
	end
	if Combatants.Cooldown(c, "PvPToggle") > 0 then
		Net.Toast(player, "Wait a moment before switching again.", "Bad")
		return
	end
	if profile.PvPEnabled and os.clock() - (c.Data.LastCombat or 0) < 10 then
		Net.Toast(player, "You cannot turn PvP off in the middle of a fight.", "Bad")
		return
	end
	Combatants.SetCooldown(c, "PvPToggle", Config.PvP.ToggleCooldown)
	profile.PvPEnabled = not profile.PvPEnabled
	c.Model:SetAttribute("PvP", profile.PvPEnabled)
	DataService.MarkDirty(player)
	Net.Toast(player, if profile.PvPEnabled then "PvP on. Other duelists can fight you outside towns." else "PvP off.", if profile.PvPEnabled then "Bad" else "Info")
end

-- Arena -------------------------------------------------------------------------

local function inQueue(player: Player): boolean
	return table.find(queue, player) ~= nil
end

local function leaveQueue(player: Player)
	local i = table.find(queue, player)
	if i then
		table.remove(queue, i)
	end
end

local function arenaCenter(): Vector3
	local c = Layout.PvPArena.Center
	return Vector3.new(c.X, HeightField.Surface(c.X, c.Z) + 2, c.Z)
end

local function placeAt(player: Player, slot: number)
	local cf = pads[slot] or CFrame.new(arenaCenter())
	if HorseService.IsMounted(player) then
		HorseService.Dismount(player, false)
	end
	CharacterService.Teleport(player, cf)
end

local function endMatch(match: Match, winner: Player?, reason: string)
	if match.Over then
		return
	end
	match.Over = true
	match.Live = false
	matches[match.A] = nil
	matches[match.B] = nil
	local loser: Player? = nil
	if winner then
		loser = if winner == match.A then match.B else match.A
	end
	if winner and loser then
		local wp = DataService.Get(winner)
		local lp = DataService.Get(loser)
		local delta = 0
		if wp and lp then
			delta = Progression.RankedDelta(wp.Ranked, lp.Ranked)
			wp.Ranked += delta
			lp.Ranked = math.max(0, lp.Ranked - delta)
			wp.ArenaWins += 1
			lp.ArenaLosses += 1
			DataService.MarkDirty(winner)
			DataService.MarkDirty(loser)
		end
		DataService.AddCounter(winner, "PvPWins", 1)
		LevelService.AddXP(winner, Config.XP.ArenaWin, "Arena win")
		if loser.Parent then
			LevelService.AddXP(loser, Config.XP.ArenaLoss, "Arena match")
		end
		Signals.Quest:Fire(winner, "ArenaWin", 1)
		Net.Notify(winner, "ArenaEnd", { Won = true, Delta = delta, Ranked = if wp then wp.Ranked else 0, Reason = reason })
		if loser.Parent then
			Net.Notify(loser, "ArenaEnd", { Won = false, Delta = -delta, Ranked = if lp then lp.Ranked else 0, Reason = reason })
		end
	else
		for _, p in { match.A, match.B } do
			if p.Parent then
				Net.Notify(p, "ArenaEnd", { Won = false, Draw = true, Delta = 0, Reason = reason })
			end
		end
	end
	-- Send survivors back to town after a moment.
	task.delay(3, function()
		for _, p in { match.A, match.B } do
			local c = Combatants.ForPlayer(p)
			if p.Parent and c and Combatants.IsAlive(c) then
				c.Humanoid.Health = c.Humanoid.MaxHealth
				CharacterService.Teleport(p, CharacterService.SpawnCFrame(p))
			end
		end
	end)
end

local function startMatch(a: Player, b: Player)
	nextMatchId += 1
	local match: Match = { Id = nextMatchId, A = a, B = b, Live = false, StartedAt = 0, Over = false }
	matches[a] = match
	matches[b] = match
	leaveQueue(a)
	leaveQueue(b)
	for slot, p in { a, b } do
		local c = Combatants.ForPlayer(p)
		if c then
			c.Humanoid.Health = c.Humanoid.MaxHealth
			c.Stamina = c.StaminaMax
			c.StandDurability = c.StandMaxDurability
			c.Cooldowns = {}
			c.Effects = {}
		end
		placeAt(p, slot)
		local other = if p == a then b else a
		local op = DataService.Get(other)
		Net.Notify(p, "ArenaStart", { Opponent = other.DisplayName, Ranked = if op then op.Ranked else 0, Countdown = Config.PvP.ArenaCountdown })
		if c then
			c.StunUntil = os.clock() + Config.PvP.ArenaCountdown
			Combatants.ApplyMovement(c)
		end
	end
	task.delay(Config.PvP.ArenaCountdown, function()
		if match.Over then
			return
		end
		match.Live = true
		match.StartedAt = os.clock()
		for _, p in { a, b } do
			Net.Notify(p, "ArenaGo", { Time = Config.PvP.ArenaMaxTime })
		end
	end)
end

local function matchmake()
	for i = #queue, 1, -1 do
		local p = queue[i]
		local c = Combatants.ForPlayer(p)
		if not p.Parent or not c or not Combatants.IsAlive(c) or matches[p] then
			table.remove(queue, i)
		end
	end
	while #queue >= 2 do
		-- Pair the two closest ratings.
		table.sort(queue, function(x, y)
			local px, py = DataService.Get(x), DataService.Get(y)
			return (if px then px.Ranked else 0) < (if py then py.Ranked else 0)
		end)
		local bestI, bestGap = 1, math.huge
		for i = 1, #queue - 1 do
			local p1, p2 = DataService.Get(queue[i]), DataService.Get(queue[i + 1])
			local gap = math.abs((if p1 then p1.Ranked else 0) - (if p2 then p2.Ranked else 0))
			if gap < bestGap then
				bestGap = gap
				bestI = i
			end
		end
		startMatch(queue[bestI], queue[bestI + 1])
	end
	-- Time limits.
	local seen: { [Match]: boolean } = {}
	for _, match in matches do
		if not seen[match] then
			seen[match] = true
			if match.Live and os.clock() - match.StartedAt > Config.PvP.ArenaMaxTime then
				local ca, cb = Combatants.ForPlayer(match.A), Combatants.ForPlayer(match.B)
				local fa = if ca then ca.Humanoid.Health / ca.Humanoid.MaxHealth else 0
				local fb = if cb then cb.Humanoid.Health / cb.Humanoid.MaxHealth else 0
				if math.abs(fa - fb) < 0.02 then
					endMatch(match, nil, "Time")
				else
					endMatch(match, if fa > fb then match.A else match.B, "Time")
				end
			end
		end
	end
end

-- Kill feed and PvP kill rewards ------------------------------------------------------

local function onKilled(killer: Combatant?, victim: Combatant)
	if victim.Player or victim.IsBoss then
		Net.NotifyAll("KillFeed", {
			Killer = if killer then killer.Name else nil,
			Victim = victim.Name,
			Move = victim.LastHitMove,
		})
	end
	local vp = victim.Player
	if vp then
		local match = matches[vp]
		if match and not match.Over then
			endMatch(match, if match.A == vp then match.B else match.A, "Knockout")
			return
		end
	end
	if killer and killer.Player and vp and killer.Player ~= vp then
		LevelService.AddXP(killer.Player, Config.XP.PvPKill, "Defeated " .. victim.Name)
		DataService.AddCounter(killer.Player, "PvPKills", 1)
		Signals.Quest:Fire(killer.Player, "PvPKill", 1)
	end
end

-- Leaderboard -------------------------------------------------------------------------

local function nameFor(userId: number): string
	local cached = nameCache[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = if ok and type(name) == "string" then name else ("Rider " .. userId)
	nameCache[userId] = result
	return result
end

local function pushRanked(player: Player)
	local profile = DataService.Get(player)
	local ds = rankedStore
	if not profile or not ds then
		return
	end
	pcall(function()
		ds:SetAsync(tostring(player.UserId), profile.Ranked)
	end)
end

local function refreshLeaderboard()
	local ds = rankedStore
	if not ds then
		return
	end
	local ok, pages = pcall(function()
		return ds:GetSortedAsync(false, 10)
	end)
	if not ok or not pages then
		return
	end
	local list = {}
	for _, entry in (pages :: DataStorePages):GetCurrentPage() do
		local userId = tonumber(entry.key)
		if userId then
			table.insert(list, { Name = nameFor(userId), Ranked = entry.value })
		end
	end
	leaderboard = list
end

function PvPService.Init()
	Hitbox.SetPlayerRule(canFight)
	Net.OnAction("PvPToggle", onToggle)
	Net.OnRequest("QueueArena", function(player: Player)
		local profile = DataService.Get(player)
		if not profile then
			return Net.Fail("Profile not loaded")
		end
		if not Progression.IsUnlocked(profile.Level, "PvPArena") then
			return Net.Fail("The arena opens at level " .. Progression.UnlockLevel("PvPArena"))
		end
		if matches[player] then
			return Net.Fail("You are already in a match")
		end
		if inQueue(player) then
			leaveQueue(player)
			return Net.Ok({ Queued = false })
		end
		table.insert(queue, player)
		return Net.Ok({ Queued = true, Count = #queue })
	end)
	Net.OnRequest("Leaderboard", function(_player: Player)
		local server = {}
		for _, p in Players:GetPlayers() do
			local profile = DataService.Get(p)
			if profile then
				table.insert(server, { Name = p.DisplayName, Ranked = profile.Ranked, Level = profile.Level, Wins = profile.ArenaWins })
			end
		end
		table.sort(server, function(a, b)
			return a.Ranked > b.Ranked
		end)
		return Net.Ok({ Global = leaderboard, Server = server })
	end)
	Signals.Killed:Connect(onKilled)
	Signals.CharacterReady:Connect(function(player, character)
		local profile = DataService.Get(player)
		if profile then
			character:SetAttribute("PvP", profile.PvPEnabled)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		leaveQueue(player)
		local match = matches[player]
		if match and not match.Over then
			endMatch(match, if match.A == player then match.B else match.A, "Forfeit")
		end
		pushRanked(player)
	end)
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.Data.RankedStoreName)
	end)
	if ok then
		rankedStore = store
	end
end

function PvPService.Start()
	for _, pad in CollectionService:GetTagged("SBR_ArenaPad") do
		if pad:IsA("BasePart") then
			local slot = pad:GetAttribute("Slot")
			if type(slot) == "number" then
				local center = arenaCenter()
				local p = pad.Position + Vector3.new(0, 1, 0)
				pads[slot] = CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z))
			end
		end
	end
	task.spawn(function()
		while true do
			task.wait(2)
			matchmake()
		end
	end)
	task.spawn(function()
		while true do
			refreshLeaderboard()
			task.wait(Config.PvP.LeaderboardRefresh)
			for _, p in Players:GetPlayers() do
				task.spawn(pushRanked, p)
			end
		end
	end)
end

return PvPService
