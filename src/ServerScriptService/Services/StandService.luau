--!strict
-- Stands: Arrow rolls weighted by rarity, Rokakaka removal, storage,
-- evolution, summoning and following, and move use with cooldowns.
-- The Stand model follows its user through AlignPosition and AlignOrientation
-- constraints and is owned by the user's client so it moves smoothly; every
-- clients animates it from the Pose attributes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Util = require(ReplicatedStorage.Shared.Util)
local StandData = require(ReplicatedStorage.Shared.StandData)
local SkinData = require(ReplicatedStorage.Shared.SkinData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local StandBuilder = require(ReplicatedStorage.Builders.StandBuilder)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Net)
local Signals = require(script.Parent.Signals)
local Combatants = require(script.Parent.Combatants)
local CombatService = require(script.Parent.CombatService)
local MasteryService = require(script.Parent.MasteryService)
local SkinService = require(script.Parent.SkinService)
local Moves = require(script.Parent.Moves)

type Combatant = Combatants.Combatant

local StandService = {}

local standsFolder: Folder

local ATTACK_POSES = { Punch = true, Barrage = true, Heavy = true, Point = true, Dash = true, Counter = true, Block = true }

-- Sets the Stand id on a fighter and resets durability.
function StandService.Setup(c: Combatant, standId: string?)
	local s = StandData.Get(standId)
	c.StandId = if s then s.Id else nil
	c.Family = if s then s.Family else nil
	c.StandMaxDurability = if s then Progression.StandDurability(s) else Config.Stand.BaseDurability
	c.StandDurability = c.StandMaxDurability
	c.Model:SetAttribute("Stand", if s then s.Id else "")
	c.Model:SetAttribute("StandName", if s then s.Name else "")
end

local function followAttachment(c: Combatant): Attachment
	local existing = c.Root:FindFirstChild("StandFollow")
	if existing and existing:IsA("Attachment") then
		return existing
	end
	local att = Instance.new("Attachment")
	att.Name = "StandFollow"
	att.Position = Config.Stand.FollowOffset
	att.Parent = c.Root
	return att
end

export type SummonOptions = {
	Look: StandData.Look?,
	Skin: SkinData.Skin?,
	Perfected: boolean?,
}

function StandService.Summon(c: Combatant, opts: SummonOptions?)
	if c.StandSummoned or c.Dead then
		return
	end
	local o: SummonOptions = opts or {}
	local source: string | StandData.Look
	if o.Look then
		source = o.Look
	elseif c.StandId then
		source = c.StandId
	else
		return
	end
	local skin = o.Skin
	local perfected = o.Perfected
	if c.Player and c.Family then
		skin = skin or SkinService.Equipped(c.Player, c.Family)
		if perfected == nil then
			perfected = MasteryService.AnyPerfected(c.Player, c.Family)
		end
	end
	local model = StandBuilder.Build(source, { Skin = skin, Perfected = perfected })
	model.Name = c.Name .. " Stand"
	local root = model.PrimaryPart :: BasePart
	local follow = followAttachment(c)
	follow.Position = Config.Stand.FollowOffset
	model:PivotTo(c.Root.CFrame * CFrame.new(Config.Stand.FollowOffset))

	local ownerRef = Instance.new("ObjectValue")
	ownerRef.Name = "Owner"
	ownerRef.Value = c.Model
	ownerRef.Parent = model
	model:SetAttribute("OwnerId", if c.Player then c.Player.UserId else 0)
	model:SetAttribute("Pose", "Idle")
	model:SetAttribute("PoseAt", workspace:GetServerTimeNow())

	local a0 = Instance.new("Attachment")
	a0.Name = "Follow"
	a0.Parent = root
	local ap = Instance.new("AlignPosition")
	ap.Name = "FollowPosition"
	ap.Attachment0 = a0
	ap.Attachment1 = follow
	ap.Responsiveness = Config.Stand.FollowResponsiveness
	ap.MaxForce = 1e6
	ap.MaxVelocity = 400
	ap.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "FollowOrientation"
	ao.Attachment0 = a0
	ao.Attachment1 = follow
	ao.Responsiveness = Config.Stand.FollowResponsiveness
	ao.MaxTorque = 1e6
	ao.Parent = root

	model.Parent = standsFolder
	if c.Player then
		local ok = pcall(function()
			root:SetNetworkOwner(c.Player)
		end)
		if not ok then
			warn("[StandService] could not hand Stand to its owner")
		end
	end
	c.StandModel = model
	c.StandSummoned = true

	-- Step forward for attacks, then return to the shoulder.
	local poseSerial = 0
	model:GetAttributeChangedSignal("PoseAt"):Connect(function()
		poseSerial += 1
		local serial = poseSerial
		local pose = model:GetAttribute("Pose")
		if type(pose) == "string" and ATTACK_POSES[pose] then
			follow.Position = Config.Stand.AttackOffset
			local duration = model:GetAttribute("PoseDuration")
			local hold = if type(duration) == "number" and duration > 0 then duration else 0.45
			if pose == "Block" then
				return
			end
			task.delay(hold, function()
				if serial == poseSerial and follow.Parent then
					follow.Position = Config.Stand.FollowOffset
				end
			end)
		else
			follow.Position = Config.Stand.FollowOffset
		end
	end)
	Net.FX("StandSummon", { Model = c.Model, Stand = model })
