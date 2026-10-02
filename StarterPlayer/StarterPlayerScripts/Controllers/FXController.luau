--!strict
-- Every visual and sound effect the server asks for, drawn locally from
-- Parts, particles and engine bundled sounds. Also applies the local player's
-- own dashes and knockback, renders projectiles between server updates and
-- records move cooldowns.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Style = require(ReplicatedStorage.Shared.Style)
local StandData = require(ReplicatedStorage.Shared.StandData)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Signal = require(ReplicatedStorage.Shared.Signal)
local State = require(script.Parent.State)
local CameraController = require(script.Parent.CameraController)
local RigAnimator = require(script.Parent.RigAnimator)
local StandAnimator = require(script.Parent.StandAnimator)

local FXController = {}

-- Fired for every effect after it is drawn, so the UI can react too.
FXController.Event = Signal.new() :: Signal.Signal<string, any>

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local folder: Folder

local WHITE = Color3.fromRGB(244, 236, 218)
local INK = Style.Colors.Ink
local HEAL = Color3.fromRGB(120, 176, 92)

-- Helpers ------------------------------------------------------------------------

type PartProps = {
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Transparency: number?,
	Shape: Enum.PartType?,
}

local function makePart(props: PartProps): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Size = props.Size
	p.CFrame = props.CFrame
	p.Color = props.Color or WHITE
	p.Material = props.Material or Enum.Material.Neon
	p.Transparency = props.Transparency or 0
	if props.Shape then
		p.Shape = props.Shape
	end
	p.Parent = folder
	return p
end

local function tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), goal)
	tw:Play()
	return tw
end

local function fadeOut(p: BasePart, time: number, sizeTo: Vector3?)
	local goal: { [string]: any } = { Transparency = 1 }
	if sizeTo then
		goal.Size = sizeTo
	end
	tween(p, time, goal)
	Debris:AddItem(p, time + 0.05)
end

local function near(position: Vector3, range: number): boolean
	return (camera.CFrame.Position - position).Magnitude < range
end

local function rootOf(model: any): BasePart?
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return nil
	end
	local m = model :: Model
	local root = m:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	return m.PrimaryPart
end

local function isLocal(model: any): boolean
	return model ~= nil and model == player.Character
end

local function color(c: any, fallback: Color3): Color3
	return if typeof(c) == "Color3" then c else fallback
end

local function vec(v: any): Vector3?
	return if typeof(v) == "Vector3" then v else nil
end

local function playAt(soundId: string, position: Vector3, volume: number, speed: number?)
	if not near(position, 160) then
		return
	end
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = workspace.Terrain
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.RollOffMaxDistance = 160
	s.RollOffMinDistance = 8
	s.Parent = a
	s:Play()
	Debris:AddItem(a, 4)
end

local function play2D(soundId: string, volume: number, speed: number?)
	local s = Instance.new("Sound")
	s.SoundId = soundId
	s.Volume = volume
	s.PlaybackSpeed = speed or 1
	s.Parent = workspace.CurrentCamera
	s:Play()
	Debris:AddItem(s, 4)
end

local function emitAt(position: Vector3, texture: string, c: Color3, count: number, speed: number, size: number, lifetime: number?)
	if not near(position, 220) then
		return
	end
	local a = Instance.new("Attachment")
	a.WorldPosition = position
	a.Parent = workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(c)
	e.LightEmission = 0.4
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, size * 0.2) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new((lifetime or 0.5) * 0.6, lifetime or 0.5)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = a
	e:Emit(count)
	Debris:AddItem(a, (lifetime or 0.5) + 0.3)
end

-- Expanding flat disc on the ground: shockwaves and pulses.
local function shockwave(position: Vector3, c: Color3, radius: number, time: number, startTransparency: number?)
	if not near(position, 300) then
		return
	end
	local p = makePart({
		Size = Vector3.new(0.2, 1, 1),
		CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90)),
		Color = c,
		Transparency = startTransparency or 0.35,
		Shape = Enum.PartType.Cylinder,
	})
	fadeOut(p, time, Vector3.new(0.1, radius * 2, radius * 2))
end

local function burstSphere(position: Vector3, c: Color3, radius: number, time: number, material: Enum.Material?)
	if not near(position, 300) then
		return
	end
	local p = makePart({
		Size = Vector3.one * 0.5,
		CFrame = CFrame.new(position),
		Color = c,
		Material = material or Enum.Material.Neon,
		Transparency = 0.2,
		Shape = Enum.PartType.Ball,
	})
	fadeOut(p, time, Vector3.one * radius * 2)
end

local function beam(a: Vector3, b: Vector3, width: number, c: Color3, time: number)
	local length = (b - a).Magnitude
	if length < 0.05 then
		return
	end
	local p = makePart({
		Size = Vector3.new(width, width, length),
		CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = c,
		Transparency = 0.15,
	})
	fadeOut(p, time, Vector3.new(0.05, 0.05, length))
end

