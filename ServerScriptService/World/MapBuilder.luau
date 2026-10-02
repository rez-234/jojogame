--!strict
-- Builds the whole map from the seed in Config: terrain, trail, landmarks,
-- towns, props and lighting. Progress is published on ReplicatedStorage so the
-- loading screen can show it. Everything yields regularly so the server never
-- stalls while generating.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PartUtil = require(ReplicatedStorage.Builders.PartUtil)
local Route = require(ReplicatedStorage.Shared.Route)
local Layout = require(ReplicatedStorage.Shared.Layout)
local TerrainGen = require(script.Parent.TerrainGen)
local TrailBuilder = require(script.Parent.TrailBuilder)
local Landmarks = require(script.Parent.Landmarks)
local TownBuilder = require(script.Parent.TownBuilder)
local Scatter = require(script.Parent.Scatter)
local AtmosphereBuilder = require(script.Parent.AtmosphereBuilder)

local MapBuilder = {}

local readyEvent = Instance.new("BindableEvent")
local ready = false
MapBuilder.Folder = nil :: Folder?

local function setProgress(stage: string, fraction: number)
	ReplicatedStorage:SetAttribute("MapStage", stage)
	ReplicatedStorage:SetAttribute("MapProgress", math.clamp(fraction, 0, 1))
end

local function anchorAll(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			-- Windmill blades are welded to an anchored hub and spin on clients.
			if not (d.Name == "Blade") then
				d.Anchored = true
			end
		end
	end
end

function MapBuilder.Build()
	local started = os.clock()
	ReplicatedStorage:SetAttribute("MapReady", false)
	local map = PartUtil.folder("Map", workspace)
	MapBuilder.Folder = map

	setProgress("Lighting", 0)
	AtmosphereBuilder.Build()

	setProgress("Shaping the land", 0)
	TerrainGen.Generate(function(f)
		setProgress("Shaping the land", f * 0.55)
	end)

	setProgress("Laying the trail", 0.55)
	TrailBuilder.Build(map, function(f)
		setProgress("Laying the trail", 0.55 + f * 0.1)
	end)

	setProgress("Raising landmarks", 0.65)
	local landmarkFolder = PartUtil.folder("Landmarks", map)
	Landmarks.buildStartLine(landmarkFolder)
	task.wait()
	for _, cp in Layout.Checkpoints do
		if cp.Name == "Finish" then
			Landmarks.buildFinishArch(landmarkFolder)
		else
			Landmarks.buildCheckpointGate(cp, landmarkFolder)
		end
	end
	task.wait()
	for i, lm in Layout.Landmarks do
		Landmarks.build(lm, landmarkFolder)
		setProgress("Raising landmarks", 0.65 + i / #Layout.Landmarks * 0.04)
		task.wait()
	end
	for _, arena in Layout.Arenas do
		Landmarks.buildBossArena(arena, landmarkFolder)
	end
	Landmarks.buildPvPArena(landmarkFolder)
	task.wait()

	setProgress("Building towns", 0.7)
	TownBuilder.Build(map, function(f)
		setProgress("Building towns", 0.7 + f * 0.15)
	end)

	setProgress("Scattering the wild", 0.85)
	local _, propCount = Scatter.Build(map, function(f)
		setProgress("Scattering the wild", 0.85 + f * 0.14)
	end)

	anchorAll(map)
	AtmosphereBuilder.StartCycle()
	setProgress("Ready", 1)
	ReplicatedStorage:SetAttribute("MapReady", true)
	ready = true
	readyEvent:Fire()
	print(string.format("[MapBuilder] Route %.0f studs, %d props, built in %.1fs", Route.Length, propCount, os.clock() - started))
end

function MapBuilder.IsReady(): boolean
	return ready
end

function MapBuilder.WaitUntilReady()
	if not ready then
		readyEvent.Event:Wait()
	end
end

return MapBuilder
