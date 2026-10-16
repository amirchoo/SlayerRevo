# Dungeon editable in Studio (saved layouts)

**Asked:** change the dungeon's assets and layout by hand in Studio (edit mode), not in a
playtest; the cave entrance couldn't be found in Studio (it only existed at runtime).

## How it works now
- `workspace.DungeonLayouts` is saved in the place (like workspace.Town):
  - `Grimgorg`: the dungeon at `DungeonConfig.LayoutOrigin` (X 2200, Y 300). Its **terrain**
    (sculpt with the terrain tools) and its **Decor** model (torches, rocks, crystals, crates,
    braziers, the fake wall, the arena's lava ring; anything added inside it) are copied into
    every run. **Guide** (gates, chests, the way out, gate seals) is locked and only shows where
    the game puts those: they're rebuilt per run from the Map. Attributes `Origin`,
    `RegionLow`, `RegionSize` say what terrain belongs to it.
  - `GrimgorgEntrance`: the cave mouth, used as saved (moved, reshaped, added to). It needs
    parts named `Opening` (walk in to enter; also gives the ground spot and facing for the
    waypoint) and `PromptAnchor` (its prompt).
- At server start DungeonService takes each layout out of the world (`DungeonBuilder.loadLayout`:
  copies its terrain to a TerrainRegion, clears it, keeps a Decor copy) and each run pastes it
  at the run's spot (`DungeonTerrain.paste`, offset = run origin − layout origin). Scripts in
  Decor and the entrance are removed (Toolbox safety). Without a saved layout/entrance the old
  generated path is used.
- [tools/dungeon_layout.lua](../../tools/dungeon_layout.lua): command-bar snippet that (re)builds
  them; flags `REBUILD_DUNGEON` / `REBUILD_ENTRANCE`. Rebuilding throws away hand edits.

## Tested (edit mode, no playtest)
Layout built (114 decor items, 17 guide pieces); a run built from it at the slot-1 spot:
decor offset exactly +800 X, floor under the spawn at Y 300, gates/chests/way out built;
the saved entrance reads back at the config spot facing south. Test terrain cleared.

## Open
- The map marker, waypoint discovery radius and `DungeonConfig.Entrance` still use the config
  position; if the entrance is moved far, update MapConfig too (teleport uses the saved one).
- Hand edits must keep the Map's squares walkable (orcs route on the grid, not the terrain).
- **Save the place** to keep the layouts.
