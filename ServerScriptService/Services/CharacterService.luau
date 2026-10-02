--!strict
-- Spawns characters once the map is ready, places them at their last town,
-- applies level and stat bonuses, spawn protection, respawns, and tracks which
-- zone every player is standing in.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Zones = require(ReplicatedStorage.Shared.Zones)
local Progression = require(ReplicatedStorage.Shared.Progression)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Net)
local Signals = require(script.Parent.Signals)
local Combatants = require(script.Parent.Combatants)
local CombatService = require(script.Parent.CombatService)
local Hitbox = require(script.Parent.Hitbox)

local CharacterService = {}

local RESPAWN_DELAY = 5
local BASE_WALK = 16

CharacterService.Hooks = {
	-- Return a CFrame to override where a player respawns (races use this).
	SpawnOverride = nil :: ((Player) -> CFrame?)?,
}

local townSpawns: { [number]: CFrame } = {}
local startSpawn: CFrame? = nil
local lastZone: { [Player]: Zones.ZoneInfo } = {}
local spawning: { [Player]: boolean } = {}
local mapReady = false

local function collectSpawns()
	for _, part in CollectionService:GetTagged("SBR_TownSpawn") do
		if part:IsA("BasePart") then
			local index = part:GetAttribute("Town")
			if type(index) == "number" then
				townSpawns[index] = part.CFrame
			end
		end
	end
	for _, part in CollectionService:GetTagged("SBR_StartSpawn") do
		if part:IsA("BasePart") then
			startSpawn = part.CFrame
		end
	end
end

function CharacterService.TownSpawn(index: number): CFrame
	local cf = townSpawns[index]
	if cf then
		return cf
	end
	local town = Layout.Towns[index] or Layout.Towns[1]
	return CFrame.new(town.Spawn)
end

function CharacterService.SpawnCFrame(player: Player): CFrame
	local hook = CharacterService.Hooks.SpawnOverride
	if hook then
		local cf = hook(player)
		if cf then
			return cf
		end
	end
	local profile = DataService.Get(player)
	if profile and profile.LastTown > 1 then
		return CharacterService.TownSpawn(profile.LastTown)
	end
	return startSpawn or CharacterService.TownSpawn(1)
end

-- Applies level and stat bonuses to a live character.
function CharacterService.ApplyStats(player: Player)
	local profile = DataService.Get(player)
	local c = Combatants.ForPlayer(player)
	if not profile or not c then
		return
	end
	local h = c.Humanoid
	local ratio = if h.MaxHealth > 0 then h.Health / h.MaxHealth else 1
	h.MaxHealth = Progression.MaxHealth(profile)
	h.Health = math.max(1, h.MaxHealth * ratio)
	c.BaseWalkSpeed = BASE_WALK * Progression.SpeedMult(profile)
	c.DamageMult = Progression.PowerMult(profile)
	c.StaminaMax = Progression.StaminaMax(profile)
	c.Level = profile.Level
	c.Model:SetAttribute("Level", profile.Level)
	Combatants.ApplyMovement(c)
end

local function onCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?
	if not humanoid or not root then
		return
	end
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local spawnCF = CharacterService.SpawnCFrame(player)
	character:PivotTo(spawnCF + Vector3.new(0, 3.5, 0))

	humanoid.MaxHealth = Progression.MaxHealth(profile)
	humanoid.Health = humanoid.MaxHealth
	humanoid.WalkSpeed = BASE_WALK * Progression.SpeedMult(profile)
	humanoid.BreakJointsOnDeath = false

	local c = Combatants.Register(character, {
		Player = player,
		Name = player.DisplayName,
		Level = profile.Level,
		DamageMult = Progression.PowerMult(profile),
		StaminaMax = Progression.StaminaMax(profile),
	})
	if not c then
		return
	end
	c.BaseWalkSpeed = humanoid.WalkSpeed
	character:SetAttribute("Level", profile.Level)
	CombatService.Track(c)

	local ff = Instance.new("ForceField")
	ff.Visible = true
	ff.Parent = character
	c.ProtectedUntil = os.clock() + Config.World.SafeSpawnSeconds
	task.delay(Config.World.SafeSpawnSeconds, function()
		if ff.Parent then
			ff:Destroy()
		end
	end)

	lastZone[player] = nil
	Signals.CharacterReady:Fire(player, character)

	humanoid.Died:Connect(function()
		local killerName: string? = nil
		if c.LastAttacker and os.clock() - c.LastAttackTime < 15 then
			killerName = c.LastAttacker.Name
		end
		Net.Notify(player, "Died", { Killer = killerName, Respawn = RESPAWN_DELAY })
		task.delay(RESPAWN_DELAY, function()
			if player.Parent and player.Character == character then
				CharacterService.Load(player)
			end
		end)
	end)
end

function CharacterService.Load(player: Player)
	if spawning[player] then
		return
	end
	spawning[player] = true
	local cf = CharacterService.SpawnCFrame(player)
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 8)
	end)
	if player.Parent then
		player:LoadCharacterAsync()
	end
	spawning[player] = nil
end

-- Moves a live character to a town (used by fast travel and race resets).
function CharacterService.Teleport(player: Player, cf: CFrame)
	local character = player.Character
	if not character then
		return
	end
	pcall(function()
		player:RequestStreamAroundAsync(cf.Position, 5)
	end)
	character:PivotTo(cf + Vector3.new(0, 3.5, 0))
end

local function updateZones()
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if character and root then
			local info = Zones.Classify(root.Position)
			Hitbox.SetSafe(character, info.Safe)
			local prev = lastZone[player]
			if not prev or prev.Kind ~= info.Kind or prev.Name ~= info.Name then
				lastZone[player] = info
				character:SetAttribute("Zone", info.Name)
				character:SetAttribute("ZoneKind", info.Kind)
				character:SetAttribute("Safe", info.Safe)
				Net.Notify(player, "Zone", { Kind = info.Kind, Name = info.Name, Safe = info.Safe, Level = info.Level, Stage = info.Stage })
				if info.Town then
					local profile = DataService.Get(player)
					if profile and profile.LastTown ~= info.Town.Index then
						profile.LastTown = info.Town.Index
						DataService.MarkDirty(player)
						if prev then
							Net.Toast(player, "Respawn point set to " .. info.Town.Name .. ".", "Info")
						end
					end
				end
				Signals.ZoneChanged:Fire(player, info, prev)
			end
		end
	end
end

function CharacterService.Zone(player: Player): Zones.ZoneInfo?
	return lastZone[player]
end

function CharacterService.Init()
	Signals.LevelUp:Connect(function(player)
		CharacterService.ApplyStats(player)
	end)
	Signals.StatsChanged:Connect(function(player)
		CharacterService.ApplyStats(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		lastZone[player] = nil
		spawning[player] = nil
	end)
end

-- Called by Main once the map exists.
function CharacterService.Start()
	mapReady = true
	collectSpawns()
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end
	for _, player in Players:GetPlayers() do
		hook(player)
	end
	Players.PlayerAdded:Connect(hook)
	DataService.OnLoaded(function(player)
		if mapReady and not player.Character then
			CharacterService.Load(player)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.5)
			updateZones()
		end
	end)
end

return CharacterService
