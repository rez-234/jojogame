--!strict
-- The feel of the land: fog color, haze and tint blend between stages as you
-- ride, darkened by night; wind rises with speed; a small saloon tune plays
-- in towns, sequenced from one bundled note sound; tumbleweeds roll with the
-- wind and windmills and the lighthouse lamp turn. All of it is local.

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Route = require(ReplicatedStorage.Shared.Route)
local Zones = require(ReplicatedStorage.Shared.Zones)
local HeightField = require(ReplicatedStorage.Shared.HeightField)
local Util = require(ReplicatedStorage.Shared.Util)
local State = require(script.Parent.State)
local HorseController = require(script.Parent.HorseController)

local AmbienceController = {}

local camera = workspace.CurrentCamera
local WIND_DIR = Vector3.new(1, 0, 0.3).Unit

AmbienceController.ZoneKind = "Wild"
AmbienceController.Stage = 1

-- Atmosphere ---------------------------------------------------------------------

local function stepAtmosphere(dt: number, position: Vector3)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	local grade = Lighting:FindFirstChild("Grade")
	local a, b, t = Route.StageBlend(position.X, 320)
	local sunY = Lighting:GetSunDirection().Y
	local day = Util.smoothstep(-0.12, 0.25, sunY)
	local k = 1 - math.exp(-1.5 * dt)
	if atmosphere then
		local fog = a.FogColor:Lerp(b.FogColor, t)
		local night = Color3.fromRGB(40, 44, 62)
		local target = night:Lerp(fog, day)
		atmosphere.Color = atmosphere.Color:Lerp(target, k)
		atmosphere.Decay = atmosphere.Decay:Lerp(target:Lerp(Color3.new(0, 0, 0), 0.4), k)
		atmosphere.Density += (Util.lerp(a.FogDensity, b.FogDensity, t) - atmosphere.Density) * k
		atmosphere.Haze += (Util.lerp(a.Haze, b.Haze, t) - atmosphere.Haze) * k
	end
	if grade and grade:IsA("ColorCorrectionEffect") then
		local tint = a.Tint:Lerp(b.Tint, t):Lerp(Color3.fromRGB(205, 214, 255), (1 - day) * 0.6)
		grade.TintColor = grade.TintColor:Lerp(tint, k)
	end
end

-- Wind ---------------------------------------------------------------------------

local wind: Sound

local function stepWind(dt: number, position: Vector3)
	local stage = Route.StageAtX(position.X)
	local speedFrac = 0
	local motor = HorseController.Motor
	if motor then
		speedFrac = math.clamp(motor.Speed / Config.Horse.GallopSpeed, 0, 1.2)
	end
	local altitude = math.clamp((position.Y - 120) / 200, 0, 0.4)
	local target = stage.WindVolume * 0.35 + speedFrac * 0.35 + altitude * 0.3
	local k = 1 - math.exp(-2 * dt)
	wind.Volume += (target - wind.Volume) * k
	wind.PlaybackSpeed += ((0.7 + speedFrac * 0.45) - wind.PlaybackSpeed) * k
end

-- Town music -----------------------------------------------------------------------

-- An original tune on a pentatonic scale. Numbers are semitones from the
-- root, R is a rest. Each step is an eighth note.
local R = -99
local MELODY: { number } = {
	0, R, 3, 5, 7, R, 5, 3,
	5, R, 7, 10, 7, R, R, R,
	12, R, 10, 7, 5, R, 7, 5,
	3, R, 0, 3, 0, R, R, R,
	7, 7, 10, 12, 10, R, 7, 5,
	3, 5, 7, R, 5, R, R, R,
	0, R, 3, 5, 7, 10, 7, 5,
	3, R, 5, 3, 0, R, R, R,
}
local BASS: { number } = { 0, 0, 5, 0, 7, 5, 0, 0 }
local STEP_SECONDS = 60 / 112 / 2

local musicVolume = 0
local musicTarget = 0

local function note(semitones: number, volume: number, parent: Instance)
	local s = Instance.new("Sound")
	s.SoundId = Config.Sounds.Note
	s.PlaybackSpeed = 2 ^ (semitones / 12)
	s.Volume = volume
	s.Parent = parent
	s:Play()
	s.Ended:Once(function()
		s:Destroy()
	end)
	task.delay(3, function()
		if s.Parent then
			s:Destroy()
		end
	end)
end

