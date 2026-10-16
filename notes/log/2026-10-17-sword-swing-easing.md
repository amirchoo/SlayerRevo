# Sword swings: whip, stop hard, hold (main issue step 1a)

**Asked:** improve swing animations toward the Dueling Grounds feel, weapon by weapon, with
the Sword first ([[main-issue-dueling-vibe]]).

## Why they felt flat
Every keyframe in our generated clips used the same easing (Cubic in-out). Every move, from
wind-up to strike to recovery, had the same gentle rhythm, so a strike never "snapped".
Swings also drifted straight from the follow-through to a neutral, arms-down pose, with no hold.

## What changed
- [sword_anims.py](../../tools/sword_anims.py): a key can now carry an easing,
  `(time, pose, ease)`, written as each Pose's EasingStyle and EasingDirection. The options:

  | Easing | Style | Use |
  |---|---|---|
  | `EASE_SMOOTH` | Cubic InOut | the default, unchanged for other clips |
  | `EASE_WHIP` | CubicV2 In | into the hit |
  | `EASE_SETTLE` | CubicV2 Out | wind-ups and follow-throughs |
  | `EASE_HOLD` | Linear | a held pose that barely creeps |

  CubicV2 is used because the old Cubic has In and Out swapped. Clips that don't set an easing
  come out exactly as before.
- SwordSwing1–3 now follow the pattern: settle into the coil, whip into the hit, carry through and stop
  hard, hold about 0.1 s, then recover to the ready stance (the swing's own start pose) instead of
  NEUTRAL.
  - Hit times are unchanged (0.15, 0.13, 0.27), so `HitDelay` still matches.
  - The clips run slightly longer: 0.42→0.50 s, 0.40→0.48 s, 0.70 s unchanged. The next swing
    still cuts in at its Cooldown.
- Emberfang and Mace play the same clips, so they get the new swings too.
- Only `assets/animations/SwordSwing1-3.rbxmx` changed. The other clips that this generator writes
  differed only by renumbered internal IDs and `-0` written for `0`, so they were restored and
  don't need re-publishing.

## Published
The user published new assets (2026-10-17): SwordSwing1 `104914800619644`, SwordSwing2
`138065173637024`, SwordSwing3 `89799472238550`. They're in `CombatConfig` Sword.Combo, which
Emberfang and Mace read from. The Training Grounds' Emberfang armor stand
([TrainingStands](../../src/server/TrainingStands.luau)) poses with SwordSwing3 at 0.45 s,
which is still the held crash lunge.

## Was to do (the user, in Studio)
- Publish the three clips. Put SwordSwing1-3.rbxmx on the rig's AnimSaves, open each in the
  Animation Editor, and publish it. **Overwriting the existing asset keeps the IDs** in
  `CombatConfig` Sword.Combo. If they're published as new assets, give the new IDs to Claude
  to put in the config.
- Playtest: does the strike snap, does the hold read without feeling sluggish, does the combo
  chain cleanly?

## Open
- Not playtested. The other weapons follow in steps 1b–1h of the main issue.
