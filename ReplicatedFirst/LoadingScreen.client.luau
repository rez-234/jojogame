--!strict
-- Loading screen. Runs before anything else replicates, so it carries its
-- own colors and fonts instead of requiring the shared Style module. It
-- shows the server's map build progress and stays up until the world is
-- ready and your character has spawned.

local Players = game:GetService("Players")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local PARCHMENT = Color3.fromRGB(234, 222, 196)
local PAPER = Color3.fromRGB(244, 236, 218)
local INK = Color3.fromRGB(38, 30, 24)
local INK_SOFT = Color3.fromRGB(88, 72, 58)
local LEATHER = Color3.fromRGB(64, 44, 32)
local TRACK = Color3.fromRGB(58, 42, 32)
local BRASS = Color3.fromRGB(184, 146, 72)
local ACCENT = Color3.fromRGB(150, 44, 34)

local HEADING = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Heavy)
local BODY = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular)
local BODY_BOLD = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold)
local NUMBERS = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Medium)

local TIPS = {
	"Press E by your horse to ride. Hold Shift to gallop, but watch its stamina.",
	"Press H to whistle for your horse from anywhere on the trail.",
	"A Stand Arrow awakens a Stand. Press Q to summon it.",
	"Moves get stronger the more they land. Spread your hits across different foes.",
	"Towns are safe. Rest, shop and take quests from the board.",
	"Wild horses roam every stage. Calm one and it joins your stable.",
	"Hold F to block. A Stand that blocks too much will break.",
}

ReplicatedFirst:RemoveDefaultLoadingScreen()

local gui = Instance.new("ScreenGui")
gui.Name = "SBR_Loading"
gui.IgnoreGuiInset = true
gui.ResetOnSpawn = false
gui.DisplayOrder = 100
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

local background = Instance.new("Frame")
background.BackgroundColor3 = PARCHMENT
background.BorderSizePixel = 0
background.Size = UDim2.fromScale(1, 1)
background.Parent = gui

-- A leather band across the middle, like a poster header.
local band = Instance.new("Frame")
band.AnchorPoint = Vector2.new(0.5, 0.5)
band.BackgroundColor3 = LEATHER
band.BorderSizePixel = 0
band.Position = UDim2.fromScale(0.5, 0.4)
band.Size = UDim2.new(1, 0, 0, 150)
band.Parent = background

local title = Instance.new("TextLabel")
title.BackgroundTransparency = 1
title.AnchorPoint = Vector2.new(0.5, 0.5)
title.Position = UDim2.new(0.5, 0, 0.5, -16)
title.Size = UDim2.new(1, -32, 0, 70)
title.FontFace = HEADING
title.TextScaled = true
title.Text = "STEEL BALL RUN"
title.TextColor3 = PARCHMENT
title.Parent = band
local titleLimit = Instance.new("UITextSizeConstraint")
titleLimit.MaxTextSize = 64
titleLimit.Parent = title

local subtitle = Instance.new("TextLabel")
subtitle.BackgroundTransparency = 1
subtitle.AnchorPoint = Vector2.new(0.5, 0)
subtitle.Position = UDim2.new(0.5, 0, 0.5, 26)
subtitle.Size = UDim2.new(1, -32, 0, 24)
subtitle.FontFace = BODY_BOLD
subtitle.TextSize = 20
subtitle.Text = "San Diego to New York, 1890"
subtitle.TextColor3 = BRASS
subtitle.Parent = band

local stage = Instance.new("TextLabel")
stage.BackgroundTransparency = 1
stage.AnchorPoint = Vector2.new(0.5, 0)
stage.Position = UDim2.new(0.5, 0, 0.4, 100)
stage.Size = UDim2.fromOffset(520, 24)
stage.FontFace = BODY_BOLD
stage.TextSize = 18
stage.TextColor3 = INK
stage.Text = "Waiting for the server"
stage.Parent = background

local track = Instance.new("Frame")
track.AnchorPoint = Vector2.new(0.5, 0)
track.BackgroundColor3 = TRACK
track.BorderSizePixel = 0
track.Position = UDim2.new(0.5, 0, 0.4, 132)
track.Size = UDim2.fromOffset(520, 14)
track.Parent = background
local trackCorner = Instance.new("UICorner")
trackCorner.CornerRadius = UDim.new(0, 2)
trackCorner.Parent = track