-- Floating text in the world: damage numbers and callouts.
local function floatText(position: Vector3, text: string, c: Color3, size: number, time: number, font: Font?)
	if not near(position, 140) then
		return
	end
	local a = Instance.new("Attachment")
	a.WorldPosition = position + Vector3.new((math.random() - 0.5) * 1.5, 2.5, (math.random() - 0.5) * 1.5)
	a.Parent = workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(220, size + 12)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = 140
	gui.Adornee = a
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Text = text
	label.TextColor3 = c
	label.TextSize = size
	label.FontFace = font or Style.Fonts.Numbers
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = INK
	stroke.Thickness = 2
	stroke.Parent = label
	gui.Parent = a
	tween(gui, time, { StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0) })
	task.delay(time * 0.5, function()
		tween(label, time * 0.5, { TextTransparency = 1 })
		tween(stroke, time * 0.5, { Transparency = 1 })
	end)
	Debris:AddItem(a, time + 0.1)
end

local function flash(model: any, c: Color3, time: number, fill: number?)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local root = rootOf(model)
	if not root or not near(root.Position, 150) then
		return
	end
	local h = Instance.new("Highlight")
	h.FillColor = c
	h.OutlineColor = c
	h.FillTransparency = fill or 0.45
	h.OutlineTransparency = 0.2
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Parent = folder
	tween(h, time, { FillTransparency = 1, OutlineTransparency = 1 })
	Debris:AddItem(h, time + 0.05)
end

-- Short lived ghost copies of a model's visible parts.
local function afterimage(model: any, c: Color3, time: number)
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local count = 0
	for _, d in (model :: Model):GetDescendants() do
		if count > 24 then
			break
		end
		if d:IsA("BasePart") and d.Transparency < 0.9 and d.Name ~= "HumanoidRootPart" then
			local ok, clone = pcall(function()
				return d:Clone()
			end)
			if ok and clone then
				local ghost = clone :: BasePart
				ghost:ClearAllChildren()
				ghost.Anchored = true
				ghost.CanCollide = false
				ghost.CanQuery = false
				ghost.CanTouch = false
				ghost.CastShadow = false
				ghost.Material = Enum.Material.Neon
				ghost.Color = c
				ghost.Transparency = 0.55
				ghost.CFrame = d.CFrame
				ghost.Parent = folder
				fadeOut(ghost, time)
				count += 1
			end
		end
	end
end

-- Temporary aura particles on a model.
local function aura(model: any, c: Color3, duration: number, texture: string, rate: number)
	local root = rootOf(model)
	if not root then
		return
	end
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture
	e.Color = ColorSequence.new(c)
	e.LightEmission = 0.5
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Speed = NumberRange.new(1, 4)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 6, 0)
	e.Rate = rate
	e.Parent = root
	task.delay(duration, function()
		e.Enabled = false
		Debris:AddItem(e, 1)
	end)
end

-- Screen grade used by time stop and erasure.
local grade: ColorCorrectionEffect
local gradeToken = 0
local function screenGrade(saturation: number, contrast: number, tint: Color3, duration: number)
	gradeToken += 1
	local token = gradeToken
	tween(grade, 0.25, { Saturation = saturation, Contrast = contrast, TintColor = tint })
	task.delay(duration, function()
		if token == gradeToken then
			tween(grade, 0.5, { Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) })
		end
	end)
end

-- Local movement -----------------------------------------------------------------

local function planarVelocity(root: BasePart, duration: number, velocityAt: (number) -> Vector3)
	local attachment = root:FindFirstChild("RootAttachment") :: Attachment?
	if not attachment then
		local a = Instance.new("Attachment")
		a.Name = "RootAttachment"
		a.Parent = root
		attachment = a
	end
	local lv = Instance.new("LinearVelocity")
	lv.Name = "SBR_Push"
	lv.Attachment0 = attachment
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.MaxForce = root.AssemblyMass * 4000 + 1e5
	local v0 = velocityAt(0)
	lv.PlaneVelocity = Vector2.new(v0.X, v0.Z)
	lv.Parent = root
	local start = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - start
		if t >= duration or not lv.Parent then
			conn:Disconnect()
			lv:Destroy()
			return
		end
		local v = velocityAt(t)
		lv.PlaneVelocity = Vector2.new(v.X, v.Z)
	end)
end

local function localDash(data: any)
	local _, humanoid, root = State.Character()
	local dir = vec(data.Dir)
	if not humanoid or not root or not dir or State.Horse or humanoid.Sit then
		return
	end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then
		return
	end
	flat = flat.Unit
	local duration = math.clamp(tonumber(data.Duration) or 0.25, 0.05, 1.5)
	local distance = math.clamp(tonumber(data.Distance) or 10, 0, 120)
	local speed = distance / duration
	planarVelocity(root, duration, function()
		return flat * speed
	end)
	CameraController.Kick(6)
end

