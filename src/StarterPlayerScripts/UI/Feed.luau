--!strict
-- Messages from the server: toasts, banners for big moments, the kill feed,
-- boss dialogue, XP and cash popups, and the downed screen. Panels slide in
-- and out; nothing fades in.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Util = require(ReplicatedStorage.Shared.Util)
local Route = require(ReplicatedStorage.Shared.Route)
local Kit = require(script.Parent.Kit)

local Feed = {}

local C = Kit.Colors
local S = Kit.Space

local screen: ScreenGui
local toastStack: Frame
local killFeed: Frame
local popups: Frame
local bannerFrame: Frame
local bannerTitle: TextLabel
local bannerText: TextLabel
local dialog: Frame
local dialogName: TextLabel
local dialogLine: TextLabel
local downed: Frame
local downedBy: TextLabel
local downedTimer: TextLabel

local function slide(inst: GuiObject, goal: UDim2, time: number?)
	TweenService:Create(inst, TweenInfo.new(time or 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = goal }):Play()
end

-- Toasts ---------------------------------------------------------------------------

local TONES: { [string]: { Fill: Color3, Text: Color3 } } = {
	Good = { Fill = C.Parchment, Text = C.Good },
	Bad = { Fill = C.Accent, Text = C.Paper },
	Info = { Fill = C.Parchment, Text = C.Ink },
}

