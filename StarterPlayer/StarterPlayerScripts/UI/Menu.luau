--!strict
-- The main menu (M or Tab): a leather tab column on the left and a
-- parchment page on the right. Each tab lives in UI/Tabs and renders itself
-- into a scrolling page; the page re-renders when the profile changes and
-- keeps its scroll position.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Kit = require(script.Parent.Kit)
local Feed = require(script.Parent.Feed)
local State = require(script.Parent.Parent.Controllers.State)
local InputController = require(script.Parent.Parent.Controllers.InputController)
local Tabs = script.Parent:WaitForChild("Tabs")

local Menu = {}

local C = Kit.Colors
local S = Kit.Space

export type Context = {
	-- Re-renders the open tab.
	Rerender: () -> (),
	-- Calls a server request; shows the error as a toast. Returns ok and data.
	Do: (name: string, successText: string?, ...any) -> (boolean, any),
	-- Extra arguments for the tab, such as the town for a quest board.
	Args: { [string]: any },
	-- Switches to another tab.
	Open: (tab: string, args: { [string]: any }?) -> (),
}

export type Tab = {
	Name: string,
	Render: (page: ScrollingFrame, ctx: Context) -> (),
	OnOpen: ((ctx: Context) -> ())?,
}

local ORDER = { "Stats", "Stand", "Mastery", "Skins", "Stable", "Quests", "Shop", "Arena", "Race" }

local screen: ScreenGui
local window: Frame
local titleLabel: TextLabel
local page: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local tabs: { [string]: Tab } = {}
local current = "Stats"
local args: { [string]: any } = {}
local open = false
local renderQueued = false
local ctx: Context

local function paintTabs()
	for name, button in tabButtons do
		local on = name == current
		button.BackgroundColor3 = if on then C.Parchment else C.Leather
		button.TextColor3 = if on then C.Ink else C.Parchment
	end
end

local function render()
	local tab = tabs[current]
	if not tab or not open then
		return
	end
	local scroll = page.CanvasPosition
	Kit.Clear(page)
	titleLabel.Text = tab.Name
	local ok, err = pcall(tab.Render :: any, page, ctx)
	if not ok then
		warn("[Menu] " .. current .. ": " .. tostring(err))
		Kit.Paragraph("This page could not be drawn. Try again in a moment.", { Parent = page })
	end
	task.defer(function()
		page.CanvasPosition = scroll
	end)
end

local function queueRender()
	if renderQueued then
		return
	end
	renderQueued = true
	task.delay(0.15, function()
		renderQueued = false
		render()
	end)
end

function Menu.Open(tab: string?, tabArgs: { [string]: any }?)
	if tab and tabs[tab] then
		if tab ~= current then
			page.CanvasPosition = Vector2.zero
		end
		current = tab
	end
	args = tabArgs or {}
	ctx.Args = args
	open = true
	State.MenuOpen = true
	window.Visible = true
	paintTabs()
	local t = tabs[current]
	if t and t.OnOpen then
		task.spawn(t.OnOpen, ctx)
	end
	render()
end

function Menu.Close()
	open = false
	State.MenuOpen = false
	window.Visible = false
end

function Menu.Toggle()
	if open then
		Menu.Close()
	else
		Menu.Open()
	end
end

local function build()
	screen = Kit.Screen("SBR_Menu", 10)
	window = Kit.Panel({
		Name = "Menu",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(860, 540),
		Visible = false,
		ClipsDescendants = true,
		Parent = screen,
	})
	local uiScale = Kit.new("UIScale", { Parent = window }) :: UIScale
	local function fit()
		local size = workspace.CurrentCamera.ViewportSize
		uiScale.Scale = math.clamp(math.min((size.X - 24) / 860, (size.Y - 60) / 540), 0.5, 1)
	end
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)
	fit()

	local column = Kit.new("Frame", {
		Name = "Tabs",
		BackgroundColor3 = C.Leather,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 170, 1, 0),
		Parent = window,
	}, { Kit.Padding(S.M, 0), Kit.List(2) })
	Kit.Heading("Steel Ball Run", 16, {
		TextColor3 = C.Brass,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 36),
		LayoutOrder = 0,
		Parent = column,
	})
	for i, name in ORDER do
		local button = Kit.new("TextButton", {
			AutoButtonColor = false,
			BorderSizePixel = 0,
			Text = name,
			TextXAlignment = Enum.TextXAlignment.Left,
			FontFace = Kit.Fonts.BodyBold,
			TextSize = Kit.Text.Label,
			Size = UDim2.new(1, 0, 0, 40),
			LayoutOrder = i,
			Parent = column,
		}, { Kit.Padding(0, S.L) }) :: TextButton
		button.MouseEnter:Connect(function()
			if name ~= current then
				button.BackgroundColor3 = C.LeatherLight
			end
		end)
		button.MouseLeave:Connect(paintTabs)
		button.Activated:Connect(function()
			Menu.Open(name)
		end)
		tabButtons[name] = button
	end

	local body = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(170, 0),
		Size = UDim2.new(1, -170, 1, 0),
		Parent = window,
	}, { Kit.Padding(S.L) })
	titleLabel = Kit.Heading("", Kit.Text.Heading, { Size = UDim2.new(1, -120, 0, 36), Parent = body })
	Kit.Button("Close", "Ghost", Menu.Close, {
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.fromOffset(100, 32),
		Parent = body,
	})
	Kit.Rule({ Position = UDim2.fromOffset(0, 44), Parent = body })
	page = Kit.Scroll({ Position = UDim2.fromOffset(0, 56), Size = UDim2.new(1, 0, 1, -56), Parent = body }, S.M)
end

function Menu.Init()
	for _, module in Tabs:GetChildren() do
		if module:IsA("ModuleScript") then
			local ok, tab = pcall(require, module)
			if ok and type(tab) == "table" and type(tab.Name) == "string" then
				tabs[tab.Name] = tab :: Tab
			else
				warn("[Menu] could not load tab " .. module.Name .. ": " .. tostring(tab))
			end
		end
	end
	ctx = {
		Rerender = queueRender,
		Do = function(name: string, successText: string?, ...: any): (boolean, any)
			local result = State.Request(name, ...)
			if result.Ok then
				if successText then
					Feed.Toast(successText, "Good")
				end
				queueRender()
				return true, result.Data
			end
			Feed.Toast(result.Error or "That did not work.", "Bad")
			return false, nil
		end,
		Args = args,
		Open = function(tab: string, tabArgs: { [string]: any }?)
			Menu.Open(tab, tabArgs)
		end,
	}
	build()
	InputController.MenuToggled:Connect(Menu.Toggle)
	State.ProfileChanged:Connect(function()
		if open then
			queueRender()
		end
	end)
	Remotes.Event("Notify").OnClientEvent:Connect(function(kind: string, data: any)
		if kind == "OpenMenu" and type(data) == "table" and type(data.Tab) == "string" then
			Menu.Open(data.Tab, data)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if open and not processed and input.KeyCode == Enum.KeyCode.Escape then
			Menu.Close()
		end
	end)
	Players.LocalPlayer.CharacterRemoving:Connect(function()
		if open then
			Menu.Close()
		end
	end)
end

return Menu
