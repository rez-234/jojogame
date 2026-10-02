--!strict
-- Client side state: the latest profile from the server, move cooldowns,
-- riding and race state, and a safe wrapper around server requests.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Signal = require(ReplicatedStorage.Shared.Signal)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local State = {}

State.Player = Players.LocalPlayer
State.Profile = nil :: Types.Profile?
State.ProfileChanged = Signal.new() :: Signal.Signal<Types.Profile>

-- Move cooldowns: move id -> os.clock() when ready.
State.Cooldowns = {} :: { [string]: number }
State.CooldownLengths = {} :: { [string]: number }

-- Riding.
State.Horse = nil :: Model?
State.HorseInfo = nil :: any
State.Mounted = Signal.new() :: Signal.Signal<Model?>

-- UI focus: when a menu or typing box is open gameplay keys are ignored.
State.MenuOpen = false
State.Taming = false

local request: RemoteFunction
local action: RemoteEvent

function State.Init()
	request = Remotes.Function("Request")
	action = Remotes.Event("Action")
	Remotes.Event("Sync").OnClientEvent:Connect(function(profile)
		State.Profile = profile
		State.ProfileChanged:Fire(profile)
	end)
end

-- Calls a server request. Always returns a table with Ok and Data or Error.
function State.Request(name: string, ...: any): { Ok: boolean, Data: any, Error: string? }
	local ok, result = pcall(function(...)
		return request:InvokeServer(name, ...)
	end, ...)
	if ok and type(result) == "table" then
		return result
	end
	return { Ok = false, Data = nil, Error = "The server did not answer" }
end

function State.Action(name: string, ...: any)
	action:FireServer(name, ...)
end

function State.Character(): (Model?, Humanoid?, BasePart?)
	local character = State.Player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	return character, humanoid, root
end

function State.CooldownLeft(moveId: string): number
	return math.max(0, (State.Cooldowns[moveId] or 0) - os.clock())
end

function State.SetCooldown(moveId: string, seconds: number)
	State.Cooldowns[moveId] = os.clock() + seconds
	State.CooldownLengths[moveId] = seconds
end

return State
