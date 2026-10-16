# Lock-on framing up close; orcs die whole

**Asked:** the lock-on is still bad with enemies close (most of the time): your own body and
weapon hide the enemy, so you can't read its animation to time a parry. And stop orcs breaking
into pieces when they die.

## Lock-on up close
- Cause: the duel framing ([[2026-10-17-duel-lock-on-camera]]) sat only 12° round and 3 studs
  above your chest, so a near enemy lined up right behind your back and weapon.
- Now (Dueling Grounds does the same) the camera is **high** up close, so the enemy shows
  above your head, and further round to your right, so it's clear of your body and weapon.
  It blends to a lower camera, nearly straight behind you, as the target gets further away.
- [CombatConfig](../../src/shared/Config/CombatConfig.luau) `LockOn.Melee`: Angle 12→28,
  FarAngle 8→10, Distance 9.5→11, FarDistance 11→12, Height 3→7, new FarHeight 3.5 (Ranged got
  FarHeight = its Height, unchanged). [LockOn](../../src/client/LockOn.luau) blends height by
  distance like the others.
- Rough check of the numbers: with the enemy 4 studs away, it sits ~7° right of and ~7° above
  your chest on screen, with your head below its chest.

## Orcs die whole
- Cause: enemies kept Roblox's default `Humanoid.BreakJointsOnDeath` (animals and bosses
  already turned it off).
- [EnemyService](../../src/server/EnemyService.luau): it's off now; on death the body stops its
  animations, tips over onto its side (anchored, 0.45 s), lies there, and fades out over the last
  0.8 s of its RespawnDelay before being cleared (and respawned, for single enemies), like
  animals do.

## Open
- Not playtested. If up-close is now too high or too far round, lower `Melee.Height` or
  `Melee.Angle`; if the enemy still hides behind big weapons, raise them.
