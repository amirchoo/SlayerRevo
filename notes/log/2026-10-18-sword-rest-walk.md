# Weapon research, and the Sword's guard, spin and new walk (carry) clip

**Asked (2026-10-18):** "yes add the walk, do the animation remake. Before you actually do the animation
remake... research about each weapon type so you'll know how it works and how you can animate it with
more details."

## Research
[[weapon-animation-research]]: for every weapon, how it's really used (fencing lunge, spear thrust vs
"shoot", the hammer driven by the legs and hips, the scythe's pulling cut, the archery shot cycle, crossbow
spanning) and what that means in our style. It also covers what makes a weapon read heavy or light
(timing, follow-through, the head lagging the hands), and how the walk clips work. Sources linked in the note.

## Sword clips (tools/blender/sword_clips.py)
- **SwordGuard** (remade): the blade level across the chest, pointing left, edge out, the left hand bracing
  the flat; the chest turned and hunched behind it, breathing (1.6 s loop, upper body only).
- **SwordSpin** (remade): a low, wide whirl, the sword arm flung out with the blade level, the free arm out
  the other way, leaning in, the head looking where it turns. One turn per 0.5 s (= TickInterval). Keyed at
  every 60 fps sample (`spun()` turns the whole pose): with keys 30° apart the hand cut straight chords
  across the circle and the elbow wobbled (25 CORNERs); now 0.
- **SwordWalk** (new): the sword low in the right hand, the tip trailing behind just off the ground, the
  arm swinging with the steps and the blade a quarter cycle behind it, the chest counter-turning. Upper
  body only, 1.0 s = one walk cycle. The lag is keyed into the poses (overlap offsets don't wrap round a
  loop and would jolt at the seam).
- **SwordIdle** kept: the combo starts and ends in it (START is the idle, lowered), so it still fits.
- AUTHOR reports: 0 FLIPs, 0 CORNERs, nothing out of reach, no tip in the ground.

## Code
- `src/client/WeaponWalk.luau` (new): `mover()` (moving, with a 0.12 s delay on stopping so a tap doesn't
  flicker) and `sync()` (keeps a walk clip at the rate and phase of whichever default WalkAnim/RunAnim
  track has the most weight; snaps back if it drifts 5% of a cycle).
- `ComboWeaponClient`: loads `WalkAnimation`, swaps idle ↔ walk while the weapon is out (shield stance
  still wins), syncs it every frame; cleared on unequip and respawn.
- `CombatConfig`: `WalkAnimation` / `WalkPhase` on combo weapons; `Sword.WalkAnimation = ""` until
  published (Emberfang will share it).

## Open
- **The user publishes** SwordGuard and SwordSpin over their IDs, SwordWalk as a new asset; then its ID
  goes in `Sword.WalkAnimation` (and Emberfang's).
- **WalkPhase unchecked:** Studio wasn't open, so the default walk's keyframes weren't read; if the sword
  arm swings with the same-side foot, set `WalkPhase = 0.5`.
- Not playtested (skip-playtests rule).
