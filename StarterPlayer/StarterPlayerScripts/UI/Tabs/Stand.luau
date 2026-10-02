--!strict
-- Stand tab: your Stand, its stat grades and moves, the evolution path,
-- Stand storage and your items.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local StandData = require(ReplicatedStorage.Shared.StandData)
local ItemData = require(ReplicatedStorage.Shared.ItemData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)
local InputController = require(script.Parent.Parent.Parent.Controllers.InputController)

local StandTab = {}
StandTab.Name = "Stand"

local C = Kit.Colors
local S = Kit.Space

local STAT_ORDER = { "Power", "Speed", "Range", "Durability", "Precision" }
local confirmRokakaka = 0

local function gradeGrid(parent: Instance, stand: StandData.Stand, order: number)
	local grid = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 52), LayoutOrder = order, Parent = parent })
	Kit.new("UIGridLayout", {
		CellSize = UDim2.new(0.2, -6, 1, 0),
		CellPadding = UDim2.fromOffset(6, 0),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	for i, key in STAT_ORDER do
		local cell = Kit.new("Frame", { BackgroundColor3 = C.Parchment, BorderSizePixel = 0, LayoutOrder = i, Parent = grid }, { Kit.Corner(2) })
		Kit.Label(key, { TextSize = 13, TextColor3 = C.InkSoft, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 4), Parent = cell })
		Kit.Label(StandData.Grade((stand.Stats :: any)[key]), {
			FontFace = Kit.Fonts.Sign,
			TextSize = 24,
			TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 26),
			Position = UDim2.fromOffset(0, 22),
			Parent = cell,
		})
	end
end

local function moveRow(parent: Instance, index: number, move: StandData.Move, order: number)
	local row = Kit.new("Frame", {
		BackgroundColor3 = C.Parchment,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = order,
		Parent = parent,
	}, { Kit.Corner(2), Kit.Padding(S.S, S.M), Kit.List(2) })
	local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Parent = row })
	Kit.Label(InputController.MoveKeys[index] or "", { FontFace = Kit.Fonts.Numbers, TextColor3 = C.Accent, Size = UDim2.fromOffset(24, 22), Parent = top })
	Kit.Label(move.Name, { FontFace = Kit.Fonts.BodyBold, Size = UDim2.new(0.6, -24, 1, 0), Position = UDim2.fromOffset(24, 0), Parent = top })
	local facts = string.format("%s   %ss cooldown", move.Kind, tostring(move.Cooldown))
	if move.Damage > 0 then
		facts = string.format("%d damage   ", move.Damage) .. facts
	end
	Kit.Label(facts, { FontFace = Kit.Fonts.Numbers, TextSize = 13, TextColor3 = C.InkSoft, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(0.45, 1), Position = UDim2.fromScale(0.55, 0), Parent = top })
	Kit.Paragraph(move.Description, { TextSize = 14, TextColor3 = C.InkSoft, LayoutOrder = 2, Parent = row })
end

