# Dungeon props

**Not synced by Rojo** (mesh models, like `assets/enemies`): `ServerStorage.DungeonAssets` is
left alone by Rojo and its models live in the saved place. After changing a file here,
right-click `ServerStorage › DungeonAssets` > Insert from File (and delete the old copy). These
files are the source copies.

`src/server/DungeonBuilder.luau` uses a model from that folder, by name, in place of the stand-in
it builds out of parts. Without one, the stand-in stays. Each is a Model, anchored or not (it
anchors them), placed by its **pivot** (Model > Pivot > Edit Pivot in Studio):

| Name | Pivot | Front | Extra |
|------|-------|-------|-------|
| `Chest` | bottom middle, on the floor | +Z (the lock side) | its lid is a child named `Lid` (a part or a model) whose pivot is on the hinge; it swings up 105° about its X axis |
| `Torch` | where it's fixed to the wall, at flame height | +Z (away from the wall) | an Attachment named `Flame` where the fire goes (the game adds the light, and a fire unless the torch has its own ParticleEmitters) |
| `Crate` | anywhere (it's set down on the floor under its middle) | +Z (away from the wall) | |
| `Brazier` | bottom middle, on the floor | any | an Attachment named `Flame` over the bowl |
| `Portcullis` | bottom middle of the doorway, on the floor | spans its X axis | a child Model named `Door` (what lifts, 16 tall); anything else, like a `Frame`, stays put. Made for a 14-wide passage |
| `CaveRocks` | any | any | not one prop: a Model whose children (rock parts or models) are picked at random, scaled and turned for the cave walls |
| `Crystal` | bottom middle, on the floor | -Z against the wall | optional: caves get a few only if it exists; it's made non-solid |
| `CaveMouth` | on the ground in the middle of the opening, ~2.5 studs in front of the arch (so it sits flush on the rock behind) | +Z (out of the cave) | the rock arch round a ~14 × 16 opening; the dark doorway, prompt and torches are added by the game |

Sizes: the maze's squares are 7 studs (`Cell` in `DungeonConfig.luau`), corridors are 16 studs
tall and rooms 26. A chest about 4.5 × 3 × 3 studs fits; a crate 2.5 to 4.
