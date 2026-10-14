# NPC sources

Raw rigged models for the animal NPCs (not synced). The game uses the `.rbxmx` saved from
Studio into `assets/npcs/` (see the README there for the Studio steps).

| NPC    | Source       | Import this        |
|--------|--------------|--------------------|
| Bonnie | `Bonnie.glb` | `Bonnie.ready.glb` |

**Bonnie** (the inn's cat): one skinned mesh `BonnieBody`, 14,324 triangles, 0.77 x 1.85 x 1.93
studs, feet at Y=0, designed facing +Z. Six flat-color materials (furWhite, furGrey,
tabbyStripe, pinkSkin, eyeAmber, pupil). 25 bones: Root > Pelvis > Chest > Neck > Head
(EarL/R, LidL/R), FrontUpper/Lower/Paw L/R, HindUpper/Lower/Paw L/R, Tail1-4. Four looping
clips: Idle (4 s), Sleeping (6 s), Loafing (5 s), Playing (3 s). Eyelids: LidL/LidR X
rotation -1.2 rad open, 0.15 half (the rest pose), 1.45 shut (`NpcConfig.Pets` Lids).

`.ready.glb` is made with `tools/npc_glb.py`, which keeps the skeleton, skin weights and clips
(`tools/weapon_glb.py` would strip them): it bakes the colors into a palette texture, joins
the mesh into one primitive, and turns the model to face -Z:

    python3 -I tools/npc_glb.py assets/source/npcs/Bonnie.glb /dev/null --info
    python3 -I tools/npc_glb.py assets/source/npcs/Bonnie.glb assets/source/npcs/Bonnie.ready.glb --turn-y 180

`--clip Idle` (repeatable) writes only the named clips, if Studio ever needs one clip per file.
