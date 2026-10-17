# Sword swings recover smoothly instead of snapping back (main issue, step 1)

**Asked:** the Sword still feels stiff: "it snaps back after done with the animation instead of
feeling smooth and somewhat realistic". Research how games, soulslikes most of all, animate swings.
The research is in [[sword-swing-animation]].

## What changed
- [tools/sword_anims.py](../../tools/sword_anims.py), SwordSwing1–3: a new **recovery**.
  - The follow-through hold is a little shorter (0.14 s instead of 0.18).
  - Then the spent blade **sinks and swings back on a curve**: ease into a low waypoint
    (`EASE_WHIP`: starts slow, picks up), then settle into the ready stance (`EASE_SETTLE`: leaves
    quickly, eases to a stop).
  - Swings 1–2 also **draw the back foot in** (`DRAW_IN_LEFT/RIGHT`).
  - Swing 3, the overhead slam, **levers the blade up out of the ground and rises off the knee**
    (`RISING`) before standing.
  - Times:
    | Swing | Return before | Return now | Clip length |
    |---|---|---|---|
    | 1 | 0.50 → 0.72 s, straight | 0.46 → 0.64 → 0.98 s, on a curve | 0.98 s |
    | 2 | 0.48 → 0.70 s, straight | 0.44 → 0.62 → 0.96 s, on a curve | 0.96 s |
    | 3 | 0.66 → 0.92 s, straight | 0.62 → 0.86 → 1.20 s, on a curve | 1.20 s |
  - **Hits are unchanged** (0.26 / 0.24 / 0.40 s), and so is the combo pace (Cooldown 0.55 /
    0.55 / 0.85). Chaining interrupts the recovery as before; the full recovery only plays when you
    stop attacking.
  - Checked: the largest joint turn between frames is the same as before (it's the strikes); the
    recoveries add no jumps.
- [ComboWeaponClient](../../src/client/ComboWeaponClient.luau), for **every combo weapon**:
  - `CHAIN_FADE` 0.15 s: a chained swing blends out of the last one (was a 0.05 s cut), so its wind-up grows out of the follow-through.
  - `END_FADE` 0.25 s: a swing nobody follows up blends into the idle as it finishes, instead of
    dropping out on its last frame. It follows the track's time, so a hitstop just delays it.
  - `SWING_FADE_IN` 0.08 s: the first swing from the idle.
  - This already smooths the currently published clips (all weapons), before the new Sword clips
    are published.
- [CombatConfig](../../src/shared/Config/CombatConfig.luau): **damage raised as the user decided**
  (back to the old damage per second, since the swings got slower in 1a-4):
  | Weapon | Before (hits 1, 2, 3) | Now |
  |---|---|---|
  | Sword | 20, 25, 40 | 33, 41, 65 |
  | Emberfang | 26, 32, 52 | 42, 52, 85 |
  | Mace | 25, 30, 55 | 40, 47, 87 |

## Done in Studio by Claude
- The three new clips are staged in **`Workspace.Rig.AnimSaves`** (SwordSwing1 0.98 s,
  SwordSwing2 0.96 s, SwordSwing3 1.20 s), ready to publish. The temporary import folder is
  deleted on disk and in Studio.
- ComboWeaponClient reached Studio and loads. **CombatConfig hadn't synced**: the Rojo server
  wasn't running any more. The user restarts it and reconnects.

## To do (user)
1. Restart `rojo serve` and reconnect the plugin (this also applies the streaming fix and the
   loading screen).
2. In the Animation Editor, load **SwordSwing1, 2 and 3** from the Rig's AnimSaves and publish each.
   Send the three IDs; they go in `CombatConfig` `Sword.Combo` (Emberfang and Mace reuse them),
   and SwordSwing3's in TrainingStands too.

## To check
- After a single swing, the blade sinks and swings back into guard. No snap.
- A 3-hit combo flows from one swing into the next, with no pop toward the guard between hits.
- Other weapons (Rapier, Spear, Axe…) also blend more smoothly at the end of a swing and between
  swings, even with their old clips.
- Hits still land on time; the Sword, Emberfang and Mace hit harder.

## Open
- If it works, the same recovery recipe goes to the other weapons (Rapier next, as the user uses it).
- Step-in root motion (research, "Ideas not used yet").
