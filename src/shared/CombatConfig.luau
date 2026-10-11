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

-- A click-combo melee weapon (sword, mace, spear): see WeaponService and ComboWeaponClient.
export type ComboWeapon = {
	ToolName: string,
	Hand: string,
	IdleAnimation: string, -- loops while equipped
	AnimationSpeed: number, -- playback speed for its swing animations (below 1 = heavier)
	Combo: { ComboMove },
	ComboWindow: number, -- seconds after a swing's cooldown to click again before the combo resets
	Range: number, -- hitbox depth in front of the player, in studs
	Width: number,
	Height: number,
	Block: {
		Animation: string, -- looping guard stance; "" uses a simple code-driven guard instead
		BlockAmount: number, -- damage absorbed per block (a 35 hit against 20 deals 15)
	},
}

local Sword: ComboWeapon = {
	ToolName = "Sword",
	Hand = "Right",
	IdleAnimation = "rbxassetid://138485130990728",
	AnimationSpeed = 1,
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
	},
}

return {
	Sword = Sword,
	Mace = Mace,
	Spear = Spear,
	-- Shared by every weapon that can block (sword, mace, greatsword). Hold right-click to
	-- block; each block uses one charge, and each used charge comes back RechargeTime later.
	Blocking = {
		MaxCharges = 3,
		RechargeTime = 5,
		WalkSpeed = 8, -- walk speed while blocking
		KnockbackSpeed = 22, -- studs/s you're shoved back when a block lands
		KnockbackTime = 0.15, -- seconds the shove lasts
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
		-- Charge levels: reached after holding for Time seconds.
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
		MaxArrows = 30,
		Gravity = 40, -- downward pull on arrows, studs/s² (workspace gravity is ~196)
		MaxRange = 300, -- arrows vanish after flying this far
		StuckLifetime = 4, -- seconds an arrow stays stuck in what it hit
	},
	-- Press Key to dash. Up to MaxCharges stored; spent charges refill one at a time,
	-- each taking RechargeTime.
	Dash = {
		Key = Enum.KeyCode.V,
		MaxCharges = 2,
		RechargeTime = 5, -- seconds to refill one charge
		Speed = 60, -- studs/s during the dash
		Duration = 0.18, -- seconds (Speed x Duration is about how far you go: ~11 studs)
		MinInterval = 0.25, -- seconds between dashes, so one press can't use both charges
	},
}