function Feed.Toast(text: string, tone: string?)
	local scheme = TONES[tone or "Info"] or TONES.Info
	local holder = Kit.new("Frame", {
		BackgroundTransparency = 1,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = os.clock() * 1000 // 1,
		ClipsDescendants = false,
		Parent = toastStack,
	})
	local card = Kit.Panel({
		BackgroundColor3 = scheme.Fill,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Position = UDim2.fromOffset(0, -12),
		Parent = holder,
	})
	Kit.Padding(S.S, S.M).Parent = card
	Kit.Paragraph(text, { TextColor3 = scheme.Text, FontFace = Kit.Fonts.BodyBold, TextXAlignment = Enum.TextXAlignment.Center, Parent = card })
	slide(card, UDim2.fromOffset(0, 0))
	-- Keep at most four.
	local toasts = {}
	for _, child in toastStack:GetChildren() do
		if child:IsA("Frame") then
			table.insert(toasts, child)
		end
	end
	if #toasts > 4 then
		table.sort(toasts, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		toasts[1]:Destroy()
	end
	task.delay(4, function()
		if holder.Parent then
			slide(card, UDim2.new(1.2, 0, 0, 0), 0.25)
			task.wait(0.25)
			holder:Destroy()
		end
	end)
end

-- Kill feed ------------------------------------------------------------------------

local function killLine(data: any)
	local killer = if type(data.Killer) == "string" then data.Killer else nil
	local victim = if type(data.Victim) == "string" then data.Victim else "Someone"
	local text = if killer then killer .. " downed " .. victim else victim .. " went down"
	local row = Kit.Panel({
		Size = UDim2.new(1, 0, 0, 26),
		BackgroundColor3 = C.Paper,
		LayoutOrder = os.clock() * 1000 // 1,
		Parent = killFeed,
	})
	Kit.Padding(0, S.S).Parent = row
	Kit.Label(text, { TextSize = Kit.Text.Small, FontFace = Kit.Fonts.BodyBold, Size = UDim2.fromScale(1, 1), TextTruncate = Enum.TextTruncate.AtEnd, TextXAlignment = Enum.TextXAlignment.Right, Parent = row })
	local rows = {}
	for _, child in killFeed:GetChildren() do
		if child:IsA("Frame") then
			table.insert(rows, child)
		end
	end
	if #rows > 5 then
		table.sort(rows, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		rows[1]:Destroy()
	end
	task.delay(9, function()
		if row.Parent then
			row:Destroy()
		end
	end)
end

-- Popups for XP and cash -------------------------------------------------------------

local function popup(text: string, c: Color3)
	local label = Kit.Label(text, {
		FontFace = Kit.Fonts.Numbers,
		TextColor3 = c,
		TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(1, 0, 0, 22),
		LayoutOrder = os.clock() * 1000 // 1,
		Parent = popups,
	})
	local stroke = Kit.Stroke(C.Ink, 1)
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Parent = label
	task.delay(2.2, function()
		label:Destroy()
	end)
end

-- Banners ------------------------------------------------------------------------------

type Banner = { Title: string, Text: string, Time: number }
local bannerQueue: { Banner } = {}
local bannerBusy = false

local function runBanners()
	if bannerBusy then
		return
	end
	bannerBusy = true
	task.spawn(function()
		while #bannerQueue > 0 do
			local b = table.remove(bannerQueue, 1) :: Banner
			bannerTitle.Text = b.Title
			bannerText.Text = b.Text
			bannerText.Visible = b.Text ~= ""
			bannerFrame.Position = UDim2.new(0.5, 0, 0, -200)
			bannerFrame.Visible = true
			slide(bannerFrame, UDim2.new(0.5, 0, 0, 150), 0.3)
			task.wait(b.Time)
			slide(bannerFrame, UDim2.new(0.5, 0, 0, -200), 0.25)
			task.wait(0.3)
			bannerFrame.Visible = false
		end
		bannerBusy = false
	end)
end

function Feed.Banner(title: string, text: string?, time: number?)
	-- Collapse duplicates that arrive together.
	for _, b in bannerQueue do
		if b.Title == title then
			return
		end
	end
	table.insert(bannerQueue, { Title = title, Text = text or "", Time = time or 3.2 })
	runBanners()
end

-- Boss dialogue --------------------------------------------------------------------------

local dialogToken = 0
local function bossLine(name: string, line: string)
	dialogToken += 1
	local token = dialogToken
	dialogName.Text = name
	dialogLine.Text = line
	dialogLine.MaxVisibleGraphemes = 0
	dialog.Visible = true
	task.spawn(function()
		local count = utf8.len(line) or #line
		for i = 1, count do
			if token ~= dialogToken then
				return
			end
			dialogLine.MaxVisibleGraphemes = i
			task.wait(0.025)
		end
		dialogLine.MaxVisibleGraphemes = -1
		task.wait(3.5)
		if token == dialogToken then
			dialog.Visible = false
		end
	end)
end

-- Downed screen ------------------------------------------------------------------------------

local function showDowned(killer: string?, respawn: number)
	downedBy.Text = if killer then "by " .. killer else "You fell."
	downed.Visible = true
	task.spawn(function()
		local left = respawn
		while left > 0 and downed.Visible do
			downedTimer.Text = string.format("Back on your feet in %d", math.ceil(left))
			task.wait(0.25)
			left -= 0.25
		end
		downed.Visible = false
	end)
end

-- Build -----------------------------------------------------------------------------------

local function build()
	screen = Kit.Screen("SBR_Feed", 5)
	toastStack = Kit.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 160),
		Size = UDim2.fromOffset(420, 300),
		Parent = screen,
	}, { Kit.List(S.S, false, Enum.HorizontalAlignment.Center) })
	killFeed = Kit.new("Frame", {
		Name = "KillFeed",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -S.L, 0, 250),
		Size = UDim2.fromOffset(260, 200),
		Parent = screen,
	}, { Kit.List(S.XS, false, Enum.HorizontalAlignment.Right) })
	popups = Kit.new("Frame", {
		Name = "Popups",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -S.L, 0.55, 0),
		Size = UDim2.fromOffset(240, 180),
		Parent = screen,
	}, { Kit.List(2, false, Enum.HorizontalAlignment.Right) })

	bannerFrame = Kit.Panel({
		Name = "Banner",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, -200),
		Size = UDim2.fromOffset(520, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundColor3 = C.Paper,
		Visible = false,
		Parent = screen,
	})
	Kit.Padding(S.L, S.XL).Parent = bannerFrame
	Kit.List(S.S, false, Enum.HorizontalAlignment.Center).Parent = bannerFrame
	bannerTitle = Kit.Heading("", Kit.Text.Heading, { TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1, Parent = bannerFrame })
	Kit.Rule({ Size = UDim2.new(0.4, 0, 0, 2), BackgroundTransparency = 0, BackgroundColor3 = C.Accent, LayoutOrder = 2, Parent = bannerFrame })
	bannerText = Kit.Paragraph("", { TextXAlignment = Enum.TextXAlignment.Center, TextSize = Kit.Text.Label, LayoutOrder = 3, Parent = bannerFrame })

	dialog = Kit.Panel({
		Name = "BossLine",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -110),
		Size = UDim2.fromOffset(560, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = screen,
	})
	Kit.Padding(S.M, S.L).Parent = dialog
	Kit.List(S.XS).Parent = dialog
	dialogName = Kit.Heading("", Kit.Text.Label, { TextColor3 = C.Accent, LayoutOrder = 1, Parent = dialog })
	dialogLine = Kit.Paragraph("", { TextSize = Kit.Text.Label, LayoutOrder = 2, Parent = dialog })

	downed = Kit.new("Frame", {
		Name = "Downed",
		BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 10,
		Parent = screen,
	})
	local card = Kit.Panel({
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(380, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		ZIndex = 11,
		Parent = downed,
	})
	Kit.Padding(S.XL).Parent = card
	Kit.List(S.S, false, Enum.HorizontalAlignment.Center).Parent = card
	Kit.Heading("You were downed", Kit.Text.Heading, { TextXAlignment = Enum.TextXAlignment.Center, LayoutOrder = 1, ZIndex = 12, Parent = card })
	downedBy = Kit.Label("", { TextXAlignment = Enum.TextXAlignment.Center, TextSize = Kit.Text.Label, LayoutOrder = 2, ZIndex = 12, Parent = card })
	downedTimer = Kit.Label("", { TextXAlignment = Enum.TextXAlignment.Center, FontFace = Kit.Fonts.Numbers, TextColor3 = C.InkSoft, LayoutOrder = 3, ZIndex = 12, Parent = card })
end

-- Notify handlers --------------------------------------------------------------------------

local lastStage = 0
local handlers: { [string]: (any) -> () } = {}

handlers.Toast = function(d)
	Feed.Toast(tostring(d.Text or ""), d.Tone)
end
handlers.Died = function(d)
	showDowned(if type(d.Killer) == "string" then d.Killer else nil, tonumber(d.Respawn) or 5)
end
handlers.Zone = function(d)
	local stage = tonumber(d.Stage) or 0
	if stage ~= lastStage and stage > 0 then
		local s = Route.Stages[stage]
		if s and lastStage ~= 0 then
			Feed.Banner(s.Name, string.format("Stage %d of %d, %s", stage, #Route.Stages, s.Region), 2.6)
		end
		lastStage = stage
	end
	if d.Kind == "Town" or d.Kind == "Start" then
		Feed.Toast("Entered " .. tostring(d.Name) .. ". Fighting is off here.", "Good")
	elseif d.Kind == "Wild" then
		Feed.Toast(string.format("Open trail. Outlaws here are around level %d.", tonumber(d.Level) or 1), "Info")
	elseif d.Kind == "Boss" then
		Feed.Toast("You are in a boss arena.", "Bad")
	elseif d.Kind == "Arena" then
		Feed.Toast("Ranked arena.", "Info")
	end
end
handlers.StandAwakened = function(d)
	Feed.Banner(tostring(d.Name), "Your Stand has awakened. Rarity: " .. tostring(d.Rarity) .. ". Press Q to summon it.", 4.5)
end
handlers.StandRemoved = function(d)
	Feed.Toast(if d.Name ~= "" then tostring(d.Name) .. " left you." else "Your Stand left you.", "Info")
end
handlers.Evolved = function(d)
	Feed.Banner(tostring(d.To), "Evolved from " .. tostring(d.From) .. ".", 4.5)
end
handlers.XP = function(d)
	local amount = tonumber(d.Amount) or 0
	if amount > 0 then
		popup(string.format("+%s XP  %s", Util.formatNumber(amount), tostring(d.Reason or "")), C.Brass)
	end
end
handlers.LevelUp = function(d)
	local lines = { string.format("%d stat points to spend. Open the menu with M.", tonumber(d.Points) or 0) }
	if type(d.Unlocks) == "table" then
		for _, u in d.Unlocks do
			table.insert(lines, "Unlocked: " .. tostring(u))
		end
	end
	Feed.Banner("Level " .. tostring(d.Level), table.concat(lines, "\n"), 4)
end
handlers.HorseHurt = function(d)
	Feed.Toast(tostring(d.Name or "Your horse") .. " is hurt and ran off. Heal it at a stable or with Horse Feed.", "Bad")
end
handlers.HorseLevel = function(d)
	Feed.Toast(string.format("%s reached level %s.", tostring(d.Name), tostring(d.Level)), "Good")
end
handlers.NewHorse = function(d)
	local source = if d.Source == "Tamed" then "You tamed a " elseif d.Source == "Race" then "Prize from the race: a " else "A "
	Feed.Banner(tostring(d.Name), source .. tostring(d.Breed) .. " (" .. tostring(d.Rarity) .. ") joined your stable.", 4)
end
handlers.BossLine = function(d)
	bossLine(tostring(d.Name or ""), tostring(d.Line or ""))
end
handlers.Loot = function(d)
	Feed.Toast(string.format("Found %s x%d", tostring(d.Name), tonumber(d.Amount) or 1), "Good")
end
handlers.Cash = function(d)
	popup("+$" .. Util.formatNumber(tonumber(d.Amount) or 0), C.Good)
end
handlers.BossDefeated = function(d)
	Feed.Banner(tostring(d.Name) .. " defeated", "Rewards were shared by damage dealt.", 4)
end
handlers.QuestDone = function(d)
	Feed.Toast("Quest done: " .. tostring(d.Name) .. ". Claim it in the menu.", "Good")
end
handlers.Skin = function(d)
	Feed.Toast("New Stand skin: " .. tostring(d.Name), "Good")
end
handlers.Mastery = function(d)
	if d.TierName == "Perfected" then
		Feed.Banner(tostring(d.MoveName) .. " perfected", "Your Stand now carries a golden aura.", 4)
	else
		Feed.Toast(string.format("%s reached %s mastery.", tostring(d.MoveName), tostring(d.TierName)), "Good")
	end
end
handlers.ArenaStart = function(d)
	Feed.Banner("Duel with " .. tostring(d.Opponent), string.format("Rated %s. Fight starts in %s.", tostring(d.Ranked), tostring(d.Countdown)), 2.8)
end
handlers.ArenaGo = function()
	Feed.Banner("Fight", "", 1.2)
end
handlers.ArenaEnd = function(d)
	local title = if d.Draw then "Draw" elseif d.Won then "Victory" else "Defeat"
	local delta = tonumber(d.Delta) or 0
	local text = if d.Draw then "No rating change." else string.format("Rating %s (%s%d)", tostring(d.Ranked), if delta >= 0 then "+" else "", delta)
	Feed.Banner(title, text, 3.5)
end
handlers.KillFeed = killLine

function Feed.Init()
	build()
	Remotes.Event("Notify").OnClientEvent:Connect(function(kind: string, data: any)
		local handler = handlers[kind]
		if handler and type(data) == "table" then
			local ok, err = pcall(handler :: any, data)
			if not ok then
				warn("[Feed] " .. kind .. ": " .. tostring(err))
			end
		end
	end)
end

return Feed
