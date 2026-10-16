# Startup content and Workspace cleanup (polish pass step 3)

**Asked:** run step 3 of [[perf-polish]]: bake what's still built at startup and clear Workspace
clutter. Keep the "Destroyed house". The user also set priorities: **the polish and performance
pass (lag) is priority 0**, and the [[main-issue-dueling-vibe]] is priority 1.

## What changed

### In the place (Studio edit mode; the user needs to save and publish)
- **Clutter moved out of Workspace** into `ServerStorage.UnusedFromWorkspace`, where clients
  never download it:
  - the 7 `Hammer*` KeyframeSequences (the repo's `assets/animations` already has these drafts;
    the copies are kept in case they hold newer edits)
  - the "Relaxed Scene" Sound and the 3 Sounds inside it (no script uses them)
  - two tiny "Water" parts 700 studs underground
- **The Model named "Terrain" is now `MountainBackdrop`.** It holds the huge mountain mesh around
  the map, so it stays. The rename stops `FindFirstChild("Terrain")` from picking it up
  instead of the real Terrain.
- **"Destroyed house" moved into `workspace.World`**, so it's part of the world (enemy and animal
  ground checks now count it too).
- **The Grimgorg dungeon layout moved to `ServerStorage.DungeonLayouts.Grimgorg`.** Its terrain is
  saved beside it as a TerrainRegion named "Terrain", and its terrain was cleared from the world.
  `GrimgorgEntrance` (the cave mouth) stays in `workspace.DungeonLayouts`.

### Code
- [DungeonBuilder.loadLayout](../../src/server/DungeonBuilder.luau): uses a saved "Terrain"
  TerrainRegion when the layout has one. It only copies and clears world terrain for a layout
  still in Workspace, such as one just made by `tools/dungeon_layout.lua`.
- [DungeonService.start](../../src/server/DungeonService.luau): looks in `ServerStorage.DungeonLayouts`
  first, then in `workspace.DungeonLayouts`.
- [InventoryService.register](../../src/server/InventoryService.luau): WeaponService, GreatswordService
  and StaffService register each weapon at server start. The Training Grounds stands and the Hall
  of Oaths statues used to wait for the first player to join before they got their weapons, so new
  players saw empty-handed statues and weapons popping in. Now the weapons are there from the start.
- [TrainingStands](../../src/server/TrainingStands.luau): each stand streams in as a whole model
  (Atomic), like the Hall's alcoves already did.

## Choices
- **The training ground, stands and Hall of Oaths were not baked into the place.**
  - The server builds them at start, before anyone joins, so baking would barely change load time
    or lag.
  - The pop-in came from the weapons waiting for the first join. That's fixed at its cause above.
  - Baking them would mean keeping 21 armored mannequins in sync with ArmorConfig by hand.
- **The Baseplate stays.** `default.project.json` defines it, so Rojo would put it back. A grid
  check showed terrain covers it everywhere, so players never see it.
- **The `Rig` stays.** The Animation Editor needs it for publishing.

## To do (user, in Studio)
1. Save the place, then publish (the moves above are only in the open place until then).
2. Optional: delete `ServerStorage.UnusedFromWorkspace` once you're sure the Hammer drafts in it
   aren't newer than the ones in the repo.

## Editing the dungeon layout from now on
- Drag `ServerStorage.DungeonLayouts.Grimgorg` back into `workspace.DungeonLayouts`.
- Paste its terrain back with `workspace.Terrain:PasteRegion(layout.Terrain, ...)` at
  `RegionLow / 4`, then delete the "Terrain" child.
- Edit it there. The server reads a layout in Workspace the old way, copying and clearing its terrain.

## Checks
- `sh tools/check_syntax.sh`: all scripts parse.
- Not playtested.

## What to check (phone and PC)
- **Hall of Oaths (new player intro):** every statue holds its weapon right away, with nothing
  popping in.
- **Training Grounds (admin panel):** all 11 stands hold weapons, and each arrives whole.
- **Grimgorg dungeon:** enter it. The run should look and play exactly as before (terrain, torches,
  gates, chests, boss). If the dungeon has no walls or floor, the saved TerrainRegion didn't survive
  the save. Tell me and I'll switch to another method.
- **Destroyed house:** it's still where it was.
- **Join time** in a fresh server (Shift+F5 for FPS): it should be the same or a bit faster.

## Open
- Most of the lag is still ahead: step 4 (953 trees, PinkFlower's 7,320 SurfaceAppearances,
  streaming), step 5 (dungeon emitters and lights) and step 7 (230 server-moved Humanoids).