local fill = Instance.new("Frame")
fill.BackgroundColor3 = BRASS
fill.BorderSizePixel = 0
fill.Size = UDim2.fromScale(0, 1)
fill.Parent = track
local fillCorner = Instance.new("UICorner")
fillCorner.CornerRadius = UDim.new(0, 2)
fillCorner.Parent = fill

local percent = Instance.new("TextLabel")
percent.BackgroundTransparency = 1
percent.AnchorPoint = Vector2.new(0.5, 0)
percent.Position = UDim2.new(0.5, 0, 0.4, 152)
percent.Size = UDim2.fromOffset(520, 20)
percent.FontFace = NUMBERS
percent.TextSize = 14
percent.TextColor3 = INK_SOFT
percent.Text = "0%"
percent.Parent = background

local tip = Instance.new("TextLabel")
tip.BackgroundTransparency = 1
tip.AnchorPoint = Vector2.new(0.5, 1)
tip.Position = UDim2.new(0.5, 0, 1, -40)
tip.Size = UDim2.new(1, -64, 0, 48)
tip.FontFace = BODY
tip.TextSize = 18
tip.TextWrapped = true
tip.TextColor3 = INK
tip.Text = TIPS[math.random(1, #TIPS)]
tip.Parent = background

local errorLabel = Instance.new("TextLabel")
errorLabel.BackgroundColor3 = ACCENT
errorLabel.BorderSizePixel = 0
errorLabel.AnchorPoint = Vector2.new(0.5, 0)
errorLabel.Position = UDim2.new(0.5, 0, 0.4, 184)
errorLabel.Size = UDim2.fromOffset(520, 0)
errorLabel.AutomaticSize = Enum.AutomaticSize.Y
errorLabel.FontFace = BODY_BOLD
errorLabel.TextSize = 16
errorLabel.TextWrapped = true
errorLabel.TextColor3 = PAPER
errorLabel.Visible = false
errorLabel.Parent = background
local errorPadding = Instance.new("UIPadding")
errorPadding.PaddingTop = UDim.new(0, 8)
errorPadding.PaddingBottom = UDim.new(0, 8)
errorPadding.PaddingLeft = UDim.new(0, 12)
errorPadding.PaddingRight = UDim.new(0, 12)
errorPadding.Parent = errorLabel

gui.Parent = player:WaitForChild("PlayerGui")

local function refresh()
	local progress = ReplicatedStorage:GetAttribute("MapProgress")
	local stageName = ReplicatedStorage:GetAttribute("MapStage")
	local frac = if type(progress) == "number" then math.clamp(progress, 0, 1) else 0
	fill.Size = UDim2.fromScale(frac, 1)
	percent.Text = string.format("%d%%", math.floor(frac * 100))
	if type(stageName) == "string" and stageName ~= "" then
		stage.Text = "Building " .. stageName
	end
	local mapError = ReplicatedStorage:GetAttribute("MapError")
	if type(mapError) == "string" then
		errorLabel.Text = "The world did not finish building. Some areas may be missing. " .. mapError
		errorLabel.Visible = true
	end
end

ReplicatedStorage:GetAttributeChangedSignal("MapProgress"):Connect(refresh)
ReplicatedStorage:GetAttributeChangedSignal("MapStage"):Connect(refresh)
ReplicatedStorage:GetAttributeChangedSignal("MapError"):Connect(refresh)
refresh()

-- Rotate tips while waiting.
task.spawn(function()
	local index = math.random(1, #TIPS)
	while gui.Parent do
		task.wait(6)
		index = index % #TIPS + 1
		tip.Text = TIPS[index]
	end
end)

if not game:IsLoaded() then
	game.Loaded:Wait()
end
while ReplicatedStorage:GetAttribute("MapReady") ~= true do
	ReplicatedStorage:GetAttributeChangedSignal("MapReady"):Wait()
end
fill.Size = UDim2.fromScale(1, 1)
percent.Text = "100%"
stage.Text = "Saddling up"
if not player.Character then
	player.CharacterAdded:Wait()
end
-- Give the HUD a moment to build behind the curtain.
local playerGui = player:WaitForChild("PlayerGui")
playerGui:WaitForChild("SBR_Hud", 10)
task.wait(0.5)

-- Slide the curtain up rather than fading it.
local tween = TweenService:Create(background, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = UDim2.fromScale(0, -1) })
tween:Play()
tween.Completed:Wait()
gui:Destroy()
