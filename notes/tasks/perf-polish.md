# Polish and performance pass (phone and Intel Mac)

Opened 2026-10-17. Goal: look polished (Dueling Grounds-level) and run smoothly, with fast loading,
on a phone and an Intel Mac. One step per message: Claude explains the change, waits for the user's
OK, does it, logs it, and lists what to check on the phone and PC (FPS with Shift+F5, load time,
flicker, stutter). No Studio playtests unless asked.

## Steps
- [x] 0. Audit, no changes ([log](../log/2026-10-17-perf-audit.md))
- [ ] 1. Device-aware quality: shared QualityConfig plus a client Quality module, with Low, Medium and
  High tiers. The tier comes from touch input, the graphics quality level and measured FPS, and
  changes live. Every effect reads it.
- [ ] 2. Lighting: recommend ShadowMap or Future (ask the user), then get the look through art direction.
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
