--!strict
-- Player profiles with DataStoreService: retries with backoff, session locking
-- through UpdateAsync, autosave and release on leave and shutdown. Falls back to
-- in-memory profiles (with a warning) when DataStores are unavailable, such as
-- in a Studio place without API access.

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Types = require(ReplicatedStorage.Shared.Types)
local HorseData = require(ReplicatedStorage.Shared.HorseData)
local Net = require(script.Parent.Net)

local DataService = {}

local VERSION = 1

local profiles: { [Player]: Types.Profile } = {}
local dirty: { [Player]: boolean } = {}
local loadedEvent = Instance.new("BindableEvent")
local store: DataStore? = nil
local memoryMode = false

function DataService.Template(): Types.Profile
	return {
		Version = VERSION,
		Level = 1,
		XP = 0,
		StatPoints = 0,
		Stats = { Health = 0, Power = 0, Speed = 0, Stamina = 0 },
		Cash = Config.Data.StartCash,
		Items = { Arrow = 1, Bandage = 3, Feed = 1 },
		Stand = nil,
		StandStorage = {},
		Mastery = {},
		Skins = { Owned = {}, Equipped = {} },
		Counters = {
			NPCKills = 0,
			PvPKills = 0,
			PvPWins = 0,
			BossKills = 0,
			StagesFinished = 0,
			RacesWon = 0,
			Distance = 0,
			Tamed = 0,
			QuestsCompleted = 0,
		},
		Ranked = Config.PvP.RankedStart,
		ArenaWins = 0,
		ArenaLosses = 0,
		PvPEnabled = false,
		Horses = {
			{
				Id = "h1",
				Breed = "Mustang",
				Name = HorseData.Names[1],
				Level = 1,
				XP = 0,
				Health = -1,
				Coat = 1,
				ManeColor = 1,
				Pattern = "Socks",
				Cosmetics = { Saddle = "Brown", Blanket = "Red", Mane = "Classic", Shoes = "Iron" },
			},
		},
		EquippedHorse = "h1",
		NextHorseId = 2,
		HorseCosmetics = { ["Saddle:Brown"] = true, ["Blanket:Red"] = true, ["Mane:Classic"] = true, ["Shoes:Iron"] = true },
		Race = { BestTotal = nil, BestStages = {}, Wins = 0, Finishes = 0 },
		Quests = { Day = 0, Daily = {}, Board = {} },
		LastTown = 1,
		Unlocked = {},
	}
end

local function keyFor(player: Player): string
	return "u_" .. player.UserId
end

