--!strict
-- Stand skins. Each skin belongs to a Stand family and applies to every form
-- in that family. Skins are cosmetic only.

export type Source = {
	Kind: string, -- "Shop", "Level", "Mastery", "Race", "Drop", "Default"
	Price: number?,
	Level: number?,
	Move: string?,
	Tier: number?,
	Text: string,
}

export type Skin = {
	Id: string,
	Family: string,
	Name: string,
	Body: Color3?,
	Accent: Color3?,
	Trim: Color3?,
	Eyes: Color3?,
	Material: Enum.Material?,
	Aura: Color3?,
	AuraRate: number?,
	Particles: string?, -- "Sparkle", "Smoke", "Fire"
	PunchColor: Color3?,
	Source: Source,
}

local SkinData = {}

local function rgb(r: number, g: number, b: number): Color3
	return Color3.fromRGB(r, g, b)
end

local function shop(price: number): Source
	return { Kind = "Shop", Price = price, Text = "Shop" }
end

local function level(n: number): Source
	return { Kind = "Level", Level = n, Text = "Reach level " .. n }
end

local function mastery(move: string, tier: number, moveName: string): Source
	local tierNames = { "Novice", "Skilled", "Expert", "Master", "Perfected" }
	return { Kind = "Mastery", Move = move, Tier = tier, Text = tierNames[tier] .. " " .. moveName }
end

local RACE: Source = { Kind = "Race", Text = "Race podium" }
local DROP: Source = { Kind = "Drop", Text = "Boss drop" }

