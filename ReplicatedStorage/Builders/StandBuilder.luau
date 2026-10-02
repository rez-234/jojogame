--!strict
-- Builds a Stand figure from Parts and Motor6D joints using the Look table
-- from StandData (and an optional skin). Joints are created with world aligned
-- frames, so a Transform of CFrame.Angles(rad(90), 0, 0) on a shoulder swings
-- that arm straight forward.

local PartUtil = require(script.Parent.PartUtil)
local Shared = script.Parent.Parent:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local StandData = require(Shared:WaitForChild("StandData"))
local SkinData = require(Shared:WaitForChild("SkinData"))

local StandBuilder = {}

export type Options = {
	Skin: SkinData.Skin?,
	Perfected: boolean?,
	Name: string?,
}

local function decor(p: BasePart): BasePart
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.Anchored = false
	p.CastShadow = false
	return p
end

local function joint(name: string, part0: BasePart, part1: BasePart, at: CFrame): Motor6D
	return PartUtil.motor(name, part0, part1, part0.CFrame:Inverse() * at, part1.CFrame:Inverse() * at)
end

type Ctx = {
	model: Model,
	body: Color3,
	accent: Color3,
	trim: Color3,
	eyes: Color3,
	material: Enum.Material,
}

local function mk(ctx: Ctx, name: string, spec: PartUtil.PartSpec, which: string?): BasePart
	spec.Name = name
	spec.Parent = ctx.model
	if not spec.Color then
		if which == "accent" then
			spec.Color = ctx.accent
		elseif which == "trim" then
			spec.Color = ctx.trim
		elseif which == "eyes" then
			spec.Color = ctx.eyes
		else
			spec.Color = ctx.body
		end
	end
	if not spec.Material then
		spec.Material = if which == "eyes" then Enum.Material.Neon else ctx.material
	end
	return decor(PartUtil.part(spec))
end

local function weld(a: BasePart, b: BasePart): BasePart
	PartUtil.weld(a, b)
	return b
end

local function cyl(ctx: Ctx, name: string, a: Vector3, b: Vector3, d: number, which: string?): BasePart
	local color = if which == "accent" then ctx.accent elseif which == "trim" then ctx.trim else ctx.body
	return decor(PartUtil.cylinderBetween(a, b, d, { Name = name, Color = color, Material = ctx.material, Parent = ctx.model }))
end