local function localKnockback(data: any)
	local _, humanoid, root = State.Character()
	local v = vec(data.V)
	if not humanoid or not root or not v or State.Horse or humanoid.Sit then
		return
	end
	local decay = math.clamp(tonumber(data.T) or 0.25, 0.05, 1.5)
	if v.Y > 5 then
		humanoid:ChangeState(Enum.HumanoidStateType.Freefall)
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, v.Y, root.AssemblyLinearVelocity.Z)
	end
	local flat = Vector3.new(v.X, 0, v.Z)
	planarVelocity(root, decay, function(t: number)
		return flat * (1 - t / decay)
	end)
	CameraController.Shake(math.clamp(v.Magnitude / 120, 0.1, 0.45))
end

-- Projectiles ------------------------------------------------------------------------

type Projectile = {
	Part: BasePart,
	Pos: Vector3,
	Dir: Vector3,
	Speed: number,
	Born: number,
	Life: number,
	Origin: Vector3,
	FrozenUntil: number,
}

local projectiles: { [number]: Projectile } = {}

local function projectilePart(shape: string, radius: number, c: Color3): BasePart
	local cf = CFrame.new()
	local p: Part
	if shape == "Knife" then
		p = makePart({ Size = Vector3.new(0.15, 0.4, 2.0), CFrame = cf, Color = Color3.fromRGB(214, 218, 226), Material = Enum.Material.Metal })
	elseif shape == "Nail" then
		p = makePart({ Size = Vector3.new(0.25, 0.25, 1.4), CFrame = cf, Color = Color3.fromRGB(150, 150, 156), Material = Enum.Material.Metal })
	elseif shape == "Shard" then
		p = makePart({ Size = Vector3.new(0.6, 0.6, 1.8), CFrame = cf, Color = c, Material = Enum.Material.Glass, Transparency = 0.2 })
	elseif shape == "Crate" then
		p = makePart({ Size = Vector3.new(2.6, 2.6, 2.6), CFrame = cf, Color = Color3.fromRGB(140, 104, 66), Material = Enum.Material.WoodPlanks })
	elseif shape == "Tank" then
		p = makePart({ Size = Vector3.new(2.0, 1.3, 2.6), CFrame = cf, Color = Color3.fromRGB(196, 190, 176), Material = Enum.Material.Metal })
	elseif shape == "Fire" then
		p = makePart({ Size = Vector3.one * math.max(1, radius * 1.6), CFrame = cf, Color = Color3.fromRGB(255, 140, 50), Shape = Enum.PartType.Ball, Transparency = 0.15 })
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = Config.Textures.Fire
		fire.Color = ColorSequence.new(Color3.fromRGB(255, 150, 60))
		fire.LightEmission = 1
		fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, radius * 1.4), NumberSequenceKeypoint.new(1, 0) })
		fire.Lifetime = NumberRange.new(0.2, 0.4)
		fire.Rate = 60
		fire.Speed = NumberRange.new(0.5, 2)
		fire.Parent = p
	elseif shape == "Pulse" then
		p = makePart({ Size = Vector3.one * math.max(1, radius * 2), CFrame = cf, Color = c, Shape = Enum.PartType.Ball, Transparency = 0.45 })
	else
		p = makePart({ Size = Vector3.one * math.max(0.8, radius * 1.6), CFrame = cf, Color = c, Shape = Enum.PartType.Ball })
	end
	-- Trail behind everything that flies.
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.25, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.25, 0)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(c)
	trail.LightEmission = 0.6
	trail.Lifetime = 0.18
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	trail.FaceCamera = true
	trail.Parent = p
	return p
end

local function impact(position: Vector3, shape: string, c: Color3, hit: boolean)
	if shape == "Crate" then
		for _ = 1, 6 do
			local plank = makePart({
				Size = Vector3.new(0.3, 0.3, 1.6),
				CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
				Color = Color3.fromRGB(140, 104, 66),
				Material = Enum.Material.WoodPlanks,
			})
			tween(plank, 0.5, { CFrame = plank.CFrame + Vector3.new(math.random(-4, 4), math.random(1, 4), math.random(-4, 4)) })
			fadeOut(plank, 0.6)
		end
	elseif shape == "Tank" or shape == "Fire" then
		burstSphere(position, Color3.fromRGB(255, 150, 60), 5, 0.4)
		emitAt(position, Config.Textures.Smoke, Color3.fromRGB(80, 70, 64), 12, 10, 2.5, 1)
		playAt(Config.Sounds.Land, position, 0.8, 0.6)
		CameraController.ShakeAt(position, 0.35, 50)
	else
		burstSphere(position, c, if hit then 2.5 else 1.5, 0.25)
		emitAt(position, Config.Textures.Sparkle, c, if hit then 10 else 5, 14, 0.6, 0.35)
	end
end

local function freezeProjectiles(center: Vector3, radius: number, untilTime: number, owner: Vector3?)
	for _, p in projectiles do
		if (p.Pos - center).Magnitude <= radius then
			-- Projectiles fired by the user of the time stop keep flying.
			if not owner or (p.Origin - owner).Magnitude > 8 then
				p.FrozenUntil = untilTime
			end
		end
	end
end

-- Status effects ------------------------------------------------------------------------

