# Handoff: polish and performance pass (continue from here)

Written 2026-10-17 at the end of the session that did steps 0–2 of [[perf-polish]].
**Say "continue the perf pass" in a new session**: Claude reads this note and [[perf-polish]], then
proposes the next step.

## How the user wants to work
- **One step per message:** explain what will change, **wait for the user's OK**, do it, then:
  - log it in `notes/log/`
  - tick it in [[perf-polish]], `notes/log/README.md` and `notes/backlog.md`
  - commit and push to origin/main
  - list exactly what to check on the **phone and the PC** (FPS with Shift+F5, load time, flicker, stutter)
- **No Studio playtests or screenshots** unless asked. Read-only `execute_luau` counts in edit mode
  are fine (that's how the audit counted).
- **The baseline device is the user's iPhone 14.** The Intel Mac is secondary. Judge everything on the
  phone first. Build the look so Medium tier looks polished; High only adds extras.
- **Auto mode** is set for new sessions in `.claude/settings.local.json` (git-ignored).

## State
- All work is committed and pushed. Last commit: `3fa118b`.
- **Waiting on the user (Studio):**
  - set **Lighting → Technology → ShadowMap**, then publish (scripts and Rojo can't set it)
  - playtest steps 1 and 2 on the phone and the Mac (checklists at the end of each log)
- [x] 0. Audit ([log](../log/2026-10-17-perf-audit.md)). Counts, the top 10 costs, and what's built at startup.
- [x] 1. Quality tiers ([log](../log/2026-10-17-quality-tiers.md)).
  - [Quality.luau](../../src/client/Quality.luau) and [QualityConfig.luau](../../src/shared/Config/QualityConfig.luau).
  - Read the tier with `Quality.settings()` / `Quality.onChange`.
  - The console prints `[Quality] <tier> (<why>)`.
  - The admin panel can pin a tier.
- [x] 2. ShadowMap and the art-direction pass ([log](../log/2026-10-17-shadowmap-art-direction.md)).
  - LightingConfig day, night and dungeon fog, plus grade.
  - DayNight blends the night fog.
  - Phones at graphics 8+ get High.

## Next: step 3 (proposed, not yet OK'd)
The town (`workspace.Town`) and forest (`workspace.World`) are **already saved in the place**:
TownBuilder and WorldBuilder return at once when a saved copy exists. What's left:
1. **TrainingGround:** bake the arena, dummies, pads and button into the place. The server only wires
   up their behaviour (dummy health reset, pads, summon button, sparring orcs).
2. **TrainingStands (11 mannequins) and ClassHall (Hall of Oaths, 10 statues):** they pop in after
   join. Bake them as finished models; their prompts and choice logic stay in code.
3. **Dungeon layout:** `DungeonBuilder.loadLayout` copies the saved terrain region at server start,
   clears it, and destroys `workspace.DungeonLayouts`. Instead, keep the layout out of Workspace
   (for example in ServerStorage plus a saved TerrainRegion), so it never streams to clients and
   startup is lighter.
4. **Clutter in Workspace:**
   - delete or move: the 7 `Hammer*` KeyframeSequences, the "Relaxed Scene" Sound,
     the Model named "Terrain", and the Baseplate under the ground
   - **keep the `Rig`** (the Animation Editor needs it for publishing; see the memory
     "Loading and publishing animations")
   - **"Destroyed house": ask the user** whether to delete it or keep it for the world (the question was asked, not answered yet)
- Keep the generators as tools for rebuilding.

## Steps after that (from [[perf-polish]])
4. **Streaming and density:** streaming radii (Studio can't read them from a plugin script, so check in the
   Properties panel), fog to hide distance, ModelStreamingMode on big models, fewer trees and bushes on Low.
   - The biggest costs: 953 trees at 37 parts each, and **PinkFlower's 7,320 SurfaceAppearances** (40 clumps).
5. **Lights and particles:**
   - The dungeon runs copy 48 torches with 5 emitters each (240 emitters, about 40,000 particles/s).
     Quality already scales their Rate, but cut the emitters themselves.
   - Only a few strong lights.
   - PlayerLight is already tiered (2/4/8).
6. **Animation:**
   - Joint posing in code every frame in DashEffects, StaffClient, CookingPose, VillagerAnimator,
     AnimalAnimator and PetAnimator.
   - Make HitFeel's hitstop always restore track speed (it currently skips tracks that stopped or
     were changed mid-freeze).
   - Check animation priorities and fades.
7. **Enemies:** about 230 server-moved Humanoids (orcs, animals, villagers). AI ticks: 0.2, 0.25, 0.3.
   Update far ones less often.
8. **Loading:**
   - `Sounds.preload()` fetches about 70 sounds on join.
   - ReplicatedFirst is empty: add a short loading screen.
   - Load far content later.

Small leftovers found on the way:
- DamageFeedback rewrites its colour grade every frame even at full health.
- The admin panel needs the `` ` `` key, so it can't be opened on a phone.

## Separate: main issue damage decision
The user decided to **raise Sword, Emberfang and Mace back to their old damage per second**. It's not
applied yet. The proposed numbers are in [[main-issue-dueling-vibe]]:

| Weapon | Damage (hits 1, 2, 3) |
|---|---|
| Sword | 33, 41, 65 |
| Emberfang | 42, 52, 85 |
| Mace | 40, 47, 87 |

They go in `CombatConfig` `Combo[n].Damage`. Do it when the user picks up the main issue, or when asked.

## Gotchas
- `execute_luau` in edit mode can't read `Lighting.Technology` or the Workspace streaming
  properties (it lacks the capability). Use pcall, and ask the user to read them in Properties.
- LightingSetup deletes DepthOfField at server start, so the one in default.project.json never reaches players.
- The FPS watch in Quality ignores the first 15 s and pauses while the window is unfocused.
