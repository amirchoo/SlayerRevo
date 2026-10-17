# Battlegrounds-style combat feel, then PvP duels

Opened 2026-10-18. **Say "do the battlegrounds task" in a new session**: Claude reads this note and
[[battlegrounds-combat-reference]] (the frame-by-frame breakdown of the user's reference video), does
the first unticked step, ticks it here with a link to its log note, and logs it as usual.

The reference: a TikTok by skaterstudios ("Day 2 learning scripting"), saved at
`~/Downloads/v29025g50000dal5dlnog65oqfnmnrdg.MP4`. The user said "that's exactly my idea of smooth
animation… that's where we're getting to". It's the target for melee feel and for PvP.

How it fits with the other work (since 2026-10-18): the weapon animation remake ([[weapon-anim-remake]]) is
priority 0, the Arcane Atelier look ([[arcane-atelier-look]]) priority 1 (its hit VFX and ragdoll steps overlap steps here), the perf pass ([[perf-polish]]) priority 2, and the main issue ([[main-issue-dueling-vibe]]) priority 3. These steps overlap with the main issue (its step 5 is
trails), so check that note before building to avoid doing something twice.

## Steps (one per session or message, cheapest feel first)
- [x] **1. Hits land harder:** a camera shake and zoom punch on every hit, and an impact frame (grey
  screen, black silhouette with a red outline) on combo enders, heavies and kills.
  `HitFeel.luau`, `CombatConfig.HitImpact` ([log](../log/2026-10-18-hit-impact-frame.md)). Exaggerated the same day
  (rolling jolt, bigger zoom, two-stage impact frame; [log](../log/2026-10-18-hit-impact-exaggerated.md)). Not playtested yet.
- [x] **2. Afterimages on dash:** see-through white copies of the character trailing behind and fading
  out over about 0.2 s. Belongs in `DashEffects.luau`. Mind weak phones: few copies, reused.
  Pooled per character, 2/3/4 copies by quality tier, `CombatConfig.Dash.Afterimages` ([log](../log/2026-10-18-dash-afterimages.md)). Not playtested yet.
- [ ] **3. Hit reactions:** a different enemy flinch per combo step, plus a combo ender that knocks the
  target back and ragdolls it for about 1 s. Enemies first; players come with PvP.
- [ ] **4. Crescent slashes:** wide curved slash meshes along each sword/katana swing instead of thin
  trails (check main issue step 5 first).
- [ ] **5. Stun-state module (server):** Stunned / Blocking / Ragdolled / Airborne / i-frames. The
  server owns it and every action checks it. M1 stun is slightly longer than the gap between hits, so a
  4–5 hit combo can't be escaped. Needed by bosses and by PvP.
- [ ] **6. Air combat:** launcher → both float → air combo → slam with a rock crater.
- [ ] **7. PvP duels** (the user's plan, 2026-10-18): an "interact" button on another player opens a
  menu whose first option is Duel; both accept and fight right where they stand. Needs step 5. Before
  building, **ask the user**: the duel rules (to the death, or first to lose X% health?), any stakes,
  and the other interact options. `MeleeHitbox` currently skips every player (co-op), so it has to
  allow hits between the two duelists only. The research note's "What PvP would need" section lists
  the rest (knockback on players, lag fairness, anti-exploit, a way to break out of combos).

## Rules for this task
- Don't decide the [TBD] items (duel rules, stakes, interact menu) without asking.
- No Studio playtests or screenshots unless the user asks. Self-check with the syntax check and
  edit-mode `execute_luau`; device checks go into [[perf-final-check]].
- Config numbers in `src/shared/Config/`; client does VFX only, the server decides hits and damage.
