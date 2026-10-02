--!strict
-- Builds R6 style humanoid rigs for NPCs out of plain Parts.
-- Joint names and C0/C1 match the classic R6 rig so Humanoid physics and the
-- procedural walk animation both work without any animation assets.

local PartUtil = require(script.Parent.PartUtil)
local Shared = script.Parent.Parent:WaitForChild("Shared")
local NPCData = require(Shared:WaitForChild("NPCData"))

local RigBuilder = {}

local function part(model: Model, name: string, size: Vector3, color: Color3, material: Enum.Material?): Part
	local p = PartUtil.part({
		Name = name,
		Size = size,
		CFrame = CFrame.new(),
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Anchored = false,
		Parent = model,
	})
	return p
end

local function accessory(model: Model, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?, material: Enum.Material?): BasePart
	local p = PartUtil.part({
		Name = name,
		Size = size,
		CFrame = base.CFrame * offset,
		Color = color,
		Material = material or Enum.Material.SmoothPlastic,
		Shape = shape,
		Anchored = false,
		Decor = true,
		Massless = true,
		Parent = model,
	})
	PartUtil.weld(base, p)
	return p
end

-- Builds the hat on the head (already positioned).
local function buildHat(model: Model, head: BasePart, outfit: NPCData.Outfit)
	local color = outfit.HatColor or Color3.fromRGB(70, 50, 36)
	local hat = outfit.Hat or "None"
	if hat == "Cowboy" then
		accessory(model, head, "HatBrim", Vector3.new(0.12, 2.3, 2.1), CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, Enum.Material.Fabric)
		accessory(model, head, "HatCrown", Vector3.new(1.15, 0.7, 1.05), CFrame.new(0, 0.98, 0), color, nil, Enum.Material.Fabric)
		accessory(model, head, "HatBand", Vector3.new(1.17, 0.14, 1.07), CFrame.new(0, 0.72, 0), color:Lerp(Color3.new(), 0.5), nil, Enum.Material.Fabric)
		for _, s in { -1, 1 } do
			accessory(model, head, "BrimCurl", Vector3.new(0.12, 0.3, 1.6), CFrame.new(1.05 * s, 0.72, 0) * CFrame.Angles(0, 0, math.rad(-30 * s)), color, nil, Enum.Material.Fabric)
		end
	elseif hat == "Bowler" then
		accessory(model, head, "HatBrim", Vector3.new(0.1, 1.5, 1.5), CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, Enum.Material.Fabric)
		accessory(model, head, "HatCrown", Vector3.new(1.15, 0.9, 1.15), CFrame.new(0, 0.85, 0), color, Enum.PartType.Ball, Enum.Material.Fabric)
	elseif hat == "Top" then
		accessory(model, head, "HatBrim", Vector3.new(0.1, 1.6, 1.6), CFrame.new(0, 0.62, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, Enum.Material.Fabric)
		accessory(model, head, "HatCrown", Vector3.new(1.3, 0.95, 0.95), CFrame.new(0, 1.15, 0) * CFrame.Angles(0, 0, math.rad(90)), color, Enum.PartType.Cylinder, Enum.Material.Fabric)
	elseif hat == "Bandana" then
		accessory(model, head, "Bandana", Vector3.new(1.18, 0.45, 1.18), CFrame.new(0, -0.22, -0.02), color, nil, Enum.Material.Fabric)
		accessory(model, head, "HatCap", Vector3.new(1.16, 0.35, 1.16), CFrame.new(0, 0.48, 0), Color3.fromRGB(60, 44, 30), nil, Enum.Material.Fabric)
	end
end

export type RigOptions = {
	Name: string,
	Outfit: NPCData.Outfit,
	Health: number,
	WalkSpeed: number,
	DisplayName: string?,
}

function RigBuilder.Build(opts: RigOptions): Model
	local outfit = opts.Outfit
	local model = PartUtil.model(opts.Name)
	local hrp = part(model, "HumanoidRootPart", Vector3.new(2, 2, 1), outfit.Shirt)
	hrp.Transparency = 1
	hrp.CanCollide = false
	local torso = part(model, "Torso", Vector3.new(2, 2, 1), outfit.Shirt, Enum.Material.Fabric)
	local head = part(model, "Head", Vector3.new(1.15, 1.15, 1.15), outfit.Skin)
	local larm = part(model, "Left Arm", Vector3.new(1, 2, 1), outfit.Shirt, Enum.Material.Fabric)
	local rarm = part(model, "Right Arm", Vector3.new(1, 2, 1), outfit.Shirt, Enum.Material.Fabric)
	local lleg = part(model, "Left Leg", Vector3.new(1, 2, 1), outfit.Pants, Enum.Material.Fabric)
	local rleg = part(model, "Right Leg", Vector3.new(1, 2, 1), outfit.Pants, Enum.Material.Fabric)
	head.CanCollide = true
	model.PrimaryPart = hrp

	local function motor(name: string, p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame): Motor6D
		return PartUtil.motor(name, p0, p1, c0, c1)
	end
	motor("RootJoint", hrp, torso, CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, 0, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Neck", torso, head, CFrame.new(0, 1, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0), CFrame.new(0, -0.575, 0, -1, 0, 0, 0, 0, 1, 0, 1, 0))
	motor("Right Shoulder", torso, rarm, CFrame.new(1, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(-0.5, 0.5, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Shoulder", torso, larm, CFrame.new(-1, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(0.5, 0.5, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))
	motor("Right Hip", torso, rleg, CFrame.new(1, -1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0), CFrame.new(0.5, 1, 0, 0, 0, 1, 0, 1, 0, -1, 0, 0))
	motor("Left Hip", torso, lleg, CFrame.new(-1, -1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0), CFrame.new(-0.5, 1, 0, 0, 0, -1, 0, 1, 0, 1, 0, 0))

	-- Lay the rig out standing at the origin so accessories weld in place.
	hrp.CFrame = CFrame.new(0, 3, 0)
	torso.CFrame = hrp.CFrame
	head.CFrame = torso.CFrame * CFrame.new(0, 1.575, 0)
	rarm.CFrame = torso.CFrame * CFrame.new(1.5, 0, 0)
	larm.CFrame = torso.CFrame * CFrame.new(-1.5, 0, 0)
	rleg.CFrame = torso.CFrame * CFrame.new(0.5, -2, 0)
	lleg.CFrame = torso.CFrame * CFrame.new(-0.5, -2, 0)

	-- Face.
	for _, s in { -1, 1 } do
		accessory(model, head, "Eye", Vector3.new(0.14, 0.18, 0.05), CFrame.new(0.22 * s, 0.1, -0.58), Color3.fromRGB(24, 20, 18))
		accessory(model, head, "Brow", Vector3.new(0.26, 0.06, 0.05), CFrame.new(0.22 * s, 0.27, -0.585), outfit.Skin:Lerp(Color3.new(), 0.55))
	end
	accessory(model, head, "Nose", Vector3.new(0.16, 0.22, 0.12), CFrame.new(0, -0.05, -0.62), outfit.Skin:Lerp(Color3.new(), 0.08))
	accessory(model, head, "Mouth", Vector3.new(0.34, 0.05, 0.05), CFrame.new(0, -0.3, -0.585), outfit.Skin:Lerp(Color3.new(), 0.45))
	buildHat(model, head, outfit)
	if outfit.Scarf then
		accessory(model, torso, "Scarf", Vector3.new(1.4, 0.35, 1.15), CFrame.new(0, 0.9, 0), outfit.Scarf, nil, Enum.Material.Fabric)
		accessory(model, torso, "ScarfTail", Vector3.new(0.5, 0.7, 0.12), CFrame.new(0.3, 0.45, -0.55) * CFrame.Angles(0, 0, math.rad(10)), outfit.Scarf, nil, Enum.Material.Fabric)
	end

	-- Hands, boots, belt and vest.
	for _, arm in { larm, rarm } do
		accessory(model, arm, "Hand", Vector3.new(0.95, 0.45, 0.95), CFrame.new(0, -0.8, 0), outfit.Skin)
		accessory(model, arm, "Cuff", Vector3.new(1.02, 0.16, 1.02), CFrame.new(0, -0.52, 0), outfit.Shirt:Lerp(Color3.new(1, 1, 1), 0.15), nil, Enum.Material.Fabric)
	end
	for _, leg in { lleg, rleg } do
		accessory(model, leg, "Boot", Vector3.new(1.04, 0.75, 1.1), CFrame.new(0, -0.65, -0.03), Color3.fromRGB(56, 38, 26), nil, Enum.Material.Leather)
		accessory(model, leg, "Heel", Vector3.new(0.9, 0.18, 0.3), CFrame.new(0, -0.95, 0.42), Color3.fromRGB(36, 26, 20), nil, Enum.Material.Leather)
	end
	accessory(model, torso, "Belt", Vector3.new(2.04, 0.25, 1.04), CFrame.new(0, -0.85, 0), Color3.fromRGB(50, 36, 26), nil, Enum.Material.Leather)
	accessory(model, torso, "Buckle", Vector3.new(0.35, 0.22, 0.06), CFrame.new(0, -0.85, -0.54), Color3.fromRGB(200, 170, 90), nil, Enum.Material.Metal)
	accessory(model, torso, "VestL", Vector3.new(0.7, 1.7, 0.08), CFrame.new(-0.62, 0.1, -0.52), outfit.Shirt:Lerp(Color3.new(), 0.4), nil, Enum.Material.Fabric)
	accessory(model, torso, "VestR", Vector3.new(0.7, 1.7, 0.08), CFrame.new(0.62, 0.1, -0.52), outfit.Shirt:Lerp(Color3.new(), 0.4), nil, Enum.Material.Fabric)

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R6
	humanoid.MaxHealth = opts.Health
	humanoid.Health = opts.Health
	humanoid.WalkSpeed = opts.WalkSpeed
	humanoid.DisplayName = opts.DisplayName or opts.Name
	humanoid.HealthDisplayType = Enum.HumanoidHealthDisplayType.DisplayWhenDamaged
	humanoid.NameDisplayDistance = 60
	humanoid.HealthDisplayDistance = 60
	humanoid.BreakJointsOnDeath = false
	humanoid.Parent = model

	model:SetAttribute("Kind", "NPC")
	model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return model
end

return RigBuilder
