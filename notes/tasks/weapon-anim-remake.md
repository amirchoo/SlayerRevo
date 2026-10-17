# Remake every weapon's animations in the new style (priority 0)

Opened 2026-10-18. The user, after the Sword combo redo and the exaggerated hit feel: "perfect, this is how
I imagine it would be… I want to remake all weapon animations again in this style… make this number 0
priority". **Say "do the animation remake" in a new session**: Claude reads this note and
[[animation-style]] (the recipe: look, tools, loop, fixes that worked), does the next unticked weapon
(one weapon per session or message), shows it in Blender with `combo.sh`, and stages it for publishing
when the user likes it. Then ticks it here with a link to its log note.

**Deadline: 2026-10-25** (the user's call on 2026-10-18: "a week max"). About 14 entries are left, so that's
**about 2 weapons a day**. Do the slow ones (Dual Blade, Bow, Crossbow, Blunderbuss, Staff/Grimoire need
new controls) early in the week so they can't push the date. If it's slipping by ~2026-10-23, tell the
user and offer to cut scope (simpler clips for the ranged/casting weapons) rather than rush the rest.

Priorities now: **0 this remake**, 1 the Arcane Atelier look ([[arcane-atelier-look]], next once every weapon
is done), 2 the perf pass ([[perf-polish]]), 3 the main issue ([[main-issue-dueling-vibe]]) and the
battlegrounds steps ([[battlegrounds-combat]]).

## For each weapon
- Port its clips from the old generator (`tools/<weapon>_anims.py`) to `tools/blender/<weapon>_clips.py`
  in the new style. Keep each clip's name and its hit time (= the weapon's HitDelay in CombatConfig), so
  the IDs and config stay; if a hit time has to change, change the HitDelay too and say so.
- Add the weapon to `tools/blender/weapon_model.py` (model file, tool Grip from WeaponService, ModelFit)
  and to `tools/blender/combo.sh` (clips and cooldowns), so the combo viewer shows the real model.
- The authoring controls are built for a weapon in the right hand (a two-handed grip works with
  `"offhand_space": "world"`). Weapons held or used differently (dual blades, bow, crossbow, guns, the
  staff's casting, the grimoire) may need new controls first: say so and plan it before posing.
- **Every weapon also gets a walk (carry) clip** (the user said yes, 2026-10-18): upper body only, played
  instead of the idle while moving; the weapon low and trailing so it looks heavy, like the Arcane Atelier
  video ([[arcane-atelier-reference]]). Name it `<Weapon>Walk`.
- **Armor clearance:** the AUTHOR report must show 0 `WEAPON IN BODY` (the real model vs an armored body,
  [log](../log/2026-10-18-guard-armor-clearance.md)). Open: re-pose SwordSwing2/3, which go through armor (ask).
- **Read [[weapon-animation-research]] first**: how each weapon really works and how to animate it.
- Ask before changing how a move plays (its timing, reach or what it does); the look is Claude's call
  within [[animation-style]].

## Weapons (the user may reorder; their own weapon, the Rapier, goes first after the Sword)
- [x] **Sword** combo: SwordSwing1–3 (+ Moving twins). [log](../log/2026-10-18-sword-combo-exaggerated.md).
  Published 2026-10-18 over the existing IDs.
- [x] **Sword** rest: SwordIdle (kept: the combo starts from it), SwordGuard, SwordSpin, SwordWalk
  (+ the idle ↔ walk switch, `WeaponWalk`). Published 2026-10-18; SwordWalk is 101807525981698 (Emberfang
  shares it) ([log](../log/2026-10-18-sword-rest-walk.md)).
  Emberfang reuses all of the Sword's.
- [ ] **Rapier:** RapierIdle, RapierThrust1–3, RapierWindUp, RapierFlurry.
- [ ] **Spear:** SpearIdle, SpearThrust1–3, SpearWindUp, SpearLunge.
- [ ] **Dagger:** DaggerIdle, DaggerSlash1–2, DaggerStab3–4, DaggerGuard, DaggerWindUp, DaggerBackstab.
- [ ] **Dual Blade:** DualBladeIdle, DualBladeSlash1–4, DualBladeGuard, DualBladeWindUp, DualBladeRush
  (a blade in each hand: needs left-hand weapon controls).
- [ ] **Scythe:** ScytheIdle, ScytheSlash1–3, ScytheGuard, ScytheReap.
- [ ] **Hammer:** HammerIdle, HammerPound, HammerSwing, HammerCrush, HammerGuard, HammerWindUp, HammerSlam.
- [ ] **Axe:** AxeChop1–3, AxeWindUp, AxeCleave.
- [ ] **Mace:** its own combo (it reuses the Sword's old swings, played slower), MaceWindUp, MaceSlam.
- [ ] **Greatsword:** GreatswordSwing1–3 and its finisher / charged slam.
- [ ] **Crossbow:** CrossbowIdle, CrossbowAim, CrossbowShoot, CrossbowReload.
- [ ] **Blunderbuss** (see its SingleShot config for the clips).
- [ ] **Bow** (see its config for the clips).
- [ ] **Staff** and **Grimoire** (casting; see their configs).
