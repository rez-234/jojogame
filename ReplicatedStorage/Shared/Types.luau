--!strict
-- Shared data shapes. The server owns the Profile; clients receive copies.

export type HorseCosmetics = {
	Saddle: string,
	Blanket: string,
	Mane: string,
	Shoes: string,
}

export type OwnedHorse = {
	Id: string,
	Breed: string,
	Name: string,
	Level: number,
	XP: number,
	Health: number, -- -1 means full
	Coat: number, -- index into breed coats
	ManeColor: number,
	Pattern: string,
	Cosmetics: HorseCosmetics,
}

export type QuestState = {
	Id: string,
	Progress: number,
	Claimed: boolean,
	Town: number?,
}

export type Profile = {
	Version: number,
	Level: number,
	XP: number,
	StatPoints: number,
	Stats: { Health: number, Power: number, Speed: number, Stamina: number },
	Cash: number,
	Items: { [string]: number },
	Stand: string?,
	StandStorage: { string },
	Mastery: { [string]: { [string]: number } },
	Skins: { Owned: { [string]: boolean }, Equipped: { [string]: string } },
	Counters: { [string]: number },
	Ranked: number,
	ArenaWins: number,
	ArenaLosses: number,
	PvPEnabled: boolean,
	Horses: { OwnedHorse },
	EquippedHorse: string?,
	NextHorseId: number,
	HorseCosmetics: { [string]: boolean },
	Race: { BestTotal: number?, BestStages: { [string]: number }, Wins: number, Finishes: number },
	Quests: { Day: number, Daily: { QuestState }, Board: { QuestState } },
	LastTown: number,
	Unlocked: { [string]: boolean },
}

return {}
