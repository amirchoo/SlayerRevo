# Handoff: Grimgorg's Lair maze (continue from here)

Written 2026-10-16 at the end of the session that remade the lair as a maze.
Full record of that work: [log](../log/2026-10-16-grimgorg-maze.md).

## State
- **Code done, not committed, not playtested.** Uncommitted: `DungeonConfig.luau`, `DungeonGrid.luau` (new),
  `DungeonBuilder.luau`, `DungeonService.luau`, `EnemyService.luau`, `default.project.json`, `assets/dungeon/README.md` (new),
  `docs/design.md` (§12 Bosses and dungeons row), the log note, `notes/log/README.md`, `notes/backlog.md`.
  Commit and push to origin/main when the user says so.
- `sh tools/check_syntax.sh` passes; VS Code's luau-lsp showed no errors.

## How it works (short)
- Layout = ASCII grid `Map` in [DungeonConfig.luau](../../src/shared/Config/DungeonConfig.luau), 7-stud squares
  (legend at the top of that file). Rooms are square ranges (1-based column,row); patrols are waypoint letters.
- [DungeonGrid.luau](../../src/server/DungeonGrid.luau): square ↔ world, `route` (BFS + straight-line shortcuts) for orc
  pathing; closed gates and `?` fake walls block orcs.
- [DungeonBuilder.luau](../../src/server/DungeonBuilder.luau): builds the maze from the grid (merged blocks), gates, torches,
  boulders, crates, chests, arena north of the `A` squares. `asset(parent, name, cframe)` clones from
  `ServerStorage.DungeonAssets` (unmanaged by Rojo, like EnemyModels) and falls back to parts.
- [DungeonService.luau](../../src/server/DungeonService.luau): patrols spawn at run start; war rooms (rooms with `O`s) seal
  their gates; arena gate opens only after every war room is cleared; chests give coins once per run.
- [EnemyService.luau](../../src/server/EnemyService.luau): `spawnOnFloor(position, kind, roam?)`, where `Roam` = patrol route +
  navigate + sight check.

## Waiting on the user
- [x] **Chest loot** (2026-10-17: spinning gold coins, random total per player, see [log](../log/2026-10-17-chest-coins.md))
- [ ] **3D assets** (made in Claude Design from `docs/model-brief.md`, then the "Into the game" steps there).
  2026-10-17: 1–5, 8 and 12 done from Toolbox models (plus crystals), see
  [log](../log/2026-10-17-dungeon-assets.md). Still missing: 6, 7, 9, 10, 11.

### Assets: already hooked up (drop into `ServerStorage.DungeonAssets`, pivots per `assets/dungeon/README.md`)
1. `Chest` (~4.5 × 3 × 3, child `Lid` pivoted on the hinge)
2. `Torch` (wall bracket, `Flame` attachment)
3. `Crate` (~3 studs); a barrel would be a nice extra (not hooked up)
4. `Brazier` (~5 tall, `Flame` attachment; arena)

### Assets: need a new hook in DungeonBuilder when delivered
5. Portcullis (7 and 14 wide × 16 tall): replace the bars in `gate()`; `setGate` lifts whatever parts are in `bars`.
6. Stone wall kit (7-wide × 16 tall, a 26-tall room version, outer corner, pillar): would replace/skin the merged `Rock` blocks.
7. Floor tiles, stone and cave (7 × 7).
8. Cave rock kit (3–4 rock chunks, stalagmites): replace the `Boulder` balls.
9. Arch / door frame (7 and 14 wide) where passages meet rooms (the `Lintel` parts).
10. Orc camp dressing for war rooms (weapon rack, bedroll, campfire, banner, skull pile).
11. Exit portal arch (~11 wide × 13 tall), replaces `portal()` pillars.
12. Cave mouth for the outside entrance (~30 × 25, 14 × 16 opening), replaces `DungeonBuilder.entrance` parts.

## Check when it's next playtested (only if the user asks: playtests cost them tokens)
- Orcs snagging on boulders/crates or on corners while chasing; patrols bunching at waypoints.
- Nobody gets aggroed at the spawn `S` (waypoints d, e, g were moved out of its sightline).
- Frame rate: number of torches/PointLights (tune `TORCH_CHANCE`) and part count with several runs.
- Gate orientation and lift (bars should hide in the ceiling), arena doorway lining up with the `A` corridor.
- Chest lid swing, fake wall `?` walk-through, banners (room names, "Sealed. Still to clear: …").
- Whether the maze is too long or the cavern too open; tweak the `Map` strings.
