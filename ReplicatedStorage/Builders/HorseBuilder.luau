--!strict
-- Builds a horse from Parts and Motor6D joints. No meshes or asset ids.
--
-- The model faces -Z. Root is an invisible collision box at hip height;
-- every visible part hangs off it through Motor6D joints so the gait can be
-- animated by writing Motor6D.Transform on each client.

local PartUtil = require(script.Parent.PartUtil)
local Shared = script.Parent.Parent:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local HorseData = require(Shared:WaitForChild("HorseData"))
local Types = require(Shared:WaitForChild("Types"))

local HorseBuilder = {}

export type BuildOptions = {
	Breed: string,
	Coat: number?,
	ManeColor: number?,
	Pattern: string?,
	Cosmetics: Types.HorseCosmetics?,
	Name: string?,
	Seed: number?,
	-- Skip the seat (NPC horses carry a welded rider instead).
	NoSeat: boolean?,
}

local H = Config.Horse.HipHeight
local LEGS = {
	{ Name = "FL", X = -0.72, Z = -1.95, Front = true },
	{ Name = "FR", X = 0.72, Z = -1.95, Front = true },
	{ Name = "BL", X = -0.76, Z = 1.95, Front = false },
	{ Name = "BR", X = 0.76, Z = 1.95, Front = false },
}
HorseBuilder.Legs = LEGS

local WHITE = Color3.fromRGB(236, 232, 224)
local HOOF = Color3.fromRGB(46, 40, 36)
local DARK = Color3.fromRGB(22, 18, 16)

local function joint(name: string, part0: BasePart, part1: BasePart, at: CFrame): Motor6D
	return PartUtil.motor(name, part0, part1, part0.CFrame:Inverse() * at, part1.CFrame:Inverse() * at)
end

local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	return p
end

