# Polish and performance pass (phone and Intel Mac)

**Priority 0** (the user's call, 2026-10-17): lag fixes come before the main issue (priority 1).

Opened 2026-10-17. Goal: look polished (Dueling Grounds-level) and run smoothly, with fast loading,
on a phone and an Intel Mac. One step per message: Claude explains the change, waits for the user's
OK, does it, logs it, and lists what to check on the phone and PC (FPS with Shift+F5, load time,
flicker, stutter). No Studio playtests unless asked.

**Continue from the handoff:** [perf-polish-handoff](perf-polish-handoff.md) (state, the next step, and its open question).

## Steps
- [x] 0. Audit, no changes ([log](../log/2026-10-17-perf-audit.md))
- [x] 1. Device-aware quality: shared QualityConfig plus a client Quality module, with Low, Medium and
  High tiers. The tier comes from touch input, the graphics quality level and measured FPS, and
  changes live. Every effect reads it. ([log](../log/2026-10-17-quality-tiers.md))
- [x] 2. Lighting: ShadowMap (the user's pick; the iPhone 14 is the baseline device), then the look
  through art direction: grade, contrast and fog by day, night and in the dungeon; phones at graphics
  8+ get High ([log](../log/2026-10-17-shadowmap-art-direction.md)). The user still needs to set
  Lighting.Technology to ShadowMap in Studio.
- [x] 3. Startup content: Workspace clutter moved out, the dungeon layout kept in ServerStorage,
  and weapons registered at server start so the stands and the Hall's statues don't pop in.
  The training ground, stands and Hall stay code-built (they're built before anyone joins).
  ([log](../log/2026-10-17-startup-bake-cleanup.md))
- [x] 4. Streaming and density: PinkFlower clumps swapped for single-piece HogWeed (7,280 fewer
  SurfaceAppearances), World and Town models stream Atomic, walk-through plant parts out of physics
  and raycasts, fewer small plants on Low and Medium (client WorldDensity). The streaming radius is
  the user's to set in Properties (see the log). ([log](../log/2026-10-17-streaming-density.md))
- [x] 5. Lights and particles: shadow casters 52k → 11k (trees keep trunk and 6 biggest leaf
  clumps; grass, bushes, paths off), torch emitters tiered (`TorchFlames`, Fire1 only on High),
  only the nearest torch lights and town lamps lit (client LightBudget), PrioritizeLightingQuality
  off (= ShadowMap). Hit effects and PlayerLight were already fine.
  ([log](../log/2026-10-17-lights-particles.md))
- [x] 6. Animation smoothness: Lua posing kept but given level of detail (client PoseLod: every
  frame near and on screen, 30/15 per second further out, 6 off screen; `PoseDetail` per tier) for
  animals, villagers and pets, instead of clips that the user would have to publish. Hitstop,
  priorities and fades checked: fine. DamageFeedback's grade no longer rewritten every frame.
  ([log](../log/2026-10-17-pose-lod.md))
- [ ] 7. Enemy smoothness: fewer and cheaper server updates for far enemies, animals and villagers.
- [ ] 8. Loading: fewer startup preloads, a ReplicatedFirst loading screen, and far content loaded later.
