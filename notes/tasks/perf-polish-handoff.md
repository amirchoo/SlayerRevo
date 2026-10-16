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
- **Priority:** this pass (lag) is **priority 0**; the main issue is priority 1 (the user's call, 2026-10-17).
- **Waiting on the user (Studio):**
  - set **Lighting → Technology → ShadowMap**
  - **save and publish** the place (step 3 moved things in it; see its log's "To do")
  - playtest steps 1–3 on the phone and the Mac (checklists at the end of each log)
- [x] 0. Audit ([log](../log/2026-10-17-perf-audit.md)). Counts, the top 10 costs, and what's built at startup.
- [x] 1. Quality tiers ([log](../log/2026-10-17-quality-tiers.md)).
  - [Quality.luau](../../src/client/Quality.luau) and [QualityConfig.luau](../../src/shared/Config/QualityConfig.luau).
  - Read the tier with `Quality.settings()` / `Quality.onChange`.
  - The console prints `[Quality] <tier> (<why>)`.
  - The admin panel can pin a tier.
- [x] 2. ShadowMap and the art-direction pass ([log](../log/2026-10-17-shadowmap-art-direction.md)).
- [x] 3. Startup content and Workspace cleanup ([log](../log/2026-10-17-startup-bake-cleanup.md)).
  - Clutter is in `ServerStorage.UnusedFromWorkspace`; "Destroyed house" (kept) is in `workspace.World`;
    the old "Terrain" model is `MountainBackdrop`.
  - The Grimgorg layout and its TerrainRegion are in `ServerStorage.DungeonLayouts`.
  - Weapons are registered at server start (`InventoryService.register`), so the statues and stands
    hold them right away.
  - The training ground, stands and Hall were left code-built on purpose (see the log).

## Next: step 4 (proposed, not yet OK'd)
See below. It's the biggest lag win: the 953 trees and PinkFlower's 7,320 SurfaceAppearances.

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
