--!strict
-- Horses on the server: spawning the equipped horse, whistling, mounting
-- with a short arc into the saddle, dismounting and being thrown off, rider
-- network ownership with speed and teleport checks, horse health and XP,
-- stables (buying, healing, naming, equipping, cosmetics), wild herds with
-- the taming minigame, and server driven horses for NPC riders.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local Types = require(ReplicatedStorage.Shared.Types)
local HorseData = require(ReplicatedStorage.Shared.HorseData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local HorseMotor = require(ReplicatedStorage.Shared.HorseMotor)
local Layout = require(ReplicatedStorage.Shared.Layout)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HorseBuilder = require(ReplicatedStorage.Builders.HorseBuilder)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Net)
local Signals = require(script.Parent.Signals)
local Combatants = require(script.Parent.Combatants)
local CombatService = require(script.Parent.CombatService)

type Combatant = Combatants.Combatant

local HorseService = {}

local H = Config.Horse
local horseEvent: RemoteEvent
local horsesFolder: Folder

type Active = {
	Model: Model,
	HorseId: string,
	Stats: Progression.HorseStats,
	Health: number,
	Rider: boolean,
	LastPos: Vector3,
	LastCheck: number,
	Violations: number,
	RideBank: number,
	Approach: boolean,
}

local active: { [Player]: Active } = {}
local mounting: { [Player]: boolean } = {}

-- Server driven horses (NPC mounts, wild herds, whistle approach).
export type ServerHorse = {
	Model: Model,
	Motor: HorseMotor.State,
	Control: (ServerHorse, number) -> HorseMotor.Input?,
	Data: { [string]: any },
}
local serverHorses: { [Model]: ServerHorse } = {}

local function fire(player: Player, kind: string, data: any)
	horseEvent:FireClient(player, kind, data)
end

local function ownedHorse(profile: Types.Profile, id: string?): Types.OwnedHorse?
	if not id then
		return nil
	end
	for _, h in profile.Horses do
		if h.Id == id then
			return h
		end
	end
	return nil
end

local function seedFor(id: string, userId: number): number
	local n = userId % 100000
	for i = 1, #id do
		n = (n * 31 + string.byte(id, i)) % 2147483647
	end
	return n
end

local function rootOf(model: Model): BasePart
	return model.PrimaryPart :: BasePart
end

local function rear(model: Model)
	model:SetAttribute("RearAt", workspace:GetServerTimeNow())
end

local function nameplate(model: Model, title: string, subtitle: string?)
	local root = rootOf(model)
	local gui = Instance.new("BillboardGui")
	gui.Name = "Nameplate"
	gui.Size = UDim2.fromOffset(160, 40)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 5.5 * (model:GetAttribute("Scale") :: number? or 1), 0)
	gui.MaxDistance = 60
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "Title"
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, 0, 0.6, 0)
	nameLabel.Font = Enum.Font.Merriweather
	nameLabel.TextScaled = true
	nameLabel.TextColor3 = Color3.fromRGB(240, 230, 206)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextStrokeColor3 = Color3.fromRGB(40, 28, 20)
	nameLabel.Text = title
	nameLabel.Parent = gui
	if subtitle then
		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.BackgroundTransparency = 1
		sub.Position = UDim2.fromScale(0, 0.6)
		sub.Size = UDim2.new(1, 0, 0.4, 0)
		sub.Font = Enum.Font.SourceSans
		sub.TextScaled = true
		sub.TextColor3 = Color3.fromRGB(220, 206, 176)
		sub.TextStrokeTransparency = 0.5
		sub.Text = subtitle
		sub.Parent = gui
	end
	gui.Parent = root
end

-- Server driven horse helpers ------------------------------------------------

function HorseService.SpawnServerHorse(opts: HorseBuilder.BuildOptions, cf: CFrame, control: (ServerHorse, number) -> HorseMotor.Input?): ServerHorse
	local model = HorseBuilder.Build(opts)
	HorseMotor.PlaceOnGround(model, cf.Position, cf.LookVector)
	model.Parent = horsesFolder
	CollectionService:AddTag(model, "SBR_Horse")
	local root = rootOf(model)
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local stats = Progression.BreedStats(opts.Breed)
	local motor = HorseMotor.new(model, stats, false)
	HorseMotor.Enable(motor, true)
	local sh: ServerHorse = { Model = model, Motor = motor, Control = control, Data = {} }
	serverHorses[model] = sh
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			serverHorses[model] = nil
		end
	end)
	return sh
end

function HorseService.Park(sh: ServerHorse)
	HorseMotor.Enable(sh.Motor, false)
	sh.Motor.Speed = 0
	rootOf(sh.Model).Anchored = true
end

function HorseService.Unpark(sh: ServerHorse)
	local root = rootOf(sh.Model)
	if root.Anchored then
		root.Anchored = false
		pcall(function()
			root:SetNetworkOwner(nil)
		end)
	end
	HorseMotor.Enable(sh.Motor, true)
end

function HorseService.ServerHorse(model: Model): ServerHorse?
	return serverHorses[model]
end

local stepAcc = 0
local function stepServerHorses(dt: number)
	stepAcc += dt
	if stepAcc < 1 / 30 then
		return
	end
	local step = stepAcc
	stepAcc = 0
	for model, sh in serverHorses do
		local root = model.PrimaryPart
		if not root or not model.Parent then
			serverHorses[model] = nil
			continue
		end
		if root.Anchored then
			continue
		end
		local ok, input = pcall(sh.Control, sh, step)
		if ok and input then
			HorseMotor.Step(sh.Motor, step, input)
		elseif not ok then
			warn("[HorseService] control failed:", input)
			serverHorses[model] = nil
		end
	end
