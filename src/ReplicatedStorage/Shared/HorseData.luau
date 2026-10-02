--!strict
-- Horse breeds, coats and cosmetics.

export type Breed = {
	Id: string,
	Name: string,
	Rarity: string,
	Speed: number, -- multiplier on gait speeds
	Stamina: number, -- multiplier on max stamina
	Acceleration: number,
	JumpPower: number,
	Turning: number,
	Durability: number, -- max health
	Price: number,
	SizeScale: number,
	Coats: { Color3 },
	Manes: { Color3 },
	Patterns: { string }, -- "Socks", "Blaze", "Spots", "Patches", "Dapple", "Star"
	InStable: boolean,
	WildStages: { number },
	MinLevel: number,
	Description: string,
}

export type CosmeticOption = {
	Id: string,
	Name: string,
	Color: Color3,
	Price: number,
	Material: Enum.Material?,
}

local HorseData = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local BAY = rgb(122, 72, 40)
local CHESTNUT = rgb(150, 82, 44)
local DARK_BAY = rgb(82, 50, 30)
local BLACK = rgb(28, 24, 22)
local GREY = rgb(170, 168, 162)
local WHITE = rgb(232, 228, 220)
local PALOMINO = rgb(214, 170, 96)
local DUN = rgb(178, 146, 102)
local CREAM = rgb(240, 224, 190)

