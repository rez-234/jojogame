--!strict
-- Creates remotes on the server and finds them on the client.
--
-- Action   (client -> server)  combat and riding input, rate limited
-- Request  (client -> server)  menu requests that return a result
-- Sync     (server -> client)  profile snapshots
-- FX       (server -> client)  visual and sound effects
-- Notify   (server -> client)  toasts, kill feed, dialog lines
-- Race     (server -> client)  race state
-- Horse    (server -> client)  horse events for the rider (mounted, thrown, tame minigame)

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = {}

local EVENTS = { "Action", "Sync", "FX", "Notify", "Race", "Horse" }
local FUNCTIONS = { "Request" }

local folder: Folder

if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteEvent")
			r.Name = name
			r.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local r = Instance.new("RemoteFunction")
			r.Name = name
			r.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return Remotes
