--!strict
-- Stand skins: unlocking from levels, mastery, races, boss drops and the
-- shop, and equipping per Stand family. Skins are cosmetic only.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SkinData = require(ReplicatedStorage.Shared.SkinData)
local Progression = require(ReplicatedStorage.Shared.Progression)
local Types = require(ReplicatedStorage.Shared.Types)
local DataService = require(script.Parent.DataService)
local Signals = require(script.Parent.Signals)
local Net = require(script.Parent.Net)

local SkinService = {}

function SkinService.Owns(profile: Types.Profile, skinId: string): boolean
	local skin = SkinData.Skins[skinId]
	if not skin then
		return false
	end
	if skin.Source.Kind == "Default" then
		return true
	end
	return profile.Skins.Owned[skinId] == true
end

-- Grants a skin. Returns true if it was new.
function SkinService.Grant(player: Player, skinId: string): boolean
	local profile = DataService.Get(player)
	local skin = SkinData.Skins[skinId]
	if not profile or not skin or SkinService.Owns(profile, skinId) then
		return false
	end
	profile.Skins.Owned[skinId] = true
	DataService.MarkDirty(player)
	Net.Notify(player, "Skin", { Id = skinId, Name = skin.Name, Family = skin.Family })
	return true
end

-- Grants a random skin the player does not own from a source kind.
function SkinService.GrantRandom(player: Player, sourceKind: string): string?
	local profile = DataService.Get(player)
	if not profile then
		return nil
	end
	local options = {}
	for id, skin in SkinData.Skins do
		if skin.Source.Kind == sourceKind and not SkinService.Owns(profile, id) then
			table.insert(options, id)
		end
	end
	table.sort(options)
	if #options == 0 then
		return nil
	end
	local pick = options[math.random(1, #options)]
	SkinService.Grant(player, pick)
	return pick
end

function SkinService.Equipped(player: Player, family: string): SkinData.Skin?
	local profile = DataService.Get(player)
	if profile then
		local id = profile.Skins.Equipped[family]
		if id and SkinService.Owns(profile, id) then
			local skin = SkinData.Skins[id]
			if skin and skin.Family == family then
				return skin
			end
		end
	end
	return SkinData.DefaultFor(family)
end

-- Grants every level and mastery skin the profile already qualifies for.
local function reconcile(player: Player)
	local profile = DataService.Get(player)
	if not profile then
		return
	end
	for id, skin in SkinData.Skins do
		local src = skin.Source
		if src.Kind == "Level" and src.Level and profile.Level >= src.Level then
			if not profile.Skins.Owned[id] then
				profile.Skins.Owned[id] = true
			end
		elseif src.Kind == "Mastery" and src.Move and src.Tier then
			local tier = Progression.MasteryTier(Progression.MasteryXP(profile, skin.Family, src.Move))
			if tier.Index >= src.Tier and not profile.Skins.Owned[id] then
				profile.Skins.Owned[id] = true
			end
		end
	end
	DataService.MarkDirty(player)
end

function SkinService.Init()
	Net.OnRequest("EquipSkin", function(player: Player, skinId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(skinId) then
			return Net.Fail("Bad skin")
		end
		local skin = SkinData.Skins[skinId]
		if not skin then
			return Net.Fail("Unknown skin")
		end
		if not SkinService.Owns(profile, skinId) then
			return Net.Fail("You have not unlocked this skin yet")
		end
		profile.Skins.Equipped[skin.Family] = skinId
		DataService.MarkDirty(player)
		Signals.StandChanged:Fire(player)
		return Net.Ok()
	end)

	Net.OnRequest("BuySkin", function(player: Player, skinId: any)
		local profile = DataService.Get(player)
		if not profile or not Net.IsString(skinId) then
			return Net.Fail("Bad skin")
		end
		local skin = SkinData.Skins[skinId]
		if not skin or skin.Source.Kind ~= "Shop" or not skin.Source.Price then
			return Net.Fail("That skin is not sold")
		end
		if SkinService.Owns(profile, skinId) then
			return Net.Fail("You already own it")
		end
		if not DataService.SpendCash(player, skin.Source.Price) then
			return Net.Fail("Not enough cash")
		end
		SkinService.Grant(player, skinId)
		return Net.Ok()
	end)

	DataService.OnLoaded(function(player)
		reconcile(player)
	end)

	Signals.LevelUp:Connect(function(player, level)
		for id, skin in SkinData.Skins do
			if skin.Source.Kind == "Level" and skin.Source.Level and skin.Source.Level <= level then
				SkinService.Grant(player, id)
			end
		end
	end)

	Signals.MasteryTier:Connect(function(player, family, moveId, tier)
		for id, skin in SkinData.Skins do
			local src = skin.Source
			if src.Kind == "Mastery" and skin.Family == family and src.Move == moveId and src.Tier and src.Tier <= tier then
				SkinService.Grant(player, id)
			end
		end
	end)
end

return SkinService
