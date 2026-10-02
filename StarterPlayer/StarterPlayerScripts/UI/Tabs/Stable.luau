--!strict
-- Stable tab: your horses (equip, heal, rename, release), tack for the
-- horse you ride, and horses for sale. Buying and healing need you to stand
-- by a stable; the page says so instead of hiding the buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local HorseData = require(ReplicatedStorage.Shared.HorseData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Util = require(ReplicatedStorage.Shared.Util)
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)

local Stable = {}
Stable.Name = "Stable"

local C = Kit.Colors
local S = Kit.Space

local info: any = nil
local confirmRelease: { [string]: number } = {}

local SLOTS = {
	{ Key = "Saddle", Text = "Saddle", List = HorseData.Saddles },
	{ Key = "Blanket", Text = "Blanket", List = HorseData.Blankets },
	{ Key = "Mane", Text = "Mane", List = HorseData.ManeStyles },
	{ Key = "Shoes", Text = "Shoes", List = HorseData.Horseshoes },
}

function Stable.OnOpen(ctx: any)
	local result = State.Request("StableInfo")
	if result.Ok then
		info = result.Data
		ctx.Rerender()
	end
end

local function statsLine(stats: Progression.HorseStats): string
	return string.format("Top speed %s   Stamina %d   Jump %d", Kit.Speed(stats.Gallop), math.floor(stats.StaminaMax), math.floor(stats.JumpPower))
end

local function horseCard(parent: Instance, ctx: any, profile: any, horse: any, order: number)
	local stats = Progression.HorseStats(horse)
	local breed = HorseData.Breeds[horse.Breed]
	local equipped = profile.EquippedHorse == horse.Id
	local section = Kit.Section({ LayoutOrder = order, Parent = parent })
	if equipped then
		section.BackgroundColor3 = C.ParchmentDark
	end
	local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = section })
	Kit.Label(horse.Name, { FontFace = Kit.Fonts.Heading, TextSize = 18, Size = UDim2.fromScale(0.6, 1), TextTruncate = Enum.TextTruncate.AtEnd, Parent = top })
	Kit.Label(if equipped then "Your ride" else "", { FontFace = Kit.Fonts.BodyBold, TextColor3 = C.Good, TextXAlignment = Enum.TextXAlignment.Right, Size = UDim2.fromScale(0.4, 1), Position = UDim2.fromScale(0.6, 0), Parent = top })
	local rarity = Kit.Label(string.format("%s, %s   Level %d", if breed then breed.Name else horse.Breed, if breed then breed.Rarity else "", horse.Level), { LayoutOrder = 2, TextSize = 14, Parent = section })
	rarity.TextColor3 = if breed then C.Rarity[breed.Rarity] or C.InkSoft else C.InkSoft
	Kit.Label(statsLine(stats), { LayoutOrder = 3, FontFace = Kit.Fonts.Numbers, TextSize = 13, TextColor3 = C.InkSoft, Parent = section })

	local xpNeed = Progression.HorseXPForLevel(horse.Level)
	local xpBar = Kit.Bar(C.XP, 12, { LayoutOrder = 4, Parent = section })
	if horse.Level >= Config.Horse.MaxLevel then
		xpBar.Set(1, "Max level")
	else
		xpBar.Set(horse.XP / math.max(1, xpNeed), string.format("%d / %d XP", math.floor(horse.XP), xpNeed))
	end
	local health = if horse.Health < 0 then stats.MaxHealth else horse.Health
	local healthBar = Kit.Bar(C.Health, 14, { LayoutOrder = 5, Parent = section })
	healthBar.Set(health / math.max(1, stats.MaxHealth), string.format("%d / %d", math.ceil(health), stats.MaxHealth))

	local buttons = Kit.ButtonRow({ LayoutOrder = 6, Parent = section })
	if not equipped then
		Kit.Button("Ride this one", "Primary", function()
			ctx.Do("EquipHorse", horse.Name .. " is saddled. Whistle with H.", horse.Id)
		end, { Size = UDim2.fromOffset(140, 32), LayoutOrder = 1, Parent = buttons })
	end
	local missing = stats.MaxHealth - health
	if missing > 0 then
		local cost = math.ceil(missing * Config.Horse.HealCostPerMissingHP)
		Kit.Button("Heal $" .. cost, "Secondary", function()
			ctx.Do("HealHorse", horse.Name .. " is patched up.", horse.Id)
		end, { Size = UDim2.fromOffset(120, 32), LayoutOrder = 2, Parent = buttons })
	end
	local releaseArmed = (confirmRelease[horse.Id] or 0) > os.clock()
	local release = Kit.Button(if releaseArmed then "Confirm release" else "Release", "Ghost", function()
		if (confirmRelease[horse.Id] or 0) > os.clock() then
			confirmRelease[horse.Id] = nil
			ctx.Do("ReleaseHorse", horse.Name .. " runs free.", horse.Id)
		else
			confirmRelease[horse.Id] = os.clock() + 4
			ctx.Rerender()
		end
	end, { Size = UDim2.fromOffset(if releaseArmed then 150 else 100, 32), LayoutOrder = 4, Parent = buttons })
	release.SetEnabled(#profile.Horses > 1)

	-- Rename.
	local renameRow = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 32), LayoutOrder = 7, Parent = section })
	local box = Kit.new("TextBox", {
		BackgroundColor3 = C.Paper,
		BorderSizePixel = 0,
		PlaceholderText = "New name",
		PlaceholderColor3 = C.InkSoft,
		Text = "",
		TextColor3 = C.Ink,
		FontFace = Kit.Fonts.Body,
		TextSize = Kit.Text.Body,
		TextXAlignment = Enum.TextXAlignment.Left,
		ClearTextOnFocus = false,
		Size = UDim2.new(1, -110, 1, 0),
		Parent = renameRow,
	}, { Kit.Corner(2), Kit.Stroke(C.Ink, 1), Kit.Padding(0, S.S) }) :: TextBox
	Kit.Button("Rename", "Secondary", function()
		local text = box.Text
		if #text >= 2 then
			ctx.Do("RenameHorse", "Name saved.", horse.Id, text)
		end
	end, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(100, 32), Parent = renameRow })
