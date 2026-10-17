# Handoff: start here next session

Written 2026-10-17 at the end of the third session; the user is switching to their Mac.
**Say "read the handoff" (or "continue") in a new session**: Claude reads this note first, then
the two notes it points to. Update this note at the end of every session.

## Where things stand
- **New (2026-10-18): battlegrounds-style combat, then PvP duels.** The user sent a reference video
  ("that's where we're getting to"). It was analysed in [[battlegrounds-combat-reference]], and the
  plan is the step list in [[battlegrounds-combat]]. Steps 1 (shake, zoom punch, impact frame) and 2 (dash afterimages) are done
  but not playtested. **First:** ask how hits feel, then continue with step 2 when the user says
  "do the battlegrounds task". PvP duels are step 7; ask the user for the duel rules before building it.
- **Perf pass (priority 0): all 8 steps are built.** The user's first phone test showed no lag,
  but trees and ground were missing (memory: streaming was on defaults). Fixed in
  `default.project.json` ([log](../log/2026-10-17-streaming-fix.md)); not tested on the phone yet.
  Details: [[perf-polish-handoff]]. The user's checklist: [[perf-final-check]].
- **Main issue (priority 1): the Sword's swing recovery was reworked** after research on soulslike
  animation ([research](../research/sword-swing-animation.md), [log](../log/2026-10-17-sword-recovery-blend.md)).
  The new clips are staged but **not published yet**. Details: [[main-issue-dueling-vibe]].
- **Damage raise** (Sword 33/41/65, Emberfang 42/52/85, Mace 40/47/87) is committed but hadn't
  reached Studio (Rojo had stopped).

## Waiting on the user (in this order, on the Mac)
> 2026-10-18 (latest): the Sword combo was redone, exaggerated ([log](../log/2026-10-18-sword-combo-exaggerated.md)). SwordSwing1–3 and their Moving twins are staged in `Workspace.Rig.AnimSaves`. **First:** ask whether they were published over the existing IDs and how the combo plays. Next after that: slash crescents (battlegrounds step 4). Watch clips with `tools/blender/combo.sh Sword`.
> 2026-10-18 (latest): SwordSwing1–3 were re-authored in Blender ([log](../log/2026-10-18-blender-anim-authoring.md)) and are staged in `Workspace.Rig.AnimSaves`. Published 2026-10-18 (Swing 1 is the new 104914800619644; 2 and 3 were written over). **First:** ask how the new Sword combo plays. New clips are now made with `tools/blender/author.sh` (data in `tools/blender/*_clips.py`).
> 2026-10-18 (later): the Sword was redone katana-style and the four clips are published and in ([log](../log/2026-10-18-sword-katana-redo.md)). **First:** ask how the new Sword plays.
> 2026-10-18: steps 1 and 2 are done (Rojo connected; Sword IDs in, [log](../log/2026-10-18-sword-recovery-ids.md)). Step 3 and a Sword playtest are left.

1. **Start `rojo serve` and connect the plugin.** The Rojo server stopped mid-session, and the
   project file changed, so a fresh connect is needed. It brings in:
   - the streaming settings (Workspace: 768 / 128, Opportunistic, MinimumRadiusPause)
   - the loading screen (ReplicatedFirst)
   - the CombatConfig damage raise
2. **Publish SwordSwing1, 2, 3** from `Workspace.Rig.AnimSaves` in the Animation Editor (Claude put
   them there; they're the new 0.98 / 0.96 / 1.20 s clips). Send the three IDs.
3. **Save and publish the place**, then go through [[perf-final-check]] on the phone and the Mac.

## Claude's first moves next session
1. Ask whether steps 1–3 above are done. If the user sends the Sword IDs, put them in
   `CombatConfig` `Sword.Combo` (Emberfang and Mace reuse them) and SwordSwing3's in
   TrainingStands, then commit.
2. Check with `script_grep` / `execute_luau` that Studio has the latest code before any playtest
   (CombatConfig Sword swing 1 should read `Damage = 33`). If not, ask the user to reconnect Rojo.
   Don't push sources in by hand.
3. Then act on the user's feedback:
   - **Phone check results:** fix what's reported (tuning knobs are listed in each step's log).
     If the far hills vanish, raise `StreamingTargetRadius` to 1024 and keep the rest.
   - **Sword feel:** if it's right, give the **Rapier** the same recovery next (the user plays it).
     It's in step 1c of the main issue; the recipe is in the research note and SwordSwing1–3 in
     `tools/sword_anims.py`. If it still feels stiff, ask what exactly (the return, the strike,
     the wind-up) before changing more. An unused idea: step-in root motion on each swing.

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
