--!strict
-- Inventory items.

export type Item = {
	Id: string,
	Name: string,
	Description: string,
	Price: number?, -- nil means not sold in shops
	Usable: boolean,
	Color: Color3,
}

local ItemData = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

ItemData.Items = {
	Arrow = {
		Id = "Arrow",
		Name = "Stand Arrow",
		Description = "Pierce yourself to awaken a Stand. Only works if you have none.",
		Price = 1200,
		Usable = true,
		Color = rgb(196, 160, 80),
	},
	Rokakaka = {
		Id = "Rokakaka",
		Name = "Rokakaka Fruit",
		Description = "Removes your current Stand so a new Arrow can roll again.",
		Price = 2000,
		Usable = true,
		Color = rgb(150, 70, 60),
	},
	RequiemArrow = {
		Id = "RequiemArrow",
		Name = "Requiem Arrow",
		Description = "An arrow with a beetle carved on it. Needed for some evolutions.",
		Usable = false,
		Color = rgb(220, 190, 90),
	},
	CorpseEye = {
		Id = "CorpseEye",
		Name = "Saint's Corpse: Right Eye",
		Description = "A holy remain. Some Stands grow near it.",
		Usable = false,
		Color = rgb(200, 180, 140),
	},
	CorpseArm = {
		Id = "CorpseArm",
		Name = "Saint's Corpse: Left Arm",
		Description = "A holy remain. Some Stands grow near it.",
		Usable = false,
		Color = rgb(200, 180, 140),
	},
	CorpseSpine = {
		Id = "CorpseSpine",
		Name = "Saint's Corpse: Spine",
		Description = "A holy remain. Some Stands grow near it.",
		Usable = false,
		Color = rgb(200, 180, 140),
	},
	CorpseHeart = {
		Id = "CorpseHeart",
		Name = "Saint's Corpse: Heart",
		Description = "A holy remain. Some Stands grow near it.",
		Usable = false,
		Color = rgb(200, 180, 140),
	},
	DioBone = {
		Id = "DioBone",
		Name = "Dio's Bone",
		Description = "Fourteen words are written on a scrap tied to it.",
		Usable = false,
		Color = rgb(226, 220, 200),
	},
	Bandage = {
		Id = "Bandage",
		Name = "Bandage",
		Description = "Restores 40 health over a few seconds.",
		Price = 80,
		Usable = true,
		Color = rgb(230, 220, 200),
	},
	Feed = {
		Id = "Feed",
		Name = "Horse Feed",
		Description = "Restores half of your horse's health.",
		Price = 120,
		Usable = true,
		Color = rgb(190, 160, 90),
	},
} :: { [string]: Item }

ItemData.ShopOrder = { "Arrow", "Rokakaka", "Bandage", "Feed" }

return ItemData
