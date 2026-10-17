# Blender animation preview: Claude can see the animations it makes

**Asked:** the user can't animate and makes everything with AI. They liked the idea of Claude
driving Blender (already installed: Blender 4.5 LTS) so Claude can check its own animations by eye
instead of only from numbers.

## What changed
- [tools/blender/preview_anim.py](../../tools/blender/preview_anim.py) and
  [tools/blender/preview.sh](../../tools/blender/preview.sh):
  `sh tools/blender/preview.sh assets/animations/<Clip>.rbxmx [more] [--views behind,side,front,top] [--fps 30]`
  - Runs Blender without a window. It builds our blocky R15 rig with the exact joint offsets and
    part sizes of `Workspace.Rig` (read in Studio), plus the sword (5.2 studs, held 11% from the pommel).
  - It plays the clip the way Roblox does: each pose eases (EasingStyle/Direction) toward the
    next keyframe that has that pose, and weight-0 placeholder poses are skipped.
  - It renders every frame from each camera. **behind** is our lock-on view; there are also side,
    front and top. Each frame is stamped with its time, and HIT on the hit marker. The blade tip's
    path is drawn as an orange line, so the swing's arc shows.
  - Output goes to `build/anim_preview/<Clip>/`: `<view>_sheet.png` (all frames, 8 across) and
    `behind.mp4` (real speed). `build/` is gitignored.
  - Speed: about 13 s for a 0.9 s clip from 3 cameras on the Intel Mac.
- `.gitignore`: `/build/`.

## Checked against Roblox
SwordSwing1 was played on the Rig in Studio (edit mode, `Animator:StepAnimations`, priority
Action4) and its joint angles were read every 1/30 s. They match the preview's to **0.1°**, every
frame. The first try didn't match, because the Animation Editor still had a clip playing on the
Rig that blended 50/50; a higher priority fixed that.

## What the first previews showed (the new katana Sword)
- **SwordSwing3 is wrong:** while cocked, the blade sticks out back-left and down instead of
  hanging behind the head, and **on the hit frame it points straight up**: the cut comes down after
  the hit. Then it's held low in front, hidden by the body from the lock-on camera.
- **SwordSwing1:** the wind-up wobbles: the tip makes a jagged loop off to the right before the
  cut.
- **SwordSwing2** reads as intended: cocked left, flat cut, held out to the right.

## Open
- Fix Swing 3 and Swing 1's wind-up using the preview (next step).
- Later: author the swings in Blender (real curves, IK) and export to the same .rbxmx files.
- Gotcha: `Animator:StepAnimations` in edit mode leaves test tracks in the Rig's playing list
  (at weight 0) until Studio restarts; they aren't saved with the place.
