# Dungeon carved from terrain, no map inside

**Asked:** no map in the dungeon (harder), and walls/floors with more detail: cave terrain like
the land instead of flat blocks.

## No map in a run
[Map.luau](../../src/client/Map.luau): while the player has the `Dungeon` attribute the minimap
is hidden and M / the minimap / DPadLeft don't open the world map (an open one closes on entry).
It comes back when they leave.

## Terrain
New [DungeonTerrain.luau](../../src/server/DungeonTerrain.luau) carves each run out of solid
terrain with WriteVoxels (16×16-voxel chunks, yields between them; the whole run builds in
~0.5 s in edit mode), and clears it to air when the run ends (`DungeonBuilder.clear`).
- Open space = every floor square (its ceiling: 16 corridors/caves, 26 rooms), the arena circle
  (radius 70, 55 tall) and the passage to its doorway. The rock is cut back **past** the grid
  edges by noise (walls 1.5–3.5, ceilings 1.5–6), never into them, so orc routing on the grid is
  unchanged. Measured: floors within ±0.4 of the line, walls on average 2.8 past the edge
  (a few spots at ankle height dip up to 0.6 in), headroom at least 17.6.
- Materials: built rooms/corridors Cobblestone floor with Slate patches, Slate walls with
  Basalt; caves Ground floor with Mud, Rock walls with Slate; arena Basalt with CrackedLava
  patches. (Terrain colours are the place's global ones, same as the land.)
- Gotcha found while testing: a voxel's surface shows half a voxel (2 studs) out from where its
  occupancy says; the carve allows for it (`RES / 2`) and the floor's top layer is half full.
- Removed: block-built rock/floor/ceilings, lintels, the part-built arena floor/ceiling/walls.
- Torches, cave rocks, crystals, crates, chests and the way out are placed by a ray to the
  carved rock (`wallHit`), since the walls are uneven.
- Gates get invisible `GateSeal`s either side, since the passage is now wider than the gate.
- The fake wall is oversized (+7 wide/deep, +6 tall) to cover the carved gap round it.
- DungeonService reserves the slot (and the player) while a run is being built, since building
  now yields; if the player left meanwhile, the run is cleared.

## Open
- Not playtested (no screenshots either). Look for: how it reads in the dark, orcs snagging on
  the rough wall bases, the fake wall standing out against terrain, torch light vs. terrain.
- Tuning: `WALL_CARVE`, `CEILING_CARVE`, `MATERIALS` in DungeonTerrain.