-- Builds a head of the given style welded to `head`.
local function buildHead(ctx: Ctx, head: BasePart, style: string, center: Vector3)
	local cf = CFrame.new(center)
	local eyeY = 0.08
	if style == "Bird" then
		weld(head, mk(ctx, "Beak", { Size = Vector3.new(0.5, 0.45, 0.9), CFrame = cf * CFrame.new(0, -0.1, -0.85) * CFrame.Angles(math.rad(10), 0, 0) }, "accent"))
		for i = -1, 1 do
			weld(head, mk(ctx, "Crest", { Size = Vector3.new(0.18, 0.9, 0.5), CFrame = cf * CFrame.new(i * 0.22, 0.75, 0.2) * CFrame.Angles(math.rad(-25), 0, math.rad(i * 15)) }, "accent"))
		end
	elseif style == "Helmet" then
		weld(head, mk(ctx, "Helm", { Size = Vector3.new(1.3, 0.55, 1.3), CFrame = cf * CFrame.new(0, 0.45, 0.05) }, "accent"))
		weld(head, mk(ctx, "HelmCrest", { Size = Vector3.new(0.18, 0.45, 1.2), CFrame = cf * CFrame.new(0, 0.8, 0.05) }, "trim"))
		weld(head, mk(ctx, "Faceplate", { Size = Vector3.new(0.9, 0.5, 0.12), CFrame = cf * CFrame.new(0, -0.25, -0.6) }, "accent"))
	elseif style == "Mask" then
		weld(head, mk(ctx, "Mask", { Size = Vector3.new(1.05, 0.7, 0.15), CFrame = cf * CFrame.new(0, 0.05, -0.6) }, "accent"))
		weld(head, mk(ctx, "Brow", { Size = Vector3.new(1.15, 0.18, 0.3), CFrame = cf * CFrame.new(0, 0.38, -0.55) }, "trim"))
	elseif style == "Horned" then
		for _, s in { -1, 1 } do
			weld(head, mk(ctx, "Horn", { Size = Vector3.new(0.22, 0.8, 0.22), CFrame = cf * CFrame.new(0.45 * s, 0.75, -0.05) * CFrame.Angles(0, 0, math.rad(-25 * s)) }, "trim"))
		end
		weld(head, mk(ctx, "Ridge", { Size = Vector3.new(0.2, 0.25, 1.1), CFrame = cf * CFrame.new(0, 0.62, 0.05) }, "accent"))
	elseif style == "Crown" then
		for i = 0, 6 do
			local a = i / 7 * math.pi * 2
			weld(head, mk(ctx, "Crown", { Size = Vector3.new(0.18, 0.5, 0.18), CFrame = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.7, -0.5) * CFrame.Angles(math.rad(-15), 0, 0) }, "trim"))
		end
		weld(head, mk(ctx, "Ladybug", { Size = Vector3.new(0.3, 0.3, 0.12), CFrame = cf * CFrame.new(0, 0.35, -0.6), Shape = Enum.PartType.Ball }, "accent"))
	elseif style == "Hood" then
		weld(head, mk(ctx, "Hood", { Size = Vector3.new(1.45, 1.45, 1.2), CFrame = cf * CFrame.new(0, 0.1, 0.25), Shape = Enum.PartType.Ball }, "accent"))
	elseif style == "Visor" then
		weld(head, mk(ctx, "Visor", { Size = Vector3.new(1.15, 0.22, 0.2), CFrame = cf * CFrame.new(0, 0.05, -0.58) }, "trim"))
		weld(head, mk(ctx, "Epitaph", { Size = Vector3.new(0.45, 0.4, 0.15), CFrame = cf * CFrame.new(0, 0.55, -0.5) }, "accent"))
		for _, s in { -1, 1 } do
			weld(head, mk(ctx, "SmallEye", { Size = Vector3.new(0.08, 0.08, 0.05), CFrame = cf * CFrame.new(0.1 * s, 0.6, -0.59) }, "eyes"))
		end
		eyeY = 0.05
	elseif style == "Void" then
		weld(head, mk(ctx, "Mouth", { Size = Vector3.new(0.12, 1.0, 1.0), CFrame = cf * CFrame.new(0, -0.05, -0.55) * CFrame.Angles(0, math.rad(90), 0), Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(8, 6, 10), Material = Enum.Material.SmoothPlastic }))
		for _, s in { -1, 1 } do
			weld(head, mk(ctx, "Tooth", { Size = Vector3.new(0.14, 0.3, 0.14), CFrame = cf * CFrame.new(0.32 * s, 0.32, -0.6) }, "trim"))
		end
		eyeY = 0.42
	end
	for _, s in { -1, 1 } do
		weld(head, mk(ctx, "Eye", { Size = Vector3.new(0.26, 0.12, 0.08), CFrame = cf * CFrame.new(0.24 * s, eyeY, -0.61) }, "eyes"))
	end
end

