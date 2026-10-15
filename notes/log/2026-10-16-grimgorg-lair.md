# Grimgorg's Lair: first dungeon and boss

2026-10-16 · not playtested (the Grimgorg model still needs importing in Studio)

## Asked
Put the Grimgorg boss (made in Claude Design, with 11 animation clips) into the game, in a
dungeon: fight through some orcs, then the boss in its own arena at the end. Loot comes later.

Decided with the user:
- **Private run per party**: each player (each party, once parties exist) gets their own copy.
- **Entrance**: a cave in the mountains at the north-west edge of the hunting grounds.
- **Death**: respawn in the entry hall, cleared rooms stay cleared; if nobody's left alive in
  the arena, the boss heals to full and the arena opens again.
- **Fight**: two phases plus an enrage.

## Changed
- [BossConfig.luau](../../src/shared/Config/BossConfig.luau): Grimgorg's stats, phases and attacks (timing, shape, damage, parryable or not, telegraph)
- [DungeonConfig.luau](../../src/shared/Config/DungeonConfig.luau): the lair's layout (hall, Guard Post with 3 orcs, War Camp with 5, round arena), the entrance spot, where runs are built (X 3000+, Y 300)
- [BossService.luau](../../src/server/BossService.luau): builds the rigged boss (like the pets: an invisible Humanoid root with the mesh welded on) and runs the fight (picking attacks, server-side hit checks at each blow, poise stagger, parry, phases, wipe reset)
- [DungeonService.luau](../../src/server/DungeonService.luau): the cave's Enter prompt, runs, rooms that seal and drop orcs, arena gate, respawn in the hall, ways out
- [DungeonBuilder.luau](../../src/server/DungeonBuilder.luau): the rooms, corridors, portcullis gates, torches, braziers, arena and the cave mouth, all built from parts
- [EnemyService.luau](../../src/server/EnemyService.luau): `spawnOnFloor` drops an orc onto a floor up in the sky (dungeon orcs give normal XP, coins and drops, and don't respawn)
- [EnemyEffects.luau](../../src/server/EnemyEffects.luau): bosses ignore weapon knockback, pull and stun
- [BossAnimator.luau](../../src/client/BossAnimator.luau): poses the boss's bones from the clip data
- [DungeonHud.luau](../../src/client/DungeonHud.luau): boss bar at the top, banners, red floor telegraphs, the beam, slam dust and camera jolt, knockback
- [RigClips.luau](../../src/shared/RigClips.luau): was client `PetClips`, moved to shared so the server can read clip lengths
- [EnemyClips/Grimgorg.luau](../../src/shared/EnemyClips/Grimgorg.luau): the clip data, generated from the .glb
- [npc_glb.py](../../tools/npc_glb.py): merges several meshes on one skeleton into one (Grimgorg's wings and tail are separate meshes)
- [npc_clips.py](../../tools/npc_clips.py): drops keys a straight line between their neighbours already gives (within 0.1°): Grimgorg's clips went from 570 KB to 133 KB
- ZoneBanner (dungeon name while in a run), EnemyHealthBars (no small bar on bosses), MapConfig ("Grimgorg's Lair" label), `DungeonEvent` remote, [assets/enemies/README.md](../../assets/enemies/README.md) (boss import steps)

## Fixed after the first try
- "Can't enter": the cave's opening was a solid black wall, and its "Enter" hint floated above its 16-stud top, easy to miss. Entering worked from the threshold. Now walking into the dark doorway takes you in, and the hint sits at eye height in the mouth.
- Dying sent you to town and ended the run: you respawn at the town spawn first, and the "left the run some other way" check saw you there before DungeonService moved you back to the entry hall. Members on their way back are now skipped by that check.
- The terrain climbs into the mouth (about 2 studs above the threshold just inside); fine for now.

## Choices (easy to change)
- Grimgorg: 17 studs tall, 3000 HP, Lv 8, 400 XP, 120 coins. All placeholders.
- Attacks (hit times measured from the clips' fastest hand or tail motion):
  - **Combo**: 3 blows in front (22/22/32), parryable, no telegraph
  - **Overhead**: slam 9 studs ahead (60 damage), telegraphed, can't be parried
  - **Tail swipe**: a spin all round (40 damage), used mostly when you're behind him; telegraphed after a 0.35 s pause
  - **Beam**: from phase 2, at players 24+ studs away; a 70-stud line (50 damage), telegraphed
- Phases: below 50% "furious" (shorter recovery, beam unlocked); below 20% "enraged" (20% faster).
- A stagger every 450 damage (2.4 s down), and from any parry. Hits of 45+ make him flinch between attacks.
- Rooms: walking in drops the gate behind you and the orcs come in from the far wall.
- Walk and run clip speeds (8 and 17 studs/s) are guesses: tune them if the feet slide.

## Open
- **Import the model**: steps in [assets/enemies/README.md](../../assets/enemies/README.md). Without it the arena is empty.
- Boss loot: [TBD], for later (user's call).
- Re-entry: no cooldown; the boss can be farmed. Decide whether it should have one.
- Party size and HP scaling with party size: still [TBD] (the run already takes a list of members).
- The cave's spot (-480, -862) hasn't been checked against the saved terrain; it's placed on the ground at runtime, so it may sit on a slope.
- The minimap has nothing to show inside a dungeon (it's off the map).