end

local function tackSection(parent: Instance, ctx: any, profile: any, horse: any, order: number)
	local section = Kit.Section({ LayoutOrder = order, Parent = parent })
	Kit.Heading("Tack for " .. horse.Name, Kit.Text.Label, { LayoutOrder = 0, Parent = section })
	for i, slot in SLOTS do
		local current = horse.Cosmetics[slot.Key]
		Kit.Label(slot.Text, { FontFace = Kit.Fonts.BodyBold, LayoutOrder = i * 10, Parent = section })
		local row = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = i * 10 + 1, Parent = section })
		Kit.new("UIGridLayout", { CellSize = UDim2.new(0.33, -6, 0, 32), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = row })
		for k, option in slot.List do
			local owned = option.Price == 0 or profile.HorseCosmetics[slot.Key .. ":" .. option.Id] == true
			local isCurrent = current == option.Id
			local label = if isCurrent then option.Name .. " (on)" elseif owned then option.Name else string.format("%s $%s", option.Name, Util.formatNumber(option.Price))
			local button = Kit.Button(label, if isCurrent then "Secondary" elseif owned then "Ghost" else "Primary", function()
				if isCurrent then
					return
				end
				if owned then
					ctx.Do("SetHorseCosmetic", nil, horse.Id, slot.Key, option.Id)
				else
					local ok = ctx.Do("BuyHorseCosmetic", option.Name .. " bought.", slot.Key, option.Id)
					if ok then
						ctx.Do("SetHorseCosmetic", nil, horse.Id, slot.Key, option.Id)
					end
				end
			end, { LayoutOrder = k, Parent = row })
			button.Instance.TextSize = 14
			if not owned and profile.Cash < option.Price then
				button.SetEnabled(false)
			end
		end
	end
end

function Stable.Render(page: ScrollingFrame, ctx: any)
	local profile = State.Profile
	if not profile then
		Kit.Paragraph("Loading...", { Parent = page })
		return
	end
	local near = info and info.Near == true
	local intro = Kit.Section({ LayoutOrder = 1, Parent = page })
	Kit.Paragraph(
		if near
			then "You are at a stable. Buy, heal and outfit horses here."
			else "Buying horses, healing and new tack need a stable keeper. Every town has one. You can still pick your ride and rename horses from anywhere.",
		{ LayoutOrder = 1, Parent = intro }
	)
	Kit.Paragraph("Wild herds roam every stage. Walk up slowly and hold E to calm one, then keep the marker in the band.", { LayoutOrder = 2, TextSize = 14, TextColor3 = C.InkSoft, Parent = intro })

	Kit.Heading(string.format("Your horses (%d / %d)", #profile.Horses, Config.Horse.MaxOwned), Kit.Text.Label, { LayoutOrder = 2, Parent = page })
	local equippedHorse = nil
	for i, horse in profile.Horses do
		horseCard(page, ctx, profile, horse, 2 + i)
		if horse.Id == profile.EquippedHorse then
			equippedHorse = horse
		end
	end
	if equippedHorse then
		tackSection(page, ctx, profile, equippedHorse, 40)
	end

	local market = Kit.Section({ LayoutOrder = 50, Parent = page })
	Kit.Heading("Horses for sale", Kit.Text.Label, { LayoutOrder = 0, Parent = market })
	if not info then
		Kit.Paragraph("Asking the stable keeper...", { LayoutOrder = 1, TextColor3 = C.InkSoft, Parent = market })
		return
	end
	for i, breed in info.Breeds do
		local stats = Progression.BreedStats(breed.Id)
		local row = Kit.new("Frame", {
			BackgroundColor3 = C.Parchment,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = i,
			Parent = market,
		}, { Kit.Corner(2), Kit.Padding(S.S, S.M), Kit.List(2) })
		local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1, Parent = row })
		local name = Kit.Label(string.format("%s  %s", breed.Name, breed.Rarity), { FontFace = Kit.Fonts.BodyBold, Size = UDim2.new(1, -150, 1, 0), Parent = top })
		name.TextColor3 = C.Rarity[breed.Rarity] or C.Ink
		local buy = Kit.Button(if breed.Unlocked then "$" .. Util.formatNumber(breed.Price) else "Locked", "Primary", function()
			ctx.Do("BuyHorse", "New horse in your stable.", breed.Id)
		end, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(140, 30), Parent = top })
		buy.SetEnabled(near and breed.Unlocked and profile.Cash >= breed.Price and #profile.Horses < Config.Horse.MaxOwned)
		Kit.Label(statsLine(stats), { FontFace = Kit.Fonts.Numbers, TextSize = 13, TextColor3 = C.InkSoft, LayoutOrder = 2, Parent = row })
		Kit.Paragraph(breed.Description, { TextSize = 14, LayoutOrder = 3, Parent = row })
	end
end

return Stable