end

-- Player horses ----------------------------------------------------------------

local function persistHealth(player: Player)
	local entry = active[player]
	local profile = DataService.Get(player)
	if not entry or not profile then
		return
	end
	local owned = ownedHorse(profile, entry.HorseId)
	if owned then
		owned.Health = if entry.Health >= entry.Stats.MaxHealth then -1 else math.max(0, math.floor(entry.Health))
		DataService.MarkDirty(player)
	end
end

function HorseService.Despawn(player: Player)
	local entry = active[player]
	if not entry then
		return
	end
	persistHealth(player)
	if entry.Rider then
		HorseService.Dismount(player, false)
	end
	local sh = serverHorses[entry.Model]
	if sh then
		serverHorses[entry.Model] = nil
	end
	entry.Model:Destroy()
	active[player] = nil
end

function HorseService.Active(player: Player): Model?
	local entry = active[player]
	return if entry then entry.Model else nil
end

function HorseService.IsMounted(player: Player): boolean
	local entry = active[player]
	return entry ~= nil and entry.Rider
end

local function buildPlayerHorse(player: Player, owned: Types.OwnedHorse): Model
	local model = HorseBuilder.Build({
		Breed = owned.Breed,
		Coat = owned.Coat,
		ManeColor = owned.ManeColor,
		Pattern = owned.Pattern,
		Cosmetics = owned.Cosmetics,
		Name = owned.Name,
		Seed = seedFor(owned.Id, player.UserId),
	})
	model:SetAttribute("OwnerId", player.UserId)
	model:SetAttribute("HorseId", owned.Id)
	model:SetAttribute("HorseName", owned.Name)
	model:SetAttribute("RiderId", 0)
	local root = rootOf(model)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "MountPrompt"
	prompt.ActionText = "Ride"
	prompt.ObjectText = owned.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = H.MountDistance
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = root
	prompt.Triggered:Connect(function(who)
		if who == player then
			HorseService.Mount(player)
		end
	end)
	nameplate(model, owned.Name, player.DisplayName .. "'s horse")
	CollectionService:AddTag(model, "SBR_Horse")
	return model
end

-- Spawns the equipped horse at a position facing a direction.
function HorseService.SpawnAt(player: Player, position: Vector3, facing: Vector3): Model?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local owned = ownedHorse(profile, profile.EquippedHorse)
	if not owned then
		Net.Toast(player, "You have no horse equipped. Visit a stable.", "Bad")
		return nil
	end
	if owned.Health == 0 then
		Net.Toast(player, owned.Name .. " is hurt. Heal it at a stable or use Horse Feed.", "Bad")
		return nil
	end
	HorseService.Despawn(player)
	local stats = Progression.HorseStats(owned)
	local model = buildPlayerHorse(player, owned)
	HorseMotor.PlaceOnGround(model, position, facing)
	local health = if owned.Health < 0 then stats.MaxHealth else owned.Health
	model:SetAttribute("Health", math.floor(health))
	model:SetAttribute("MaxHealth", math.floor(stats.MaxHealth))
	model.Parent = horsesFolder
	active[player] = {
		Model = model,
		HorseId = owned.Id,
		Stats = stats,
		Health = health,
		Rider = false,
		LastPos = rootOf(model).Position,
		LastCheck = os.clock(),
		Violations = 0,
		RideBank = 0,
		Approach = false,
	}
	return model
end

-- Gallops a player's idle horse toward them, then parks it.
local function approach(player: Player, entry: Active)
	local model = entry.Model
	local root = rootOf(model)
	entry.Approach = true
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	local motor = HorseMotor.new(model, entry.Stats, false)
	HorseMotor.Enable(motor, true)
	local started = os.clock()
	local sh: ServerHorse = {
		Model = model,
		Motor = motor,
		Data = {},
		Control = function(_sh, _dt)
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hrp or not entry.Approach or os.clock() - started > 12 then
				return nil
			end
			local to = hrp.Position - root.Position
			local flat = Vector3.new(to.X, 0, to.Z)
			local dist = flat.Magnitude
			if dist < 7 then
				return nil
			end
			local speed = if dist > 40 then entry.Stats.Gallop elseif dist > 16 then entry.Stats.Trot else entry.Stats.Walk
			return { Throttle = 0, Steer = 0, Gallop = true, Jump = false, TargetSpeed = speed, TargetHeading = flat }
		end,
	}
	serverHorses[model] = sh
	task.spawn(function()
		while serverHorses[model] == sh and model.Parent do
			local character = player.Character
			local hrp = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local done = not hrp or not entry.Approach or os.clock() - started > 12
			if hrp then
				local flat = Vector3.new(hrp.Position.X - root.Position.X, 0, hrp.Position.Z - root.Position.Z)
				if flat.Magnitude < 7 then
					done = true
				end
			end
			if done then
				break
			end
			task.wait(0.1)
		end
		if serverHorses[model] == sh then
			serverHorses[model] = nil
		end
		if model.Parent and not entry.Rider then
			HorseMotor.Enable(motor, false)
			HorseMotor.PlaceOnGround(model, root.Position, root.CFrame.LookVector)
			root.Anchored = true
			rear(model)
			entry.LastPos = root.Position
		end
		entry.Approach = false
	end)
