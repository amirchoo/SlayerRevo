--!strict
-- The skill trees: one General tree for the character and one per weapon. All the rules are
-- here as data (SkillMath applies them; SkillService enforces them on the server).
--
-- Skill points are shared by every tree, so nobody can max everything: you specialise.
-- * General branches each have a Rival: putting a point into a branch locks its rival
--   completely (e.g. Mobility vs Guard) until you respec.
-- * A node's Tier needs that many points already spent in its branch (General) or tree
--   (weapon), per TierPoints. Requires names a node that must be unlocked first.
-- * Exclusive names a node it can't be taken alongside (the weapon masteries are a fork).
--
-- Effects are per rank, by stat:
--   General: MaxHealth, HealthRegen (per second), DashCharges, DashRecharge (fraction off the
--     recharge time), DashIFrames (seconds), BlockCharges, BlockAmount, ParryWindow (seconds),
--     MaxStamina, StaminaRegen (per second), Damage (fraction, every weapon).
--   Weapon: Damage, LightDamage, HeavyDamage (fractions), StaminaCost, LightStaminaCost,
--     HeavyStaminaCost (fractions, negative = cheaper), BlockAmount, ParryWindow, and each
--     weapon's own: SpinDuration (s, sword), ChargeSpeed (greatsword), QuakeRadius (mace),
--     LungeDistance (spear), BleedDamage (per tick, axe), DrawSpeed (bow) as fractions.

export type Node = {
	Id: string,
	Name: string,
	Description: string,
	Tier: number,
	MaxRank: number,
	Effects: { [string]: number }, -- per rank
	Requires: string?,
	Exclusive: string?,
}

export type Branch = {
	Id: string,
	Name: string,
	Icon: string,
	Rival: string?,
	Nodes: { Node },
}

local SkillTrees = {}

-- Points that must already be spent in the branch (General) or tree (weapon) for each tier.
SkillTrees.GeneralTierPoints = { 0, 3, 5 }
SkillTrees.WeaponTierPoints = { 0, 3, 7, 10 }

SkillTrees.General = {
	{
		Id = "Mobility",
		Name = "Mobility",
		Icon = "💨",
		Rival = "Guard",
		Nodes = {
			{ Id = "FleetFoot", Name = "Fleet Foot", Description = "Dashes recharge 8% faster.", Tier = 1, MaxRank = 3, Effects = { DashRecharge = 0.08 } },
			{ Id = "ExtraDash", Name = "Extra Dash", Description = "+1 dash charge.", Tier = 2, MaxRank = 1, Effects = { DashCharges = 1 } },
			{ Id = "GhostStep", Name = "Ghost Step", Description = "Dash dodges hits for 0.05 s longer.", Tier = 3, MaxRank = 2, Effects = { DashIFrames = 0.05 }, Requires = "ExtraDash" },
		},
	},
	{
		Id = "Guard",
		Name = "Guard",
		Icon = "🛡️",
		Rival = "Mobility",
		Nodes = {
			{ Id = "Bulwark", Name = "Bulwark", Description = "Blocks absorb 5 more damage.", Tier = 1, MaxRank = 3, Effects = { BlockAmount = 5 } },
			{ Id = "ExtraGuard", Name = "Extra Guard", Description = "+1 block charge.", Tier = 2, MaxRank = 1, Effects = { BlockCharges = 1 } },
			{ Id = "Riposte", Name = "Riposte", Description = "Parry window 0.03 s longer.", Tier = 3, MaxRank = 2, Effects = { ParryWindow = 0.03 }, Requires = "ExtraGuard" },
		},
	},
	{
		Id = "Vitality",
		Name = "Vitality",
		Icon = "❤️",
		Rival = "Might",
		Nodes = {
			{ Id = "Toughness", Name = "Toughness", Description = "+15 max health.", Tier = 1, MaxRank = 5, Effects = { MaxHealth = 15 } },
			{ Id = "Recovery", Name = "Recovery", Description = "Health regenerates 3/s faster.", Tier = 2, MaxRank = 2, Effects = { HealthRegen = 3 } },
			{ Id = "Juggernaut", Name = "Juggernaut", Description = "+40 max health.", Tier = 3, MaxRank = 1, Effects = { MaxHealth = 40 }, Requires = "Recovery" },
		},
	},
	{
		Id = "Might",
		Name = "Might",
		Icon = "💪",
		Rival = "Vitality",
		Nodes = {
			{ Id = "Power", Name = "Power", Description = "+4% damage with every weapon.", Tier = 1, MaxRank = 5, Effects = { Damage = 0.04 } },
			{ Id = "Brutality", Name = "Brutality", Description = "+5% damage with every weapon.", Tier = 2, MaxRank = 2, Effects = { Damage = 0.05 } },
			{ Id = "Executioner", Name = "Executioner", Description = "+8% damage with every weapon.", Tier = 3, MaxRank = 1, Effects = { Damage = 0.08 }, Requires = "Brutality" },
		},
	},
	{
		Id = "Endurance",
		Name = "Endurance",
		Icon = "🔋",
		Nodes = {
			{ Id = "StaminaPool", Name = "Deep Lungs", Description = "+10 max stamina.", Tier = 1, MaxRank = 5, Effects = { MaxStamina = 10 } },
			{ Id = "SecondBreath", Name = "Second Breath", Description = "Stamina refills 5/s faster.", Tier = 2, MaxRank = 3, Effects = { StaminaRegen = 5 } },
		},
	},
} :: { Branch }

