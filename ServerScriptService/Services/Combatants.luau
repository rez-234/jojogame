--!strict
-- Registry and per-fighter state for everything that can deal or take damage:
-- player characters and hostile NPCs. Combat, Stands, NPC AI and PvP all read
-- and write these tables.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local StandData = require(ReplicatedStorage.Shared.StandData)

local Combatants = {}

export type Effect = {
	Until: number,
	Power: number,
	NextTick: number,
	Source: any?,
}

export type HistoryEntry = {
	Time: number,
	CFrame: CFrame,
	Health: number,
}

export type Combatant = {
	Model: Model,
	Humanoid: Humanoid,
	Root: BasePart,
	Player: Player?,
	IsNPC: boolean,
	IsBoss: boolean,
	Name: string,
	Level: number,
	-- Multiplier on all outgoing damage (stat points for players, level for NPCs).
	DamageMult: number,
	BaseWalkSpeed: number,
	BaseJumpPower: number,
	-- Stand
	StandId: string?,
	Family: string?,
	StandModel: Model?,
	StandSummoned: boolean,
	StandDurability: number,
	StandMaxDurability: number,
	StandBrokenUntil: number,
	-- Resources
	Stamina: number,
	StaminaMax: number,
	-- Status
	StunUntil: number,
	ComboStart: number,
	ComboStun: number,
	ComboImmuneUntil: number,
	IFrameUntil: number,
	Blocking: boolean,
	BlockStarted: number,
	BusyUntil: number,
	BusySpeed: number,
	Cooldowns: { [string]: number },
	Effects: { [string]: Effect },
	Counter: { Until: number, Move: StandData.Move, Mult: number }?,
	ErasedUntil: number,
	TimeStoppedUntil: number,
	SpeedBuff: { Until: number, Power: number }?,
	ProtectedUntil: number,
	LastAttacker: Combatant?,
	LastAttackTime: number,
	LastHitMove: string?,
	Contributors: { [Combatant]: number },
	Mounted: Model?,
	History: { HistoryEntry },
	PunchIndex: number,
	LastPunch: number,
	Dead: boolean,
	-- Free slot for the owning service (NPC brain, boss data).
	Data: { [string]: any },
}

local byModel: { [Model]: Combatant } = {}
local byPlayer: { [Player]: Combatant } = {}
local modelList: { Model } = {}

local listChanged: { () -> () } = {}

local function notifyList()
	for _, fn in listChanged do
		task.spawn(fn)
	end
end

export type RegisterOptions = {
	Player: Player?,
	Name: string?,
	Level: number?,
	DamageMult: number?,
	IsBoss: boolean?,
	StaminaMax: number?,
}

function Combatants.Register(model: Model, opts: RegisterOptions): Combatant?
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not root then
		return nil
	end
	local existing = byModel[model]
	if existing then
		return existing
	end
	local c: Combatant = {
		Model = model,
		Humanoid = humanoid,
		Root = root,
		Player = opts.Player,
		IsNPC = opts.Player == nil,
		IsBoss = opts.IsBoss == true,
		Name = opts.Name or model.Name,
		Level = opts.Level or 1,
		DamageMult = opts.DamageMult or 1,
		BaseWalkSpeed = humanoid.WalkSpeed,
		BaseJumpPower = if humanoid.UseJumpPower then humanoid.JumpPower else 50,
		StandId = nil,
		Family = nil,
		StandModel = nil,
		StandSummoned = false,
		StandDurability = 100,
		StandMaxDurability = 100,
		StandBrokenUntil = 0,
		Stamina = opts.StaminaMax or 100,
		StaminaMax = opts.StaminaMax or 100,
		StunUntil = 0,
		ComboStart = 0,
		ComboStun = 0,
		ComboImmuneUntil = 0,
		IFrameUntil = 0,
		Blocking = false,
		BlockStarted = 0,
		BusyUntil = 0,
		BusySpeed = 1,
		Cooldowns = {},
		Effects = {},
		Counter = nil,
		ErasedUntil = 0,
		TimeStoppedUntil = 0,
		SpeedBuff = nil,
		ProtectedUntil = 0,
		LastAttacker = nil,
		LastAttackTime = 0,
		LastHitMove = nil,
		Contributors = {},
		Mounted = nil,
		History = {},
		PunchIndex = 0,
		LastPunch = 0,
		Dead = false,
		Data = {},
	}
	byModel[model] = c
	if c.Player then
		byPlayer[c.Player] = c
	end
	table.insert(modelList, model)
	notifyList()
	model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			Combatants.Unregister(model)
		end
	end)
	return c
