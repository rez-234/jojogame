--!strict
-- UI building blocks in the flat Western poster style: parchment panels with
-- an ink rule, leather header strips, solid buttons that change color
-- instantly on hover, flat progress bars and plain text. No gradients, no
-- translucency over the game, no icons. Every gap comes from Style.Space.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Style = require(ReplicatedStorage.Shared.Style)

local Kit = {}

local C = Style.Colors
local S = Style.Space
local T = Style.TextSize
Kit.Colors = C
Kit.Space = S
Kit.Text = T
Kit.Fonts = Style.Fonts

export type Props = { [string]: any }

-- Creates an instance, applies properties and parents children.
function Kit.new(className: string, props: Props?, children: { any }?): any
	local inst = Instance.new(className)
	local parent: Instance? = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			(child :: Instance).Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Kit.Corner(radius: number?): Instance
	return Kit.new("UICorner", { CornerRadius = UDim.new(0, radius or 2) })
end

function Kit.Stroke(color: Color3?, thickness: number?): UIStroke
	return Kit.new("UIStroke", {
		Color = color or C.Ink,
		Thickness = thickness or 2,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Kit.Padding(all: number, horizontal: number?): Instance
	local h = horizontal or all
	return Kit.new("UIPadding", {
		PaddingTop = UDim.new(0, all),
		PaddingBottom = UDim.new(0, all),
		PaddingLeft = UDim.new(0, h),
		PaddingRight = UDim.new(0, h),
	})
end

function Kit.List(gap: number?, horizontal: boolean?, align: Enum.HorizontalAlignment?): Instance
	return Kit.new("UIListLayout", {
		Padding = UDim.new(0, gap or S.S),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		VerticalAlignment = if horizontal then Enum.VerticalAlignment.Center else Enum.VerticalAlignment.Top,
	})
end

-- Parchment panel with an ink rule.
function Kit.Panel(props: Props?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = C.Parchment,
		BorderSizePixel = 0,
	}, { Kit.Corner(2), Kit.Stroke(C.Ink, 2) })
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(frame :: any)[k] = v
			end
		end
		if props.Parent then
			frame.Parent = props.Parent
		end
	end
	return frame
end

-- Plain text label.
function Kit.Label(text: string, props: Props?): TextLabel
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		TextColor3 = C.Ink,
		FontFace = Style.Fonts.Body,
		TextSize = T.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, T.Body + 6),
		TextWrapped = false,
	})
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(label :: any)[k] = v
			end
		end
		if props.Parent then
			label.Parent = props.Parent
		end
	end
	return label
end

function Kit.Heading(text: string, size: number?, props: Props?): TextLabel
	local label = Kit.Label(text, props)
	label.FontFace = Style.Fonts.Heading
	label.TextSize = size or T.Title
	if not (props and props.Size) then
		label.Size = UDim2.new(1, 0, 0, (size or T.Title) + 8)
	end
	return label
end

-- Paragraph that grows to fit its text.
function Kit.Paragraph(text: string, props: Props?): TextLabel
	local label = Kit.Label(text, props)
	label.TextWrapped = true
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.TextYAlignment = Enum.TextYAlignment.Top
	if not (props and props.Size) then
		label.Size = UDim2.new(1, 0, 0, 0)
	end
	return label
end

export type ButtonKind = "Primary" | "Secondary" | "Ghost"

local BUTTON_COLORS: { [string]: { Fill: Color3, Hover: Color3, Text: Color3 } } = {
	Primary = { Fill = C.Accent, Hover = C.AccentDark, Text = C.Paper },
	Secondary = { Fill = C.Leather, Hover = C.LeatherDark, Text = C.Parchment },
	Ghost = { Fill = C.Parchment, Hover = C.ParchmentDark, Text = C.Ink },
}

export type Button = {
	Instance: TextButton,
	SetEnabled: (enabled: boolean) -> (),
	SetText: (text: string) -> (),
	SetKind: (kind: ButtonKind) -> (),
}

-- Solid button. Hover swaps the fill color at once; nothing fades.
function Kit.Button(text: string, kind: ButtonKind?, onClick: (() -> ())?, props: Props?): Button
	local currentKind: string = kind or "Secondary"
	local enabled = true
	local hovering = false
	local button = Kit.new("TextButton", {
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = text,
		FontFace = Style.Fonts.BodyBold,
		TextSize = T.Body,
		Size = UDim2.fromOffset(120, 34),
	}, { Kit.Corner(2) }) :: TextButton
	local stroke = Kit.Stroke(C.Ink, 1)
	stroke.Parent = button
	local function paint()
		local scheme = BUTTON_COLORS[currentKind] or BUTTON_COLORS.Secondary
		if not enabled then
			button.BackgroundColor3 = C.ParchmentDark
			button.TextColor3 = C.InkSoft
			stroke.Enabled = currentKind == "Ghost"
			return
		end
		button.BackgroundColor3 = if hovering then scheme.Hover else scheme.Fill
		button.TextColor3 = scheme.Text
		stroke.Enabled = currentKind == "Ghost"
	end
	button.MouseEnter:Connect(function()
		hovering = true
		paint()
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		paint()
	end)
	button.Activated:Connect(function()
		if enabled and onClick then
			onClick()
		end
	end)
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(button :: any)[k] = v
			end
		end
		if props.Parent then
			button.Parent = props.Parent
		end
	end
	paint()
	return {
		Instance = button,
		SetEnabled = function(on: boolean)
			enabled = on
			button.Active = on
			paint()
		end,
		SetText = function(t: string)
			button.Text = t
		end,
		SetKind = function(k: ButtonKind)
			currentKind = k
			paint()
		end,
	}