HorseData.Breeds = {
	Mustang = {
		Id = "Mustang",
		Name = "Mustang",
		Rarity = "Common",
		Speed = 1.0,
		Stamina = 1.05,
		Acceleration = 1.0,
		JumpPower = 1.0,
		Turning = 1.05,
		Durability = 110,
		Price = 600,
		SizeScale = 0.95,
		Coats = { BAY, DUN, CHESTNUT, GREY },
		Manes = { BLACK, DARK_BAY },
		Patterns = { "Socks", "Star" },
		InStable = true,
		WildStages = { 1, 2, 3, 4, 5 },
		MinLevel = 1,
		Description = "Tough wild stock. Steady on rough ground.",
	},
	QuarterHorse = {
		Id = "QuarterHorse",
		Name = "Quarter Horse",
		Rarity = "Common",
		Speed = 0.98,
		Stamina = 0.95,
		Acceleration = 1.25,
		JumpPower = 1.0,
		Turning = 1.15,
		Durability = 100,
		Price = 750,
		SizeScale = 1.0,
		Coats = { CHESTNUT, BAY, rgb(110, 60, 36) },
		Manes = { DARK_BAY, BLACK },
		Patterns = { "Blaze", "Socks" },
		InStable = true,
		WildStages = { 5, 6 },
		MinLevel = 1,
		Description = "Explosive off the line and quick to turn.",
	},
	Appaloosa = {
		Id = "Appaloosa",
		Name = "Appaloosa",
		Rarity = "Uncommon",
		Speed = 1.04,
		Stamina = 1.1,
		Acceleration = 1.0,
		JumpPower = 1.05,
		Turning = 1.0,
		Durability = 115,
		Price = 1400,
		SizeScale = 1.0,
		Coats = { WHITE, GREY, CREAM },
		Manes = { GREY, BLACK },
		Patterns = { "Spots" },
		InStable = true,
		WildStages = { 3, 6, 7 },
		MinLevel = 1,
		Description = "Spotted coat, long legs, good wind.",
	},
	Pinto = {
		Id = "Pinto",
		Name = "Pinto",
		Rarity = "Uncommon",
		Speed = 1.02,
		Stamina = 1.05,
		Acceleration = 1.05,
		JumpPower = 1.0,
		Turning = 1.05,
		Durability = 110,
		Price = 1300,
		SizeScale = 0.98,
		Coats = { BAY, BLACK, CHESTNUT },
		Manes = { WHITE, BLACK },
		Patterns = { "Patches", "Blaze" },
		InStable = true,
		WildStages = { 2, 5, 8 },
		MinLevel = 1,
		Description = "Patchwork coat and an easy temper.",
	},
	Palomino = {
		Id = "Palomino",
		Name = "Palomino",
		Rarity = "Uncommon",
		Speed = 1.05,
		Stamina = 1.0,
		Acceleration = 1.05,
		JumpPower = 1.05,
		Turning = 1.0,
		Durability = 105,
		Price = 1600,
		SizeScale = 1.0,
		Coats = { PALOMINO, rgb(226, 186, 110) },
		Manes = { CREAM, WHITE },
		Patterns = { "Blaze", "Socks" },
		InStable = true,
		WildStages = { 2, 3 },
		MinLevel = 1,
		Description = "Golden coat with a pale mane.",
	},
	Arabian = {
		Id = "Arabian",
		Name = "Arabian",
		Rarity = "Rare",
		Speed = 1.1,
		Stamina = 1.25,
		Acceleration = 1.05,
		JumpPower = 1.1,
		Turning = 1.1,
		Durability = 100,
		Price = 3200,
		SizeScale = 0.95,
		Coats = { GREY, WHITE, BLACK, CHESTNUT },
		Manes = { WHITE, BLACK, GREY },
		Patterns = { "Dapple", "Star" },
		InStable = true,
		WildStages = { 2 },
		MinLevel = 8,
		Description = "Built for distance. Barely tires.",
	},
	Thoroughbred = {
		Id = "Thoroughbred",
		Name = "Thoroughbred",
		Rarity = "Rare",
		Speed = 1.16,
		Stamina = 0.95,
		Acceleration = 1.12,
		JumpPower = 1.05,
		Turning = 0.95,
		Durability = 95,
		Price = 3600,
		SizeScale = 1.08,
		Coats = { BAY, DARK_BAY, CHESTNUT, BLACK },
		Manes = { BLACK, DARK_BAY },
		Patterns = { "Blaze", "Star", "Socks" },
		InStable = true,
		WildStages = {},
		MinLevel = 8,
		Description = "Race bred. The fastest stable horse.",
	},
	Clydesdale = {
		Id = "Clydesdale",
		Name = "Clydesdale",
		Rarity = "Rare",
		Speed = 0.9,
		Stamina = 1.3,
		Acceleration = 0.85,
		JumpPower = 0.85,
		Turning = 0.85,
		Durability = 190,
		Price = 2800,
		SizeScale = 1.25,
		Coats = { BAY, DARK_BAY, BLACK },
		Manes = { BLACK, CREAM },
		Patterns = { "Socks", "Blaze" },
		InStable = true,
		WildStages = { 6 },
		MinLevel = 8,
		Description = "Huge and slow, but hard to knock down.",
	},
	BlackStallion = {
		Id = "BlackStallion",
		Name = "Black Stallion",
		Rarity = "Epic",
		Speed = 1.2,
		Stamina = 1.15,
		Acceleration = 1.15,
		JumpPower = 1.15,
		Turning = 1.05,
		Durability = 130,
		Price = 7500,
		SizeScale = 1.1,
		Coats = { BLACK },
		Manes = { BLACK },
		Patterns = {},
		InStable = true,
		WildStages = { 4 },
		MinLevel = 25,
		Description = "Jet black, fast and proud.",
	},
	AkhalTeke = {
		Id = "AkhalTeke",
		Name = "Akhal-Teke",
		Rarity = "Epic",
		Speed = 1.22,
		Stamina = 1.2,
		Acceleration = 1.1,
		JumpPower = 1.1,
		Turning = 1.1,
		Durability = 105,
		Price = 8200,
		SizeScale = 1.0,
		Coats = { rgb(204, 160, 84), rgb(170, 130, 70) },
		Manes = { rgb(150, 110, 60) },
		Patterns = { "Star" },
		InStable = true,
		WildStages = {},
		MinLevel = 25,
		Description = "A metallic sheen and a desert heart.",
	},
	Valkyrie = {
		Id = "Valkyrie",
		Name = "Valkyrie",
		Rarity = "Legendary",
		Speed = 1.28,
		Stamina = 1.3,
		Acceleration = 1.2,
		JumpPower = 1.2,
		Turning = 1.15,
		Durability = 140,
		Price = 0,
		SizeScale = 1.05,
		Coats = { rgb(96, 62, 40) },
		Manes = { rgb(58, 38, 26) },
		Patterns = { "Socks" },
		InStable = false,
		WildStages = {},
		MinLevel = 1,
		Description = "A rider's partner from the first race. Race reward.",
	},
	SlowDancer = {
		Id = "SlowDancer",
		Name = "Slow Dancer",
		Rarity = "Legendary",
		Speed = 1.24,
		Stamina = 1.45,
		Acceleration = 1.15,
		JumpPower = 1.25,
		Turning = 1.2,
		Durability = 130,
		Price = 0,
		SizeScale = 1.0,
		Coats = { rgb(150, 138, 120) },
		Manes = { rgb(210, 200, 186) },
		Patterns = { "Dapple" },
		InStable = false,
		WildStages = {},
		MinLevel = 1,
		Description = "Calm and clever. Boss reward.",
	},
	SilverBullet = {
		Id = "SilverBullet",
		Name = "Silver Bullet",
		Rarity = "Legendary",
		Speed = 1.32,
		Stamina = 1.15,
		Acceleration = 1.3,
		JumpPower = 1.2,
		Turning = 1.1,
		Durability = 120,
		Price = 0,
		SizeScale = 1.06,
		Coats = { rgb(196, 198, 200) },
		Manes = { rgb(236, 236, 236) },
		Patterns = { "Blaze" },
		InStable = false,
		WildStages = {},
		MinLevel = 1,
		Description = "Silver grey and terrifyingly quick. Race reward.",
	},
	GhostHorse = {
		Id = "GhostHorse",
		Name = "Pale Rider",
		Rarity = "Mythic",
		Speed = 1.35,
		Stamina = 1.4,
		Acceleration = 1.3,
		JumpPower = 1.35,
		Turning = 1.2,
		Durability = 150,
		Price = 0,
		SizeScale = 1.08,
		Coats = { rgb(238, 240, 236) },
		Manes = { rgb(200, 210, 214) },
		Patterns = {},
		InStable = false,
		WildStages = { 4, 8 },
		MinLevel = 1,
		Description = "Seen at dusk on the high passes. Almost never caught.",
	},
} :: { [string]: Breed }

