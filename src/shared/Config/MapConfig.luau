--!strict
-- The minimap (top right) and the full world map (M, or tap/click the minimap), drawn by
-- client Map from a top-down picture of the world: assets/map/world.png, uploaded as Image.
-- The picture covers WorldMin to WorldMax on X/Z, north (-Z) at the top. It's a capture of
-- the world as built, so after changing the terrain, town or forest a lot, recapture it
-- (tools/stitch_map.py has the steps) and upload the new one.

-- A place on the world map you can teleport to. Discover: it starts locked and unlocks for
-- good once you come within that many studs of Position (MapService saves it); without it,
-- it's always open. Dungeon: teleports to that dungeon's cave mouth (DungeonConfig) instead
-- of the ground at Position.
export type Waypoint = {
	Id: string,
	Name: string,
	Position: Vector2, -- X/Z in the world
	Letter: string, -- on its map button
	Discover: number?,
	Dungeon: string?,
}

export type Label = {
	Text: string,
	Position: Vector2, -- X/Z in the world
	Kind: "town" | "area" | "ruin", -- how big and what color it's drawn
}

local MapConfig = {}

MapConfig.Image = "rbxassetid://131734136830887"
MapConfig.WorldMin = Vector2.new(-1024, -1024)
MapConfig.WorldMax = Vector2.new(1024, 1024)

MapConfig.OpenKey = Enum.KeyCode.M
MapConfig.TownWaypoint = { Id = "BeginningTown", Name = "Beginning Town", Position = Vector2.new(0, 16), Letter = "T" } :: Waypoint
MapConfig.Waypoints = {
	MapConfig.TownWaypoint,
	-- DungeonConfig.Grimgorg.Entrance
	{ Id = "GrimgorgLair", Name = "Grimgorg's Lair", Position = Vector2.new(-480, -862), Letter = "L", Discover = 40, Dungeon = "Grimgorg" },
} :: { Waypoint }

-- Whether `player` can use `waypoint` (unlocked ones have a "Waypoint_<Id>" attribute, set by
-- MapService from their save).
function MapConfig.unlocked(player: Player, waypoint: Waypoint): boolean
	return waypoint.Discover == nil or player:GetAttribute("Waypoint_" .. waypoint.Id) == true
end

MapConfig.Minimap = {
	Size = 190, -- pixels across (before HUD scaling)
	Range = 170, -- studs from the player to the minimap's edge
	Margin = Vector2.new(16, 16), -- from the top-right corner
}

-- Place names drawn on the full map (and named under the minimap when you're there).
MapConfig.Labels = {
	{ Text = "Beginning Town", Position = Vector2.new(0, 0), Kind = "town" },
	{ Text = "Hunting Grounds", Position = Vector2.new(0, -460), Kind = "area" },
	{ Text = "The Great Arch", Position = Vector2.new(0, -900), Kind = "ruin" },
	{ Text = "Fallen Columns", Position = Vector2.new(-330, -800), Kind = "ruin" },
	{ Text = "Broken Keep", Position = Vector2.new(340, -830), Kind = "ruin" },
	{ Text = "Grimgorg's Lair", Position = Vector2.new(-480, -862), Kind = "ruin" }, -- DungeonConfig.Grimgorg.Entrance
	{ Text = "West Ruins", Position = Vector2.new(-600, 130), Kind = "ruin" },
	{ Text = "East Ruins", Position = Vector2.new(600, 150), Kind = "ruin" },
	{ Text = "Old Shrine", Position = Vector2.new(0, 540), Kind = "ruin" },
} :: { Label }

return MapConfig
