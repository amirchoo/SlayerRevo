--!strict
-- Enemy tuning: stats, attacks, animations, and where each enemy spawns. EnemyService runs
-- them; a new enemy type starts as a new entry here (plus its model and animations).

local SafeZone = require(script.Parent.Parent.SafeZone)

export type EnemyType = {
	DisplayName: string,
	Level: number, -- shown over its head; how tough it is next to the player's level
	Model: string, -- R15 model in assets/enemies (e.g. Orc.rbxmx); falls back to a plain body in Color
	Color: Color3,
	Scale: number?, -- size of the model (1 = as saved); AttackRange is in the scaled size
	MaxHealth: number,
	WalkSpeed: number,
	AggroRange: number, -- studs
	AttackRange: number,
	AttackDamage: number,
	AttackWindup: number, -- seconds between starting the attack and the hit landing (match the animation's "Hit")
	AttackAnimation: string, -- "" uses Roblox's default tool swing
	AttackCooldown: number,
	RespawnDelay: number,
	XP: number, -- given to the player who defeats it (see ProgressionConfig for the level curve)
	Coins: number?, -- coins given to the killer (defaults to 0 if nil)
	-- Only X/Z matter: each spawns dropped onto whatever ground is below, and respawns there.
	SpawnPoints: { Vector2 },
	Pack: Pack?, -- roams the world in packs (see Pack) as well as at any SpawnPoints
}

-- Enemies that live in packs: Count packs of Min..Max members, each with a camp somewhere in
-- Area (X/Z), but never within SafeMargin studs of the safe zone (camps and roaming stay that
-- far out from the town's edge). A pack's behaviour (EnemyService):
--   Roam: the pack wanders together around its camp (within RoamRadius), walking at
--     RoamSpeed (of WalkSpeed), pausing RoamPause seconds between moves.
--   Aggro: when any member sees a player within AggroRange (outside the safe zone), or is
--     hit, the whole pack turns on that player.
--   Swarm: the MaxAttackers closest members close in and attack; the rest circle the target
--     RingRadius studs out, waiting for a gap, so the pack surrounds you rather than piling up.
--   Leash: a target that drags the pack more than LeashRange from its camp (or reaches the
--     safe zone) is given up; the pack walks home and recovers its health.
--   Respawn: once every member is dead, a new pack forms RespawnDelay seconds later at a new
--     camp, away from players.
export type Pack = {
	Count: number,
	Min: number,
	Max: number,
	Area: { Min: Vector2, Max: Vector2 },
	SafeMargin: number, -- studs kept clear around the safe zone
	CampSpacing: number, -- studs between camps
	RoamRadius: number,
	RoamSpeed: number,
	RoamPause: { number }, -- min, max seconds
	Spread: number, -- studs members keep around the pack's centre while roaming
	AggroRange: number,
	LeashRange: number,
	MaxAttackers: number,
	RingRadius: number,
	RespawnDelay: number,
}

-- The hunting grounds, just north of the hub's edge.
local HUNTING_GROUNDS_Z = -SafeZone.HALF_SIZE - 55

local EnemyConfig = {}

-- The little green guys: the first thing players fight.
EnemyConfig.Orc = {
	DisplayName = "Orc",
	Level = 3,
	Model = "Orc",
	Color = Color3.fromRGB(70, 130, 50),
	MaxHealth = 200,
	WalkSpeed = 10,
	AggroRange = 60,
	AttackRange = 5,
	AttackDamage = 30,
	AttackWindup = 0.4, -- matches DemonClaw's "Hit" keyframe (tools/sword_anims.py)
	AttackAnimation = "rbxassetid://135668765525905", -- DemonClaw
	AttackCooldown = 1.5,
	RespawnDelay = 8,
	XP = 15,
	Coins = 5,
	SpawnPoints = {}, -- orcs live in packs (below); the Training Grounds places its own
	Pack = {
		Count = 14, -- spread over the whole map (the hunting grounds alone had 6)
		Min = 4,
		Max = 6,
		-- The whole map (forest and hunting grounds), short of the mountains along its edge
		-- (WorldConfig.Mountains.Start); the hub is kept clear by SafeMargin.
		Area = { Min = Vector2.new(-820, -820), Max = Vector2.new(820, 820) },
		SafeMargin = 60,
		CampSpacing = 150,
		RoamRadius = 45,
		RoamSpeed = 0.45,
		RoamPause = { 3, 8 },
		Spread = 7,
		AggroRange = 45,
		LeashRange = 130,
		MaxAttackers = 3,
		RingRadius = 11,
		RespawnDelay = 30,
	},
} :: EnemyType

-- A winged demon a size up from the orcs: three times the health, hits half again as hard
-- with a longer reach, but swings a little slower (so it's readable). Waits behind the orcs.
EnemyConfig.LesserDemon = {
	DisplayName = "Lesser Demon",
	Level = 8,
	Model = "LesserDemon",
	Scale = 1.3,
	Color = Color3.fromRGB(120, 25, 30),
	MaxHealth = 600,
	WalkSpeed = 11,
	AggroRange = 70,
	AttackRange = 6.5,
	AttackDamage = 45,
	AttackWindup = 0.4, -- DemonClaw again (its "Hit" keyframe)
	AttackAnimation = "rbxassetid://135668765525905", -- DemonClaw
	AttackCooldown = 1.8,
	RespawnDelay = 20,
	XP = 60,	Coins = 25,	SpawnPoints = {
		Vector2.new(0, HUNTING_GROUNDS_Z - 45),
	},
} :: EnemyType

-- Every enemy type, spawned at its SpawnPoints when the server starts.
-- The Lesser Demon is left out for now (its model in assets/enemies isn't rigged yet).
EnemyConfig.Types = { EnemyConfig.Orc }

-- Shared by every enemy.
EnemyConfig.AiTick = 0.2 -- seconds between AI decisions
EnemyConfig.IdleAnimation = "rbxassetid://507766388" -- Roblox's default R15 idle
EnemyConfig.WalkAnimation = "rbxassetid://507777826" -- Roblox's default R15 walk
EnemyConfig.DefaultAttackAnimation = "rbxassetid://522635514" -- used when an enemy's AttackAnimation is ""
EnemyConfig.FlinchAnimation = "" -- EnemyFlinch (tools/sword_anims.py): the jolt when hit; "" = no flinch
EnemyConfig.ParriedAnimation = "" -- EnemyParried (tools/sword_anims.py): the recoil held through a parry's stun; "" = none

return EnemyConfig
