# Arena floor fix, player light, lighter torches

**Asked:** the arena's terrain and floor plates glitch through each other; give every player
some kind of torch (the caves are dark, and so are the wilds at night); lights flicker and
take long to load on an Intel MacBook: hardware or scripts?

## Arena floor
The terrain floor's rendered surface wobbles about ±0.8 studs (299.2–300.8 in the arena,
measured by raycasts) and the plates were 0.1 studs thick at 300.05, so a third of the floor
poked through. The LavaRing and ArenaInner are now solid slabs 2 studs thick, tops at
+0.86 / +0.9 over the floor (DungeonBuilder `ARENA_PLATE`), and collide (you stand on them).
Applied to the saved layout in Studio too: 0 terrain samples above the plates.

## Player light
New client [PlayerLight](../../src/client/PlayerLight.luau), tuned in LightingConfig.PlayerLight:
a warm PointLight (range 26, brightness 1.4, no shadows) at chest height on every character,
lit on each screen. Full in a dungeon run, follows DayCycle's night out of town, 40% in town
at night, off by day; fades in and out; only the 8 characters nearest the camera are lit.
A glow, not a held torch model (hands hold weapons); a visible lantern could be added later.

## Flicker / slow lights
Both: the place uses Future lighting, and the dungeon had 32 shadow-casting torch lights and
about 240 particle emitters. Future renders only a few shadowed lights at once on weak GPUs
(Intel Mac integrated graphics), swapping them as you move: that's the flicker. Streaming
also loads far parts (and their lights) late. Wall torches no longer cast shadows (code and
the saved layout: 28 turned off); the 4 arena braziers keep theirs. If it still flickers,
lowering Studio's graphics quality or switching Lighting.Technology to ShadowMap
(default.project.json) are the next steps.

## Not playtested
Measured in edit mode only (plates vs terrain). The player light hasn't been seen in game.

## Follow-up: crates and chests sunk into the floor
Asked: "most of the crate if not all is also stuck underground". The Crate asset's pivot is
its middle (the code expected its bottom), so crates sat half their height (1.75) low, plus
the floor's bumps; chests sank up to a stud from the bumps alone. DungeonBuilder `settle`
now sets crates and chests down on the terrain under their middle (cast from the prop's top,
since some sit under overhangs), sunk 0.15 so no gap shows; braziers stand on the arena plate
top. In the saved layout: 16 crates and 4 chests set down (one crate buried in a wall's foot
moved 2 studs out), the 4 braziers raised 0.86 onto the plates. Edit mode only.