end

function StandService.Unsummon(c: Combatant)
	if c.StandModel then
		Net.FX("StandUnsummon", { Model = c.Model, P = (c.StandModel.PrimaryPart :: BasePart).Position })
		c.StandModel:Destroy()
	end
	c.StandModel = nil
	c.StandSummoned = false
	local follow = c.Root:FindFirstChild("StandFollow")
	if follow and follow:IsA("Attachment") then
		follow.Position = Config.Stand.FollowOffset
	end
end

local function refresh(player: Player)
	local profile = DataService.Get(player)
	local c = Combatants.ForPlayer(player)
	if not profile or not c then
		return
	end
	local wasUp = c.StandSummoned
	if wasUp then
		StandService.Unsummon(c)
	end
	StandService.Setup(c, profile.Stand)
	if wasUp and c.StandId then
		StandService.Summon(c)
	end
end

local function onToggle(player: Player)
	local c = Combatants.ForPlayer(player)
	if not c or not Combatants.IsAlive(c) or not c.StandId then
		return
	end
	if Combatants.Cooldown(c, "Summon") > 0 then
		return
	end
	Combatants.SetCooldown(c, "Summon", Config.Stand.SummonCooldown)
	if c.StandSummoned then
		StandService.Unsummon(c)
	else
		if os.clock() < c.StandBrokenUntil then
			Net.Toast(player, "Your Stand is recovering.", "Bad")
			return
		end
		StandService.Summon(c)
	end
end

-- Builds the move context for a player from Stand stats and mastery.
function StandService.ContextFor(player: Player, c: Combatant, move: StandData.Move): Moves.Context
	local s = StandData.Get(c.StandId) :: StandData.Stand
	local tier = MasteryService.Tier(player, c.Family, move.Id)
	local perfected = tier.Index == #Config.Mastery.Tiers
	return {
		Family = c.Family,
		Tier = tier,
		Power = Progression.GradeValue(Config.Stand.PowerGrades, s.Stats.Power) * (1 + tier.Damage),
		Range = Progression.GradeValue(Config.Stand.RangeGrades, s.Stats.Range),
		Speed = Progression.GradeValue(Config.Stand.SpeedGrades, s.Stats.Speed),
		Color = if perfected then Config.Mastery.PerfectedColor else move.Color,
	}
end

local function onMove(player: Player, slot: any, aim: any)
	local c = Combatants.ForPlayer(player)
	if not c or not Combatants.IsAlive(c) or not c.StandId then
		return
	end
	if not Net.IsNumber(slot, 1, 5) then
		return
	end
	if Combatants.IsStunned(c) or Combatants.IsBusy(c) then
		return
	end
	if Combatants.HasEffect(c, "Silence") then
		Net.Toast(player, "Your Stand is silenced.", "Bad")
		return
	end
	if os.clock() < c.StandBrokenUntil then
		Net.Toast(player, "Your Stand is recovering.", "Bad")
		return
	end
	local s = StandData.Get(c.StandId)
	if not s then
		return
	end
	local moveId = s.Moves[math.floor(slot)]
	local move = if moveId then StandData.GetMove(moveId) else nil
	if not move then
		return
	end
	if Combatants.Cooldown(c, move.Id) > 0 then
		return
	end
	local aimPoint: Vector3? = nil
	if Net.IsVector(aim) and ((aim :: Vector3) - c.Root.Position).Magnitude <= Config.Combat.MaxAimDistance then
		aimPoint = aim
	end
	if not c.StandSummoned then
		StandService.Summon(c)
	end
	c.Blocking = false
	local ctx = StandService.ContextFor(player, c, move)
	local cd = Moves.Cooldown(c, move, ctx)
	Combatants.SetCooldown(c, move.Id, cd)
	Net.FXTo(player, "Cooldown", { Move = move.Id, T = cd })
	Moves.Execute(c, move, aimPoint, ctx)
end