end

local function onWhistle(player: Player)
	local c = Combatants.ForPlayer(player)
	if not c or not Combatants.IsAlive(c) or c.Mounted then
		return
	end
	if Combatants.Cooldown(c, "Whistle") > 0 then
		return
	end
	Combatants.SetCooldown(c, "Whistle", H.WhistleCooldown)
	Net.FX("Whistle", { Model = c.Model })
	local entry = active[player]
	local hrp = c.Root
	if entry and entry.Model.Parent then
		local dist = (rootOf(entry.Model).Position - hrp.Position).Magnitude
		if dist < 120 then
			if not entry.Approach then
				approach(player, entry)
			end
			return
		end
	end
	-- Spawn behind the player out of sight and gallop in.
	local back = -Combatants.Look(c)
	local spawnPos = hrp.Position + back * (H.WhistleSpawnDistance + 20)
	local blocked = workspace:Raycast(hrp.Position + Vector3.new(0, 3, 0), back * (H.WhistleSpawnDistance + 20), HorseMotor.RayParams())
	if blocked then
		spawnPos = hrp.Position + back * math.max(6, (blocked.Position - hrp.Position).Magnitude - 4)
	end
	local model = HorseService.SpawnAt(player, spawnPos, -back)
	if model then
		local newEntry = active[player]
		if newEntry then
			approach(player, newEntry)
		end
	end
end

function HorseService.Mount(player: Player)
	local entry = active[player]
	local c = Combatants.ForPlayer(player)
	if not entry or not c or mounting[player] or entry.Rider then
		return
	end
	if not Combatants.IsAlive(c) or Combatants.IsStunned(c) or c.Mounted then
		return
	end
	if entry.Health <= 0 then
		Net.Toast(player, "Your horse is too hurt to ride.", "Bad")
		return
	end
	local model = entry.Model
	local root = rootOf(model)
	if (root.Position - c.Root.Position).Magnitude > H.MountDistance + 4 then
		return
	end
	local seat = model:FindFirstChild("Saddle") :: Seat?
	if not seat then
		return
	end
	mounting[player] = true
	entry.Approach = false
	serverHorses[model] = nil
	c.Blocking = false

	-- Arc up and over into the saddle.
	local hrp = c.Root
	local startCF = hrp.CFrame
	local endCF = seat.CFrame * CFrame.new(0, 2.4, 0)
	local mid = (startCF.Position + endCF.Position) / 2 + Vector3.new(0, 3, 0)
	local midCF = CFrame.lookAt(mid, mid + root.CFrame.LookVector)
	hrp.Anchored = true
	local t1 = TweenService:Create(hrp, TweenInfo.new(H.MountTweenTime * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = midCF })
	t1:Play()
	t1.Completed:Wait()
	local t2 = TweenService:Create(hrp, TweenInfo.new(H.MountTweenTime * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = endCF })
	t2:Play()
	t2.Completed:Wait()
	hrp.Anchored = false
	mounting[player] = nil
	if not Combatants.IsAlive(c) or not model.Parent then
		return
	end

	seat.Disabled = false
	seat:Sit(c.Humanoid)
	root.Anchored = false
	pcall(function()
		root:SetNetworkOwner(player)
	end)
	entry.Rider = true
	entry.LastPos = root.Position
	entry.LastCheck = os.clock()
	entry.Violations = 0
	c.Mounted = model
	model:SetAttribute("RiderId", player.UserId)
	c.Model:SetAttribute("Mounted", true)
	rear(model)
	local profile = DataService.Get(player)
	local owned = if profile then ownedHorse(profile, entry.HorseId) else nil
	fire(player, "Mounted", {
		Horse = model,
		Stats = entry.Stats,
		Name = if owned then owned.Name else model.Name,
		Breed = if owned then owned.Breed else "",
		Level = if owned then owned.Level else 1,
	})

	local conn: RBXScriptConnection
	conn = seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if seat.Occupant == nil then
			conn:Disconnect()
			if entry.Rider then
				HorseService.Dismount(player, false)
			end
		end
	end)
end

function HorseService.Dismount(player: Player, thrown: boolean)
	local entry = active[player]
	if not entry or not entry.Rider then
		return
	end
	entry.Rider = false
	local model = entry.Model
	local root = rootOf(model)
	local seat = model:FindFirstChild("Saddle") :: Seat?
	if seat then
		seat.Disabled = true
	end
	model:SetAttribute("RiderId", 0)
	local c = Combatants.ForPlayer(player)
	if c then
		c.Mounted = nil
		c.Model:SetAttribute("Mounted", false)
		if Combatants.IsAlive(c) then
			local side = root.CFrame * CFrame.new(-3.6, 0.5, 0)
			c.Model:PivotTo(CFrame.lookAt(side.Position, side.Position + root.CFrame.LookVector))
			if thrown then
				local dir = root.CFrame.LookVector
				CombatService.Knockback(c, (dir + Vector3.new(0, 0.6, 0)) * H.ThrowOffKnockback)
				CombatService.Stun(c, 1.2, true)
			end
		end
	end
	pcall(function()
		root:SetNetworkOwner(nil)
	end)
	fire(player, "Dismounted", { Thrown = thrown })
	persistHealth(player)
	task.delay(0.35, function()
		if model.Parent and not entry.Rider then
			local velocity = model.PrimaryPart and (model.PrimaryPart :: BasePart):FindFirstChild("Velocity") :: LinearVelocity?
			local align = model.PrimaryPart and (model.PrimaryPart :: BasePart):FindFirstChild("Align") :: AlignOrientation?
			if velocity then
				velocity.MaxForce = 0
			end
			if align then
				align.MaxTorque = 0
			end
			HorseMotor.PlaceOnGround(model, root.Position, root.CFrame.LookVector)
			root.Anchored = true
			entry.LastPos = root.Position
		end
	end)
