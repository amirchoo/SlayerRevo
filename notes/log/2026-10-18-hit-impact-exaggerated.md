# Hits land harder still: rolling camera jolt, bigger zoom punch, two-stage impact frame

**Asked:** "the camera work and camera shake and impact frame is not enough, we need to exaggerate it a
bit more" (after seeing the new Sword combo).

**Changed**
- `src/client/HitFeel.luau`
  - **Shake** is now a jolt that rings out instead of random jitter: it slides (CameraOffset, as before,
    so LockOn shows it) in a sine wobble and also **tilts and rolls** the view (roll either way at
    random), dying away over 0.22 s. The turn is laid on after the camera and LockOn (RenderPriority
    Camera + 2) and taken off again before the next camera update (Camera - 1), because the default
    camera reads its own facing back and a leftover tilt would creep into the view.
  - **Hitstop** is longer on heavy hits (combo enders, heavies, kills): + Hitstop.Heavy.
  - **Impact frame** has two stages: a near-white flash (0.03 s), then the washed-out, harsh frame with
    the target as a black silhouette outlined red **and you** as one outlined white, 0.12 s in all.
- `CombatConfig` (all tunable there):
  - Hitstop: Base 0.03→0.04, PerDamage 0.0008→0.001, Min 0.04→0.05, Max 0.1→0.12, new Heavy +0.05.
  - Shake: Min 0.05→0.12, PerDamage 0.0015→0.003, Max 0.16→0.3, Heavy x2→x2.2, Time 0.12→0.22;
    new Frequency 22, Tilt 0.8°, Roll 1.5°, HeavyRoll 4.5°.
  - Zoom punch: 1.2°→3°, heavy 4°→9°, back over 0.3 s (was 0.2).
  - Impact frame: Time 0.07→0.12, MinGap 0.5→0.4, Saturation -1, Contrast 1, Brightness 0.15, new
    FlashTime 0.03 / FlashBrightness 0.7, Attacker (true) / AttackerOutline (white).

**Checked:** syntax and type check pass. **Not playtested** (skip-playtests rule).

**Open:** whether it's now too much on the phone (the tilt/roll can make some players queasy: an
accessibility toggle for screen shake and flashes may be wanted); tune in CombatConfig.HitImpact.
