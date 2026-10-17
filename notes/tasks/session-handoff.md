# Handoff: start here next session

Written 2026-10-18 at the end of the session (the user: "lets do it on another session").
**Say "read the handoff" (or "continue") in a new session**: Claude reads this note first, then
the notes it points to. Update this note at the end of every session.

## Priorities (the user's order, 2026-10-18)
0. **Weapon animation remake, deadline 2026-10-25** (~2 weapons a day; the user: "a week max"; if it slips
   by ~10-23, say so and offer to cut scope, e.g. simpler ranged/caster clips). Say **"do the animation
   remake"**. Checklist [[weapon-anim-remake]], recipe [[animation-style]], research
   [[weapon-animation-research]].
1. **Armor remake** ([[armor-remake]]): low tiers mostly painted with minimal 3D, more 3D as tiers rise;
   weapons' paths kept clear. First step: decide each set's tier with the user. ("do the armor remake")
2. **The Arcane Atelier look** ([[arcane-atelier-look]], breakdown [[arcane-atelier-reference]]): bright
   painterly world, big hit VFX, ornate HUD. (Claude asked whether 1 and 2 should swap; no answer yet.)
3. **Perf pass** ([[perf-polish]], [[perf-polish-handoff]]): built; re-check on a weak phone.
4. **Main issue** ([[main-issue-dueling-vibe]]) and the battlegrounds steps ([[battlegrounds-combat]]).

## The animation remake: where it is
- **Sword: done.** Combo (Swing1-3 + Moving twins), SwordGuard, SwordSpin, SwordWalk (new,
  `rbxassetid://101807525981698`, also on Emberfang), SwordIdle kept.
  - **SwordGuard was re-posed clear of armor and is staged in `Rig.AnimSaves`: the user still has to
    publish it over 82457273702146** (ask if they did). The first published version clipped the chestplate.
  - SwordSwing2/3 go through bulky armor for a few frames: **kept** (the user: effects will hide it).
- **Next: the Rapier** (RapierIdle, Thrust1-3, WindUp, Flurry + RapierWalk). Its research section: arm
  extends before the body in the lunge, side-on body, free arm thrown back; walk light and bouncy, tip up.
  Then Spear, Dagger, Dual Blade (needs left-hand weapon controls), Scythe, Hammer, Axe, Mace, Greatsword,
  Crossbow, Blunderbuss, Bow, Staff/Grimoire.
- **For every weapon, keep in mind** (all in [[animation-style]] "Every weapon, every clip"):
  - **Armor:** the AUTHOR report's `WEAPON IN BODY` check (real weapon model vs an armored body) must be
    clean; add the weapon to `tools/blender/weapon_model.py` WEAPONS (model .glb, Grip from WeaponService,
    ModelFit) and `WEAPON = "<Weapon>"` in its `*_clips.py` before authoring.
  - **Effects:** hit VFX will cover the cut, so make the wind-up and end poses clear and the arc clean.
  - **Walk clip** per weapon (`<Weapon>Walk`, time 0 = left foot ahead) + `WalkAnimation` in its config.
    Only `ComboWeaponClient` plays walks so far; other weapon clients need the `WeaponWalk` hook.
  - **No preview videos for the user.** Stage in `Rig.AnimSaves` (temp `src/server/AnimImport/`, delete it
    on disk and in Studio after), give the table of clips and asset IDs to publish over.

## Other changes this session (2026-10-18)
- Players' own avatar accessories (hats, hair, face items) are no longer worn: only the game's armor
  (src/server/AvatarService.luau). Not playtested yet: the user's fedora/shades should be gone.
- `WeaponWalk` syncs walk clips to the real feet (works with any walk/run or animation pack).
- The Arcane Atelier video was analysed ([[arcane-atelier-reference]]).

## Not playtested yet
The new Sword walk in game (does the arm swing with the right foot?), the re-posed guard (after it's
published), the avatar-accessory change, plus the earlier ones in [[perf-final-check]].

## Claude's first moves next session
1. Ask whether SwordGuard was published, and whether the Arcane Atelier look and the armor remake should
   swap places.
2. On "do the animation remake": read [[animation-style]], [[weapon-animation-research]] (the weapon's
   section) and [[weapon-anim-remake]], then do the Rapier.
3. Before any Studio work, check Studio is open and Rojo is connected.

## How the user wants to work (keep to it)
- Explain, do, log it in `notes/log/`, tick it, push to origin/main.
- No preview videos or screenshots unless asked (they cost the user tokens); no playtests unless asked.
- No per-step phone checklists: Claude checks each step itself; device checks go into [[perf-final-check]].
- The baseline device is an average/low-end Roblox phone, not the user's iPhone 14.
- The user can't animate: Claude authors every clip; the user watches in Studio and publishes.
- The user's Roblox account is **ColePalmer6954**.

## Gotchas
- Authoring: a loop's first and last keys never move with overlap, so overlap offsets jolt a loop's seam:
  key any lag into the poses. A full-turn spin needs a key on every 60 fps sample (`spun()` in
  sword_clips.py) or the hand cuts straight chords across the circle.
- Reading a default walk's KeyframeSequence can't tell which foot leads (Pose CFrames are in each joint's
  own frame); `WeaponWalk` measures the real feet instead.
- In a playtest, the game's camera script overrides `CurrentCamera`; to look at the character, bind a
  RenderStep after `Enum.RenderPriority.Last` and unbind it after.
- New Studio has no `Lighting.Technology`: ShadowMap = `LightingStyle` Realistic +
  `PrioritizeLightingQuality` off.
- Scripts can't set Workspace streaming properties; they come from `default.project.json` (a changed
  project file needs a Rojo reconnect).
- To move a test character in a playtest, move it from the client.
- `rbxassetid://203785492` in the Output is a Studio plugin's sound: ignore it.
- The old generators (`tools/<weapon>_anims.py`) rewrite other clips with renumbered IDs: `git checkout --`
  what you didn't mean to change.
- Blender: objects imported from a .glb turn by quaternion; keying `rotation_euler` does nothing.
- To confirm a publish, read the asset's latest revision time through Open Cloud and compare with staging.