end

local function onDismount(player: Player)
	if HorseService.IsMounted(player) then
		HorseService.Dismount(player, false)
	end
end

-- Damage to the horse when its rider is hit.
local function onMountedHit(rider: Combatant, damage: number, _attacker: Combatant?)
	local player = rider.Player
	if not player then
		return
	end
	local entry = active[player]
	if not entry then
		return
	end
	entry.Health = math.max(0, entry.Health - damage * H.DamageTakenMult)
	entry.Model:SetAttribute("Health", math.floor(entry.Health))
	if entry.Health <= 0 then
		persistHealth(player)
		Net.Notify(player, "HorseHurt", { Name = entry.Model:GetAttribute("HorseName") })
		HorseService.Dismount(player, true)
		rear(entry.Model)
		task.delay(1.5, function()
			if active[player] == entry then
				HorseService.Despawn(player)
			end
		end)
	end
end

-- Horse XP from riding distance and race wins.
function HorseService.AddHorseXP(player: Player, amount: number)
	local entry = active[player]
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	local id = if entry then entry.HorseId else profile.EquippedHorse
	local owned = ownedHorse(profile, id)
	if not owned or owned.Level >= H.MaxLevel then
		return
	end
	owned.XP += amount
	local leveled = false
	while owned.Level < H.MaxLevel and owned.XP >= Progression.HorseXPForLevel(owned.Level) do
		owned.XP -= Progression.HorseXPForLevel(owned.Level)
		owned.Level += 1
		leveled = true
	end
	DataService.MarkDirty(player)
	if leveled then
		Net.Notify(player, "HorseLevel", { Name = owned.Name, Level = owned.Level })
		if entry and entry.HorseId == owned.Id then
			entry.Stats = Progression.HorseStats(owned)
			entry.Model:SetAttribute("MaxHealth", math.floor(entry.Stats.MaxHealth))
			if entry.Rider then
				fire(player, "Stats", { Stats = entry.Stats, Level = owned.Level })
			end
		end
	end
end

