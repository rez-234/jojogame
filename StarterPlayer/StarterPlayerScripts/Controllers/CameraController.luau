--!strict
-- Camera feel: field of view widens with horse speed, the view shakes on
-- hard landings, heavy hits and explosions, and a short zoom punch marks big
-- moments. Shake goes through Humanoid.CameraOffset so it never fights the
-- default camera scripts.

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local State = require(script.Parent.State)
local HorseController = require(script.Parent.HorseController)

local CameraController = {}

local BASE_FOV = 70
local MAX_EXTRA_FOV = 16

local camera = workspace.CurrentCamera
local trauma = 0
local fovKick = 0
local currentFov = BASE_FOV

-- Adds screen shake. Amount 0..1; it decays on its own.
function CameraController.Shake(amount: number)
	trauma = math.clamp(trauma + amount, 0, 1)
end

-- Shake scaled by how close a world point is to the camera.
function CameraController.ShakeAt(position: Vector3, amount: number, radius: number)
	local d = (camera.CFrame.Position - position).Magnitude
	if d < radius then
		CameraController.Shake(amount * (1 - d / radius))
	end
end

-- A brief widening of the view, for dashes and time stops.
function CameraController.Kick(degrees: number)
	fovKick = math.max(fovKick, degrees)
end

function CameraController.Init()
	HorseController.Landed:Connect(function(impact: number)
		if impact > 20 then
			CameraController.Shake(math.clamp(impact / 120, 0.1, 0.5))
		end
	end)

	local seed = math.random() * 100
	RunService.RenderStepped:Connect(function(dt: number)
		local _, humanoid = State.Character()
		-- Field of view by riding speed.
		local target = BASE_FOV
		local motor = HorseController.Motor
		if motor then
			local frac = math.clamp(motor.Speed / (Config.Horse.GallopSpeed * 1.1), 0, 1)
			target += MAX_EXTRA_FOV * frac * frac
		end
		fovKick = math.max(0, fovKick - dt * 30)
		target += fovKick
		currentFov += (target - currentFov) * (1 - math.exp(-5 * dt))
		camera.FieldOfView = currentFov

		-- Trauma based shake: offset grows with the square of trauma.
		trauma = math.max(0, trauma - dt * 1.6)
		if humanoid then
			local shake = trauma * trauma
			if shake > 0.001 then
				local t = os.clock() * 28
				local offset = Vector3.new(
					math.noise(seed, t) * 1.2,
					math.noise(seed + 10, t) * 0.9,
					math.noise(seed + 20, t) * 0.6
				) * shake
				humanoid.CameraOffset = offset
			elseif humanoid.CameraOffset ~= Vector3.zero then
				humanoid.CameraOffset = Vector3.zero
			end
		end
	end)
end

return CameraController
