--!strict
-- Client entry point. Starts every controller and UI module in order; one
-- failing module is reported and the rest still start.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

-- Make sure the server has created the remotes.
require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Remotes"))

local Controllers = script.Parent:WaitForChild("Controllers")
local UI = script.Parent:WaitForChild("UI")

local State = require(Controllers:WaitForChild("State"))
local HorseController = require(Controllers:WaitForChild("HorseController"))
local InputController = require(Controllers:WaitForChild("InputController"))
local CameraController = require(Controllers:WaitForChild("CameraController"))
local HorseAnimator = require(Controllers:WaitForChild("HorseAnimator"))
local StandAnimator = require(Controllers:WaitForChild("StandAnimator"))
local RigAnimator = require(Controllers:WaitForChild("RigAnimator"))
local FXController = require(Controllers:WaitForChild("FXController"))
local AmbienceController = require(Controllers:WaitForChild("AmbienceController"))

local Kit = require(UI:WaitForChild("Kit"))
local Hud = require(UI:WaitForChild("Hud"))
local Feed = require(UI:WaitForChild("Feed"))
local HorseHud = require(UI:WaitForChild("HorseHud"))
local RaceHud = require(UI:WaitForChild("RaceHud"))
local Map = require(UI:WaitForChild("Map"))
local TameGame = require(UI:WaitForChild("TameGame"))
local Menu = require(UI:WaitForChild("Menu"))
local Prompts = require(UI:WaitForChild("Prompts"))

local function step(name: string, fn: () -> ())
	local ok, err = pcall(fn :: any)
	if not ok then
		warn(string.format("[Client] %s failed: %s", name, tostring(err)))
	end
end

-- The default backpack is unused; the hotbar replaces it.
pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

step("State", State.Init)
step("HorseController", HorseController.Init)
step("InputController", InputController.Init)
step("CameraController", CameraController.Init)
step("HorseAnimator", HorseAnimator.Init)
step("StandAnimator", StandAnimator.Init)
step("RigAnimator", RigAnimator.Init)
step("FXController", FXController.Init)
step("AmbienceController", AmbienceController.Init)

step("Feed", Feed.Init)
step("Hud", Hud.Init)
step("RaceHud", RaceHud.Init)
step("Map", function()
	Map.Init(Kit.Screen("SBR_Map", 2))
end)
step("HorseHud", function()
	HorseHud.Init(Kit.Screen("SBR_Ride", 2))
end)
step("TameGame", function()
	TameGame.Init(Kit.Screen("SBR_Tame", 6))
end)
step("Menu", Menu.Init)
step("Prompts", Prompts.Init)
