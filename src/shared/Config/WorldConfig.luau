--!strict
-- The world around Beginning Town: the shape of the land (used by server WorldTerrain, which
-- sculpts the terrain in edit mode) and what stands on it (placed by server WorldBuilder).
-- Positions are X/Z on the ground. North (-Z) is the hunting grounds, a wide open plain made
-- for riding across; forest covers the hills on every other side of the hub; mountains rise
-- along the map edge. Dirt paths link the town's exits, the forest clearings and the plain.
-- See shared/WorldMap for the geometry helpers both sides share.

export type Clearing = {
	Name: string,
	Position: Vector2,
	Radius: number, -- kept free of trees and flattened
	Ruin: string?, -- a WorldAssets model standing in the middle
	RuinScale: number?,
	RuinFacing: Vector2?,
	Chests: { Vector2 }?, -- treasure chests, offsets from Position
}

export type Plant = {
	Model: string, -- a WorldAssets model
	Scale: { number }, -- random between these, times the model's size
	PerTree: number?, -- forest: the chance of one beside each tree
	Plain: number?, -- hunting grounds: how many to scatter
}

local WorldConfig = {}

WorldConfig.Seed = 42
WorldConfig.HalfSize = 1000 -- the land runs this far from the center on every side
WorldConfig.GroundY = 10 -- height of flat ground (the town and plain sit at about this)

-- Flat around the hub: no hills inside HubFlat (studs from the center, a square), easing
-- into the hills by HubBlend.
WorldConfig.HubFlat = 190
WorldConfig.HubBlend = 280

-- The hunting grounds: a gently rolling plain (with a feathered edge), sparse trees.
WorldConfig.HuntingGrounds = { Min = Vector2.new(-540, -840), Max = Vector2.new(540, -250), Feather = 90 }

WorldConfig.HillHeight = 28 -- forest hills rise up to about this above flat ground
WorldConfig.PlainHeight = 5 -- the plain's gentle roll
WorldConfig.Mountains = { Start = 850, Height = 120 } -- rising from Start studs out to the map edge

-- A river across the hunting grounds, ending in a small lake at each end.
WorldConfig.River = {
	Width = 18,
	Depth = 6,
	LakeRadius = 45,
	Points = {
		Vector2.new(-800, -560),
		Vector2.new(-600, -640),
		Vector2.new(-280, -575),
		Vector2.new(0, -620),
		Vector2.new(300, -700),
		Vector2.new(600, -630),
		Vector2.new(800, -690),
	},
}

-- Dirt paths (polylines). Bridges go where a path crosses the river.
WorldConfig.PathWidth = 10
WorldConfig.Paths = {
	-- The trail north from the town arch, across the plain to the great arch.
	{ Vector2.new(0, -140), Vector2.new(0, -300), Vector2.new(-30, -480), Vector2.new(0, -620), Vector2.new(40, -760), Vector2.new(0, -830) },
	-- The south forest loop, from the west gate round to the east gate.
	{ Vector2.new(-140, 0), Vector2.new(-260, 10), Vector2.new(-360, 140), Vector2.new(-300, 330), Vector2.new(-130, 470), Vector2.new(0, 500), Vector2.new(130, 470), Vector2.new(300, 330), Vector2.new(360, 140), Vector2.new(260, -10), Vector2.new(140, 0) },
	-- Out to the forest ruins, west and east.
	{ Vector2.new(-360, 140), Vector2.new(-470, 110), Vector2.new(-570, 130) },
	{ Vector2.new(360, 140), Vector2.new(470, 170), Vector2.new(570, 150) },
	-- Through the forest to the plain's west and east sides.
	{ Vector2.new(-260, 10), Vector2.new(-410, -90), Vector2.new(-500, -260), Vector2.new(-380, -470), Vector2.new(-280, -575), Vector2.new(-320, -760) },
	{ Vector2.new(260, -10), Vector2.new(420, -110), Vector2.new(500, -260), Vector2.new(420, -480), Vector2.new(300, -700), Vector2.new(330, -780) },
}