function HorseBuilder.Build(opts: BuildOptions): Model
	local breed = HorseData.Breeds[opts.Breed] or HorseData.Breeds.Mustang
	local rng = Random.new(opts.Seed or 1)
	local coat = breed.Coats[math.clamp(opts.Coat or 1, 1, #breed.Coats)]
	local maneColor = breed.Manes[math.clamp(opts.ManeColor or 1, 1, #breed.Manes)]
	local pattern = opts.Pattern or ""
	local cosmetics = opts.Cosmetics or { Saddle = "Brown", Blanket = "Red", Mane = "Classic", Shoes = "Iron" }
	local saddleOpt = HorseData.FindCosmetic("Saddle", cosmetics.Saddle) or HorseData.Saddles[1]
	local blanketOpt = HorseData.FindCosmetic("Blanket", cosmetics.Blanket) or HorseData.Blankets[1]
	local shoesOpt = HorseData.FindCosmetic("Shoes", cosmetics.Shoes) or HorseData.Horseshoes[1]
	local maneStyle = cosmetics.Mane
	local ghost = breed.Id == "GhostHorse"
	local coatMaterial = if ghost then Enum.Material.Glass elseif breed.Id == "AkhalTeke" then Enum.Material.Foil else Enum.Material.SmoothPlastic

	local model = PartUtil.model(opts.Name or breed.Name)
	model:SetAttribute("Breed", breed.Id)
	model:SetAttribute("Kind", "Horse")

	local root = PartUtil.part({
		Name = "Root",
		Size = Vector3.new(2.3, 2.4, 6.2),
		CFrame = CFrame.new(0, H + 0.1, 0),
		Transparency = 1,
		Anchored = true,
		CanCollide = true,
		Parent = model,
	})
	root.CanQuery = true
	root.CanTouch = true
	root.CustomPhysicalProperties = PhysicalProperties.new(1.2, 0.2, 0, 1, 1)
	model.PrimaryPart = root

	local function body(name: string, spec: PartUtil.PartSpec): BasePart
		spec.Name = name
		spec.Parent = model
		spec.Color = spec.Color or coat
		spec.Material = spec.Material or coatMaterial
		local p = PartUtil.part(spec)
		if ghost then
			p.Transparency = 0.25
		end
		return decor(p)
	end

	-- Torso: a capsule from a cylinder and two spheres.
	local torso = body("Torso", {
		Size = Vector3.new(4.4, 2.5, 2.5),
		CFrame = CFrame.new(0, H, 0) * CFrame.Angles(0, math.rad(90), 0),
		Shape = Enum.PartType.Cylinder,
	})
	joint("TorsoJoint", root, torso, CFrame.new(0, H, 0))

	local function weldTo(base: BasePart, p: BasePart): BasePart
		PartUtil.weld(base, p)
		return p
	end

	weldTo(torso, body("Chest", { Size = Vector3.new(2.6, 2.6, 2.6), CFrame = CFrame.new(0, H + 0.05, -2.2), Shape = Enum.PartType.Ball }))
	weldTo(torso, body("Rump", { Size = Vector3.new(2.8, 2.8, 2.8), CFrame = CFrame.new(0, H + 0.12, 2.15), Shape = Enum.PartType.Ball }))
	weldTo(torso, body("Withers", { Size = Vector3.new(1.5, 1.5, 1.8), CFrame = CFrame.new(0, H + 0.95, -1.7), Shape = Enum.PartType.Ball }))
	weldTo(torso, body("Belly", { Size = Vector3.new(2.2, 2.2, 3.6), CFrame = CFrame.new(0, H - 0.25, 0), Shape = Enum.PartType.Ball }))

	-- Neck and head.
	local neckBase = Vector3.new(0, H + 0.55, -2.65)
	local neckTop = Vector3.new(0, H + 2.65, -3.75)
	local neck = decor(PartUtil.cylinderBetween(neckBase, neckTop, 1.3, {
		Name = "Neck",
		Color = coat,
		Material = coatMaterial,
		Parent = model,
	}))
	if ghost then
		neck.Transparency = 0.25
	end
	joint("NeckJoint", torso, neck, CFrame.new(neckBase))
	weldTo(neck, body("NeckBase", { Size = Vector3.new(1.55, 1.7, 1.6), CFrame = CFrame.new(0, H + 0.7, -2.85), Shape = Enum.PartType.Ball }))

	local headCenter = Vector3.new(0, H + 2.55, -4.35)
	local headCF = CFrame.lookAt(headCenter, headCenter + Vector3.new(0, -0.62, -1))
	local head = body("Head", { Size = Vector3.new(0.95, 1.0, 1.55), CFrame = headCF })
	joint("HeadJoint", neck, head, CFrame.new(neckTop))
	weldTo(head, body("Jowl", { Size = Vector3.new(1.0, 1.05, 1.05), CFrame = headCF * CFrame.new(0, 0.05, 0.45), Shape = Enum.PartType.Ball }))
	local snoutCF = headCF * CFrame.new(0, -0.1, -0.95)
	local snout = weldTo(head, body("Snout", { Size = Vector3.new(0.8, 0.75, 0.9), CFrame = snoutCF }))
	weldTo(head, body("Muzzle", { Size = Vector3.new(0.82, 0.78, 0.6), CFrame = snoutCF * CFrame.new(0, -0.02, -0.35), Shape = Enum.PartType.Ball, Color = coat:Lerp(DARK, 0.35) }))
	for _, side in { -1, 1 } do
		weldTo(head, body("Nostril", { Size = Vector3.new(0.14, 0.14, 0.14), CFrame = snoutCF * CFrame.new(0.22 * side, 0.05, -0.62), Shape = Enum.PartType.Ball, Color = DARK, Material = Enum.Material.SmoothPlastic }))
		weldTo(head, body("Eye", { Size = Vector3.new(0.22, 0.22, 0.22), CFrame = headCF * CFrame.new(0.47 * side, 0.22, 0.05), Shape = Enum.PartType.Ball, Color = DARK, Material = Enum.Material.Glass }))
		local earCF = headCF * CFrame.new(0.26 * side, 0.6, 0.55) * CFrame.Angles(math.rad(-15), 0, math.rad(-12 * side))
		local ear = body(if side < 0 then "EarL" else "EarR", { Size = Vector3.new(0.2, 0.55, 0.3), CFrame = earCF })
		joint(if side < 0 then "EarLJoint" else "EarRJoint", head, ear, headCF * CFrame.new(0.26 * side, 0.4, 0.55))
	end
	if pattern == "Blaze" then
		weldTo(head, body("Blaze", { Size = Vector3.new(0.3, 0.06, 1.6), CFrame = headCF * CFrame.new(0, 0.5, -0.35), Color = WHITE, Material = Enum.Material.SmoothPlastic }))
	elseif pattern == "Star" then
		weldTo(head, body("Star", { Size = Vector3.new(0.35, 0.06, 0.35), CFrame = headCF * CFrame.new(0, 0.51, 0.1), Color = WHITE, Material = Enum.Material.SmoothPlastic }))
	end

	-- Mane along the top of the neck.
	local neckDir = (neckTop - neckBase).Unit
	-- Perpendicular to the neck, pointing up and back (where the mane grows).
	local neckUp = Vector3.new(0, -neckDir.Z, neckDir.Y).Unit
	local maneCount = 7
	for i = 0, maneCount - 1 do
		local t = i / (maneCount - 1)
		local p = neckBase:Lerp(neckTop + neckDir * 0.3, t) + neckUp * 0.55 + Vector3.new(0, 0.1, 0.2)
		local cf = CFrame.lookAt(p, p + neckDir)
		local height = 0.75
		local width = 0.3
		if maneStyle == "Roached" then
			height = 0.35
		elseif maneStyle == "Long" then
			height = 1.0
			width = 0.36
		end
		local seg: BasePart
		if maneStyle == "Braided" then
			seg = body("Mane", { Size = Vector3.new(0.38, 0.38, 0.38), CFrame = cf, Shape = Enum.PartType.Ball, Color = maneColor, Material = Enum.Material.Fabric })
		else
			seg = body("Mane", { Size = Vector3.new(width, height, 0.5), CFrame = cf * CFrame.new(0, height * 0.2, 0), Color = maneColor, Material = Enum.Material.Fabric })
		end
		weldTo(neck, seg)
		if maneStyle == "Long" then
			weldTo(neck, body("ManeDrape", { Size = Vector3.new(0.12, 0.9, 0.5), CFrame = cf * CFrame.new(0.5, -0.2, 0) * CFrame.Angles(0, 0, math.rad(-20)), Color = maneColor, Material = Enum.Material.Fabric }))
		end
	end
	weldTo(head, body("Forelock", { Size = Vector3.new(0.32, 0.3, 0.55), CFrame = headCF * CFrame.new(0, 0.55, -0.05), Color = maneColor, Material = Enum.Material.Fabric }))

	-- Legs.
	local hooves: { BasePart } = {}
	for _, leg in LEGS do
		local thick = if leg.Front then 0.78 else 0.92
		local top = Vector3.new(leg.X, H - 0.3, leg.Z)
		local knee = Vector3.new(leg.X, H - 2.2, leg.Z + (if leg.Front then 0 else 0.15))
		local ankle = Vector3.new(leg.X, 0.4, leg.Z)
		local upper = decor(PartUtil.cylinderBetween(top, knee, thick, { Name = leg.Name .. "Upper", Color = coat, Material = coatMaterial, Parent = model }))
		joint(leg.Name .. "Hip", torso, upper, CFrame.new(Vector3.new(leg.X, H - 0.6, leg.Z)))
		weldTo(upper, body(leg.Name .. "Muscle", {
			Size = if leg.Front then Vector3.new(0.95, 1.4, 1.1) else Vector3.new(1.15, 1.7, 1.45),
			CFrame = CFrame.new(leg.X * 1.05, H - 0.75, leg.Z + (if leg.Front then -0.05 else 0.1)),
			Shape = Enum.PartType.Ball,
		}))
		local lower = decor(PartUtil.cylinderBetween(knee, ankle, 0.46, { Name = leg.Name .. "Lower", Color = coat, Material = coatMaterial, Parent = model }))
		joint(leg.Name .. "Knee", upper, lower, CFrame.new(knee))
		weldTo(lower, body(leg.Name .. "Joint", { Size = Vector3.new(0.56, 0.56, 0.56), CFrame = CFrame.new(knee), Shape = Enum.PartType.Ball }))
		if pattern == "Socks" and rng:NextNumber() < 0.75 then
			weldTo(lower, decor(PartUtil.cylinderBetween(ankle, ankle + Vector3.new(0, 0.75, 0), 0.5, { Name = "Sock", Color = WHITE, Parent = model })))
		end
		local hoof = body(leg.Name .. "Hoof", {
			Size = Vector3.new(0.58, 0.42, 0.66),
			CFrame = CFrame.new(leg.X, 0.21, leg.Z - 0.05),
			Color = HOOF,
			Material = Enum.Material.SmoothPlastic,
		})
		weldTo(lower, hoof)
		weldTo(lower, body(leg.Name .. "Shoe", {
			Size = Vector3.new(0.6, 0.08, 0.68),
			CFrame = CFrame.new(leg.X, 0.04, leg.Z - 0.05),
			Color = shoesOpt.Color,
			Material = shoesOpt.Material or Enum.Material.Metal,
		}))
		local dustAttachment = Instance.new("Attachment")
		dustAttachment.Name = "Dust"
		dustAttachment.Parent = hoof
		local dust = Instance.new("ParticleEmitter")
		dust.Name = "Dust"
		dust.Texture = Config.Textures.Smoke
		dust.Color = ColorSequence.new(Color3.fromRGB(196, 170, 130))
		dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 2.2) })
		dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		dust.Lifetime = NumberRange.new(0.5, 0.9)
		dust.Speed = NumberRange.new(1, 3)
		dust.SpreadAngle = Vector2.new(60, 60)
		dust.Acceleration = Vector3.new(0, 2, 0)
		dust.Rate = 0
		dust.Enabled = true
		dust.Parent = dustAttachment
		table.insert(hooves, hoof)
	end

	-- Coat patterns on the body.
	if pattern == "Spots" then
		for _ = 1, 18 do
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			local p = Vector3.new(side * rng:NextNumber(1.05, 1.3), H + rng:NextNumber(-0.6, 0.9), rng:NextNumber(0.6, 3.0))
			weldTo(torso, body("Spot", {
				Size = Vector3.one * rng:NextNumber(0.25, 0.45),
				CFrame = CFrame.new(p),
				Shape = Enum.PartType.Ball,
				Color = DARK:Lerp(coat, 0.2),
				Material = Enum.Material.SmoothPlastic,
			}))
		end
	elseif pattern == "Patches" then
		for _, side in { -1, 1 } do
			for _ = 1, 3 do
				local z = rng:NextNumber(-1.6, 2.0)
				local y = H + rng:NextNumber(-0.7, 0.5)
				weldTo(torso, body("Patch", {
					Size = Vector3.new(0.1, rng:NextNumber(0.8, 1.4), rng:NextNumber(0.9, 1.6)),
					CFrame = CFrame.new(side * 1.3, y, z) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, side * 0.18),
					Color = WHITE,
					Material = Enum.Material.SmoothPlastic,
				}))
			end
		end
	elseif pattern == "Dapple" then
		for _ = 1, 22 do
			local side = if rng:NextNumber() < 0.5 then -1 else 1
			weldTo(torso, body("Dapple", {
				Size = Vector3.new(0.08, 0.32, 0.32),
				CFrame = CFrame.new(side * rng:NextNumber(1.18, 1.3), H + rng:NextNumber(-0.7, 0.6), rng:NextNumber(-2, 2.4)),
				Color = coat:Lerp(WHITE, 0.35),
				Material = Enum.Material.SmoothPlastic,
			}))
		end
	end

	-- Tail as a joint chain.
	local tailPrev: BasePart = torso
	local tailPos = Vector3.new(0, H + 0.75, 3.35)
	local tailDir = Vector3.new(0, -0.35, 1).Unit
	for i = 1, 4 do
		local length = 0.85
		local nextPos = tailPos + tailDir * length
		local seg = decor(PartUtil.cylinderBetween(tailPos, nextPos, 0.5 - i * 0.05, {
			Name = "Tail" .. i,
			Color = maneColor,
			Material = Enum.Material.Fabric,
			Parent = model,
		}))
		if ghost then
			seg.Transparency = 0.3
		end
		joint("Tail" .. i .. "Joint", tailPrev, seg, CFrame.new(tailPos))
		tailPrev = seg
		tailPos = nextPos
		tailDir = (tailDir + Vector3.new(0, -0.55, -0.05)).Unit
	end
	weldTo(tailPrev, body("TailTip", { Size = Vector3.new(0.5, 0.9, 0.5), CFrame = CFrame.new(tailPos + Vector3.new(0, -0.3, 0)), Shape = Enum.PartType.Ball, Color = maneColor, Material = Enum.Material.Fabric }))

	-- Tack: blanket, saddle, stirrups, reins.
	local tackY = H + 1.27
	local function tack(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
		local p = PartUtil.part({ Name = name, Size = size, CFrame = cf, Color = color, Material = material or Enum.Material.Leather, Parent = model })
		decor(p)
		return weldTo(torso, p)
	end
	tack("Blanket", Vector3.new(2.5, 0.1, 2.3), CFrame.new(0, tackY, -0.45), blanketOpt.Color, Enum.Material.Fabric)
	for _, side in { -1, 1 } do
		tack("BlanketSide", Vector3.new(0.1, 1.15, 2.3), CFrame.new(side * 1.28, tackY - 0.5, -0.45) * CFrame.Angles(0, 0, side * 0.12), blanketOpt.Color, Enum.Material.Fabric)
		if blanketOpt.Id == "Striped" then
			tack("Stripe", Vector3.new(0.12, 0.18, 2.32), CFrame.new(side * 1.31, tackY - 0.35, -0.45) * CFrame.Angles(0, 0, side * 0.12), Color3.fromRGB(150, 50, 40), Enum.Material.Fabric)
			tack("Stripe", Vector3.new(0.12, 0.18, 2.32), CFrame.new(side * 1.33, tackY - 0.75, -0.45) * CFrame.Angles(0, 0, side * 0.12), Color3.fromRGB(40, 50, 80), Enum.Material.Fabric)
		end
		tack("Skirt", Vector3.new(0.1, 0.85, 1.4), CFrame.new(side * 1.34, tackY - 0.25, -0.4) * CFrame.Angles(0, 0, side * 0.12), saddleOpt.Color)
		tack("Strap", Vector3.new(0.1, 1.6, 0.16), CFrame.new(side * 1.42, tackY - 0.95, -0.35), saddleOpt.Color:Lerp(DARK, 0.3))
		tack("Stirrup", Vector3.new(0.42, 0.1, 0.34), CFrame.new(side * 1.45, tackY - 1.8, -0.35), shoesOpt.Color, Enum.Material.Metal)
		tack("StirrupSide", Vector3.new(0.08, 0.32, 0.32), CFrame.new(side * 1.45 + side * 0.18, tackY - 1.65, -0.35), shoesOpt.Color, Enum.Material.Metal)
	end
	tack("Seat", Vector3.new(1.4, 0.3, 1.55), CFrame.new(0, tackY + 0.2, -0.4), saddleOpt.Color)
	tack("Cantle", Vector3.new(1.25, 0.45, 0.22), CFrame.new(0, tackY + 0.42, 0.32) * CFrame.Angles(math.rad(-12), 0, 0), saddleOpt.Color)
	tack("Pommel", Vector3.new(1.0, 0.35, 0.3), CFrame.new(0, tackY + 0.38, -1.12), saddleOpt.Color)
	local horn = tack("Horn", Vector3.new(0.45, 0.22, 0.22), CFrame.new(0, tackY + 0.7, -1.18) * CFrame.Angles(0, 0, math.rad(90)), saddleOpt.Color:Lerp(DARK, 0.2))
	tack("Girth", Vector3.new(2.3, 0.2, 0.3), CFrame.new(0, H - 1.22, -0.5), saddleOpt.Color:Lerp(DARK, 0.4))

	local hornAttachment = Instance.new("Attachment")
	hornAttachment.Name = "ReinAnchor"
	hornAttachment.Parent = horn
	for _, side in { -1, 1 } do
		local bit = Instance.new("Attachment")
		bit.Name = "Bit"
		bit.Parent = snout
		bit.WorldCFrame = snoutCF * CFrame.new(0.42 * side, -0.1, -0.1)
		local rein = Instance.new("Beam")
		rein.Name = "Rein"
		rein.Attachment0 = bit
		rein.Attachment1 = hornAttachment
		rein.Color = ColorSequence.new(saddleOpt.Color:Lerp(DARK, 0.4))
		rein.Width0 = 0.07
		rein.Width1 = 0.07
		rein.FaceCamera = true
		rein.Segments = 6
		rein.CurveSize0 = -0.4
		rein.CurveSize1 = 0.4
		rein.LightInfluence = 1
		rein.Transparency = NumberSequence.new(0)
		rein.Parent = snout
	end
	local bridle = PartUtil.part({ Name = "Bridle", Size = Vector3.new(0.88, 0.1, 0.12), CFrame = headCF * CFrame.new(0, 0.1, -0.6), Color = saddleOpt.Color:Lerp(DARK, 0.4), Material = Enum.Material.Leather, Parent = model })
	weldTo(head, decor(bridle))
	local noseband = PartUtil.part({ Name = "Noseband", Size = Vector3.new(0.86, 0.12, 0.1), CFrame = snoutCF * CFrame.new(0, 0.05, -0.15), Color = saddleOpt.Color:Lerp(DARK, 0.4), Material = Enum.Material.Leather, Parent = model })
	weldTo(head, decor(noseband))

	if not opts.NoSeat then
		local seat = Instance.new("Seat")
		seat.Name = "Saddle"
		seat.Size = Vector3.new(1.2, 0.2, 1.2)
		seat.CFrame = CFrame.new(0, tackY + 0.38, -0.35)
		seat.Transparency = 1
		seat.CanCollide = false
		seat.CanQuery = false
		seat.CanTouch = false
		seat.Massless = true
		seat.Disabled = true -- mounting is done by the server, never by touch
		seat.Anchored = false
		seat.Parent = model
		PartUtil.weld(torso, seat)
	end
	local riderAttachment = Instance.new("Attachment")
	riderAttachment.Name = "RiderAttachment"
	riderAttachment.Parent = torso
	riderAttachment.WorldCFrame = CFrame.new(0, tackY + 0.38, -0.35)

	-- Physics drivers, disabled until something controls the horse.
	local drive = Instance.new("Attachment")
	drive.Name = "Drive"
	drive.Parent = root
	local velocity = Instance.new("LinearVelocity")
	velocity.Name = "Velocity"
	velocity.Attachment0 = drive
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.MaxForce = 0
	velocity.VectorVelocity = Vector3.zero
	velocity.Parent = root
	local align = Instance.new("AlignOrientation")
	align.Name = "Align"
	align.Attachment0 = drive
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.MaxTorque = 0
	align.Responsiveness = 25
	align.CFrame = CFrame.identity
	align.Parent = root

	local hoofSound = Instance.new("Sound")
	hoofSound.Name = "Hoof"
	hoofSound.SoundId = Config.Sounds.Hoof
	hoofSound.Volume = 0.5
	hoofSound.RollOffMaxDistance = 120
	hoofSound.Parent = root

	-- Scale for breed size.
	local scale = breed.SizeScale
	if math.abs(scale - 1) > 1e-3 then
		model:ScaleTo(scale)
	end
	model:SetAttribute("Scale", scale)
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

-- Height of the root above the ground for this model.
function HorseBuilder.HipHeight(model: Model): number
	local scale = model:GetAttribute("Scale")
	return (H + 0.1) * (if type(scale) == "number" then scale else 1)
end

return HorseBuilder
