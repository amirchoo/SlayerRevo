--!strict
-- Beginning Town's layout (built by server TownBuilder), centered on the world origin inside
-- the hub safe zone. North (-Z) is the arch out to the hunting grounds.
-- Positions are X/Z on the ground; Facing is the way a building's front door (or a prop's
-- front) points. A building with an Asset uses that model from ServerStorage.TownAssets
-- (assets/town) when it's there, fitted to its footprint, and is part-built otherwise; the
-- models still to make are briefed in docs/model-brief.md.
-- NPCs stand where NpcConfig puts them (in front of their buildings).

export type Building = {
	Name: string,
	Kind: "house" | "forge" | "stall" | "hall",
	Position: Vector2,
	Facing: Vector2,
	Size: Vector3, -- width, wall height (per story), depth
	Stories: number?, -- default 1
	Roof: Color3?,
	Walls: Color3?,
	Sign: string?, -- text on a board over the door
	Chimney: boolean?,
	Awning: Color3?, -- stalls
	Asset: string?,
}

export type Prop = {
	Kind: "bench" | "barrel" | "crate" | "anvil" | "well" | "flowers" | "cart" | "hay" | "questboard" | "signpost",
	Position: Vector2,
	Facing: Vector2?,
	Text: string?, -- signposts
}

local ROOF_RED = Color3.fromRGB(150, 60, 45)
local ROOF_SLATE = Color3.fromRGB(70, 80, 110)
local ROOF_BROWN = Color3.fromRGB(110, 75, 45)
local ROOF_GREEN = Color3.fromRGB(70, 100, 60)

local TownConfig = {}

TownConfig.Name = "Beginning Town"

TownConfig.PlazaSize = 56
TownConfig.FountainSize = 16
TownConfig.Spawn = Vector2.new(0, 16)
TownConfig.RoadWidth = 12
TownConfig.EdgeHalfSize = 90 -- the fence ring: a square this far from the center on each side
TownConfig.FenceGap = 18 -- openings in the fence where roads leave town
TownConfig.LampSpacing = 18

-- Cobblestone roads (from, to), and the dirt path past the arch to the hunting grounds.
TownConfig.Roads = {
	{ From = Vector2.new(0, -28), To = Vector2.new(0, -90) }, -- north, to the arch
	{ From = Vector2.new(0, 28), To = Vector2.new(0, 57) }, -- south, to the guild hall
	{ From = Vector2.new(28, 0), To = Vector2.new(90, 0) }, -- east
	{ From = Vector2.new(-28, 0), To = Vector2.new(-90, 0) }, -- west
}
TownConfig.Trail = { From = Vector2.new(0, -90), To = Vector2.new(0, -170) }

TownConfig.Arch = { Position = Vector2.new(0, -90), Width = 18, Inward = "Hunting Grounds" }

TownConfig.Buildings = {
	{ Name = "Blacksmith", Kind = "forge", Position = Vector2.new(-40, -24), Facing = Vector2.new(0, 1), Size = Vector3.new(18, 10, 14), Roof = ROOF_SLATE, Sign = "Blacksmith", Chimney = true, Asset = "Blacksmith" },
	{ Name = "Armorer", Kind = "house", Position = Vector2.new(-48, 24), Facing = Vector2.new(0, -1), Size = Vector3.new(18, 10, 14), Roof = ROOF_BROWN, Sign = "Armorer", Asset = "Armorer" },
	{ Name = "The Sleeping Boar", Kind = "house", Position = Vector2.new(46, -27), Facing = Vector2.new(0, 1), Size = Vector3.new(24, 9, 16), Stories = 2, Roof = ROOF_RED, Sign = "The Sleeping Boar", Chimney = true, Asset = "Inn" },
	{ Name = "Item Shop", Kind = "stall", Position = Vector2.new(36, 22), Facing = Vector2.new(0, -1), Size = Vector3.new(11, 9, 9), Awning = Color3.fromRGB(50, 110, 160), Sign = "Item Shop", Asset = "MarketStall" },
	{ Name = "Provisions", Kind = "stall", Position = Vector2.new(56, 22), Facing = Vector2.new(0, -1), Size = Vector3.new(11, 9, 9), Awning = Color3.fromRGB(170, 120, 50), Sign = "Provisions", Asset = "MarketStall" },
	{ Name = "Hunters' Guild", Kind = "hall", Position = Vector2.new(0, 67), Facing = Vector2.new(0, -1), Size = Vector3.new(30, 14, 20), Roof = ROOF_GREEN, Sign = "Hunters' Guild", Chimney = true, Asset = "HuntersGuild" },

	-- Homes.
	{ Name = "House", Kind = "house", Position = Vector2.new(-26, -58), Facing = Vector2.new(1, 0), Size = Vector3.new(14, 9, 12), Roof = ROOF_RED, Chimney = true, Asset = "House_1" },
	{ Name = "House", Kind = "house", Position = Vector2.new(26, -58), Facing = Vector2.new(-1, 0), Size = Vector3.new(14, 9, 12), Roof = ROOF_SLATE, Asset = "Houses_SecondAge_1_Level2" },
	{ Name = "House", Kind = "house", Position = Vector2.new(-74, -24), Facing = Vector2.new(0, 1), Size = Vector3.new(14, 9, 12), Roof = ROOF_BROWN, Asset = "Houses_SecondAge_1_Level2" },
	{ Name = "House", Kind = "house", Position = Vector2.new(-74, 26), Facing = Vector2.new(0, -1), Size = Vector3.new(16, 8, 12), Stories = 2, Roof = ROOF_SLATE, Chimney = true, Asset = "House_1" },
	{ Name = "House", Kind = "house", Position = Vector2.new(76, -24), Facing = Vector2.new(0, 1), Size = Vector3.new(16, 8, 12), Stories = 2, Roof = ROOF_RED, Asset = "House_1" },
	{ Name = "House", Kind = "house", Position = Vector2.new(76, 26), Facing = Vector2.new(0, -1), Size = Vector3.new(14, 9, 12), Roof = ROOF_BROWN, Chimney = true, Asset = "Houses_SecondAge_1_Level2" },
	{ Name = "House", Kind = "house", Position = Vector2.new(-34, 56), Facing = Vector2.new(1, 0), Size = Vector3.new(14, 9, 12), Roof = ROOF_GREEN, Asset = "Houses_SecondAge_1_Level2" },
	{ Name = "House", Kind = "house", Position = Vector2.new(34, 56), Facing = Vector2.new(-1, 0), Size = Vector3.new(14, 9, 12), Roof = ROOF_RED, Chimney = true, Asset = "House_1" },
} :: { Building }

