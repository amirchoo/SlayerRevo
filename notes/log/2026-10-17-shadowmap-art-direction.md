# ShadowMap lighting and an art-direction pass (polish pass step 2)

**Asked:** step 2 of [[perf-polish]]. Recommend ShadowMap or Future for both devices and ask, then
get the Dueling Grounds look through art direction instead of costly lighting tech: colour grade,
contrast, fog and atmosphere, and a few strong lights. The user made the **iPhone 14 the baseline**
(most players are on phones, not Macs) and chose **ShadowMap**. They also said **yes to letting phones
at graphics level 8+ reach High**.

## Why ShadowMap
- Future's extras are torch and lamp shadows and richer reflections, and phones mostly drop those to
  keep their frame rate. It's the costliest mode for the iPhone 14 (heat, then a slower frame rate
  over a long session) and for the Intel Mac's GPU, where it caused the dungeon flicker
  ([[2026-10-17-arena-floor-player-light]]).
- ShadowMap keeps crisp sun and moon shadows. Lamps, torches and hit flashes still light their
  surroundings, but don't cast shadows.

## What changed
- [default.project.json](../../default.project.json): `Lighting.Technology` is ShadowMap.
  **Scripts and Rojo can't set this property** (Roblox blocks it), so the user sets it in Studio
  once (see below).
- [LightingConfig](../../src/shared/Config/LightingConfig.luau):

  | Setting | Before | After | Why |
  |---|---|---|---|
  | Day ShadowSoftness | 0.35 | 0.2 | crisp ShadowMap sun shadows |
  | Day contrast | 0.10 | 0.15 | punchier, still warm and friendly |
  | Day fog Density / Haze | 0.24 / 0.3 | 0.3 / 0.8 | the far forest fades into a cool haze: depth, and late-streaming trees don't pop |
  | Night fog | none (day fog all night) | Density 0.36, Haze 1.2, blue-indigo (70,85,130), Glare 0 | the duel-night look: cold fog that warm lamps and hit flashes glow against |
  | Dungeon fog Density | 0.30 | 0.38 | far corridors sink into murk; the torch-lit space near you is the stage |

  Night grade, saturation and the dungeon grade are unchanged (tuned in [[2026-10-17-hit-flares-night-grade]]).
- [DayNight](../../src/client/DayNight.luau) blends the fog from day to night, as it already does
  for the grade and the light. It leaves the dungeon fog alone.
- [QualityConfig](../../src/shared/Config/QualityConfig.luau) `Device.TouchHighFrom = 8`, read by
  [Quality](../../src/client/Quality.luau): a phone with graphics turned up to 8+ by hand starts on
  High. On Automatic it stays Medium, and the FPS watch still drops the tier if the phone heats up.

## Choices
- **"A few strong lights":** no new lights in this step. The town's lamps, the dungeon torches and
  the hit flashes are already there. Making a few of them stronger, and turning the rest down, is
  step 5. The Grimgorg arena's own look (floor, rim light) is step 3 of
  [[main-issue-dueling-vibe]].
- **The look is built for Medium** on the phone (grade, fog, flashes). High only adds SunRays,
  more hit lights and a wider ambience range on top.

## To do (user, in Studio)
1. In Explorer, select **Lighting**.
2. In Properties, set **Technology** to **ShadowMap**.
3. Publish.

## Checks
- `sh tools/check_syntax.sh`: all scripts parse.
- Not playtested.

## Open
- **Lights look softer on ShadowMap.** Torch and lamp light, and hit flashes, can look softer and
  spread a little through thin walls. Check the dungeon torches and the parry flash on the floor.
  If the arena loses its punch, step 3 of the main issue can make up for it there.
