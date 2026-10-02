--!strict
-- All NPCs: enemies that populate each PvE zone while players are near,
-- bandit ambushes on horseback, a boss with phases in every stage arena,
-- and the townsfolk who run shops, stables and quest boards. Also pays out
-- kill rewards and loot.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Route = require(ReplicatedStorage.Shared.Route)
local Layout = require(ReplicatedStorage.Shared.Layout)
local HeightField = require(ReplicatedStorage.Shared.HeightField)
local NPCData = require(ReplicatedStorage.Shared.NPCData)
local StandData = require(ReplicatedStorage.Shared.StandData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local RigBuilder = require(ReplicatedStorage.Builders.RigBuilder)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Net)
local Signals = require(script.Parent.Signals)
local Combatants = require(script.Parent.Combatants)
local Hitbox = require(script.Parent.Hitbox)
local CombatService = require(script.Parent.CombatService)
local StandService = require(script.Parent.StandService)
local HorseService = require(script.Parent.HorseService)
local LevelService = require(script.Parent.LevelService)
local SkinService = require(script.Parent.SkinService)
local NPCBrain = require(script.Parent.NPCBrain)

type Combatant = Combatants.Combatant

local NPCService = {}

local npcFolder: Folder
local townsFolder: Folder

-- Live NPCs that think every tick.
type Live = {
	C: Combatant,
	Brain: NPCBrain.Brain,
	Kind: string, -- "Enemy", "Rider", "Boss", "Add"
	Archetype: NPCData.Archetype?,
	Zone: number?,
	Horse: HorseService.ServerHorse?,
	Expires: number?,
}
local live: { [Combatant]: Live } = {}

type ZoneState = {
	Zone: Layout.Zone,
	Active: boolean,
	LastNear: number,
	Count: number,
	NextSpawn: number,
}
local zoneStates: { ZoneState } = {}

type BossState = {
	Arena: Layout.Arena,
	Data: NPCData.Boss,
	Spawn: Vector3,
	C: Combatant?,
	RespawnAt: number,
	Phase: number,
	Adds: { Combatant },
	LastPlayers: number,
}
local bosses: { BossState } = {}

local function groundAt(x: number, z: number): Vector3
	local hit = Hitbox.GroundBelow(Vector3.new(x, HeightField.Surface(x, z) + 30, z), 120)
	if hit then
		return hit
	end
	return Vector3.new(x, HeightField.Surface(x, z), z)
end

local function serverOwn(model: Model)
	local root = model.PrimaryPart
	if root and not root.Anchored then
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
end

local function levelMult(level: number): number
	return 1 + level * Config.NPC.DamagePerLevel
end

