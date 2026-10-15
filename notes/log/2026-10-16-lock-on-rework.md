# Lock-on rework

2026-10-16 · not playtested

## Asked
The lock-on felt sloppy. Add switching to another enemy, make it more responsive, and change the
camera angle so the enemy is easier to see (to time parries; a clear view for ranged).

## Changed
- [LockOn.luau](../../src/client/LockOn.luau): rewritten
- [CombatConfig.luau](../../src/shared/Config/CombatConfig.luau): `LockOn` tuning (new `Melee` / `Ranged` groups)
- [design.md](../../docs/design.md): §12 Lock-on row; the Controller row mentions the stick flick

## How it works now
- **Switch target:** mouse flick sideways, right-stick flick, or a swipe across the screen. It picks the next enemy on that side.
- **Camera:** it orbits behind you and off to your right. The swing and the aim point are both eased, so there's no snapping, and locking on glides in over 0.22 s.
  - **Melee:** a wide two-shot (34° to the side) that shows the enemy's whole wind-up.
  - **Ranged or magic weapon:** beyond 10 studs it's tight over the shoulder, aimed at the target.
  - **Big targets** (over 6 studs tall) push the camera back and up.
  - **Walls** pull the camera in instantly.
- Hit and block shakes now show while you're locked on.

## Tuning
- `SwitchFlick` (110 px) sets how hard the mouse flick has to be.
- `Melee.*` and `Ranged.*` set the angle, distance, height and focus.
- `TurnSpeed`, `FocusSpeed` and `ZoomSpeed` set how quickly the camera follows.

## Open
- The tutorial's LockOn step doesn't mention switching yet.