function StandService.UseArrow(player: Player): (boolean, string)
	local profile = DataService.Get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	if profile.Stand then
		return false, "You already have a Stand. Eat a Rokakaka or put it in storage first."
	end
	if not DataService.TakeItem(player, "Arrow", 1) then
		return false, "You have no Arrows"
	end
	local pool = StandData.Rollable()
	local rng = Random.new()
	local pick = Util.weightedPick(rng, pool, function(s)
		return (Config.Stand.RarityWeights :: any)[s.Rarity] or 1
	end)
	if not pick then
		DataService.AddItem(player, "Arrow", 1)
		return false, "The Arrow missed"
	end
	profile.Stand = pick.Id
	DataService.MarkDirty(player)
	Net.Notify(player, "StandAwakened", { Id = pick.Id, Name = pick.Name, Rarity = pick.Rarity })
	Signals.StandChanged:Fire(player)
	return true, pick.Name
end

function StandService.UseRokakaka(player: Player): (boolean, string)
	local profile = DataService.Get(player)
	if not profile then
		return false, "Profile not loaded"
	end
	if not profile.Stand then
		return false, "You have no Stand to remove"
	end
	if not Progression.IsUnlocked(profile.Level, "Rokakaka") then
		return false, "Rokakaka unlocks at level " .. Progression.UnlockLevel("Rokakaka")
	end
	if not DataService.TakeItem(player, "Rokakaka", 1) then
		return false, "You have no Rokakaka"
	end
	local old = StandData.Get(profile.Stand)
	profile.Stand = nil
	DataService.MarkDirty(player)
	Net.Notify(player, "StandRemoved", { Name = if old then old.Name else "" })
	Signals.StandChanged:Fire(player)
	return true, "Your Stand is gone"
end

function StandService.Init()
	local folder = workspace:FindFirstChild("Stands")
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Stands"
		f.Parent = workspace
		folder = f
	end
	standsFolder = folder :: Folder

	CombatService.Hooks.StandBreak = function(c)
		StandService.Unsummon(c)
	end

	Net.OnAction("StandToggle", onToggle)
	Net.OnAction("Move", onMove)

	Net.OnRequest("StoreStand", function(player: Player)
		local profile = DataService.Get(player)
		if not profile or not profile.Stand then
			return Net.Fail("You have no Stand to store")
		end
		if #profile.StandStorage >= Config.Stand.MaxStorage then
			return Net.Fail("Storage is full")
		end
		table.insert(profile.StandStorage, profile.Stand)
		profile.Stand = nil
		DataService.MarkDirty(player)
		Signals.StandChanged:Fire(player)
		return Net.Ok()
	end)

	Net.OnRequest("TakeStand", function(player: Player, index: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsNumber(index, 1, Config.Stand.MaxStorage) then
			return Net.Fail("Bad slot")
		end
		local i = math.floor(index)
		local stored = profile.StandStorage[i]
		if not stored then
			return Net.Fail("That slot is empty")
		end
		if profile.Stand then
			profile.StandStorage[i] = profile.Stand
		else
			table.remove(profile.StandStorage, i)
		end
		profile.Stand = stored
		DataService.MarkDirty(player)
		Signals.StandChanged:Fire(player)
		return Net.Ok()
	end)

	Net.OnRequest("Evolve", function(player: Player)
		local profile = DataService.Get(player)
		if not profile or not profile.Stand then
			return Net.Fail("You have no Stand")
		end
		local s = StandData.Get(profile.Stand)
		if not s or not s.Evolution then
			return Net.Fail("This Stand cannot evolve")
		end
		local ok = Progression.EvolutionStatus(profile, s)
		if not ok then
			return Net.Fail("Requirements are not met yet")
		end
		local nextStand = StandData.Get(s.Evolution.Next)
		if not nextStand then
			return Net.Fail("Unknown evolution")
		end
		for _, r in s.Evolution.Requirements do
			if r.Kind == "Item" then
				DataService.TakeItem(player, r.Id, r.Amount)
			end
		end
		profile.Stand = nextStand.Id
		DataService.MarkDirty(player)
		Net.Notify(player, "Evolved", { From = s.Name, To = nextStand.Name, Id = nextStand.Id })
		Signals.StandChanged:Fire(player)
		return Net.Ok(nextStand.Id)
	end)

	Signals.StandChanged:Connect(refresh)

	Signals.CharacterReady:Connect(function(player)
		local profile = DataService.Get(player)
		local c = Combatants.ForPlayer(player)
		if profile and c then
			StandService.Setup(c, profile.Stand)
		end
	end)

	Signals.Killed:Connect(function(_killer, victim)
		if victim.StandModel then
			StandService.Unsummon(victim)
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		local c = Combatants.ForPlayer(player)
		if c then
			StandService.Unsummon(c)
		end
	end)
end

return StandService
