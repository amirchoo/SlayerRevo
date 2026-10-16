# Performance audit (step 0 of the polish and performance pass)

**Asked:** make Slayer Revo look polished (Dueling Grounds-level) and run smoothly, with fast loading,
on a phone and an Intel Mac. Step 0: audit only, no changes. Part of [[perf-polish]].

Counted in Studio's edit mode by a read-only script (no playtest), plus a read of the code.
TriangleCount and the streaming radii can't be read from a plugin script, so they're missing.

## What's in the place

| Where | Instances | Parts | MeshParts | Unions | Lights (shadowed) | Emitters (particles/s) | SurfaceAppearances |
|---|---|---|---|---|---|---|---|
| workspace.World | 74,066 | **53,652** | 45,280 | 214 | 0 | 0 | **7,771** |
| workspace.Town | 7,995 | 6,989 | 576 | 603 | 42 (0) | 7 (21) | 4 |
| workspace.DungeonLayouts | 2,430 | 1,420 | 40 | 64 | 60 (4) | **240 (40,560)** | 0 |
| Other workspace clutter | ~1,600 | 343 | | | | | |
| ServerStorage (assets) | 16,710 | 2,076 | 752 | 171 | 7 | 5 | 201 |
| **Workspace total** | **86,527** | **62,409** | 45,911 | 885 | 102 (4) | 247 | 7,775 |

- **Every part casts a shadow:** 62,391 of 62,409.
- **World by asset:**

  | Asset | Count | Parts | Note |
  |---|---|---|---|
  | Tree | 953 | 35,261 | 37 parts per tree, only 2 distinct meshes |
  | PinkFlower | 40 | 7,800 | 195 MeshParts per clump, **7,320 SurfaceAppearances** |
  | TallGrass | 403 | 6,448 | 16 parts each |
  | Bush | 416 | 2,496 | |
  | Ruins, chests, bridges | | ~1,200 | |
  | Wildflower, HogWeed | 451 | 451 | each with a SurfaceAppearance |

- **Dungeon:** 48 wall torches with 5 emitters each (Fire1–3, Smoke, CandleLight) make the 240.
  The saved layout is taken out of the world when the server starts, but every run copies all of it back.
- **Clutter in Workspace that every client downloads:**
  - 7 Hammer KeyframeSequences (animation drafts)
  - a "Relaxed Scene" Sound (4 instances)
  - "Destroyed house" (327 parts)
  - the animation `Rig` (474)
  - a Model named "Terrain"
  - the 512-stud Baseplate under the ground
- **Lighting:** Future, GlobalShadows on, plus Bloom, SunRays, DepthOfField and ColorCorrection.
  DamageFeedback adds a second ColorCorrection and writes it every frame.
- **Streaming:** on (radii unread).
- **Server-moved characters:**
  - about 120 orcs (24 packs of 4–6)
  - about 84 wild animals (12 herds of 2–4 cows, 12 flocks of 3–5 chickens)
  - 9 town animals, 11 villagers, the pets and NPCs
  - so roughly 230 server-owned Humanoids, all moved with `Humanoid:MoveTo`
  - AI ticks: orcs 0.2 s, packs 0.3 s, animals 0.25 s, villagers 0.3 s, boss 0.1 s

## Per-frame connections (52 in code)

**Always running (24):**

| Script | Event | What it does each frame | Cost |
|---|---|---|---|
| TownAmbience | RenderStepped | sets CFrames on swaying cloth (within 180 studs), pivots the windmill, flies bird flocks | **high in town** |
| AnimalAnimator | PreSimulation | poses legs, heads, wings and tails in Lua (within 160 studs) | **high** (84+ animals) |
| VillagerAnimator | PreSimulation | poses joints in Lua (within 150 studs) | medium |
| PetAnimator | PreRender | poses joints in Lua (within 150 studs) | low–medium |
| BossAnimator | PreRender | poses joints (within 400 studs) | low (1 boss) |
| CookingPose | PreSimulation | poses everyone who is cooking | low (usually empty) |
| LootClient | RenderStepped | `PivotTo` on every floating drop | low–medium |
| Map | RenderStepped ×2 | minimap and creature markers (the big map only while open) | medium |
| DamageFeedback | RenderStepped | writes the low-health vignette and colour grade, even at full health | low, but wasted |
| EnemyHealthBars | Heartbeat | picks bars every 0.2 s | low |
| PlayerLight | Heartbeat | picks lights every 0.25 s, fades | low |
| DayNight | Heartbeat | lighting every 0.1 s | low |
| Soundscape | Heartbeat | where you are every 0.5 s, music fades | low |
| Dash, Crosshair, CookingPanel, QuestPanel, DungeonHud, Dialogue, TutorialClient, Gamepad | Heartbeat/RenderStepped | small HUD updates | low |
| StaffClient | Stepped | staff hand aim (only if AimWithHand) | low |
| LockOn | BindToRenderStep | camera (returns early when not locked) | low |

