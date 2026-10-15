--!strict
-- Villagers: townsfolk who stroll Beginning Town on set routes, pausing now and then. Walk up
-- to one and they stop, turn to you and say something (a chat bubble); at their stops they
-- sometimes mutter a line to themselves. No menus, and nothing can hurt them.
-- VillagerService walks them (on the server); the client draws the bubbles (VillagerChat).
-- Routes are loops of X/Z points along the roads and yards (clear of lamps and props); a
-- point with Stop = true is where they pause.

export type Point = { At: Vector2, Stop: boolean? }

export type Villager = {
	Shirt: Color3,
	Pants: Color3,
	Skin: Color3?,
	Route: { Point },
}

local function p(x: number, z: number, stop: boolean?): Point
	return { At = Vector2.new(x, z), Stop = stop }
end

local VillagerConfig = {}

VillagerConfig.WalkSpeed = 4 -- an easy stroll (players walk at 16)
VillagerConfig.StopTime = { 3, 8 } -- seconds paused at a Stop (min, max)
VillagerConfig.TalkRange = 9 -- studs: walking this close makes them talk to you
VillagerConfig.TalkTime = 4 -- seconds they stand facing you, bubble up
VillagerConfig.TalkCooldown = 40 -- seconds before the same villager greets the same player again
VillagerConfig.MutterChance = 0.3 -- chance they say an idle line at a Stop

VillagerConfig.List = {
	-- Round the plaza.
	{ Shirt = Color3.fromRGB(170, 70, 60), Pants = Color3.fromRGB(70, 55, 45), Route = { p(-30, -14), p(-10, -30, true), p(10, -30), p(30, -12), p(28, 14, true), p(14, 30), p(-12, 30, true), p(-28, 12) } },
	{ Shirt = Color3.fromRGB(80, 120, 170), Pants = Color3.fromRGB(60, 60, 70), Route = { p(28, 14), p(14, 30, true), p(-12, 30), p(-28, 12, true), p(-30, -14), p(-10, -30), p(10, -30, true), p(30, -12) } },
	-- Along the roads (keeping to one side each way).
	{ Shirt = Color3.fromRGB(200, 170, 90), Pants = Color3.fromRGB(90, 70, 50), Route = { p(30, 3), p(56, 3, true), p(126, 3), p(126, -3, true), p(100, -3), p(30, -3) } },
	{ Shirt = Color3.fromRGB(110, 140, 90), Pants = Color3.fromRGB(70, 60, 50), Route = { p(-30, -3), p(-56, -3, true), p(-126, -3), p(-126, 3, true), p(-96, 3), p(-30, 3) } },
	{ Shirt = Color3.fromRGB(140, 90, 150), Pants = Color3.fromRGB(55, 50, 65), Route = { p(3, -40), p(3, -126, true), p(-3, -126), p(-3, -80, true), p(-3, -40) } },
	{ Shirt = Color3.fromRGB(190, 120, 80), Pants = Color3.fromRGB(80, 70, 60), Route = { p(-3, 40), p(-3, 90, true), p(3, 90), p(3, 40, true) } },
	-- The market lane, between the stalls.
	{ Shirt = Color3.fromRGB(220, 200, 160), Pants = Color3.fromRGB(100, 80, 60), Route = { p(56, -77), p(72, -77, true), p(112, -77), p(94, -77, true) } },
	-- The farmer, down the path between the crop beds.
	{ Shirt = Color3.fromRGB(150, 110, 70), Pants = Color3.fromRGB(70, 90, 120), Route = { p(-60, 82), p(-92, 82, true), p(-124, 82), p(-76, 82, true) } },
	-- Round the tavern-yard campfire.
	{ Shirt = Color3.fromRGB(120, 60, 50), Pants = Color3.fromRGB(50, 45, 40), Route = { p(66, 70), p(102, 70, true), p(102, 104), p(66, 104, true) } },
} :: { Villager }

-- What they say when you walk up.
VillagerConfig.Greetings = {
	"Morning, slayer!",
	"Mind the orcs past the arch.",
	"The cows wander off into the hills, you know.",
	"Try the campfire in the tavern yard. Nothing beats a fresh steak!",
	"The guild's always looking for new hunters.",
	"Stay safe out there.",
	"You look like you could use a hot meal.",
	"The blacksmith's been hammering since dawn.",
	"Heard the hunting grounds got rougher lately.",
	"Welcome to Beginning Town!",
	"Have you seen Bonnie? White with gray patches, usually napping by the statue.",
	"Bring back something big for the trophy board!",
	"Pet Bonnie for luck before you leave town!",
	"Bonnie's asleep by the statue again. Lucky cat.",
	"My grandad swore Bonnie was old when he was a boy.",
}

-- What they mutter at their stops.
VillagerConfig.Mutters = {
	"Lovely weather today.",
	"Now where did I put that...",
	"Hmm, need more flour.",
	"*hums a tune*",
	"Those chickens again...",
	"Busy day at the market.",
	"Here, Bonnie, Bonnie...",
}

-- At night they have other things on their mind.
VillagerConfig.NightGreetings = {
	"Out late, slayer?",
	"Careful after dark.",
	"The lamps make the town look lovely at night.",
	"Can't sleep either?",
}

return VillagerConfig
