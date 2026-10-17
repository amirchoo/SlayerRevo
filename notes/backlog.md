# Backlog

Ideas and features to build, most important first. Ask Claude Code to "do the top item in notes/backlog.md",
or turn an item into a task note (notes/tasks/) when it needs more detail.

## Next
- [ ] **Priority 0: Polish and performance pass (lag)** for the phone and the Intel Mac, one step per message ([note](tasks/perf-polish.md))
- [ ] **Priority 1: MAIN ISSUE:** combat feel and atmosphere like Dueling Grounds, one step per session ([note](tasks/main-issue-dueling-vibe.md))

## Later
- [ ] **Idea (the user's, 2026-10-17): dungeons in their own place.** Entering teleports you (and
  later your party) to a reserved server of a separate dungeon place; leaving teleports you back.
  Claude's read, not decided: the dungeon already costs the main server almost nothing until a
  run starts (its layout sits in ServerStorage, which never reaches clients), and since perf step 7
  the overworld's orcs and animals sleep while you're inside. So the gain is mostly isolation, not
  FPS. The costs: a loading screen each way, data saved and loaded across places, a second Rojo
  project, and teleports don't work in Studio playtests, so every dungeon test needs a publish.
  Worth revisiting after the perf pass's final check, if dungeon runs are still laggy or once
  parties and more dungeons exist. Changes design.md §"Bosses and dungeons" (a private copy in the same server).
- [ ] 

## Done
- [x] Sword combo and idle redone katana-style after Dueling Grounds: a chained combo, flick wind-ups, held end poses; Mace keeps the old swings (2026-10-18, [log](log/2026-10-18-sword-katana-redo.md))
- [x] Sword recovery clips published and wired in (CombatConfig Sword.Combo, Emberfang training stand) (2026-10-18, [log](log/2026-10-18-sword-recovery-ids.md))
- [x] Sword swings recover on a curve instead of snapping back; swings blend into each other and into the idle; Sword/Emberfang/Mace damage raised (2026-10-17, [log](log/2026-10-17-sword-recovery-blend.md))
- [x] Loading: a Slayer Revo loading screen, sounds preloaded once you're in (2026-10-17, [log](log/2026-10-17-loading.md))
- [x] Enemy smoothness: orcs and animals far from every player sleep, anchored, waking as you come near (2026-10-17, [log](log/2026-10-17-dormancy.md))
- [x] Animation smoothness: animals, villagers and pets posed less often when far or off screen; hitstop and priorities checked (2026-10-17, [log](log/2026-10-17-pose-lod.md))
- [x] Lights and particles: shadow casters 52k → 11k, torch emitters tiered, only the nearest lights lit, ShadowMap really on (2026-10-17, [log](log/2026-10-17-lights-particles.md))
- [x] Streaming and density: daisy clumps simplified, models stream whole, decor out of physics, fewer plants on lower tiers (2026-10-17, [log](log/2026-10-17-streaming-density.md))
- [x] Startup cleanup: Workspace clutter out, dungeon layout in ServerStorage, statues and stands hold weapons from server start (2026-10-17, [log](log/2026-10-17-startup-bake-cleanup.md))
- [x] ShadowMap lighting, with grade, contrast and fog for day, night and the dungeon; phones at graphics 8+ get High (2026-10-17, [log](log/2026-10-17-shadowmap-art-direction.md))
- [x] Effects quality tiers (Low, Medium, High) by device and FPS; every effect reads the tier (2026-10-17, [log](log/2026-10-17-quality-tiers.md))
- [x] Performance audit: part, light, emitter and per-frame counts, plus the top 10 costs (2026-10-17, [log](log/2026-10-17-perf-audit.md))
- [x] Sword swings use the whole body (overlap, elbow) with a deliberate wind-up; dash is a low body dash, not a roll (2026-10-17, [log](log/2026-10-17-sword-whole-body-body-dash.md))
- [x] Sword swings rebuilt with big arcs, fast strikes and held follow-through; dash is now a dodge roll (2026-10-17, [log](log/2026-10-17-sword-arcs-dodge-roll.md))
- [x] Sword swings eased (whip into the hit, stop hard, hold, recover to ready); shared easing in the generator (2026-10-17, [log](log/2026-10-17-sword-swing-easing.md))
- [x] Lock-on: enemy visible up close (higher, further round); orcs topple and fade instead of breaking apart (2026-10-17, [log](log/2026-10-17-lock-on-close-range-orc-death.md))
- [x] Hits light up and flare, bigger gold parry flash, moonlit night grade (2026-10-17, [log](log/2026-10-17-hit-flares-night-grade.md))
- [x] Arena floor no longer glitches with terrain; players carry a light in the dark; torches cast no shadows (2026-10-17, [log](log/2026-10-17-arena-floor-player-light.md))
- [x] Dungeon playtest fixes (moved layout, too dark), admin god mode, orcs player-sized (2026-10-17, [log](log/2026-10-17-dungeon-playtest-fixes.md))
- [x] Dungeon gates, chests and exit editable in Studio like the town (2026-10-17, [log](log/2026-10-17-dungeon-working-parts.md))
- [x] Lock-on camera: duel framing like Dueling Grounds (2026-10-17, [log](log/2026-10-17-duel-lock-on-camera.md))
- [x] Grimgorg sounds and boss music; 5 parries to stun him (2026-10-17, [log](log/2026-10-17-grimgorg-sounds-parries.md))
- [x] Music by place, background ambience, coin pickup sound (2026-10-17, [log](log/2026-10-17-music-ambience.md))
- [x] Dungeon chests spill spinning gold coins, random total per player (2026-10-17, [log](log/2026-10-17-chest-coins.md))
- [x] Dungeon gates hug the rock; grim, dark dungeon lighting (2026-10-17, [log](log/2026-10-17-dungeon-gates-ambience.md))
- [x] Dungeon and its entrance editable in Studio: saved layouts in workspace.DungeonLayouts (2026-10-17, [log](log/2026-10-17-dungeon-layouts.md))
- [x] Dungeon carved from terrain like the land's rock; no map inside a run (2026-10-17, [log](log/2026-10-17-dungeon-terrain.md))
- [x] Dungeon props (chest, torch, crate, brazier, portcullis, cave rocks, crystals, cave mouth) from Toolbox models (2026-10-17, [log](log/2026-10-17-dungeon-assets.md))
- [x] Grimgorg's Lair remade as a maze: patrols, chests, hidden nook, sealed arena (2026-10-16, [log](log/2026-10-16-grimgorg-maze.md))
- [x] Map waypoint at Grimgorg's Lair, unlocked by reaching it (2026-10-16, [log](log/2026-10-16-dungeon-waypoint.md))
- [x] Grimgorg's Lair: dungeon with orc rooms and the Grimgorg boss fight (2026-10-16, [log](log/2026-10-16-grimgorg-lair.md))
- [x] Lock-on rework: target switching, new camera (2026-10-16, [log](log/2026-10-16-lock-on-rework.md))
- [x] Orc Skin drop, sold to Greta (2026-10-16, [log](log/2026-10-16-orc-skin-drop.md))
- [x] Orcs and animals on the map (2026-10-16, [log](log/2026-10-16-map-creature-markers.md))
- [x] Enemies heal to full when they give up (2026-10-16, [log](log/2026-10-16-enemy-reset-heal.md))
