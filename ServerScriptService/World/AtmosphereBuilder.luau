--!strict
-- Lighting, sky and post effects for a warm western look, plus the server
-- day and night cycle, night lights and the city clock.

local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local AtmosphereBuilder = {}

local function getOrCreate(className: string, name: string): Instance
	local existing = Lighting:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = Lighting
	return inst
end

function AtmosphereBuilder.Build()
	Lighting.ClockTime = Config.World.StartClockTime
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(96, 82, 70)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 128, 110)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 226, 190)
	Lighting.ColorShift_Bottom = Color3.fromRGB(120, 90, 70)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3
	Lighting.GeographicLatitude = 34
	Lighting.ExposureCompensation = 0.1

	local atmosphere = getOrCreate("Atmosphere", "Atmosphere") :: Atmosphere
	atmosphere.Density = 0.3
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(226, 196, 160)
	atmosphere.Decay = Color3.fromRGB(150, 110, 90)
	atmosphere.Glare = 0.35
	atmosphere.Haze = 1.6

	local sky = getOrCreate("Sky", "Sky") :: Sky
	sky.SunAngularSize = 16
	sky.MoonAngularSize = 9
	sky.StarCount = 3500
	sky.CelestialBodiesShown = true

	local cc = getOrCreate("ColorCorrectionEffect", "Grade") :: ColorCorrectionEffect
	cc.Brightness = 0.02
	cc.Contrast = 0.08
	cc.Saturation = -0.05
	cc.TintColor = Color3.fromRGB(255, 240, 222)

	local rays = getOrCreate("SunRaysEffect", "SunRays") :: SunRaysEffect
	rays.Intensity = 0.08
	rays.Spread = 0.6

	local bloom = getOrCreate("BloomEffect", "Bloom") :: BloomEffect
	bloom.Intensity = 0.4
	bloom.Size = 26
	bloom.Threshold = 1.6

	local dof = getOrCreate("DepthOfFieldEffect", "Distance") :: DepthOfFieldEffect
	dof.FarIntensity = 0.12
	dof.FocusDistance = 120
	dof.InFocusRadius = 260
	dof.NearIntensity = 0
end

-- Advances the clock, toggles lamps at dusk and dawn and turns clock hands.
function AtmosphereBuilder.StartCycle()
	local minutesPerSecond = 24 * 60 / (Config.World.DayLengthMinutes * 60)
	local lightsOn: boolean? = nil
	local handTimer = 0
	RunService.Heartbeat:Connect(function(dt: number)
		Lighting:SetMinutesAfterMidnight((Lighting:GetMinutesAfterMidnight() + dt * minutesPerSecond) % 1440)
		local t = Lighting.ClockTime
		local night = t < 6.3 or t > 18.2
		if night ~= lightsOn then
			lightsOn = night
			for _, glass in CollectionService:GetTagged("SBR_NightLight") do
				for _, child in glass:GetChildren() do
					if child:IsA("Light") then
						child.Enabled = night
					end
				end
				if glass:IsA("BasePart") then
					glass.Material = if night then Enum.Material.Neon else Enum.Material.Glass
				end
			end
		end
		handTimer += dt
		if handTimer >= 1 then
			handTimer = 0
			local minutes = Lighting:GetMinutesAfterMidnight()
			for _, hand in CollectionService:GetTagged("SBR_ClockHand") do
				if hand:IsA("BasePart") then
					local pivot = hand:GetAttribute("Pivot")
					if typeof(pivot) == "CFrame" then
						local isHour = hand.Name == "HourHand"
						local angle = if isHour then (minutes / 720) * math.pi * 2 else (minutes % 60) / 60 * math.pi * 2
						local length = hand.Size.Y
						-- Viewed from the front (looking along +Z), positive Z rotation is clockwise.
						hand.CFrame = pivot * CFrame.Angles(0, 0, angle) * CFrame.new(0, length * 0.45, 0)
					end
				end
			end
		end
	end)
end

return AtmosphereBuilder
