# Enemy models

Synced to `ServerStorage.EnemyModels`. An enemy uses the model named in its `Model` setting
(see `LESSER_DEMON` in `src/server/EnemyService.luau`), e.g. `Orc.rbxmx`. Without one it's a
plain R15 body in the enemy's color.

The model must be an **R15 character**: a Model with a `Humanoid` and a `HumanoidRootPart`
and the usual R15 body parts, so the walk, the attack animation, hit effects, and stuns all
work. A custom-skeleton model (like most downloaded characters) gets there with Studio's
Avatar Auto Setup:

1. Import 3D the prepared mesh, e.g. `assets/source/enemies/Orc.ready.glb`
   (made by `tools/weapon_glb.py`: colors baked into a texture, weapon removed, facing -Z).
2. Avatar tab > Avatar Setup > select the imported model > Auto Setup (body type: humanoid).
3. Check it in the preview, then add it to the Workspace, rename it `Orc`, and
   right-click > Save to File, into this folder.
