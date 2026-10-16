# Polish and performance pass (phone and Intel Mac)

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
- [ ] 3. Bake what's still built at startup. Town and World are already saved; still to bake are the
  TrainingGround, the TrainingStands, the ClassHall and the NPC rigs. Keep the generators as tools.
- [ ] 4. Streaming and density:
  - streaming radii
  - fog
  - ModelStreamingMode
  - fewer trees and bushes on Low, and simpler models
- [ ] 5. Lights and particles:
  - few shadow casters
  - cut the dungeon's 240 emitters
  - PlayerLight on the nearest few characters
  - short-lived hit effects
- [ ] 6. Animation smoothness:
  - replace per-frame joint posing with clips
  - make sure hitstop always restores track speed
  - check animation priorities and fades
- [ ] 7. Enemy smoothness: fewer and cheaper server updates for far enemies, animals and villagers.
- [ ] 8. Loading: fewer startup preloads, a ReplicatedFirst loading screen, and far content loaded later.
