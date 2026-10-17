# Arcane Atelier video analysed (priority 1, after the remake)

**Asked (2026-10-18):** the user sent a 75 s TikTok of *Arcane Atelier*, an in-development Roblox game,
and asked what Claude gets from it: they like its whole style and environment. Then: put it all in
notes as the next priority; the attacks look smooth too (is it because the VFX hide the animation's
flaws?), and the walk makes the sword look heavy, the hand back, flowing with the sword.

**What changed (notes only, no code):**
- [[arcane-atelier-reference]]: the breakdown (environment, post-processing, combat VFX, damage numbers,
  ragdolls, UI, why the swings look smooth, the heavy-sword walk, phone cost).
- [[arcane-atelier-look]]: the task, **priority 1** (the user's call: next after the animation remake, before
  the perf pass and the main issue),
  with proposed steps and [TBD]s to confirm.
- `docs/animation-style.md` ("Around the animation"), [[weapon-anim-remake]], the backlog, CLAUDE.md,
  the session handoff and the priority memory point to it.

**Findings on the user's two questions:**
- VFX: yes. Frame by frame at 10 fps, the crescent arcs, impact ring and flash cover the body on almost
  every frame of a swing; it's only clearly visible in the held poses between swings.
- Walk: the sword hangs low in the right hand, tip down and trailing behind, swaying with the steps
  (enemies too). We have no weapon walk clip: the weapon idle plays over the default walk.

**Open:** the step order and each [TBD] in the task (whether to add walk clips to the remake, damage
numbers, the HUD theme, which areas get the new lighting). Sound in the video not checked.

**Playtested:** n/a (notes only).
