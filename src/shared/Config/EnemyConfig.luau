--!strict
-- Enemy tuning: stats, attacks, animations, and where each enemy spawns. EnemyService runs
-- them; a new enemy type starts as a new entry here (plus its model and animations).

local SafeZone = require(script.Parent.Parent.SafeZone)

export type EnemyType = {
	DisplayName: string,
	Model: string, -- R15 model in assets/enemies (e.g. Orc.rbxmx); falls back to a plain body in Color
	Color: Color3,
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
	-- Only X/Z matter: each spawns dropped onto whatever ground is below, and respawns there.
	SpawnPoints: { Vector2 },
}

-- The hunting grounds, just north of the hub's edge.
local HUNTING_GROUNDS_Z = -SafeZone.HALF_SIZE - 55

local EnemyConfig = {}

EnemyConfig.LesserDemon = {
	DisplayName = "Lesser Demon",
	Model = "Orc",
	Color = Color3.fromRGB(120, 25, 30),
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
	SpawnPoints = {
		Vector2.new(0, HUNTING_GROUNDS_Z),
		Vector2.new(22, HUNTING_GROUNDS_Z - 20),
		Vector2.new(-22, HUNTING_GROUNDS_Z - 15),
	},
} :: EnemyType

-- Shared by every enemy.
EnemyConfig.AiTick = 0.2 -- seconds between AI decisions
EnemyConfig.IdleAnimation = "rbxassetid://507766388" -- Roblox's default R15 idle
EnemyConfig.WalkAnimation = "rbxassetid://507777826" -- Roblox's default R15 walk
EnemyConfig.DefaultAttackAnimation = "rbxassetid://522635514" -- used when an enemy's AttackAnimation is ""
EnemyConfig.FlinchAnimation = "" -- EnemyFlinch (tools/sword_anims.py): the jolt when hit; "" = no flinch

return EnemyConfig
