--!strict
-- Visual identity shared by world signage and the UI: a flat Western poster
-- look built from parchment, leather and ink with one oxblood accent.

local Style = {}

Style.Colors = {
	Parchment = Color3.fromRGB(234, 222, 196),
	ParchmentDark = Color3.fromRGB(214, 198, 166),
	Paper = Color3.fromRGB(244, 236, 218),
	Ink = Color3.fromRGB(38, 30, 24),
	InkSoft = Color3.fromRGB(88, 72, 58),
	Leather = Color3.fromRGB(64, 44, 32),
	LeatherDark = Color3.fromRGB(40, 28, 21),
	LeatherLight = Color3.fromRGB(96, 68, 48),
	Accent = Color3.fromRGB(150, 44, 34),
	AccentDark = Color3.fromRGB(112, 30, 24),
	Brass = Color3.fromRGB(184, 146, 72),
	Good = Color3.fromRGB(86, 122, 64),
	Bad = Color3.fromRGB(150, 44, 34),
	Stamina = Color3.fromRGB(196, 150, 54),
	Health = Color3.fromRGB(150, 44, 34),
	XP = Color3.fromRGB(184, 146, 72),
	Track = Color3.fromRGB(58, 42, 32),
	Rarity = {
		Common = Color3.fromRGB(120, 108, 92),
		Uncommon = Color3.fromRGB(86, 122, 64),
		Rare = Color3.fromRGB(58, 92, 140),
		Epic = Color3.fromRGB(122, 64, 110),
		Legendary = Color3.fromRGB(184, 120, 40),
		Mythic = Color3.fromRGB(150, 44, 34),
	} :: { [string]: Color3 },
}

-- Slab serif for headings, plain sans for body text, monospaced figures for timers.
Style.Fonts = {
	Heading = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold),
	HeadingRegular = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular),
	Body = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.Regular),
	BodyBold = Font.new("rbxasset://fonts/families/SourceSansPro.json", Enum.FontWeight.SemiBold),
	Numbers = Font.new("rbxasset://fonts/families/RobotoMono.json", Enum.FontWeight.Medium),
	Sign = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Heavy),
}

-- Spacing scale in pixels. Every gap in the UI comes from this list.
Style.Space = {
	XS = 4,
	S = 8,
	M = 12,
	L = 16,
	XL = 24,
}

Style.TextSize = {
	Small = 14,
	Body = 16,
	Label = 18,
	Title = 22,
	Heading = 28,
	Display = 40,
}

return Style
