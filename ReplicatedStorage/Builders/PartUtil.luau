--!strict
-- Part construction helpers shared by every procedural builder.

local PartUtil = {}

export type PartSpec = {
	Name: string?,
	Size: Vector3,
	CFrame: CFrame,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Anchored: boolean?,
	CanCollide: boolean?,
	Decor: boolean?, -- no collision, query or touch
	Transparency: number?,
	Reflectance: number?,
	Massless: boolean?,
	Parent: Instance?,
}

local function apply(p: BasePart, spec: PartSpec)
	p.Name = spec.Name or p.Name
	p.Size = spec.Size
	p.CFrame = spec.CFrame
	p.Color = spec.Color or Color3.fromRGB(160, 160, 160)
	p.Material = spec.Material or Enum.Material.SmoothPlastic
	p.Anchored = if spec.Anchored == nil then true else spec.Anchored
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if spec.Decor then
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
	elseif spec.CanCollide ~= nil then
		p.CanCollide = spec.CanCollide
	end
	if spec.Transparency then
		p.Transparency = spec.Transparency
	end
	if spec.Reflectance then
		p.Reflectance = spec.Reflectance
	end
	if spec.Massless then
		p.Massless = true
	end
	p.CastShadow = true
	if spec.Parent then
		p.Parent = spec.Parent
	end
end

function PartUtil.part(spec: PartSpec): Part
	local p = Instance.new("Part")
	if spec.Shape then
		p.Shape = spec.Shape
	end
	apply(p, spec)
	return p
end

function PartUtil.wedge(spec: PartSpec): WedgePart
	local p = Instance.new("WedgePart")
	apply(p, spec)
	return p
end

function PartUtil.corner(spec: PartSpec): CornerWedgePart
	local p = Instance.new("CornerWedgePart")
	apply(p, spec)
	return p
end

-- Cylinder from point a to point b.
function PartUtil.cylinderBetween(a: Vector3, b: Vector3, diameter: number, spec: { [string]: any }): Part
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local cf: CFrame
	if length < 1e-3 then
		cf = CFrame.new(mid)
	else
		-- Cylinders run along their local X axis.
		local dir = (b - a).Unit
		local up = if math.abs(dir.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
		local z = dir:Cross(up).Unit
		local y = z:Cross(dir).Unit
		cf = CFrame.fromMatrix(mid, dir, y, z)
	end
	local s = table.clone(spec)
	s.Size = Vector3.new(math.max(length, 0.05), diameter, diameter)
	s.CFrame = cf
	s.Shape = Enum.PartType.Cylinder
	return PartUtil.part(s :: any)
end

-- Block from point a to point b with a given cross section.
function PartUtil.beamBetween(a: Vector3, b: Vector3, width: number, height: number, spec: { [string]: any }): Part
	local length = (b - a).Magnitude
	local mid = (a + b) / 2
	local s = table.clone(spec)
	s.Size = Vector3.new(width, height, math.max(length, 0.05))
	if length < 1e-3 then
		s.CFrame = CFrame.new(mid)
	else
		s.CFrame = CFrame.lookAt(mid, b)
	end
	return PartUtil.part(s :: any)
end

function PartUtil.model(name: string, parent: Instance?): Model
	local m = Instance.new("Model")
	m.Name = name
	if parent then
		m.Parent = parent
	end
	return m
end

function PartUtil.folder(name: string, parent: Instance?): Folder
	local f = Instance.new("Folder")
	f.Name = name
	if parent then
		f.Parent = parent
	end
	return f
end

function PartUtil.weld(a: BasePart, b: BasePart): WeldConstraint
	local w = Instance.new("WeldConstraint")
	w.Part0 = a
	w.Part1 = b
	w.Parent = a
	return w
end

function PartUtil.motor(name: string, part0: BasePart, part1: BasePart, c0: CFrame, c1: CFrame?): Motor6D
	local m = Instance.new("Motor6D")
	m.Name = name
	m.Part0 = part0
	m.Part1 = part1
	m.C0 = c0
	m.C1 = c1 or CFrame.identity
	m.Parent = part0
	return m
end

-- Welds every BasePart in a model to its primary part and unanchors them.
function PartUtil.weldModel(model: Model, root: BasePart)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d ~= root then
			local hasMotor = false
			for _, j in d:GetJoints() do
				if j:IsA("Motor6D") then
					hasMotor = true
					break
				end
			end
			if not hasMotor then
				PartUtil.weld(root, d)
			end
			d.Anchored = false
		end
	end
	root.Anchored = false
end

function PartUtil.vary(rng: Random, color: Color3, amount: number): Color3
	local h, s, v = color:ToHSV()
	h = (h + rng:NextNumber(-amount, amount) * 0.1) % 1
	s = math.clamp(s + rng:NextNumber(-amount, amount) * 0.5, 0, 1)
	v = math.clamp(v + rng:NextNumber(-amount, amount), 0, 1)
	return Color3.fromHSV(h, s, v)
end

function PartUtil.setDecor(root: Instance)
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		end
	end
end

function PartUtil.light(parent: BasePart, color: Color3, range: number, brightness: number): PointLight
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = parent
	return l
end

return PartUtil
