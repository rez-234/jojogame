--!strict
-- Every tunable number in the game lives here.

local Config = {}

Config.Map = {
	Seed = 1890,
	-- Length of the race route along the X axis, in studs. The real route is
	-- roughly 6,000 km; this compresses it to a playable ride.
	RouteLength = 16000,
	-- Multiplier for how far the trail wanders north and south.
	RouteMeander = 900,
	-- Half width of the generated land band around the trail.
	CorridorHalfWidth = 460,
	-- Spacing of the precomputed route samples along X.
	RouteSampleSpacing = 8,
	TrailHalfWidth = 9,
	-- Distance from the trail edge over which terrain blends back to natural height.
	TrailBlendWidth = 70,
	ChunkSize = 64,
	VoxelResolution = 4,
	SeaLevel = 0,
	OceanWidth = 500,
	BedrockDepth = 24,
	SnowLine = 230,
	MileMarkerSpacing = 400,
	RutSegmentLength = 24,
	BoundaryWallHeight = 220,
	-- Chunks built per frame before yielding while generating.
	ChunksPerYield = 6,
	PropsPerYield = 40,
	StartOffset = 140,
}

Config.World = {
	DayLengthMinutes = 18,
	StartClockTime = 16.5,
	SafeSpawnSeconds = 6,
}

Config.Horse = {
	-- Speeds in studs per second for each gait. Breed speed scales these.
	WalkSpeed = 14,
	TrotSpeed = 30,
	CanterSpeed = 52,
	GallopSpeed = 78,
	ReverseSpeed = 8,
	BaseAcceleration = 22,
	BrakeDeceleration = 60,
	CoastDeceleration = 14,
	BaseTurnRate = 2.2, -- radians per second at low speed
	HighSpeedTurnFactor = 0.45,
	BaseJumpPower = 46,
	Gravity = 196.2,
	HipHeight = 4.2,
	MaxClimbSlope = 52, -- degrees
	StaminaMax = 100,
	GallopDrain = 14, -- per second
	CanterDrain = 3,
	WalkRegen = 16,
	IdleRegen = 24,
	TrotRegen = 6,
	ExhaustedThreshold = 25, -- stamina needed before gallop is allowed again
	WhistleCooldown = 8,
	WhistleSpawnDistance = 18,
	MountDistance = 12,
	MountTweenTime = 0.35,
	-- Fraction of combat damage that horses take.
	DamageTakenMult = 0.35,
	ThrowOffKnockback = 60,
	HealCostPerMissingHP = 0.5,
	-- XP per stud ridden and per race win.
	XPPerStud = 0.02,
	XPPerRaceWin = 400,
	XPCurveBase = 120,
	XPCurveExponent = 1.45,
	MaxLevel = 30,
	SpeedPerLevel = 0.012,
	StaminaPerLevel = 0.02,
	AccelerationPerLevel = 0.015,
	MaxOwned = 12,
	-- Server sanity checks
	SpeedTolerance = 1.35,
	TeleportTolerance = 40,
	SanityInterval = 0.5,
	HerdSize = { 3, 5 },
	HerdWanderRadius = 60,
	TameWindows = 3,
	TameWindowWidth = 0.32,
	TameLatencyAllowance = 0.35,
	RenameMaxLength = 20,
}

Config.Level = {
	MaxLevel = 100,
	XPBase = 100,
	XPExponent = 1.55,
	StatPointsPerLevel = 3,
	-- Bonus per stat point.
	HealthPerPoint = 4,
	PowerPerPoint = 0.012,
	SpeedPerPoint = 0.006,
	StaminaPerPoint = 1.5,
	BaseHealth = 120,
	Unlocks = {
		{ Level = 1, Key = "Arrow", Text = "Stand Arrow use" },
		{ Level = 5, Key = "PvPArena", Text = "Ranked arena" },
		{ Level = 8, Key = "RareHorses", Text = "Rare horses at stables" },
		{ Level = 10, Key = "Rokakaka", Text = "Rokakaka use" },
		{ Level = 12, Key = "BossArenas", Text = "Boss arenas" },
		{ Level = 20, Key = "Evolution", Text = "Stand evolution" },
		{ Level = 25, Key = "LegendaryHorses", Text = "Legendary horses at stables" },
		{ Level = 35, Key = "RequiemEvolution", Text = "Second evolutions" },
	},
}

Config.XP = {
	NPCKillBase = 30,
	NPCKillPerLevel = 6,
	PvPKill = 120,
	BossKillBase = 600,
	RaceStage = 250,
	RaceFinish = 900,
	QuestDefault = 200,
	ArenaWin = 300,
	ArenaLoss = 60,
}

Config.Stand = {
	SummonCooldown = 1.0,
	FollowOffset = Vector3.new(2.2, 1.1, 2.6),
	AttackOffset = Vector3.new(0, 0.4, -3.2),
	FollowResponsiveness = 35,
	BaseDurability = 100,
	DurabilityPerStatGrade = 25,
	DurabilityRegen = 6, -- per second while not blocking
	BreakStun = 2.2,
	BreakCooldown = 8,
	-- Damage multiplier for each Power grade (E to A, then S for evolved forms).
	PowerGrades = { 0.8, 0.9, 1.0, 1.12, 1.25, 1.4 },
	SpeedGrades = { 0.85, 0.92, 1.0, 1.08, 1.16, 1.25 },
	RangeGrades = { 0.8, 0.9, 1.0, 1.15, 1.3, 1.5 },
	PrecisionGrades = { 0.0, 0.03, 0.06, 0.09, 0.12, 0.15 }, -- crit chance
	CritMultiplier = 1.5,
	RarityWeights = {
		Common = 40,
		Uncommon = 28,
		Rare = 18,
		Epic = 9,
		Legendary = 4,
		Mythic = 1,
	},
	MaxStorage = 4,
}

