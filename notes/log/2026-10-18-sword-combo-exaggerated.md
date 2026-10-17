# Sword combo redone, exaggerated like the battlegrounds video; Blender tools to watch it

**Asked:** redo Sword Swing 1 smoother with animation principles (two guides the user sent), then
"overexaggerate it so it looks flashy like the video", then "create a full animation combo so I can see
the whole thing", with the real sword model in Blender. Then stage it for publishing.

**The combo** (`tools/blender/sword_clips.py`, each cut a different way so 1 and 3 no longer look alike):
1. **Swing 1, forehand down-left:** the body coils ~56° back and leans away, blade cocked behind the
   shoulder; a long lunge (front foot ~2 studs out, hips ~0.9 down), ~60° of twist through the cut, the
   chest over the front knee, then a settle.
2. **Swing 2, backhand flat right:** from Swing 1's lunge the body whips ~65° round, the blade sweeps
   flat and wide to the far right.
3. **Swing 3, leaping two-handed slam:** both hands, deep crouch, tucked leap, the blade raised behind
   the head, a hang at the top, slam straight down into a deep squat.
Hit times unchanged (0.18 / 0.15 / 0.38 s), so CombatConfig's HitDelays still match. Edge leads each cut
0.84 / 0.98 / 0.92 (1 = square on).

**New in the authoring script** (`tools/blender/author_anim.py`), for every clip from now on:
- Overlapping action: per body-part key offsets (hips lead 2 frames, chest/feet 1, blade trails 1,
  free arm 2, head 3); on the hit key the hips, chest and sword land together (staggered there, the arm
  stuttered). Per clip: `"overlap"`, `"offhand_space"`, `"blend_in"`, `"sudden"`, and per-key per-part
  eases (`(t, pose, ease, {group: ease})`).
- The blade's aim is keyed as a rotation (it used to spin round in a frame on big turns); the free hand
  and both elbow poles ride with the chest between keys (they used to fall out of reach / flip when the
  body whipped round); flat curve handles next to holds.
- Checks printed every run: CORNER (sudden stops/starts/reversals), FLIP (one-frame spikes over 30°,
  never excused on the hit), elbow bend per key, which way the tip moves at the hit.

**Viewing tools:** `tools/blender/show.sh <Clip>` (one clip in Blender), `tools/blender/combo.sh Sword`
(the whole combo chained as the game chains it, with the real ShortSword.glb fitted as the game fits it
via `weapon_model.py`; a Blender file plus 60 fps and quarter-speed videos). A bug where the sword didn't
turn with the hand in the combo file (keyed Euler on a quaternion object) was found by the user and fixed.

**Staged:** the six clips (SwordSwing1–3 and their Moving twins) are in `Workspace.Rig.AnimSaves`; the
temporary import folder is deleted on disk and in Studio.

**Published:** the user wrote all six over the existing assets on 2026-10-18 (new revisions confirmed
through Open Cloud; IDs unchanged in CombatConfig `Sword.Combo`).

**Open:** a playtest in game. Known leftovers: Swing 1's knee snaps a little on the stamp (meant as a hard stamp); a couple
of mild stops at the ends of cuts. Next: slash crescents (battlegrounds step 4). Not playtested.
