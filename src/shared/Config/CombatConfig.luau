--!strict
-- Combat tuning shared by the server (authoritative) and client (input gating/visuals).

-- One click in a combo weapon's combo. Cooldown: seconds before the next click counts.
-- HitDelay: seconds after the click that the hit lands (line it up with the animation).
-- Knockback / Stun (optional): push the enemy back (studs/s) / stun it (seconds) on hit.
-- Lunge (optional): the attacker surges forward at this many studs/s as they swing.
-- Radius / Arc (optional, together): a sweep that hits everything within Radius studs inside
-- Arc degrees around where the attacker faces (360 = all around), instead of the weapon's box.
-- Shockwave (optional): the blow hits the ground, drawing a dust ring as wide as Radius.
export type ComboMove = {
	Animation: string,
	-- The same swing with only the upper body; while the player walks, the client blends toward it so
	-- the legs walk instead of sliding in the swing's stance (ComboWeaponClient).
	MovingAnimation: string?,
	Damage: number,
	Cooldown: number,
	HitDelay: number,
	Knockback: number?,
	Stun: number?,
	Lunge: number?,
	Radius: number?,
	Arc: number?,
	Shockwave: boolean?,
}

-- Heavy attacks (optional, per combo weapon): hold left-click instead of tapping.
-- Spin: spin while held, hitting everything around you every TickInterval for as long as
-- you hold (up to MaxDuration), then a short Recovery before the next one.
export type SpinHeavy = {
	Kind: "Spin",
	Animation: string, -- loops while spinning; "" until published
	Stamina: number, -- stamina spent per hit (stops the spin when you run out)
	HoldTime: number, -- seconds the click must be held to count as a heavy (shorter = a normal tap)
	WindUp: number, -- seconds before the first hit
	TickInterval: number, -- seconds between hits (one per spin)
	Damage: number, -- per hit
	Radius: number, -- studs around the player that each hit reaches
	MaxDuration: number, -- seconds a spin can last
	Recovery: number, -- seconds after a spin before the next one
	WalkSpeed: number, -- while spinning
	-- Optional: turn the weapon 180 degrees around its handle for this heavy (when its
	-- animations hold it the other way round from the light attacks, e.g. the axe's edge).
	FlipGrip: boolean?,
}

-- Quake: raise the weapon while held (a ring on the ground shows the reach), then release to
-- smash the ground. The shockwave hits and pushes back everything around you; the longer the
-- hold (up to FullChargeTime), the wider and harder it is. Holding past MaxHold smashes on
-- its own.
export type QuakeHeavy = {
	Kind: "Quake",
	WindUpAnimation: string, -- raising the weapon; held on its last frame while charging
	SlamAnimation: string, -- the smash on release
	Stamina: number, -- stamina spent to start charging
	HoldTime: number, -- seconds the click must be held to count as a heavy (shorter = a normal tap)
	FullChargeTime: number, -- seconds of charging for full power
	MaxHold: number, -- seconds of charging before it smashes by itself
	MinDamage: number,
	MaxDamage: number,
	MinRadius: number, -- studs around the player the shockwave reaches
	MaxRadius: number,
	Knockback: number, -- studs/s enemies are pushed away from the impact
	-- Optional: the push grows with the charge, from Knockback to MaxKnockback, and lasts
	-- KnockbackTime seconds (longer = thrown further; 0.2 if unset).
	MaxKnockback: number?,
	KnockbackTime: number?,
	HitDelay: number, -- seconds after release that the smash lands (matches the animation)
	Recovery: number, -- seconds after a smash before the next heavy
	WalkSpeed: number, -- while charging
	-- Optional: turn the weapon 180 degrees around its handle for this heavy (when its
	-- animations hold it the other way round from the light attacks, e.g. the axe's edge).
	FlipGrip: boolean?,
}

-- Thrust: draw the weapon back while held, turning with the camera (a strip on the ground
-- shows the reach), then release to lunge forward, hitting everything along the line (the
-- spear's piercing lunge, the axe's leaping cleave).
-- The longer the hold (up to FullChargeTime), the further the lunge and the harder the hit.
-- Holding past MaxHold lunges on its own.
export type ThrustHeavy = {
	Kind: "Thrust",
	WindUpAnimation: string, -- drawing back; held on its last frame while charging
	ThrustAnimation: string, -- the lunge on release
	Stamina: number, -- stamina spent to start charging
	HoldTime: number, -- seconds the click must be held to count as a heavy (shorter = a normal tap)
	FullChargeTime: number, -- seconds of charging for full power
	MaxHold: number, -- seconds of charging before it lunges by itself
	MinDamage: number,
	MaxDamage: number,
	MinDistance: number, -- studs the lunge carries you
	MaxDistance: number,
	LungeTime: number, -- seconds the lunge lasts
	Reach: number, -- studs the point reaches past where the lunge ends
	Width: number, -- hitbox width and height
	Height: number,
	Knockback: number, -- studs/s enemies are pushed away
	HitDelay: number, -- seconds after release that the hit lands (matches the animation)
	Recovery: number, -- seconds after a lunge before the next heavy
	WalkSpeed: number, -- while charging
	-- Optional: enemies hit keep bleeding, taking Damage every Interval for Duration seconds
	-- (a new bleed restarts the timer rather than stacking).
	Bleed: { Damage: number, Interval: number, Duration: number }?,
	-- Optional: turn the weapon 180 degrees around its handle for this heavy (when its
	-- animations hold it the other way round from the light attacks, e.g. the axe's edge).
	FlipGrip: boolean?,
}

-- Flurry: draw back while held, turning with the camera (a strip on the ground shows the
-- reach), then release into rapid thrusts: the longer the hold (up to FullChargeTime), the
-- more stabs (MinHits to MaxHits). Each stab hits along a narrow line ahead; the last one
-- knocks back. You stay planted, creeping forward, until the last stab. Holding past
-- MaxHold releases on its own.
export type FlurryHeavy = {
	Kind: "Flurry",
	WindUpAnimation: string, -- drawing back; held on its last frame while charging
	FlurryAnimation: string, -- the stabbing, looped for as long as the flurry lasts
	Stamina: number, -- stamina spent to start charging
	HoldTime: number, -- seconds the click must be held to count as a heavy (shorter = a normal tap)
	FullChargeTime: number, -- seconds of charging for the most stabs
	MaxHold: number, -- seconds of charging before it releases by itself
	MinHits: number,
	MaxHits: number,
	Damage: number, -- per stab
	Interval: number, -- seconds between stabs (matches the flurry animation's rhythm)
	HitDelay: number, -- seconds after release that the first stab lands
	Range: number, -- hitbox depth ahead of the player, in studs
	Width: number,
	Height: number,
	FinalKnockback: number, -- studs/s the last stab pushes enemies away
	Advance: number, -- studs/s you creep forward while stabbing
	Recovery: number, -- seconds after the last stab before the next heavy
	WalkSpeed: number, -- while charging
	FlipGrip: boolean?,
}

-- Rush: crouch and gather while held (feet nearly planted). After ChargeTime the rush starts
-- by itself: you surge in whichever direction you walk (straight on if you aren't), spinning
-- and slashing everything within Radius every TickInterval, for as long as you hold (up to
-- MaxDuration) or until stamina runs out. Letting go before the rush starts calls it off.
export type RushHeavy = {
	Kind: "Rush",
	WindUpAnimation: string, -- gathering; held on its last frame until the rush starts
	RushAnimation: string, -- the spinning slashes, looped while rushing
	Stamina: number, -- stamina spent per hit (the first when the rush starts; nothing to charge)
	HoldTime: number, -- seconds the click must be held to count as a heavy (shorter = a normal tap)
	ChargeTime: number, -- seconds of gathering before the rush starts
	WalkSpeed: number, -- while gathering
	Speed: number, -- studs/s you rush at
	TickInterval: number, -- seconds between hits
	Damage: number, -- per hit
	Radius: number, -- studs around the player that each hit reaches
	MaxDuration: number, -- seconds a rush can last
	Recovery: number, -- seconds after a rush before the next heavy
	FlipGrip: boolean?,
}

-- Reap: one press, no charging. The weapon reaches far ahead and hooks whatever it catches
-- (HookDelay after the press): each enemy within Reach takes HookDamage, is held (a silent
-- stun) and dragged in to PullTo studs in front of you over PullTime. At CutDelay you cut all
-- around (CutRadius, inside CutArc degrees), knocking everything back. Letting go doesn't stop
-- it; the move lasts Duration.
export type ReapHeavy = {
	Kind: "Reap",
	Animation: string, -- the whole move: reach, yank back, cut
	Stamina: number, -- stamina spent when it starts
	HoldTime: number, -- seconds the click must be held to count as a heavy (shorter = a normal tap)
	WalkSpeed: number, -- during the move
	HookDelay: number, -- seconds after the press that the hook lands (the animation's "Hit")
	Reach: number, -- studs ahead the hook reaches
	Width: number, -- the hook's hitbox
	Height: number,
	HookDamage: number,
	PullTime: number, -- seconds to drag a hooked enemy in
	PullTo: number, -- studs in front of you it's dragged to
	CutDelay: number, -- seconds after the press that the cut lands (the animation's "Cut")
	CutDamage: number,
	CutRadius: number,
	CutArc: number, -- degrees around where you face (360 = all around)
	Knockback: number, -- studs/s the cut pushes enemies away
	Duration: number, -- seconds the whole move lasts
	Recovery: number, -- seconds after it ends before the next heavy
	FlipGrip: boolean?,
}

export type HeavyAttack = SpinHeavy | QuakeHeavy | ThrustHeavy | FlurryHeavy | RushHeavy | ReapHeavy

-- A click-combo melee weapon (sword, mace, spear): see WeaponService and ComboWeaponClient.
export type ComboWeapon = {
	ToolName: string,
	Hand: string,
	IdleAnimation: string, -- loops while equipped
	AnimationSpeed: number, -- playback speed for its swing animations (below 1 = heavier)
	Stamina: number, -- stamina each swing costs
	Combo: { ComboMove },
	-- Walk speed from a swing's click until its Cooldown is over, so attacking on the move is slower
	-- (ComboWeaponClient). Walking is 16.
	SwingWalkSpeed: number?,
	ComboWindow: number, -- seconds after a swing's cooldown to click again before the combo resets
	Range: number, -- hitbox depth in front of the player, in studs
	Width: number,
	Height: number,
	Block: {
		Animation: string, -- looping guard stance; "" uses a simple code-driven guard instead
		BlockAmount: number, -- damage absorbed per block (a 35 hit against 20 deals 15)
		ParryWindow: number, -- seconds after raising the guard that a hit is parried (lighter weapons: longer)
	},
	Heavy: HeavyAttack?, -- hold-to-use attack; without one, every click is a normal swing
	-- How a real model (assets/weapons/<ToolName>.rbxmx) is fitted to the hand; see
	-- src/server/WeaponModels.luau. Length: studs from handle end to tip. GripFrom: where the
	-- hand holds it, as a fraction of Length from the handle end. FlipBlade: true if it comes
	-- out held by the tip.
	ModelFit: { Length: number, GripFrom: number, FlipBlade: boolean?, FlipEdge: boolean?, Shift: Vector3? }?,
	TrailColor: Color3?, -- the swing trail's color (white if unset)
	-- A second copy of the weapon held in the other hand (dual blades). Both hands hold the
	-- same model, fitted with the same ModelFit; the hitboxes are the weapon's as usual.
	DualWield: boolean?,
	-- Walk speed while it's equipped (heavy weapons); the normal walk speed if unset.
	WalkSpeed: number?,
}

-- One click in the greatsword's combo: a wide sweep hitting everything within Radius studs
-- inside Arc degrees of where the player faces (360 = all the way around).
export type GreatswordSwing = {
	Animation: string,
	Damage: number,
	Cooldown: number,
	HitDelay: number,
	Radius: number,
	Arc: number,
	Knockback: number?,
}

local Sword: ComboWeapon = {
	ToolName = "Sword",
	Hand = "Right",
	IdleAnimation = "rbxassetid://128056004893251", -- SwordIdle (katana-style, 2026-10-18)
	AnimationSpeed = 1,
	Stamina = 8,
	ModelFit = { Length = 5.2, GripFrom = 0.11 },
	Combo = {
		-- HitDelay matches each swing's "Hit" keyframe in tools/blender/sword_clips.py.
		{ Animation = "rbxassetid://104914800619644", MovingAnimation = "rbxassetid://88087903830218", Damage = 33, Cooldown = 0.55, HitDelay = 0.18 }, -- SwordSwing1
		{ Animation = "rbxassetid://99968467521543", MovingAnimation = "rbxassetid://88649716388151", Damage = 41, Cooldown = 0.55, HitDelay = 0.15 }, -- SwordSwing2
		{ Animation = "rbxassetid://98009756362330", MovingAnimation = "rbxassetid://79289853982811", Damage = 65, Cooldown = 0.85, HitDelay = 0.38 }, -- SwordSwing3
	},
	SwingWalkSpeed = 8, -- half speed while swinging
	ComboWindow = 0.8,
	Range = 6,
	Width = 6,
	Height = 6,
	Block = {
		Animation = "rbxassetid://82457273702146", -- SwordGuard
		BlockAmount = 20,
		ParryWindow = 0.25,
	},
	Heavy = {
		Kind = "Spin",
		Stamina = 6, -- per hit (every TickInterval)
		Animation = "rbxassetid://105976549343738", -- SwordSpin
		HoldTime = 0.2,
		WindUp = 0.3,
		TickInterval = 0.5, -- matches one full turn of SwordSpin
		Damage = 15,
		Radius = 8,
		MaxDuration = 3,
		Recovery = 0.6,
		WalkSpeed = 8,
	},
}

-- Emberfang (Epic): the sword's moves and animations, hitting about 30% harder for a little
-- less stamina, with a sturdier guard and an ember swing trail. Uses the Sword's skill tree
-- (SkillTrees.SharedTrees).
local Emberfang: ComboWeapon = {
	ToolName = "Emberfang",
	Hand = "Right",
	IdleAnimation = Sword.IdleAnimation,
	AnimationSpeed = 1,
	Stamina = 7,
	ModelFit = { Length = 5.4, GripFrom = 0.12 }, -- the hand on the grip wrap
	TrailColor = Color3.fromRGB(255, 120, 40),
	Combo = {
		{ Animation = Sword.Combo[1].Animation, MovingAnimation = Sword.Combo[1].MovingAnimation, Damage = 42, Cooldown = 0.55, HitDelay = Sword.Combo[1].HitDelay },
		{ Animation = Sword.Combo[2].Animation, MovingAnimation = Sword.Combo[2].MovingAnimation, Damage = 52, Cooldown = 0.55, HitDelay = Sword.Combo[2].HitDelay },
		{ Animation = Sword.Combo[3].Animation, MovingAnimation = Sword.Combo[3].MovingAnimation, Damage = 85, Cooldown = 0.85, HitDelay = Sword.Combo[3].HitDelay },
	},
	SwingWalkSpeed = Sword.SwingWalkSpeed,
	ComboWindow = 0.8,
	Range = 6.5,
	Width = 6,
	Height = 6,
	Block = {
		Animation = Sword.Block.Animation,
		BlockAmount = 25,
		ParryWindow = 0.25,
	},
	Heavy = {
		Kind = "Spin",
		Stamina = 6,
		Animation = "rbxassetid://105976549343738", -- SwordSpin
		HoldTime = 0.2,
		WindUp = 0.3,
		TickInterval = 0.5,
		Damage = 20,
		Radius = 8.5,
		MaxDuration = 3,
		Recovery = 0.6,
		WalkSpeed = 8,
	},
}

-- Heavier, blunter cousin of the sword: same guard, harder hits, and a finisher that knocks back
-- and stuns. It keeps the sword's previous swings and idle (played slower); the Sword's own were
-- redone katana-style (2026-10-18), which doesn't suit a mace. Its own pass comes later.
local MACE_SPEED = 0.8
local Mace: ComboWeapon = {
	ToolName = "Mace",
	Hand = "Right",
	IdleAnimation = "rbxassetid://138485130990728", -- the sword's previous idle
	AnimationSpeed = MACE_SPEED,
	Stamina = 12,
	ModelFit = { Length = 4.4, GripFrom = 0.14 },
	Combo = {
		-- The sword's previous SwordSwing1-3 (2026-10-17 recovery clips); slower animations land
		-- later: their HitDelays divided by MACE_SPEED.
		{ Animation = "rbxassetid://105789243194617", Damage = 40, Cooldown = 0.7, HitDelay = 0.26 / MACE_SPEED },
		{ Animation = "rbxassetid://125525200710497", Damage = 47, Cooldown = 0.7, HitDelay = 0.24 / MACE_SPEED },
		{
			Animation = "rbxassetid://108194359632313",
			Damage = 87,
			Cooldown = 1.05,
			HitDelay = 0.4 / MACE_SPEED,
			Knockback = 30,
			Stun = 1.5, -- stunned enemies stop moving and their wind-up attack is cancelled
		},
	},
	ComboWindow = 0.8,
	Range = 6,
	Width = 7,
	Height = 6,
	Block = {
		Animation = Sword.Block.Animation,
		BlockAmount = 25,
		ParryWindow = 0.18, -- heavy head: harder to parry with
	},
	Heavy = {
		Kind = "Quake",
		Stamina = 25,
		WindUpAnimation = "rbxassetid://92676795728467", -- MaceWindUp
		SlamAnimation = "rbxassetid://103806771771542", -- MaceSlam
		HoldTime = 0.2,
		FullChargeTime = 1.2,
		MaxHold = 2.5,
		MinDamage = 30,
		MaxDamage = 70,
		MinRadius = 5,
		MaxRadius = 10,
		Knockback = 25,
		HitDelay = 0.18, -- matches MaceSlam's "Hit" keyframe in tools/sword_anims.py
		Recovery = 1,
		WalkSpeed = 6,
	},
}

-- Reach weapon: a long, narrow hitbox and medium damage, two quick thrusts then a lunging
-- thrust that carries you forward. Its guard is weak; keeping distance is the defense.
-- Animation IDs: leave "" until published (it still works, just unanimated).
local Spear: ComboWeapon = {
	ToolName = "Spear",
	Hand = "Right",
	IdleAnimation = "rbxassetid://133791607724854", -- SpearIdle
	AnimationSpeed = 1,
	Stamina = 7,
	ModelFit = { Length = 8.3, GripFrom = 0.42 },
	Combo = {
		-- HitDelay matches each thrust's "Hit" keyframe in tools/spear_anims.py.
		{ Animation = "rbxassetid://108365738581135", Damage = 18, Cooldown = 0.3, HitDelay = 0.13 }, -- SpearThrust1
		{ Animation = "rbxassetid://102652655497282", Damage = 20, Cooldown = 0.3, HitDelay = 0.12 }, -- SpearThrust2
		{ Animation = "rbxassetid://83821017663539", Damage = 32, Cooldown = 0.7, HitDelay = 0.2, Lunge = 40, Knockback = 18 }, -- SpearThrust3
	},
	ComboWindow = 0.8,
	Range = 11, -- long reach...
	Width = 3.5, -- ...but narrow: aim the point
	Height = 5,
	Block = {
		Animation = "", -- SpearGuard
		BlockAmount = 10,
		ParryWindow = 0.3, -- light and quick: the easiest to parry with
	},
	Heavy = {
		Kind = "Thrust",
		Stamina = 20,
		WindUpAnimation = "rbxassetid://116496473188639", -- SpearWindUp
		ThrustAnimation = "rbxassetid://125007774453707", -- SpearLunge
		HoldTime = 0.2,
		FullChargeTime = 1,
		MaxHold = 2.5,
		MinDamage = 25,
		MaxDamage = 55,
		MinDistance = 4,
		MaxDistance = 14,
		LungeTime = 0.2,
		Reach = 8,
		Width = 4,
		Height = 5,
		Knockback = 20,
		HitDelay = 0.15, -- matches SpearLunge's "Hit" keyframe in tools/spear_anims.py
		Recovery = 0.8,
		WalkSpeed = 4,
	},
}

-- Rapier: a duelist's thrusting blade. Three quick, elegant stabs on a long, narrow line
-- (the third a full lunge). Its heavy charges a coiled thrust that releases as a flurry of
-- rapid stabs. A light guard with the widest parry window of the blades: it rewards timing.
-- Animations from tools/rapier_anims.py.
local Rapier: ComboWeapon = {
	ToolName = "Rapier",
	Hand = "Right",
	IdleAnimation = "rbxassetid://135237202710751", -- RapierIdle
	AnimationSpeed = 1,
	Stamina = 6,
	ModelFit = { Length = 5.2, GripFrom = 0.08 },
	TrailColor = Color3.fromRGB(235, 240, 255),
	Combo = {
		-- HitDelay matches each thrust's "Hit" keyframe in tools/rapier_anims.py.
		{ Animation = "rbxassetid://71951880133711", Damage = 14, Cooldown = 0.26, HitDelay = 0.12 }, -- RapierThrust1
		{ Animation = "rbxassetid://73842983778232", Damage = 16, Cooldown = 0.26, HitDelay = 0.11 }, -- RapierThrust2
		{ Animation = "rbxassetid://99868728319102", Damage = 28, Cooldown = 0.55, HitDelay = 0.2, Lunge = 32, Knockback = 12 }, -- RapierThrust3
	},
	ComboWindow = 0.8,
	Range = 8.5, -- reaches past a sword...
	Width = 3, -- ...but only along the point
	Height = 5,
	Block = {
		Animation = Sword.Block.Animation,
		BlockAmount = 14,
		ParryWindow = 0.28, -- a duelist's blade: the best parry of the swords
	},
	Heavy = {
		Kind = "Flurry",
		Stamina = 22,
		WindUpAnimation = "rbxassetid://84782831490199", -- RapierWindUp
		FlurryAnimation = "rbxassetid://102139168442942", -- RapierFlurry
		HoldTime = 0.2,
		FullChargeTime = 1.1,
		MaxHold = 2.5,
		MinHits = 3,
		MaxHits = 8,
		Damage = 9,
		Interval = 0.09, -- matches RapierFlurry (two stabs per loop)
		HitDelay = 0.08,
		Range = 9,
		Width = 3.5,
		Height = 5,
		FinalKnockback = 20,
		Advance = 6,
		Recovery = 0.6,
		WalkSpeed = 6,
	},
}

-- Dagger: a light knife for close work (the mage's sidearm, but anyone can use it). A fast
-- 4-hit combo mixing slashes and stabs with very little reach; its heavy is a backstab: a
-- quick crouch, then a short lunge into one deep stab. Guards and parries, but its block
-- absorbs very little. Animations from tools/dagger_anims.py.
local Dagger: ComboWeapon = {
	ToolName = "Dagger",
	Hand = "Right",
	IdleAnimation = "rbxassetid://72729646632069", -- DaggerIdle
	AnimationSpeed = 1,
	Stamina = 4,
	ModelFit = { Length = 2.6, GripFrom = 0.23 }, -- the hand round the middle of the wooden grip
	TrailColor = Color3.fromRGB(225, 230, 240),
	Combo = {
		-- HitDelay matches each move's "Hit" keyframe in tools/dagger_anims.py.
		{ Animation = "rbxassetid://116823676876543", Damage = 9, Cooldown = 0.22, HitDelay = 0.1 }, -- DaggerSlash1
		{ Animation = "rbxassetid://90557310267126", Damage = 9, Cooldown = 0.22, HitDelay = 0.1 }, -- DaggerSlash2
		{ Animation = "rbxassetid://83346210942030", Damage = 11, Cooldown = 0.24, HitDelay = 0.1 }, -- DaggerStab3
		{ Animation = "rbxassetid://114949057482513", Damage = 18, Cooldown = 0.45, HitDelay = 0.16, Lunge = 18, Knockback = 10 }, -- DaggerStab4
	},
	ComboWindow = 0.7,
	Range = 4.5, -- very short: you have to be right on them
	Width = 4.5,
	Height = 5,
	Block = {
		Animation = "rbxassetid://99184131102784", -- DaggerGuard
		BlockAmount = 8, -- the lightest guard there is
		ParryWindow = 0.24,
	},
	Heavy = {
		Kind = "Thrust",
		Stamina = 16,
		WindUpAnimation = "rbxassetid://85052814385918", -- DaggerWindUp
		ThrustAnimation = "rbxassetid://118491558524288", -- DaggerBackstab
		HoldTime = 0.2,
		FullChargeTime = 0.6, -- quick to ready
		MaxHold = 2,
		MinDamage = 28,
		MaxDamage = 55,
		MinDistance = 3,
		MaxDistance = 8,
		LungeTime = 0.15,
		Reach = 3,
		Width = 3.5,
		Height = 5,
		Knockback = 8,
		HitDelay = 0.12, -- matches DaggerBackstab's "Hit" keyframe
		Recovery = 0.5,
		WalkSpeed = 9,
	},
}

-- How many stabs a flurry gets for a charge of `power` (0..1), plus `bonus` from skills
-- (FlurryHits). Shared so the client's animation and the server's hits agree.
local function flurryHits(flurry: FlurryHeavy, power: number, bonus: number?): number
	return math.round(flurry.MinHits + (flurry.MaxHits - flurry.MinHits) * math.clamp(power, 0, 1)) + (bonus or 0)
end

-- One-handed axe: hard-hitting chops (the third hops in and knocks back). Its heavy is a
-- leaping cleave that leaves enemies bleeding. Animations from tools/sword_anims.py
-- (Axe*); leave "" until published. Guards like the sword.
local Axe: ComboWeapon = {
	ToolName = "Axe",
	Hand = "Right",
	IdleAnimation = "125266707080163", -- AxeIdle
	AnimationSpeed = 1,
	Stamina = 10,
	-- Shift moves the hand onto the haft, which sits off to one side of the model (in the
	-- imported model's terms: Studio turns GLBs 180 degrees on import, see WeaponModels).
	ModelFit = { Length = 3.8, GripFrom = 0.22, Shift = Vector3.new(-0.124, 0, 0) },
	Combo = {
		-- HitDelay matches each chop's "Hit" keyframe in tools/sword_anims.py.
		{ Animation = "rbxassetid://77572045003423", Damage = 22, Cooldown = 0.4, HitDelay = 0.2 }, -- AxeChop1
		{ Animation = "rbxassetid://138312767684322", Damage = 26, Cooldown = 0.4, HitDelay = 0.17 }, -- AxeChop2
		{ Animation = "rbxassetid://97744825235225", Damage = 42, Cooldown = 0.75, HitDelay = 0.31, Knockback = 25 }, -- AxeChop3
	},
	ComboWindow = 0.8,
	Range = 6.5,
	Width = 6,
	Height = 6,
	Block = {
		Animation = Sword.Block.Animation,
		BlockAmount = 22,
		ParryWindow = 0.2,
	},
	Heavy = {
		Kind = "Thrust",
		Stamina = 22,
		WindUpAnimation = "rbxassetid://86819744387869", -- AxeWindUp
		ThrustAnimation = "rbxassetid://118861083375033", -- AxeCleave
		HoldTime = 0.2,
		FullChargeTime = 1,
		MaxHold = 2.5,
		MinDamage = 30,
		MaxDamage = 60,
		MinDistance = 3, -- a short hop...
		MaxDistance = 9, -- ...to a full leap
		LungeTime = 0.2,
		Reach = 6,
		Width = 6, -- a wide chop, not a narrow thrust
		Height = 6,
		Knockback = 15,
		HitDelay = 0.15, -- matches AxeCleave's "Hit" keyframe
		Recovery = 0.9,
		WalkSpeed = 6,
		Bleed = { Damage = 5, Interval = 0.5, Duration = 3 }, -- 30 more over 3 seconds
		FlipGrip = true, -- the cleave's animations hold the axe the other way round
	},
}

-- Dual Blade: a pair of short blades, light and fast. A four-cut combo alternating hands (the
-- last a crossing slash that knocks back). Its heavy gathers, then rushes wherever you walk,
-- spinning and slashing everything around. A light guard but a good parry: it rewards timing.
-- Animations from tools/dualblade_anims.py.
local DualBlade: ComboWeapon = {
	ToolName = "DualBlade",
	Hand = "Right", -- and its twin in the left (DualWield)
	DualWield = true,
	IdleAnimation = "rbxassetid://126261020043365", -- DualBladeIdle
	AnimationSpeed = 1,
	Stamina = 5,
	-- The hand on the grip wrap, which sits a little off the model's center line (in the imported
	-- model's terms: Studio turns GLBs 180 degrees on import, see WeaponModels). FlipEdge turns
	-- it so the edge leads the cuts.
	ModelFit = { Length = 3.5, GripFrom = 0.13, Shift = Vector3.new(0.03, 0, 0), FlipEdge = true },
	TrailColor = Color3.fromRGB(200, 215, 255),
	Combo = {
		-- HitDelay matches each slash's "Hit" keyframe in tools/dualblade_anims.py.
		{ Animation = "rbxassetid://85225520731947", Damage = 12, Cooldown = 0.2, HitDelay = 0.1 }, -- DualBladeSlash1 (right)
		{ Animation = "rbxassetid://90923424107382", Damage = 12, Cooldown = 0.2, HitDelay = 0.1 }, -- DualBladeSlash2 (left)
		{ Animation = "rbxassetid://97352809754863", Damage = 15, Cooldown = 0.24, HitDelay = 0.11 }, -- DualBladeSlash3 (right, spinning)
		{ Animation = "rbxassetid://96172665039338", Damage = 26, Cooldown = 0.45, HitDelay = 0.16, Knockback = 15, Lunge = 24 }, -- DualBladeSlash4 (both)
	},
	ComboWindow = 0.7,
	Range = 5.5,
	Width = 6.5,
	Height = 6,
	Block = {
		Animation = "rbxassetid://85472441817145", -- DualBladeGuard
		BlockAmount = 12,
		ParryWindow = 0.27, -- quick hands: second only to the spear
	},
	Heavy = {
		Kind = "Rush",
		WindUpAnimation = "rbxassetid://106005210293110", -- DualBladeWindUp
		RushAnimation = "rbxassetid://132412277806315", -- DualBladeRush
		Stamina = 5, -- per hit
		HoldTime = 0.2,
		ChargeTime = 0.6,
		WalkSpeed = 6,
		Speed = 24,
		TickInterval = 0.3, -- matches one turn of DualBladeRush
		Damage = 10,
		Radius = 7,
		MaxDuration = 3,
		Recovery = 0.8,
	},
}

-- Scythe: a long, two-handed reaper's blade that towers over its wielder. Slow, wide reaps
-- that hit everything around (a forehand sweep, a full spin, an overhead crescent that steps
-- in and knocks back). Its heavy reaches far out to hook an enemy, drags it in, and cuts it
-- away. A middling guard and a short parry window: the reach is its defense.
-- Animations from tools/scythe_anims.py.
local Scythe: ComboWeapon = {
	ToolName = "Scythe",
	Hand = "Right",
	IdleAnimation = "rbxassetid://109652222193210", -- ScytheIdle
	AnimationSpeed = 1,
	Stamina = 8, -- a wide sweep costs more than a cut
	-- Taller than its wielder, like the spear. The hand holds the low end of the grip wrap;
	-- the shaft sits off the model's center (the blade sticks out to one side), and FlipEdge
	-- turns the blade to lead the reaps (in the imported model's terms, see WeaponModels).
	ModelFit = { Length = 8, GripFrom = 0.3, Shift = Vector3.new(0.228, 0, 0), FlipEdge = true },
	TrailColor = Color3.fromRGB(190, 200, 215),
	Combo = {
		-- HitDelay matches each reap's "Hit" keyframe in tools/scythe_anims.py.
		{ Animation = "rbxassetid://100336990978687", Damage = 18, Cooldown = 0.42, HitDelay = 0.2, Radius = 9, Arc = 200 }, -- ScytheSlash1 (forehand sweep)
		{ Animation = "rbxassetid://79245477162837", Damage = 20, Cooldown = 0.5, HitDelay = 0.25, Radius = 9, Arc = 360 }, -- ScytheSlash2 (full spin)
		{ Animation = "rbxassetid://84455638228199", Damage = 34, Cooldown = 0.75, HitDelay = 0.26, Radius = 10, Arc = 160, Lunge = 20, Knockback = 18 }, -- ScytheSlash3 (crescent)
	},
	ComboWindow = 0.8,
	-- The box hitbox isn't used (every reap sweeps), but stays sized like the reach.
	Range = 9,
	Width = 12,
	Height = 6,
	Block = {
		Animation = "rbxassetid://137637794904376", -- ScytheGuard
		BlockAmount = 14,
		ParryWindow = 0.2,
	},
	Heavy = {
		Kind = "Reap",
		Animation = "rbxassetid://93099600284244", -- ScytheReap
		Stamina = 22,
		HoldTime = 0.2,
		WalkSpeed = 2,
		HookDelay = 0.3, -- matches ScytheReap's "Hit" marker
		Reach = 12,
		Width = 5,
		Height = 6,
		HookDamage = 8,
		PullTime = 0.3,
		PullTo = 4,
		CutDelay = 0.78, -- matches ScytheReap's "Cut" marker
		CutDamage = 40,
		CutRadius = 8,
		CutArc = 220,
		Knockback = 32,
		Duration = 1.15,
		Recovery = 0.6,
	},
}

-- Hammer: a huge two-handed warhammer, the heaviest weapon (you walk slowly with it out).
-- Slow, crushing blows: an overhead pound into the ground in front, a wide sweeping swing,
-- then a leaping pound that knocks everything back. Its heavy raises it high while held and
-- slams the ground: a shockwave like the mace's, but wider and throwing enemies much further.
-- The sturdiest guard, but the hardest to parry with. Animations from tools/hammer_anims.py.
local Hammer: ComboWeapon = {
	ToolName = "Hammer",
	Hand = "Right",
	WalkSpeed = 12, -- like the greatsword
	IdleAnimation = "rbxassetid://126322227016170", -- HammerIdle
	AnimationSpeed = 1,
	Stamina = 14,
	-- Scaled up well past the model's own size: it should look huge. The right hand holds the
	-- top of the grip wrap, the left hand below it.
	ModelFit = { Length = 7.2, GripFrom = 0.24 },
	TrailColor = Color3.fromRGB(255, 210, 150),
	Combo = {
		-- HitDelay matches each blow's "Hit" keyframe in tools/hammer_anims.py.
		{ Animation = "rbxassetid://72402918663640", Damage = 30, Cooldown = 0.65, HitDelay = 0.36, Radius = 8, Arc = 110, Knockback = 15, Shockwave = true }, -- HammerPound
		{ Animation = "rbxassetid://107585366377673", Damage = 34, Cooldown = 0.65, HitDelay = 0.33, Radius = 9.5, Arc = 220, Knockback = 25 }, -- HammerSwing
		{ Animation = "rbxassetid://91897241931056", Damage = 55, Cooldown = 1.1, HitDelay = 0.46, Radius = 10, Arc = 150, Knockback = 45, Lunge = 18, Shockwave = true }, -- HammerCrush
	},
	ComboWindow = 0.8,
	-- The box hitbox isn't used (every blow is a Radius sweep), but stays sized like the reach.
	Range = 9,
	Width = 9,
	Height = 8,
	Block = {
		Animation = "rbxassetid://87210542607297", -- HammerGuard
		BlockAmount = 35, -- as sturdy as the greatsword
		ParryWindow = 0.12, -- and as hard to parry with
	},
	Heavy = {
		Kind = "Quake",
		Stamina = 30,
		WindUpAnimation = "rbxassetid://106260116576920", -- HammerWindUp
		SlamAnimation = "rbxassetid://87753330606839", -- HammerSlam
		HoldTime = 0.25,
		FullChargeTime = 1.5,
		MaxHold = 3,
		MinDamage = 45,
		MaxDamage = 110,
		MinRadius = 7,
		MaxRadius = 14,
		Knockback = 40, -- the mace's is 25 (for 0.2 s): this throws enemies 3 to 6 times as far
		MaxKnockback = 80,
		KnockbackTime = 0.35,
		HitDelay = 0.2, -- matches HammerSlam's "Hit" keyframe
		Recovery = 1.3,
		WalkSpeed = 4,
	},
}

-- One element of the staff: its light missile and its charged heavy attack.
--   Light: a missile flying at Speed; Damage on the first enemy it hits, plus optional
--     Slow { Factor, Duration }, Knockback (studs/s), Chain { Count, Range, DamageScale },
--     or Heal (Faith: heals the ally it hits; only nicks enemies).
--   Heavy: charged up to the staff's FullChargeTime; damage (or healing) goes from Min to Max
--     by charge. Its Kind decides what it does:
--       FireWave: slam the ground; a wall of fire rolls forward Range studs at Speed,
--         Width wide, burning (Burn { Damage, Interval, Duration }) everything it passes
--       WaterBlast: a torrent straight ahead, Range long and Width wide, with Knockback
--       Boulder: a giant rock (Size) thrown in an arc (Speed, Gravity) that crashes down in a
--         Radius, with Knockback and Stun
--       Thunder: lightning strikes the aim point (within Range) after Delay, hitting a Radius
--         around it and slowing (Slow) everything caught
--       HealBurst: heals you and every player within Radius (MinHeal..MaxHeal)
--       Homing: MinCount..MaxCount (by charge) missiles that each seek an enemy: your lock-on
--         target if you have one (within Range), else the nearest enemy within Range; they
--         fly at Speed, turning up to TurnRate degrees a second
--   Missile (optional): "Hand" flies an undead hand instead of an orb.
export type StaffElement = {
	Name: string,
	Icon: string,
	Color: Color3,
	Missile: "Orb" | "Hand" | nil,
	Light: { Damage: number, Speed: number, Size: number, Heal: number?, Knockback: number?, Slow: { Factor: number, Duration: number }?, Burn: { Damage: number, Interval: number, Duration: number }?, Chain: { Count: number, Range: number, DamageScale: number }? },
	Heavy: {
		Kind: "FireWave" | "WaterBlast" | "Boulder" | "Thunder" | "HealBurst" | "Homing",
		MinCount: number?,
		MaxCount: number?,
		TurnRate: number?,
		MinDamage: number,
		MaxDamage: number,
		Range: number?,
		Width: number?,
		Radius: number?,
		Speed: number?,
		Size: number?,
		Gravity: number?,
		Delay: number?,
		MinHeal: number?,
		MaxHeal: number?,
		Knockback: number?,
		Stun: number?,
		Slow: { Factor: number, Duration: number }?,
		Burn: { Damage: number, Interval: number, Duration: number }?,
	},
}

-- A caster weapon (the staff, the grimoire): a set of elements (switch with R or the element
-- bar). Tap to fire a missile at what you're aiming at (or your lock-on target); hold to charge
-- a stronger spell. Run by StaffService and StaffClient (one for every caster). Its skill tree
-- is a class (SkillTrees.Casters): unlock the class, then each element.
-- Staff: four elements. Animations from tools/sword_anims.py (Staff*); "" until published.
local Staff = {
	ToolName = "Staff",
	Hand = "Right",
	IdleAnimation = "123330122713275", -- StaffIdle
	CastAnimation = "113419380544278", -- StaffCast (light)
	ChargeAnimation = "80897307077510", -- StaffCharge (held raised while charging)
	BlastAnimation = "73647528064933", -- StaffBlast (heavy release: Water, Earth, Lightning, Faith)
	SlamAnimation = "", -- StaffSlam (Fire\'s heavy: the staff slammed into the ground)
	-- How the hand holds it (Tool.Grip): its length along the grip part's Z.
	Grip = CFrame.new(0, 0, -0.3) * CFrame.Angles(math.pi / 2, 0, 0),
	AimWithHand = false, -- see the grimoire's
	ElementKey = Enum.KeyCode.R, -- cycles the element
	CastMana = 15, -- mana per light missile (see Mana: about 6 missiles from full)
	ChargeMana = 40, -- mana to start charging a blast
	CastCooldown = 0.45, -- seconds between light missiles
	CastDelay = 0.14, -- seconds from click to the missile leaving (matches StaffCast's "Hit")
	HoldTime = 0.2, -- hold this long to charge instead of casting
	FullChargeTime = 1.4,
	MaxHold = 3, -- charging this long releases by itself
	BlastDelay = 0.12, -- seconds from release to the blast leaving (matches StaffBlast's "Hit")
	Recovery = 0.8, -- seconds after a blast before the next charge
	ChargeWalkSpeed = 8,
	MaxRange = 140, -- studs a missile flies before fizzling
	-- A real model (assets/weapons/Staff.rbxmx); see Sword.ModelFit. Held below the middle.
	ModelFit = { Length = 6, GripFrom = 0.38 },
	Elements = {
		{
			Name = "Fire", Icon = "Fire", Color = Color3.fromRGB(255, 120, 40),
			Light = { Damage = 14, Speed = 110, Size = 1 },
			Heavy = { Kind = "FireWave", MinDamage = 25, MaxDamage = 55, Range = 28, Width = 9, Speed = 38, Burn = { Damage = 4, Interval = 0.5, Duration = 3 } },
		},
		{
			Name = "Water", Icon = "Water", Color = Color3.fromRGB(70, 160, 255),
			Light = { Damage = 12, Speed = 110, Size = 1, Slow = { Factor = 0.6, Duration = 2 } },
			Heavy = { Kind = "WaterBlast", MinDamage = 25, MaxDamage = 55, Range = 26, Width = 7, Knockback = 40 },
		},
		{
			Name = "Earth", Icon = "Earth", Color = Color3.fromRGB(170, 125, 70),
			Light = { Damage = 18, Speed = 70, Size = 1.3, Knockback = 15 },
			Heavy = { Kind = "Boulder", MinDamage = 40, MaxDamage = 90, Radius = 8, Speed = 75, Size = 4, Gravity = 45, Knockback = 25, Stun = 0.6 },
		},
		{
			Name = "Electric", Icon = "Electric", Color = Color3.fromRGB(255, 235, 90),
			Light = { Damage = 10, Speed = 170, Size = 0.8, Chain = { Count = 2, Range = 12, DamageScale = 0.6 } },
			Heavy = { Kind = "Thunder", MinDamage = 30, MaxDamage = 65, Range = 70, Radius = 10, Delay = 0.35, Slow = { Factor = 0.5, Duration = 3 } },
		},
	} :: { StaffElement },
}

-- Grimoire: a tome of necromancy and faith, held open in the left hand while the right casts.
-- Necromancy throws grasping undead hands, and its charged spell looses a few of them that hunt
-- down enemies (your lock-on target first). Faith heals allies. Animations from
-- tools/grimoire_anims.py.
local Grimoire = {
	ToolName = "Grimoire",
	Hand = "Left",
	IdleAnimation = "129767567804443", -- GrimoireIdle
	CastAnimation = "124629734591157", -- GrimoireCast (light)
	ChargeAnimation = "94630732418140", -- GrimoireCharge (held while charging)
	BlastAnimation = "101609423364698", -- GrimoireBlast (heavy release)
	SlamAnimation = "",
	-- Held by the bottom of its spine, turned so its pages face the reader.
	Grip = CFrame.Angles(0, 0, math.rad(-90)) * CFrame.new(0, 0, -0.3) * CFrame.Angles(math.pi / 2, 0, 0),
	-- While casting, the head and the free (right) hand turn onto the aim on top of the
	-- animations, and the head watches the lock-on target between casts (StaffClient).
	AimWithHand = true,
	ElementKey = Enum.KeyCode.R,
	CastMana = 14,
	ChargeMana = 40,
	CastCooldown = 0.45,
	CastDelay = 0.14, -- matches GrimoireCast's "Hit"
	HoldTime = 0.2,
	FullChargeTime = 1.3,
	MaxHold = 3,
	BlastDelay = 0.15, -- matches GrimoireBlast's "Hit"
	Recovery = 0.8,
	ChargeWalkSpeed = 8,
	MaxRange = 140,
	-- A real model (assets/weapons/Grimoire.rbxmx): held by the spine, the book standing upright.
	ModelFit = { Length = 1.6, GripFrom = 0.2 },
	Elements = {
		{
			Name = "Necromancy", Icon = "Necromancy", Color = Color3.fromRGB(130, 220, 120), Missile = "Hand",
			Light = { Damage = 15, Speed = 35, Size = 1.9 },
			Heavy = { Kind = "Homing", MinDamage = 18, MaxDamage = 32, MinCount = 2, MaxCount = 3, Range = 70, Speed = 25, Size = 2.1, TurnRate = 300 },
		},
		{
			Name = "Faith", Icon = "Faith", Color = Color3.fromRGB(255, 245, 190),
			Light = { Damage = 6, Speed = 120, Size = 1, Heal = 12 },
			Heavy = { Kind = "HealBurst", MinDamage = 0, MaxDamage = 0, Radius = 15, MinHeal = 10, MaxHeal = 30 },
		},
	} :: { StaffElement },
}

-- A ranged weapon that fires once and then reloads (the crossbow, the blunderbuss; see
-- SingleShotService). Hold right-click to aim (zoom in, slow down, face the aim); left-click
-- fires, aiming or not.
export type SingleShot = {
	ToolName: string,
	Hand: string,
	IdleAnimation: string, -- loops while equipped
	AimAnimation: string, -- held on its last frame while aiming
	ShootAnimation: string, -- the kick as it fires
	ReloadAnimation: string, -- stretched to the reload time
	ShootRemote: string, -- the RemoteEvent (in Remotes) the client fires to shoot
	Damage: number, -- per projectile
	ProjectileSpeed: number, -- studs per second
	Pellets: number?, -- projectiles per shot (1 if nil)
	Spread: number?, -- degrees; each pellet flies up to this far off the aim
	DamageRange: number?, -- studs; projectiles do no damage past this (no limit if nil)
	ReloadTime: number, -- seconds after each shot before it can fire again
	ReloadWalkSpeed: number,
	AimWalkSpeed: number,
	AimZoomFov: number, -- camera field of view while aiming (Roblox default is 70)
	AimZoomTime: number,
	ZoomOutTime: number,
	ShotStamina: number,
	Clip: number?, -- shots it holds before it has to reload (1 if nil)
	ShotDelay: number?, -- seconds between shots from the same clip
	Ammo: string, -- the player attribute holding its ammo; "Max" .. Ammo holds the most
	MaxAmmo: number,
	Gravity: number, -- downward pull on its projectiles, studs/s² (workspace gravity is ~196)
	MaxRange: number, -- projectiles vanish after flying this far
	StuckLifetime: number, -- seconds a projectile stays stuck in what it hit
	TrailLifetime: number, -- seconds a projectile's streak takes to fade behind it
	ModelFit: { Length: number, GripFrom: number, Shift: Vector3?, FlipBlade: boolean?, FlipEdge: boolean? },
}

-- The bow's heavier cousin: no draw, every bolt flies at full power, but it has to be
-- reloaded after every shot. Hold right-click to aim (zoom in, slow down, face the aim);
-- left-click fires, aiming or not. Its flight, ammo refills, and arrows-stick-in-things
-- work like the bow's (see SingleShotService).
local Crossbow: SingleShot = {
	ToolName = "Crossbow",
	Hand = "Right",
	-- Made by tools/crossbow_anims.py (assets/animations). While "", that one doesn't play.
	IdleAnimation = "rbxassetid://76216598845137", -- CrossbowIdle: held low and ready; loops while equipped
	AimAnimation = "rbxassetid://80845530831049", -- CrossbowAim: raised to the shoulder; held on its last frame while aiming
	ShootAnimation = "rbxassetid://136461210557366", -- CrossbowShoot: the kick as it fires
	ReloadAnimation = "rbxassetid://77673098666584", -- CrossbowReload: string cranked back, a bolt laid in; stretched to ReloadTime
	Damage = 55, -- every bolt (the bow's full draw is 40)
	ProjectileSpeed = 230, -- studs per second (the bow's full draw is 200)
	ReloadTime = 1.3, -- seconds after each shot before it can fire again
	ReloadWalkSpeed = 10, -- walk speed while reloading
	AimWalkSpeed = 8, -- walk speed while aiming
	AimZoomFov = 45, -- camera field of view while aiming (Roblox default is 70)
	AimZoomTime = 0.15, -- seconds to zoom in
	ZoomOutTime = 0.25, -- seconds to zoom back out
	ShotStamina = 8, -- stamina per bolt
	ShootRemote = "CrossbowShoot",
	Ammo = "Bolts", -- the player attributes Bolts / MaxBolts
	MaxAmmo = 20,
	Gravity = 25, -- downward pull on bolts, studs/s² (flatter than arrows)
	MaxRange = 350, -- bolts vanish after flying this far
	StuckLifetime = 4, -- seconds a bolt stays stuck in what it hit
	TrailLifetime = 0.3, -- seconds a bolt's streak takes to fade behind it
	-- A real model (assets/weapons/Crossbow.rbxmx); see Sword.ModelFit. It's held like a
	-- pistol, so its tool Grip (SingleShotService) runs it along the forearm with the thumb
	-- on top, not out of the fist like a blade. Shift lowers the hand under the stock.
	ModelFit = { Length = 3.8, GripFrom = 0.36, Shift = Vector3.new(0, 0, -0.04) },
}

-- A short-range gun: each shot is a spray of pellets that fly dead straight (no drop) but do
-- nothing past DamageRange, so it's deadly up close and harmless at range. Fires 3 shots
-- (ShotDelay apart), then reloads.
local Blunderbuss: SingleShot = {
	ToolName = "Blunderbuss",
	Hand = "Right",
	-- Made by tools/blunderbuss_anims.py (assets/animations): held one-handed like a big
	-- pistol. Until they're published these borrow the crossbow's; put each one's id in place.
	IdleAnimation = "113773098230304", -- BlunderbussIdle: low by the hip, muzzle down; loops while equipped
	AimAnimation = "83517724451635", -- BlunderbussAim: arm out straight; held on its last frame
	ShootAnimation = "83517724451635", -- BlunderbussShoot: the kick throws the arm up
	ReloadAnimation = Crossbow.ReloadAnimation, -- BlunderbussReload: broken open, a shell from the belt thumbed in, flicked shut; stretched to ReloadTime
	ShootRemote = "BlunderbussShoot",
	Damage = 10, -- per pellet: 80 if all of them hit
	Pellets = 8,
	Spread = 7, -- degrees off the aim, at most
	DamageRange = 35, -- studs; pellets past this do no damage
	ProjectileSpeed = 180,
	Clip = 3, -- shots before it has to reload
	ShotDelay = 0.5, -- seconds between those shots
	ReloadTime = 1.8, -- once all 3 are fired
	ReloadWalkSpeed = 10,
	AimWalkSpeed = 9,
	AimZoomFov = 55, -- less zoom than the crossbow: it's for close range
	AimZoomTime = 0.15,
	ZoomOutTime = 0.25,
	ShotStamina = 10,
	Ammo = "Shells", -- the player attributes Shells / MaxShells
	MaxAmmo = 12,
	Gravity = 0, -- pellets fly straight
	MaxRange = 50, -- they vanish this far out (harmless for the last stretch)
	StuckLifetime = 0.6,
	TrailLifetime = 0.12,
	-- A real model (assets/weapons/Blunderbuss.rbxmx); gripped like the crossbow (the tool Grip
	-- in SingleShotService), by the wrist of the stock just behind the trigger.
	ModelFit = { Length = 3.6, GripFrom = 0.24 },
}

return {
	Sword = Sword,
	Emberfang = Emberfang,
	Mace = Mace,
	Spear = Spear,
	Rapier = Rapier,
	Dagger = Dagger,
	flurryHits = flurryHits,
	Axe = Axe,
	DualBlade = DualBlade,
	Scythe = Scythe,
	Hammer = Hammer,
	Staff = Staff,
	Grimoire = Grimoire,
	-- Every caster weapon, for the systems that serve them all (StaffService, StaffClient, ManaBar).
	Casters = { Staff, Grimoire },
	-- Shared by every weapon that can block (sword, mace, greatsword). Hold right-click to
	-- block; each block uses one charge, and each used charge comes back RechargeTime later.
	Blocking = {
		MaxCharges = 3,
		RechargeTime = 5,
		WalkSpeed = 8, -- walk speed while blocking
		KnockbackSpeed = 22, -- studs/s you're shoved back when a block lands
		KnockbackTime = 0.15, -- seconds the shove lasts
		-- Parry: a hit landing within the weapon's ParryWindow of raising the guard is
		-- negated completely (no charge used) and stuns the attacker for ParryStun seconds.
		-- Raising the guard again within ParryRecovery of the last time gets no parry window,
		-- so mashing block doesn't work.
		ParryStun = 0.5,
		ParryRecovery = 0.5,
	},
	-- Two-handed greatsword: hold left-click to charge (feet planted), release to slam.
	-- The charge level reached decides damage; level 2+ knocks enemies back.
	Greatsword = {
		ToolName = "Greatsword",
		Hand = "Right",
		WalkSpeed = 12, -- while equipped (heavy)
		-- Animation IDs; leave "" until published (the weapon still works, just unanimated).
		IdleAnimation = "rbxassetid://118849792931819",
		ChargeAnimation = "rbxassetid://98786062327224", -- frozen on its last frame while holding the charge
		SlamAnimation = "rbxassetid://112152707381541",
		GuardAnimation = "rbxassetid://121573830441683",
		-- Tap left-click for the combo; hold it for HoldTime to start charging a slam instead.
		HoldTime = 0.25,
		-- Combo swings: wide sweeps that hit everything within Radius studs inside an Arc
		-- (degrees, centred on where you face; 360 = all the way around). HitDelay matches
		-- each swing's "Hit" keyframe in tools/greatsword_anims.py.
		Combo = ({
			{ Animation = "rbxassetid://134521206552991", Damage = 25, Cooldown = 0.6, HitDelay = 0.3, Radius = 10, Arc = 200 }, -- GreatswordSwing1
			{ Animation = "rbxassetid://76640107806249", Damage = 30, Cooldown = 0.6, HitDelay = 0.29, Radius = 10, Arc = 200 }, -- GreatswordSwing2
			{ Animation = "rbxassetid://114659523395029", Damage = 45, Cooldown = 1.0, HitDelay = 0.42, Radius = 11, Arc = 360, Knockback = 30 }, -- GreatswordSwing3
		} :: { GreatswordSwing }),
		ComboWindow = 0.8, -- seconds after a swing's cooldown to click again before the combo resets
		SwingWalkSpeed = 6, -- while swinging
		SwingStamina = 14, -- stamina per combo swing
		SlamStamina = 25, -- stamina to start charging a slam
		-- Charge levels: reached after holding for Time seconds (counted once charging starts).
		ChargeLevels = {
			{ Time = 0, Damage = 35, Knockback = 0 },
			{ Time = 0.5, Damage = 55, Knockback = 0 },
			{ Time = 1.0, Damage = 80, Knockback = 35 },
			{ Time = 1.6, Damage = 120, Knockback = 60 },
		},
		KnockbackTime = 0.25, -- seconds enemies are pushed for
		HitDelay = 0.13, -- seconds after release that the slam lands (matches the animation)
		Recovery = 0.9, -- seconds after a slam before you can charge again
		Range = 10, -- hitbox reach in front, in studs
		Width = 9,
		Height = 8,
		BlockAmount = 35, -- damage absorbed per block while guarding with the greatsword
		ParryWindow = 0.12, -- seconds after raising the guard that a hit is parried: the hardest to parry with
		ModelFit = { Length = 8.9, GripFrom = 0.18 }, -- a real model (assets/weapons/Greatsword.rbxmx); see Sword.ModelFit
	},
	Bow = {
		ToolName = "Bow",
		Hand = "Right", -- "Left" or "Right"; must match the hand the bow animations were made for
		IdleAnimation = "rbxassetid://107914048958318", -- loops while the bow is equipped
		ChargeAnimation = "rbxassetid://74878365746948", -- plays while drawing; held on its last frame
		ShootAnimation = "rbxassetid://133197627404697", -- plays on release
		-- Hold right-click to draw; power grows from 0 to 1 over MaxDrawTime and scales
		-- damage and arrow speed between their Min and Max.
		MaxDrawTime = 1, -- seconds to reach full power
		MinDamage = 10,
		MaxDamage = 40,
		MinArrowSpeed = 90, -- studs per second
		MaxArrowSpeed = 200,
		DrawWalkSpeed = 8, -- walk speed while drawing
		DrawZoomFov = 50, -- camera field of view at full draw (Roblox default is 70; lower = more zoom)
		ZoomOutTime = 0.25, -- seconds to zoom back out after releasing
		DrawPull = 1.6, -- studs the string pulls back at full draw (visual)
		Cooldown = 0.3, -- seconds between shots
		TrailLifetime = 0.35, -- seconds an arrow's glowing streak takes to fade behind it
		-- A real model (assets/weapons/Bow.rbxm); see Sword.ModelFit. Shift moves the hand onto
		-- the model's grip; FlipEdge turns it so the string faces the player. StringTips: where
		-- the string meets the limbs, relative to the hand, as fractions of Length: (0, back, up)
		-- for the upper tip; the lower tip mirrors it.
		ModelFit = { Length = 5.6, GripFrom = 0.5, Shift = Vector3.new(-0.072, 0, 0), FlipEdge = true },
		StringTips = Vector3.new(0, -0.157, 0.49),
		ShotStamina = 6, -- stamina per arrow
		MaxArrows = 30,
		Gravity = 40, -- downward pull on arrows, studs/s² (workspace gravity is ~196)
		MaxRange = 300, -- arrows vanish after flying this far
		StuckLifetime = 4, -- seconds an arrow stays stuck in what it hit
	},

	Crossbow = Crossbow,
	Blunderbuss = Blunderbuss,
	-- Press Key to dash. Up to MaxCharges stored; spent charges refill one at a time,
	-- each taking RechargeTime.
	-- Lock-on (see LockOn): face and follow one enemy, with the camera framing you both.
	LockOn = {
		Key = Enum.KeyCode.Q, -- toggles the lock (touch screens get a button)
		Range = 60, -- studs: how far away a target can be picked (and switched to)
		BreakRange = 90, -- studs: the lock lets go past this
		MaxAngle = 75, -- degrees from the centre of the view a target can be picked
		-- The camera sits behind you and a little to your right, aimed at the target. With a
		-- ranged or magic weapon out and the target further than RangedFrom, it closes in over
		-- your shoulder.
		-- Melee is a duel framing (after Dueling Grounds), aimed at the target so it sits centre
		-- screen. Up close (where most fights are) the camera is high and further round to your
		-- right, looking down past your left side, so the enemy shows above your head and to the
		-- right of your body and weapon (its whole wind-up stays in view to time a parry); as it
		-- gets further away it drops lower and swings in nearly straight behind you.
		Melee = {
			Angle = 28, -- degrees round to your right from straight behind you, up close...
			FarAngle = 10, -- ...and with the target FarDistance away
			Distance = 11, -- studs from you, up close...
			FarDistance = 12, -- ...and with the target FarDistance away
			Height = 7, -- studs above your chest, up close...
			FarHeight = 3.5, -- ...and far away
			Focus = 0.9, -- how far from you to the target the camera aims (0 you, 1 the target), up close...
			FarFocus = 1, -- ...and far away
		},
		Ranged = {
			Angle = 16,
			FarAngle = 12,
			Distance = 8.5,
			FarDistance = 9.5,
			Height = 2.2,
			FarHeight = 2.2,
			Focus = 0.85,
			FarFocus = 1,
		},
		FarDistance = 35, -- studs to the target where the Far values are reached
		RangedFrom = 10, -- studs: closer than this, a ranged weapon uses the melee framing (blended over 10 more)
		BigTarget = 6, -- studs tall: each stud a target is over this moves the camera...
		BigBack = 0.9, -- ...this much further back...
		BigUp = 0.35, -- ...and this much higher
		TurnSpeed = 11, -- how fast the camera swings round as you and the target move (higher = snappier)
		FocusSpeed = 16, -- how fast the aim point follows
		ZoomSpeed = 6, -- how fast distance, height and angle change between framings
		EnterTime = 0.22, -- seconds the camera takes to glide from where it was into the lock framing
		-- Switching to another enemy while locked (the one nearest on that side of the screen):
		SwitchFlick = 110, -- pixels the mouse has to move sideways in a quick flick...
		SwitchFlickTime = 0.12, -- ...within about this many seconds
		SwitchStick = 0.75, -- right stick pushed this far left or right (it re-arms back under 0.35)
		SwitchSwipe = 70, -- pixels a touch swipe across the screen has to cover (in under 0.45 s)
		SwitchCooldown = 0.25, -- seconds between switches
	},
	-- Getting hurt, on your own screen (see DamageFeedback): a red flash and camera shake per
	-- hit, scaled by the share of max health lost; below LowHealth, a pulsing red vignette,
	-- drained colours, and a heartbeat.
	DamageFeedback = {
		FlashMin = 0.35, -- red flash strength (0..1) for the smallest hit...
		FlashPerHealth = 2, -- ...plus this x the share of max health lost
		FlashTime = 0.45, -- seconds for a full flash to fade
		ShakeMin = 0.15, -- studs of camera shake for the smallest hit...
		ShakePerHealth = 1.5, -- ...plus this x the share of max health lost
		ShakeMax = 0.6,
		ShakeTime = 0.3, -- seconds the shake takes to settle
		LowHealth = 0.3, -- below this share of max health, the low-health effects start
		LowHealthDesaturate = 0.45, -- how much colour drains at zero health
	},
	-- Hitstop: when your hit lands, you and the target freeze for Base + damage x PerDamage
	-- seconds (kept between Min and Max), so a sword poke stops for ~0.05 s, a big slam ~0.1 s.
	Hitstop = {
		Base = 0.03,
		PerDamage = 0.0008,
		Min = 0.04,
		Max = 0.1,
	},
	-- More impact when your hit lands (HitFeel), after battlegrounds games. A hit is "heavy" when it
	-- comes from a combo's last swing or a heavy attack (landing within HeavySlack seconds of its hit
	-- time, to cover ping) or when it kills.
	HitImpact = {
		HeavySlack = 0.4,
		-- Camera shake: Min + damage x PerDamage studs (up to Max), x Heavy for heavy hits. Full
		-- strength when the hit is within FullRange studs of you, none past NoneRange (bow shots).
		Shake = { Min = 0.05, PerDamage = 0.0015, Max = 0.16, Heavy = 2, Time = 0.12, FullRange = 8, NoneRange = 20 },
		-- Zoom punch: the view narrows by Degrees (HeavyDegrees for heavy hits) in In seconds and
		-- eases back over Out. Skipped while something else (a bow's aim) is zooming.
		Zoom = { Degrees = 1.2, HeavyDegrees = 4, In = 0.03, Out = 0.2 },
		-- Impact frame on heavy hits: for Time seconds the screen goes grey and harsh and the target
		-- turns into a black silhouette with a red outline. At most one every MinGap seconds.
		ImpactFrame = {
			Enabled = true,
			Time = 0.07,
			MinGap = 0.5,
			Contrast = 0.8,
			Saturation = -0.9,
			Brightness = 0.06,
			Outline = Color3.fromRGB(255, 40, 40),
		},
	},
	-- Mana: what the staff's spells spend (other weapons use stamina). It refills at
	-- RegenPerSecond once you've gone RegenDelay seconds without spending any, but not while
	-- charging a blast. Skills (the Arcana branch) raise both.
	Mana = {
		Max = 100,
		RegenPerSecond = 6,
		RegenDelay = 1.5,
	},
	-- Stamina: attacks spend it (each weapon's cost is in its own section above) and the
	-- server refuses an attack you can't afford. It refills at RegenPerSecond once you've
	-- gone RegenDelay seconds without spending any, but not while spinning or charging a heavy.
	Stamina = {
		Max = 100,
		RegenPerSecond = 30,
		RegenDelay = 0.8,
	},
	Dash = {
		Key = Enum.KeyCode.V,
		MaxCharges = 2,
		RechargeTime = 5, -- seconds to refill one charge
		Speed = 52, -- studs/s during the dash
		Duration = 0.21, -- seconds (Speed x Duration is about how far you go: ~11 studs); about as long as DashEffects holds its pose
		MinInterval = 0.25, -- seconds between dashes, so one press can't use both charges
		IFrameTime = 0.25, -- seconds after a dash starts that incoming hits are dodged
	},
}
