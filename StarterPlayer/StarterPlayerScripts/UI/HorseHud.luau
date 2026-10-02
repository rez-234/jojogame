--!strict
-- Riding panel shown while mounted: horse name and level, health, stamina,
-- speed, the current gait on a four step scale, the cruising pace and the
-- riding keys.

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.Controllers.State)
local HorseController = require(script.Parent.Parent.Controllers.HorseController)

local HorseHud = {}

local C = Kit.Colors
local S = Kit.Space
local GAITS = { "Walk", "Trot", "Canter", "Gallop" }

local panel: Frame
local nameLabel: TextLabel
local levelLabel: TextLabel
local breedLabel: TextLabel
local healthBar: Kit.Bar
local staminaBar: Kit.Bar
local speedLabel: TextLabel
local cruiseLabel: TextLabel
local gaitCells: { [string]: Frame } = {}
local gaitTexts: { [string]: TextLabel } = {}

local function build(screen: ScreenGui)
	local touch = UserInputService.TouchEnabled
	panel = Kit.Panel({
		Name = "Horse",
		AnchorPoint = Vector2.new(1, 1),
		Position = if touch then UDim2.new(1, -S.L, 1, -250) else UDim2.new(1, -S.L, 1, -S.L),
		Size = UDim2.fromOffset(290, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = screen,
	})
	Kit.Padding(S.M).Parent = panel
	Kit.List(S.S).Parent = panel

	local header = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = panel })
	nameLabel = Kit.Heading("", 18, { Size = UDim2.fromScale(0.68, 1), TextTruncate = Enum.TextTruncate.AtEnd, Parent = header })
	levelLabel = Kit.Label("", { Size = UDim2.fromScale(0.32, 1), Position = UDim2.fromScale(0.68, 0), TextXAlignment = Enum.TextXAlignment.Right, FontFace = Kit.Fonts.Numbers, Parent = header })
	breedLabel = Kit.Label("", { TextColor3 = C.InkSoft, TextSize = Kit.Text.Small, Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 2, Parent = panel })
	healthBar = Kit.Bar(C.Health, 14, { LayoutOrder = 3, Parent = panel })
	staminaBar = Kit.Bar(C.Stamina, 18, { LayoutOrder = 4, Parent = panel })

	local speedRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 5, Parent = panel })
	speedLabel = Kit.Label("0 mph", { FontFace = Kit.Fonts.Numbers, TextSize = 28, Size = UDim2.fromScale(0.5, 1), Parent = speedRow })
	cruiseLabel = Kit.Label("", { TextSize = Kit.Text.Small, TextColor3 = C.InkSoft, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(0.5, 1), Position = UDim2.fromScale(0.5, 0), Parent = speedRow })

	local scale = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 6, Parent = panel })
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.25, -3, 1, 0),
		CellPadding = UDim2.fromOffset(4, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = scale,
	})
	for i, gait in GAITS do
		local cell = Kit.new("Frame", { BackgroundColor3 = C.ParchmentDark, BorderSizePixel = 0, LayoutOrder = i, Parent = scale }, { Kit.Corner(2) }) :: Frame
		local text = Kit.Label(gait, { Size = UDim2.fromScale(1, 1), TextSize = 13, FontFace = Kit.Fonts.BodyBold, TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.InkSoft, Parent = cell })
		gaitCells[gait] = cell
		gaitTexts[gait] = text
	end

	if not touch then
		Kit.Paragraph("Shift gallop   Space jump   R pace   G get off", {
			TextSize = 13,
			TextColor3 = C.InkSoft,
			LayoutOrder = 7,
			Parent = panel,
		})
	end
end

local function refreshInfo()
	local info = State.HorseInfo
	local horse = State.Horse
	panel.Visible = horse ~= nil
	if not horse or not info then
		return
	end
	nameLabel.Text = tostring(info.Name or horse:GetAttribute("HorseName") or "Horse")
	levelLabel.Text = "Level " .. tostring(info.Level or 1)
	breedLabel.Text = tostring(info.Breed or horse:GetAttribute("Breed") or "")
	cruiseLabel.Text = "Pace: " .. HorseController.CruiseName()
end

local function step()
	local motor = HorseController.Motor
	local horse = State.Horse
	if not motor or not horse then
		return
	end
	local maxStamina = math.max(1, motor.Stats.StaminaMax)
	staminaBar.Set(motor.Stamina / maxStamina, if motor.Exhausted then "Winded" else string.format("Stamina %d", math.floor(motor.Stamina)))
	staminaBar.Fill.BackgroundColor3 = if motor.Exhausted then C.Accent else C.Stamina
	local health = tonumber(horse:GetAttribute("Health")) or motor.Stats.MaxHealth
	local maxHealth = math.max(1, tonumber(horse:GetAttribute("MaxHealth")) or motor.Stats.MaxHealth)
	healthBar.Set(health / maxHealth, string.format("%d / %d", math.ceil(health), maxHealth))
	speedLabel.Text = Kit.Speed(math.abs(motor.Speed))
	local gait = if motor.Speed < 1 then "" else motor.Gait
	for name, cell in gaitCells do
		local on = name == gait
		cell.BackgroundColor3 = if on then C.Leather else C.ParchmentDark
		gaitTexts[name].TextColor3 = if on then C.Parchment else C.InkSoft
	end
end

function HorseHud.Init(screen: ScreenGui)
	build(screen)
	State.Mounted:Connect(refreshInfo)
	HorseController.Changed:Connect(refreshInfo)
	RunService.RenderStepped:Connect(step)
	refreshInfo()
end

return HorseHud