function StandTab.Render(page: ScrollingFrame, ctx: any)
	local profile = State.Profile
	if not profile then
		Kit.Paragraph("Loading...", { Parent = page })
		return
	end
	local stand = StandData.Get(profile.Stand)
	local arrows = profile.Items.Arrow or 0

	local card = Kit.Section({ LayoutOrder = 1, Parent = page })
	if not stand then
		Kit.Heading("No Stand yet", Kit.Text.Title, { LayoutOrder = 1, Parent = card })
		Kit.Paragraph(string.format("Pierce yourself with a Stand Arrow to awaken one. You have %d. Arrows cost $%d in town shops and drop from bosses.", arrows, Config.Economy.ArrowPrice), { LayoutOrder = 2, Parent = card })
		local use = Kit.Button("Use an Arrow", "Primary", function()
			ctx.Do("UseItem", nil, "Arrow")
		end, { LayoutOrder = 3, Size = UDim2.fromOffset(160, 34), Parent = card })
		use.SetEnabled(arrows > 0)
	else
		Kit.Heading(stand.Name, Kit.Text.Title, { LayoutOrder = 1, Parent = card })
		local rarity = Kit.Label(string.format("Part %d   %s   %s form", stand.Part, stand.Rarity, if stand.Stage > 1 then "Evolved" else "Base"), { LayoutOrder = 2, FontFace = Kit.Fonts.BodyBold, Parent = card })
		rarity.TextColor3 = C.Rarity[stand.Rarity] or C.InkSoft
		Kit.Paragraph(stand.Description, { LayoutOrder = 3, Parent = card })
		gradeGrid(card, stand, 4)
		Kit.Row("Stand durability", tostring(Progression.StandDurability(stand)), { LayoutOrder = 5, Parent = card })
		Kit.Paragraph("Press Q to summon or recall it. Blocking with it out spends durability; if it runs out your Stand breaks for a while.", { LayoutOrder = 6, TextSize = 14, TextColor3 = C.InkSoft, Parent = card })

		local moves = Kit.Section({ LayoutOrder = 2, Parent = page })
		Kit.Heading("Moves", Kit.Text.Label, { LayoutOrder = 0, Parent = moves })
		for i, moveId in stand.Moves do
			local move = StandData.GetMove(moveId)
			if move then
				moveRow(moves, i, move, i)
			end
		end

		local evo = Kit.Section({ LayoutOrder = 3, Parent = page })
		Kit.Heading("Evolution", Kit.Text.Label, { LayoutOrder = 0, Parent = evo })
		local evolution = stand.Evolution
		local nextStand = evolution and StandData.Get(evolution.Next)
		if not evolution or not nextStand then
			Kit.Paragraph("This is the final form.", { LayoutOrder = 1, TextColor3 = C.InkSoft, Parent = evo })
		else
			Kit.Paragraph("Next form: " .. nextStand.Name .. ". " .. nextStand.Description, { LayoutOrder = 1, Parent = evo })
			local ready, list = Progression.EvolutionStatus(profile, stand)
			for i, req in list do
				local _, value = Kit.Row(req.Text, if req.Met then "Done" else string.format("%d / %d", req.Have, req.Need), { LayoutOrder = 1 + i, Parent = evo })
				value.TextColor3 = if req.Met then C.Good else C.Accent
			end
			local button = Kit.Button("Evolve", "Primary", function()
				ctx.Do("Evolve", nil)
			end, { LayoutOrder = 20, Parent = evo })
			button.SetEnabled(ready)
		end
	end

	local storage = Kit.Section({ LayoutOrder = 4, Parent = page })
	Kit.Heading(string.format("Stand storage (%d / %d)", #profile.StandStorage, Config.Stand.MaxStorage), Kit.Text.Label, { LayoutOrder = 0, Parent = storage })
	if stand then
		local store = Kit.Button("Store current Stand", "Secondary", function()
			ctx.Do("StoreStand", "Stand stored.")
		end, { LayoutOrder = 1, Size = UDim2.fromOffset(200, 34), Parent = storage })
		store.SetEnabled(#profile.StandStorage < Config.Stand.MaxStorage)
	end
	if #profile.StandStorage == 0 then
		Kit.Paragraph("Stored Stands wait here. Store one to free yourself for a new Arrow.", { LayoutOrder = 2, TextColor3 = C.InkSoft, Parent = storage })
	end
	for i, id in profile.StandStorage do
		local stored = StandData.Get(id)
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 2 + i, Parent = storage })
		Kit.Label(if stored then stored.Name else id, { FontFace = Kit.Fonts.BodyBold, Size = UDim2.new(1, -150, 1, 0), Parent = row })
		Kit.Button(if stand then "Swap in" else "Take out", "Secondary", function()
			ctx.Do("TakeStand", nil, i)
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(130, 30), Parent = row })
	end

	local items = Kit.Section({ LayoutOrder = 5, Parent = page })
	Kit.Heading("Items", Kit.Text.Label, { LayoutOrder = 0, Parent = items })
	local order = 0
	for id, count in profile.Items do
		local item = ItemData.Items[id]
		if item and count > 0 then
			order += 1
			local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order, Parent = items }, { Kit.List(2) })
			local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1, Parent = row })
			Kit.Label(string.format("%s  x%d", item.Name, count), { FontFace = Kit.Fonts.BodyBold, Size = UDim2.new(1, -140, 1, 0), Parent = top })
			if item.Usable then
				local isFruit = id == "Rokakaka"
				local label = if isFruit and os.clock() < confirmRokakaka then "Confirm" else "Use"
				Kit.Button(label, if isFruit then "Primary" else "Secondary", function()
					if isFruit and os.clock() >= confirmRokakaka then
						confirmRokakaka = os.clock() + 4
						ctx.Rerender()
						return
					end
					confirmRokakaka = 0
					ctx.Do("UseItem", nil, id)
				end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(120, 30), Parent = top })
			end
			local description = item.Description
			if id == "Rokakaka" then
				description ..= " Removes your current Stand for good."
			end
			Kit.Paragraph(description, { TextSize = 14, TextColor3 = C.InkSoft, LayoutOrder = 2, Parent = row })
		end
	end
	if order == 0 then
		Kit.Paragraph("Your saddlebag is empty.", { LayoutOrder = 1, TextColor3 = C.InkSoft, Parent = items })
	end
end

return StandTab