Config.Combat = {
	-- Client input rate limit (token bucket).
	InputBurst = 12,
	InputRefillPerSecond = 8,
	PunchCooldown = 0.38,
	PunchComboLength = 4,
	PunchComboReset = 1.1,
	PunchDamage = 6,
	PunchRange = 5.5,
	FinisherKnockback = 38,
	HitStun = 0.35,
	HeavyStun = 0.8,
	-- Combo limiter: once a target has been stunned this long inside the window,
	-- further stuns are ignored and it gets a brief immunity.
	MaxComboStun = 2.4,
	ComboWindow = 3.0,
	ComboImmunity = 1.6,
	BlockDamageMult = 0.25,
	BlockAngle = 110, -- degrees, frontal cone
	BlockDurabilityCost = 1.2, -- durability lost per point of blocked damage
	BlockWalkSpeed = 7,
	DodgeCooldown = 1.6,
	DodgeDistance = 18,
	DodgeIFrames = 0.35,
	DodgeStaminaCost = 20,
	PlayerStaminaMax = 100,
	PlayerStaminaRegen = 18,
	GuardBreakStun = 1.4,
	MaxAimDistance = 400,
	MaxPositionDesync = 25,
	KnockbackDecay = 0.25,
	DamageNumberThreshold = 1,
	-- PvP horseback tuning.
	MountedDamageTakenMult = 0.85,
}

Config.Mastery = {
	XPPerHit = 6,
	-- Diminishing returns against the same target within the window.
	SameTargetWindow = 90,
	SameTargetFalloff = 0.22,
	MinFactor = 0.05,
	Tiers = {
		{ Name = "Novice", XP = 0, Damage = 0.0, Cooldown = 0.0, Speed = 0.0, ExtraHits = 0 },
		{ Name = "Skilled", XP = 150, Damage = 0.06, Cooldown = 0.05, Speed = 0.05, ExtraHits = 1 },
		{ Name = "Expert", XP = 500, Damage = 0.13, Cooldown = 0.10, Speed = 0.10, ExtraHits = 2 },
		{ Name = "Master", XP = 1300, Damage = 0.21, Cooldown = 0.16, Speed = 0.15, ExtraHits = 3 },
		{ Name = "Perfected", XP = 3000, Damage = 0.32, Cooldown = 0.24, Speed = 0.22, ExtraHits = 5 },
	},
	PerfectedColor = Color3.fromRGB(235, 196, 92),
}

Config.NPC = {
	MaxPerZone = 6,
	RespawnTime = 25,
	AggroRange = 70,
	LeashRange = 160,
	AttackRange = 6,
	RetreatHealthFraction = 0.2,
	RetreatDuration = 4,
	PatrolRadius = 40,
	ThinkInterval = 0.2,
	HealthPerLevel = 14,
	DamagePerLevel = 0.06,
	AmbushChance = 0.35,
	BossRespawnTime = 180,
	LootDropChance = 0.25,
	ActivationRange = 600, -- zones only run AI while a player is this close
}

Config.Race = {
	LobbyCountdown = 20,
	StartCountdown = 5,
	MinPlayers = 1,
	Rivals = 5,
	RivalBaseSpeed = 62,
	RubberBandRange = 400,
	RubberBandStrength = 0.25,
	RivalAttackRange = 45,
	RivalAttackChance = 0.18,
	RivalAttackInterval = 4,
	TimeLimitMinutes = 20,
	ProgressInterval = 0.25,
	CheckpointRadius = 40,
	StageCash = 150,
	PlacementCash = { 1500, 900, 600, 400, 250 },
	FinishCash = 150,
	WinArrows = 2,
	PodiumArrows = 1,
	-- Chance of a horse reward for the winner.
	WinHorseChance = 0.5,
}

Config.PvP = {
	ArenaCountdown = 3,
	ArenaMaxTime = 180,
	RankedStart = 1000,
	RankedK = 32,
	KillFeedSize = 5,
	LeaderboardRefresh = 120,
	ToggleCooldown = 10,
}

Config.Data = {
	StoreName = "SBR_Profiles_v1",
	RankedStoreName = "SBR_Ranked_v1",
	AutosaveInterval = 120,
	MaxRetries = 5,
	RetryBaseDelay = 1,
	-- A lock older than this is treated as abandoned.
	LockTimeout = 600,
	LockRetryAttempts = 6,
	LockRetryDelay = 3,
	StartCash = 300,
}

Config.Economy = {
	ArrowPrice = 1200,
	RokakakaPrice = 2000,
	DailyQuestCount = 3,
	BoardQuestCount = 3,
	SellStandRefund = 0,
}

Config.Sounds = {
	-- Only engine bundled sounds are used so the place needs no uploaded audio.
	Wind = "rbxasset://sounds/action_falling.mp3",
	Hoof = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Jump = "rbxasset://sounds/action_jump.mp3",
	Land = "rbxasset://sounds/action_jump_land.mp3",
	Water = "rbxasset://sounds/impact_water.mp3",
	Swing = "rbxasset://sounds/swoosh.wav",
	Hit = "rbxasset://sounds/action_jump_land.mp3",
	Note = "rbxasset://sounds/electronicpingshort.wav",
	Hurt = "rbxasset://sounds/uuhhh.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
}

Config.Textures = {
	Smoke = "rbxasset://textures/particles/smoke_main.dds",
	Sparkle = "rbxasset://textures/particles/sparkles_main.dds",
	Fire = "rbxasset://textures/particles/fire_main.dds",
}

return Config
