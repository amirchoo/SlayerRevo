--!strict
-- Boss tuning: stats, phases, and every attack's timing and shape. BossService runs them;
-- BossAnimator (client) plays their clips. A boss is a rigged model with its own skeleton
-- (ServerStorage.EnemyModels.<Model>, imported from a .glb; see assets/enemies/README.md)
-- whose clips are played from the file's own keys (src/shared/EnemyClips/<Clips>.luau, made
-- by tools/npc_clips.py), like the pets.
--
-- A fight (BossService):
--   Dormant: stands in its arena until a player walks in; then the Intro clip plays (it can't
--     be hurt meanwhile) and the fight starts.
--   Fight: walks or runs at its target (the nearest player), and picks an attack by where they
--     stand: in front within reach, behind it, or far off. After each attack it holds still
--     for Recovery seconds (the punish window).
--   Phases: below each phase's HealthBelow the next one takes over (more attacks, shorter
--     recovery, faster). Each change shows its Banner to the players in the fight.
--   Stagger: Poise damage taken (from anything) knocks it down for StunTime (its Stunned
--     clip) and the count starts again. Parries count too: a parried blow does the parrying
--     player no harm, and the ParriesToStun-th parry (counted across attacks and players, back
--     to 0 after any stagger) knocks it down.
--   Sounds (BossSounds, client): its voice (Sounds: Roar at the intro, Enrage at each phase
--     change, Hurt when struck, Stunned, Death) and each attack's cues (At seconds into the
--     clip at normal speed), all names in shared/Sounds.
--   Wipe: when no player in the fight is alive, it heals to full and goes back to Dormant
--     at its spot.

-- Where an attack hits, around the boss's root (its feet, facing its front). All in studs.
--   Cone: within Radius in front, up to Angle degrees either side of straight ahead.
--   Circle: within Radius of a spot Forward studs ahead (Forward 0 = all around it).
--   Line: a band Width wide from the boss to Length ahead (aimed at the target).
export type Shape = {
	Kind: "Cone" | "Circle" | "Line",
	Radius: number?,
	Angle: number?,
	Forward: number?,
	Length: number?,
	Width: number?,
}

-- One attack. Times are seconds into its clip at normal speed (a phase's Speed scales them).
--   Hits: when each blow lands. A Window (start, end) instead keeps the shape live for a
--     while (a spin), hitting each player once.
--   Telegraph: shown on the ground from the attack's start until its first hit (red, so it
--     can be dodged); Lead adds that many seconds of standing still before the clip starts.
--   Aim: the boss keeps turning to its target until this time, then commits.
--   Parryable: a parry on a blow deflects it and counts toward a stagger (ParriesToStun);
--     otherwise blocking only absorbs (Unparryable attacks are telegraphed instead).
export type SoundCue = { At: number, Sound: string }
export type Attack = {
	Clip: string, -- name in Clips
	Shape: Shape,
	Damage: { number }, -- per hit (one entry per Hits; a Window uses the first)
	Hits: { number }?,
	Window: { number }?,
	Lead: number?,
	Aim: number,
	Parryable: boolean,
	Knockback: number?, -- studs/s players are thrown away from the boss
	Telegraph: boolean,
	Cooldown: number, -- seconds before it can be used again
	-- When it's picked: the target is Near (within MeleeRange, in front), Behind (within
	-- MeleeRange, behind), or Far (past FarRange). Weight among the attacks that fit.
	When: { Near: number?, Behind: number?, Far: number? },
	Phase: number, -- the first phase it's used in
	Sounds: { SoundCue }?, -- played from the boss as the clip reaches each At
}

export type Phase = {
	HealthBelow: number, -- 0..1 of max health; phase 1 is 1
	Recovery: number, -- seconds standing still after an attack
	Speed: number, -- clip and attack speed
	Banner: string?,
}

export type Boss = {
	Id: string,
	DisplayName: string,
	Title: string, -- under its name on the boss bar
	Level: number,
	Model: string, -- in ServerStorage.EnemyModels
	Clips: string, -- module in src/shared/EnemyClips
	Height: number, -- studs, feet to the top of the head (the model is scaled to it)
	FacingOffset: number, -- degrees to turn the model so it faces the root's front (-Z)
	MaxHealth: number,
	WalkSpeed: number,
	RunSpeed: number,
	RunAbove: number, -- farther than this from its target, it runs
	MeleeRange: number,
	FarRange: number,
	Poise: number, -- damage that staggers it
	ParriesToStun: number, -- parried blows that stagger it
	StunTime: number,
	HurtAbove: number, -- a single hit dealing this much makes it flinch (Hurt clip), when not attacking
	XP: number,
	Coins: number,
	-- The clips by what they're for; WalkClipSpeed / RunClipSpeed are the ground speeds
	-- (studs/s at Height) the cycles were made for, so the feet don't slide.
	Animations: {
		Intro: string,
		Idle: string,
		Walk: string,
		Run: string,
		Stunned: string,
		Hurt: string,
		Death: string,
		WalkClipSpeed: number,
		RunClipSpeed: number,
	},
	Phases: { Phase },
	Attacks: { [string]: Attack },
	Sounds: { Roar: string?, Enrage: string?, Hurt: string?, Stunned: string?, Death: string? },
}