local function buildHumanoid(ctx: Ctx, root: BasePart, look: StandData.Look)
	local muscular = look.Build == "Muscular" or look.Build == "Creature"
	local small = look.Build == "Small"
	local torsoW = if muscular then 2.3 elseif small then 1.3 else 1.85
	local torsoH = if small then 1.3 else 2.1
	local shoulderX = torsoW / 2 + (if small then 0.25 else 0.35)
	local armD = if muscular then 0.78 elseif small then 0.5 else 0.62
	local upperLen = if small then 0.8 else 1.45
	local foreLen = if small then 0.75 else 1.35
	local headSize = if small then 1.35 else 1.2

	local torso = mk(ctx, "Torso", { Size = Vector3.new(torsoW, torsoH, 1.15), CFrame = CFrame.new(0, 0, 0) })
	joint("Waist", root, torso, CFrame.new(0, -torsoH / 2, 0))
	if muscular then
		for _, s in { -1, 1 } do
			weld(torso, mk(ctx, "Pec", { Size = Vector3.new(1.0, 0.75, 0.35), CFrame = CFrame.new(0.52 * s, 0.4, -0.55) }))
		end
		for row = 0, 2 do
			for _, s in { -1, 1 } do
				weld(torso, mk(ctx, "Ab", { Size = Vector3.new(0.42, 0.32, 0.2), CFrame = CFrame.new(0.24 * s, -0.25 - row * 0.36, -0.55) }, "trim"))
			end
		end
	end
	weld(torso, mk(ctx, "Abdomen", { Size = Vector3.new(torsoW * 0.72, 0.7, 0.95), CFrame = CFrame.new(0, -torsoH / 2 - 0.3, 0) }))
	local pelvis = weld(torso, mk(ctx, "Pelvis", { Size = Vector3.new(torsoW * 0.8, 0.6, 1.0), CFrame = CFrame.new(0, -torsoH / 2 - 0.85, 0) }, "accent"))

	local neckY = torsoH / 2
	local headCenter = Vector3.new(0, neckY + headSize / 2 + 0.15, 0)
	local head = mk(ctx, "Head", { Size = Vector3.new(headSize * 0.92, headSize, headSize), CFrame = CFrame.new(headCenter) })
	weld(head, mk(ctx, "Jaw", { Size = Vector3.new(headSize * 0.7, headSize * 0.45, headSize * 0.8), CFrame = CFrame.new(headCenter + Vector3.new(0, -headSize * 0.32, -0.08)) }))
	joint("Neck", torso, head, CFrame.new(0, neckY, 0))
	weld(torso, mk(ctx, "NeckPiece", { Size = Vector3.new(0.6, 0.4, 0.6), CFrame = CFrame.new(0, neckY + 0.1, 0) }))
	buildHead(ctx, head, look.Head, headCenter)

	for _, side in { -1, 1 } do
		local prefix = if side < 0 then "L" else "R"
		local shoulder = Vector3.new(shoulderX * side, torsoH / 2 - 0.35, 0)
		local elbow = shoulder + Vector3.new(0.08 * side, -upperLen, 0)
		local wrist = elbow + Vector3.new(0, -foreLen, -0.05)
		local upper = cyl(ctx, prefix .. "UpperArm", shoulder, elbow, armD)
		joint(prefix .. "Shoulder", torso, upper, CFrame.new(shoulder))
		weld(upper, mk(ctx, prefix .. "Delt", { Size = Vector3.one * (armD * 1.35), CFrame = CFrame.new(shoulder), Shape = Enum.PartType.Ball }))
		local fore = cyl(ctx, prefix .. "Forearm", elbow, wrist, armD * 0.88)
		joint(prefix .. "Elbow", upper, fore, CFrame.new(elbow))
		weld(fore, mk(ctx, prefix .. "Glove", { Size = Vector3.new(armD * 1.02, foreLen * 0.45, armD * 1.02), CFrame = CFrame.new(wrist + Vector3.new(0, foreLen * 0.2, 0)) }, "accent"))
		local fist = weld(fore, mk(ctx, prefix .. "Fist", { Size = Vector3.one * (armD * 1.15), CFrame = CFrame.new(wrist + Vector3.new(0, -0.15, 0)), Shape = Enum.PartType.Ball }))
		local att = Instance.new("Attachment")
		att.Name = "FistTip"
		att.Parent = fist

		if look.Build ~= "Creature" then
			local hip = Vector3.new(torsoW * 0.24 * side, -torsoH / 2 - 0.95, 0)
			local knee = hip + Vector3.new(0.05 * side, -(if small then 0.8 else 1.55), -0.1)
			local ankle = knee + Vector3.new(0, -(if small then 0.7 else 1.5), 0.15)
			local thigh = cyl(ctx, prefix .. "Thigh", hip, knee, armD * 1.15)
			thigh.Transparency = 0.15
			joint(prefix .. "Hip", torso, thigh, CFrame.new(hip))
			local shin = cyl(ctx, prefix .. "Shin", knee, ankle, armD * 0.95)
			shin.Transparency = 0.45
			joint(prefix .. "Knee", thigh, shin, CFrame.new(knee))
			local foot = weld(shin, mk(ctx, prefix .. "Foot", { Size = Vector3.new(armD, 0.3, armD * 1.6), CFrame = CFrame.new(ankle + Vector3.new(0, -0.1, -0.2)) }, "accent"))
			foot.Transparency = 0.6
		end
	end

	if look.Build == "Creature" then
		-- Tapered lower body instead of legs.
		local prev: BasePart = pelvis
		local top = Vector3.new(0, -torsoH / 2 - 1.1, 0)
		for i = 1, 3 do
			local bottom = top + Vector3.new(0, -0.9, 0.25 * i)
			local seg = cyl(ctx, "Tail" .. i, top, bottom, 1.1 - i * 0.28)
			seg.Transparency = 0.1 + i * 0.2
			joint("Tail" .. i .. "Joint", prev, seg, CFrame.new(top))
			prev = seg
			top = bottom
		end
	end

	-- Extras.
	for _, extra in look.Extras do
		if extra == "Scarf" then
			weld(torso, mk(ctx, "Scarf", { Size = Vector3.new(torsoW * 0.75, 0.4, 1.3), CFrame = CFrame.new(0, neckY + 0.05, 0) }, "accent"))
			for i = 1, 2 do
				weld(torso, mk(ctx, "ScarfTail", { Size = Vector3.new(0.4, 1.3, 0.12), CFrame = CFrame.new(0.25 * (i - 1.5) * 2, neckY - 0.6, 0.62) * CFrame.Angles(math.rad(12), 0, math.rad((i - 1.5) * 16)) }, "accent"))
			end
		elseif extra == "Shoulders" then
			for _, s in { -1, 1 } do
				weld(torso, mk(ctx, "Pad", { Size = Vector3.new(armD * 1.6, 0.35, armD * 1.6), CFrame = CFrame.new(shoulderX * s, torsoH / 2 - 0.05, 0) * CFrame.Angles(0, 0, math.rad(-18 * s)) }, "accent"))
			end
		elseif extra == "Hair" then
			weld(head, mk(ctx, "Hair", { Size = Vector3.new(headSize * 1.05, headSize * 0.55, headSize * 1.05), CFrame = CFrame.new(headCenter + Vector3.new(0, headSize * 0.42, 0.1)), Color = Color3.fromRGB(26, 22, 30) }))
			weld(head, mk(ctx, "HairBack", { Size = Vector3.new(headSize * 0.95, headSize * 0.9, 0.4), CFrame = CFrame.new(headCenter + Vector3.new(0, 0.05, headSize * 0.5)), Color = Color3.fromRGB(26, 22, 30) }))
		elseif extra == "Belt" then
			weld(torso, mk(ctx, "Belt", { Size = Vector3.new(torsoW * 0.82, 0.25, 1.05), CFrame = CFrame.new(0, -torsoH / 2 - 0.55, 0) }, "trim"))
			weld(torso, mk(ctx, "Buckle", { Size = Vector3.new(0.35, 0.3, 0.1), CFrame = CFrame.new(0, -torsoH / 2 - 0.55, -0.55) }, "accent"))
		elseif extra == "Hearts" then
			for _, s in { -1, 1 } do
				weld(torso, mk(ctx, "Heart", { Size = Vector3.new(0.3, 0.3, 0.08), CFrame = CFrame.new(0.55 * s, torsoH / 2 - 0.45, -0.6) * CFrame.Angles(0, 0, math.rad(45)) }, "accent"))
			end
			weld(torso, mk(ctx, "Heart", { Size = Vector3.new(0.35, 0.35, 0.08), CFrame = CFrame.new(0, -torsoH / 2 - 0.85, -0.52) * CFrame.Angles(0, 0, math.rad(45)) }, "trim"))
		elseif extra == "Tubes" then
			for _, s in { -1, 1 } do
				local tube = cyl(ctx, "Tube", Vector3.new(0.35 * s, torsoH / 2 - 0.3, 0.55), headCenter + Vector3.new(0.3 * s, -0.1, 0.45), 0.18, "trim")
				weld(torso, tube)
			end
		elseif extra == "Stars" then
			for _, s in { -1, 1 } do
				weld(torso, mk(ctx, "Star", { Size = Vector3.new(0.28, 0.28, 0.08), CFrame = CFrame.new(shoulderX * s * 0.7, torsoH / 2 - 0.25, -0.6) * CFrame.Angles(0, 0, math.rad(45)), Material = Enum.Material.Neon }, "trim"))
			end
		elseif extra == "Zippers" then
			for _, x in { -0.45, 0.45 } do
				weld(torso, mk(ctx, "Zipper", { Size = Vector3.new(0.1, torsoH * 0.9, 0.06), CFrame = CFrame.new(x, 0, -0.6), Material = Enum.Material.Metal }, "trim"))
			end
		elseif extra == "Rapier" then
			local hand = ctx.model:FindFirstChild("RFist") :: BasePart?
			if hand then
				local base = hand.Position
				local blade = cyl(ctx, "Blade", base + Vector3.new(0, 0, -0.2), base + Vector3.new(0, 0, -4.2), 0.14, "trim")
				blade.Material = Enum.Material.Metal
				blade.Color = Color3.fromRGB(220, 224, 232)
				weld(hand, blade)
				weld(hand, mk(ctx, "Guard", { Size = Vector3.new(0.7, 0.7, 0.12), CFrame = CFrame.new(base + Vector3.new(0, 0, -0.3)), Shape = Enum.PartType.Cylinder, Material = Enum.Material.Metal }, "trim"))
			end
		elseif extra == "Wings" then
			for _, s in { -1, 1 } do
				weld(torso, mk(ctx, "Wing", { Size = Vector3.new(0.15, 1.8, 1.2), CFrame = CFrame.new(0.6 * s, 0.4, 0.75) * CFrame.Angles(math.rad(20), math.rad(30 * s), math.rad(-25 * s)) }, "accent"))
			end
		elseif extra == "Bombs" then
			weld(torso, mk(ctx, "Skull", { Size = Vector3.new(0.45, 0.45, 0.2), CFrame = CFrame.new(0, -torsoH / 2 - 0.85, -0.55), Shape = Enum.PartType.Ball }, "trim"))
			for _, s in { -1, 1 } do
				weld(torso, mk(ctx, "Stud", { Size = Vector3.new(0.25, 0.25, 0.25), CFrame = CFrame.new(shoulderX * s, torsoH / 2 + 0.05, 0), Shape = Enum.PartType.Ball }, "trim"))
			end
		elseif extra == "Discs" then
			weld(head, mk(ctx, "Disc", { Size = Vector3.new(0.08, 0.7, 0.7), CFrame = CFrame.new(headCenter + Vector3.new(0, 0.3, -0.62)) * CFrame.Angles(0, math.rad(90), 0), Shape = Enum.PartType.Cylinder, Material = Enum.Material.Foil }, "trim"))
			for i = 1, 3 do
				weld(torso, mk(ctx, "Script", { Size = Vector3.new(torsoW * 0.7, 0.1, 0.06), CFrame = CFrame.new(0, 0.5 - i * 0.35, -0.6) }, "accent"))
			end
		elseif extra == "Strings" then
			for _, s in { -1, 1 } do
				for k = 1, 2 do
					local start = Vector3.new(shoulderX * s, torsoH / 2 - 0.6 - k * 0.5, 0)
					weld(torso, cyl(ctx, "String", start, start + Vector3.new(0.4 * s, -1.4, 0.3), 0.08, "trim"))
				end
			end
		elseif extra == "Flags" then
			local pole = cyl(ctx, "FlagPole", Vector3.new(0.6, -0.4, 0.65), Vector3.new(0.6, 2.8, 0.65), 0.1, "trim")
			weld(torso, pole)
			weld(torso, mk(ctx, "Flag", { Size = Vector3.new(0.06, 0.8, 1.2), CFrame = CFrame.new(0.6, 2.35, 1.25) }, "accent"))
			weld(torso, mk(ctx, "FlagStripe", { Size = Vector3.new(0.07, 0.15, 1.2), CFrame = CFrame.new(0.6, 2.2, 1.25), Color = Color3.fromRGB(240, 240, 240) }))
		elseif extra == "Spikes" then
			for _, s in { -1, 1 } do
				for k = 0, 1 do
					weld(torso, mk(ctx, "Spike", { Size = Vector3.new(0.2, 0.6, 0.2), CFrame = CFrame.new(shoulderX * s * (0.8 + k * 0.25), torsoH / 2 + 0.25, -0.1 + k * 0.3) * CFrame.Angles(0, 0, math.rad(-30 * s)) }, "trim"))
				end
			end
		end
	end
