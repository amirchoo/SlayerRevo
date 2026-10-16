# Dungeon props from Toolbox models

**Asked:** the user dropped models into Workspace and asked me to sort them into the dungeon
(the asset list in [the maze handoff](../tasks/grimgorg-maze-handoff.md)).

## Malware found and removed
Two of the Toolbox models carried malicious scripts:
- `Workspace.Part` (an 11 × 0.4 × 13 slab with `LightConfig` / `VFXParticles`): the fake
  "Quenty" backdoor that decodes a hidden value to load remote code. Deleted whole.
- `Large Crystal Geode` › … › `PointLight` › `Runtime`: Studio-only script that builds a fake
  "instructions" window (the paste-into-command-bar scam). Deleted; the crystals are kept.
A scan of every unmanaged script in the place found nothing else. The other Toolbox scripts
(the chest's open script, a "read me") were disabled in Workspace and left out of the copies.

## What's in `ServerStorage.DungeonAssets` now (built from the Workspace originals, since removed from Workspace along with the unused `Union` and `Stone wall 1`)
| Asset | From | Done to it |
|---|---|---|
| `Chest` | Chest | rig/prompt/script removed; `Lid` = WoodTop + MetalTop + KeyHole, pivot on the back hinge; +Z = lock |
| `Torch` | WallTorch | lights removed (game adds one), its particle fire kept, `Flame` attachment, scaled 1.5 |
| `Crate` | Wood Crate | scaled to 3.5 |
| `Brazier` | `Model` (fire bowl) | Fire/light removed, `Flame` attachment, scaled to 5 tall |
| `Portcullis` | Portcullis | `Door` (lifts, 122 parts) + `Frame` (rock union), door scaled to 16 tall (12.6 wide) |
| `CaveRocks` | Pack Cave | its 15 rock meshes, recoloured to cave rock |
| `Crystal` | one small cluster of the geode | ~7 tall, one light kept |
| `CaveMouth` | Cave Entrance | ×1.25 (opening ~14 × 16), rock material |

## Code ([DungeonBuilder](../../src/server/DungeonBuilder.luau))
- `gate()` uses `Portcullis` (its `Door` lifts); gates now carry their own `lift` height.
- Cave boulders use a random `CaveRocks` rock, scaled and turned (`boulder()`).
- `crystal()`: `CRYSTAL_CHANCE = 0.04` per cave wall square, only when the asset exists, non-solid.
- `entrance()` uses `CaveMouth` in place of the pillars and lintel.
- Torches with their own ParticleEmitters don't get the game's Fire too.
- Pivots/names in [assets/dungeon/README.md](../../assets/dungeon/README.md).

## Open
- Edit-mode test build passes (after Rojo was reconnected, with the terrain rework: see
  [its log](2026-10-17-dungeon-terrain.md)); not playtested.
- Not covered by what was added: floor tiles, orc camp dressing, door-frame arches, exit
  portal arch (the white marble `Union` might be one; unused), stone wall kit (`Stone wall 1`
  is a single 7 × 4 strip, too many meshes to tile the maze).
- The `.rbxmx` source copies in `assets/dungeon/` aren't saved yet; the props live only in the
  place, so **save the place**.
- Watch in play: portcullis performance (122 tweened parts per gate), frame pillars narrowing
  14-wide passages slightly, the scaled cave mouth sitting right on the mound.
