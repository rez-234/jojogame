--!strict
-- General store purchases and item use (Arrows, Rokakaka, bandages, feed).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemData = require(ReplicatedStorage.Shared.ItemData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local DataService = require(script.Parent.DataService)
local Net = require(script.Parent.Net)
local Combatants = require(script.Parent.Combatants)
local CombatService = require(script.Parent.CombatService)
local StandService = require(script.Parent.StandService)
local HorseService = require(script.Parent.HorseService)
local CharacterService = require(script.Parent.CharacterService)

local ShopService = {}

local BANDAGE_HEAL = 40
local BANDAGE_TIME = 4
local BANDAGE_COOLDOWN = 8

local function inTown(player: Player): boolean
	local zone = CharacterService.Zone(player)
	return zone ~= nil and (zone.Kind == "Town" or zone.Kind == "Start")
end

function ShopService.Init()
	Net.OnRequest("Buy", function(player: Player, itemId: any, quantity: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(itemId) then
			return Net.Fail("Bad request")
		end
		local item = ItemData.Items[itemId]
		if not item or not item.Price then
			return Net.Fail("That is not for sale")
		end
		if not inTown(player) then
			return Net.Fail("Shops are only open in town")
		end
		local qty = if Net.IsNumber(quantity, 1, 25) then math.floor(quantity) else 1
		if not DataService.SpendCash(player, item.Price * qty) then
			return Net.Fail("Not enough cash")
		end
		DataService.AddItem(player, itemId, qty)
		return Net.Ok(profile.Items[itemId])
	end)

	Net.OnRequest("UseItem", function(player: Player, itemId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(itemId) then
			return Net.Fail("Bad request")
		end
		local item = ItemData.Items[itemId]
		if not item or not item.Usable then
			return Net.Fail("That cannot be used")
		end
		if (profile.Items[itemId] or 0) <= 0 then
			return Net.Fail("You have none")
		end
		if itemId == "Arrow" then
			if not Progression.IsUnlocked(profile.Level, "Arrow") then
				return Net.Fail("Arrows unlock at level " .. Progression.UnlockLevel("Arrow"))
			end
			local ok, message = StandService.UseArrow(player)
			return if ok then Net.Ok(message) else Net.Fail(message)
		elseif itemId == "Rokakaka" then
			local ok, message = StandService.UseRokakaka(player)
			return if ok then Net.Ok(message) else Net.Fail(message)
		elseif itemId == "Bandage" then
			local c = Combatants.ForPlayer(player)
			if not c or not Combatants.IsAlive(c) then
				return Net.Fail("You cannot do that now")
			end
			if Combatants.Cooldown(c, "Bandage") > 0 then
				return Net.Fail("You are still wrapping the last one")
			end
			if c.Humanoid.Health >= c.Humanoid.MaxHealth then
				return Net.Fail("You are not hurt")
			end
			DataService.TakeItem(player, "Bandage", 1)
			Combatants.SetCooldown(c, "Bandage", BANDAGE_COOLDOWN)
			CombatService.HealOverTime(c, BANDAGE_HEAL, BANDAGE_TIME)
			return Net.Ok("Bandaged")
		elseif itemId == "Feed" then
			local ok, message = HorseService.Feed(player)
			if ok then
				DataService.TakeItem(player, "Feed", 1)
				return Net.Ok(message)
			end
			return Net.Fail(message)
		end
		return Net.Fail("That cannot be used")
	end)
end

return ShopService