local BossConfig = {}

-- The orc warlord at the bottom of his lair (DungeonConfig.Grimgorg): a winged brute with a
-- spiked tail. Swings in front, sweeps his tail at anyone behind, and from half health
-- breathes a beam at anyone keeping their distance.
BossConfig.Grimgorg = {
	Id = "Grimgorg",
	DisplayName = "Grimgorg",
	Title = "Warlord of the Orc Lair",
	Level = 8,
	Model = "Grimgorg",
	Clips = "Grimgorg",
	Height = 17,
	FacingOffset = 0, -- the .glb faces +Z; Import 3D turns it 180 degrees, to -Z
	MaxHealth = 3000, -- placeholder: about 3-4 minutes for one Lv 5-8 player
	WalkSpeed = 9,
	RunSpeed = 17,
	RunAbove = 26,
	MeleeRange = 14,
	FarRange = 24,
	Poise = 450,
	ParriesToStun = 5,
	StunTime = 2.4,
	HurtAbove = 45,
	XP = 400,
	Coins = 120,
	Animations = {
		Intro = "Anim_Grimgorg_Intro_Spawn",
		Idle = "Anim_Grimgorg_Idle",
		Walk = "Anim_Grimgorg_Walk",
		Run = "Anim_Grimgorg_Run",
		Stunned = "Anim_Grimgorg_Stunned",
		Hurt = "Anim_Grimgorg_Hurt_Light",
		Death = "Anim_Grimgorg_Death",
		-- Guesses (the clips don't say): tune until the feet stop sliding.
		WalkClipSpeed = 8,
		RunClipSpeed = 17,
	},
	Sounds = {
		Roar = "GrimgorgRoar",
		Enrage = "GrimgorgEnrage",
		Hurt = "GrimgorgHurt",
		Stunned = "GrimgorgStunned",
		Death = "GrimgorgDeath",
	},
	Phases = {
		{ HealthBelow = 1, Recovery = 1.3, Speed = 1 },
		{ HealthBelow = 0.5, Recovery = 0.9, Speed = 1, Banner = "Grimgorg is furious!" },
		{ HealthBelow = 0.2, Recovery = 0.6, Speed = 1.2, Banner = "Grimgorg is enraged!" },
	},
	-- Hit times measured from the clips (fastest hand / tail motion; see notes/log).
	Attacks = {
		-- Right swipe, left swipe, two-handed smash.
		Combo = {
			Clip = "Anim_Grimgorg_Attack_Combo_Light",
			Shape = { Kind = "Cone", Radius = 14, Angle = 70 },
			Damage = { 22, 22, 32 },
			Hits = { 0.38, 1.2, 1.48 },
			Aim = 1.1,
			Parryable = true,
			Telegraph = false,
			Cooldown = 0,
			When = { Near = 3 },
			Phase = 1,
			Sounds = {
				{ At = 0.05, Sound = "GrimgorgAttack" },
				{ At = 0.3, Sound = "GrimgorgSwing" },
				{ At = 1.1, Sound = "GrimgorgSwing" },
				{ At = 1.38, Sound = "GrimgorgSwing" },
			},
		},
		-- Both fists overhead, slammed into the ground ahead.
		Overhead = {
			Clip = "Anim_Grimgorg_Attack_Heavy_Overhead",
			Shape = { Kind = "Circle", Radius = 10, Forward = 9 },
			Damage = { 60 },
			Hits = { 1.4 },
			Aim = 0.9,
			Parryable = false,
			Knockback = 40,
			Telegraph = true,
			Cooldown = 5,
			When = { Near = 2 },
			Phase = 1,
			Sounds = {
				{ At = 0.3, Sound = "GrimgorgAttack" },
				{ At = 1.4, Sound = "GrimgorgSlam" },
			},
		},
		-- Spins on the spot, tail out, hitting all around.
		TailSwipe = {
			Clip = "Anim_Grimgorg_Attack_Heavy_TailSwipe",
			Shape = { Kind = "Circle", Radius = 15, Forward = 0 },
			Damage = { 40 },
			Window = { 0.45, 1.15 },
			Lead = 0.35,
			Aim = 0,
			Parryable = false,
			Knockback = 70,
			Telegraph = true,
			Cooldown = 6,
			When = { Near = 1, Behind = 5 },
			Phase = 1,
			Sounds = {
				{ At = 0, Sound = "GrimgorgAttack" },
				{ At = 0.45, Sound = "GrimgorgTail" },
				{ At = 0.8, Sound = "GrimgorgTail" },
			},
		},
		-- Gathers fire in his maw, then breathes it in a straight line.
		Beam = {
			Clip = "Anim_Grimgorg_Attack_Ranged_Beam",
			Shape = { Kind = "Line", Length = 70, Width = 7 },
			Damage = { 50 },
			Window = { 1.4, 2 },
			Aim = 1,
			Parryable = false,
			Telegraph = true,
			Cooldown = 8,
			When = { Far = 4 },
			Phase = 2,
			Sounds = {
				{ At = 0.2, Sound = "GrimgorgAttack" },
				{ At = 1.4, Sound = "GrimgorgBeam" },
				{ At = 1.7, Sound = "GrimgorgBeam" },
			},
		},
	},
} :: Boss

return BossConfig