local function runMusic()
	local holder = Instance.new("Folder")
	holder.Name = "TownMusicNotes"
	holder.Parent = SoundService
	local step = 0
	while true do
		task.wait(STEP_SECONDS)
		musicVolume += (musicTarget - musicVolume) * 0.15
		if musicVolume < 0.01 then
			step = 0
			continue
		end
		step += 1
		local m = MELODY[(step - 1) % #MELODY + 1]
		if m ~= R then
			-- Root sits a fourth below the bundled note's pitch.
			note(m - 5, musicVolume, holder)
		end
		if (step - 1) % 4 == 0 then
			local bar = math.floor((step - 1) / 8) % #BASS + 1
			note(BASS[bar] - 17, musicVolume * 0.7, holder)
		end
	end
end

-- Tumbleweeds and spinners ----------------------------------------------------------

type Weed = {
	Model: Model,
	Base: CFrame,
	Travel: number,
	Speed: number,
	Radius: number,
	Spin: number,
}

local weeds: { [Model]: Weed } = {}

local function addWeed(inst: Instance)
	if not inst:IsA("Model") or weeds[inst] then
		return
	end
	local core = inst.PrimaryPart
	if not core then
		return
	end
	weeds[inst] = {
		Model = inst,
		Base = inst:GetPivot(),
		Travel = math.random() * 80,
		Speed = 6 + math.random() * 5,
		Radius = core.Size.X / 1.2,
		Spin = 0,
	}
end

local function stepWeeds(dt: number, camPos: Vector3)
	for model, w in weeds do
		if not model.Parent then
			weeds[model] = nil
			continue
		end
		if (w.Base.Position - camPos).Magnitude > 260 then
			continue
		end
		w.Travel += w.Speed * dt
		if w.Travel > 90 then
			w.Travel = 0
		end
		local along = WIND_DIR * w.Travel
		local x = w.Base.Position.X + along.X
		local z = w.Base.Position.Z + along.Z
		local ground = HeightField.Surface(x, z)
		-- Rise out of the grass at the start of a run and sink at the end.
		local emerge = math.min(1, w.Travel / 10) * math.min(1, (90 - w.Travel) / 10)
		local bounce = math.abs(math.sin(w.Travel * 0.45)) * 1.4
		local y = ground + w.Radius * (2 * emerge - 1) + bounce * emerge
		w.Spin += w.Speed * dt / math.max(0.5, w.Radius)
		local axis = Vector3.new(-WIND_DIR.Z, 0, WIND_DIR.X)
		model:PivotTo(CFrame.new(x, y, z) * CFrame.fromAxisAngle(axis, w.Spin))
	end
end

type Spinner = { Part: BasePart, Base: CFrame, Rate: number, Angle: number }
local spinners: { [BasePart]: Spinner } = {}

local function addSpinner(inst: Instance)
	if not inst:IsA("BasePart") or spinners[inst] then
		return
	end
	spinners[inst] = {
		Part = inst,
		Base = inst.CFrame,
		Rate = if inst.Name == "Lamp" then 0.8 else 1.4 + math.random() * 0.4,
		Angle = math.random() * math.pi * 2,
	}
end

local function stepSpinners(dt: number, camPos: Vector3)
	for part, s in spinners do
		if not part.Parent then
			spinners[part] = nil
			continue
		end
		if (s.Base.Position - camPos).Magnitude > 600 then
			continue
		end
		s.Angle = (s.Angle + s.Rate * dt) % (math.pi * 2)
		part.CFrame = s.Base * CFrame.Angles(s.Angle, 0, 0)
	end
end

local function watchTag(tag: string, fn: (Instance) -> ())
	for _, inst in CollectionService:GetTagged(tag) do
		fn(inst)
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(fn)
end

function AmbienceController.Init()
	local w = Instance.new("Sound")
	w.Name = "SBR_Wind"
	w.SoundId = Config.Sounds.Wind
	w.Looped = true
	w.Volume = 0
	w.Parent = SoundService
	w:Play()
	wind = w

	watchTag("SBR_Tumbleweed", addWeed)
	watchTag("SBR_Spinner", addSpinner)
	task.spawn(runMusic)

	-- Zone checks are cheap but need not run every frame.
	task.spawn(function()
		while true do
			task.wait(0.5)
			local _, _, root = State.Character()
			if root then
				local info = Zones.Classify(root.Position)
				AmbienceController.ZoneKind = info.Kind
				AmbienceController.Stage = info.Stage
				musicTarget = if info.Kind == "Town" or info.Kind == "Start" then 0.18 else 0
			end
		end
	end)

	RunService.Heartbeat:Connect(function(dt: number)
		local camPos = camera.CFrame.Position
		local _, _, root = State.Character()
		local position = if root then root.Position else camPos
		stepAtmosphere(dt, position)
		stepWind(dt, position)
		stepWeeds(dt, camPos)
		stepSpinners(dt, camPos)
	end)
end

return AmbienceController