**Only while something is happening (about 28):**
- swings, aiming and charging in ComboWeaponClient, Greatsword, Bow, SingleShot and Staff
- DashEffects (poses joints during a dash)
- hit effects
- cutscene cameras (Intro, Tutorial, PetCutscene)
- the panels' distance watches
- the server's Projectile and StaffService projectiles

## Built at runtime

| Builder | What it builds | When |
|---|---|---|
| TownBuilder | **nothing**: workspace.Town is saved in the place, so `build()` returns at once | startup |
| WorldBuilder | **nothing**: workspace.World is saved, so `build()` returns at once | startup |
| DungeonService | reads the saved layout (copies its terrain region, clears it, destroys the folder) and wires up the saved cave mouth | startup |
| DungeonService | each run copies the layout: terrain paste, Decor (48 torches, 240 emitters, 58 lights) and Working | entering the lair |
| TrainingGround | the arena, dummies, pads, summon button, sparring orcs | startup |
| TestChest | the chest and its prompt | startup |
| TrainingStands | 11 mannequins in armor, posed (yields) | startup, pops in |
| ClassHall | the Hall of Oaths floor and 10 statues in armor (yields) | startup, pops in |
| NpcService, PetService, VillagerService, AnimalService, EnemyService | NPC rigs (HumanoidDescription), pets, villagers, about 90 animals, 24 orc packs | startup and respawns |
| LeaderboardService | the board's SurfaceGui | startup |
| Client TownAmbience | bird flocks, ambient sound emitters | after join |

So Step 3's town and forest baking is **already done** (the tools/ generators build them in
edit mode and the place saves them). What's left to bake:
- the training ground
- the stands
- the Hall of Oaths
- NPC rigs (optional)

## Startup loads
- `Sounds.preload()` on join fetches all about 70 sound effects (music isn't preloaded).
- Each weapon client preloads its animations when the weapon is first used.
- ReplicatedFirst is empty: no loading screen, so the player drops in while the world is still streaming.

## Top 10 costs

### Phone
1. **World part count**: 53.6k parts and 45k MeshParts, mostly 953 trees at 37 parts each. That means
   draw calls, memory and streaming time.
2. **PinkFlower's 7,320 SurfaceAppearances**: PBR textures on tiny petals. On a phone that's mostly
   memory (crash risk) and texture loading.
3. **Dungeon torches**: 240 emitters asking for about 40,000 particles/s, plus 58 lights, in every run.
4. **About 230 server-moved Humanoids**: their position updates fill the network, and far ones still replicate.
5. **Lua joint posing every frame**: animals, villagers and pets, plus TownAmbience's cloth and birds.
6. **Post effects**: DepthOfField, SunRays and Bloom are full-screen passes, costly on mobile GPUs.
7. **Shadow casters**: all 62k parts cast shadows (phones drop shadow quality but still pay for some of it).
8. **Join load**: 70 sounds preloaded alongside world streaming, and no loading screen.
9. **Workspace clutter**: animation drafts, the Rig, Destroyed house, a stray sound, the Baseplate.
10. **Town**: 603 unions and 42 PointLights lit at night (unions are heavier than plain parts to stream).

### PC (Intel Mac integrated graphics)
1. **Future lighting with 62k shadow casters**: the shadow pass is the main GPU cost.
   Its light swapping is the flicker reported earlier.
2. **Lights at night and in dungeons**: 42 in town, 58 per dungeon run, 8 PlayerLights, and hit lights
   (Future shades all of them per pixel).
3. **World part and mesh count**: draw calls, as on the phone.
4. **The dungeon's 40k particles/s.**
5. **Post effects**: DoF and SunRays.
6. **7.7k SurfaceAppearances**: texture memory and bandwidth.
7. **Lua joint posing**: animals, villagers and town scenery.
8. **About 230 replicated Humanoids**: stutter on far enemies.
9. **Unions in the town.**
10. **Join load**: sound preloads, and no loading screen.

## Open
- No changes made. Next is Step 1 (quality tiers), after the user's OK.
- Damage decision recorded in [[main-issue-dueling-vibe]] (raise Sword, Emberfang and Mace back to the old damage per second);
  not applied yet.
- Not playtested (audit only).
