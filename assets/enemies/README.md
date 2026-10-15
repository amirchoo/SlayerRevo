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