end

local function buildRaptor(ctx: Ctx, root: BasePart)
	local torso = mk(ctx, "Torso", { Size = Vector3.new(1.6, 1.7, 3.0), CFrame = CFrame.new(0, 0, 0), Shape = Enum.PartType.Ball })
	joint("Waist", root, torso, CFrame.new(0, 0, 0))
	weld(torso, mk(ctx, "Belly", { Size = Vector3.new(1.3, 1.2, 2.2), CFrame = CFrame.new(0, -0.25, -0.1), Shape = Enum.PartType.Ball }, "accent"))
	local neckBase = Vector3.new(0, 0.4, -1.3)
	local neckTop = Vector3.new(0, 1.4, -2.0)
	local neck = cyl(ctx, "NeckSeg", neckBase, neckTop, 0.8)
	joint("Neck", torso, neck, CFrame.new(neckBase))
	local headCF = CFrame.new(neckTop + Vector3.new(0, 0.15, -0.6))
	local head = weld(neck, mk(ctx, "Head", { Size = Vector3.new(0.85, 0.75, 1.6), CFrame = headCF }))
	weld(neck, mk(ctx, "Snout", { Size = Vector3.new(0.7, 0.5, 1.0), CFrame = headCF * CFrame.new(0, 0.05, -1.0) }))
	local jaw = mk(ctx, "Jaw", { Size = Vector3.new(0.65, 0.25, 1.5), CFrame = headCF * CFrame.new(0, -0.45, -0.55) }, "accent")
	joint("JawJoint", head, jaw, headCF * CFrame.new(0, -0.3, 0.3))
	for i = 0, 4 do
		weld(head, mk(ctx, "Tooth", { Size = Vector3.new(0.6, 0.12, 0.08), CFrame = headCF * CFrame.new(0, -0.32, -0.6 - i * 0.28), Color = Color3.fromRGB(240, 236, 220), Material = Enum.Material.SmoothPlastic }))
	end
	for _, s in { -1, 1 } do
		weld(head, mk(ctx, "Eye", { Size = Vector3.new(0.08, 0.16, 0.22), CFrame = headCF * CFrame.new(0.43 * s, 0.18, -0.2) }, "eyes"))
	end
	local prev: BasePart = torso
	local p = Vector3.new(0, 0.2, 1.4)
	for i = 1, 4 do
		local q = p + Vector3.new(0, -0.05 * i, 1.0)
		local seg = cyl(ctx, "Tail" .. i, p, q, 0.85 - i * 0.17)
		joint("Tail" .. i .. "Joint", prev, seg, CFrame.new(p))
		prev = seg
		p = q
	end
	for _, side in { -1, 1 } do
		local prefix = if side < 0 then "L" else "R"
		local hip = Vector3.new(0.6 * side, -0.3, 0.4)
		local knee = hip + Vector3.new(0.05 * side, -1.1, 0.5)
		local ankle = knee + Vector3.new(0, -1.1, -0.4)
		local thigh = cyl(ctx, prefix .. "Thigh", hip, knee, 0.75)
		joint(prefix .. "Hip", torso, thigh, CFrame.new(hip))
		local shin = cyl(ctx, prefix .. "Shin", knee, ankle, 0.42)
		joint(prefix .. "Knee", thigh, shin, CFrame.new(knee))
		weld(shin, mk(ctx, prefix .. "Foot", { Size = Vector3.new(0.5, 0.2, 0.9), CFrame = CFrame.new(ankle + Vector3.new(0, -0.1, -0.3)) }, "trim"))
		weld(shin, mk(ctx, prefix .. "Claw", { Size = Vector3.new(0.12, 0.35, 0.12), CFrame = CFrame.new(ankle + Vector3.new(0.15 * side, 0.15, -0.6)) * CFrame.Angles(math.rad(-40), 0, 0), Color = Color3.fromRGB(240, 236, 220) }))
		local shoulder = Vector3.new(0.6 * side, 0.1, -1.0)
		local arm = cyl(ctx, prefix .. "UpperArm", shoulder, shoulder + Vector3.new(0, -0.6, -0.4), 0.3)
		joint(prefix .. "Shoulder", torso, arm, CFrame.new(shoulder))
		local fist = weld(arm, mk(ctx, prefix .. "Fist", { Size = Vector3.new(0.3, 0.3, 0.3), CFrame = CFrame.new(shoulder + Vector3.new(0, -0.65, -0.45)), Shape = Enum.PartType.Ball }, "trim"))
		local att = Instance.new("Attachment")
		att.Name = "FistTip"
		att.Parent = fist
	end
