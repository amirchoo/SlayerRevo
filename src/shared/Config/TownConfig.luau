--!strict
-- Beginning Town's layout (built by server TownBuilder), centered on the world origin inside
-- the hub safe zone. North (-Z) is the arch out to the hunting grounds.
-- Positions are X/Z on the ground; Facing is the way a building's front door (or a prop's
-- front) points. A building with an Asset uses that model from ServerStorage.TownAssets
-- (assets/town) when it's there (at its Scale, or fitted to its Size), and is part-built
-- otherwise. Homes and shops all use the House_1 model; Walls and Roof recolor it.
-- Props use their model from TownAssets when there is one (see TownBuilder's PROP_MODELS).
-- NPCs stand where NpcConfig puts them (in front of their buildings).
--
-- Districts: plaza and knight statue in the middle, with the bell tower off its north-east
-- corner; forge row and training yard (north-west); market lane and stable (north-east); farm
-- and windmill (south-west); tavern yard with the cooking campfire (south-east); the Hunters'
-- Guild and its trophy board at the end of the south road; watchtowers either side of the arch.
-- Decor is the small scenery between it all (bushes, planters, washing lines, flags, clutter).

export type Building = {
	Name: string,
	Kind: "house" | "forge" | "stall" | "hall" | "watchtower" | "belltower" | "windmill",
	Position: Vector2,
	Facing: Vector2,
	Size: Vector3, -- width, wall height (per story), depth: the footprint (and part-built size)
	Scale: number?, -- the model's Scale (as in Studio's Properties); otherwise fitted to Size
	Stories: number?, -- default 1
	Roof: Color3?,
	Walls: Color3?,
	Sign: string?, -- text on a board over the door
	Chimney: boolean?, -- smoke rises from it (from the model's highest point, for an Asset)
	Awning: Color3?, -- stalls
	Asset: string?,
}

export type Prop = {
	Kind: "bench" | "barrel" | "crate" | "anvil" | "well" | "flowers" | "cart" | "hay" | "questboard" | "signpost"
		| "dummy" | "target" | "rack" | "campfire" | "table" | "itembox" | "stable" | "supplies" | "tent"
		| "crops" | "pond" | "trophies" | "bush" | "planter" | "laundry" | "flag" | "woodpile" | "sacks",
	Position: Vector2,
	Facing: Vector2?,
	Text: string?, -- signposts
	Scale: number?, -- model props: times the model's own size
	Size: Vector2?, -- crops: the bed size; pond: X is its diameter
	Color: Color3?, -- model props: recolors colored cloth (stall canopies); flags: the cloth
}

local ROOF_RED = Color3.fromRGB(150, 60, 45)
local ROOF_SLATE = Color3.fromRGB(70, 80, 110)
local ROOF_BROWN = Color3.fromRGB(110, 75, 45)
local ROOF_GREEN = Color3.fromRGB(70, 100, 60)
local ROOF_TEAL = Color3.fromRGB(50, 110, 120)
local ROOF_GOLD = Color3.fromRGB(175, 125, 50)

local WALL_CREAM = Color3.fromRGB(235, 225, 200)
local WALL_BUTTER = Color3.fromRGB(240, 215, 150)
local WALL_ROSE = Color3.fromRGB(225, 180, 165)
local WALL_SAGE = Color3.fromRGB(190, 205, 170)
local WALL_SKY = Color3.fromRGB(185, 205, 220)
local WALL_WHITE = Color3.fromRGB(245, 245, 240)
local WALL_STONE = Color3.fromRGB(185, 180, 170)

local TownConfig = {}

TownConfig.Name = "Beginning Town"

-- Houses use the House_1 model at this Scale (about 19 wide, 24 deep, 30 tall); a few use the
-- smaller Houses_SecondAge_1_Level2 model instead (fitted to the same footprint), for variety.
local HOUSE = 9
local HOUSE_SIZE = Vector3.new(20, 10, 24)
local COTTAGE = "Houses_SecondAge_1_Level2"
local FLAG_GREEN = Color3.fromRGB(70, 110, 60)
local FLAG_RED = Color3.fromRGB(160, 50, 45)
local FLAG_BLUE = Color3.fromRGB(50, 80, 150)
local FLAG_GOLD = Color3.fromRGB(200, 150, 50)

TownConfig.PlazaSize = 72
-- The knight statue in the plaza's middle (assets/town/KnightStatue, plain Parts made by
-- tools/box_glb.py), facing the spawn to the south.
TownConfig.PlazaStatue = { Asset = "KnightStatue", Scale = 1.2, Facing = Vector2.new(0, 1) }
TownConfig.Spawn = Vector2.new(0, 16)
TownConfig.RoadWidth = 14
TownConfig.EdgeHalfSize = 140 -- the fence ring: a square this far from the center on each side
TownConfig.FenceGap = 20 -- openings in the fence where roads leave town
TownConfig.LampSpacing = 20