TownConfig.Props = {
	-- Plaza.
	{ Kind = "bench", Position = Vector2.new(-12, -13), Facing = Vector2.new(1, 1) },
	{ Kind = "bench", Position = Vector2.new(12, -13), Facing = Vector2.new(-1, 1) },
	{ Kind = "flowers", Position = Vector2.new(-23, -23) },
	{ Kind = "flowers", Position = Vector2.new(23, -23) },
	{ Kind = "flowers", Position = Vector2.new(23, 23) },
	{ Kind = "flowers", Position = Vector2.new(-23, 23) },
	{ Kind = "signpost", Position = Vector2.new(3, 10.5), Facing = Vector2.new(0, 1), Text = "Start here: talk to Elder Maren" },
	-- Forge yard.
	{ Kind = "anvil", Position = Vector2.new(-33, -13), Facing = Vector2.new(1, 0) },
	{ Kind = "barrel", Position = Vector2.new(-30, -15) },
	{ Kind = "crate", Position = Vector2.new(-52, -13) },
	-- Inn.
	{ Kind = "barrel", Position = Vector2.new(33, -16) },
	{ Kind = "barrel", Position = Vector2.new(34.5, -13.5) },
	{ Kind = "crate", Position = Vector2.new(60, -15) },
	{ Kind = "crate", Position = Vector2.new(61.5, -12.5) },
	{ Kind = "bench", Position = Vector2.new(38, -14), Facing = Vector2.new(0, 1) },
	-- Market.
	{ Kind = "cart", Position = Vector2.new(68, 13), Facing = Vector2.new(-1, 0) },
	{ Kind = "crate", Position = Vector2.new(46, 26) },
	{ Kind = "barrel", Position = Vector2.new(45, 22) },
	-- Guild.
	{ Kind = "questboard", Position = Vector2.new(-10, 52), Facing = Vector2.new(0, -1) },
	{ Kind = "flowers", Position = Vector2.new(-16, 55) },
	{ Kind = "flowers", Position = Vector2.new(16, 55) },
	-- Around town.
	{ Kind = "well", Position = Vector2.new(-17, -40) },
	{ Kind = "hay", Position = Vector2.new(14, -98) },
	{ Kind = "hay", Position = Vector2.new(-15, -100) },
	{ Kind = "barrel", Position = Vector2.new(-12, -84) },
	{ Kind = "crate", Position = Vector2.new(-58, 9) },
} :: { Prop }

-- Trees inside the fence (fixed spots) and how many to scatter outside it.
TownConfig.Trees = {
	Vector2.new(-82, -82), Vector2.new(82, -82), Vector2.new(-82, 82), Vector2.new(82, 82),
	Vector2.new(-60, -60), Vector2.new(60, -60), Vector2.new(-60, 70), Vector2.new(60, 70),
	Vector2.new(-80, -50), Vector2.new(80, -52), Vector2.new(-20, 82), Vector2.new(22, 82),
}
TownConfig.OutsideTrees = 70
TownConfig.OutsideTreeReach = 75 -- studs past the fence the outside trees spread
TownConfig.TrailClearance = 30 -- no outside trees closer than this to the trail's center line

return TownConfig