local function statusEffect(model: any, name: string, duration: number)
	local root = rootOf(model)
	if not root or not near(root.Position, 200) then
		return
	end
	if name == "Burn" then
		aura(model, Color3.fromRGB(255, 140, 50), duration, Config.Textures.Fire, 30)
	elseif name == "Bleed" then
		aura(model, Color3.fromRGB(150, 30, 30), duration, Config.Textures.Sparkle, 12)
	elseif name == "Slow" then
		local h = Instance.new("Highlight")
		h.FillColor = Color3.fromRGB(110, 150, 196)
		h.FillTransparency = 0.6
		h.OutlineTransparency = 1
		h.Adornee = model
		h.Parent = folder
		Debris:AddItem(h, duration)
	elseif name == "Spin" then
		local start = os.clock()
		local ringPart = makePart({ Size = Vector3.new(0.2, 6, 6), CFrame = root.CFrame, Color = Color3.fromRGB(196, 170, 90), Transparency = 0.6, Shape = Enum.PartType.Cylinder })
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - start
			if t > duration or not root.Parent then
				conn:Disconnect()
				ringPart:Destroy()
				return
			end
			ringPart.CFrame = CFrame.new(root.Position) * CFrame.Angles(0, t * 12, math.rad(90))
		end)
	elseif name == "Silence" then
		floatText(root.Position, "Silenced", Color3.fromRGB(200, 196, 186), 18, 1.2, Style.Fonts.BodyBold)
	elseif name == "Bomb" then
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 70, 50)
		light.Range = 8
		light.Parent = root
		local start = os.clock()
		task.spawn(function()
			while os.clock() - start < duration and light.Parent do
				local left = duration - (os.clock() - start)
				light.Enabled = not light.Enabled
				playAt(Config.Sounds.Note, root.Position, 0.25, 2.2)
				task.wait(math.clamp(left / 6, 0.08, 0.4))
			end
			light:Destroy()
		end)
	end
end

-- Barrages ------------------------------------------------------------------------

local barrages: { [Instance]: number } = {}

local function barrage(model: any, duration: number, c: Color3)
	if typeof(model) ~= "Instance" then
		return
	end
	local token = (barrages[model] or 0) + 1
	barrages[model] = token
	local start = os.clock()
	task.spawn(function()
		while os.clock() - start < duration and barrages[model] == token do
			local stand = if model:IsA("Model") then StandAnimator.StandOf(model) else nil
			local base = rootOf(stand) or rootOf(model)
			if not base then
				break
			end
			if near(base.Position, 160) then
				local cf = base.CFrame * CFrame.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 2 + 0.5, -2.5 - math.random() * 2)
				local fist = makePart({ Size = Vector3.one * 0.9, CFrame = cf, Color = c, Shape = Enum.PartType.Ball, Transparency = 0.25 })
				tween(fist, 0.12, { CFrame = cf * CFrame.new(0, 0, -1.5) })
				fadeOut(fist, 0.14, Vector3.one * 0.4)
			end
			task.wait(0.035)
		end
	end)
	local root = rootOf(model)
	if root then
		playAt(Config.Sounds.Swing, root.Position, 0.5, 1.6)
	end
end

-- Handlers ------------------------------------------------------------------------

local handlers: { [string]: (any) -> () } = {}

handlers.Cooldown = function(data)
	if type(data.Move) == "string" and type(data.T) == "number" then
		State.SetCooldown(data.Move, data.T)
	end
end

handlers.Dash = localDash
handlers.Knockback = localKnockback

handlers.Hit = function(data)
	local p = vec(data.P)
	if not p then
		return
	end
	local dealt = tonumber(data.D) or 0
	local c = color(data.Col, WHITE)
	if data.B then
		floatText(p, "Blocked " .. dealt, Color3.fromRGB(200, 196, 186), 18, 0.8)
		burstSphere(p + Vector3.new(0, 1, 0), Color3.fromRGB(220, 214, 200), 2, 0.2)
		playAt(Config.Sounds.Hit, p, 0.4, 1.4)
	elseif data.Dot then
		floatText(p, tostring(dealt), Color3.fromRGB(214, 160, 120), 16, 0.7)
	else
		local crit = data.C == true
		floatText(p, if crit then dealt .. "!" else tostring(dealt), if crit then Style.Colors.Brass else WHITE, if crit then 30 else 22, 0.9)
		burstSphere(p + Vector3.new(0, 1, 0), c, if crit then 3.5 else 2.2, 0.18)
		emitAt(p + Vector3.new(0, 1, 0), Config.Textures.Sparkle, c, if crit then 12 else 6, 16, 0.5, 0.3)
		playAt(Config.Sounds.Hit, p, 0.55, 1.1 + math.random() * 0.3)
		flash(data.Model, Color3.fromRGB(255, 255, 255), 0.15, 0.4)
	end
	if isLocal(data.Model) then
		CameraController.Shake(math.clamp(0.12 + dealt / 80, 0.12, 0.5))
	end
end

handlers.Heal = function(data)
	local root = rootOf(data.Model)
	if root then
		floatText(root.Position, "+" .. tostring(data.Amount or 0), HEAL, 20, 0.9)
		emitAt(root.Position, Config.Textures.Sparkle, HEAL, 8, 4, 0.8, 0.8)
	end