-- Cobblestone roads (from, to), and the dirt path past the arch to the hunting grounds.
TownConfig.Roads = {
	{ From = Vector2.new(0, -36), To = Vector2.new(0, -140) }, -- north, to the arch
	{ From = Vector2.new(0, 36), To = Vector2.new(0, 100) }, -- south, to the guild hall
	{ From = Vector2.new(36, 0), To = Vector2.new(140, 0) }, -- east
	{ From = Vector2.new(-36, 0), To = Vector2.new(-140, 0) }, -- west
}
TownConfig.Trail = { From = Vector2.new(0, -140), To = Vector2.new(0, -215) }

TownConfig.Arch = { Position = Vector2.new(0, -140), Width = 20, Inward = "Hunting Grounds" }

TownConfig.Buildings = {
	-- West road: the forge row.
	{ Name = "Blacksmith", Kind = "forge", Position = Vector2.new(-62, -22), Facing = Vector2.new(0, 1), Size = Vector3.new(26, 12, 20), Roof = ROOF_SLATE, Sign = "Blacksmith", Chimney = true, Asset = "Blacksmith" },
	{ Name = "Armorer", Kind = "house", Position = Vector2.new(-100, -24), Facing = Vector2.new(0, 1), Size = HOUSE_SIZE, Scale = HOUSE, Roof = ROOF_BROWN, Walls = WALL_STONE, Sign = "Armorer", Asset = "House_1" },
	{ Name = "House", Kind = "house", Position = Vector2.new(-62, 24), Facing = Vector2.new(0, -1), Size = HOUSE_SIZE, Roof = ROOF_RED, Walls = WALL_CREAM, Asset = COTTAGE },
	{ Name = "House", Kind = "house", Position = Vector2.new(-100, 24), Facing = Vector2.new(0, -1), Size = HOUSE_SIZE, Scale = HOUSE, Roof = ROOF_TEAL, Walls = WALL_SKY, Chimney = true, Asset = "House_1" },
	-- East road: the inn and shops.
	{ Name = "The Sleeping Boar", Kind = "house", Position = Vector2.new(62, -26), Facing = Vector2.new(0, 1), Size = Vector3.new(23, 10, 28), Scale = 10.5, Roof = ROOF_RED, Walls = WALL_BUTTER, Sign = "The Sleeping Boar", Chimney = true, Asset = "House_1" },
	{ Name = "House", Kind = "house", Position = Vector2.new(100, -24), Facing = Vector2.new(0, 1), Size = HOUSE_SIZE, Roof = ROOF_GREEN, Walls = WALL_SAGE, Asset = COTTAGE },
	{ Name = "Item Shop", Kind = "stall", Position = Vector2.new(58, 23), Facing = Vector2.new(0, -1), Size = Vector3.new(17, 9, 21), Scale = 8, Awning = Color3.fromRGB(50, 110, 160), Roof = Color3.fromRGB(50, 110, 160), Walls = WALL_WHITE, Sign = "Item Shop", Asset = "House_1" },
	{ Name = "Provisions", Kind = "stall", Position = Vector2.new(90, 23), Facing = Vector2.new(0, -1), Size = Vector3.new(17, 9, 21), Scale = 8, Awning = Color3.fromRGB(170, 120, 50), Roof = ROOF_GOLD, Walls = WALL_CREAM, Sign = "Provisions", Asset = "House_1" },
	{ Name = "House", Kind = "house", Position = Vector2.new(122, 24), Facing = Vector2.new(0, -1), Size = HOUSE_SIZE, Scale = HOUSE, Roof = ROOF_SLATE, Walls = WALL_ROSE, Chimney = true, Asset = "House_1" },
	-- North road, toward the arch.
	{ Name = "House", Kind = "house", Position = Vector2.new(-24, -66), Facing = Vector2.new(1, 0), Size = HOUSE_SIZE, Scale = HOUSE, Roof = ROOF_GOLD, Walls = WALL_ROSE, Chimney = true, Asset = "House_1" },
	{ Name = "House", Kind = "house", Position = Vector2.new(-24, -104), Facing = Vector2.new(1, 0), Size = HOUSE_SIZE, Roof = ROOF_SLATE, Walls = WALL_WHITE, Asset = COTTAGE },
	{ Name = "House", Kind = "house", Position = Vector2.new(24, -66), Facing = Vector2.new(-1, 0), Size = HOUSE_SIZE, Scale = HOUSE, Roof = ROOF_RED, Walls = WALL_SAGE, Asset = "House_1" },
	{ Name = "House", Kind = "house", Position = Vector2.new(24, -104), Facing = Vector2.new(-1, 0), Size = HOUSE_SIZE, Scale = HOUSE, Roof = ROOF_BROWN, Walls = WALL_BUTTER, Chimney = true, Asset = "House_1" },
	-- South road, up to the guild.
	{ Name = "House", Kind = "house", Position = Vector2.new(-24, 64), Facing = Vector2.new(1, 0), Size = HOUSE_SIZE, Scale = HOUSE, Roof = ROOF_GREEN, Walls = WALL_CREAM, Chimney = true, Asset = "House_1" },
	{ Name = "House", Kind = "house", Position = Vector2.new(24, 64), Facing = Vector2.new(-1, 0), Size = HOUSE_SIZE, Roof = ROOF_TEAL, Walls = WALL_ROSE, Asset = COTTAGE },
	-- The Fantasy Inn model (by Quaternius), fitted to a 30-stud square; its own colors (Roof
	-- and Walls only color the part-built hall used when the model is missing).
	{ Name = "Hunters' Guild", Kind = "hall", Position = Vector2.new(0, 118), Facing = Vector2.new(0, -1), Size = Vector3.new(30, 14, 30), Roof = ROOF_GREEN, Walls = WALL_STONE, Sign = "Hunters' Guild", Asset = "FantasyInn" },
	-- Landmarks: part-built until a model of that Asset name is added to assets/town.
	{ Name = "Bell Tower", Kind = "belltower", Position = Vector2.new(46, -48), Facing = Vector2.new(-1, 1), Size = Vector3.new(9, 30, 9), Roof = ROOF_SLATE, Asset = "BellTower" },
	{ Name = "Watchtower", Kind = "watchtower", Position = Vector2.new(-26, -128), Facing = Vector2.new(0, -1), Size = Vector3.new(8, 20, 8), Roof = ROOF_BROWN, Asset = "Watchtower" },
	{ Name = "Watchtower", Kind = "watchtower", Position = Vector2.new(26, -128), Facing = Vector2.new(0, -1), Size = Vector3.new(8, 20, 8), Roof = ROOF_BROWN, Asset = "Watchtower" },
	{ Name = "Windmill", Kind = "windmill", Position = Vector2.new(-128, 108), Facing = Vector2.new(1, 0), Size = Vector3.new(10, 20, 10), Roof = ROOF_RED, Asset = "Windmill" },
} :: { Building }

