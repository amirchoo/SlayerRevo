# Sword guard clipped through armor; the authoring tool now checks the real weapon against armor

**Asked (2026-10-18):** "check how the guards work for swords in playtest right now, the swords clip thru
the body. Fix it and when animating make sure to import the weapon models too so no issues will appear."

**Found (playtest, the user's character in full armor):** the guard held the blade ~1.2 studs in front of
the body, but the armor is much bulkier than the bare rig the clips are authored on: the chestplate is
2.26 × 2.22 × 1.39 studs (vs a 2 × 1.6 × 1 torso), the sleeves ~1.6-stud boxes round each arm, the
helmet/hat rises ~1.5 studs over the head. The blade ran through the chestplate (the chest was turned, so
its corner reached forward) and the left sleeve (the bracing forearm lay along the blade).

**Fix, the guard (`tools/blender/sword_clips.py`):** the blade 1.5 studs out with the chest square behind it,
leaning in for the reach; the left elbow drops under the blade so the forearm meets it from below.
Staged in `Rig.AnimSaves`; **the user publishes it over SwordGuard (82457273702146)**.

**Fix, the tool (`tools/blender/author_anim.py`, `clearance()`):** every baked sample, ~400 vertices of the
real weapon model (weapon_model.py, fitted in the hand as the game fits it) are tested against the body
with the measured armor boxes (`ARMOR`, shrunk to 85%: the meshes are rounder). Points within 1 stud of
a hand holding the weapon don't count against that arm. Prints `WEAPON IN BODY: <part> <times>, up to
<depth> (at <t>)`; under 0.1 studs counts as a graze. Each `*_clips.py` names its model with `WEAPON = ...`;
add the weapon to `weapon_model.WEAPONS` before authoring it. docs/animation-style.md: 0 WEAPON IN BODY
is now part of a clean clip.

**The published combo, checked (not changed):**
- SwordSwing1: the right sleeve 0.17 deep for 3 frames mid-cut (the trail covers it); grazes.
- SwordSwing2: the wind-up rolls the blade through the chestplate (0.30) and left sleeve (0.28).
- SwordSwing3: through the helmet/hat (0.67) at the top of the leap and as it comes down past the face;
  the right sleeve (0.44) for 2 frames as it gathers; the chestplate (0.28) in the squat.
- SwordSpin, SwordWalk: clear.
A first try at moving Swing 2/3's poses made the elbow flip and the arm lock, so it's put back: the combo
is the user's approved one. **Decided (the user):** keep them; hit VFX will hide it (like Arcane Atelier).

## Follow-up the same day: the armor itself
Research (classic clothing vs rigid accessories vs layered clothing) and every set measured in Studio: the
verdict and the per-set numbers are in [[armor-remake]]. **The user's plan:** low tiers mostly painted with
minimal 3D, more 3D as tiers rise; the armor remake comes right after the weapon remake (priority 1; the
Arcane Atelier look moves to 2, the perf pass 3, the main issue 4). **Players' own avatar accessories are no
longer put on** (hats, hair, face items: `AvatarService` clears them; checked in Studio that the
description empties).

Not changed yet: the other weapons' old guards (they're remade in the remake, now with this check).
Playtested: yes (the guard, as the user asked; posed with the guard track, measured in game).
