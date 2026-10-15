--!strict
-- Dungeons: a cave in the world leads into a private copy of the dungeon for whoever walks
-- in (one run per player for now; a party will share one when parties exist). DungeonService
-- builds each run's copy out past the edge of the land, far from the others, and runs it.
--
-- A run: start in the entry hall; each orc room seals its doors as you walk in and drops its
-- orcs, and opens both doors once they're all dead; the last door leads to the boss arena,
-- which seals until the boss is beaten (or everyone in it is dead). Dying puts you back in the
-- entry hall with the cleared rooms still cleared; a room you were fighting in empties and
-- opens again (its orcs come back when you walk in). Beating the boss opens a way out in the
-- arena; the hall's way out works any time. Leaving (or disconnecting) ends the run.
--
-- The layout runs from the entry hall toward -Z. Positions are offsets from the run's origin
-- (the hall floor's centre); every piece is a box (Size X, Z) on the floor, Height tall,
-- except the arena, a round room.

export type Room = {
	Name: string,
	Center: Vector2, -- X/Z offset
	Size: Vector2,
	Height: number,
	Orcs: number?, -- an orc room: how many come at you
}

export type Dungeon = {
	Id: string,
	DisplayName: string,
	Recommended: string, -- shown on the entrance
	Boss: string, -- BossConfig id
	-- The cave mouth in the world (X/Z; dropped onto the ground) and which way it faces.
	Entrance: Vector2,
	EntranceFacing: Vector2,
	Hall: Room,
	Rooms: { Room }, -- in order, each joined to the last by a corridor
	CorridorWidth: number,
	CorridorHeight: number,
	DoorWidth: number, -- the openings between rooms (closed by the gates)
	DoorHeight: number,
	Arena: { Center: Vector2, Radius: number, Height: number },
	OrcSpawnDepth: number, -- orcs drop in this far from a room's far wall
}

local DungeonConfig = {}

-- Grimgorg's Lair: a cave in the mountains at the north-west edge of the hunting grounds.
DungeonConfig.Grimgorg = {
	Id = "Grimgorg",
	DisplayName = "Grimgorg's Lair",
	Recommended = "Lv 5-8",
	Boss = "Grimgorg",
	Entrance = Vector2.new(-480, -862),
	EntranceFacing = Vector2.new(0, 1), -- out over the plain (south)
	Hall = { Name = "Entry Hall", Center = Vector2.new(0, 0), Size = Vector2.new(36, 36), Height = 22 },
	Rooms = {
		{ Name = "Guard Post", Center = Vector2.new(0, -83), Size = Vector2.new(70, 70), Height = 28, Orcs = 3 },
		{ Name = "War Camp", Center = Vector2.new(0, -188), Size = Vector2.new(80, 80), Height = 30, Orcs = 5 },
	},
	CorridorWidth = 16,
	CorridorHeight = 18,
	DoorWidth = 14,
	DoorHeight = 14,
	Arena = { Center = Vector2.new(0, -338), Radius = 70, Height = 55 },
	OrcSpawnDepth = 12,
}

DungeonConfig.Dungeons = { DungeonConfig.Grimgorg }

-- Where runs are built: the first at Origin, each next one Spacing further along +X (past the
-- land's east edge and the Training Grounds at X 1700).
DungeonConfig.Origin = Vector3.new(3000, 300, 0)
DungeonConfig.Spacing = 800
DungeonConfig.Slots = 24 -- runs at once (players per server is far fewer)

-- True if `position` is inside some run's space (for the zone banner).
function DungeonConfig.contains(position: Vector3): boolean
	local x = position.X - DungeonConfig.Origin.X
	return x > -DungeonConfig.Spacing / 2
		and x < DungeonConfig.Spacing * (DungeonConfig.Slots - 0.5)
		and math.abs(position.Y - DungeonConfig.Origin.Y) < 150
end

return DungeonConfig
