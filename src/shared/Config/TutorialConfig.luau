--!strict
-- The training camp: the tutorial every new player goes through right after the Hall of Oaths
-- (it can't be skipped), in Beginning Town's training yard. Drill Master Hode (NpcConfig)
-- runs it: a short cutscene, then one drill at a time, each taught for the weapon the player
-- chose (Weapons below), and each finished only when the server sees it done. No rewards.
-- Talking to Hode again runs the drills again any time, with the weapon in hand (or the
-- starter weapon, if the one in hand has no lesson here); a replay can be left early.
-- Run by server TutorialService and client TutorialClient.
--
-- Text can use {Attack}, {Block}, {Dash}, {Lock} and {Skills} (the control for it on the
-- player's keyboard, controller or touch screen; see Keys) and {Weapon}.

local CombatConfig = require(script.Parent.CombatConfig)
local EnemyConfig = require(script.Parent.EnemyConfig)

export type Step = {
	Line: string, -- what Hode says as the step starts
	Objective: string, -- what to do, shown under it
	Goal: number?, -- how many times (default 1)
}

export type Lesson = {
	Light: string, -- Hode's line for the Light step (how the combo works)
	Heavy: string, -- and for the Heavy step
	LightGoal: number?, -- hits to land (default Steps.Light.Goal)
	Caster: boolean?, -- casters unlock their magic in the skill tree first (CasterOrder)
}

export type Station = { Stand: Vector2, Facing: Vector2 }

local TutorialConfig = {}

-- The steps, in order, for most weapons; casters (the staff) unlock their class and an element
-- in the skill tree before they can cast at all, so their skill steps come first.
TutorialConfig.Order = { "Intro", "Light", "Heavy", "LockOn", "Dodge", "Block", "Parry", "SkillsOpen", "SkillsSpend", "Spar" }
TutorialConfig.CasterOrder = { "Intro", "SkillsOpen", "SkillsSpend", "Light", "Heavy", "LockOn", "Dodge", "Block", "Parry", "Spar" }

TutorialConfig.Steps = {
	Intro = { Line = "", Objective = "" }, -- the cutscene (Cutscene below)
	Light = { Line = "", Objective = "Hit the training dummy ({Attack})", Goal = 6 },
	Heavy = { Line = "", Objective = "Land heavy attacks on the dummy (hold {Attack})", Goal = 2 },
	LockOn = {
		Line = "Out there, things move. Lock on and you'll never lose sight of them: you'll keep facing your target, and so will every swing.",
		Objective = "Lock on to the sparring orc ({Lock})",
	},
	Dodge = {
		Line = "Watch him. When he glows red, a swing is coming. Dash through it: for a split second, nothing can touch you.",
		Objective = "Dodge his attacks with a dash ({Dash})",
		Goal = 2,
	},
	Block = {
		Line = "You won't always have a dash ready. Raise your guard and take the hit on your weapon. Each block spends a charge, and they come back after a few seconds.",
		Objective = "Block his attacks (hold {Block})",
		Goal = 2,
	},
	Parry = {
		Line = "Now the real trick. Raise your guard just before the claw lands, not early. A parry takes no damage, costs no charge, and leaves him reeling. {ParryTip}",
		Objective = "Parry his attacks (press {Block} just before the hit)",
		Goal = 3,
	},
	SkillsOpen = {
		Line = "Strength isn't only in the arm. Every level earns you skill points, and you start with two.",
		Objective = "Open your skill tree ({Skills})",
	},
	SkillsSpend = {
		Line = "General skills help with every weapon; your {Weapon} tree helps only that one. Changing your mind costs nothing: respec any time.",
		Objective = "Spend a skill point",
	},
	Spar = {
		Line = "Enough drills. Two orcs from the pens, real claws this time. Show me everything.",
		Objective = "Defeat the sparring orcs",
		Goal = 2,
	},
} :: { [string]: Step }

-- Casters' skill steps say what to unlock.
TutorialConfig.CasterSkills = {
	SkillsOpen = {
		Line = "A {Weapon} is just a stick until you know its magic. Open your skill tree.",
		Objective = "Open your skill tree ({Skills})",
	},
	SkillsSpend = {
		Line = "Unlock the class at the root, then one element: Fire, Water, Earth or Lightning. Changing your mind costs nothing: respec any time.",
		Objective = "Unlock the class and one element",
	},
} :: { [string]: Step }

-- How each weapon (ToolName) is taught. Weapons without one are taught with the player's
-- starter weapon instead.
local SWORD: Lesson = {
	Light = "Start with the basics. Click to swing: three quick cuts, and the third hits hardest. Keep clicking in rhythm to chain them.",
	Heavy = "Now hold it down. The sword spins, cutting everything around you. Each turn costs stamina; let go to stop.",
}
TutorialConfig.Weapons = {
	Sword = SWORD,
	Emberfang = SWORD, -- the sword's moves
	Rapier = {
		Light = "Click for three quick stabs; the third lunges forward. Long reach, narrow line: keep your target right in front of you.",
		Heavy = "Hold to gather a flurry, release to unleash it. The longer you hold, the more stabs, up to eight. The last one knocks back.",
	},
	DualBlade = {
		Light = "Click for a four-cut combo: right, left, a spinning sweep, then a crossing cut that lunges in. Fast hands win.",
		Heavy = "Hold to gather yourself, then rush wherever you walk, slashing all around. Every hit costs stamina; let go to stop.",
	},
	Greatsword = {
		Light = "Click for wide sweeps. The third spins all the way round and knocks back. You walk slowly with it out, so let it come to them.",
		Heavy = "Hold to charge a slam with your feet planted, release to bring it down. Hold longer for more damage; past halfway, it knocks back too.",
		LightGoal = 4,
	},
	Axe = {
		Light = "Click for hard chops. Nothing fancy: an axe does its talking up close.",
		Heavy = "Hold to wind up a leaping cleave, release to jump in. Hold longer to leap further and hit harder. The cleave makes them bleed.",
	},
	Mace = {
		Light = "Click for a three-hit combo. Land the third and they're stunned.",
		Heavy = "Hold to raise the mace, release to pound the ground and hit everything around you. Longer charge, bigger quake.",
	},
	Hammer = {
		Light = "Click: an overhead pound, a wide sweep, then a crushing step that knocks them flat. It's slow. Pick your moment.",
		Heavy = "Hold to raise it high (the ring shows how far it'll reach), release to slam. Hold longer to throw them further.",
		LightGoal = 4,
	},
	Spear = {
		Light = "Click for quick thrusts. Your reach is your defense: hit them from where they can't hit you.",
		Heavy = "Hold to draw back, release to lunge through everything in a line. Hold longer to lunge further.",
	},
	Scythe = {
		Light = "Click: a wide reap, a full spin, then an overhead crescent that knocks back. Every swing cuts all around you.",
		Heavy = "Hold once and it does the rest: the hook catches what's ahead, drags it in, and cuts it away. Letting go won't stop it.",
	},
	Staff = {
		Light = "Click to cast a missile at what you're aiming at, or at your lock-on target. Spells cost mana, not stamina; watch the blue bar.",
		Heavy = "Hold to charge a stronger spell, release to cast it. Every element's is different. Try it.",
		LightGoal = 4,
		Caster = true,
	},
} :: { [string]: Lesson }

-- The parry tip in the Parry step's line, by the weapon's parry window (CombatConfig).
TutorialConfig.ParryTips = {
	{ Min = 0.27, Text = "Your {Weapon} gives you a generous window. Use it." },
	{ Min = 0.2, Text = "Your {Weapon}'s window is fair, but don't guess." },
	{ Min = 0, Text = "Your {Weapon} is heavy: its window is tight. Wait for it." },
}

function TutorialConfig.parryWindow(weapon: string): number
	local config = (CombatConfig :: any)[weapon]
	if typeof(config) ~= "table" then
		return 0.2
	end
	if typeof(config.Block) == "table" and typeof(config.Block.ParryWindow) == "number" then
		return config.Block.ParryWindow
	end
	return if typeof(config.ParryWindow) == "number" then config.ParryWindow else 0.2
end

function TutorialConfig.parryTip(weapon: string): string
	local window = TutorialConfig.parryWindow(weapon)
	for _, tip in TutorialConfig.ParryTips do
		if window >= tip.Min then
			return tip.Text
		end
	end
	return ""
end

-- The steps for `weapon`, and the Step for each (with its lesson's lines filled in).
function TutorialConfig.order(weapon: string): { string }
	local lesson = TutorialConfig.Weapons[weapon]
	return if lesson and lesson.Caster then TutorialConfig.CasterOrder else TutorialConfig.Order
end

function TutorialConfig.step(id: string, weapon: string): Step
	local base = TutorialConfig.Steps[id]
	local lesson = TutorialConfig.Weapons[weapon]
	if lesson and lesson.Caster and TutorialConfig.CasterSkills[id] then
		base = TutorialConfig.CasterSkills[id]
	end
	local step = table.clone(base)
	if lesson and id == "Light" then
		step.Line = lesson.Light
		step.Goal = lesson.LightGoal or base.Goal
	elseif lesson and id == "Heavy" then
		step.Line = lesson.Heavy
	end
	return step
end

-- The controls named in the text, per input.
TutorialConfig.Keys = {
	Keyboard = {
		Attack = "Left-click",
		Block = "Right-click",
		Dash = CombatConfig.Dash.Key.Name,
		Lock = CombatConfig.LockOn.Key.Name,
		Skills = "K",
	},
	Gamepad = {
		Attack = "R2 / RT",
		Block = "L2 / LT",
		Dash = "Circle / B",
		Lock = "R3",
		Skills = "D-pad Right",
	},
	Touch = {
		Attack = "the Attack button",
		Block = "the Block button",
		Dash = "the Dash button",
		Lock = "the Lock button",
		Skills = "the Skills button",
	},
}

-- The cutscene that opens the camp (first time only): the camera sweeps over the yard, then
-- finds Hode, then the player, a line from Hode on each shot.
TutorialConfig.Cutscene = {
	ShotTime = 5, -- seconds per shot
	Lines = {
		"So the Hall of Oaths sent me another one. Good. The hunting grounds are hungry.",
		"I'm Hode, drill master of Beginning Town. Every slayer here learned to fight in this yard.",
		"A {Weapon} is only as good as the hands holding it. Let's see yours.",
	},
}

TutorialConfig.Complete = {
	Banner = "Training Complete",
	Line = "Not bad, slayer. The hunting grounds are past the north arch. Come and find me whenever you want to train again.",
}

-- What the drills say back to each attack (TutorialEvent "Result").
TutorialConfig.Results = {
	Dodge = "Dodged!",
	Block = "Blocked!",
	Parry = "Parried!",
	Early = "Too early: that was a block. Raise your guard later.",
	Hit = "Hit! Watch for the red glow.",
	GuardOut = "Out of guard charges: they come back in a few seconds.",
	Miss = "Out of reach. Stay close and let him swing.",
	Leash = "Not so fast. Finish your training first.",
}

-- The sparring circles in the training yard (north-west of the plaza, TownConfig), in the open
-- ground between the yard's dummies and the pond: each player in training gets one to
-- themselves (others share the last if they're all taken), walled in while they train. The
-- player stands at Stand looking along Facing; the dummy and sparring partner stand ahead of
-- them, and the circle's middle is halfway between.
TutorialConfig.Stations = {
	{ Stand = Vector2.new(-63, -80.5), Facing = Vector2.new(0, -1) }, -- middle (-63, -85)
	{ Stand = Vector2.new(-89, -78.5), Facing = Vector2.new(0, -1) }, -- middle (-89, -83)
} :: { Station }
TutorialConfig.CircleRadius = 11 -- the ring of stakes (and the walls) round each circle's middle
TutorialConfig.TargetDistance = 9 -- the dummy and partner stand this far ahead of Stand
TutorialConfig.SparSpread = 4 -- the sparring orcs stand this far either side of that
TutorialConfig.LeashRadius = 40 -- a first-timer this far from their circle is brought back (if they get past the walls)
TutorialConfig.QuitRadius = 60 -- someone replaying who walks this far away leaves the drills

TutorialConfig.DummyHealth = 400 -- it never breaks: healed back up whenever it gets low

-- The orc in the dodge, block and parry drills: it keeps close and swings every Interval, with
-- a long, slowed-down wind-up (and a red glow) so it's easy to read; it can't be hurt.
TutorialConfig.Partner = {
	Reach = 5.5,
	Damage = 10,
	Interval = 2.4,
	Windup = { Dodge = 1, Block = 1, Parry = 0.9 },
	AnimationHit = EnemyConfig.Orc.AttackWindup, -- when the hit lands in the attack animation at normal speed
	TelegraphColor = Color3.fromRGB(255, 60, 40),
}

-- The orcs in the last drill: weaker than the real thing, and they give nothing.
TutorialConfig.SparringOrc = {
	DisplayName = "Sparring Orc",
	Level = 1,
	Model = EnemyConfig.Orc.Model,
	Color = EnemyConfig.Orc.Color,
	MaxHealth = 120,
	WalkSpeed = 9,
	AggroRange = 80,
	AttackRange = 5,
	AttackDamage = 12,
	AttackWindup = EnemyConfig.Orc.AttackWindup,
	AttackAnimation = EnemyConfig.Orc.AttackAnimation,
	AttackCooldown = 2.2,
	Animations = EnemyConfig.Orc.Animations,
	RespawnDelay = 3, -- seconds its body stays down
	XP = 0,
	Coins = 0,
	SpawnPoints = {},
} :: EnemyConfig.EnemyType

-- While training, each dash charge refills in this many seconds (instead of Dash.RechargeTime),
-- so the dodge drill never waits on the meter: as good as endless. Applied by server
-- DashService and the client's dash meter alike (dashRecharge), so they stay in step.
TutorialConfig.DashRecharge = 0.3

-- The dash recharge time for `player`: DashRecharge while they're in training, else `normal`.
function TutorialConfig.dashRecharge(player: Player, normal: number): number
	local step = player:GetAttribute("TutorialStep")
	return if typeof(step) == "string" and step ~= "" then TutorialConfig.DashRecharge else normal
end

-- During the drills the player never drops below 1 health; they're healed to full at each
-- step, and whenever they fall under this fraction.
TutorialConfig.HealBelow = 0.25

return TutorialConfig
