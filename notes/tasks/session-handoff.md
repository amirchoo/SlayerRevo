# Handoff: start here next session

Written 2026-10-18 at the end of the session (the user ended it for the day).
**Say "read the handoff" (or "continue") in a new session**: Claude reads this note first, then
the notes it points to. Update this note at the end of every session.

## Where things stand
- **Priority 0: remake every weapon's animations** in the new style. The user loved the exaggerated
  Sword combo ("perfect, this is how I imagine it would be"). Recipe: [[animation-style]]
  (`docs/animation-style.md`); checklist: [[weapon-anim-remake]]. Say **"do the animation remake"**.
  - **Sword combo: done and published** (SwordSwing1–3 + Moving twins, written over the existing IDs on
    2026-10-18, revisions checked through Open Cloud; [log](../log/2026-10-18-sword-combo-exaggerated.md)).
    Copies are still in `Workspace.Rig.AnimSaves` (harmless).
  - **Next weapon:** the Sword's rest (SwordIdle check, SwordGuard, SwordSpin), then the **Rapier** (the
    user's weapon). The user may reorder.
- **Hit feel exaggerated** (rolling camera jolt, bigger zoom punch, longer heavy hitstop, flash-then-
  silhouettes impact frame; [log](../log/2026-10-18-hit-impact-exaggerated.md)). The user said it's how
  they imagined it. Tune in `CombatConfig.HitImpact` / `Hitstop`.
- **Dash afterimages** (battlegrounds step 2) are built ([log](../log/2026-10-18-dash-afterimages.md)).
  Battlegrounds step 3 (enemy reactions) and 4 (slash crescents) are next there ([[battlegrounds-combat]]).
- **Priority 1: the perf pass** is built (8 steps); not re-tested on the phone since the streaming fix.
  The target device is now an **average or weak phone**, not the user's iPhone 14. Four earlier choices to
  re-check for weak phones (the user hasn't decided): phones on Automatic start at Medium, ShadowMap
  shadows, streaming 768/128, Medium's decor 75% and 12 lights. Details: [[perf-polish-handoff]].
- **Priority 2: the main issue** ([[main-issue-dueling-vibe]]).
- **Art in Blender:** the user asked that all new animations **and 3D models** be made by Claude in
  Blender (not Claude Design). No model-building script exists yet.

## Not playtested yet
Nothing from this session was playtested in Studio by Claude (skip-playtests rule): the new Sword combo
in game, the exaggerated hit feel, the dash afterimages. Their checks are in [[perf-final-check]].

## Claude's first moves next session
1. Ask how the published Sword combo and the new hit feel play in game (and whether the place was saved
   and published so live servers have them).
2. If the user says "do the animation remake": read [[animation-style]] and do the next weapon in
   [[weapon-anim-remake]] (author in the scratchpad, fix the report, previews, `combo.sh`, show the user,
   stage when they like it).
3. Before any Studio check, confirm Studio has the latest code (Rojo plugin connected).

## How the user wants to work (keep to it)
- One step at a time: explain it, wait for the OK, do it, log it in `notes/log/`, tick it, push to
  origin/main.
- **No per-step phone checklists.** Claude checks each step itself (syntax, edit-mode
  `execute_luau`, a short console-only playtest only for risky steps). Device checks are batched
  into [[perf-final-check]], so add new checks there.
- The baseline device is an average/low-end Roblox phone (minimum spec), not the user's iPhone 14
  (2026-10-18: "that's just my phone"). The iPhone 14 is the phone they test on. The user's Mac is slow, so keep Studio playtests short
  and skip screenshots.
- The user's Roblox account is **ColePalmer6954**; that "joined live editing session" line is them.

## Gotchas from this session
- New Studio has no `Lighting.Technology`: ShadowMap = `LightingStyle` Realistic +
  `PrioritizeLightingQuality` off. Scripts can set those two.
- Scripts can't read or write Workspace streaming properties. They're now set from
  `default.project.json`, so a Rojo reconnect applies them.
- A changed `default.project.json` (new service entries or properties) needs a Rojo **reconnect**.
- To move a test character in a playtest, move it from the **client** (the server's PivotTo gets
  snapped back).
- `rbxassetid://203785492` in the Output is a Studio plugin's sound, not the game: ignore it.
- The sword generator rewrites other clips with renumbered IDs: `git checkout --` everything you
  didn't mean to change after running it.
- Blender: objects imported from a .glb turn by **quaternion**; keying `rotation_euler` on them does
  nothing (the combo viewer's sword once kept one angle). Still renders don't catch this: check playback.
- To confirm the user published a clip over its asset, read its latest revision time through Open
  Cloud (`roblox_assets.call('GET', f'{BASE}/<id>?readMask=revisionId,revisionCreateTime')`) and compare
  it with when the clip was staged.
- Blender on the user's Intel Mac draws the viewport slowly at Retina size: playback under 30 fps there
  is the GPU, not the animation. The combo viewer's videos play smoothly.
