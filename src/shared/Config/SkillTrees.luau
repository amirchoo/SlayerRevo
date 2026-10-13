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
--     MaxStamina, StaminaRegen (per second), MaxMana, ManaRegen (per second), Damage
--     (fraction, every weapon).
--   Weapon: Damage, LightDamage, HeavyDamage (fractions), StaminaCost, LightStaminaCost,
--     HeavyStaminaCost (fractions, negative = cheaper), BlockAmount, ParryWindow, and each
--     weapon's own: SpinDuration (s, sword), ChargeSpeed (greatsword), QuakeRadius (mace, hammer),
--     LungeDistance (spear), HookReach (scythe), FlurryHits (extra stabs, rapier), RushDuration (s, dual blade), BleedDamage (per tick, axe), DrawSpeed (bow), ReloadSpeed (crossbow, blunderbuss), DamageRange (blunderbuss) as fractions; the
--     casters' (staff, grimoire) are listed with SkillTrees.Casters below.

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
		Icon = "Mobility",
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
		Icon = "Shield",
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
		Icon = "Vitality",
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
		Icon = "Might",
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
		Icon = "Endurance",
		Rival = "Arcana",
		Nodes = {
			{ Id = "StaminaPool", Name = "Deep Lungs", Description = "+10 max stamina.", Tier = 1, MaxRank = 5, Effects = { MaxStamina = 10 } },
			{ Id = "SecondBreath", Name = "Second Breath", Description = "Stamina refills 5/s faster.", Tier = 2, MaxRank = 3, Effects = { StaminaRegen = 5 } },
		},
	},
	{
		Id = "Arcana",
		Name = "Arcana",
		Icon = "Arcana",
		Rival = "Endurance",
		Nodes = {
			{ Id = "Wellspring", Name = "Wellspring", Description = "+15 max mana.", Tier = 1, MaxRank = 5, Effects = { MaxMana = 15 } },
			{ Id = "Flow", Name = "Flow", Description = "Mana refills 2/s faster.", Tier = 2, MaxRank = 3, Effects = { ManaRegen = 2 } },
			{ Id = "Archmage", Name = "Archmage", Description = "+40 max mana.", Tier = 3, MaxRank = 1, Effects = { MaxMana = 40 }, Requires = "Flow" },
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
	Hammer = weaponTree(
		{ Id = "Earthshaker", Name = "Earthshaker", Description = "Ground slam reaches 10% wider.", Tier = 2, MaxRank = 3, Effects = { QuakeRadius = 0.1 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "Bonecrusher", Name = "Bonecrusher", Description = "+15% combo damage, combo blows cost 20% less stamina.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.15, LightStaminaCost = -0.2 } },
		{ Id = "Cataclysm", Name = "Cataclysm", Description = "+20% ground slam damage, 20% wider.", Tier = 4, MaxRank = 1, Effects = { HeavyDamage = 0.2, QuakeRadius = 0.2 } }
	),
	Spear = weaponTree(
		{ Id = "LongLunge", Name = "Long Lunge", Description = "Lunge carries 15% further.", Tier = 2, MaxRank = 3, Effects = { LungeDistance = 0.15 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "Phalanx", Name = "Phalanx", Description = "Blocks absorb 10 more; parry window 0.05 s longer.", Tier = 4, MaxRank = 1, Effects = { BlockAmount = 10, ParryWindow = 0.05 } },
		{ Id = "Skewer", Name = "Skewer", Description = "+20% lunge damage, lunge carries 25% further.", Tier = 4, MaxRank = 1, Effects = { HeavyDamage = 0.2, LungeDistance = 0.25 } }
	),
	Scythe = weaponTree(
		{ Id = "GrimReach", Name = "Grim Reach", Description = "Reap's hook reaches 10% further.", Tier = 2, MaxRank = 3, Effects = { HookReach = 0.1 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "Harvester", Name = "Harvester", Description = "+15% reap damage in the combo, combo sweeps cost 20% less stamina.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.15, LightStaminaCost = -0.2 } },
		{ Id = "DeathsGrasp", Name = "Death's Grasp", Description = "+20% hook-and-cut damage, the hook reaches 20% further.", Tier = 4, MaxRank = 1, Effects = { HeavyDamage = 0.2, HookReach = 0.2 } }
	),
	Rapier = weaponTree(
		{ Id = "Finesse", Name = "Finesse", Description = "Flurry strikes 1 more time.", Tier = 2, MaxRank = 3, Effects = { FlurryHits = 1 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "Duelist", Name = "Duelist", Description = "+15% thrust damage, thrusts cost 20% less stamina.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.15, LightStaminaCost = -0.2 } },
		{ Id = "ThousandCuts", Name = "Thousand Cuts", Description = "Flurry strikes 2 more times, +15% flurry damage.", Tier = 4, MaxRank = 1, Effects = { FlurryHits = 2, HeavyDamage = 0.15 } }
	),
	DualBlade = weaponTree(
		{ Id = "Relentless", Name = "Relentless", Description = "Rush lasts 0.5 s longer.", Tier = 2, MaxRank = 3, Effects = { RushDuration = 0.5 } },
		{ table.clone(HEAVY_TRAINING), guardcraft() },
		{ Id = "TwinFangs", Name = "Twin Fangs", Description = "+15% combo damage, combo cuts cost 20% less stamina.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.15, LightStaminaCost = -0.2 } },
		{ Id = "Bladestorm", Name = "Bladestorm", Description = "+20% rush damage, rush lasts 1 s longer.", Tier = 4, MaxRank = 1, Effects = { HeavyDamage = 0.2, RushDuration = 1 } }
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
	Crossbow = weaponTree(
		{ Id = "SteadyHands", Name = "Steady Hands", Description = "Reload 8% faster.", Tier = 2, MaxRank = 3, Effects = { ReloadSpeed = 0.08 } },
		{ { Id = "Marksman", Name = "Marksman", Description = "+6% bolt damage.", Tier = 3, MaxRank = 3, Effects = { Damage = 0.06 } } },
		{ Id = "Piercer", Name = "Piercer", Description = "+20% bolt damage.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.2 } },
		{ Id = "Quickload", Name = "Quickload", Description = "Reload 25% faster.", Tier = 4, MaxRank = 1, Effects = { ReloadSpeed = 0.25 } }
	),
	Blunderbuss = weaponTree(
		{ Id = "QuickPowder", Name = "Quick Powder", Description = "Reload 8% faster.", Tier = 2, MaxRank = 3, Effects = { ReloadSpeed = 0.08 } },
		{ { Id = "HeavyShot", Name = "Heavy Shot", Description = "+6% pellet damage.", Tier = 3, MaxRank = 3, Effects = { Damage = 0.06 } } },
		{ Id = "PointBlank", Name = "Point Blank", Description = "+20% pellet damage.", Tier = 4, MaxRank = 1, Effects = { LightDamage = 0.2 } },
		{ Id = "LongBarrel", Name = "Long Barrel", Description = "Pellets do damage 30% further out.", Tier = 4, MaxRank = 1, Effects = { DamageRange = 0.3 } }
	),
} :: { [string]: { Node } }

-- Caster weapons (the staff, the grimoire) each have a class tree, drawn as branches growing
-- from the class node, like the General tree. Unlock the class first (until then the weapon
-- only blocks), then each element is its own branch that must be unlocked before that element
-- can be cast, with upgrades beyond. All their nodes are tier 1; the Requires chains set the
-- order. Element stats (fractions unless noted): <Element>Damage (that element's spells),
-- BurnDamage (per tick), WaterKnockback, EarthStun (seconds), ElectricRadius (thunder),
-- FaithRadius (healing burst), HealPower, ExtraHands (more homing hands, Necromancy).
export type CasterTree = {
	Class: string, -- the class node's Id
	ClassNode: Node,
	ElementUnlocks: { [string]: string }, -- element name (CombatConfig) -> the node that unlocks it
	Branches: { Branch },
	Angles: { [string]: number }, -- each branch's direction on the skill screen, by branch Id
	About: string, -- shown in the skill screen with nothing selected
}

local function elementBranch(classId: string, id: string, name: string, icon: string, unlockText: string, upgrade: Node, special: Node): Branch
	upgrade.Tier, upgrade.Requires = 1, `{id}Unlock`
	special.Tier, special.Requires = 1, upgrade.Id
	return {
		Id = id,
		Name = name,
		Icon = icon,
		Nodes = {
			{ Id = `{id}Unlock`, Name = name, Description = unlockText, Tier = 1, MaxRank = 1, Effects = {}, Requires = classId },
			upgrade,
			special,
		},
	}
end

local function arcaneBranch(classId: string): Branch
	return {
		Id = "Arcane",
		Name = "Arcane",
		Icon = "Arcane",
		Nodes = {
			{ Id = "Efficiency", Name = "Efficiency", Description = "Spells cost 6% less mana.", Tier = 1, MaxRank = 3, Effects = { StaminaCost = -0.06 }, Requires = classId },
			{ Id = "Overcharge", Name = "Overcharge", Description = "Heavy spells charge 12% faster.", Tier = 1, MaxRank = 3, Effects = { ChargeSpeed = 0.12 }, Requires = "Efficiency" },
			{ Id = "Spellweaver", Name = "Spellweaver", Description = "+8% heavy spell damage.", Tier = 1, MaxRank = 3, Effects = { HeavyDamage = 0.08 }, Requires = "Overcharge" },
		},
	}
end

SkillTrees.Casters = {
	Staff = {
		Class = "Mage",
		ClassNode = { Id = "Mage", Name = "Mage", Description = "Unlocks the Mage class: the staff can cast spells. Unlock an element next.", Tier = 1, MaxRank = 1, Effects = {} },
		ElementUnlocks = { Fire = "FireUnlock", Water = "WaterUnlock", Earth = "EarthUnlock", Electric = "ElectricUnlock" },
		Branches = {
			elementBranch("Mage", "Fire", "Pyromancy", "Fire", "Unlocks Fire: missiles, and a slam that sends a burning wall of flame.",
				{ Id = "Inferno", Name = "Inferno", Description = "+10% Fire damage.", Tier = 1, MaxRank = 3, Effects = { FireDamage = 0.1 } },
				{ Id = "Scorch", Name = "Scorch", Description = "Burns deal 1 more damage per tick.", Tier = 1, MaxRank = 2, Effects = { BurnDamage = 1 } }),
			elementBranch("Mage", "Water", "Hydromancy", "Water", "Unlocks Water: slowing missiles, and a torrent that knocks back.",
				{ Id = "Torrent", Name = "Torrent", Description = "+10% Water damage.", Tier = 1, MaxRank = 3, Effects = { WaterDamage = 0.1 } },
				{ Id = "Undertow", Name = "Undertow", Description = "Water knocks back 25% harder.", Tier = 1, MaxRank = 2, Effects = { WaterKnockback = 0.25 } }),
			elementBranch("Mage", "Earth", "Geomancy", "Earth", "Unlocks Earth: heavy rocks, and a thrown boulder that stuns.",
				{ Id = "Bedrock", Name = "Bedrock", Description = "+10% Earth damage.", Tier = 1, MaxRank = 3, Effects = { EarthDamage = 0.1 } },
				{ Id = "Tremor", Name = "Tremor", Description = "The boulder stuns 0.2 s longer.", Tier = 1, MaxRank = 2, Effects = { EarthStun = 0.2 } }),
			elementBranch("Mage", "Electric", "Electromancy", "Electric", "Unlocks Lightning: chaining bolts, and thunder that slows.",
				{ Id = "Storm", Name = "Storm", Description = "+10% Lightning damage.", Tier = 1, MaxRank = 3, Effects = { ElectricDamage = 0.1 } },
				{ Id = "Overload", Name = "Overload", Description = "Thunder strikes 15% wider.", Tier = 1, MaxRank = 2, Effects = { ElectricRadius = 0.15 } }),
			arcaneBranch("Mage"),
		},
		Angles = { Fire = -60, Water = -30, Earth = 0, Electric = 30, Arcane = 60 },
		About = "The staff's magic. Unlock the Mage class (the root) to cast at all, then unlock each element's branch to use that element, and grow its upgrades.",
	},
	Grimoire = {
		Class = "Occultist",
		ClassNode = { Id = "Occultist", Name = "Occultist", Description = "Unlocks the Occultist class: the grimoire can cast spells. Unlock a school next.", Tier = 1, MaxRank = 1, Effects = {} },
		ElementUnlocks = { Necromancy = "NecromancyUnlock", Faith = "FaithUnlock" },
		Branches = {
			elementBranch("Occultist", "Necromancy", "Necromancy", "Necromancy", "Unlocks Necromancy: grasping undead hands, and a swarm of them that hunts down enemies.",
				{ Id = "GraveStrength", Name = "Grave Strength", Description = "+10% Necromancy damage.", Tier = 1, MaxRank = 3, Effects = { NecromancyDamage = 0.1 } },
				{ Id = "Horde", Name = "Horde", Description = "The charged spell looses 1 more hand.", Tier = 1, MaxRank = 2, Effects = { ExtraHands = 1 } }),
			elementBranch("Occultist", "Faith", "Faith", "Faith", "Unlocks Faith: missiles that heal allies, and a healing burst.",
				{ Id = "Devotion", Name = "Devotion", Description = "Faith heals 10% more.", Tier = 1, MaxRank = 3, Effects = { HealPower = 0.1 } },
				{ Id = "Sanctuary", Name = "Sanctuary", Description = "The healing burst reaches 15% further.", Tier = 1, MaxRank = 2, Effects = { FaithRadius = 0.15 } }),
			arcaneBranch("Occultist"),
		},
		Angles = { Necromancy = -40, Faith = 40, Arcane = 0 },
		About = "The grimoire's magic. Unlock the Occultist class (the root) to cast at all, then unlock Necromancy or Faith to use it, and grow its upgrades.",
	},
} :: { [string]: CasterTree }

-- Each caster's nodes as one list (for the rules), its class first.
for weapon, caster in SkillTrees.Casters do
	local nodes: { Node } = { caster.ClassNode }
	for _, branch in caster.Branches do
		for _, node in branch.Nodes do
			table.insert(nodes, node)
		end
	end
	SkillTrees.Weapons[weapon] = nodes
end

-- Weapons with no tree of their own use another's (points spent there count for both).
SkillTrees.SharedTrees = {
	Emberfang = "Sword",
} :: { [string]: string }

-- Tabs in the skill screen, in order ("General" first, then each weapon).
SkillTrees.WeaponOrder = { "Sword", "Rapier", "DualBlade", "Greatsword", "Axe", "Mace", "Hammer", "Spear", "Scythe", "Bow", "Crossbow", "Blunderbuss", "Staff", "Grimoire" }

return SkillTrees