TownConfig.Props = {
	-- Plaza.
	{ Kind = "bench", Position = Vector2.new(-15, -16), Facing = Vector2.new(1, 1) },
	{ Kind = "bench", Position = Vector2.new(15, -16), Facing = Vector2.new(-1, 1) },
	{ Kind = "flowers", Position = Vector2.new(-30, -30) },
	{ Kind = "flowers", Position = Vector2.new(30, -30) },
	{ Kind = "flowers", Position = Vector2.new(30, 30) },
	{ Kind = "flowers", Position = Vector2.new(-30, 30) },
	{ Kind = "itembox", Position = Vector2.new(-26, 22), Facing = Vector2.new(1, 0), Scale = 1.5 },
	{ Kind = "well", Position = Vector2.new(-22, -46) },
	-- Forge yard.
	{ Kind = "anvil", Position = Vector2.new(-44, -14), Facing = Vector2.new(1, 0) },
	{ Kind = "barrel", Position = Vector2.new(-80, -13) },
	{ Kind = "crate", Position = Vector2.new(-82, -16) },
	-- Training yard (north-west): racks, dummies, archery targets.
	{ Kind = "rack", Position = Vector2.new(-60, -48), Facing = Vector2.new(0, 1) },
	{ Kind = "rack", Position = Vector2.new(-84, -48), Facing = Vector2.new(0, 1) },
	{ Kind = "dummy", Position = Vector2.new(-54, -68), Facing = Vector2.new(0, 1), Scale = 1.3 },
	{ Kind = "dummy", Position = Vector2.new(-66, -68), Facing = Vector2.new(0, 1), Scale = 1.3 },
	{ Kind = "dummy", Position = Vector2.new(-78, -68), Facing = Vector2.new(0, 1), Scale = 1.3 },
	{ Kind = "target", Position = Vector2.new(-104, -70), Facing = Vector2.new(0, 1), Scale = 1.4 },
	{ Kind = "target", Position = Vector2.new(-114, -70), Facing = Vector2.new(0, 1), Scale = 1.4 },
	{ Kind = "target", Position = Vector2.new(-124, -70), Facing = Vector2.new(0, 1), Scale = 1.4 },
	{ Kind = "hay", Position = Vector2.new(-108, -78) },
	{ Kind = "hay", Position = Vector2.new(-120, -79) },
	{ Kind = "supplies", Position = Vector2.new(-126, -48), Facing = Vector2.new(1, 0) },
	-- Fishing pond (north-west corner).
	{ Kind = "pond", Position = Vector2.new(-92, -112), Size = Vector2.new(26, 26) },
	{ Kind = "bench", Position = Vector2.new(-70, -104), Facing = Vector2.new(-1, 0) },
	{ Kind = "bench", Position = Vector2.new(-104, -94), Facing = Vector2.new(0, -1) },
	-- Market lane (north-east): two rows of stalls facing each other, and the stable.
	{ Kind = "tent", Position = Vector2.new(60, -60), Facing = Vector2.new(0, -1), Color = Color3.fromRGB(190, 60, 55) },
	{ Kind = "tent", Position = Vector2.new(82, -60), Facing = Vector2.new(0, -1), Color = Color3.fromRGB(60, 110, 190) },
	{ Kind = "tent", Position = Vector2.new(104, -60), Facing = Vector2.new(0, -1), Color = Color3.fromRGB(70, 150, 80) },
	{ Kind = "tent", Position = Vector2.new(60, -94), Facing = Vector2.new(0, 1), Color = Color3.fromRGB(140, 80, 170) },
	{ Kind = "tent", Position = Vector2.new(82, -94), Facing = Vector2.new(0, 1), Color = Color3.fromRGB(230, 150, 40) },
	{ Kind = "tent", Position = Vector2.new(104, -94), Facing = Vector2.new(0, 1), Color = Color3.fromRGB(40, 150, 150) },
	{ Kind = "barrel", Position = Vector2.new(120, -64) },
	{ Kind = "crate", Position = Vector2.new(122, -90) },
	{ Kind = "stable", Position = Vector2.new(112, -124), Facing = Vector2.new(0, 1) },
	{ Kind = "cart", Position = Vector2.new(76, -122), Facing = Vector2.new(1, 0) },
	{ Kind = "hay", Position = Vector2.new(88, -128) },
	-- Farm (south-west).
	{ Kind = "crops", Position = Vector2.new(-70, 70), Size = Vector2.new(16, 16) },
	{ Kind = "crops", Position = Vector2.new(-92, 70), Size = Vector2.new(16, 16) },
	{ Kind = "crops", Position = Vector2.new(-114, 70), Size = Vector2.new(16, 16) },
	{ Kind = "crops", Position = Vector2.new(-70, 94), Size = Vector2.new(16, 16) },
	{ Kind = "crops", Position = Vector2.new(-92, 94), Size = Vector2.new(16, 16) },
	{ Kind = "crops", Position = Vector2.new(-114, 94), Size = Vector2.new(16, 16) },
	{ Kind = "well", Position = Vector2.new(-58, 118) },
	{ Kind = "hay", Position = Vector2.new(-80, 118) },
	{ Kind = "hay", Position = Vector2.new(-84, 121) },
	{ Kind = "barrel", Position = Vector2.new(-100, 118) },
	-- Tavern yard (south-east): the campfire, tables and benches.
	{ Kind = "campfire", Position = Vector2.new(84, 86) }, -- the cooking fire, its pot on a tripod (CookingConfig)
	{ Kind = "table", Position = Vector2.new(58, 62), Facing = Vector2.new(1, 0) },
	{ Kind = "table", Position = Vector2.new(110, 62), Facing = Vector2.new(1, 0) },
	{ Kind = "table", Position = Vector2.new(58, 110), Facing = Vector2.new(1, 0) },
	{ Kind = "table", Position = Vector2.new(110, 110), Facing = Vector2.new(1, 0) },
	{ Kind = "barrel", Position = Vector2.new(126, 84) },
	{ Kind = "barrel", Position = Vector2.new(127, 88) },
	{ Kind = "supplies", Position = Vector2.new(124, 100), Facing = Vector2.new(-1, 0) },
	-- Guild.
	{ Kind = "questboard", Position = Vector2.new(-14, 96), Facing = Vector2.new(0, -1) },
	-- The trophy board: orc heads over the top hunters by level (LeaderboardService fills it).
	{ Kind = "trophies", Position = Vector2.new(30, 94), Facing = Vector2.new(0, -1) },
	{ Kind = "flowers", Position = Vector2.new(-18, 100) },
	{ Kind = "flowers", Position = Vector2.new(18, 100) },
	-- By the arch.
	{ Kind = "hay", Position = Vector2.new(16, -146) },
	{ Kind = "hay", Position = Vector2.new(-17, -148) },
	{ Kind = "barrel", Position = Vector2.new(-14, -132) },
} :: { Prop }

