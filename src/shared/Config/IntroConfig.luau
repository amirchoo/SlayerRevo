--!strict
-- The new-player intro (client Intro): a cutscene telling the story so far, flown over the
-- real world, then the Hall of Oaths, where the player picks a starter class (a starter
-- weapon with its armor set; see shared/Starter). The hall is built by server ClassHall: a
-- floating temple high above the southern forest, out of sight from the ground, with one
-- statue per class (a mannequin wearing the set and holding the weapon) in a ring, facing in.
-- Shields are never part of a starter class.

export type Shot = {
	From: CFrame, -- the camera at the start of the shot...
	To: CFrame, -- ...and where it drifts to by the end
	Duration: number,
	Text: string, -- the narration shown over the shot
}

export type ClassInfo = {
	Title: string, -- the class name shown in big letters
	Order: string, -- the old Slayer Order it's named after (flavor line under the title)
	Lore: string,
	Playstyle: string,
	-- Display ratings, 0..1 (Defense isn't here: it's the armor set's real protection).
	Damage: number,
	Speed: number,
	Reach: number,
	Difficulty: number,
}

local IntroConfig = {}

-- A shot whose camera moves from `fromPos` to `toPos`, looking at `fromLook`, then `toLook`.
local function shot(fromPos: Vector3, fromLook: Vector3, toPos: Vector3, toLook: Vector3, duration: number, text: string): Shot
	return {
		From = CFrame.lookAt(fromPos, fromLook),
		To = CFrame.lookAt(toPos, toLook),
		Duration = duration,
		Text = text,
	}
end

-- The story, one shot per line. North (-Z) is the hunting grounds; the town is at the center.
IntroConfig.Shots = {
	shot(
		Vector3.new(-280, 230, -940), Vector3.new(0, 20, -420),
		Vector3.new(-150, 200, -880), Vector3.new(0, 20, -380),
		7,
		"Long ago, the Slayer Orders stood between the wilds and the world of men."
	),
	shot(
		Vector3.new(-110, 45, -800), Vector3.new(0, 40, -900),
		Vector3.new(-50, 32, -790), Vector3.new(0, 38, -900),
		7,
		"The Great Arch was the last gate they held. When it fell, so did they."
	),
	shot(
		Vector3.new(-230, 24, -430), Vector3.new(60, 14, -640),
		Vector3.new(-140, 20, -480), Vector3.new(120, 14, -660),
		7.5,
		"A hundred years on, orc warbands roam the plains, and older things stir in the mountains beyond."
	),
	shot(
		Vector3.new(-60, 32, 600), Vector3.new(0, 16, 540),
		Vector3.new(-34, 24, 575), Vector3.new(0, 16, 540),
		7,
		"The Orders are gone. But their oaths were never broken. Only forgotten."
	),
	shot(
		Vector3.new(-200, 120, 210), Vector3.new(0, 20, 0),
		Vector3.new(-110, 80, 150), Vector3.new(0, 20, 0),
		7.5,
		"At the forest's edge, Beginning Town still keeps the Slayers' last hall, and waits."
	),
	shot(
		Vector3.new(0, 70, 100), Vector3.new(0, 20, 0),
		Vector3.new(0, 36, 56), Vector3.new(0, 22, 0),
		6.5,
		"Now a new slayer has come to answer the call."
	),
} :: { Shot }

IntroConfig.Title = "SLAYER REVO"
IntroConfig.Subtitle = "The Slayers rise again."
IntroConfig.TitleTime = 4 -- seconds the title card shows
IntroConfig.FadeTime = 1 -- each fade to and from black
IntroConfig.LetterboxHeight = 0.11 -- each black bar, a fraction of the screen's height
IntroConfig.ChooseHeading = "CHOOSE YOUR PATH"
IntroConfig.OathText = "Your oath is sworn."
IntroConfig.AfterText = "Elder Maren waits in the town square."

-- The Hall of Oaths (server ClassHall builds it; client Intro points the camera at it).
IntroConfig.Hall = {
	Center = Vector3.new(0, 600, 760), -- the top of its floor, at the middle
	Radius = 36, -- studs from the middle to each statue's pedestal
	PedestalHeight = 1.6,
	-- The camera on a statue: this far in front of it, this high above its feet, looking at
	-- this height; shifted this far to its left, so the statue stands right of the info panel.
	CameraDistance = 14,
	CameraHeight = 4.2,
	LookHeight = 3,
	CameraShift = 2.4,
	FieldOfView = 40,
	TurnTime = 0.75, -- seconds to swing from one statue to the next
}

-- Armor protection (a full set) that fills the Defense bar.
IntroConfig.FullDefense = 0.3

-- Per starter weapon (shared/Starter decides which weapons are starters, and their sets).
IntroConfig.Classes = {
	Sword = {
		Title = "Swordsman",
		Order = "Heir of the Wayfarers",
		Lore = "The Wayfarers held no castle and needed none. They walked the old roads with a blade at their hip and were never caught off guard.",
		Playstyle = "A quick 3-hit combo, and a spinning heavy. Balanced and forgiving, with a generous parry: a fine first weapon.",
		Damage = 0.5,
		Speed = 0.75,
		Reach = 0.45,
		Difficulty = 0.2,
	},
	Rapier = {
		Title = "Fencer",
		Order = "Heir of the Duelists' Court",
		Lore = "The Duelists' Court settled every quarrel at the point of a blade. Their heirs strike first, and from further away than you'd think.",
		Playstyle = "Swift thrusts with long, narrow reach; hold for a flurry of stabs. The best parry of any sword, but a light guard.",
		Damage = 0.45,
		Speed = 0.85,
		Reach = 0.7,
		Difficulty = 0.55,
	},
	DualBlade = {
		Title = "Stalker",
		Order = "Heir of the Prowlers",
		Lore = "The Prowlers hunted alone in the deep forest, wrapped in furs and never still. By the time a beast turned, they were already behind it.",
		Playstyle = "A blade in each hand: a fast 4-cut combo, and a spinning rush you steer by walking. Deadly up close, light on defense.",
		Damage = 0.55,
		Speed = 0.95,
		Reach = 0.35,
		Difficulty = 0.6,
	},
	Greatsword = {
		Title = "Berserker",
		Order = "Heir of the Warhide Clans",
		Lore = "The Warhide clans wore the skins of what they slew, and swung steel taller than a man. Nothing they hit got up again.",
		Playstyle = "Slow, wide sweeps, and a charged slam that hits harder than almost anything. Commit to every swing: the parry window is tiny.",
		Damage = 0.95,
		Speed = 0.25,
		Reach = 0.65,
		Difficulty = 0.65,
	},
	Axe = {
		Title = "Ravager",
		Order = "Heir of the Woodcutters",
		Lore = "Woodcutters first, Slayers after: when the beasts came for the forest villages, they answered with the axes in their hands.",
		Playstyle = "Hard chops, and a leaping cleave that leaves enemies bleeding. Aggressive, with high damage.",
		Damage = 0.8,
		Speed = 0.5,
		Reach = 0.45,
		Difficulty = 0.45,
	},
	Mace = {
		Title = "Sentinel",
		Order = "Heir of the Wardens",
		Lore = "The Wardens kept the gates of every Slayer hall. Whatever came at them never stayed on its feet for long.",
		Playstyle = "Heavy blows, and every third hit of the combo stuns. Hold for a ground pound. Steady and hard to rattle.",
		Damage = 0.65,
		Speed = 0.5,
		Reach = 0.4,
		Difficulty = 0.35,
	},
	Hammer = {
		Title = "Juggernaut",
		Order = "Heir of the Vanguard",
		Lore = "The Vanguard marched at the front of every hunt, in plate so thick that claws and arrows broke on it.",
		Playstyle = "A huge warhammer: crushing pounds and sweeps, and a charged slam that hurls enemies away. You walk slowly with it out, so your armor does the dodging.",
		Damage = 1,
		Speed = 0.15,
		Reach = 0.6,
		Difficulty = 0.7,
	},
	Spear = {
		Title = "Lancer",
		Order = "Heir of the Skirmishers",
		Lore = "The Skirmishers fought on the open plains, keeping beasts at the end of their spears and never letting them close.",
		Playstyle = "Long reach, and a piercing lunge. The easiest parry of all, but the weakest block: distance is your defense.",
		Damage = 0.5,
		Speed = 0.6,
		Reach = 0.85,
		Difficulty = 0.4,
	},
	Scythe = {
		Title = "Revenant",
		Order = "Heir of the Reapers",
		Lore = "The Reapers swore to walk among the dead to guard the living. Some say they never stopped walking.",
		Playstyle = "Wide reaps that cut all around you, and a hook that drags an enemy in for the kill. Made for fighting crowds.",
		Damage = 0.6,
		Speed = 0.45,
		Reach = 0.8,
		Difficulty = 0.6,
	},
	Staff = {
		Title = "Mage",
		Order = "Heir of the Arcane Spire",
		Lore = "The Apprentices of the Arcane Spire studied the elements to fight what steel couldn't. The Spire is gone; its lessons aren't.",
		Playstyle = "Fire, Water, Earth or Lightning missiles; hold to charge a blast. Spells spend mana. Spend your 2 starting skill points on Mage and a first element to begin casting. Comes with a dagger for close work: block and parry with it.",
		Damage = 0.7,
		Speed = 0.5,
		Reach = 1,
		Difficulty = 0.8,
	},
} :: { [string]: ClassInfo }

return IntroConfig
