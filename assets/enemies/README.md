# Enemy models

**Not synced by Rojo**: Avatar Auto Setup models carry instances Rojo's live sync can't make
(SurfaceAppearance, WrapTarget, FaceControls...), so it never built them and deleted ones added by
hand. `ServerStorage.EnemyModels` is left alone by Rojo instead and its models live in the saved
place: after changing a file here, right-click `ServerStorage › EnemyModels` > Insert from File
(and delete the old copy). These files are the source copies. Each enemy type uses the model named in its `Model`
setting in `src/shared/Config/EnemyConfig.luau`: the Orc uses `Orc.rbxmx`, the Lesser Demon
`LesserDemon.rbxmx`. Without one it's a plain R15 body in the enemy's color.

The model must be an **R15 character**: a Model with a `Humanoid` and a `HumanoidRootPart`
and the usual R15 body parts, so the walk, the attack animation, hit effects, and stuns all
work. A custom-skeleton model (like most downloaded characters) gets there with Studio's
Avatar Auto Setup:

1. Import 3D the prepared mesh, e.g. `assets/source/enemies/LesserDemon.ready.glb`
   (made by `tools/weapon_glb.py`: colors baked into a texture, facing -Z). Studio imports at
   most 20,000 triangles per mesh, so a heavier model is decimated first with `tools/decimate_glb.py` (the
   Lesser Demon went from 22,522 to 12,000, all parts joined, then `--turn-y 180`).
2. Avatar tab > Avatar Setup > select the imported model > Auto Setup (body type: humanoid).
3. Check it in the preview, then add it to the Workspace, rename it (e.g. `LesserDemon`), and
   right-click > Save to File, into this folder.

## Bosses (rigged, not R15)

A boss (`src/shared/Config/BossConfig.luau`) is different: its model keeps its own skeleton
(no Avatar Setup), and BossService/BossAnimator play the clips from the `.glb`'s own keys
(`src/shared/EnemyClips/<Name>.luau`), like the pets in `assets/npcs`. Grimgorg:

1. The source is `assets/source/enemies/Grimgorg.glb` (from Claude Design). Make the import
   file and the clip data from it:

       python3 -I tools/npc_glb.py assets/source/enemies/Grimgorg.glb assets/source/enemies/Grimgorg.ready.glb
       python3 -I tools/npc_clips.py assets/source/enemies/Grimgorg.glb src/shared/EnemyClips/Grimgorg.luau

   No `--turn-y`: Import 3D turns the model 180 degrees itself, which brings the file's +Z
   front round to -Z. (`npc_glb.py` merges its body, wing and tail meshes into one; they share
   one skeleton.)
2. In Studio: File > Import 3D, pick `Grimgorg.ready.glb`. Rig type **Custom** (not R15, even
   though its bones have R15 names; skip Avatar Setup). Leave animations on or off: they
   aren't used. You should get a Model with one MeshPart holding 22 Bones.
3. Rename the Model `Grimgorg`, delete any `AnimSaves` folder, move it into
   `ServerStorage › EnemyModels`, and right-click > Save to File into this folder as
   `Grimgorg.rbxmx` (the source copy).
4. If it walks backwards, set `FacingOffset = 180` in its BossConfig entry.

Without the model the dungeon still works, but the arena is empty (the server warns).
