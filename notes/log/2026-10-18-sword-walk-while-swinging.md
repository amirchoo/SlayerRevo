# Sword: the legs walk when you swing on the move (no more sliding)

**Asked:** "I don't think the feet are planted since I can still move while attacking and it looks
very ass." The swings animate the legs in a planted stance, but the Sword doesn't slow you, so
walking mid-swing slid the whole body across the ground with frozen legs.
**Decided by the user:** keep full movement; the legs walk while moving, and the full-body stance
and footwork play when standing still.

## What changed
- **Upper-body twins:** the Blender bake writes `<Clip>Moving.rbxmx` for clips marked
  `"moving_twin"` ([author_anim.py](../../tools/blender/author_anim.py), [sword_clips.py](../../tools/blender/sword_clips.py)):
  the same swing with only the upper body. The hips' turn is folded into the chest, so the upper
  body turns as far as before; the hips' sink is left out.
- **Uploaded by Claude** through Open Cloud (new `upload` command in [roblox_assets.py](../../tools/roblox_assets.py)):
  SwordSwing1Moving 88087903830218, SwordSwing2Moving 88649716388151, SwordSwing3Moving 79289853982811.
  So Open Cloud *can* create animations from our generated .rbxmx files (it can't overwrite or archive them).
- [CombatConfig](../../src/shared/Config/CombatConfig.luau): new optional `MovingAnimation` on combo
  moves; set for the Sword's three swings, and Emberfang reads the Sword's.
- [ComboWeaponClient](../../src/client/ComboWeaponClient.luau): a swing with a twin plays both, in
  sync. Standing still: full-body at weight 1, twin at 0.001. Walking: the reverse, so the legs come
  from the walk animation. It re-blends over `MOVING_BLEND` (0.15 s) when you start or stop walking
  mid-swing, and the twin stops with its swing (chain, end fade, heavy). Hitstop freezes both.

## Checked (short Studio playtest, Claude)
Logged the tracks' weights and the right hip joint every 0.1 s:
- Standing click: SwordSwing1 at 1.00, its twin at 0.00.
- Click while holding W: twin at 1.00, full-body at 0.00, and the hip joint moving with the walk
  cycle (8° → 57° → 10°): the legs walk.
- Letting go of W mid-swing: blends back to the full-body stance, then fades out at the end.
No errors in the output.

## Open
- Other weapons still slide if you walk while swinging; the same twin trick works for any clip
  that moves to the Blender rig.
- Not checked on the phone (add to the batched device check).
