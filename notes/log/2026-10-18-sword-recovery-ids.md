# The Sword recovery clips' IDs go in (main issue, step 1)

**Asked:** the user published SwordSwing1–3 (the recovery clips from
[[2026-10-17-sword-recovery-blend]]) and sent the IDs.

## What changed
- [CombatConfig](../../src/shared/Config/CombatConfig.luau) `Sword.Combo` (Emberfang and Mace use it too):
  | Clip | Old | New |
  |---|---|---|
  | SwordSwing1 (0.98 s) | 101378158511989 | 105789243194617 |
  | SwordSwing2 (0.96 s) | 100925354916925 | 125525200710497 |
  | SwordSwing3 (1.20 s) | 78373052274628 | 108194359632313 |
- [TrainingStands](../../src/server/TrainingStands.luau): the Emberfang stand uses the new SwordSwing3.
  `PoseAt` went from 0.5 to **0.38**. The clip is longer now (0.92 → 1.20 s), and 0.5 would land in
  the recovery. 0.38 × 1.20 = 0.46 s, the same moment just after the hit as before.
- Damage, hit timings and cooldowns didn't change.

## Checked
- `check_syntax.sh` passes. Studio (Rojo connected) has the new IDs, the 0.38 stand pose, Sword
  damage 33 and the loading screen, so the reconnect from the handoff is done.
- Not playtested (the user plays it).

## To check (user)
- A single Sword swing sinks and swings back into guard with no snap. A 3-hit combo flows.
- The Emberfang training stand still shows the slam just after it lands.

## Open
- If the Sword feels right: the Rapier gets the same recovery next (main issue step 1c).
