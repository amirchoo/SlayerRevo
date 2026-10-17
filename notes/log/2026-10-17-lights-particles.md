# Lights and particles (polish pass step 5)

**Asked:** step 5 of [[perf-polish]] (priority 0: lag), as proposed in [[perf-polish-handoff]] and
OK'd by the user. Before it, the user's ShadowMap setting was fixed (see "Also" below).

## Results

| | Before | After |
|---|---|---|
| Parts casting shadows in Workspace | 52,279 | **11,287** |
| One dungeon torch, particles/s (Low / Medium / High) | ~295 / ~550 / 845 | **42 / 104 / 295** |
| All 46 Grimgorg torches, particles/s on Medium | ~25,000 | **~4,800** |
| Torch lights lit at once (Low / Medium / High) | all 46 | **6 / 12 / 24 nearest** |
| Town lamps lit at night (Low / Medium / High) | all ~42 | **6 / 12 / 24 nearest** |

(Torch "before" already includes step 1's Particles multiplier: 0.35 / 0.65 / 1.)

## What changed

### In the place (Studio edit mode; the user needs to save and publish)
- **Shadow casters trimmed** with the new [tools/trim_shadows.lua](../../tools/trim_shadows.lua)
  (safe to run again):
  - Each of the 965 trees keeps shadows on its trunk and its **6 largest leaf clumps** (5,790 leaves),
    so the canopy still drops a shadow on the ground. Its other 27,985 leaves stop casting.
  - TallGrass, Bush, Wildflower, HogWeed and the StonePath stones stop casting (13,007 parts):
    their shadows were lost in the grass or flat on the ground anyway.
- **Lighting:** `PrioritizeLightingQuality` is off (with `LightingStyle` Realistic, this is the
  old ShadowMap; it was on, the old Future). New Studio has no `Technology` row.

### Code
- [QualityConfig](../../src/shared/Config/QualityConfig.luau): two new settings per tier.
  - `TorchFlames`: the share of each torch emitter's own rate, on top of `Particles`; emitters it
    doesn't list are off.
    - Low: `Fire3` 0.6 (the big flame only).
    - Medium: `Fire3` 0.5, `Fire2` 0.5, `Smoke`.
    - High: those, plus `CandleLight` and `Fire1` at 0.2.
    - `Fire1` (500/s, 0.075 s life, a flicker core) was most of each torch's cost.
  - `WorldLights`: torch lights and town lamps lit at once, nearest the camera (6 / 12 / 24).
- [Quality](../../src/client/Quality.luau): an emitter under `workspace.Dungeons` inside a `Torch`
  model gets its `TorchFlames` share. Everything else scales as before.
- New client [LightBudget](../../src/client/LightBudget.luau):
  - Every 0.5 s it lights the nearest `WorldLights` of the lights it manages and darkens the rest.
    A light fades in or out over 0.4 s, so it doesn't pop.
  - It manages dungeon torch lights by itself, and town lamps through DayNight.
  - Braziers, the portal and the campfire aren't budgeted (they're few and they're the big ones).
- [DayNight](../../src/client/DayNight.luau): at night, town lamps are handed to LightBudget
  instead of all switching on. Windows still all glow.

### Checked, no change
- **Hit effects:**
  - Every spark burst, flare and impact light lives on an attachment cleaned up within 2 s.
  - Burst counts already scale with `Particles`, and impact lights are capped per tier (`HitLights`).
- **PlayerLight:** already nearest-N per tier (2 / 4 / 8).
- **Brazier lights:** they have `Shadows` on, but on ShadowMap only the sun casts shadows, so it costs nothing.

## Also: the startup asset error
`rbxassetid://203785492` ("Pop Close Sound", an audio file loaded as another type) isn't anywhere
in the game, saved or running. It logs once per Studio DataModel, so it's a Studio plugin. Players
never see it. To silence it, turn plugins off one by one in Manage Plugins.

## Open
- Not playtested (the user's rule): the look of Low and Medium torches and the light budget's
  edges are unchecked.
- Tuning: `TorchFlames` and `WorldLights` in QualityConfig; `KEEP_LEAVES` in the tool (rerun it);
  `UPDATE_INTERVAL` and the fade in LightBudget.
- Server burn and bleed emitters on enemies (`EnemyEffects`) aren't tiered. They're small
  (14–20/s, only while an enemy burns).

## To check (phone first, then PC)
1. **Save the place** first (the shadow trim and the lighting setting are place edits).
2. Town by day, Shift+F5: FPS compared with before. Trees should still drop a canopy shadow;
   grass and paths have none.
3. Town at night: lamps near you are lit. Walk down a road: the ones ahead fade in and the ones
   behind fade out, without popping.
4. The Grimgorg dungeon: torches still look like fire on the phone (Medium). Walk a corridor: the
   torch lights ahead come on smoothly. FPS in the big rooms compared with before.
5. On the PC (High), torches have smoke, glow and the flicker core back.
