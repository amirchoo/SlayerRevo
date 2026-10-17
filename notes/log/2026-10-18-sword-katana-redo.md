# Sword combo and idle redone katana-style, after Dueling Grounds (main issue, step 1)

**Asked:** "redo the whole animation for the sword, make the combo a bit more fresh and make it
in the way Dueling Grounds works for it."
**Decided by the user:** keep 3 hits; redo the combo **and the idle**; Emberfang keeps sharing
the Sword's swings, the Mace doesn't.

## What the recording showed
Frame by frame, from `~/Downloads/ScreenRecording_10-17-2026 04-08-16_1.MP4` (15 fps sheets, 2–28 s):
- **The combo is a chain.** Each cut ends where the next one starts; nothing goes back to a ready
  stance between hits. The held end pose (about 0.3 s) is the pause between hits. Ours went back
  toward ready every time, which is why it felt stiff.
- **The wind-up is a flick:** the blade stands up beside the right shoulder for one frame (about
  0.07 s), then crosses the whole arc in one or two frames.
- **Order:** forehand diagonal down to low left → flat backhand out to the right → overhead (arm
  high, blade cocked behind the head, held about 0.25 s) cut diagonally down. A backhand followed,
  but we keep 3 hits.
- **Feet planted** in a low, wide stance; the hips and chest do the turning. No jumps.
- **Idle:** one hand low by the right hip, blade angled up and forward, left arm loose.

## What changed
- [tools/sword_anims.py](../../tools/sword_anims.py):
  - **SwordIdle** (new, looping, upper body only so the legs walk): `IDLE_UPPER`.
  - **SwordSwing1** (0.90 s, hit 0.18): flick up beside the shoulder (0.08), whip down across to
    low left (`S1_END`), hold to 0.50 (`S1_HELD`), then back to the idle through a low point.
  - **SwordSwing2** (0.88 s, hit 0.15): starts at `S1_HELD`, the wrist rolls the blade over the
    top, cocks across the left side, cuts flat out to the right (`S2_END`), holds to 0.48.
  - **SwordSwing3** (1.20 s, hit 0.38): starts at `S2_HELD`, raises the blade cocked behind the
    head (0.13), holds to 0.31, cuts diagonally down into a deep step (`LOW_CUT`), holds to 0.75,
    rises back to the idle.
  - New footwork: `SHIFT_LEFT/RIGHT` (weight shifts, not lunges), `OVERHEAD_COIL`, `LOW_CUT`.
  - **No seams:** the held poses fix their blade twist (`plane_lean`), so the next swing starts
    from exactly the same pose. On the way back, each recovery passes a low point whose twist is
    `halfway` between the held pose and the idle, so neither half of the turn can flip.
    Checked: every recovery turns at most about 48° per 1/30 s sample; the only fast turns are
    the flicks at the start of each swing (under 120°, so they can't flip).
- [CombatConfig](../../src/shared/Config/CombatConfig.luau): the **Mace** is pinned to the
  current swing and idle IDs, so it keeps them when the Sword changes.
- Not changed yet: the Sword's IDs and HitDelays (0.26/0.24/0.40 → **0.18/0.15/0.38**, Emberfang
  too) go in together with the published IDs, so the hits match the clips. Cooldowns (0.55/0.55/0.85)
  and damage stay the same.

## Done in Studio by Claude
- SwordIdle, SwordSwing1, 2 and 3 are in **`Workspace.Rig.AnimSaves`**, ready to publish
  (replacing the old Swing1–3 there). The temporary import folder is deleted on disk and in Studio.

## To do (user)
Publish **SwordIdle, SwordSwing1, SwordSwing2, SwordSwing3** in the Animation Editor and send the
four IDs. Claude then puts them in `Sword` (IdleAnimation and Combo, with the new HitDelays) and
in Emberfang, and the TrainingStands Emberfang pose (PoseAt about 0.37, just after the slam).

## To check (after the IDs are in)
- The idle: blade low and angled up and forward, one-handed.
- Hit, hit, hit flows: each cut leaves from where the last one stopped, with a short hold between.
- A single swing goes back to the idle smoothly, with no snap or twist.
- Hits land on time (the hit is earlier than before: about 0.15–0.18 s for the first two).
- The Mace looks and plays exactly as before.

## Open
- If the timing feels too quick or too slow: the hold lengths (`S1_HELD` at 0.50, `S2_HELD` at
  0.48) and the Cooldowns in CombatConfig set the rhythm.
- The guard (SwordGuard) wasn't changed; it may want to match the new stance later.
- Rapier next if the Sword feels right.
