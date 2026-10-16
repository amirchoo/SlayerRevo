# Device-aware effects quality (Low, Medium, High)

**Asked:** step 1 of [[perf-polish]]. A shared QualityConfig and a client Quality module pick a tier
(Low, Medium or High) from:
- touch input
- the player's Roblox graphics level
- the measured FPS

It adjusts live when FPS drops. Every effects system reads the tier. Phones default to Low or
Medium, PCs to High.

## How the tier is picked ([Quality](../../src/client/Quality.luau))

**Device tier.** "Touch" means a touchscreen with no keyboard.

| Device | Automatic graphics | Graphics level |
|---|---|---|
| Phone or tablet | **Medium** | 1–4 Low, 5+ Medium (never High) |
| Computer | **High** | 1–3 Low, 4–6 Medium, 7+ High |

**FPS watch:**
- It ignores the first 15 s after joining, while the world loads.
- Averaged over each second:
  - **5 s in a row under 40 FPS** drops one tier.
  - **60 s in a row at 57+** climbs one tier, but never above the device tier and at most twice a session, so it can't flip-flop.
- It's paused while the window is in the background, where the frame rate is throttled.
- Changing the graphics level in Roblox's menu starts over from the new device tier.

**Seeing the tier:**
- Each change prints `[Quality] <tier> (<why>)` to the console (F9 on PC; Developer Console on the phone).
- The admin panel (`` ` ``) shows the tier, with **Auto / Low / Med / High** buttons that pin one for testing.

## What each tier does ([QualityConfig](../../src/shared/Config/QualityConfig.luau))

| Setting | Low | Medium | High | Read by |
|---|---|---|---|---|
| Particles (counts and rates) | ×0.35 | ×0.65 | ×1 | HitEffectsClient bursts, DashEffects dust, anvil sparks; Quality scales every emitter in `workspace.Town` (chimney smoke) and `workspace.Dungeons` (the runs' torches) |
| Player glows at once | 2 | 4 | 8 | PlayerLight |
| Impact lights at once | 0 | 3 | 6 | HitEffectsClient (hits still flash white and flare on Low) |
| Parry floor flash | on | on | on | HitEffectsClient |
| Swing trails | off | on | on | ComboWeaponClient, GreatswordClient |
| Bloom | off | on | on | Quality (Lighting's BloomEffect.Enabled) |
| SunRays | off | off | on | Quality |
| Cloth sway and windmill range | none | 90 studs | 180 studs | TownAmbience |
| Town birds | hidden | shown | shown | TownAmbience |

## Choices
- **DepthOfField:** nothing to do. LightingSetup already deletes it at server start (the one in
  default.project.json never reaches players).
- **Parry flash on Low:** kept, because it's the one showpiece light and lasts 0.3 s.
- **Colour grade and atmosphere:** stay on every tier. They're cheap, and they carry the look on phones.
- **HitFeel:** HitFeel's hitstop isn't an effect, so it's unchanged. The hit "flashes" are HitEffectsClient's,
  covered above. Making hitstop restore its tracks reliably is step 6.
- **Per-frame posing:** the Lua animators (animals, villagers, pets) aren't tiered yet. That belongs to steps 6 and 7.

## Checks
- `sh tools/check_syntax.sh`: all scripts parse.
- Not playtested.

## Open
- On the phone the admin panel needs the `` ` `` key, so read the tier from the Developer Console line instead.
- DamageFeedback still rewrites its grade every frame at full health (small; for a later step).
