# Lock-on camera: duel framing (after Dueling Grounds)

**Asked:** research the Roblox game Dueling Grounds (animations, mechanics); copy its lock-on
camera framing, which the user liked from a screenshot.

## What changed
- [CombatConfig](../../src/shared/Config/CombatConfig.luau) `LockOn.Melee`: from a wide two-shot
  (Angle 34/18, Distance 11/15, Height 4.5, Focus 0.5/0.8) to a duel framing: nearly straight
  behind you and aimed at the target (Angle 12/8, Distance 9.5/11, Height 3, Focus 0.9/1). The
  target sits centre screen, you just left of centre below it. Ranged framing unchanged.
- Comments in [LockOn](../../src/client/LockOn.luau) and the config updated to match.
- Old values are above, if the wide shot is wanted back.

## Dueling Grounds notes (from guides; no developer sources found)
- 1v1 rounds, fighting-game HUD: mirrored health bars at the top, round pips, a centre-bottom
  posture (shield) bar, "Round 1" splash, cosmetic intro and death animations.
- Light (M1) / heavy (M2), L-L-L-H chain; a guard break triggers an automatic Finisher (stun),
  then the Ultimate (R) window. Tap F to parry (no posture cost, opens a counter), hold to block
  (drains posture). Dodge has i-frames and dash-attack follow-ups; jump attack = drop strike.

## Open
- Not playtested. No video analysis of their animations was possible (text sources only).
