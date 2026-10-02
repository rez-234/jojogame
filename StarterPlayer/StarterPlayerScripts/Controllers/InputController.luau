--!strict
-- Combat and utility input. Keyboard: M1 punch, Z X C V B Stand moves,
-- Q summon, F hold to block, Left Ctrl dodge, H whistle, M menu, P PvP.
-- Gamepad and touch get the same actions through ContextActionService.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local State = require(script.Parent.State)

local InputController = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

InputController.MenuToggled = Signal.new() :: Signal.Signal<>
InputController.TamePressed = Signal.new() :: Signal.Signal<>

local MOVE_KEYS = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V, Enum.KeyCode.B }
InputController.MoveKeys = { "Z", "X", "C", "V", "B" }

local aimParams = RaycastParams.new()
aimParams.FilterType = Enum.RaycastFilterType.Exclude

-- World point under the cursor (or straight ahead on touch and gamepad).
function InputController.AimPoint(): Vector3?
	local character, _, root = State.Character()
	if not character or not root then
		return nil
	end
	local ignore: { Instance } = { character }
	local stands = workspace:FindFirstChild("Stands")
	if stands then
		table.insert(ignore, stands)
	end
	if State.Horse then
		table.insert(ignore, State.Horse)
	end
	aimParams.FilterDescendantsInstances = ignore
	local ray: Ray
	if UserInputService.MouseEnabled and not UserInputService.TouchEnabled then
		local mouse = UserInputService:GetMouseLocation()
		ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	else
		local size = camera.ViewportSize
		ray = camera:ViewportPointToRay(size.X / 2, size.Y * 0.45)
	end
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 400, aimParams)
	if hit then
		return hit.Position
	end
	return ray.Origin + ray.Direction * 120
end

local function canAct(): boolean
	if State.MenuOpen or State.Taming then
		return false
	end
	local character, humanoid = State.Character()
	if not character or not humanoid or humanoid.Health <= 0 then
		return false
	end
	return true
end

local function useMove(slot: number)
	if not canAct() then
		return
	end
	State.Action("Move", slot, InputController.AimPoint())
end

local function punch()
	if not canAct() then
		return
	end
	State.Action("Punch", InputController.AimPoint())
end

local function dodge()
	if not canAct() or State.Horse then
		return
	end
	local _, humanoid, root = State.Character()
	if not humanoid or not root then
		return
	end
	local dir = humanoid.MoveDirection
	if dir.Magnitude < 0.1 then
		dir = root.CFrame.LookVector
	end
	State.Action("Dodge", Vector3.new(dir.X, 0, dir.Z).Unit)
end

local blocking = false
local function setBlock(on: boolean)
	if on and not canAct() then
		return
	end
	if blocking == on then
		return
	end
	blocking = on
	State.Action("Block", on)
end

local function handler(fn: (Enum.UserInputState) -> ())
	return function(_name: string, inputState: Enum.UserInputState, _input: InputObject)
		fn(inputState)
		return Enum.ContextActionResult.Pass
	end
end

function InputController.Init()
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if State.Taming and (input.KeyCode == Enum.KeyCode.E or input.KeyCode == Enum.KeyCode.Space or input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch or input.KeyCode == Enum.KeyCode.ButtonA) then
			InputController.TamePressed:Fire()
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			punch()
		end
		local key = input.KeyCode
		local slot = table.find(MOVE_KEYS, key)
		if slot then
			useMove(slot)
		elseif key == Enum.KeyCode.Q then
			if canAct() then
				State.Action("StandToggle")
			end
		elseif key == Enum.KeyCode.F then
			setBlock(true)
		elseif key == Enum.KeyCode.LeftControl then
			dodge()
		elseif key == Enum.KeyCode.H then
			if canAct() then
				State.Action("Whistle")
			end
		elseif key == Enum.KeyCode.M or key == Enum.KeyCode.Tab then
			InputController.MenuToggled:Fire()
		elseif key == Enum.KeyCode.P then
			if canAct() then
				State.Action("PvPToggle")
			end
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.F then
			setBlock(false)
		end
	end)

	-- Gamepad and touch buttons.
	ContextActionService:BindAction("SBR_Punch", handler(function(s)
		if s == Enum.UserInputState.Begin then
			punch()
		end
	end), true, Enum.KeyCode.ButtonR2)
	ContextActionService:BindAction("SBR_Block", handler(function(s)
		setBlock(s == Enum.UserInputState.Begin)
	end), true, Enum.KeyCode.ButtonL2)
	ContextActionService:BindAction("SBR_Stand", handler(function(s)
		if s == Enum.UserInputState.Begin and canAct() then
			State.Action("StandToggle")
		end
	end), true, Enum.KeyCode.ButtonL1)
	ContextActionService:BindAction("SBR_Whistle", handler(function(s)
		if s == Enum.UserInputState.Begin and canAct() then
			State.Action("Whistle")
		end
	end), true, Enum.KeyCode.DPadDown)
	ContextActionService:BindAction("SBR_Menu", handler(function(s)
		if s == Enum.UserInputState.Begin then
			InputController.MenuToggled:Fire()
		end
	end), false, Enum.KeyCode.ButtonSelect)
	ContextActionService:BindAction("SBR_Dodge", handler(function(s)
		if s == Enum.UserInputState.Begin then
			dodge()
		end
	end), true, Enum.KeyCode.ButtonR1)
	local gamepadMoves = { Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadUp, Enum.KeyCode.DPadRight, Enum.KeyCode.ButtonY, Enum.KeyCode.ButtonR3 }
	for slot, key in gamepadMoves do
		ContextActionService:BindAction("SBR_Move" .. slot, handler(function(s)
			if s == Enum.UserInputState.Begin then
				useMove(slot)
			end
		end), false, key)
	end
	for name, title in { SBR_Punch = "Hit", SBR_Block = "Block", SBR_Stand = "Stand", SBR_Whistle = "Horse", SBR_Dodge = "Dodge" } do
		ContextActionService:SetTitle(name, title)
	end
	ContextActionService:SetPosition("SBR_Punch", UDim2.new(1, -95, 1, -150))
	ContextActionService:SetPosition("SBR_Block", UDim2.new(1, -160, 1, -95))
	ContextActionService:SetPosition("SBR_Stand", UDim2.new(1, -220, 1, -150))
	ContextActionService:SetPosition("SBR_Whistle", UDim2.new(1, -280, 1, -95))
	ContextActionService:SetPosition("SBR_Dodge", UDim2.new(1, -95, 1, -210))

	player.CharacterAdded:Connect(function()
		blocking = false
	end)
end

-- Used by the touch hotbar buttons.
InputController.UseMove = useMove

return InputController
