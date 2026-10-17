# The Arcane Atelier look: bright painterly world, big hit VFX, heavy-sword walk (priority 1)

Opened 2026-10-18 from the user's reference video ("I like the whole style and environment"); the full
breakdown is in [[arcane-atelier-reference]]. **Priority 2** (the user's call, 2026-10-18; the armor remake, [[armor-remake]], was put before it the same
day): after the weapon remake (0) and the armor remake (1), before the perf pass (3) and the main issue (4). Say **"do the Arcane Atelier look"**: Claude reads this note and the
research note, does the first unticked step, ticks it here with a link to its log note.

Steps are Claude's proposal, not decided: confirm the order and each [TBD] with the user before building.
Each visual step needs a cheaper setting for the low-end phone ([[baseline-device-low-end-phone]]).

## Steps
- [ ] **Lighting and post-processing** in the hunting grounds: an anime-painted cloud skybox, bloom,
  saturation/colour correction, sun direction, little fog; depth of field on capable devices only.
  Mostly settings (`Config/LightingConfig`). [TBD: whole world or the hunting grounds only? Town keeps
  its day/night cycle.]
- [ ] **Ground layering** in the hunting grounds: broken flagstone path pieces, dirt patches, chunky
  grass clumps and flower clusters (models made in Blender, placed by script). Phone: fewer clumps,
  only near the player.
- [ ] **Rocks, ruins and trees** in the same style: low-poly flat-faced rocks and cliffs, ruined walls,
  round blobby tree canopies (Blender).
- [ ] **Hit VFX:** big bright crescent arcs timed to each cut, a ring shockwave at the hit point, a flash.
  Overlaps the battlegrounds crescents step ([[battlegrounds-combat]]); do them together.
- [ ] **Red serif damage numbers** popping over the target. [TBD: show them at all? Players only, or
  enemies' hits on you too?]
- [ ] **Enemies knocked flying and ragdolling** on finishers and kills (overlaps the battlegrounds
  knockback-and-ragdoll ender).
- [ ] **Weapon walk (carry) clips:** the blade low and trailing, the arm swinging back with the steps,
  so the sword looks heavy. Played instead of the idle while moving. [TBD: ask whether to add one per
  weapon to the remake ([[weapon-anim-remake]]), since it's an animation.]
- [ ] **HUD reskin:** an ornate filigree frame on the health bar, round skill slots, stone-tablet
  hotbar slots, parchment dialogue box, serif fonts. [TBD: the user's call on the theme.]
- [ ] **NPC flavour:** enemies with a shout in a speech bubble when they spot you ("En garde!").
