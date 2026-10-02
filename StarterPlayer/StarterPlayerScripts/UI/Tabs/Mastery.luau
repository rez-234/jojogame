--!strict
-- Mastery tab: every move of your Stand family with its tier, progress to
-- the next tier and the bonuses it gives. Mastery carries over when the
-- Stand evolves because it belongs to the family.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local StandData = require(ReplicatedStorage.Shared.StandData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Util = require(ReplicatedStorage.Shared.Util)
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)

local Mastery = {}
Mastery.Name = "Mastery"

local C = Kit.Colors

local function bonusText(tier: Progression.TierInfo): string
	if tier.Index <= 1 then
		return "No bonus yet"
	end
	local parts = {}
	if tier.Damage > 0 then
		table.insert(parts, string.format("+%d%% damage", math.floor(tier.Damage * 100 + 0.5)))
	end
	if tier.Cooldown > 0 then
		table.insert(parts, string.format("%d%% shorter cooldown", math.floor(tier.Cooldown * 100 + 0.5)))
	end
	if tier.Speed > 0 then
		table.insert(parts, string.format("+%d%% speed", math.floor(tier.Speed * 100 + 0.5)))
	end
	if tier.ExtraHits > 0 then
		table.insert(parts, string.format("+%d hits on multi hit moves", tier.ExtraHits))
	end
	return table.concat(parts, ", ")
end

function Mastery.Render(page: ScrollingFrame, _ctx: any)
	local profile = State.Profile
	if not profile then
		Kit.Paragraph("Loading...", { Parent = page })
		return
	end
	local stand = StandData.Get(profile.Stand)
	local intro = Kit.Section({ LayoutOrder = 1, Parent = page })
	Kit.Paragraph(
		"Moves grow stronger as they land. Hitting the same target again and again earns less each time, so spread your hits around. "
			.. "Perfecting any move gives your Stand a golden aura.",
		{ LayoutOrder = 1, Parent = intro }
	)
	local tiersLine = {}
	for _, t in Config.Mastery.Tiers do
		table.insert(tiersLine, string.format("%s %s", t.Name, Util.formatNumber(t.XP)))
	end
	Kit.Paragraph("Tiers: " .. table.concat(tiersLine, ", "), { LayoutOrder = 2, TextSize = 14, TextColor3 = C.InkSoft, Parent = intro })

	if not stand then
		Kit.Paragraph("Awaken a Stand to start mastering moves.", { LayoutOrder = 2, Parent = page })
		return
	end

	local seen: { [string]: boolean } = {}
	local order = 1
	for _, form in StandData.FamilyForms(stand.Family) do
		for _, moveId in form.Moves do
			if not seen[moveId] then
				seen[moveId] = true
				local move = StandData.GetMove(moveId)
				if move then
					order += 1
					local xp = Progression.MasteryXP(profile, stand.Family, moveId)
					local tier = Progression.MasteryTier(xp)
					local section = Kit.Section({ LayoutOrder = order, Parent = page })
					local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = 1, Parent = section })
					Kit.Label(move.Name, { FontFace = Kit.Fonts.Heading, TextSize = 17, Size = UDim2.fromScale(0.6, 1), Parent = top })
					local tierLabel = Kit.Label(tier.Name, { FontFace = Kit.Fonts.BodyBold, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(0.4, 1), Position = UDim2.fromScale(0.6, 0), Parent = top })
					tierLabel.TextColor3 = if tier.Name == "Perfected" then C.Brass else C.Ink
					local bar = Kit.Bar(if tier.Name == "Perfected" then C.Brass else C.Leather, 16, { LayoutOrder = 2, Parent = section })
					local nextXP = tier.NextXP
					if nextXP then
						bar.Set((xp - tier.XP) / math.max(1, nextXP - tier.XP), string.format("%s / %s", Util.formatNumber(xp), Util.formatNumber(nextXP)))
					else
						bar.Set(1, Util.formatNumber(xp) .. " XP, perfected")
					end
					Kit.Paragraph(bonusText(tier), { LayoutOrder = 3, TextSize = 14, TextColor3 = C.InkSoft, Parent = section })
					if form.Stage > stand.Stage then
						Kit.Paragraph("Unlocks when your Stand evolves into " .. form.Name .. ".", { LayoutOrder = 4, TextSize = 14, TextColor3 = C.Accent, Parent = section })
					end
				end
			end
		end
	end

	-- Other families you have trained before keep their progress.
	local others = {}
	for family, moves in profile.Mastery do
		if family ~= stand.Family then
			local total = 0
			for _, xp in moves do
				total += xp
			end
			if total > 0 then
				local base = StandData.Get(family)
				table.insert(others, { Name = if base then base.Name else family, Total = total })
			end
		end
	end
	if #others > 0 then
		local section = Kit.Section({ LayoutOrder = order + 1, Parent = page })
		Kit.Heading("Other Stands you have trained", Kit.Text.Label, { LayoutOrder = 0, Parent = section })
		for i, o in others do
			Kit.Row(o.Name, Util.formatNumber(o.Total) .. " XP", { LayoutOrder = i, Parent = section })
		end
	end
end

return Mastery
