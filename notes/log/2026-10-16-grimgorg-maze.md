# Grimgorg's Lair as a maze

2026-10-16 · not playtested

## Asked
The lair was too straightforward (hall → two rooms → arena in a line). Remake it as a maze,
like a hand-drawn dungeon map (a Dyson Logos map was the reference): confusing parts, orcs roaming
around, rooms with chests. List the 3D assets needed rather than building everything from parts.

## Changed
- [DungeonConfig.luau](../../src/shared/Config/DungeonConfig.luau): the layout is now a grid map
  (one string per row, 7-stud squares): `#` rock, `.` stone floor, `,` cave floor, `+` gate,
  `?` fake wall, `S` start, `E` way out, `C` chest, `O` war-room orc, `A` arena doorway, `a-z`
  patrol waypoints. Named rooms by square range, patrols by waypoint letters, chest coins.
- [DungeonGrid.luau](../../src/server/DungeonGrid.luau) (new): the map placed for one run: square ↔
  world, and `route` (breadth-first over the squares plus straight-line shortcuts) so orcs walk
  round walls and through open gates.
- [DungeonBuilder.luau](../../src/server/DungeonBuilder.luau): builds the maze from the map, merging
  squares into big blocks (cut stone for rooms/corridors, rough rock and bulging boulders in the
  caves), taller ceilings in named rooms with lintels where passages meet them, gates per run of
  `+`, torches (dense in rooms, rare in caves), crates, chests with a swinging lid, the arena north
  of the `A` squares. Uses `ServerStorage.DungeonAssets` models (Chest, Torch, Crate, Brazier) when
  present.
- [DungeonService.luau](../../src/server/DungeonService.luau): patrols set off at run start; war rooms
  seal all their gates; the arena gate starts shut and opens once every war room is cleared
  (walking up to it while shut says what's left); room name banner the first time you walk in;
  chests give every member coins once.
- [EnemyService.luau](../../src/server/EnemyService.luau): `spawnOnFloor` takes a `Roam`: a patrol
  route (walked slowly, pausing 1-3 s at each point), a way round walls, and a sight check (a
  patroller notices you only with a clear line; once chasing it follows round corners).
- `default.project.json`: `ServerStorage.DungeonAssets`, unmanaged like EnemyModels;
  [assets/dungeon/README.md](../../assets/dungeon/README.md) says how each prop must be pivoted.

## The layout
Hall (bottom middle) opens three ways. The middle is a big cavern with rock pillars to loop
round, leading north to the Antechamber and the arena. The two war rooms that unseal the arena
are in the far corners: the **Guard Post** (4 orcs, NW, up the west corridor) and the **War
Camp** (5 orcs, NE, up the east caves). Side places: the Old Cell (chest, west, down a 1-wide
passage), the Storeroom (2 chests, SE, two orcs on guard), a hidden nook behind a fake wall
in the east caves (chest), and a few dead ends. 4 patrols of 2 orcs: round the cavern, the west
corridor, the east caves, the Storeroom. 17 orcs in all (was 8).

## Choices (easy to change)
- Arena sealed until both war rooms are cleared: forces exploring instead of beelining.
- Patrol waypoints kept out of sight of the spawn so you're not jumped when you arrive or respawn.
- Dead patrol orcs stay dead for the run (also after dying).
- Chests: 25-50 coins to each member: **placeholder**; chest loot is [TBD].
- Fake wall is a shade lighter than the rock around it (a faint tell).
- Patrollers don't use the fake wall.

## Open
- Chest loot [TBD] (user's call), with boss loot.
- 3D assets for the dungeon (list in the reply that went with this; README for the props that
  are already hooked up). Wall/floor kit pieces would need a new hook in the builder.
- Not playtested: watch for orcs snagging on boulders/crates, torch count (frame rate), and
  whether the cavern is too open or the maze too long.
- Part count is roughly a few hundred blocks per run plus torches; check with several runs.