end

export type Bar = {
	Instance: Frame,
	Set: (fraction: number, text: string?) -> (),
	Fill: Frame,
	Label: TextLabel,
}

-- Flat progress bar: dark leather track, solid fill, mono figures on top.
function Kit.Bar(fillColor: Color3, height: number?, props: Props?): Bar
	local h = height or 18
	local track = Kit.new("Frame", {
		BackgroundColor3 = C.Track,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, h),
		ClipsDescendants = true,
	}, { Kit.Corner(2) }) :: Frame
	local fill = Kit.new("Frame", {
		Name = "Fill",
		BackgroundColor3 = fillColor,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = track,
	}, { Kit.Corner(2) }) :: Frame
	local label = Kit.new("TextLabel", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Text = "",
		TextColor3 = C.Paper,
		FontFace = Style.Fonts.Numbers,
		TextSize = math.max(12, h - 4),
		ZIndex = 2,
		Parent = track,
	}, { Kit.Padding(0, S.S) }) :: TextLabel
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(track :: any)[k] = v
			end
		end
		if props.Parent then
			track.Parent = props.Parent
		end
	end
	return {
		Instance = track,
		Fill = fill,
		Label = label,
		Set = function(fraction: number, text: string?)
			fill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
			if text then
				label.Text = text
			end
		end,
	}
end

-- A labelled row: name on the left, value on the right.
function Kit.Row(name: string, value: string, props: Props?): (Frame, TextLabel)
	local row = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 24),
	}) :: Frame
	Kit.Label(name, { Size = UDim2.fromScale(0.6, 1), Parent = row, TextColor3 = C.InkSoft })
	local valueLabel = Kit.Label(value, {
		Size = UDim2.fromScale(0.4, 1),
		Position = UDim2.fromScale(0.6, 0),
		TextXAlignment = Enum.TextXAlignment.Right,
		FontFace = Style.Fonts.Numbers,
		Parent = row,
	})
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(row :: any)[k] = v
			end
		end
		if props.Parent then
			row.Parent = props.Parent
		end
	end
	return row, valueLabel
end

-- Thin ink rule between sections.
function Kit.Rule(props: Props?): Frame
	local rule = Kit.new("Frame", {
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.6,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 1),
	}) :: Frame
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(rule :: any)[k] = v
			end
		end
		if props.Parent then
			rule.Parent = props.Parent
		end
	end
	return rule
end

-- Vertical scrolling list that sizes its canvas to the content.
function Kit.Scroll(props: Props?, gap: number?): ScrollingFrame
	local scroll = Kit.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = C.Leather,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
	}, { Kit.List(gap or S.M), Kit.Padding(S.XS, S.XS) }) :: ScrollingFrame
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(scroll :: any)[k] = v
			end
		end
		if props.Parent then
			scroll.Parent = props.Parent
		end
	end
	return scroll
end

-- A section block inside a menu tab: parchment-dark background, no colored edge.
function Kit.Section(props: Props?): Frame
	local frame = Kit.new("Frame", {
		BackgroundColor3 = C.Paper,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
	}, { Kit.Corner(2), Kit.Padding(S.M), Kit.List(S.S) }) :: Frame
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(frame :: any)[k] = v
			end
		end
		if props.Parent then
			frame.Parent = props.Parent
		end
	end
	return frame
end

-- Horizontal strip for a row of buttons.
function Kit.ButtonRow(props: Props?): Frame
	local frame = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 34),
	}, { Kit.List(S.S, true) }) :: Frame
	if props then
		for k, v in props do
			if k ~= "Parent" then
				(frame :: any)[k] = v
			end
		end
		if props.Parent then
			frame.Parent = props.Parent
		end
	end
	return frame
end

-- Removes every child except layout objects.
function Kit.Clear(container: Instance)
	for _, child in container:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UIGridLayout") and not child:IsA("UICorner") and not child:IsA("UIStroke") then
			child:Destroy()
		end
	end
end

-- A ScreenGui in the local PlayerGui that survives respawns.
function Kit.Screen(name: string, displayOrder: number): ScreenGui
	local playerGui = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	return Kit.new("ScreenGui", {
		Name = name,
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = displayOrder,
		Parent = playerGui,
	})
end

-- Formats a number of studs per second as miles per hour for display.
function Kit.Speed(studsPerSecond: number): string
	return string.format("%d mph", math.floor(studsPerSecond * 0.62 + 0.5))
end

return Kit
