# Animations authored in Blender: IK rig, real curves; Sword swings 1–3 redone with it

**Asked:** "let's do the animation in Blender now" (the open item from
[the preview log](2026-10-18-blender-anim-preview.md): author the swings in Blender with real
curves and IK, and fix Swing 3 and Swing 1's wind-up).

## What changed
- [tools/blender/author_anim.py](../../tools/blender/author_anim.py) and
  [tools/blender/author.sh](../../tools/blender/author.sh):
  `sh tools/blender/author.sh SwordSwing1 [more] [--no-preview] [--views behind,side,top]`
  - Builds an armature on the preview's R15 rig (same joint offsets, so what bakes is what plays).
  - **Controls instead of joint angles:** the sword is a grip point plus a blade-tip point (Damped
    Track) and an edge point (Locked Track); the right arm reaches it by IK, the hand copies its turn.
    The left wrist, both feet (IK, so planted feet stay put), the hips, chest and head are keyed too.
    Elbows and knees bend toward pole points (pole angles are calibrated automatically).
  - Each control follows Blender f-curves between keys: `smooth` (Bezier), `in` (whip into a hit),
    `out` (settle), `inout`, `linear` (held).
  - Bakes 60 samples a second (plus the key and hit times) into `assets/animations/<Clip>.rbxmx`,
    Linear between samples. Saves `build/anim_author/<Clip>.blend`, then runs the preview.
  - It prints a check per key: GRIP / LEFT HAND / FOOT OUT OF REACH, TIP IN THE GROUND, and at the
    hit the tip speed and how squarely the edge leads the cut.
  - Gotcha: Blender's IK can't bend a dead-straight chain, so the legs start from a slight knee bend.
- [tools/blender/sword_clips.py](../../tools/blender/sword_clips.py): SwordSwing1–3 as poses. The
  chain still holds: swing 2 starts from `S1_HELD`, swing 3 from `S2_HELD`, and every swing starts
  and ends at the idle's upper body (read off the published SwordIdle) with the hips sunk 0.15.
  Lengths and hit times are unchanged (0.90/0.88/1.20 s, hits 0.18/0.15/0.38), so CombatConfig
  doesn't change.
- `tools/sword_anims.py` still writes the other sword clips (idle, guard, spin). **Don't re-run it
  for SwordSwing1–3**, or it overwrites these.

## What the previews show
- **Swing 1:** the wind-up is one clean arc up beside the shoulder and over, with no jagged loop.
  The left foot steps forward into the cut (a real step: the foot lifts and plants). Tip speed at
  the hit is 265 studs/s; the edge leads it (0.80).
- **Swing 2:** rolls over, cocks across the left side, cuts flat out to the right (edge 0.99).
- **Swing 3:** cocked with the blade hanging behind the head; it comes **over the top before the
  hit**, and on the hit frame it points forward and a little down (it used to point straight up).
  It ends deep in the step with the blade straight out to the left, so the lock-on camera sees it
  (before, it was hidden behind the body).
- Feet no longer sink into the ground or slide (the old clips had them at -0.1).

## Done in Studio by Claude
SwordSwing1, 2 and 3 are in `Workspace.Rig.AnimSaves` (replacing the old ones there); the temporary
import folder is deleted on disk and in Studio.

## To do (user)
Publish SwordSwing1, 2, 3 from the Animation Editor and send the three IDs. Claude puts them in
`Sword.Combo` (Emberfang follows) and Swing 3's in TrainingStands.

## Open
- Not playtested.

## Publish timed out (fixed)
The first bake was 0.5–0.65 MB per clip and the user's publish timed out. The bake now thins
keyframes: a sample is dropped when the Linear blend between its neighbours lands within 1.5° (and
0.02 studs for the hips) of it (`THIN_ANGLE` / `THIN_MOVE`). Holds thin out and fast cuts keep
every sample: 38/32/44 keyframes, 307/258/355 KB, about the size of the old clips that published.
Re-staged in `Workspace.Rig.AnimSaves`.

## Fewer animation assets
Publishing as new makes a new asset (and ID) every time. Publish over the existing one instead
(in the publish dialog, pick the clip's current asset to overwrite). The ID stays the same, so
CombatConfig needs no change. Old unused assets can be archived on the Creator Dashboard.
Current IDs: SwordSwing1 90592657091699, SwordSwing2 99968467521543, SwordSwing3 98009756362330.
- The idle, guard, and the other weapons can move onto the Blender rig one at a time (Rapier next).
