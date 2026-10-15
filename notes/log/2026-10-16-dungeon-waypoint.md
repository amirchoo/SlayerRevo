# Waypoint at Grimgorg's Lair

2026-10-16 · not playtested

## Asked
Add a map waypoint at the dungeon once you've reached it.

## Changed
- [MapConfig.luau](../../src/shared/Config/MapConfig.luau): `Waypoints`, a list (Beginning Town, always open; Grimgorg's Lair, unlocked by reaching it). A waypoint has a map letter, an optional `Discover` radius, and an optional `Dungeon` to teleport to its cave mouth
- [MapService.luau](../../src/server/MapService.luau): unlocks a waypoint when you come within `Discover` studs (40 for the lair), saves it, puts a "Waypoint unlocked" banner up, and only teleports to unlocked waypoints
- [DataService.luau](../../src/server/DataService.luau): saves `Waypoints` (reached ids)
- [DungeonService.luau](../../src/server/DungeonService.luau): `outsideOf` gives the spot in front of a cave mouth
- [Map.luau](../../src/client/Map.luau): a teleport button per waypoint on the world map ("L" for the lair), hidden until unlocked, with "Teleport to <name>?" to confirm

## Choices (easy to change)
- Reaching = within 40 studs of the cave mouth (going in counts, since you have to walk up to it).
- The lair teleport puts you outside the cave, not inside a run.
- Teleporting away from inside a run ends that run (it already did for the town waypoint).

## Open
- Unlocking reuses the dungeon banner (DungeonEvent remote); a proper "discovered" toast could come later.
