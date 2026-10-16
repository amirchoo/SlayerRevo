# Streaming and density (polish pass step 4)

**Asked:** step 4 of [[perf-polish]] (priority 0: lag). The user was away from the Mac and asked
Claude to playtest and verify it in Studio.

## Results

| | Before | After |
|---|---|---|
| Parts in workspace.World | 53,979 (with the Destroyed house) | **46,219** |
| SurfaceAppearances in World | 7,771 | **491** |
| World parts in touch and raycast checks | all of them | 2,476 (trunks, ruins, bridges, chests, house) |
| Parts in Workspace | 62,409 | **53,282** |
| Small plants drawn on Low / Medium / High | 1,310 everywhere | **538 / 983 / 1,310** |

## What changed

### In the place (Studio edit mode; the user needs to save and publish)
- **The 40 "PinkFlower" clumps are now single-piece HogWeed plants.**
  - Each clump was a knee-high bunch of white daisies made of 195 MeshParts with 183 SurfaceAppearances.
  - Each one is now a HogWeed copy (already used in the world, also a white-flowered weed),
    scaled to the clump's height, standing on the same ground with a varied facing.
  - The originals are kept in `ServerStorage.UnusedFromWorkspace.PinkFlowers`.
  - Compared from the same camera spot: it reads as the same kind of meadow weed.
- **Every model in `World` and `Town` streams in whole** (ModelStreamingMode Atomic, 2,521 models).
  A tree, a weapon rack or a stall no longer arrives a few parts at a time.
- **`MountainBackdrop` is Persistent:** the mountain ring around the map is always loaded.
- **Walk-through plant parts** (leaves, grass, flowers, bushes: 43,743 parts):
  - CanTouch and CanQuery are off, so physics and raycasts skip them. Enemy and animal ground
    checks no longer land on leaves.
  - Their collision shape is a plain Box (37,295 MeshParts were Hull or Default), which is less
    collision geometry to keep in memory.
  - The bushes' RenderFidelity went from Precise to Automatic (2,496 parts), so far bushes draw
    with fewer triangles.
  - Tree trunks keep their collision.

### Code
- [QualityConfig](../../src/shared/Config/QualityConfig.luau) `Decor` per tier: the share of the
  world's grass, small flowers and bushes drawn. Low 0.4, Medium 0.75, High 1.
- [WorldDensity](../../src/client/WorldDensity.luau) (new, started in init.client):
  - On this screen only, it takes out the share of TallGrass, Wildflower, HogWeed and Bush that the tier
    doesn't draw.
  - Which plants go is fixed by where they stand, so it's the same plants every time.
  - Raising the tier puts them back.
  - None of these collide, so movement and the server are unaffected.

## Choices
- **The streaming radius was not changed.**
  - Studio scripts can't read or write it, so it's a to-do for the user.
  - The play client had the whole world loaded: 2,285 World models up to 1,265 studs away. So the radius is
    large (probably the 1,024 default).
  - Lowering it is the biggest phone memory win left, but the world terrain also streams. Below
    about 850 studs the mountains around the map could disappear when seen from town. The user should judge that by eye (see To do).
- **Trees keep all 35 leaf meshes.** Merging them needs a new mesh asset. Every leaf uses the same mesh, so the GPU can
  batch them well. Their shadows are step 5.
- **Medium thins plants to 75%** so the phone (Medium by default) gains something. The look is built
  for Medium, and at 75% a meadow still reads full.

## Checks
- `sh tools/check_syntax.sh`: all scripts parse.
- **Playtested in Studio by Claude:**
  - no script errors (only the same old asset warnings as step 3)
  - WorldDensity, run on the play client with the tier pinned: Low left 538 small plants
    (52,816 parts loaded), Medium 983 (56,001), High all 1,310 (58,468)
  - limit: a test script gets its own copy of the modules, so it couldn't pin the game's real tier.
    The real client script was checked to require and start WorldDensity, and the same code ran
    in the test.
  - HogWeed replacement: before and after screenshots from the same spot

## To do (user, in Studio)
1. Save and publish (all of the place changes above are only in the open place).
2. **Streaming:** select Workspace and, in Properties, note the current values first. Then try:
   - `StreamOutBehavior` = **Opportunistic** (a phone lets far parts go even before it runs short of memory)
   - `StreamingTargetRadius` = **768**, `StreamingMinRadius` = **128**
   - then stand in town and look at the mountains. If they vanish or pop, go back up to 1024
     (keep Opportunistic).

## What to check (phone and PC)
- FPS (Shift+F5) in the forest and in town, against before.
- Memory on the phone (Shift+F5, or no crash after a long session).
- Trees and town props pop in whole, never half-built.
- Meadows on Medium (the phone default) still look full. On Low, about 40% of the small plants remain.
- Arrows and spells pass through leaves and grass. Tree trunks still block you.

## Open
- Streaming radius (above).
- Tree shadows and the town's 42 night lights: step 5.