-- Builds a weapon tree from its signature skill, its third-tier skills, and its two masteries.
local function weaponTree(signature: Node, tier3: { Node }, masteryA: Node, masteryB: Node): { Node }
	masteryA.Tier, masteryA.MaxRank, masteryA.Exclusive = 4, 1, masteryB.Id
	masteryB.Tier, masteryB.MaxRank, masteryB.Exclusive = 4, 1, masteryA.Id
	signature.Tier = 2
	local nodes: { Node } = {
		{ Id = "Sharpness", Name = "Sharpness", Description = "+5% damage.", Tier = 1, MaxRank = 5, Effects = { Damage = 0.05 } },
		{ Id = "Efficiency", Name = "Efficiency", Description = "Attacks cost 6% less stamina.", Tier = 2, MaxRank = 3, Effects = { StaminaCost = -0.06 } },
		signature,
	}
	for _, node in tier3 do
		node.Tier = 3
		table.insert(nodes, node)
	end
	table.insert(nodes, masteryA)
	table.insert(nodes, masteryB)
	return nodes
end

local HEAVY_TRAINING: Node = { Id = "HeavyTraining", Name = "Heavy Training", Description = "+8% heavy attack damage.", Tier = 3, MaxRank = 3, Effects = { HeavyDamage = 0.08 } }
local function guardcraft(): Node
	return { Id = "Guardcraft", Name = "Guardcraft", Description = "Blocks absorb 4 more; parry window 0.02 s longer.", Tier = 3, MaxRank = 2, Effects = { BlockAmount = 4, ParryWindow = 0.02 } }
end

SkillTrees.Weapons = {
	Sword = weaponTree(
		{ Id = "Whirlwind", Name = "Whirlwind", Description = "Spin lasts 0.5 s longer.", Tier = 2, MaxRank = 3, Effects = { SpinDuration = 0.5 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "Blademaster", Name = "Blademaster", Description = "+15% combo damage, combo swings cost 20% less stamina.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.15, LightStaminaCost = -0.2 } },
		{ Id = "Cyclone", Name = "Cyclone", Description = "+20% spin damage, spin lasts 1 s longer.", Tier = 4, MaxRank = 1, Effects = { HeavyDamage = 0.2, SpinDuration = 1 } }
	),
	Greatsword = weaponTree(
		{ Id = "SwiftCharge", Name = "Swift Charge", Description = "Charge levels come 10% sooner.", Tier = 2, MaxRank = 3, Effects = { ChargeSpeed = 0.1 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "Executioner", Name = "Executioner", Description = "+25% slam damage, charge 15% faster.", Tier = 4, MaxRank = 1, Effects = { HeavyDamage = 0.25, ChargeSpeed = 0.15 } },
		{ Id = "Sweeper", Name = "Sweeper", Description = "+20% sweep damage, sweeps cost 20% less stamina.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.2, LightStaminaCost = -0.2 } }
	),
	Mace = weaponTree(
		{ Id = "Aftershock", Name = "Aftershock", Description = "Ground pound reaches 10% wider.", Tier = 2, MaxRank = 3, Effects = { QuakeRadius = 0.1 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "Crusher", Name = "Crusher", Description = "+20% ground pound damage, 20% wider.", Tier = 4, MaxRank = 1, Effects = { HeavyDamage = 0.2, QuakeRadius = 0.2 } },
		{ Id = "Brawler", Name = "Brawler", Description = "+15% combo damage, combo swings cost 20% less stamina.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.15, LightStaminaCost = -0.2 } }
	),
	Spear = weaponTree(
		{ Id = "LongLunge", Name = "Long Lunge", Description = "Lunge carries 15% further.", Tier = 2, MaxRank = 3, Effects = { LungeDistance = 0.15 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "Phalanx", Name = "Phalanx", Description = "Blocks absorb 10 more; parry window 0.05 s longer.", Tier = 4, MaxRank = 1, Effects = { BlockAmount = 10, ParryWindow = 0.05 } },
		{ Id = "Skewer", Name = "Skewer", Description = "+20% lunge damage, lunge carries 25% further.", Tier = 4, MaxRank = 1, Effects = { HeavyDamage = 0.2, LungeDistance = 0.25 } }
	),
	Axe = weaponTree(
		{ Id = "DeepCuts", Name = "Deep Cuts", Description = "Bleed deals 1 more damage per tick.", Tier = 2, MaxRank = 3, Effects = { BleedDamage = 1 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "Butcher", Name = "Butcher", Description = "Bleed deals 3 more damage per tick.", Tier = 4, MaxRank = 1, Effects = { BleedDamage = 3 } },
		{ Id = "Berserker", Name = "Berserker", Description = "+15% combo damage, +10% cleave damage.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.15, HeavyDamage = 0.1 } }
	),
	Bow = weaponTree(
		{ Id = "QuickDraw", Name = "Quick Draw", Description = "Reach full draw 10% sooner.", Tier = 2, MaxRank = 3, Effects = { DrawSpeed = 0.1 } },
		{ { Id = "HuntersFocus", Name = "Hunter's Focus", Description = "+6% arrow damage.", Tier = 3, MaxRank = 3, Effects = { Damage = 0.06 } } },
		{ Id = "Deadeye", Name = "Deadeye", Description = "+20% arrow damage.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.2 } },
		{ Id = "Rapidfire", Name = "Rapid Fire", Description = "Reach full draw 25% sooner.", Tier = 4, MaxRank = 1, Effects = { DrawSpeed = 0.25 } }
	),
} :: { [string]: { Node } }

-- Tabs in the skill screen, in order ("General" first, then each weapon).
SkillTrees.WeaponOrder = { "Sword", "Greatsword", "Axe", "Mace", "Spear", "Bow" }

return SkillTrees