HorseData.Order = {
	"Mustang",
	"QuarterHorse",
	"Appaloosa",
	"Pinto",
	"Palomino",
	"Arabian",
	"Thoroughbred",
	"Clydesdale",
	"BlackStallion",
	"AkhalTeke",
	"Valkyrie",
	"SlowDancer",
	"SilverBullet",
	"GhostHorse",
}

HorseData.RarityWildWeight = {
	Common = 50,
	Uncommon = 26,
	Rare = 12,
	Epic = 5,
	Legendary = 1,
	Mythic = 0.4,
}

HorseData.Saddles = {
	{ Id = "Brown", Name = "Brown Leather", Color = rgb(96, 58, 34), Price = 0 },
	{ Id = "Tan", Name = "Tan Leather", Color = rgb(164, 116, 70), Price = 250 },
	{ Id = "Black", Name = "Black Leather", Color = rgb(36, 30, 28), Price = 400 },
	{ Id = "Oxblood", Name = "Oxblood", Color = rgb(110, 36, 30), Price = 600 },
	{ Id = "Bone", Name = "Bone White", Color = rgb(222, 210, 186), Price = 900 },
} :: { CosmeticOption }

HorseData.Blankets = {
	{ Id = "Red", Name = "Red Wool", Color = rgb(150, 44, 36), Price = 0 },
	{ Id = "Navy", Name = "Navy Wool", Color = rgb(40, 52, 82), Price = 200 },
	{ Id = "Olive", Name = "Olive Wool", Color = rgb(88, 92, 54), Price = 200 },
	{ Id = "Mustard", Name = "Mustard", Color = rgb(196, 150, 54), Price = 350 },
	{ Id = "Charcoal", Name = "Charcoal", Color = rgb(52, 50, 48), Price = 350 },
	{ Id = "Striped", Name = "Trade Stripe", Color = rgb(196, 176, 140), Price = 700 },
} :: { CosmeticOption }

HorseData.ManeStyles = {
	{ Id = "Classic", Name = "Classic", Color = Color3.new(), Price = 0 },
	{ Id = "Roached", Name = "Roached", Color = Color3.new(), Price = 300 },
	{ Id = "Braided", Name = "Braided", Color = Color3.new(), Price = 500 },
	{ Id = "Long", Name = "Long", Color = Color3.new(), Price = 500 },
} :: { CosmeticOption }

HorseData.Horseshoes = {
	{ Id = "Iron", Name = "Iron", Color = rgb(70, 70, 72), Price = 0, Material = Enum.Material.Metal },
	{ Id = "Steel", Name = "Steel", Color = rgb(160, 164, 170), Price = 300, Material = Enum.Material.DiamondPlate },
	{ Id = "Silver", Name = "Silver", Color = rgb(214, 214, 220), Price = 900, Material = Enum.Material.Foil },
	{ Id = "Gold", Name = "Gold", Color = rgb(222, 178, 70), Price = 2000, Material = Enum.Material.Foil },
} :: { CosmeticOption }

function HorseData.FindCosmetic(slot: string, id: string): CosmeticOption?
	local list: { CosmeticOption }
	if slot == "Saddle" then
		list = HorseData.Saddles
	elseif slot == "Blanket" then
		list = HorseData.Blankets
	elseif slot == "Mane" then
		list = HorseData.ManeStyles
	elseif slot == "Shoes" then
		list = HorseData.Horseshoes
	else
		return nil
	end
	for _, option in list do
		if option.Id == id then
			return option
		end
	end
	return nil
end

HorseData.Names = {
	"Dusty",
	"Juniper",
	"Copper",
	"Whiskey",
	"Sage",
	"Rio",
	"Maverick",
	"Bandit",
	"Biscuit",
	"Comet",
	"Duke",
	"Sierra",
	"Ranger",
	"Mesa",
	"Ember",
	"Cinder",
	"Pecos",
	"Tumble",
	"Ghost",
	"Dakota",
}

return HorseData
