--!strict
-- Wildlife: animals that roam the land in herds and never fight back. Hit one and it (and its
-- herd) runs from you; kill it and it drops its Drops on the ground for you to pick up
-- (LootService). AnimalService runs them; the client animates them (AnimalAnimator).
-- The town keeps a few tame ones too (TownPens): they wander their pen and can't be hurt.
-- Models: assets/animals (made from all-box GLBs by tools/box_glb.py), rigged at spawn from
-- their Limbs.

export type Drop = {
	Item: string, -- a MaterialConfig item Id
	Chance: number, -- 0..1
	Min: number,
	Max: number,
}

-- A part of the model that moves on its own (a sub-Model or Part of that name, or several
-- Parts). Swing: how the client animates it:
--   Leg: swings forward and back as it walks; legs with Phase 0.5 swing opposite those at 0.
--   Head: bobs as it walks; while standing it grazes (cow) or pecks (chicken) now and then.
--   Wing: flaps while it runs (Side: 1 for the right wing, -1 for the left).
--   Tail: swishes side to side.
export type Limb = {
	Name: string,
	Parts: { string }?, -- several top-level Parts moving together (the first is the limb's name); default { Name }
	Swing: string,
	Phase: number?,
	Side: number?,
	Upright: boolean?, -- a tail held up (the cat's): it turns at its bottom, not its top
}

-- While standing, the head dips to graze (or peck) now and then: Pitch radians down
-- (negative), held Time seconds (min, max), every Gap seconds (min, max).
export type Graze = { Pitch: number, Time: { number }, Gap: { number } }

-- Now and then the animal makes its Sound (a Sounds name), every Gap seconds (min, max),
-- heard by players near it.
export type Call = { Sound: string, Gap: { number } }

-- Where an animal's herds live: Count herds of Min..Max animals, each around a home somewhere
-- in Area (X/Z), never within SafeMargin studs of the safe zone.
export type Herd = {
	Count: number,
	Min: number,
	Max: number,
	Area: { Min: Vector2, Max: Vector2 },
	SafeMargin: number,
	HomeSpacing: number, -- studs between herd homes
	Spread: number, -- studs the herd keeps around its home's moving centre
}

export type AnimalType = {
	DisplayName: string,
	Model: string, -- in assets/animals
	Scale: number, -- the model's size (1 = as made: 1 GLB unit = 1 stud)
	MaxHealth: number,
	WalkSpeed: number, -- wandering
	FleeSpeed: number, -- running from whoever hurt it (players walk at 16)
	FleeTime: number, -- seconds it keeps running after the last hit
	Skittish: number, -- 0..1: how much it zig-zags while fleeing
	RoamRadius: number, -- studs from home it wanders
	RoamPause: { number }, -- min, max seconds standing between wanders
	RespawnDelay: number, -- seconds after dying before a new one joins its herd
	XP: number,
	Drops: { Drop },
	Limbs: { Limb },
	Graze: Graze,
	Call: Call?,
	Herd: Herd,
}

-- Tame animals in town: Count of Type wandering inside the pen (X/Z corners Min..Max).
-- They have no health, so nothing can hurt them (or lock on to them).
export type Pen = { Type: string, Count: number, Min: Vector2, Max: Vector2 }

local AREA = { Min = Vector2.new(-820, -820), Max = Vector2.new(820, 820) } -- like the orcs

local AnimalConfig = {}

AnimalConfig.Cow = {
	DisplayName = "Cow",
	Model = "Cow",
	Scale = 1.4, -- about shoulder height on a player
	MaxHealth = 120,
	WalkSpeed = 4,
	FleeSpeed = 13,
	FleeTime = 6,
	Skittish = 0.15,
	RoamRadius = 40,
	RoamPause = { 4, 12 },
	RespawnDelay = 60,
	XP = 5,
	Drops = {
		{ Item = "CowMeat", Chance = 1, Min = 1, Max = 2 },
	},
	Limbs = {
		{ Name = "LegFrontLeft", Swing = "Leg", Phase = 0 },
		{ Name = "LegBackRight", Swing = "Leg", Phase = 0 },
		{ Name = "LegFrontRight", Swing = "Leg", Phase = 0.5 },
		{ Name = "LegBackLeft", Swing = "Leg", Phase = 0.5 },
		{ Name = "Head", Swing = "Head" },
		{ Name = "Tail", Parts = { "Tail", "TailTuft" }, Swing = "Tail" },
	},
	Graze = { Pitch = -0.7, Time = { 2, 4 }, Gap = { 3, 9 } },
	Call = { Sound = "CowMoo", Gap = { 15, 40 } },
	Herd = {
		Count = 6,
		Min = 2,
		Max = 4,
		Area = AREA,
		SafeMargin = 40,
		HomeSpacing = 160,
		Spread = 10,
	},
} :: AnimalType

AnimalConfig.Chicken = {
	DisplayName = "Chicken",
	Model = "Chicken",
	Scale = 0.55, -- knee-high
	MaxHealth = 30,
	WalkSpeed = 3,
	FleeSpeed = 15,
	FleeTime = 5,
	Skittish = 0.6,
	RoamRadius = 25,
	RoamPause = { 1.5, 5 },
	RespawnDelay = 40,
	XP = 2,
	Drops = {
		{ Item = "ChickenMeat", Chance = 1, Min = 1, Max = 1 },
	},
	Limbs = {
		{ Name = "LegLeft", Swing = "Leg", Phase = 0 },
		{ Name = "LegRight", Swing = "Leg", Phase = 0.5 },
		{ Name = "Head", Swing = "Head" },
		{ Name = "WingLeft", Swing = "Wing", Side = -1 },
		{ Name = "WingRight", Swing = "Wing", Side = 1 },
	},
	Graze = { Pitch = -0.9, Time = { 0.12, 0.2 }, Gap = { 0.3, 2.5 } }, -- quick pecks
	Call = { Sound = "ChickenCluck", Gap = { 6, 20 } },
	Herd = {
		Count = 6,
		Min = 3,
		Max = 5,
		Area = AREA,
		SafeMargin = 30,
		HomeSpacing = 140,
		Spread = 6,
	},
} :: AnimalType

-- The town cat: only in town (no wild herds), lazing about the tavern yard.
AnimalConfig.Cat = {
	DisplayName = "Cat",
	Model = "Cat",
	Scale = 0.75,
	MaxHealth = 20,
	WalkSpeed = 3.5,
	FleeSpeed = 16,
	FleeTime = 4,
	Skittish = 0.5,
	RoamRadius = 20,
	RoamPause = { 5, 15 },
	RespawnDelay = 30,
	XP = 0,
	Drops = {},
	Limbs = {
		{ Name = "LegFrontLeft", Swing = "Leg", Phase = 0 },
		{ Name = "LegBackRight", Swing = "Leg", Phase = 0 },
		{ Name = "LegFrontRight", Swing = "Leg", Phase = 0.5 },
		{ Name = "LegBackLeft", Swing = "Leg", Phase = 0.5 },
		{ Name = "Head", Swing = "Head" },
		{ Name = "Tail", Parts = { "Tail", "TailTip" }, Swing = "Tail", Upright = true },
	},
	Graze = { Pitch = -0.35, Time = { 1.5, 3 }, Gap = { 4, 10 } }, -- sniffing about
	Herd = {
		Count = 0, -- none in the wild
		Min = 1,
		Max = 1,
		Area = AREA,
		SafeMargin = 0,
		HomeSpacing = 0,
		Spread = 6,
	},
} :: AnimalType

-- Every animal type, spawned in herds when the server starts. Each type's key (e.g. "Cow")
-- is set on its models as the "Animal" attribute, so the client can look its type up.
AnimalConfig.Types = {
	Cow = AnimalConfig.Cow,
	Chicken = AnimalConfig.Chicken,
	Cat = AnimalConfig.Cat,
} :: { [string]: AnimalType }

-- Tame animals in Beginning Town: chickens on the farm, cows by the stable, cats in the
-- tavern yard (see TownConfig for where those are).
AnimalConfig.TownPens = {
	{ Type = "Chicken", Count = 5, Min = Vector2.new(-118, 104), Max = Vector2.new(-62, 126) },
	{ Type = "Cow", Count = 2, Min = Vector2.new(96, -112), Max = Vector2.new(128, -104) },
	{ Type = "Cat", Count = 2, Min = Vector2.new(62, 68), Max = Vector2.new(106, 104) },
} :: { Pen }

AnimalConfig.AiTick = 0.25 -- seconds between each animal's decisions
AnimalConfig.HerdPanicRange = 30 -- studs: herd mates this close to a hurt animal run too
AnimalConfig.AnimateRange = 160 -- studs from the camera within which the client animates them

return AnimalConfig
