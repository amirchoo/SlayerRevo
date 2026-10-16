--!strict
-- Dungeons: a cave in the world leads into a private copy of the dungeon for whoever walks
-- in (one run per player for now; a party will share one when parties exist). DungeonService
-- builds each run's copy out past the edge of the land, far from the others, and runs it.
--
-- A run: start in the entry hall of a maze of corridors, caves and rooms, with orc patrols
-- walking their routes (they notice you when they can see you, and chase you round corners).
-- Each war room seals its gates as you walk in and drops its orcs, and opens them once
-- they're all dead; the arena's gate stays shut until every war room is cleared, then seals
-- again behind you until the boss is beaten (or everyone in it is dead). Chests open once per
-- run. Dying puts you back in the entry hall with cleared rooms still cleared (dead patrols
-- stay dead); a room you were fighting in empties and opens again (its orcs come back when
-- you walk in). Beating the boss opens a way out in the arena; the hall's way out works any
-- time. Leaving (or disconnecting) ends the run.
--
-- The layout is a grid map (Map: one string per row, north/-Z at the top), each character one
-- Cell-stud square:
--   #  rock (cave rock where it borders cave floor, cut stone elsewhere)
--   .  stone floor (built rooms and corridors)    ,  cave floor
--   +  a portcullis across the passage (each run of them is one gate, owned by the room it
--      touches); open until that room's fight starts
--   ?  a fake wall: looks like the rock next to it, but you walk through it (orcs don't)
--   S  where players arrive (and come back after dying)    E  the way out (against a wall)
--   C  a chest    O  an orc that drops in when its room's fight starts
--   A  the arena's doorway (top row): the round arena sits north of it
--   a-z  patrol waypoints (Patrols)
-- Every other floor marker (S, E, C, O, A, a-z) is floor of whichever kind is next to it.
-- Columns and rows count from 1 at the top left.

export type Room = {
	Name: string,
	From: Vector2, -- top-left cell (column, row)
	To: Vector2, -- bottom-right cell
}

export type Patrol = {
	Route: string, -- waypoint letters, walked in order and round again
	Orcs: number,
}

export type Dungeon = {
	Id: string,
	DisplayName: string,
	Recommended: string, -- shown on the entrance
	Boss: string, -- BossConfig id
	-- The cave mouth in the world (X/Z; dropped onto the ground) and which way it faces.
	Entrance: Vector2,
	EntranceFacing: Vector2,
	Map: { string },
	Cell: number, -- studs per map square
	Height: number, -- ceiling over corridors and caves (and the gates' height)
	-- Named rooms (a taller ceiling, a banner the first time you walk in). A room with O's in
	-- it is a war room: walking in seals its gates and drops its orcs, and the arena stays
	-- sealed until every war room is cleared.
	Rooms: { Room },
	RoomHeight: number,
	Patrols: { Patrol },
	-- A chest spills Shown gold coins for each member in the run, worth a random total from Min
	-- to Max (rolled for each member), picked up by walking through them.
	ChestCoins: { Min: number, Max: number, Shown: number },
	Arena: { Radius: number, Height: number },
}

local DungeonConfig = {}

-- Grimgorg's Lair: a cave in the mountains at the north-west edge of the hunting grounds.
-- The hall (bottom middle) opens three ways; the cavern in the middle loops round its rock
-- pillars to the antechamber and the arena (top). The war rooms that unseal it are in the
-- far corners: the Guard Post up the west corridor, the War Camp up the east caves.
DungeonConfig.Grimgorg = {
	Id = "Grimgorg",
	DisplayName = "Grimgorg's Lair",
	Recommended = "Lv 5-8",
	Boss = "Grimgorg",
	Entrance = Vector2.new(-480, -862),
	EntranceFacing = Vector2.new(0, 1), -- out over the plain (south)
	Map = {
		"###################AA###################",
		"###################..###################",
		"##.........########..########.........##",
		"##..O...O..####..........####..O...O..##",
		"##.........####..........####....O....##",
		"##.O.....O.####..........####.O.....O.##",
		"##.........####..........####.........##",
		"##.........####..........####.........##",
		"##.........####..........####.........##",
		"#####++########,,##..############++#####",
		"#####..########,,##..##########,,,,#####",
		"#####..########,,##..#######,,,,h,,#####",
		"#####.....#####,,,,,b,,,,,,,###,,,,#####",
		"#####....f##,,,,,,##,,,,,,,,###,,,,#####",
		"########..##,a,,,,,,,,,,,,c,###,,,#,,,##",
		"########..##,,,##,,,,###,,,,###,,,?,C,##",
		"########....,,,##,,,,###,,,,,,,,,,#,,,##",
		"########....,,,,,,,,,###,,,,,,,,,,#,,,##",
		"#...####..##,,,,,,,,,,,,d,,####,,,######",
		"#...####..##,,,,,,,,,,,,,,,####,,,######",
		"#C........###,,####..##########,,,.....#",
		"#...####.e###,,####..########,g,,,.i..C#",
		"#...####..###,,#........##,,,,,,,,.....#",
		"########................,,,,,,,,,,.....#",
		"########...........S....,,,,,,####...j.#",
		"################........##,,,,####...C.#",
		"################....E...##,,,###########",
		"########################################",
	},
	Cell = 7,
	Height = 16,
	Rooms = {
		{ Name = "Entry Hall", From = Vector2.new(17, 23), To = Vector2.new(24, 27) },
		{ Name = "Guard Post", From = Vector2.new(3, 3), To = Vector2.new(11, 9) },
		{ Name = "War Camp", From = Vector2.new(30, 3), To = Vector2.new(38, 9) },
		{ Name = "Antechamber", From = Vector2.new(16, 4), To = Vector2.new(25, 9) },
		{ Name = "Old Cell", From = Vector2.new(2, 19), To = Vector2.new(4, 23) },
		{ Name = "Storeroom", From = Vector2.new(35, 21), To = Vector2.new(39, 26) },
	},
	RoomHeight = 26,
	Patrols = {
		{ Route = "abcd", Orcs = 2 }, -- round the cavern's pillars
		{ Route = "ef", Orcs = 2 }, -- up and down the west corridor
		{ Route = "gh", Orcs = 2 }, -- the east caves, up toward the War Camp
		{ Route = "ij", Orcs = 2 }, -- guarding the Storeroom
	},
	ChestCoins = { Min = 25, Max = 50, Shown = 20 },
	Arena = { Radius = 70, Height = 55 },
}

DungeonConfig.Dungeons = { DungeonConfig.Grimgorg }

-- Where runs are built: the first at Origin, each next one Spacing further along +X (past the
-- land's east edge and the Training Grounds at X 1700).
DungeonConfig.Origin = Vector3.new(3000, 300, 0)
DungeonConfig.Spacing = 800
DungeonConfig.Slots = 24 -- runs at once (players per server is far fewer)
-- Where tools/dungeon_layout.lua builds the editable copy (workspace.DungeonLayouts) in Studio;
-- the game copies it into each run and takes it away when the server starts.
DungeonConfig.LayoutOrigin = Vector3.new(2200, 300, 0)

-- True if `position` is inside some run's space (for the zone banner).
function DungeonConfig.contains(position: Vector3): boolean
	local x = position.X - DungeonConfig.Origin.X
	return x > -DungeonConfig.Spacing / 2
		and x < DungeonConfig.Spacing * (DungeonConfig.Slots - 0.5)
		and math.abs(position.Y - DungeonConfig.Origin.Y) < 150
end

return DungeonConfig
