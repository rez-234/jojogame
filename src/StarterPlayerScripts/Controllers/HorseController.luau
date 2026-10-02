--!strict
-- Drives the local player's horse while riding. The rider's client owns the
-- horse physics, so this steps the shared HorseMotor every physics frame from
-- keyboard, gamepad or touch input. Space jumps the horse instead of the
-- rider, Shift gallops, R changes the cruising gait and G dismounts.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local HorseMotor = require(ReplicatedStorage.Shared.HorseMotor)
local Signal = require(ReplicatedStorage.Shared.Signal)
local State = require(script.Parent.State)

local HorseController = {}

local player = Players.LocalPlayer

HorseController.Motor = nil :: HorseMotor.State?
HorseController.Cruise = 3
HorseController.Gallop = false
HorseController.Changed = Signal.new() :: Signal.Signal<>
HorseController.Landed = Signal.new() :: Signal.Signal<number>

local CRUISE_NAMES = { "Walk", "Trot", "Canter" }
HorseController.CruiseNames = CRUISE_NAMES

local controls: any = nil
local jumpQueued = false
local stepConn: RBXScriptConnection? = nil
local jumpConn: RBXScriptConnection? = nil
local lastLanded = 0

local function getControls(): any
	if controls then
		return controls
	end
	local ok, module = pcall(function()
		local playerModule = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule")
		return (require :: any)(playerModule):GetControls()
	end)
	if ok then
		controls = module
	end
	return controls
end

local function sink(fn: (Enum.UserInputState) -> ())
	return function(_name: string, inputState: Enum.UserInputState, _input: InputObject)
		fn(inputState)
		return Enum.ContextActionResult.Sink
	end
end

local function bind()
	local high = Enum.ContextActionPriority.High.Value + 50
	ContextActionService:BindActionAtPriority("SBR_HorseJump", sink(function(s)
		if s == Enum.UserInputState.Begin then
			jumpQueued = true
		end
	end), true, high, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	ContextActionService:BindActionAtPriority("SBR_HorseGallop", sink(function(s)
		HorseController.Gallop = s == Enum.UserInputState.Begin or s == Enum.UserInputState.Change
		HorseController.Changed:Fire()
	end), true, high, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
	ContextActionService:BindActionAtPriority("SBR_HorseCruise", sink(function(s)
		if s == Enum.UserInputState.Begin then
			HorseController.Cruise = HorseController.Cruise % 3 + 1
			HorseController.Changed:Fire()
		end
	end), true, high, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority("SBR_HorseDismount", sink(function(s)
		if s == Enum.UserInputState.Begin then
			State.Action("Dismount")
		end
	end), true, high, Enum.KeyCode.G, Enum.KeyCode.ButtonB)
	for name, title in { SBR_HorseJump = "Jump", SBR_HorseGallop = "Gallop", SBR_HorseCruise = "Gait", SBR_HorseDismount = "Off" } do
		ContextActionService:SetTitle(name, title)
	end
	ContextActionService:SetPosition("SBR_HorseGallop", UDim2.new(1, -170, 1, -150))
	ContextActionService:SetPosition("SBR_HorseCruise", UDim2.new(1, -230, 1, -90))
	ContextActionService:SetPosition("SBR_HorseDismount", UDim2.new(1, -110, 1, -210))
end

local function unbind()
	for _, name in { "SBR_HorseJump", "SBR_HorseGallop", "SBR_HorseCruise", "SBR_HorseDismount" } do
		ContextActionService:UnbindAction(name)
	end
	HorseController.Gallop = false
end

local function stop()
	if stepConn then
		stepConn:Disconnect()
		stepConn = nil
	end
	if jumpConn then
		jumpConn:Disconnect()
		jumpConn = nil
	end
	unbind()
	local motor = HorseController.Motor
	if motor and motor.Model.Parent then
		HorseMotor.Enable(motor, false)
	end
	HorseController.Motor = nil
	State.Horse = nil
	State.HorseInfo = nil
	local _, humanoid = State.Character()
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
	end
	State.Mounted:Fire(nil)
	HorseController.Changed:Fire()
end

local function start(data: any)
	stop()
	local horse = data.Horse :: Model?
	if not horse or not horse.PrimaryPart then
		return
	end
	local motor = HorseMotor.new(horse, data.Stats, true)
	HorseController.Motor = motor
	State.Horse = horse
	State.HorseInfo = data
	jumpQueued = false
	lastLanded = motor.LandedAt
	-- Wait for the server to hand over physics before driving.
	task.delay(0.15, function()
		if HorseController.Motor == motor then
			HorseMotor.Enable(motor, true)
		end
	end)
	bind()
	local _, humanoid = State.Character()
	if humanoid then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		jumpConn = humanoid:GetPropertyChangedSignal("Jump"):Connect(function()
			if humanoid.Jump and HorseController.Motor then
				humanoid.Jump = false
			end
		end)
	end
	stepConn = RunService.PreSimulation:Connect(function(dt: number)
		local m = HorseController.Motor
		if not m or not m.Model.Parent or not m.Root.Parent then
			stop()
			return
		end
		if m.Root.Anchored then
			-- Frozen by the server (race start or time stop).
			return
		end
		local move = Vector3.zero
		local c = getControls()
		if c and not State.MenuOpen then
			local ok, v = pcall(function()
				return c:GetMoveVector()
			end)
			if ok and typeof(v) == "Vector3" then
				move = v
			end
		end
		if m.Velocity.MaxForce <= 0 then
			HorseMotor.Enable(m, true)
		end
		HorseMotor.Step(m, dt, {
			Throttle = -move.Z,
			Steer = move.X,
			Gallop = HorseController.Gallop,
			Jump = jumpQueued,
			Cruise = HorseController.Cruise,
		})
		jumpQueued = false
		if m.LandedAt ~= lastLanded then
			lastLanded = m.LandedAt
			HorseController.Landed:Fire(math.abs(m.VY))
		end
	end)
	State.Mounted:Fire(horse)
	HorseController.Changed:Fire()
end

-- Only show the ride prompt on your own horse, and no prompts while riding.
local function updatePrompts()
	for _, horse in CollectionService:GetTagged("SBR_Horse") do
		if horse:IsA("Model") then
			local root = horse.PrimaryPart
			if root then
				local mount = root:FindFirstChild("MountPrompt") :: ProximityPrompt?
				if mount then
					mount.Enabled = horse:GetAttribute("OwnerId") == player.UserId and HorseController.Motor == nil and horse:GetAttribute("RiderId") == 0
				end
				local tame = root:FindFirstChild("TamePrompt") :: ProximityPrompt?
				if tame then
					tame.Enabled = HorseController.Motor == nil and not State.Taming
				end
			end
		end
	end
end

function HorseController.Init()
	local horseEvent = Remotes.Event("Horse")
	horseEvent.OnClientEvent:Connect(function(kind: string, data: any)
		if kind == "Mounted" then
			start(data)
		elseif kind == "Dismounted" then
			stop()
		elseif kind == "Stats" then
			local m = HorseController.Motor
			if m and data and data.Stats then
				m.Stats = data.Stats
				if State.HorseInfo then
					State.HorseInfo.Level = data.Level
				end
				HorseController.Changed:Fire()
			end
		end
	end)
	player.CharacterRemoving:Connect(function()
		stop()
	end)
	task.spawn(function()
		while true do
			updatePrompts()
			task.wait(0.5)
		end
	end)
end

function HorseController.CruiseName(): string
	return CRUISE_NAMES[HorseController.Cruise] or "Canter"
end

return HorseController
