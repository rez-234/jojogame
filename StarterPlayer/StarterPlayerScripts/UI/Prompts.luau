--!strict
-- Draws every proximity prompt in the game (they all use the Custom style)
-- as a small parchment tag with a leather key cap, the action and the
-- object. Hold prompts fill a bar under the action. Tags can be clicked or
-- tapped. While riding, a local "Get off" prompt sits on the saddle.

local ProximityPromptService = game:GetService("ProximityPromptService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Kit = require(script.Parent.Kit)
local State = require(script.Parent.Parent.Controllers.State)

local Prompts = {}

local C = Kit.Colors
local S = Kit.Space

type Shown = { Gui: BillboardGui, Fill: Frame, HoldStart: number?, Conn: RBXScriptConnection? }
local shown: { [ProximityPrompt]: Shown } = {}
local folder: ScreenGui

local GAMEPAD_NAMES: { [string]: string } = {
	ButtonX = "X",
	ButtonY = "Y",
	ButtonA = "A",
	ButtonB = "B",
}

local function keyText(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "Tap"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		return GAMEPAD_NAMES[prompt.GamepadKeyCode.Name] or prompt.GamepadKeyCode.Name
	end
	local name = prompt.KeyboardKeyCode.Name
	return if #name > 6 then string.sub(name, 1, 6) else name
end

local tagSize = Vector2.new(240, 56)

local function adorneeFor(prompt: ProximityPrompt): Instance?
	local parent = prompt.Parent
	if parent and (parent:IsA("BasePart") or parent:IsA("Attachment")) then
		return parent
	elseif parent and parent:IsA("Model") then
		return parent.PrimaryPart
	end
	return nil
end

local function show(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local adornee = adorneeFor(prompt)
	if not adornee then
		return
	end
	local gui = Kit.new("BillboardGui", {
		Name = "Prompt",
		AlwaysOnTop = true,
		LightInfluence = 0,
		Size = UDim2.fromOffset(tagSize.X, tagSize.Y),
		SizeOffset = Vector2.new(0, 0.6),
		StudsOffset = Vector3.new(0, 1.5, 0),
		Adornee = adornee,
		Active = true,
		ResetOnSpawn = false,
		Parent = folder,
	}) :: BillboardGui
	local button = Kit.new("TextButton", {
		AutoButtonColor = false,
		Text = "",
		BackgroundColor3 = C.Parchment,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromScale(1, 1),
		Parent = gui,
	}, { Kit.Corner(2), Kit.Stroke(C.Ink, 2) }) :: TextButton
	local cap = Kit.new("Frame", {
		BackgroundColor3 = C.Leather,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(S.S, S.S),
		Size = UDim2.new(0, 40, 1, -S.S * 2),
		Parent = button,
	}, { Kit.Corner(2) })
	Kit.Label(keyText(prompt, inputType), {
		FontFace = Kit.Fonts.Numbers,
		TextColor3 = C.Parchment,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.fromScale(1, 1),
		Parent = cap,
	})
	Kit.Label(prompt.ActionText, {
		FontFace = Kit.Fonts.BodyBold,
		TextSize = 17,
		Position = UDim2.fromOffset(56, 6),
		Size = UDim2.new(1, -64, 0, 22),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})
	Kit.Label(prompt.ObjectText, {
		TextSize = 13,
		TextColor3 = C.InkSoft,
		Position = UDim2.fromOffset(56, 28),
		Size = UDim2.new(1, -64, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
		Parent = button,
	})
	local track = Kit.new("Frame", {
		BackgroundColor3 = C.ParchmentDark,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 56, 1, -4),
		Size = UDim2.new(1, -64, 0, 3),
		Visible = prompt.HoldDuration > 0,
		Parent = button,
	})
	local fill = Kit.new("Frame", { BackgroundColor3 = C.Accent, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1), Parent = track }) :: Frame

	-- Click or tap the tag to use the prompt.
	button.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			prompt:InputHoldBegin()
		end
	end)
	button.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			prompt:InputHoldEnd()
		end
	end)
	button.MouseEnter:Connect(function()
		button.BackgroundColor3 = C.Paper
	end)
	button.MouseLeave:Connect(function()
		button.BackgroundColor3 = C.Parchment
	end)
	shown[prompt] = { Gui = gui, Fill = fill, HoldStart = nil, Conn = nil }
end

local function hide(prompt: ProximityPrompt)
	local s = shown[prompt]
	if s then
		if s.Conn then
			s.Conn:Disconnect()
		end
		s.Gui:Destroy()
		shown[prompt] = nil
	end
end

-- A local prompt on the saddle so getting off is visible and clickable.
-- G itself is handled by HorseController, which sinks the key while riding,
-- so the tag only fires from a click or tap and never doubles up.
local dismount: ProximityPrompt? = nil
local function onMounted(horse: Model?)
	if dismount then
		dismount:Destroy()
		dismount = nil
	end
	if not horse then
		return
	end
	local saddle = horse:FindFirstChild("Saddle") or horse.PrimaryPart
	if not saddle then
		return
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DismountPrompt"
	prompt.ActionText = "Get off"
	prompt.ObjectText = tostring(horse:GetAttribute("HorseName") or "Horse")
	prompt.KeyboardKeyCode = Enum.KeyCode.G
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonB
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Triggered:Connect(function()
		State.Action("Dismount")
	end)
	prompt.Parent = saddle
	dismount = prompt
end

function Prompts.Init()
	folder = Kit.Screen("SBR_Prompts", 4)
	ProximityPromptService.PromptShown:Connect(function(prompt, inputType)
		if prompt.Style == Enum.ProximityPromptStyle.Custom then
			show(prompt, inputType)
		end
	end)
	ProximityPromptService.PromptHidden:Connect(hide)
	ProximityPromptService.PromptButtonHoldBegan:Connect(function(prompt)
		local s = shown[prompt]
		if s then
			s.HoldStart = os.clock()
			local duration = math.max(0.05, prompt.HoldDuration)
			s.Conn = RunService.RenderStepped:Connect(function()
				local start = s.HoldStart
				if start then
					s.Fill.Size = UDim2.fromScale(math.clamp((os.clock() - start) / duration, 0, 1), 1)
				end
			end)
		end
	end)
	ProximityPromptService.PromptButtonHoldEnded:Connect(function(prompt)
		local s = shown[prompt]
		if s then
			s.HoldStart = nil
			if s.Conn then
				s.Conn:Disconnect()
				s.Conn = nil
			end
			s.Fill.Size = UDim2.fromScale(0, 1)
		end
	end)
	-- Bigger tags for thumbs.
	if UserInputService.TouchEnabled then
		tagSize = Vector2.new(280, 66)
	end
	State.Mounted:Connect(onMounted)
end

return Prompts
