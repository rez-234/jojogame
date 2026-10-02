--!strict
-- Server side networking: one RemoteEvent for gameplay input and one
-- RemoteFunction for menu requests. Every handler is rate limited per player
-- and wrapped so a bad payload can never break the dispatcher.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)

local Net = {}

type ActionHandler = (Player, ...any) -> ()
type RequestHandler = (Player, ...any) -> any

local actions: { [string]: ActionHandler } = {}
local requests: { [string]: RequestHandler } = {}

type Bucket = { Tokens: number, Last: number }
local actionBuckets: { [Player]: Bucket } = {}
local requestBuckets: { [Player]: Bucket } = {}

local function take(buckets: { [Player]: Bucket }, player: Player, burst: number, refill: number): boolean
	local now = os.clock()
	local b = buckets[player]
	if not b then
		b = { Tokens = burst, Last = now }
		buckets[player] = b
	end
	b.Tokens = math.min(burst, b.Tokens + (now - b.Last) * refill)
	b.Last = now
	if b.Tokens < 1 then
		return false
	end
	b.Tokens -= 1
	return true
end

function Net.OnAction(name: string, handler: ActionHandler)
	actions[name] = handler
end

function Net.OnRequest(name: string, handler: RequestHandler)
	requests[name] = handler
end

-- Argument validators.
function Net.IsVector(v: any, maxMagnitude: number?): boolean
	if typeof(v) ~= "Vector3" then
		return false
	end
	local vec = v :: Vector3
	if vec.X ~= vec.X or vec.Y ~= vec.Y or vec.Z ~= vec.Z then
		return false
	end
	if maxMagnitude and vec.Magnitude > maxMagnitude then
		return false
	end
	return true
end

function Net.IsString(v: any, maxLength: number?): boolean
	return type(v) == "string" and #v <= (maxLength or 64)
end

function Net.IsNumber(v: any, min: number?, max: number?): boolean
	if type(v) ~= "number" or v ~= v then
		return false
	end
	if min and v < min then
		return false
	end
	if max and v > max then
		return false
	end
	return true
end

local syncEvent: RemoteEvent
local fxEvent: RemoteEvent
local notifyEvent: RemoteEvent

function Net.Init()
	local actionEvent = Remotes.Event("Action")
	local request = Remotes.Function("Request")
	syncEvent = Remotes.Event("Sync")
	fxEvent = Remotes.Event("FX")
	notifyEvent = Remotes.Event("Notify")

	actionEvent.OnServerEvent:Connect(function(player: Player, name: any, ...: any)
		if type(name) ~= "string" then
			return
		end
		local handler = actions[name]
		if not handler then
			return
		end
		if not take(actionBuckets, player, Config.Combat.InputBurst, Config.Combat.InputRefillPerSecond) then
			return
		end
		local ok, err = pcall(handler :: any, player, ...)
		if not ok then
			warn("[Net] action", name, "failed:", err)
		end
	end)

	request.OnServerInvoke = function(player: Player, name: any, ...: any): any
		if type(name) ~= "string" then
			return { Ok = false, Error = "Bad request" }
		end
		local handler = requests[name]
		if not handler then
			return { Ok = false, Error = "Unknown request" }
		end
		if not take(requestBuckets, player, 10, 4) then
			return { Ok = false, Error = "Slow down" }
		end
		local ok, result = pcall(handler, player, ...)
		if not ok then
			warn("[Net] request", name, "failed:", result)
			return { Ok = false, Error = "Something went wrong" }
		end
		return result
	end

	Players.PlayerRemoving:Connect(function(player)
		actionBuckets[player] = nil
		requestBuckets[player] = nil
	end)
end

function Net.Sync(player: Player, payload: any)
	syncEvent:FireClient(player, payload)
end

function Net.FX(kind: string, data: any)
	fxEvent:FireAllClients(kind, data)
end

function Net.FXTo(player: Player, kind: string, data: any)
	fxEvent:FireClient(player, kind, data)
end

function Net.Notify(player: Player, kind: string, data: any)
	notifyEvent:FireClient(player, kind, data)
end

function Net.NotifyAll(kind: string, data: any)
	notifyEvent:FireAllClients(kind, data)
end

-- Short message toast for one player.
function Net.Toast(player: Player, text: string, tone: string?)
	notifyEvent:FireClient(player, "Toast", { Text = text, Tone = tone or "Info" })
end

function Net.Ok(data: any?): any
	return { Ok = true, Data = data }
end

function Net.Fail(message: string): any
	return { Ok = false, Error = message }
end

return Net