-- Spawns a foot NPC from an archetype at a position.
local function spawnEnemy(arch: NPCData.Archetype, level: number, at: Vector3, kind: string): Live?
	local rng = Random.new()
	local outfit = arch.Outfits[rng:NextInteger(1, #arch.Outfits)]
	local health = arch.Health + level * Config.NPC.HealthPerLevel
	local model = RigBuilder.Build({
		Name = arch.Name,
		Outfit = outfit,
		Health = health,
		WalkSpeed = arch.WalkSpeed,
		DisplayName = arch.Name .. "  Lv " .. level,
	})
	model:PivotTo(CFrame.new(at + Vector3.new(0, 3, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0))
	model:SetAttribute("Level", level)
	model:SetAttribute("Archetype", arch.Id)
	model.Parent = npcFolder
	serverOwn(model)
	local c = Combatants.Register(model, { Name = arch.Name, Level = level, DamageMult = levelMult(level) })
	if not c then
		model:Destroy()
		return nil
	end
	CombatService.Track(c)
	local moves = table.clone(arch.Moves)
	if arch.RandomStand then
		local standId = NPCData.EnemyStands[rng:NextInteger(1, #NPCData.EnemyStands)]
		StandService.Setup(c, standId)
		local s = StandData.Get(standId)
		if s then
			moves = table.clone(s.Moves)
			model:SetAttribute("StandName", s.Name)
		end
		StandService.Summon(c)
	elseif arch.Stand then
		StandService.Setup(c, arch.Stand)
		StandService.Summon(c)
	end
	local brain = NPCBrain.new(at, moves, arch.Ranged == true, arch.Damage * levelMult(level))
	c.Data.Brain = brain
	local entry: Live = { C = c, Brain = brain, Kind = kind, Archetype = arch }
	live[c] = entry
	return entry
end

-- A mounted NPC: a rig welded into the saddle of a server driven horse.
export type RiderOptions = {
	Name: string,
	Outfit: NPCData.Outfit,
	Health: number,
	Level: number,
	Breed: string,
	At: CFrame,
	Moves: { string },
	Stand: string?,
	Control: (Live, HorseService.ServerHorse, number) -> any,
	Passive: boolean?,
}

function NPCService.SpawnRider(opts: RiderOptions): Live?
	local rig = RigBuilder.Build({ Name = opts.Name, Outfit = opts.Outfit, Health = opts.Health, WalkSpeed = 16, DisplayName = opts.Name })
	local entryRef: { Live? } = { nil }
	local sh = HorseService.SpawnServerHorse({ Breed = opts.Breed, NoSeat = true, Seed = math.random(1, 1e6), Name = opts.Name .. "'s horse" }, opts.At, function(sh, dt)
		local e = entryRef[1]
		if not e then
			return nil
		end
		return opts.Control(e, sh, dt)
	end)
	local horse = sh.Model
	local torso = horse:FindFirstChild("Torso") :: BasePart
	local riderAtt = torso:FindFirstChild("RiderAttachment") :: Attachment
	local hrp = rig:FindFirstChild("HumanoidRootPart") :: BasePart
	for _, d in rig:GetDescendants() do
		if d:IsA("BasePart") then
			d.Massless = true
			d.CanCollide = false
			d.Anchored = false
		end
	end
	rig:PivotTo(riderAtt.WorldCFrame * CFrame.new(0, 2.1, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso
	weld.Part1 = hrp
	weld.Parent = hrp
	local humanoid = rig:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.PlatformStand = true
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
	rig:SetAttribute("Mounted", true)
	rig:SetAttribute("Level", opts.Level)
	rig.Parent = npcFolder
	local c = Combatants.Register(rig, { Name = opts.Name, Level = opts.Level, DamageMult = levelMult(opts.Level) })
	if not c then
		rig:Destroy()
		horse:Destroy()
		return nil
	end
	c.Mounted = horse
	c.Data.Passive = opts.Passive
	CombatService.Track(c)
	if opts.Stand then
		StandService.Setup(c, opts.Stand)
		StandService.Summon(c)
	end
	local brain = NPCBrain.new(opts.At.Position, opts.Moves, true, 6 * levelMult(opts.Level))
	brain.LeashRange = math.huge
	brain.AggroRange = 90
	c.Data.Brain = brain
	local entry: Live = { C = c, Brain = brain, Kind = "Rider", Horse = sh }
	entryRef[1] = entry
	live[c] = entry
	-- Horse goes when the rider goes.
	rig.AncestryChanged:Connect(function(_, parent)
		if parent == nil and horse.Parent then
			task.delay(2, function()
				horse:Destroy()
			end)
		end
	end)
	return entry
end

function NPCService.Remove(entry: Live)
	live[entry.C] = nil
	if entry.Horse then
		entry.Horse.Model:Destroy()
	end
	entry.C.Model:Destroy()
end

-- Zones ------------------------------------------------------------------------

local function pickArchetype(stage: number, rng: Random): NPCData.Archetype?
	local options = {}
	for _, arch in NPCData.Archetypes do
		if arch.MinStage <= stage and not arch.Mounted then
			table.insert(options, arch)
		end
	end
	table.sort(options, function(a, b)
		return a.Id < b.Id
	end)
	return Util.weightedPick(rng, options, function(a)
		return a.Weight
	end)
end

local function spawnInZone(index: number, state: ZoneState)
	local zone = state.Zone
	local rng = Random.new()
	for _ = 1, 6 do
		local d = rng:NextNumber(zone.Dist0 + 20, zone.Dist1 - 20)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		local p = Route.OffsetPoint(d, side * rng:NextNumber(26, 170))
		if not HeightField.WaterLevel(p.X, p.Z) and HeightField.Slope(p.X, p.Z) < 30 then
			local arch = pickArchetype(zone.Stage, rng)
			if arch then
				local level = zone.Level + rng:NextInteger(0, 2)
				local entry = spawnEnemy(arch, level, groundAt(p.X, p.Z), "Enemy")
				if entry then
					entry.Zone = index
					state.Count += 1
				end
			end
			return
		end
	end
end

local function playerNearZone(zone: Layout.Zone): boolean
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d, lateral = Route.Project(root.Position)
			local margin = Config.NPC.ActivationRange * 0.5
			if d > zone.Dist0 - margin and d < zone.Dist1 + margin and math.abs(lateral) < Config.NPC.ActivationRange then
				return true
			end
		end
	end
	return false
end

local function updateZones()
	local now = os.clock()
	for index, state in zoneStates do
		if playerNearZone(state.Zone) then
			state.LastNear = now
			state.Active = true
			if state.Count < Config.NPC.MaxPerZone and now >= state.NextSpawn then
				spawnInZone(index, state)
				-- Fill quickly at first, then trickle in with respawns.
				state.NextSpawn = now + (if state.Count < Config.NPC.MaxPerZone then 0.5 else 0)
			end
		elseif state.Active and now - state.LastNear > 30 then
			state.Active = false
			for _, entry in table.clone(live) do
				if entry.Zone == index then
					NPCService.Remove(entry)
				end
			end
			state.Count = 0
		end
	end
end

-- Ambushes ---------------------------------------------------------------------

local nextAmbush: { [Player]: number } = {}

local function riderControl(entry: Live, sh: HorseService.ServerHorse, _dt: number)
	local brain = entry.Brain
	return NPCBrain.RiderControl(entry.C, brain, sh.Motor, function()
		local t = brain.Target
		local tSpeed = if t then t.Root.AssemblyLinearVelocity.Magnitude else 0
		return math.clamp(tSpeed * 1.12 + 6, sh.Motor.Stats.Trot, sh.Motor.Stats.Gallop)
	end)
end

local function spawnAmbush(player: Player, c: Combatant)
	local d = Route.Project(c.Root.Position)
	local zone = Layout.ZoneAtDist(d)
	if not zone then
		return
	end
	local arch = NPCData.Archetypes.BanditRider
	local rng = Random.new()
	local count = rng:NextInteger(2, 3)
	Net.Toast(player, "Riders on your tail.", "Bad")
	for k = 1, count do
		local behind = math.max(0, d - 90 - k * 12)
		local p, t = Route.OffsetPoint(behind, (k - 2) * 8)
		local ground = groundAt(p.X, p.Z)
		local level = zone.Level + rng:NextInteger(0, 2)
		local entry = NPCService.SpawnRider({
			Name = arch.Name,
			Outfit = arch.Outfits[rng:NextInteger(1, #arch.Outfits)],
			Health = arch.Health + level * Config.NPC.HealthPerLevel,
			Level = level,
			Breed = if rng:NextNumber() < 0.7 then "Mustang" else "QuarterHorse",
			At = CFrame.lookAt(ground, ground + t),
			Moves = arch.Moves,
			Control = riderControl,
		})
		if entry then
			entry.Archetype = arch
			entry.Brain.Target = c
			entry.Expires = os.clock() + 70
		end
	end
end

local function updateAmbushes()
	local now = os.clock()
	for _, player in Players:GetPlayers() do
		local c = Combatants.ForPlayer(player)
		if c and c.Mounted and Combatants.IsAlive(c) and not c.Data.Racing then
			local speed = c.Root.AssemblyLinearVelocity.Magnitude
			local zoneKind = c.Model:GetAttribute("ZoneKind")
			if speed > 35 and zoneKind == "Wild" then
				local due = nextAmbush[player]
				if not due then
					nextAmbush[player] = now + 25
				elseif now >= due then
					nextAmbush[player] = now + 45
					if math.random() < Config.NPC.AmbushChance then
						spawnAmbush(player, c)
					end
				end
			end
		end
	end
end

-- Bosses -----------------------------------------------------------------------

local function spawnBoss(state: BossState)
	local boss = state.Data
	local model = RigBuilder.Build({
		Name = boss.Name,
		Outfit = boss.Outfit,
		Health = boss.Health,
		WalkSpeed = boss.WalkSpeed,
		DisplayName = boss.Name,
	})
	-- Bosses stand a little taller than everyone else.
	model:ScaleTo(1.15)
	model:PivotTo(CFrame.new(state.Spawn + Vector3.new(0, 4, 0)))
	model:SetAttribute("Boss", true)
	model:SetAttribute("BossName", boss.Name)
	model:SetAttribute("BossStand", boss.StandName)
	model:SetAttribute("Level", boss.Level)
	model:SetAttribute("Phase", 1)
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	model.Parent = npcFolder
	serverOwn(model)
	local c = Combatants.Register(model, { Name = boss.Name, Level = boss.Level, DamageMult = levelMult(boss.Level), IsBoss = true })
	if not c then
		model:Destroy()
		return
	end
	CombatService.Track(c)
	if boss.Stand then
		StandService.Setup(c, boss.Stand)
		StandService.Summon(c)
	elseif boss.Look then
		StandService.Summon(c, { Look = boss.Look })
	end
	local phase = boss.Phases[1]
	local brain = NPCBrain.new(state.Spawn, table.clone(phase.Moves), false, boss.Damage * levelMult(boss.Level) * 0.6)
	brain.AggroRange = state.Arena.Radius + 10
	brain.LeashRange = state.Arena.Radius + 25
	brain.MoveCooldownMult = 1.1
	c.Data.Brain = brain
	live[c] = { C = c, Brain = brain, Kind = "Boss" }
	state.C = c
	state.Phase = 1
	state.Adds = {}
	state.LastPlayers = os.clock()
end

local function playersInArena(state: BossState): { Player }
	local list = {}
	for _, player in Players:GetPlayers() do
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (Vector3.new(root.Position.X, 0, root.Position.Z) - state.Arena.Center).Magnitude < state.Arena.Radius + 20 then
			table.insert(list, player)
		end
	end
	return list
end

local function bossLine(state: BossState, line: string)
	for _, player in playersInArena(state) do
		Net.Notify(player, "BossLine", { Name = state.Data.Name, Line = line })
	end
end

local function updateBosses()
	local now = os.clock()
	local unlock = Progression.UnlockLevel("BossArenas")
	for _, state in bosses do
		local players = playersInArena(state)
		-- Keep under-level players out.
		for _, player in players do
			local profile = DataService.Get(player)
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if profile and root and character and profile.Level < unlock then
				local out = Vector3.new(root.Position.X, 0, root.Position.Z) - state.Arena.Center
				if out.Magnitude < 1 then
					out = Vector3.new(1, 0, 0)
				end
				local dest = state.Arena.Center + out.Unit * (state.Arena.Radius + 30)
				character:PivotTo(CFrame.new(groundAt(dest.X, dest.Z) + Vector3.new(0, 4, 0)))
				Net.Toast(player, "Boss arenas open at level " .. unlock .. ".", "Bad")
			end
		end
		local c = state.C
		if c and Combatants.IsAlive(c) then
			if #players > 0 then
				state.LastPlayers = now
			elseif now - state.LastPlayers > 20 then
				-- Nobody left: reset the fight.
				c.Humanoid.Health = c.Humanoid.MaxHealth
				c.Contributors = {}
				if state.Phase ~= 1 then
					state.Phase = 1
					c.Model:SetAttribute("Phase", 1)
					local brain = c.Data.Brain :: NPCBrain.Brain
					brain.Moves = table.clone(state.Data.Phases[1].Moves)
					c.BaseWalkSpeed = state.Data.WalkSpeed
				end
				for _, add in state.Adds do
					if add.Model.Parent then
						add.Model:Destroy()
					end
				end
				state.Adds = {}
			end
			-- Phase changes.
			local fraction = c.Humanoid.Health / c.Humanoid.MaxHealth
			local nextPhase = state.Data.Phases[state.Phase + 1]
			if nextPhase and fraction <= nextPhase.HealthFraction then
				state.Phase += 1
				c.Model:SetAttribute("Phase", state.Phase)
				local brain = c.Data.Brain :: NPCBrain.Brain
				brain.Moves = table.clone(nextPhase.Moves)
				c.BaseWalkSpeed = state.Data.WalkSpeed * nextPhase.SpeedMult
				brain.MoveCooldownMult = 1.1 / nextPhase.SpeedMult
				bossLine(state, nextPhase.Line)
				Net.FX("BossPhase", { Model = c.Model, Phase = state.Phase })
				local arch = NPCData.Archetypes[state.Data.AddArchetype]
				if arch then
					for k = 1, nextPhase.SummonAdds do
						local a = k / math.max(1, nextPhase.SummonAdds) * math.pi * 2
						local p = state.Arena.Center + Vector3.new(math.cos(a), 0, math.sin(a)) * (state.Arena.Radius * 0.6)
						local add = spawnEnemy(arch, state.Data.Level - 4, groundAt(p.X, p.Z), "Add")
						if add then
							add.Brain.LeashRange = state.Arena.Radius + 25
							add.Brain.Home = state.Arena.Center
							table.insert(state.Adds, add.C)
						end
					end
				end
			end
		elseif c and not Combatants.IsAlive(c) then
			state.C = nil
		elseif not c and now >= state.RespawnAt then
			local eligible = false
			for _, player in players do
				local profile = DataService.Get(player)
				if profile and profile.Level >= unlock then
					eligible = true
				end
			end
			if eligible then
				spawnBoss(state)
				bossLine(state, state.Data.Phases[1].Line)
			end
		end
	end
end

-- Townsfolk ----------------------------------------------------------------------

local function townsperson(spot: BasePart, name: string, action: string, onTrigger: (Player) -> ())
	local rng = Random.new(math.floor(spot.Position.X * 7 + spot.Position.Z))
	local outfit = NPCData.TownsfolkOutfits[rng:NextInteger(1, #NPCData.TownsfolkOutfits)]
	local model = RigBuilder.Build({ Name = name, Outfit = outfit, Health = 100, WalkSpeed = 0, DisplayName = name })
	local look = spot.CFrame.LookVector
	local at = spot.Position + Vector3.new(0, 2.6, 0)
	model:PivotTo(CFrame.lookAt(at, at - Vector3.new(look.X, 0, look.Z)))
	local hrp = model:FindFirstChild("HumanoidRootPart") :: BasePart
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.Anchored = d == hrp
		end
	end
	hrp.Anchored = true
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Subject
	humanoid.NameDisplayDistance = 30
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	model:SetAttribute("Townsfolk", true)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = hrp
	prompt.Triggered:Connect(onTrigger)
	model.Parent = townsFolder
end

local function promptOn(part: BasePart, name: string, action: string, onTrigger: (Player) -> ())
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = part
	prompt.Triggered:Connect(onTrigger)
end

local function spawnTownsfolk()
	for _, spot in CollectionService:GetTagged("SBR_Merchant") do
		if spot:IsA("BasePart") then
			townsperson(spot, "Shopkeeper", "Shop", function(player)
				Net.Notify(player, "OpenMenu", { Tab = "Shop" })
			end)
		end
	end
	for _, spot in CollectionService:GetTagged("SBR_HorseDealer") do
		if spot:IsA("BasePart") then
			townsperson(spot, "Stable Keeper", "Stable", function(player)
				Net.Notify(player, "OpenMenu", { Tab = "Stable" })
			end)
		end
	end
	for _, part in CollectionService:GetTagged("SBR_HealStation") do
		if part:IsA("BasePart") then
			promptOn(part, "Water Trough", "Tend horse", function(player)
				Net.Notify(player, "OpenMenu", { Tab = "Stable" })
			end)
		end
	end
	for _, board in CollectionService:GetTagged("SBR_QuestBoard") do
		if board:IsA("BasePart") then
			local town = board:GetAttribute("Town")
			promptOn(board, "Quest Board", "Read", function(player)
				Net.Notify(player, "OpenMenu", { Tab = "Quests", Town = town })
			end)
		end
	end
end

-- Rewards ------------------------------------------------------------------------

local function grantDrops(player: Player, drops: { NPCData.Drop }, rng: Random)
	for _, drop in drops do
		if rng:NextNumber() < drop.Chance then
			if drop.Item then
				DataService.AddItem(player, drop.Item, drop.Amount or 1)
				local item = ItemData.Items[drop.Item]
				Net.Notify(player, "Loot", { Item = drop.Item, Name = if item then item.Name else drop.Item, Amount = drop.Amount or 1 })
			elseif drop.Skin then
				SkinService.Grant(player, drop.Skin)
			elseif drop.Horse then
				HorseService.Grant(player, drop.Horse, "Boss")
			end
		end
	end
end

local function rewardEnemy(killer: Combatant, victim: Combatant, entry: Live)
	local player = killer.Player
	if not player then
		return
	end
	local arch = entry.Archetype
	local rng = Random.new()
	local level = victim.Level
	if arch then
		local cash = rng:NextInteger(arch.Cash[1], arch.Cash[2]) * (1 + level * 0.05)
		DataService.AddCash(player, cash)
		LevelService.AddXP(player, (Config.XP.NPCKillBase + Config.XP.NPCKillPerLevel * level) * arch.XPMult, "Defeated " .. arch.Name)
		grantDrops(player, arch.Drops, rng)
		Net.Notify(player, "Cash", { Amount = math.floor(cash) })
	end
	if rng:NextNumber() < Config.NPC.LootDropChance then
		local item = if rng:NextNumber() < 0.5 then "Bandage" else "Feed"
		DataService.AddItem(player, item, 1)
		Net.Notify(player, "Loot", { Item = item, Name = ItemData.Items[item].Name, Amount = 1 })
	end
	DataService.AddCounter(player, "NPCKills", 1)
	Signals.Quest:Fire(player, "NPCKill", 1)
end

local function rewardBoss(state: BossState, victim: Combatant)
	local boss = state.Data
	local total = 0
	for _, dealt in victim.Contributors do
		total += dealt
	end
	for attacker, dealt in victim.Contributors do
		local player = attacker.Player
		if player and player.Parent and total > 0 then
			local share = dealt / total
			if share >= 0.05 then
				local scale = math.max(0.3, math.min(1, share * 2))
				DataService.AddCash(player, boss.Cash * scale)
				Net.Notify(player, "Cash", { Amount = math.floor(boss.Cash * scale) })
				LevelService.AddXP(player, (Config.XP.BossKillBase + boss.XP) * scale, "Defeated " .. boss.Name)
				grantDrops(player, boss.Drops, Random.new())
				DataService.AddCounter(player, "BossKills", 1)
				Signals.Quest:Fire(player, "BossKill", 1)
				Net.Notify(player, "BossDefeated", { Name = boss.Name })
			end
		end
	end
end

local function onKilled(killer: Combatant?, victim: Combatant)
	local entry = live[victim]
	if not entry then
		return
	end
	live[victim] = nil
	if entry.Kind == "Boss" then
		for _, state in bosses do
			if state.C == victim then
				rewardBoss(state, victim)
				state.C = nil
				state.RespawnAt = os.clock() + Config.NPC.BossRespawnTime
				for _, add in state.Adds do
					if add.Model.Parent then
						add.Model:Destroy()
					end
				end
				state.Adds = {}
			end
		end
	elseif killer then
		rewardEnemy(killer, victim, entry)
	end
	if entry.Zone then
		local state = zoneStates[entry.Zone]
		if state then
			state.Count = math.max(0, state.Count - 1)
			state.NextSpawn = math.max(state.NextSpawn, os.clock() + Config.NPC.RespawnTime)
		end
	end
	-- Fall over, then fade out.
	victim.Humanoid:ChangeState(Enum.HumanoidStateType.Dead)
	task.delay(4, function()
		if entry.Horse and entry.Horse.Model.Parent then
			entry.Horse.Model:Destroy()
		end
		if victim.Model.Parent then
			victim.Model:Destroy()
		end
	end)
end

local function think()
	local now = os.clock()
	for c, entry in table.clone(live) do
		if not c.Model.Parent then
			live[c] = nil
			continue
		end
		if entry.Expires and now > entry.Expires then
			NPCService.Remove(entry)
			continue
		end
		if entry.Kind == "Rider" then
			-- Riders drop off when far behind their target.
			local brain = entry.Brain
			local t = brain.Target
			if not t or not Combatants.IsAlive(t) or (t.Root.Position - c.Root.Position).Magnitude > 500 then
				if not c.Data.Passive then
					NPCService.Remove(entry)
				end
				continue
			end
			if Combatants.IsAlive(c) and not Combatants.IsStunned(c) and not Combatants.IsBusy(c) then
				NPCBrain.TryMove(c, brain, t)
			end
		else
			NPCBrain.Think(c, entry.Brain)
		end
	end
end

function NPCService.Init()
	local folder = workspace:FindFirstChild("NPCs")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "NPCs"
		f.Parent = workspace
		folder = f
	end
	npcFolder = folder :: Folder
	local tf = workspace:FindFirstChild("Townsfolk")
	if not tf then
		local f = Instance.new("Folder")
		f.Name = "Townsfolk"
		f.Parent = workspace
		tf = f
	end
	townsFolder = tf :: Folder

	for _, zone in Layout.Zones do
		table.insert(zoneStates, { Zone = zone, Active = false, LastNear = 0, Count = 0, NextSpawn = 0 })
	end
	Signals.Killed:Connect(onKilled)
	Players.PlayerRemoving:Connect(function(player)
		nextAmbush[player] = nil
	end)
end

-- Called once the map is built.
function NPCService.Start()
	spawnTownsfolk()
	for _, arena in Layout.Arenas do
		local spawn = arena.Center
		for _, pad in CollectionService:GetTagged("SBR_BossSpawn") do
			if pad:IsA("BasePart") and pad:GetAttribute("Stage") == arena.Stage then
				spawn = pad.Position
			end
		end
		local data = NPCData.Bosses[arena.BossIndex]
		if data then
			table.insert(bosses, { Arena = arena, Data = data, Spawn = spawn, C = nil, RespawnAt = 0, Phase = 1, Adds = {}, LastPlayers = 0 })
		end
	end
	task.spawn(function()
		while true do
			task.wait(Config.NPC.ThinkInterval)
			think()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			updateZones()
			updateBosses()
			updateAmbushes()
		end
	end)
end

return NPCService