SkinData.Skins = {
	SP_Classic = {
		Id = "SP_Classic",
		Family = "StarPlatinum",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	SP_Manga = {
		Id = "SP_Manga",
		Family = "StarPlatinum",
		Name = "Ink Wash",
		Body = rgb(70, 110, 160),
		Accent = rgb(220, 220, 220),
		Trim = rgb(40, 40, 40),
		Source = shop(4000),
	},
	SP_Star = {
		Id = "SP_Star",
		Family = "StarPlatinum",
		Name = "Starlight",
		Body = rgb(60, 50, 110),
		Accent = rgb(240, 220, 120),
		Aura = rgb(200, 180, 255),
		AuraRate = 10,
		Particles = "Sparkle",
		PunchColor = rgb(200, 180, 255),
		Source = mastery("OraBarrage", 4, "Ora Barrage"),
	},
	TW_Classic = {
		Id = "TW_Classic",
		Family = "TheWorld",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	TW_Shadow = {
		Id = "TW_Shadow",
		Family = "TheWorld",
		Name = "Shadow",
		Body = rgb(60, 54, 50),
		Accent = rgb(200, 40, 40),
		Trim = rgb(20, 20, 20),
		Eyes = rgb(255, 60, 60),
		Source = level(40),
	},
	TW_Heaven = {
		Id = "TW_Heaven",
		Family = "TheWorld",
		Name = "Over Heaven",
		Body = rgb(240, 236, 226),
		Accent = rgb(230, 200, 90),
		Material = Enum.Material.Foil,
		Aura = rgb(255, 240, 180),
		AuraRate = 14,
		Particles = "Sparkle",
		PunchColor = rgb(255, 240, 180),
		Source = DROP,
	},
	CD_Classic = {
		Id = "CD_Classic",
		Family = "CrazyDiamond",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	CD_Diamond = {
		Id = "CD_Diamond",
		Family = "CrazyDiamond",
		Name = "Diamond",
		Body = rgb(170, 220, 240),
		Accent = rgb(240, 240, 255),
		Material = Enum.Material.Glass,
		Aura = rgb(190, 240, 255),
		AuraRate = 8,
		Particles = "Sparkle",
		Source = shop(5000),
	},
	GE_Classic = {
		Id = "GE_Classic",
		Family = "GoldExperience",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	GE_Verdant = {
		Id = "GE_Verdant",
		Family = "GoldExperience",
		Name = "Verdant",
		Body = rgb(110, 160, 80),
		Accent = rgb(230, 210, 120),
		Source = mastery("LifeGiver", 3, "Life Giver"),
	},
	KQ_Classic = {
		Id = "KQ_Classic",
		Family = "KillerQueen",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	KQ_Office = {
		Id = "KQ_Office",
		Family = "KillerQueen",
		Name = "Salaryman",
		Body = rgb(150, 150, 160),
		Accent = rgb(110, 40, 90),
		Trim = rgb(40, 40, 50),
		Source = shop(3500),
	},
	KQ_Blast = {
		Id = "KQ_Blast",
		Family = "KillerQueen",
		Name = "Ignition",
		Body = rgb(230, 120, 70),
		Accent = rgb(60, 40, 40),
		Particles = "Fire",
		Aura = rgb(255, 150, 80),
		AuraRate = 8,
		PunchColor = rgb(255, 150, 80),
		Source = mastery("Detonate", 5, "Detonate"),
	},
	KC_Classic = {
		Id = "KC_Classic",
		Family = "KingCrimson",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	KC_Bone = {
		Id = "KC_Bone",
		Family = "KingCrimson",
		Name = "Bone",
		Body = rgb(230, 220, 200),
		Accent = rgb(150, 30, 40),
		Source = RACE,
	},
	SC_Classic = {
		Id = "SC_Classic",
		Family = "SilverChariot",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	SC_Gilded = {
		Id = "SC_Gilded",
		Family = "SilverChariot",
		Name = "Gilded",
		Body = rgb(214, 180, 90),
		Accent = rgb(160, 120, 60),
		Material = Enum.Material.Foil,
		Source = level(30),
	},
	MR_Classic = {
		Id = "MR_Classic",
		Family = "MagiciansRed",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	MR_Ash = {
		Id = "MR_Ash",
		Family = "MagiciansRed",
		Name = "Ashen",
		Body = rgb(80, 74, 70),
		Accent = rgb(240, 120, 50),
		Particles = "Smoke",
		Aura = rgb(120, 110, 100),
		AuraRate = 6,
		Source = shop(3000),
	},
	HG_Classic = {
		Id = "HG_Classic",
		Family = "HierophantGreen",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	HG_Jade = {
		Id = "HG_Jade",
		Family = "HierophantGreen",
		Name = "Jade",
		Body = rgb(40, 120, 90),
		Accent = rgb(200, 230, 210),
		Material = Enum.Material.Marble,
		Source = level(20),
	},
	TH_Classic = {
		Id = "TH_Classic",
		Family = "TheHand",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	TH_Void = {
		Id = "TH_Void",
		Family = "TheHand",
		Name = "Nullspace",
		Body = rgb(40, 40, 50),
		Accent = rgb(120, 160, 240),
		Source = shop(2500),
	},
	SF_Classic = {
		Id = "SF_Classic",
		Family = "StickyFingers",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	SF_White = {
		Id = "SF_White",
		Family = "StickyFingers",
		Name = "Snow Zip",
		Body = rgb(220, 224, 230),
		Accent = rgb(70, 96, 160),
		Source = shop(2500),
	},
	ST_Classic = {
		Id = "ST_Classic",
		Family = "StoneFree",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	ST_Prison = {
		Id = "ST_Prison",
		Family = "StoneFree",
		Name = "Green Dolphin",
		Body = rgb(70, 100, 80),
		Accent = rgb(220, 160, 60),
		Source = RACE,
	},
	WS_Classic = {
		Id = "WS_Classic",
		Family = "Whitesnake",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	WS_Priest = {
		Id = "WS_Priest",
		Family = "Whitesnake",
		Name = "Priest",
		Body = rgb(40, 40, 46),
		Accent = rgb(220, 200, 120),
		Trim = rgb(230, 230, 230),
		Source = level(35),
	},
	TU_Classic = {
		Id = "TU_Classic",
		Family = "Tusk",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	TU_Golden = {
		Id = "TU_Golden",
		Family = "Tusk",
		Name = "Golden Spin",
		Body = rgb(236, 200, 110),
		Accent = rgb(250, 240, 200),
		Material = Enum.Material.Foil,
		Aura = rgb(255, 220, 120),
		AuraRate = 10,
		Particles = "Sparkle",
		PunchColor = rgb(255, 220, 120),
		Source = mastery("SpinNail", 5, "Spin Nail"),
	},
	TU_Rider = {
		Id = "TU_Rider",
		Family = "Tusk",
		Name = "Jockey",
		Body = rgb(220, 120, 150),
		Accent = rgb(60, 60, 90),
		Source = RACE,
	},
	D4_Classic = {
		Id = "D4_Classic",
		Family = "D4C",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	D4_Patriot = {
		Id = "D4_Patriot",
		Family = "D4C",
		Name = "Patriot",
		Body = rgb(220, 220, 230),
		Accent = rgb(170, 40, 50),
		Trim = rgb(40, 60, 130),
		Source = DROP,
	},
	SM_Classic = {
		Id = "SM_Classic",
		Family = "ScaryMonsters",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	SM_Fossil = {
		Id = "SM_Fossil",
		Family = "ScaryMonsters",
		Name = "Fossil",
		Body = rgb(200, 190, 170),
		Accent = rgb(120, 100, 80),
		Material = Enum.Material.Limestone,
		Source = shop(2200),
	},
	MD_Classic = {
		Id = "MD_Classic",
		Family = "Mandom",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	MD_Brass = {
		Id = "MD_Brass",
		Family = "Mandom",
		Name = "Brass Watch",
		Body = rgb(190, 150, 70),
		Accent = rgb(240, 220, 160),
		Material = Enum.Material.Foil,
		Source = mastery("SixSeconds", 4, "Six Seconds"),
	},
	CR_Classic = {
		Id = "CR_Classic",
		Family = "Cream",
		Name = "Classic",
		Source = { Kind = "Default", Text = "Default" },
	},
	CR_Abyss = {
		Id = "CR_Abyss",
		Family = "Cream",
		Name = "Abyss",
		Body = rgb(24, 20, 30),
		Accent = rgb(140, 60, 200),
		Particles = "Smoke",
		Aura = rgb(60, 30, 80),
		AuraRate = 8,
		Source = DROP,
	},
} :: { [string]: Skin }

function SkinData.ForFamily(family: string): { Skin }
	local list = {}
	for _, skin in SkinData.Skins do
		if skin.Family == family then
			table.insert(list, skin)
		end
	end
	table.sort(list, function(a, b)
		local ad = if a.Source.Kind == "Default" then 0 else 1
		local bd = if b.Source.Kind == "Default" then 0 else 1
		if ad ~= bd then
			return ad < bd
		end
		return a.Name < b.Name
	end)
	return list
end

function SkinData.DefaultFor(family: string): Skin?
	for _, skin in SkinData.Skins do
		if skin.Family == family and skin.Source.Kind == "Default" then
			return skin
		end
	end
	return nil
end

return SkinData