end

-- Builds the Stand model. `standOrLook` is a Stand id or a raw Look table.
function StandBuilder.Build(standOrLook: string | StandData.Look, options: Options?): Model
	local opts: Options = options or {}
	local look: StandData.Look
	local standName = opts.Name or "Stand"
	local punchColor = Color3.fromRGB(220, 220, 220)
	if type(standOrLook) == "string" then
		local stand = StandData.Get(standOrLook)
		assert(stand, "Unknown stand " .. standOrLook)
		look = stand.Look
		standName = stand.Name
		punchColor = stand.PunchColor
	else
		look = standOrLook
	end
	local skin = opts.Skin
	local ctx: Ctx = {
		model = PartUtil.model(standName),
		body = (skin and skin.Body) or look.Body,
		accent = (skin and skin.Accent) or look.Accent,
		trim = (skin and skin.Trim) or look.Trim,
		eyes = (skin and skin.Eyes) or look.Eyes,
		material = (skin and skin.Material) or look.Material,
	}
	if skin and skin.PunchColor then
		punchColor = skin.PunchColor
	end
	local model = ctx.model
	model:SetAttribute("Kind", "Stand")
	model:SetAttribute("PunchColor", punchColor)

	local root = PartUtil.part({
		Name = "Root",
		Size = Vector3.new(1, 1, 1),
		CFrame = CFrame.new(0, 0, 0),
		Transparency = 1,
		Anchored = false,
		CanCollide = false,
		Parent = model,
	})
	root.CanQuery = false
	root.CanTouch = false
	model.PrimaryPart = root

	if look.Build == "Raptor" then
		buildRaptor(ctx, root)
	else
		buildHumanoid(ctx, root, look)
	end

	-- Aura from skins or Perfected mastery.
	local auraColor = (skin and skin.Aura) or (if opts.Perfected then Config.Mastery.PerfectedColor else nil)
	if auraColor then
		local torso = model:FindFirstChild("Torso") :: BasePart?
		if torso then
			local aura = Instance.new("ParticleEmitter")
			aura.Name = "Aura"
			local kind = (skin and skin.Particles) or "Sparkle"
			aura.Texture = if kind == "Fire" then Config.Textures.Fire elseif kind == "Smoke" then Config.Textures.Smoke else Config.Textures.Sparkle
			aura.Color = ColorSequence.new(auraColor)
			aura.LightEmission = 0.6
			aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
			aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
			aura.Lifetime = NumberRange.new(0.6, 1.2)
			aura.Rate = (skin and skin.AuraRate) or 12
			aura.Speed = NumberRange.new(0.5, 2)
			aura.SpreadAngle = Vector2.new(180, 180)
			aura.Acceleration = Vector3.new(0, 3, 0)
			aura.Parent = torso
			local glow = Instance.new("PointLight")
			glow.Name = "AuraLight"
			glow.Color = auraColor
			glow.Range = 8
			glow.Brightness = 0.8
			glow.Parent = torso
		end
	end

	if math.abs(look.Size - 1) > 1e-3 then
		model:ScaleTo(look.Size)
	end
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

return StandBuilder