-- Clearings in the forest and on the plain, each with a ruin and treasure chests.
WorldConfig.Clearings = {
	{ Name = "Old Shrine", Position = Vector2.new(0, 540), Radius = 45, Ruin = "RuinPillars", RuinScale = 1, Chests = { Vector2.new(0, 4) } },
	{ Name = "West Ruins", Position = Vector2.new(-600, 130), Radius = 50, Ruin = "RuinWall", RuinScale = 1, RuinFacing = Vector2.new(1, 0), Chests = { Vector2.new(6, -8) } },
	{ Name = "East Ruins", Position = Vector2.new(600, 150), Radius = 50, Ruin = "RuinWall", RuinScale = 1, RuinFacing = Vector2.new(-1, 0), Chests = { Vector2.new(-6, 8) } },
	{ Name = "The Great Arch", Position = Vector2.new(0, -900), Radius = 110, Ruin = "RuinArch", RuinScale = 0.8, Chests = { Vector2.new(-30, 20), Vector2.new(35, 15) } },
	{ Name = "Fallen Columns", Position = Vector2.new(-330, -800), Radius = 45, Ruin = "RuinPillars", RuinScale = 1.2, Chests = { Vector2.new(4, -2) } },
	{ Name = "Broken Keep", Position = Vector2.new(340, -830), Radius = 50, Ruin = "RuinWall", RuinScale = 1.2, RuinFacing = Vector2.new(0, 1), Chests = { Vector2.new(0, 10) } },
	-- Small hidden spots: just a chest.
	{ Name = "Hollow", Position = Vector2.new(-200, 300), Radius = 16, Chests = { Vector2.new(0, 0) } },
	{ Name = "Hilltop", Position = Vector2.new(250, 560), Radius = 16, Chests = { Vector2.new(0, 0) } },
	{ Name = "Riverbank", Position = Vector2.new(-620, -605), Radius = 16, Chests = { Vector2.new(0, 0) } },
	{ Name = "Lone Tree", Position = Vector2.new(160, -420), Radius = 16, Chests = { Vector2.new(0, 0) } },
	{ Name = "Ridge", Position = Vector2.new(680, -300), Radius = 16, Chests = { Vector2.new(0, 0) } },
} :: { Clearing }

-- Trees: one try per Cell x Cell square (jittered); forest squares get one with ForestChance,
-- plain squares with PlainChance. No trees on paths, the river, clearings or high mountain.
WorldConfig.Trees = {
	Cell = 46,
	ForestChance = 0.85,
	PlainChance = 0.05,
	Scale = { 0.4, 0.75 }, -- of the Tree model (~38 studs tall at 1)
	MaxHeight = 70, -- studs above flat ground
	AutumnChance = 0.08,
}

-- Undergrowth in the forest (beside trees) and scattered across the plain.
WorldConfig.Undergrowth = {
	{ Model = "Bush", Scale = { 1, 1.5 }, PerTree = 0.45 },
	{ Model = "TallGrass", Scale = { 0.18, 0.26 }, PerTree = 0.25 },
	{ Model = "HogWeed", Scale = { 0.7, 1 }, PerTree = 0.12 },
	{ Model = "TallGrass", Scale = { 0.18, 0.26 }, Plain = 160 },
	{ Model = "Wildflower", Scale = { 1, 1.4 }, Plain = 260 },
	{ Model = "HogWeed", Scale = { 0.7, 1 }, Plain = 90 },
	{ Model = "PinkFlower", Scale = { 0.26, 0.32 }, Plain = 40 },
} :: { Plant }

WorldConfig.ChestScale = 1.6
WorldConfig.Rocks = { Count = 140, Radius = { 3, 9 } } -- terrain rock outcrops (sculpted with the terrain)

return WorldConfig