end

handlers.StandSummon = function(data)
	local stand = data.Stand
	local root = rootOf(stand)
	if not root then
		return
	end
	local c = if typeof(stand) == "Instance" then color(stand:GetAttribute("PunchColor"), WHITE) else WHITE
	shockwave(root.Position, c, 5, 0.35)
	playAt(Config.Sounds.Swing, root.Position, 0.6, 0.6)
	-- Fade the Stand in.
	if typeof(stand) == "Instance" then
		local parts = {}
		for _, d in stand:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 1
				table.insert(parts, d)
			end
		end
		local start = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local k = math.clamp((os.clock() - start) / 0.25, 0, 1)
			for _, part in parts do
				part.LocalTransparencyModifier = 1 - k
			end
			if k >= 1 then
				conn:Disconnect()
			end
		end)
	end
end

handlers.StandUnsummon = function(data)
	local p = vec(data.P)
	if p then
		burstSphere(p, WHITE, 3, 0.25)
		emitAt(p, Config.Textures.Smoke, Color3.fromRGB(200, 196, 186), 6, 3, 1.5, 0.6)
	end
end

handlers.StandBreak = function(data)
	local root = rootOf(data.Model)
	if not root then
		return
	end
	for _ = 1, 10 do
		local shard = makePart({
			Size = Vector3.new(0.5, 0.5, 0.9),
			CFrame = CFrame.new(root.Position + Vector3.new(0, 2, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Color = Color3.fromRGB(196, 190, 176),
			Material = Enum.Material.Glass,
		})
		tween(shard, 0.6, { CFrame = shard.CFrame + Vector3.new(math.random(-6, 6), math.random(2, 6), math.random(-6, 6)) })
		fadeOut(shard, 0.7)
	end
	floatText(root.Position, "Stand broken", Style.Colors.Accent, 24, 1.3, Style.Fonts.Heading)
	playAt(Config.Sounds.Hit, root.Position, 0.9, 0.5)
	if isLocal(data.Model) then
		CameraController.Shake(0.5)
	end
end

handlers.GuardBreak = function(data)
	local root = rootOf(data.Model)
	if root then
		floatText(root.Position, "Guard broken", Style.Colors.Brass, 22, 1.1, Style.Fonts.Heading)
		shockwave(root.Position, Style.Colors.Brass, 6, 0.3)
		playAt(Config.Sounds.Hit, root.Position, 0.8, 0.7)
	end
end

handlers.ComboBreak = function(data)
	local root = rootOf(data.Model)
	if root then
		shockwave(root.Position, WHITE, 7, 0.35)
		floatText(root.Position, "Broke free", WHITE, 18, 0.9, Style.Fonts.BodyBold)
	end
end

handlers.Dodged = function(data)
	local root = rootOf(data.Model)
	if root then
		floatText(root.Position, "Dodged", Color3.fromRGB(200, 196, 186), 18, 0.8, Style.Fonts.BodyBold)
	end
end

handlers.Dodge = function(data)
	afterimage(data.Model, Color3.fromRGB(214, 206, 190), 0.3)
	local root = rootOf(data.Model)
	if root then
		playAt(Config.Sounds.Swing, root.Position, 0.5, 1.3)
		emitAt(root.Position - Vector3.new(0, 2.5, 0), Config.Textures.Smoke, Color3.fromRGB(196, 170, 130), 6, 5, 1.2, 0.6)
	end
end

handlers.Counter = function(data)
	local c = color(data.Color, WHITE)
	local a = rootOf(data.Model)
	local b = rootOf(data.Target)
	if a then
		flash(data.Model, c, 0.4, 0.3)
		floatText(a.Position, "Countered", c, 24, 1.1, Style.Fonts.Heading)
	end
	if a and b then
		beam(a.Position, b.Position, 0.6, c, 0.25)
	end
end

handlers.Effect = function(data)
	if type(data.Name) == "string" then
		statusEffect(data.Model, data.Name, math.clamp(tonumber(data.Duration) or 2, 0.1, 30))
	end
end

handlers.Explosion = function(data)
	local p = vec(data.P)
	if not p then
		return
	end
	local radius = tonumber(data.Radius) or 8
	burstSphere(p, Color3.fromRGB(255, 160, 70), radius, 0.4)
	burstSphere(p, Color3.fromRGB(255, 230, 180), radius * 0.6, 0.25)
	emitAt(p, Config.Textures.Smoke, Color3.fromRGB(70, 62, 56), 16, 14, 3, 1.2)
	shockwave(p - Vector3.new(0, 2, 0), Color3.fromRGB(255, 180, 100), radius * 1.4, 0.4)
	playAt(Config.Sounds.Land, p, 1, 0.5)
	CameraController.ShakeAt(p, 0.6, radius * 6)
end

handlers.TimeStop = function(data)
	local center = vec(data.Center)
	if not center then
		return
	end
	local radius = tonumber(data.Radius) or 60
	local duration = math.clamp(tonumber(data.Duration) or 3, 0.5, 15)
	local sphere = makePart({
		Size = Vector3.one,
		CFrame = CFrame.new(center),
		Color = Color3.fromRGB(230, 220, 180),
		Material = Enum.Material.ForceField,
		Transparency = 0,
		Shape = Enum.PartType.Ball,
	})
	tween(sphere, 0.5, { Size = Vector3.one * radius * 2 })
	task.delay(0.6, function()
		fadeOut(sphere, 0.6, Vector3.one * radius * 2.2)
	end)
	local user = rootOf(data.Model)
	freezeProjectiles(center, radius, os.clock() + duration, if user then user.Position else nil)
	local _, _, root = State.Character()
	local inside = root ~= nil and (root.Position - center).Magnitude <= radius * 1.5
	if inside or isLocal(data.Model) then
		local caught = not isLocal(data.Model)
		screenGrade(if caught then -1 else -0.7, 0.25, Color3.fromRGB(236, 226, 200), duration)
		CameraController.Kick(12)
		play2D(Config.Sounds.Note, 0.6, 0.25)
		-- A clock ticks while time is stopped.
		task.spawn(function()
			local start = os.clock()
			while os.clock() - start < duration - 0.2 do
				task.wait(1)
				play2D(Config.Sounds.Note, 0.35, 3)
			end
		end)
	end
end

handlers.Erase = function(data)
	local duration = math.clamp(tonumber(data.Duration) or 2, 0.2, 10)
	local root = rootOf(data.Model)
	if root and near(root.Position, 200) then
		screenGrade(0.15, 0.15, Color3.fromRGB(255, 196, 196), duration)
		play2D(Config.Sounds.Note, 0.5, 0.4)
	end
	local model = data.Model
	if typeof(model) == "Instance" and model ~= player.Character then
		local parts = {}
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.LocalTransparencyModifier = 0.75
				table.insert(parts, d)
			end
		end
		task.delay(duration, function()
			for _, part in parts do
				part.LocalTransparencyModifier = 0
			end
		end)
	end
end

handlers.Rewind = function(data)
	local from = vec(data.From)
	local to = vec(data.To)
	if not from or not to then
		return
	end
	for i = 0, 8 do
		local p = from:Lerp(to, i / 8)
		task.delay(i * 0.04, function()
			shockwave(p, Color3.fromRGB(196, 170, 90), 3, 0.35)
		end)
	end
	burstSphere(to, Color3.fromRGB(220, 200, 140), 4, 0.35)
	playAt(Config.Sounds.Note, to, 0.5, 0.6)
end

handlers.MoveUsed = function(data)
	local root = rootOf(data.Model)
	local move = if type(data.Move) == "string" then StandData.GetMove(data.Move) else nil
	if root and move then
		floatText(root.Position + Vector3.new(0, 2, 0), move.Name, color(data.Color, WHITE), 22, 1.2, Style.Fonts.Heading)
	end
end

handlers.Barrage = function(data)
	barrage(data.Model, math.clamp(tonumber(data.Duration) or 1.5, 0.1, 8), color(data.Color, WHITE))
end

handlers.BarrageEnd = function(data)
	if typeof(data.Model) == "Instance" then
		barrages[data.Model] = (barrages[data.Model] or 0) + 1
	end
end

handlers.Windup = function(data)
	local root = rootOf(data.Model)
	if not root or not near(root.Position, 200) then
		return
	end
	local t = math.clamp(tonumber(data.T) or 0.4, 0.05, 3)
	local c = color(data.Color, WHITE)
	local disc = makePart({
		Size = Vector3.new(0.2, 9, 9),
		CFrame = CFrame.new(root.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = c,
		Transparency = 0.7,
		Shape = Enum.PartType.Cylinder,
	})
	tween(disc, t, { Size = Vector3.new(0.2, 1.5, 1.5), Transparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	Debris:AddItem(disc, t + 0.05)
	local light = Instance.new("PointLight")
	light.Color = c
	light.Range = 0
	light.Brightness = 3
	light.Parent = root
	tween(light, t, { Range = 14 })
	Debris:AddItem(light, t + 0.1)
end

handlers.Heavy = function(data)
	local p = vec(data.P)
	local dir = vec(data.Dir)
	if not p then
		return
	end
	local c = color(data.Color, WHITE)
	local range = tonumber(data.Range) or 8
	shockwave(p, c, range * 0.7, 0.35)
	burstSphere(p, c, range * 0.4, 0.25)
	if dir then
		for i = -2, 2 do
			local side = Vector3.new(-dir.Z, 0, dir.X) * i * 0.6
			beam(p + side, p + side + dir * range, 0.3, c, 0.25)
		end
	end
	playAt(Config.Sounds.Hit, p, 0.9, 0.8)
	CameraController.ShakeAt(p, 0.35, 40)
end

handlers.Line = function(data)
	local from = vec(data.From)
	local to = vec(data.To)
	if from and to then
		local c = color(data.Color, WHITE)
		local width = tonumber(data.Width) or 2.5
		beam(from, to, width, c, 0.4)
		beam(from, to, width * 0.4, WHITE, 0.25)
		burstSphere(to, c, width * 1.5, 0.3)
		playAt(Config.Sounds.Swing, from, 0.7, 0.8)
	end
end

handlers.Blast = function(data)
	local p = vec(data.P)
	if not p or not near(p, 300) then
		return
	end
	local radius = tonumber(data.Radius) or 10
	local delay = math.clamp(tonumber(data.Delay) or 0.5, 0, 5)
	local c = color(data.Color, Style.Colors.Accent)
	-- Telegraph: a ring on the ground that fills in before it goes off.
	local ground = p
	local outer = makePart({
		Size = Vector3.new(0.15, radius * 2, radius * 2),
		CFrame = CFrame.new(ground) * CFrame.Angles(0, 0, math.rad(90)),
		Color = c,
		Transparency = 0.75,
		Shape = Enum.PartType.Cylinder,
	})
	local inner = makePart({
		Size = Vector3.new(0.2, 0.5, 0.5),
		CFrame = outer.CFrame,
		Color = c,
		Transparency = 0.45,
		Shape = Enum.PartType.Cylinder,
	})
	tween(inner, math.max(0.05, delay), { Size = Vector3.new(0.2, radius * 2, radius * 2) }, Enum.EasingStyle.Linear)
	Debris:AddItem(outer, delay + 0.05)
	Debris:AddItem(inner, delay + 0.05)
end

handlers.BlastHit = function(data)
	local p = vec(data.P)
	if not p then
		return
	end
	local radius = tonumber(data.Radius) or 10
	local c = color(data.Color, Style.Colors.Accent)
	local shape = if type(data.Sh) == "string" then data.Sh else "Explosion"
	if shape == "Fire" then
		emitAt(p, Config.Textures.Fire, Color3.fromRGB(255, 150, 60), 30, radius, 3, 0.8)
		burstSphere(p, Color3.fromRGB(255, 150, 60), radius, 0.35)
	elseif shape == "Pulse" then
		shockwave(p, c, radius, 0.45, 0.2)
		burstSphere(p, c, radius, 0.3, Enum.Material.ForceField)
	else
		burstSphere(p, c, radius, 0.4)
		burstSphere(p, Color3.fromRGB(255, 230, 180), radius * 0.5, 0.25)
		emitAt(p, Config.Textures.Smoke, Color3.fromRGB(70, 62, 56), 14, radius, 3, 1)
	end
	playAt(Config.Sounds.Land, p, 1, 0.55)
	CameraController.ShakeAt(p, 0.5, radius * 5)
end

handlers.DashTrail = function(data)
	local from = vec(data.From)
	local to = vec(data.To)
	if from and to then
		local c = color(data.Color, WHITE)
		beam(from, to, 1.2, c, 0.35)
		afterimage(data.Model, c, 0.35)
		playAt(Config.Sounds.Swing, from, 0.7, 1.1)
	end
end

handlers.Pull = function(data)
	local from = vec(data.From)
	local to = vec(data.To)
	if not from or not to then
		return
	end
	local c = color(data.Color, WHITE)
	local length = (to - from).Magnitude
	local links = math.clamp(math.floor(length / 1.5), 2, 40)
	for i = 1, links do
		local p = from:Lerp(to, i / links)
		local link = makePart({ Size = Vector3.new(0.35, 0.35, 0.9), CFrame = CFrame.lookAt(p, to), Color = c, Material = Enum.Material.Metal })
		task.delay(0.15 + (links - i) * 0.008, function()
			if link.Parent then
				tween(link, 0.12, { CFrame = CFrame.new(from) })
				fadeOut(link, 0.14)
			end
		end)
	end
	playAt(Config.Sounds.Swing, from, 0.6, 0.7)
end

handlers.HealPulse = function(data)
	local p = vec(data.P)
	if p then
		local c = color(data.Color, HEAL)
		shockwave(p - Vector3.new(0, 2.5, 0), c, tonumber(data.Radius) or 10, 0.6, 0.4)
		emitAt(p, Config.Textures.Sparkle, c, 16, 6, 1, 1)
	end
end

handlers.Teleport = function(data)
	local from = vec(data.From)
	local to = vec(data.To)
	local c = color(data.Color, WHITE)
	for _, p in { from, to } do
		if p then
			burstSphere(p, c, 3.5, 0.3)
			emitAt(p, Config.Textures.Smoke, c, 8, 4, 1.4, 0.6)
			playAt(Config.Sounds.Swing, p, 0.6, 1.5)
		end
	end
end

handlers.CounterStance = function(data)
	local model = data.Model
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local h = Instance.new("Highlight")
	h.FillTransparency = 0.85
	h.FillColor = color(data.Color, WHITE)
	h.OutlineColor = color(data.Color, WHITE)
	h.OutlineTransparency = 0.1
	h.Adornee = model
	h.Parent = folder
	Debris:AddItem(h, math.clamp(tonumber(data.Duration) or 1.5, 0.1, 10))
end

handlers.Buff = function(data)
	aura(data.Model, color(data.Color, Style.Colors.Brass), math.clamp(tonumber(data.Duration) or 5, 0.1, 30), Config.Textures.Sparkle, 18)
	local root = rootOf(data.Model)
	if root then
		shockwave(root.Position - Vector3.new(0, 2.5, 0), color(data.Color, Style.Colors.Brass), 6, 0.4)
	end
end

handlers.Punch = function(data)
	local model = data.Model
	if typeof(model) ~= "Instance" or not model:IsA("Model") then
		return
	end
	local root = rootOf(model)
	if not root or not near(root.Position, 160) then
		return
	end
	local index = tonumber(data.Index) or 1
	if data.Stand then
		local stand = StandAnimator.StandOf(model)
		local standRoot = rootOf(stand)
		if standRoot then
			local cf = standRoot.CFrame * CFrame.new(0, 0.5, -3.5)
			burstSphere(cf.Position, color(data.Color, WHITE), 1.6, 0.15)
		end
	else
		RigAnimator.Punch(model, index)
	end
	playAt(Config.Sounds.Swing, root.Position, 0.45, 1.2 + (index % 4) * 0.08)
end

handlers.Whistle = function(data)
	local root = rootOf(data.Model)
	if root then
		playAt(Config.Sounds.Note, root.Position, 0.7, 2.4)
		task.delay(0.18, function()
			playAt(Config.Sounds.Note, root.Position, 0.7, 3.0)
		end)
	end
end

handlers.BossPhase = function(data)
	local root = rootOf(data.Model)
	if root then
		shockwave(root.Position - Vector3.new(0, 2, 0), Style.Colors.Accent, 30, 0.7)
		burstSphere(root.Position, Style.Colors.Accent, 8, 0.4)
		playAt(Config.Sounds.Land, root.Position, 1, 0.4)
		CameraController.ShakeAt(root.Position, 0.6, 120)
	end
end

handlers.Proj = function(data)
	local id = tonumber(data.Id)
	local origin = vec(data.O)
	local dir = vec(data.D)
	if not id or not origin or not dir then
		return
	end
	local speed = tonumber(data.S) or 80
	local range = tonumber(data.R) or 100
	local shape = if type(data.Sh) == "string" then data.Sh else "Ball"
	local part = projectilePart(shape, tonumber(data.Rad) or 1, color(data.C, WHITE))
	part.CFrame = CFrame.lookAt(origin, origin + dir)
	projectiles[id] = {
		Part = part,
		Pos = origin,
		Dir = dir.Unit,
		Speed = speed,
		Born = os.clock(),
		Life = range / math.max(1, speed) + 1.5,
		Origin = origin,
		FrozenUntil = 0,
	}
	playAt(Config.Sounds.Swing, origin, 0.4, 1.4)
end

handlers.ProjMove = function(data)
	local p = projectiles[tonumber(data.Id) or -1]
	local pos = vec(data.P)
	local dir = vec(data.D)
	if p and pos then
		p.Pos = pos
		if dir then
			p.Dir = dir.Unit
		end
	end
end

handlers.ProjEnd = function(data)
	local id = tonumber(data.Id) or -1
	local p = projectiles[id]
	local pos = vec(data.P)
	if p then
		projectiles[id] = nil
		p.Part:Destroy()
	end
	if pos then
		impact(pos, if type(data.Sh) == "string" then data.Sh else "Ball", if p then p.Part.Color else WHITE, data.Hit == true)
	end
end

local function stepProjectiles(dt: number)
	local now = os.clock()
	for id, p in projectiles do
		if now - p.Born > p.Life or not p.Part.Parent then
			p.Part:Destroy()
			projectiles[id] = nil
			continue
		end
		if now >= p.FrozenUntil then
			p.Pos += p.Dir * p.Speed * dt
		end
		p.Part.CFrame = CFrame.lookAt(p.Pos, p.Pos + p.Dir) * CFrame.Angles(0, 0, now * 6)
	end
end

function FXController.Init()
	local existing = workspace:FindFirstChild("ClientFX")
	if existing and existing:IsA("Folder") then
		folder = existing
	else
		local f = Instance.new("Folder")
		f.Name = "ClientFX"
		f.Parent = workspace
		folder = f
	end
	local g = Instance.new("ColorCorrectionEffect")
	g.Name = "SBR_ScreenGrade"
	g.Parent = Lighting
	grade = g

	Remotes.Event("FX").OnClientEvent:Connect(function(kind: string, data: any)
		if type(kind) ~= "string" or type(data) ~= "table" then
			return
		end
		local handler = handlers[kind]
		if handler then
			local ok, err = pcall(handler :: any, data)
			if not ok then
				warn("[FX] " .. kind .. ": " .. tostring(err))
			end
		end
		FXController.Event:Fire(kind, data)
	end)
	RunService.RenderStepped:Connect(stepProjectiles)
end

-- Exposed for UI moments (level up, stand awakened) that want a screen beat.
FXController.Shockwave = shockwave
FXController.Burst = burstSphere
FXController.FloatText = floatText

return FXController
