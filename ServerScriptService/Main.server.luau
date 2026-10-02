--!strict
-- Server entry point. Initializes every service, builds the map from the
-- seed, then starts spawning players and NPCs.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Creates the remote folder before anything else asks for it.
require(ReplicatedStorage.Shared.Remotes)

local Services = ServerScriptService:WaitForChild("Services")
local World = ServerScriptService:WaitForChild("World")

local Net = require(Services.Net)
local DataService = require(Services.DataService)
local MasteryService = require(Services.MasteryService)
local SkinService = require(Services.SkinService)
local LevelService = require(Services.LevelService)
local CombatService = require(Services.CombatService)
local Projectiles = require(Services.Projectiles)
local StandService = require(Services.StandService)
local CharacterService = require(Services.CharacterService)
local HorseService = require(Services.HorseService)
local NPCService = require(Services.NPCService)
local QuestService = require(Services.QuestService)
local ShopService = require(Services.ShopService)
local RaceService = require(Services.RaceService)
local PvPService = require(Services.PvPService)
local MapBuilder = require(World.MapBuilder)

local function step(name: string, fn: () -> ())
	local ok, err = pcall(fn :: any)
	if not ok then
		warn(string.format("[Main] %s failed: %s", name, tostring(err)))
	end
end

-- 1. Wire up services. Order matters only where hooks are set.
step("Net", Net.Init)
step("DataService", DataService.Init)
step("MasteryService", MasteryService.Init)
step("SkinService", SkinService.Init)
step("LevelService", LevelService.Init)
step("CombatService", CombatService.Init)
step("StandService", StandService.Init)
step("CharacterService", CharacterService.Init)
step("HorseService", HorseService.Init)
step("NPCService", NPCService.Init)
step("QuestService", QuestService.Init)
step("ShopService", ShopService.Init)
step("RaceService", RaceService.Init)
step("PvPService", PvPService.Init)

-- 2. Start loading profiles and the simulation loops while the map builds.
step("DataService.Start", DataService.Start)
step("CombatService.Start", CombatService.Start)
step("Projectiles.Start", Projectiles.Start)
step("HorseService.Start", HorseService.Start)

-- 3. Build the world. This yields regularly and publishes progress.
local ok, err = pcall(MapBuilder.Build :: any)
if not ok then
	warn("[Main] map build failed: " .. tostring(err))
	ReplicatedStorage:SetAttribute("MapError", tostring(err))
	ReplicatedStorage:SetAttribute("MapReady", true)
end

-- 4. Spawn players and populate the world.
step("CharacterService.Start", CharacterService.Start)
step("NPCService.Start", NPCService.Start)
step("RaceService.Start", RaceService.Start)
step("PvPService.Start", PvPService.Start)

print("[Main] Steel Ball Run server ready")