-- Small scenery between the buildings, built after the Props.
TownConfig.Decor = {
	-- Flags at the plaza corners and the guild door (their cloth sways in the wind).
	{ Kind = "flag", Position = Vector2.new(-34, -34), Facing = Vector2.new(-1, -1), Color = FLAG_GREEN },
	{ Kind = "flag", Position = Vector2.new(34, -34), Facing = Vector2.new(1, -1), Color = FLAG_GOLD },
	{ Kind = "flag", Position = Vector2.new(34, 34), Facing = Vector2.new(1, 1), Color = FLAG_GREEN },
	{ Kind = "flag", Position = Vector2.new(-34, 34), Facing = Vector2.new(-1, 1), Color = FLAG_GOLD },
	{ Kind = "flag", Position = Vector2.new(-22, 108), Facing = Vector2.new(0, -1), Color = FLAG_RED },
	{ Kind = "flag", Position = Vector2.new(22, 108), Facing = Vector2.new(0, -1), Color = FLAG_BLUE },
	-- Bushes.
	{ Kind = "bush", Position = Vector2.new(-44, -30) },
	{ Kind = "bush", Position = Vector2.new(44, -30) },
	{ Kind = "bush", Position = Vector2.new(44, 30) },
	{ Kind = "bush", Position = Vector2.new(-44, 30) },
	{ Kind = "bush", Position = Vector2.new(-134, -30) },
	{ Kind = "bush", Position = Vector2.new(-134, 30) },
	{ Kind = "bush", Position = Vector2.new(134, -34) },
	{ Kind = "bush", Position = Vector2.new(-30, 136) },
	{ Kind = "bush", Position = Vector2.new(30, 136) },
	{ Kind = "bush", Position = Vector2.new(-48, -80) },
	{ Kind = "bush", Position = Vector2.new(-48, -120) },
	-- Flower planters.
	{ Kind = "planter", Position = Vector2.new(-42, -42), Facing = Vector2.new(1, -1) },
	{ Kind = "planter", Position = Vector2.new(42, 42), Facing = Vector2.new(-1, 1) },
	-- Washing lines between the houses.
	{ Kind = "laundry", Position = Vector2.new(-46, 53), Facing = Vector2.new(1, 0) },
	{ Kind = "laundry", Position = Vector2.new(46, 70), Facing = Vector2.new(1, 0) },
	-- Clutter.
	{ Kind = "woodpile", Position = Vector2.new(-82, -38), Facing = Vector2.new(0, 1) },
	{ Kind = "sacks", Position = Vector2.new(105, 32), Facing = Vector2.new(0, -1) },
	{ Kind = "sacks", Position = Vector2.new(122, -77), Facing = Vector2.new(-1, 0) },
	{ Kind = "cart", Position = Vector2.new(46, -112), Facing = Vector2.new(0, 1) },
	{ Kind = "crate", Position = Vector2.new(38, -120) },
	{ Kind = "crate", Position = Vector2.new(130, -58) },
	{ Kind = "barrel", Position = Vector2.new(-44, -52) },
	{ Kind = "barrel", Position = Vector2.new(44, 96) },
	{ Kind = "barrel", Position = Vector2.new(46, 99) },
	{ Kind = "hay", Position = Vector2.new(-50, 104) },
	{ Kind = "hay", Position = Vector2.new(-52, 108) },
} :: { Prop }

-- Where flocks of little town birds peck about (TownAmbience): they fly off when you come close.
TownConfig.BirdSpots = { Vector2.new(-18, -24), Vector2.new(20, 24), Vector2.new(-90, 112), Vector2.new(80, 62), Vector2.new(-3, 70) }

-- Trees inside the fence (fixed spots) and how many to scatter outside it.
TownConfig.Trees = {
	Vector2.new(-130, -130), Vector2.new(-58, -130), Vector2.new(-128, -45), Vector2.new(-128, -95),
	Vector2.new(50, -130), Vector2.new(128, -40), Vector2.new(130, 50), Vector2.new(-128, 45),
	Vector2.new(-128, 128), Vector2.new(-38, 130), Vector2.new(48, 128), Vector2.new(128, 128),
}
TownConfig.OutsideTrees = 0 -- the forest beyond the fence is WorldBuilder's (shared/Config/WorldConfig)
TownConfig.OutsideTreeReach = 35 -- studs past the fence the outside trees spread (to the safe zone edge)
TownConfig.TrailClearance = 30 -- no outside trees closer than this to the trail's center line

return TownConfig
