--!strict
-- Townsfolk in Beginning Town: where each stands, how they look, and what they say.
-- NpcService (server) spawns them with a "Talk" prompt; Dialogue (client) shows their lines.
-- Positions are X/Z on the ground; Facing is the direction they look.
-- Action "StarterPick": after their lines, a player who hasn't picked a starter weapon is
-- offered the choice (see shared/Starter); ChosenLines replace Lines once they have.
-- Action "Training": after their lines, the drills start again (TutorialService, with the
-- weapon in hand; the player is taken into a sparring circle).

export type Npc = {
	Id: string,
	Name: string,
	Title: string,
	Position: Vector2,
	Facing: Vector2,
	Shirt: Color3,
	Pants: Color3,
	Lines: { string },
	ChosenLines: { string }?,
	Action: string?,
}

local NpcConfig = {}

NpcConfig.TalkDistance = 10 -- studs from an NPC its Talk prompt shows
NpcConfig.CloseDistance = 18 -- the dialogue closes when you walk this far away
NpcConfig.TypeSpeed = 60 -- characters per second as a line types out

NpcConfig.List = {
	{
		Id = "Guide",
		Name = "Elder Maren",
		Title = "Town Guide",
		Position = Vector2.new(9, 13),
		Facing = Vector2.new(-1, 0.4),
		Shirt = Color3.fromRGB(90, 110, 80),
		Pants = Color3.fromRGB(70, 55, 40),
		Lines = {
			"Welcome to Beginning Town, traveler. Every slayer's road starts here.",
			"Beyond the north arch lie the hunting grounds. Monsters there won't wait for you to be ready.",
			"No one walks out that gate empty-handed. Choose the weapon you'll learn first, and the armor that goes with it.",
		},
		ChosenLines = {
			"That weapon suits you. Learn its rhythm before you learn its strength.",
			"Short on coin? Greta the butcher pays for any meat you bring back from the fields.",
			"And before you go, find Bonnie by the statue. Slayers have scratched that cat's ears for luck since before my grandmother was born.",
			"When you're ready, the north arch leads to the hunting grounds. Come back alive.",
		},
		Action = "StarterPick",
	},
	{
		Id = "Blacksmith",
		Name = "Bram",
		Title = "Blacksmith",
		Position = Vector2.new(-54, -10.5),
		Facing = Vector2.new(0, 1),
		Shirt = Color3.fromRGB(60, 60, 65),
		Pants = Color3.fromRGB(50, 40, 30),
		Lines = {
			"Mind the sparks. This forge hasn't gone cold in twenty years.",
			"Bonnie sneaks in to nap by the coals every winter. Never singed a whisker. Smarter than half my customers.",
			"I've got weapons for every fighting style. Three hundred coins each.",
		},
		Action = "Shop",
	},
	{
		Id = "Armorer",
		Name = "Hilde",
		Title = "Armorer",
		Position = Vector2.new(-93, -10.5),
		Facing = Vector2.new(0, 1),
		Shirt = Color3.fromRGB(120, 85, 60),
		Pants = Color3.fromRGB(60, 50, 45),
		Lines = {
			"Leather, hide, quilted cloth: every piece you wear turns a little of a blow aside.",
			"Mind you, nothing I stitch turns a blow like Bonnie's luck. Pet her before you head out; the hunters swear by it.",
			"Full armor sets are two hundred fifty coins each.",
		},
		Action = "Shop",
	},
	{
		Id = "Innkeeper",
		Name = "Tobin",
		Title = "Innkeeper",
		Position = Vector2.new(54, -10.5),
		Facing = Vector2.new(0, 1),
		Shirt = Color3.fromRGB(150, 120, 80),
		Pants = Color3.fromRGB(70, 50, 35),
		Lines = {
			"Welcome to the Sleeping Boar! Warm stew, warm beds, and the best stories this side of the forest.",
			"Hunters swap tales here at night. Some of them are even true.",
			"The oldest one goes like this: the night the Orders marched to the Great Arch, a cat sat at the Knight's feet in the plaza. Called her Bonnie. White, with gray markings, just like ours.",
		},
	},
	{
		Id = "Merchant",
		Name = "Pip",
		Title = "Merchant",
		Position = Vector2.new(52, 10.5),
		Facing = Vector2.new(0, -1),
		Shirt = Color3.fromRGB(90, 140, 70),
		Pants = Color3.fromRGB(60, 50, 40),
		Lines = {
			"The supply cart finally made it through. Nothing fancy yet, but potions keep slayers alive.",
			"I tried selling Bonnie charms once. Nobody bought one. They all just went and petted the real cat.",
			"Health and Mana potions are stocked and ready.",
		},
		Action = "Shop",
	},
	{
		-- Runs the stall on the east road (TownConfig's "Butcher"), on the way to the tavern
		-- yard's cooking fire.
		Id = "Butcher",
		Name = "Greta",
		Title = "Butcher",
		Position = Vector2.new(88, 10.5),
		Facing = Vector2.new(0, -1),
		Shirt = Color3.fromRGB(225, 220, 205),
		Pants = Color3.fromRGB(110, 45, 40),
		Lines = {
			"Fresh meat, fair prices. Well, fair for me.",
			"The best scraps go to Bonnie, and don't you tell her otherwise. She's kept more of you alive than my steaks have.",
			"Bring me what you hunt out in the fields and I'll pay coin for it. Buying from me costs more, mind.",
		},
		Action = "Shop",
	},
	{
		Id = "GuildClerk",
		Name = "Sera",
		Title = "Guild Clerk",
		Position = Vector2.new(10, 97),
		Facing = Vector2.new(0, -1),
		Shirt = Color3.fromRGB(70, 80, 110),
		Pants = Color3.fromRGB(45, 45, 55),
		Lines = {
			"The Hunters' Guild keeps track of every beast that threatens this town.",
			"Our records go back a hundred years, and there's a cat named Bonnie in them on nearly every page. Not once does anyone mention a kitten.",
			"Check the quest board outside for open bounties, or head north to thin the hunting grounds.",
		},
	},
	{
		-- Runs the training camp in the training yard (TutorialService, TutorialConfig); the
		-- camp's lines are TutorialConfig's, these are for talking to him any other time, which
		-- runs the drills again.
		Id = "DrillMaster",
		Name = "Hode",
		Title = "Drill Master",
		Position = Vector2.new(-106, -87),
		Facing = Vector2.new(1, 0),
		Shirt = Color3.fromRGB(140, 45, 40),
		Pants = Color3.fromRGB(50, 45, 40),
		Lines = {
			"Every slayer in this town learned to fight in my yard. Some of them even listened.",
			"Blessings from a cat. In my day we called that luck, and trained anyway. ...Still. Pet her.",
			"Rusty? Say the word and we'll run the drills again, with whatever weapon you're holding.",
		},
		Action = "Training",
	},
	{
		Id = "Guard",
		Name = "Fenn",
		Title = "Gate Guard",
		Position = Vector2.new(11, -132),
		Facing = Vector2.new(0, 1),
		Shirt = Color3.fromRGB(110, 115, 125),
		Pants = Color3.fromRGB(55, 55, 60),
		Lines = {
			"Halt. Past this arch you're outside the safe zone; nothing out there cares that you're new.",
			"I ask every hunter who walks through here one thing: did you pet Bonnie? The ones who say no are the ones I worry about.",
			"Orcs roam close to the road. Further in, something worse. Keep your guard up and your stamina higher.",
		},
	},
} :: { Npc }

-- Animal NPCs with their own rigged model and animation clips (not R15 figures): PetService
-- (server) spawns each from ServerStorage.NpcModels, walks it around its Wander area and
-- picks what it's doing; PetAnimator (client) poses its bones from its clip data, swings its
-- legs while it walks, and moves its eyelids (PetEyes). Pet it (its prompt) and it plays.
-- See assets/npcs/README.md.
-- Clips: the clip data module in src/shared/PetClips (made by tools/npc_clips.py from the
-- source .glb; played by the game itself, not uploaded). States: the clip each state plays
-- (Walking has none of its own: the legs are swung on top of it).
-- Wander: walks to random spots between MinRadius and MaxRadius studs from Center, never
-- along a line that passes through an Avoid circle (the area inside MinRadius is avoided too).
-- Lids: the X rotation (radians) of the "LidL"/"LidR" bones for open, half-open and shut eyes.
-- Eyes: how open (0 shut .. 1 open) the eyes are in each state; she blinks when they're open.
-- FacingOffset: degrees the model is turned on its root, in case Import 3D turned it around.
-- Height: studs tall in its rest pose; the model is scaled to it, whatever scale it imported at
-- (its root, hip height and stride scale with it).
-- Blessing: the buff (BuffConfig) a player gets for petting it, shown in a short cutscene
-- (PetCutscene, set up in PetCutscene below).
export type PetState = "Idle" | "Walking" | "Loafing" | "Sleeping" | "Playing"
export type Circle = { Center: Vector2, Radius: number }
export type Pet = {
	Id: string,
	Name: string,
	Title: string, -- under its name (client Nameplates)
	Model: string,
	Wander: { Center: Vector2, MinRadius: number, MaxRadius: number, Avoid: { Circle } },
	WalkSpeed: number,
	FacingOffset: number,
	Height: number,
	Clips: string,
	States: { [string]: string }, -- PetState -> clip name
	Lids: { Open: number, Half: number, Shut: number },
	Eyes: { [string]: number }, -- by PetState
	Blessing: string?,
}

NpcConfig.Pets = {
	{
		-- The town cat: a white girl kitty with gray markings. The townsfolk's lines tell her
		-- lore (she's been in town as long as anyone remembers, and hunters pet her for luck).
		Id = "Bonnie",
		Name = "Bonnie",
		Title = "Town Cat",
		Model = "Bonnie",
		-- The town plaza (72 studs square, TownConfig.PlazaSize), around the knight statue.
		Wander = {
			Center = Vector2.new(0, 0),
			MinRadius = 9, -- clear of the statue
			MaxRadius = 30,
			Avoid = {
				{ Center = Vector2.new(9, 13), Radius = 3 }, -- Elder Maren
			},
		},
		WalkSpeed = 5,
		FacingOffset = 180, -- Import 3D turned her around (on top of npc_glb.py's --turn-y 180)
		Height = 2.6, -- studs, ears up and tail raised (modeled at 1.85; bigger so she's easy to spot)
		Clips = "Bonnie",
		States = { Idle = "Idle", Walking = "Idle", Loafing = "Loafing", Sleeping = "Sleeping", Playing = "Playing" },
		Lids = { Open = -1.2, Half = 0.15, Shut = 1.45 },
		Eyes = { Idle = 1, Walking = 1, Playing = 1, Loafing = 0.5, Sleeping = 0 },
		Blessing = "BonniesGrace",
	},
} :: { Pet }

-- How the pets behave (PetService). After each idle spell a pet picks what to do next by
-- these weights; loafs and naps last RestTime. Petting it (the prompt) makes it stop and
-- play for PlayTime seconds (again and again if you keep petting), facing you.
NpcConfig.PetBehaviour = {
	IdleTime = NumberRange.new(3, 8), -- seconds standing between other things
	Next = { Walking = 6, Loafing = 2, Sleeping = 1.5, Idle = 1 }, -- weights after an idle spell
	RestTime = NumberRange.new(15, 40), -- seconds loafing or sleeping before getting up
	WalkTimeout = 15, -- seconds to reach a spot before giving up on it
	StrayDistance = 8, -- studs past MaxRadius before she heads straight back into her area...
	LostDistance = 60, -- ...and this far past it, she's put back
	PlayTime = 6, -- seconds she plays after being petted
	PromptDistance = 8, -- studs her "Pet" prompt shows from
	PetCooldown = 6, -- seconds before the same player can pet her again (the cutscene's length)
	Fade = 0.6, -- seconds each clip fades into the next (PetAnimator)
	BlinkEvery = NumberRange.new(2.5, 6), -- seconds between blinks while her eyes are open
}

-- The camera when you pet a pet (client PetCutscene): it flies in to a close shot in front of
-- the pet (which turns to face you and plays), pushes in slowly while the blessing's name
-- shows between letterbox bars, then flies back. Distances are per stud of the pet's Height.
NpcConfig.PetCutscene = {
	ZoomTime = 0.8, -- seconds to fly in
	HoldTime = 3.4, -- seconds on the pet
	BackTime = 0.7, -- seconds to fly back out
	Distance = 1.9, -- in front of the pet at the start of the hold...
	EndDistance = 1.45, -- ...and at its end (a slow push in)
	Side = 0.55, -- to the pet's right, so it isn't dead-on
	Up = 0.55, -- camera height above the ground
	LookUp = 0.4, -- where it looks: the pet's head is about here
	FieldOfView = 45,
}

function NpcConfig.get(id: string): Npc?
	for _, npc in NpcConfig.List do
		if npc.Id == id then
			return npc
		end
	end
	return nil
end

return NpcConfig