end

function Combatants.Unregister(model: Model)
	local c = byModel[model]
	if not c then
		return
	end
	byModel[model] = nil
	if c.Player and byPlayer[c.Player] == c then
		byPlayer[c.Player] = nil
	end
	local index = table.find(modelList, model)
	if index then
		table.remove(modelList, index)
	end
	c.Dead = true
	notifyList()
end

function Combatants.Get(model: Instance?): Combatant?
	if model and model:IsA("Model") then
		return byModel[model]
	end
	return nil
end

-- Finds the combatant owning a part (walks up to the registered model).
function Combatants.FromPart(part: Instance): Combatant?
	local current: Instance? = part
	while current and current ~= workspace do
		if current:IsA("Model") then
			local c = byModel[current]
			if c then
				return c
			end
		end
		current = current.Parent
	end
	return nil
end

function Combatants.ForPlayer(player: Player): Combatant?
	return byPlayer[player]
end

function Combatants.All(): { [Model]: Combatant }
	return byModel
end

function Combatants.Models(): { Model }
	return modelList
end

function Combatants.OnListChanged(fn: () -> ())
	table.insert(listChanged, fn)
end

function Combatants.IsAlive(c: Combatant?): boolean
	return c ~= nil and not c.Dead and c.Humanoid.Health > 0 and c.Model.Parent ~= nil
end

function Combatants.IsStunned(c: Combatant): boolean
	return os.clock() < c.StunUntil or os.clock() < c.TimeStoppedUntil
end

function Combatants.IsBusy(c: Combatant): boolean
	return os.clock() < c.BusyUntil
end

function Combatants.IsErased(c: Combatant): boolean
	return os.clock() < c.ErasedUntil
end

function Combatants.HasEffect(c: Combatant, name: string): boolean
	local e = c.Effects[name]
	return e ~= nil and os.clock() < e.Until
end

function Combatants.Cooldown(c: Combatant, key: string): number
	return math.max(0, (c.Cooldowns[key] or 0) - os.clock())
end

function Combatants.SetCooldown(c: Combatant, key: string, seconds: number)
	c.Cooldowns[key] = os.clock() + seconds
end

-- Recomputes walk speed and jump power from every active modifier.
function Combatants.ApplyMovement(c: Combatant)
	if c.Dead then
		return
	end
	local now = os.clock()
	local speed = c.BaseWalkSpeed
	local jump = c.BaseJumpPower
	if now < c.StunUntil or now < c.TimeStoppedUntil then
		speed = 0
		jump = 0
	else
		local slow = c.Effects.Slow
		if slow and now < slow.Until then
			speed *= math.clamp(1 - slow.Power, 0.2, 1)
		end
		local spin = c.Effects.Spin
		if spin and now < spin.Until then
			speed *= 0.85
		end
		if c.SpeedBuff and now < c.SpeedBuff.Until then
			speed *= 1 + c.SpeedBuff.Power
		end
		if now < c.BusyUntil then
			speed *= c.BusySpeed
			jump = 0
		end
		if c.Blocking then
			speed = math.min(speed, Config.Combat.BlockWalkSpeed)
			jump = 0
		end
	end
	if c.Humanoid.WalkSpeed ~= speed then
		c.Humanoid.WalkSpeed = speed
	end
	if c.Humanoid.UseJumpPower then
		if c.Humanoid.JumpPower ~= jump then
			c.Humanoid.JumpPower = jump
		end
	else
		local height = jump / 50 * 7.2
		if c.Humanoid.JumpHeight ~= height then
			c.Humanoid.JumpHeight = height
		end
	end
end

-- Facing direction on the ground plane.
function Combatants.Look(c: Combatant): Vector3
	local look = c.Root.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 1e-3 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

return Combatants
