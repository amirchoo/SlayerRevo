# Handoff: polish and performance pass (continue from here)

Updated 2026-10-17 in the third session (steps 5–8 done, the pass is built; 3–4 the second session, 0–2 the first).
**Start with [[session-handoff]]** (the latest state). Saying "continue the perf pass": Claude reads this note and [[perf-polish]], then
proposes the next step.

## How the user wants to work
- **One step per message:** explain what will change, **wait for the user's OK**, do it, then:
  - log it in `notes/log/`
  - tick it in [[perf-polish]], `notes/log/README.md` and `notes/backlog.md`
  - commit and push to origin/main
  - **don't** hand the user a checklist each step (2026-10-17: the Mac is slow and the phone needs a
    publish). Claude checks each step itself: syntax, edit-mode `execute_luau` (modules load, counts),
    and for risky steps only a short console-only playtest (no screenshots). Each log keeps its
    "To check" list; **one combined phone + PC check comes at the end of the pass** (after step 8).
- **No Studio playtests or screenshots** unless asked (the 2026-10-17 second session asked: the user
  was away from the Mac, so Claude playtested steps 3–4 itself; that was for that session only). Read-only `execute_luau` counts in edit mode
  are fine (that's how the audit counted).
- **The baseline device is an average/low-end Roblox phone (minimum spec)**, not the user's iPhone 14
  (changed 2026-10-18; the iPhone 14 is just the phone they test on, and it's well above average). The Intel Mac
  is secondary. Low tier must be smooth on a weak phone. Build the look so Medium tier looks polished; High only adds extras.
- **Auto mode** is set for new sessions in `.claude/settings.local.json` (git-ignored).

## State
- **Priority:** this pass (lag) is **priority 2** since 2026-10-18 (after the weapon animation remake,
  [[weapon-anim-remake]], and the Arcane Atelier look, [[arcane-atelier-look]]); the main issue is priority 3.
- **The place is saved** (the user confirmed 2026-10-17), so steps 3 and 4 are kept. Step 5's shadow
  trim and PrioritizeLightingQuality need another save (ask the user if it was done).
- **Startup asset errors, checked 2026-10-17 (third session):**
  - `rbxassetid://203785492` is an **audio** asset ("Pop Close Sound", 2015, by Zyleak), loaded as another
    type. It isn't in the repo, the saved place, or the live server/client in a playtest (all asset
    properties, script sources, attributes, CoreGui and PluginGuiService scanned). It logs **once per
    Studio DataModel** (edit, server, client), like the plugin-icon error, so it's a **Studio plugin**,
    not the game: players never see it. To silence it, turn plugins off one by one in Plugins →
    Manage Plugins.
  - `rbxassetid://1014915761` "archived" is also a plugin icon: ignore it.
- **ShadowMap is set** (2026-10-17). New Studio has no `Technology` row any more: it's
  **LightingStyle = Realistic + PrioritizeLightingQuality off** (on = the old Future). Claude set
  PrioritizeLightingQuality off via `execute_luau` (writable, unlike Technology). `default.project.json`
  still says `Technology: ShadowMap`, which is harmless.
- The user's Roblox account is **ColePalmer6954** (the "joined live editing session" line is them).
- The session should run in **auto mode** (the user wants it).
- **Waiting on the user (Studio):**
  - enter the Grimgorg dungeon once (check the saved TerrainRegion survived: walls and floor are there)
  - the one combined check at the end of the pass (steps 1–8; the "To check" lists in each log)
  - set the streaming properties on Workspace (step 4's log, "To do")
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

- [x] 4. Streaming and density ([log](../log/2026-10-17-streaming-density.md)).
  - PinkFlower → HogWeed (originals in `ServerStorage.UnusedFromWorkspace.PinkFlowers`).
  - World and Town models Atomic, MountainBackdrop Persistent.
  - Walk-through plant parts have CanTouch, CanQuery off and Box collision.
  - Client [WorldDensity](../../src/client/WorldDensity.luau) thins small plants by `QualityConfig` `Decor`.
  - Testing gotcha: `execute_luau` on the client gets its **own copy** of required modules, so
    `Quality.force` there doesn't reach the game's copy.

- [x] 5. Lights and particles ([log](../log/2026-10-17-lights-particles.md)).
  - Shadow trim is a place edit via [tools/trim_shadows.lua](../../tools/trim_shadows.lua) (rerun it after
    placing new trees).
  - `QualityConfig` `TorchFlames` and `WorldLights`; client [LightBudget](../../src/client/LightBudget.luau)
    owns `Enabled` on torch lights and town lamps (DayNight sets "wanted" at night).

- [x] 6. Animation smoothness ([log](../log/2026-10-17-pose-lod.md)).
  - Client [PoseLod](../../src/client/PoseLod.luau) (`QualityConfig` `PoseDetail`) used by the
    Animal, Villager and Pet animators. Clips weren't made (the user would have to publish them).
  - HitFeel was fine (Play() resets speed). The DamageFeedback leftover is fixed.

- [x] 7. Far creatures sleep ([log](../log/2026-10-17-dormancy.md)).
  - Server [Dormancy](../../src/server/Dormancy.luau) used by EnemyService (packs, lone orcs) and AnimalService.
  - Testing gotcha: move a test character from the client (the server's PivotTo gets snapped back).

- **The combined final check** is [[perf-final-check]]: add each finished step's checks there.

- [x] 8. Loading ([log](../log/2026-10-17-loading.md)).
  - [LoadingScreen](../../src/first/LoadingScreen.client.luau) in ReplicatedFirst; Sounds.preload waits
    until you're in and skips loops (`Loop = true`).

## First phone check (2026-10-17)
- No lag. But trees and ground were missing on the phone (memory: streaming was still on
  defaults). Fixed by putting the streaming settings in `default.project.json`
  ([log](../log/2026-10-17-streaming-fix.md)). Waiting on the user: reconnect Rojo, publish, recheck.
- **Next after that (the user asked):** creature animation still isn't as smooth as they want. Ask
  what looks off (which creatures, near or far, choppy or stiff) before changing PoseLod or the
  animators.

## Next: the user's final check
All 8 steps are built. The user does **one** publish and the combined check in [[perf-final-check]]
(it starts with reconnecting Rojo). Then fix whatever they report, and the pass is done; next is
the main issue (priority 1), or the dungeon-place idea in the backlog if dungeons are still laggy.

Small leftovers found on the way:
- The admin panel needs the `` ` `` key, so it can't be opened on a phone.

## Separate: main issue damage decision (applied 2026-10-17)
The user decided to **raise Sword, Emberfang and Mace back to their old damage per second**. Applied
2026-10-17 ([log](../log/2026-10-17-sword-recovery-blend.md)). The numbers:

| Weapon | Damage (hits 1, 2, 3) |
|---|---|
| Sword | 33, 41, 65 |
| Emberfang | 42, 52, 85 |
| Mace | 40, 47, 87 |

They go in `CombatConfig` `Combo[n].Damage`. Do it when the user picks up the main issue, or when asked.

## Gotchas
- `execute_luau` in edit mode can't read `Lighting.Technology` or the Workspace streaming
  properties (it lacks the capability). `LightingStyle` and `PrioritizeLightingQuality` it can. Use pcall, and ask the user to read them in Properties.
- LightingSetup deletes DepthOfField at server start, so the one in default.project.json never reaches players.
- Rojo sometimes isn't connected when a session starts: check with `script_grep` that new code is in
  Studio before playtesting, and ask the user to connect (don't push sources in by hand).
- Weapon-related checks: `InventoryService.register` runs at server start for combo weapons,
  the greatsword and the casters, but not for the bow, crossbow and blunderbuss (nothing needed them yet).
- The FPS watch in Quality ignores the first 15 s and pauses while the window is unfocused.