-- Calls fn with exponential backoff until it succeeds or retries run out.
local function retry<T>(label: string, fn: () -> T): (boolean, T?)
	local delay = Config.Data.RetryBaseDelay
	for attempt = 1, Config.Data.MaxRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		warn(string.format("[DataService] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		if attempt < Config.Data.MaxRetries then
			task.wait(delay)
			delay *= 2
		end
	end
	return false, nil
end

type Stored = {
	Data: Types.Profile?,
	Lock: { Job: string, Time: number }?,
}

-- Loads and locks the profile. Returns nil if it could not be loaded safely.
local function loadProfile(player: Player): Types.Profile?
	if memoryMode or not store then
		return DataService.Template()
	end
	local ds = store :: DataStore
	local key = keyFor(player)
	for attempt = 1, Config.Data.LockRetryAttempts do
		local lockedBy: { Job: string, Time: number }? = nil
		local loaded: Types.Profile? = nil
		local ok = retry("load " .. key, function()
			lockedBy = nil
			ds:UpdateAsync(key, function(old: Stored?): Stored?
				local now = os.time()
				if old and old.Lock and old.Lock.Job ~= game.JobId then
					local age = now - old.Lock.Time
					local stale = age > Config.Data.LockTimeout
					local giveUp = attempt == Config.Data.LockRetryAttempts and age > Config.Data.AutosaveInterval * 2
					if not stale and not giveUp then
						lockedBy = old.Lock
						return nil
					end
				end
				local record: Stored = old or { Data = nil, Lock = nil }
				record.Lock = { Job = game.JobId, Time = now }
				loaded = record.Data
				return record
			end)
			return true
		end)
		if not ok then
			return nil
		end
		if lockedBy == nil then
			local profile = loaded or DataService.Template()
			Util.reconcile(profile :: any, DataService.Template() :: any)
			profile.Version = VERSION
			return profile
		end
		if not player.Parent then
			return nil
		end
		task.wait(Config.Data.LockRetryDelay)
	end
	return nil
end

local function saveProfile(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if not profile or memoryMode or not store then
		return true
	end
	local ds = store :: DataStore
	local key = keyFor(player)
	local snapshot = Util.deepCopy(profile)
	local ok = retry("save " .. key, function()
		ds:UpdateAsync(key, function(old: Stored?): Stored?
			-- Never overwrite a profile another server has taken over.
			if old and old.Lock and old.Lock.Job ~= game.JobId then
				warn("[DataService] lock lost for", key, "- skipping save")
				return nil
			end
			return {
				Data = snapshot,
				Lock = if release then nil else { Job = game.JobId, Time = os.time() },
			}
		end)
		return true
	end)
	return ok
end

function DataService.Get(player: Player): Types.Profile?
	return profiles[player]
end

-- Yields until the player's profile loads or they leave.
function DataService.WaitFor(player: Player): Types.Profile?
	while player.Parent and not profiles[player] do
		task.wait(0.1)
	end
	return profiles[player]
end

function DataService.OnLoaded(callback: (Player, Types.Profile) -> ())
	loadedEvent.Event:Connect(callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile)
	end
end

-- Queues a sync of the profile to the client.
function DataService.MarkDirty(player: Player)
	dirty[player] = true
end

local function updateLeaderstats(player: Player, profile: Types.Profile)
	local stats = player:FindFirstChild("leaderstats")
	if not stats then
		local folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
		stats = folder
	end
	local function value(name: string, v: number)
		local existing = (stats :: Instance):FindFirstChild(name) :: IntValue?
		if not existing then
			local iv = Instance.new("IntValue")
			iv.Name = name
			iv.Parent = stats
			existing = iv
		end
		(existing :: IntValue).Value = v
	end
	value("Level", profile.Level)
	value("Ranked", profile.Ranked)
end

local function flush(player: Player)
	local profile = profiles[player]
	if not profile then
		return
	end
	dirty[player] = nil
	Net.Sync(player, profile)
	updateLeaderstats(player, profile)
end

function DataService.FlushNow(player: Player)
	flush(player)
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)
	if not player.Parent then
		if profile then
			profiles[player] = profile
			saveProfile(player, true)
			profiles[player] = nil
		end
		return
	end
	if not profile then
		player:Kick("Your save is still open on another server or could not be loaded. Please rejoin in a minute.")
		return
	end
	profiles[player] = profile
	flush(player)
	loadedEvent:Fire(player, profile)
end

function DataService.Init()
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok and result then
		store = result
		-- A quick read tells us whether API access is enabled.
		local readOk = pcall(function()
			(store :: DataStore):GetAsync("__probe")
		end)
		if not readOk then
			memoryMode = true
		end
	else
		memoryMode = true
	end
	if memoryMode then
		warn("[DataService] DataStores unavailable, using in-memory profiles. Progress will not be saved.")
	end
	ReplicatedStorage:SetAttribute("SavesEnabled", not memoryMode)
end

function DataService.Start()
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		if profiles[player] then
			saveProfile(player, true)
			profiles[player] = nil
			dirty[player] = nil
		end
	end)

	-- Sync dirty profiles twice a second at most.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for player in dirty do
				flush(player)
			end
		end
	end)

	-- Autosave.
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player in profiles do
				task.spawn(saveProfile, player, false)
			end
		end
	end)

	game:BindToClose(function()
		if RunService:IsStudio() and memoryMode then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveProfile(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- Helpers used across services.
function DataService.AddCash(player: Player, amount: number)
	local profile = profiles[player]
	if profile then
		profile.Cash = math.max(0, profile.Cash + math.floor(amount))
		DataService.MarkDirty(player)
	end
end

function DataService.SpendCash(player: Player, amount: number): boolean
	local profile = profiles[player]
	if not profile or profile.Cash < amount then
		return false
	end
	profile.Cash -= amount
	DataService.MarkDirty(player)
	return true
end

function DataService.AddItem(player: Player, item: string, amount: number)
	local profile = profiles[player]
	if profile then
		profile.Items[item] = math.max(0, (profile.Items[item] or 0) + amount)
		DataService.MarkDirty(player)
	end
end

function DataService.TakeItem(player: Player, item: string, amount: number): boolean
	local profile = profiles[player]
	if not profile or (profile.Items[item] or 0) < amount then
		return false
	end
	profile.Items[item] -= amount
	DataService.MarkDirty(player)
	return true
end

function DataService.AddCounter(player: Player, counter: string, amount: number)
	local profile = profiles[player]
	if profile then
		profile.Counters[counter] = (profile.Counters[counter] or 0) + amount
		DataService.MarkDirty(player)
	end
end

return DataService
