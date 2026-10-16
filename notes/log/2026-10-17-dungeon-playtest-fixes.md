# Dungeon playtest fixes, god mode, bigger orcs

**Asked:** "Can you run the playtest for the dungeon yourself? its all broken", then (mid-way)
a god mode in the admin panel for playtesting, and orcs about a player's size so they're
easier to read for parries and in Lock-On.

## What was broken
- **Decor and Working were moved as a whole.** While they were Models (before the Folder
  change in [[2026-10-17-dungeon-working-parts]]), a click selected the whole group, and the
  group had been turned 90° and shifted (one transform for both). Gates stood in the wrong
  corridors (the War Camp's sealed 140 studs from the War Camp), chests sat in rock, torches
  floated. Fixed in Studio by undoing that transform on every piece in both folders (worked
  out exactly from the gates' `Squares`; checked against a freshly generated copy). Hand edits
  made on top are kept. Now Folders, so it can't happen by one click again.
- **Pitch black.** The dungeon look was too dark to play outside torchlight. LightingConfig.Dungeon:
  Ambient 34,33,38 → 68,64,72; OutdoorAmbient → 52,50,58; ExposureCompensation -0.15 → 0;
  Atmosphere Density 0.42 → 0.3, Color → 52,49,56. Still dim and grim.
- **Wrong colour correction.** DayNight found effects by class, and LowHealthGrade (DamageFeedback)
  is also a ColorCorrectionEffect: the dungeon grade went onto it, and leaving a dungeon put the
  world grade on the low-health effect. Now found by name and class.

## Added
- **God mode** (AdminService "GodMode", admin panel button): toggles the player's `GodMode`
  attribute; a HealthService damage filter cancels all damage to an admin with it on. The
  panel's status line shows GOD MODE.
- **Orcs bigger:** EnemyConfig.Orc `Scale = 1.25` (5.2 studs tall, was 4.2), AttackRange 5 → 5.5.
  EnemyAnimations scales the walk/run clip speed by Scale so feet don't slide.

## Playtested (Studio, by Claude)
Entered through the cave mouth; gates on their squares (0.00 off), chests on their marks,
War Camp sealed with 5 orcs dropped. God mode on: 5 orcs for 10 s did no damage; off: dead in
5 s. Orcs 5.19 studs tall. Lighting checked by screenshot. Boss fight not played.

## Open
- Not checked: parry timing feel with the bigger orcs, Lock-On framing.
