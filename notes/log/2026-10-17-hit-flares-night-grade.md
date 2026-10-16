# Punchier hits and a moonlit night grade (feel after Dueling Grounds)

**Asked:** study a Dueling Grounds recording (2:54, Katana 1v1 on its night shrine map) for its
combat feel, animations and atmosphere. Not its game concept: just the satisfaction of its
hits and the look of its scenes, to make our combat feel better.

## What stood out in the recording
- Every clash gets a short flash showing what happened (red slash on a hit, big gold flash on
  a parry, white starburst on a clash, red X on a guard break), and the flash *lights the
  floor*. Each effect lasts about 0.1–0.3 s, so exchanges stay readable.
- Thin pale-blue swing trails; fast, low-stance strikes; the duel camera (already copied, see
  [[2026-10-17-duel-lock-on-camera]]).
- Night scene: cold blue-indigo with deep red wood, high contrast and saturation, crisp
  moon shadows, a shiny stone floor that reflects every flash, light distance fog.
- Health bars flash white and leave a delayed band (we already had this in HealthBar).

## What changed
- [HitEffectsClient](../../src/client/HitEffectsClient.luau):
  - Every hit (not just parries) now lights up briefly: a PointLight in the weapon's color
    (`HIT_LIGHT_*`, 0.14 s, at most `MAX_HIT_LIGHTS` 6 at once, so blunderbuss pellets don't
    pile up lights).
  - Every hit draws a flare streak facing the camera: a BillboardGui bar fading out to its
    ends that stretches and thins as it fades (`FLARE_LENGTH` 5 studs, `FLARE_TIME` 0.16 s,
    random ±14° tilt).
  - Parry is the showpiece: gold (255,185,70) instead of pale yellow, light 8 brightness /
    22 range / 0.3 s (was 5 / 14 / 0.15), a wide flare with a cross glint, 28 sparks (was 20).
- [LightingConfig](../../src/shared/Config/LightingConfig.luau) `DayCycle.Night`: ShadowSoftness
  0.12, EnvironmentSpecularScale 1, and a night grade (saturation 0.3, contrast 0.22, cool
  tint 220,230,255). [DayNight](../../src/client/DayNight.luau) blends these in with the night,
  like the other night values. Day (warm, friendly town) and the dungeon (grim) are unchanged.

## Open
- Not playtested. Watch: flares too big or bright on big Greatsword/Hammer hits (size is capped
  at 1.6x), and whether night is now too contrasty in town.
- Ideas not done: different flashes for clash and guard break (we have no clash/guard-break
  events yet), thinner trails on katana-like weapons, shiny floor in the Grimgorg arena,
  a round/fight intro splash for boss fights.
