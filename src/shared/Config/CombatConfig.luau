--!strict
-- Combat tuning shared by the server (authoritative) and client (input gating/visuals).

-- One click in a combo weapon's combo. Cooldown: seconds before the next click counts.
-- HitDelay: seconds after the click that the hit lands (line it up with the animation).
-- Knockback / Stun (optional): push the enemy back (studs/s) / stun it (seconds) on hit.
-- Lunge (optional): the attacker surges forward at this many studs/s as they swing.
export type ComboMove = {
	Animation: string,
	Damage: number,
	Cooldown: number,
	HitDelay: number,
	Knockback: number?,
	Stun: number?,
	Lunge: number?,
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

export type HeavyAttack = SpinHeavy | QuakeHeavy | ThrustHeavy | FlurryHeavy

-- A click-combo melee weapon (sword, mace, spear): see WeaponService and ComboWeaponClient.
export type ComboWeapon = {
	ToolName: string,
	Hand: string,
	IdleAnimation: string, -- loops while equipped
	AnimationSpeed: number, -- playback speed for its swing animations (below 1 = heavier)
	Stamina: number, -- stamina each swing costs
	Combo: { ComboMove },
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
	IdleAnimation = "rbxassetid://138485130990728",
	AnimationSpeed = 1,
	Stamina = 8,
	ModelFit = { Length = 5.2, GripFrom = 0.11 },
	Combo = {
		-- HitDelay matches each swing's "Hit" keyframe in tools/sword_anims.py.
		{ Animation = "rbxassetid://140482095490161", Damage = 20, Cooldown = 0.3, HitDelay = 0.15 },
		{ Animation = "rbxassetid://125447325276884", Damage = 25, Cooldown = 0.3, HitDelay = 0.13 },
		{ Animation = "rbxassetid://112266188901588", Damage = 40, Cooldown = 0.6, HitDelay = 0.27 },
	},
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
		{ Animation = Sword.Combo[1].Animation, Damage = 26, Cooldown = 0.3, HitDelay = 0.15 },
		{ Animation = Sword.Combo[2].Animation, Damage = 32, Cooldown = 0.3, HitDelay = 0.13 },
		{ Animation = Sword.Combo[3].Animation, Damage = 52, Cooldown = 0.6, HitDelay = 0.27 },
	},
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

-- Heavier, blunter cousin of the sword: same combo and guard (it reuses the sword's
-- animations, played slower), harder hits, and a finisher that knocks back and stuns.
local MACE_SPEED = 0.8
local Mace: ComboWeapon = {
	ToolName = "Mace",
	Hand = "Right",
	IdleAnimation = Sword.IdleAnimation,
	AnimationSpeed = MACE_SPEED,
	Stamina = 12,
	ModelFit = { Length = 4.4, GripFrom = 0.14 },
	Combo = {
		-- Slower animations land later: the sword's HitDelays divided by MACE_SPEED.
		{ Animation = Sword.Combo[1].Animation, Damage = 25, Cooldown = 0.4, HitDelay = 0.15 / MACE_SPEED },
		{ Animation = Sword.Combo[2].Animation, Damage = 30, Cooldown = 0.4, HitDelay = 0.13 / MACE_SPEED },
		{
			Animation = Sword.Combo[3].Animation,
			Damage = 55,
			Cooldown = 0.75,
			HitDelay = 0.27 / MACE_SPEED,
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
	GuardAnimation = Sword.Block.Animation,
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
	BlockAmount = 12,
	ParryWindow = 0.22,
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
	GuardAnimation = "", -- the book raised as a shield (code-driven while "")
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
	BlockAmount = 10,
	ParryWindow = 0.22,
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

return {
	Sword = Sword,
	Emberfang = Emberfang,
	Mace = Mace,
	Spear = Spear,
	Rapier = Rapier,
	flurryHits = flurryHits,
	Axe = Axe,
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
	-- Press Key to dash. Up to MaxCharges stored; spent charges refill one at a time,
	-- each taking RechargeTime.
	-- Lock-on (see LockOn): face and follow one enemy, with the camera framing you both.
	LockOn = {
		Key = Enum.KeyCode.Q, -- toggles the lock (touch screens get a button)
		Range = 60, -- studs: how far away a target can be picked
		BreakRange = 90, -- studs: the lock lets go past this
		MaxAngle = 75, -- degrees from the centre of the view a target can be picked
		CameraDistance = 13, -- studs behind you
		CameraHeight = 4.5,
		CameraShoulder = 4.5, -- studs over your right shoulder, so you're off to the left of the view and don't block the target
		CameraSmoothing = 9, -- higher = the camera catches up faster
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
		Speed = 60, -- studs/s during the dash
		Duration = 0.18, -- seconds (Speed x Duration is about how far you go: ~11 studs)
		MinInterval = 0.25, -- seconds between dashes, so one press can't use both charges
		IFrameTime = 0.25, -- seconds after a dash starts that incoming hits are dodged
	},
}