-- Gives a player a new horse. Returns the new horse id.
function HorseService.Grant(player: Player, breedId: string, source: string?): string?
	local profile = DataService.Get(player)
	local breed = HorseData.Breeds[breedId]
	if not profile or not breed then
		return nil
	end
	if #profile.Horses >= H.MaxOwned then
		Net.Toast(player, "Your stable is full. Release a horse first.", "Bad")
		return nil
	end
	local rng = Random.new()
	local id = "h" .. profile.NextHorseId
	profile.NextHorseId += 1
	local pattern = if #breed.Patterns > 0 then breed.Patterns[rng:NextInteger(1, #breed.Patterns)] else ""
	local horse: Types.OwnedHorse = {
		Id = id,
		Breed = breed.Id,
		Name = HorseData.Names[rng:NextInteger(1, #HorseData.Names)],
		Level = 1,
		XP = 0,
		Health = -1,
		Coat = rng:NextInteger(1, #breed.Coats),
		ManeColor = rng:NextInteger(1, #breed.Manes),
		Pattern = pattern,
		Cosmetics = { Saddle = "Brown", Blanket = "Red", Mane = "Classic", Shoes = "Iron" },
	}
	table.insert(profile.Horses, horse)
	if not profile.EquippedHorse then
		profile.EquippedHorse = id
	end
	DataService.MarkDirty(player)
	Net.Notify(player, "NewHorse", { Name = horse.Name, Breed = breed.Name, Rarity = breed.Rarity, Source = source })
	return id
end

-- Horse Feed: restores half of the equipped horse's health, even when hurt.
function HorseService.Feed(player: Player): (boolean, string)
	local profile = DataService.Get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	local owned = ownedHorse(profile, profile.EquippedHorse)
	if not owned then
		return false, "You have no horse equipped"
	end
	local stats = Progression.HorseStats(owned)
	local entry = active[player]
	local live = entry ~= nil and entry.HorseId == owned.Id
	local current = if live and entry then entry.Health elseif owned.Health < 0 then stats.MaxHealth else owned.Health
	if current >= stats.MaxHealth then
		return false, owned.Name .. " is already healthy"
	end
	local healed = math.min(stats.MaxHealth, current + stats.MaxHealth * 0.5)
	owned.Health = if healed >= stats.MaxHealth then -1 else math.floor(healed)
	if live and entry then
		entry.Health = healed
		entry.Model:SetAttribute("Health", math.floor(healed))
	end
	DataService.MarkDirty(player)
	return true, owned.Name .. " looks better"
end

-- Proximity helper for stable services.
local function nearTag(player: Player, tag: string, range: number): boolean
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return false
	end
	for _, part in CollectionService:GetTagged(tag) do
		if part:IsA("BasePart") and (part.Position - root.Position).Magnitude <= range then
			return true
		end
	end
	return false
end

function HorseService.NearStable(player: Player): boolean
	return nearTag(player, "SBR_HorseDealer", 40) or nearTag(player, "SBR_HealStation", 40)
end

local function breedUnlocked(profile: Types.Profile, breed: HorseData.Breed): boolean
	if profile.Level < breed.MinLevel then
		return false
	end
	if breed.Rarity == "Rare" or breed.Rarity == "Epic" then
		return Progression.IsUnlocked(profile.Level, "RareHorses")
	end
	if breed.Rarity == "Legendary" or breed.Rarity == "Mythic" then
		return Progression.IsUnlocked(profile.Level, "LegendaryHorses")
	end
	return true
end

local function filterName(player: Player, text: string): string?
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(text, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok and type(result) == "string" then
		return result
	end
	return nil
end

-- Wild herds and taming --------------------------------------------------------

type Herd = {
	Info: Layout.Herd,
	Members: { ServerHorse },
	Active: boolean,
	LastNear: number,
	Center: Vector3,
}

local herds: { Herd } = {}

type TameSession = {
	Horse: ServerHorse,
	Breed: string,
	Round: number,
	Rounds: number,
	Period: number,
	Width: number,
	Center: number,
	StartAt: number,
	Done: boolean,
}
local taming: { [Player]: TameSession } = {}
local tameCooldown: { [Model]: { [Player]: number } } = {}

local RARITY_TAME = {
	Common = { Width = 1.0, Period = 1.4 },
	Uncommon = { Width = 0.9, Period = 1.25 },
	Rare = { Width = 0.8, Period = 1.1 },
	Epic = { Width = 0.7, Period = 1.0 },
	Legendary = { Width = 0.6, Period = 0.9 },
	Mythic = { Width = 0.5, Period = 0.8 },
}

local function needle(t: number, period: number): number
	if t < 0 then
		return 0
	end
	local x = (t % (2 * period)) / period
	return if x > 1 then 2 - x else x
end

local function herdControl(herd: Herd): (ServerHorse, number) -> HorseMotor.Input?
	return function(sh, _dt)
		local data = sh.Data
		local root = rootOf(sh.Model)
		local now = os.clock()
		if data.Taming then
			return { Throttle = 0, Steer = 0, Gallop = false, Jump = false, TargetSpeed = 0 }
		end
		-- Bolt away from fast riders and failed tamers.
		if data.FleeUntil and now < data.FleeUntil and data.FleeFrom then
			local away = root.Position - (data.FleeFrom :: Vector3)
			return { Throttle = 0, Steer = 0, Gallop = true, Jump = false, TargetSpeed = sh.Motor.Stats.Canter, TargetHeading = away }
		end
		if not data.Target or now > (data.NextPick or 0) then
			local a = math.random() * math.pi * 2
			local r = math.random() * H.HerdWanderRadius
			data.Target = herd.Center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			data.NextPick = now + math.random(6, 14)
			data.Graze = math.random() < 0.4
		end
		local to = (data.Target :: Vector3) - root.Position
		local flat = Vector3.new(to.X, 0, to.Z)
		if flat.Magnitude < 4 or data.Graze then
			sh.Model:SetAttribute("Graze", data.Graze == true)
			return { Throttle = 0, Steer = 0, Gallop = false, Jump = false, TargetSpeed = 0 }
		end
		sh.Model:SetAttribute("Graze", false)
		return { Throttle = 0, Steer = 0, Gallop = false, Jump = false, TargetSpeed = sh.Motor.Stats.Walk, TargetHeading = flat }
	end
end

local function pickWildBreed(stage: number, rng: Random): string
	local options = {}
	for _, id in HorseData.Order do
		local breed = HorseData.Breeds[id]
		if table.find(breed.WildStages, stage) then
			table.insert(options, breed)
		end
	end
	if #options == 0 then
		return "Mustang"
	end
	local pick = Util.weightedPick(rng, options, function(b)
		return (HorseData.RarityWildWeight :: any)[b.Rarity] or 1
	end)
	return if pick then pick.Id else "Mustang"
end

local function spawnHerdMember(herd: Herd, rng: Random)
	local breedId = pickWildBreed(herd.Info.Stage, rng)
	local breed = HorseData.Breeds[breedId]
	local a = rng:NextNumber(0, math.pi * 2)
	local r = rng:NextNumber(4, H.HerdWanderRadius * 0.6)
	local pos = herd.Center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
	local sh = HorseService.SpawnServerHorse({
		Breed = breedId,
		Coat = rng:NextInteger(1, #breed.Coats),
		ManeColor = rng:NextInteger(1, #breed.Manes),
		Pattern = if #breed.Patterns > 0 then breed.Patterns[rng:NextInteger(1, #breed.Patterns)] else nil,
		Seed = rng:NextInteger(1, 1e6),
		NoSeat = true,
		Name = "Wild " .. breed.Name,
	}, CFrame.lookAt(pos, pos + Vector3.new(math.cos(a + 1), 0, math.sin(a + 1))), herdControl(herd))
	local model = sh.Model
	-- Wild horses wear no tack.
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local n = d.Name
			if n == "Blanket" or n == "BlanketSide" or n == "Stripe" or n == "Skirt" or n == "Strap" or n == "Stirrup" or n == "StirrupSide" or n == "Seat" or n == "Cantle" or n == "Pommel" or n == "Horn" or n == "Girth" then
				d:Destroy()
			end
		elseif d:IsA("Beam") and d.Name == "Rein" then
			d:Destroy()
		end
	end
	model:SetAttribute("Wild", true)
	model:SetAttribute("Rarity", breed.Rarity)
	nameplate(model, breed.Name, breed.Rarity)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "TamePrompt"
	prompt.ActionText = "Calm"
	prompt.ObjectText = "Wild " .. breed.Name
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.4
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = rootOf(model)
	prompt.Triggered:Connect(function(player)
		HorseService.StartTame(player, sh, breedId)
	end)
	table.insert(herd.Members, sh)
end

local function updateHerds()
	local now = os.clock()
	for _, herd in herds do
		local near = false
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - herd.Center).Magnitude < Config.NPC.ActivationRange then
				near = true
				-- Fast riders spook the herd.
				for _, sh in herd.Members do
					local hr = sh.Model.PrimaryPart
					if hr and not sh.Data.Taming then
						local d = (hr.Position - root.Position).Magnitude
						if d < 14 and root.AssemblyLinearVelocity.Magnitude > 30 then
							sh.Data.FleeUntil = now + 3
							sh.Data.FleeFrom = root.Position
						end
					end
				end
			end
		end
		if near then
			herd.LastNear = now
			if not herd.Active then
				herd.Active = true
				local rng = Random.new()
				local count = rng:NextInteger(H.HerdSize[1], H.HerdSize[2])
				for _ = 1, count do
					spawnHerdMember(herd, rng)
				end
			end
		elseif herd.Active and now - herd.LastNear > 30 then
			herd.Active = false
			for _, sh in herd.Members do
				sh.Model:Destroy()
			end
			herd.Members = {}
		end
		-- Drop removed members.
		for i = #herd.Members, 1, -1 do
			if not herd.Members[i].Model.Parent then
				table.remove(herd.Members, i)
			end
		end
	end
end

local function endTame(player: Player, success: boolean)
	local session = taming[player]
	if not session or session.Done then
		return
	end
	session.Done = true
	taming[player] = nil
	local sh = session.Horse
	sh.Data.Taming = nil
	fire(player, "TameResult", { Success = success })
	if success then
		local id = HorseService.Grant(player, session.Breed, "Tamed")
		if id then
			DataService.AddCounter(player, "Tamed", 1)
			Signals.Quest:Fire(player, "Tame", 1)
			sh.Model:Destroy()
		else
			HorseService.Unpark(sh)
		end
	else
		HorseService.Unpark(sh)
		rear(sh.Model)
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		sh.Data.FleeUntil = os.clock() + 4
		sh.Data.FleeFrom = if root then root.Position else nil
		tameCooldown[sh.Model] = tameCooldown[sh.Model] or {}
		tameCooldown[sh.Model][player] = os.clock() + 20
	end
end

local function sendRound(player: Player, session: TameSession)
	session.Center = 0.2 + math.random() * 0.6
	session.StartAt = workspace:GetServerTimeNow() + 0.8
	fire(player, "TameRound", {
		Round = session.Round,
		Rounds = session.Rounds,
		Center = session.Center,
		Width = session.Width,
		Period = session.Period,
		StartAt = session.StartAt,
	})
	local round = session.Round
	task.delay(6.8, function()
		if taming[player] == session and session.Round == round and not session.Done then
			endTame(player, false)
		end
	end)
end

function HorseService.StartTame(player: Player, sh: ServerHorse, breedId: string)
	local c = Combatants.ForPlayer(player)
	local profile = DataService.Get(player)
	if not c or not profile or not Combatants.IsAlive(c) or c.Mounted or taming[player] or sh.Data.Taming then
		return
	end
	if #profile.Horses >= H.MaxOwned then
		Net.Toast(player, "Your stable is full. Release a horse first.", "Bad")
		return
	end
	local cooldowns = tameCooldown[sh.Model]
	if cooldowns and cooldowns[player] and os.clock() < cooldowns[player] then
		Net.Toast(player, "This horse will not let you near yet.", "Bad")
		return
	end
	local breed = HorseData.Breeds[breedId]
	local tune = (RARITY_TAME :: any)[breed.Rarity] or RARITY_TAME.Common
	sh.Data.Taming = player
	HorseService.Park(sh)
	rear(sh.Model)
	local session: TameSession = {
		Horse = sh,
		Breed = breedId,
		Round = 1,
		Rounds = H.TameWindows,
		Period = tune.Period,
		Width = H.TameWindowWidth * tune.Width,
		Center = 0.5,
		StartAt = 0,
		Done = false,
	}
	taming[player] = session
	fire(player, "TameStart", { Horse = sh.Model, Breed = breed.Name, Rarity = breed.Rarity, Rounds = session.Rounds })
	sendRound(player, session)
end

local function onTamePress(player: Player)
	local session = taming[player]
	if not session or session.Done then
		return
	end
	local now = workspace:GetServerTimeNow()
	local t = now - session.StartAt
	if t < -0.1 then
		return
	end
	local hit = false
	local samples = 10
	for k = 0, samples do
		local tt = t - H.TameLatencyAllowance * k / samples
		local x = needle(tt, session.Period)
		if math.abs(x - session.Center) <= session.Width / 2 then
			hit = true
			break
		end
	end
	if not hit then
		endTame(player, false)
		return
	end
	fire(player, "TameHit", { Round = session.Round })
	if session.Round >= session.Rounds then
		endTame(player, true)
	else
		session.Round += 1
		sendRound(player, session)
	end
end

-- Requests ----------------------------------------------------------------------

local function stableList(profile: Types.Profile)
	local list = {}
	for _, id in HorseData.Order do
		local breed = HorseData.Breeds[id]
		if breed.InStable then
			table.insert(list, {
				Id = id,
				Name = breed.Name,
				Rarity = breed.Rarity,
				Price = breed.Price,
				Unlocked = breedUnlocked(profile, breed),
				Description = breed.Description,
			})
		end
	end
	return list
end

local function registerRequests()
	Net.OnRequest("StableInfo", function(player: Player)
		local profile = DataService.Get(player)
		if not profile then
			return Net.Fail("Profile not loaded")
		end
		return Net.Ok({ Near = HorseService.NearStable(player), Breeds = stableList(profile) })
	end)

	Net.OnRequest("BuyHorse", function(player: Player, breedId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(breedId) then
			return Net.Fail("Bad request")
		end
		if not nearTag(player, "SBR_HorseDealer", 40) then
			return Net.Fail("Talk to a stable keeper to buy horses")
		end
		local breed = HorseData.Breeds[breedId]
		if not breed or not breed.InStable then
			return Net.Fail("That horse is not for sale")
		end
		if not breedUnlocked(profile, breed) then
			return Net.Fail("You need a higher level for this breed")
		end
		if #profile.Horses >= H.MaxOwned then
			return Net.Fail("Your stable is full")
		end
		if not DataService.SpendCash(player, breed.Price) then
			return Net.Fail("Not enough cash")
		end
		local id = HorseService.Grant(player, breed.Id, "Bought")
		return Net.Ok(id)
	end)

	Net.OnRequest("HealHorse", function(player: Player, horseId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(horseId) then
			return Net.Fail("Bad request")
		end
		if not HorseService.NearStable(player) then
			return Net.Fail("Visit a stable to heal horses")
		end
		local owned = ownedHorse(profile, horseId)
		if not owned then
			return Net.Fail("Unknown horse")
		end
		local stats = Progression.HorseStats(owned)
		local entry = active[player]
		local current = if entry and entry.HorseId == owned.Id then entry.Health elseif owned.Health < 0 then stats.MaxHealth else owned.Health
		local missing = stats.MaxHealth - current
		if missing <= 0 then
			return Net.Fail("This horse is already healthy")
		end
		local cost = math.ceil(missing * H.HealCostPerMissingHP)
		if not DataService.SpendCash(player, cost) then
			return Net.Fail("Healing costs $" .. cost)
		end
		owned.Health = -1
		if entry and entry.HorseId == owned.Id then
			entry.Health = stats.MaxHealth
			entry.Model:SetAttribute("Health", math.floor(stats.MaxHealth))
		end
		DataService.MarkDirty(player)
		return Net.Ok(cost)
	end)

	Net.OnRequest("EquipHorse", function(player: Player, horseId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(horseId) then
			return Net.Fail("Bad request")
		end
		if not ownedHorse(profile, horseId) then
			return Net.Fail("Unknown horse")
		end
		if HorseService.IsMounted(player) then
			return Net.Fail("Dismount first")
		end
		profile.EquippedHorse = horseId
		DataService.MarkDirty(player)
		HorseService.Despawn(player)
		return Net.Ok()
	end)

	Net.OnRequest("RenameHorse", function(player: Player, horseId: any, name: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(horseId) or not Net.IsString(name, 60) then
			return Net.Fail("Bad request")
		end
		local owned = ownedHorse(profile, horseId)
		if not owned then
			return Net.Fail("Unknown horse")
		end
		local trimmed = (name :: string):gsub("^%s+", ""):gsub("%s+$", "")
		if #trimmed < 2 or #trimmed > H.RenameMaxLength then
			return Net.Fail("Names must be 2 to " .. H.RenameMaxLength .. " characters")
		end
		local filtered = filterName(player, trimmed)
		if not filtered then
			return Net.Fail("Could not check that name, try again")
		end
		owned.Name = filtered
		DataService.MarkDirty(player)
		local entry = active[player]
		if entry and entry.HorseId == owned.Id then
			entry.Model:SetAttribute("HorseName", filtered)
			local plate = rootOf(entry.Model):FindFirstChild("Nameplate")
			local title = plate and plate:FindFirstChild("Title") :: TextLabel?
			if title then
				title.Text = filtered
			end
		end
		return Net.Ok(filtered)
	end)

	Net.OnRequest("ReleaseHorse", function(player: Player, horseId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(horseId) then
			return Net.Fail("Bad request")
		end
		if #profile.Horses <= 1 then
			return Net.Fail("You cannot release your last horse")
		end
		for i, h in profile.Horses do
			if h.Id == horseId then
				local entry = active[player]
				if entry and entry.HorseId == horseId then
					HorseService.Despawn(player)
				end
				table.remove(profile.Horses, i)
				if profile.EquippedHorse == horseId then
					profile.EquippedHorse = profile.Horses[1].Id
				end
				DataService.MarkDirty(player)
				return Net.Ok()
			end
		end
		return Net.Fail("Unknown horse")
	end)

	Net.OnRequest("BuyHorseCosmetic", function(player: Player, slot: any, id: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(slot) or not Net.IsString(id) then
			return Net.Fail("Bad request")
		end
		local option = HorseData.FindCosmetic(slot, id)
		if not option then
			return Net.Fail("Unknown item")
		end
		local key = slot .. ":" .. id
		if profile.HorseCosmetics[key] then
			return Net.Fail("You already own it")
		end
		if not HorseService.NearStable(player) then
			return Net.Fail("Visit a stable to buy tack")
		end
		if not DataService.SpendCash(player, option.Price) then
			return Net.Fail("Not enough cash")
		end
		profile.HorseCosmetics[key] = true
		DataService.MarkDirty(player)
		return Net.Ok()
	end)

	Net.OnRequest("SetHorseCosmetic", function(player: Player, horseId: any, slot: any, id: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(horseId) or not Net.IsString(slot) or not Net.IsString(id) then
			return Net.Fail("Bad request")
		end
		local owned = ownedHorse(profile, horseId)
		if not owned then
			return Net.Fail("Unknown horse")
		end
		if not HorseData.FindCosmetic(slot, id) then
			return Net.Fail("Unknown item")
		end
		if not profile.HorseCosmetics[slot .. ":" .. id] then
			return Net.Fail("Buy it at a stable first")
		end
		local cosmetics = owned.Cosmetics :: any
		if cosmetics[slot] == nil then
			return Net.Fail("Unknown slot")
		end
		cosmetics[slot] = id
		DataService.MarkDirty(player)
		local entry = active[player]
		if entry and entry.HorseId == owned.Id and not entry.Rider then
			-- Rebuild in place so the new tack shows.
			local root = rootOf(entry.Model)
			local pos, look = root.Position, root.CFrame.LookVector
			HorseService.Despawn(player)
			HorseService.SpawnAt(player, pos, look)
		end
		return Net.Ok()
	end)
end

function HorseService.Init()
	horseEvent = Remotes.Event("Horse")
	local folder = workspace:FindFirstChild("Horses")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Horses"
		f.Parent = workspace
		folder = f
	end
	horsesFolder = folder :: Folder

	CombatService.Hooks.MountedHit = onMountedHit
	CombatService.Hooks.Dismount = function(c)
		if c.Player then
			HorseService.Dismount(c.Player, false)
		end
	end

	Net.OnAction("Whistle", onWhistle)
	Net.OnAction("Dismount", onDismount)
	Net.OnAction("TamePress", onTamePress)
	registerRequests()

	Signals.Killed:Connect(function(_killer, victim)
		local player = victim.Player
		if player and HorseService.IsMounted(player) then
			HorseService.Dismount(player, false)
		end
		if player and taming[player] then
			endTame(player, false)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if taming[player] then
			endTame(player, false)
		end
		HorseService.Despawn(player)
		mounting[player] = nil
	end)

	for _, info in Layout.Herds do
		table.insert(herds, { Info = info, Members = {}, Active = false, LastNear = 0, Center = info.Center })
	end
end

local function sanity()
	local now = os.clock()
	for player, entry in active do
		local model = entry.Model
		local root = model.PrimaryPart
		if not root or not model.Parent then
			active[player] = nil
			continue
		end
		local dt = now - entry.LastCheck
		entry.LastCheck = now
		if not entry.Rider then
			-- Idle horses slowly recover.
			if entry.Health < entry.Stats.MaxHealth and entry.Health > 0 then
				entry.Health = math.min(entry.Stats.MaxHealth, entry.Health + dt * 0.5)
				model:SetAttribute("Health", math.floor(entry.Health))
			end
			continue
		end
		local pos = root.Position
		local flat = Vector3.new(pos.X - entry.LastPos.X, 0, pos.Z - entry.LastPos.Z).Magnitude
		local allowed = entry.Stats.Gallop * H.SpeedTolerance * dt + H.TeleportTolerance
		if flat > allowed then
			entry.Violations += 1
			warn(string.format("[HorseService] %s moved %.0f studs in %.2fs (allowed %.0f)", player.Name, flat, dt, allowed))
			root.CFrame = CFrame.new(entry.LastPos) * root.CFrame.Rotation
			root.AssemblyLinearVelocity = Vector3.zero
			if entry.Violations >= 5 then
				HorseService.Dismount(player, false)
			end
		else
			entry.Violations = math.max(0, entry.Violations - 0.05)
			entry.LastPos = pos
			entry.RideBank += flat
			if entry.RideBank >= 50 then
				local ridden = entry.RideBank
				entry.RideBank = 0
				HorseService.AddHorseXP(player, ridden * H.XPPerStud)
				DataService.AddCounter(player, "Distance", math.floor(ridden))
				Signals.Quest:Fire(player, "Ride", math.floor(ridden))
			end
		end
	end
end

-- Lets other services move a mounted player without tripping the checks.
function HorseService.ResetSanity(player: Player)
	local entry = active[player]
	if entry and entry.Model.PrimaryPart then
		entry.LastPos = (entry.Model.PrimaryPart :: BasePart).Position
		entry.LastCheck = os.clock()
	end
end

function HorseService.Start()
	RunService.Heartbeat:Connect(stepServerHorses)
	task.spawn(function()
		while true do
			task.wait(H.SanityInterval)
			sanity()
		end
	end)
	task.spawn(function()
		while true do
			task.wait(1)
			updateHerds()
		end
	end)
end

return HorseService
