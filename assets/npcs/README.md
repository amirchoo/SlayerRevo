# NPC models

Synced to `ServerStorage.NpcModels`. Each animal NPC in `NpcConfig.Pets`
(`src/shared/Config/NpcConfig.luau`) uses the model named in its `Model` setting:
Bonnie uses `Bonnie.rbxmx`. Until that file is here, she isn't spawned (the server warns).

These are rigged meshes with their own skeleton (not R15, so no Avatar Setup). PetService
(server) scales the model to its `Height`, welds it to an invisible, non-solid
HumanoidRootPart with a Humanoid (so it walks, like the wildlife), walks it around its
`Wander` area and picks what it's doing; petting it (its prompt) makes it play. PetAnimator
(client) poses the bones every frame from the clip data in `src/shared/PetClips/`, swings the
legs while it walks, and moves the eyelids (PetEyes).

**The clips are played from the .glb's own keys, not uploaded animations.** Import 3D puts
the bones in the mesh's bind pose and converts the clips into offsets from it, and for
Bonnie (bent legs at rest, straight in the bind pose) those came out scrambled. So after
importing, make the clip data from the original file (not the turned `.ready.glb`):

    python3 -I tools/npc_clips.py assets/source/npcs/Bonnie.glb src/shared/PetClips/Bonnie.luau

and point the pet's `Clips` (NpcConfig) at it. The imported AnimSaves aren't needed.

Bonnie is in: `Bonnie.rbxmx` is saved here, her clips are `PetClips/Bonnie.luau`, and
`FacingOffset = 180` turns her the right way (Import 3D turns models 180 degrees itself, on
top of `npc_glb.py --turn-y 180`; next time leave `--turn-y` off and use `FacingOffset = 0`).

## Bringing Bonnie in

1. **Import.** In Studio: File > Import 3D (or Avatar tab > Import 3D), pick
   `assets/source/npcs/Bonnie.ready.glb`. In the import settings:
   - Rig type: **Custom** / not R15 (she's a cat; skip anything about Avatar Setup).
   - Keep **Import animations** (or the animation option) on, so her 4 clips come with her.
   - Leave the scale unit alone; the game scales her to `Height` anyway.
   Import. You should get a Model with one MeshPart (`BonnieBody`) holding bones (Root,
   Pelvis, ... LidL, LidR, Tail1-4), usually with an AnimationController and an
   `AnimSaves` folder holding 4 KeyframeSequences: Idle, Sleeping, Loafing, Playing.
   If only one clip came in, see "One clip per file" below.
2. **Check.** She should be about 0.8 x 1.9 x 1.9 studs, standing, colored (white and grey
   tabby, amber eyes). The model should face -Z (the way a Part's front face points).
3. **Make the clip data** with `tools/npc_clips.py` (above); no uploads needed.
4. **Save the model.** Delete the `AnimSaves` folder from the model (not needed), rename the Model `Bonnie`, then right-click > Save to File, into this
   folder, as `Bonnie.rbxmx`. Delete the copy from the Workspace.
5. **Check her MeshId synced.** With Rojo running, look at
   ServerStorage.NpcModels.Bonnie.BonnieBody: MeshId must not be empty (if it is, move
   `Bonnie.rbxmx` out of this folder and back in).

## If something's off

- **Facing backwards** (rump toward the path): set `FacingOffset = 180` in her NpcConfig
  entry. No re-import needed.
- **Floating or sunk**: her feet sit `HIP` (PetService) below the root's bottom, which the
  Humanoid holds `HipHeight` off the ground; adjust `HIP` if her paws don't meet the plaza.
- **Walks into something**: add an `Avoid` circle to her `Wander` area (NpcConfig).
- **Eyes move the wrong way** (open when they should be shut): swap the signs of the `Lids`
  angles (`Open = 1.2, Shut = -1.45`); Studio may have flipped the lid bones' axes.
- **One clip per file**: if the importer only takes one clip, make a file per clip and import
  each the same way (keep just its KeyframeSequence):

      python3 -I tools/npc_glb.py assets/source/npcs/Bonnie.glb assets/source/npcs/Bonnie.Idle.glb --turn-y 180 --clip Idle

  (and `--clip Sleeping`, `--clip Loafing`, `--clip Playing`).
