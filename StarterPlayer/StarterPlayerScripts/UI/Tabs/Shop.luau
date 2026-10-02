--!strict
-- Shop tab: the general store. Shops only trade in town, which the page
-- states plainly next to the buttons.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemData = require(ReplicatedStorage.Shared.ItemData)
local Util = require(ReplicatedStorage.Shared.Util)
local Kit = require(script.Parent.Parent.Kit)
local State = require(script.Parent.Parent.Parent.Controllers.State)
local AmbienceController = require(script.Parent.Parent.Parent.Controllers.AmbienceController)

local Shop = {}
Shop.Name = "Shop"

local C = Kit.Colors

function Shop.Render(page: ScrollingFrame, ctx: any)
	local profile = State.Profile
	if not profile then
		Kit.Paragraph("Loading...", { Parent = page })
		return
	end
	local inTown = AmbienceController.ZoneKind == "Town" or AmbienceController.ZoneKind == "Start"
	local intro = Kit.Section({ LayoutOrder = 1, Parent = page })
	Kit.Row("Cash", "$" .. Util.formatNumber(profile.Cash), { LayoutOrder = 1, Parent = intro })
	Kit.Paragraph(
		if inTown then "The general store is open." else "Shops only trade in town. Ride to the next town to buy.",
		{ LayoutOrder = 2, TextColor3 = if inTown then C.Good else C.Accent, FontFace = Kit.Fonts.BodyBold, Parent = intro }
	)

	for i, id in ItemData.ShopOrder do
		local item = ItemData.Items[id]
		local price = item and item.Price
		if item and price then
			local section = Kit.Section({ LayoutOrder = 1 + i, Parent = page })
			local top = Kit.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Parent = section })
			-- Flat color chip so items are easy to tell apart at a glance.
			Kit.new("Frame", {
				AnchorPoint = Vector2.new(0, 0.5),
				BackgroundColor3 = item.Color,
				BorderSizePixel = 0,
				Position = UDim2.fromScale(0, 0.5),
				Size = UDim2.fromOffset(14, 14),
				Parent = top,
			}, { Kit.Corner(2) })
			Kit.Label(item.Name, { FontFace = Kit.Fonts.Heading, TextSize = 17, Position = UDim2.fromOffset(24, 0), Size = UDim2.new(0.6, -24, 1, 0), Parent = top })
			Kit.Label(string.format("You have %d", profile.Items[id] or 0), {
				TextColor3 = C.InkSoft,
				TextXAlignment = Enum.TextXAlignment.Right,
				Size = UDim2.fromScale(0.4, 1),
				Position = UDim2.fromScale(0.6, 0),
				Parent = top,
			})
			Kit.Paragraph(item.Description, { LayoutOrder = 2, Parent = section })
			local buttons = Kit.ButtonRow({ LayoutOrder = 3, Parent = section })
			for k, qty in { 1, 5 } do
				local cost = price * qty
				local b = Kit.Button(string.format("Buy %d  $%s", qty, Util.formatNumber(cost)), if k == 1 then "Primary" else "Secondary", function()
					ctx.Do("Buy", string.format("Bought %d %s.", qty, item.Name), id, qty)
				end, { Size = UDim2.fromOffset(160, 32), LayoutOrder = k, Parent = buttons })
				b.SetEnabled(inTown and profile.Cash >= cost)
			end
		end
	end
end

return Shop
