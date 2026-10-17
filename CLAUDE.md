# Slayer Revo — Monster Hunter-style Roblox game

## Stack
- Luau, synced via Rojo 7.7.1 (default.project.json), toolchain managed by Rokit (rokit.toml)
- src/server → ServerScriptService.Server (init.server.luau is the entry point)
- src/client → StarterPlayer.StarterPlayerScripts.Client (init.client.luau is the entry point)
- src/shared → ReplicatedStorage.Shared
- assets/town → ServerStorage.TownAssets (Studio-imported models saved as .rbxmx; TownBuilder places them)
- assets/source → raw art (.fbx etc.), not synced; import via Studio's Import 3D, then save the result as .rbxmx into assets/town
- File suffixes: `.server.luau` = Script, `.client.luau` = LocalScript, plain `.luau` = ModuleScript

## Rules
- Edit scripts as files in src/ only, never inside Studio
- Server-authoritative: damage, health, and loot are decided on the server
- Client handles input, animations, and VFX only; never trust values sent from the client
- Use ModuleScripts for systems; keep entry scripts small
- Use --!strict type checking
- After editing scripts, run `sh tools/check_syntax.sh` (StyLua parses every script; `rojo build` doesn't),
  so a syntax error can't stop every script from loading in Studio
- Name RemoteEvents clearly and put them in ReplicatedStorage/Remotes
- The repo is an Obsidian vault (start page Home.md). After finishing each piece of work, log it in
  `notes/log/YYYY-MM-DD-<topic>.md` (what was asked, what changed, choices and tuning, what's open,
  playtested or not), add it to `notes/log/README.md` (newest first), and tick it under Done in `notes/backlog.md`

## Design
- Read `docs/design.md` before building any system: it's the source of truth for game direction.
  Its §12 lists where already-built systems differ from it (the built version wins).
- Work one system/phase at a time; don't decide its [TBD] items without asking.
- Animations and 3D models are made by Claude in Blender (headless scripts in `tools/blender/`;
  render a preview and check it before handing over). `docs/model-brief.md` still holds the look
  rules, and its last section is the steps for getting a .glb into the game.

## Priority 0: weapon animation remake
- Every weapon's animations get remade in the Sword combo's style (the user's call, 2026-10-18). The
  recipe is `docs/animation-style.md` (read it before authoring any clip); the checklist is
  `notes/tasks/weapon-anim-remake.md`. When the user says "do the animation remake", do its next weapon.
- Priority order: 0 this remake, 1 the perf pass (`notes/tasks/perf-polish.md`), 2 the main issue below,
  3 the Arcane Atelier look (`notes/tasks/arcane-atelier-look.md`; "do the Arcane Atelier look").

## Main issue
- `notes/tasks/main-issue-dueling-vibe.md` is the current main issue (combat feel and atmosphere like
  Dueling Grounds). When the user says "do the main issue", read it, do the first unticked step,
  then tick it there with a link to its log note.

## Notes (Obsidian vault)
- The repo is also an Obsidian vault. `notes/backlog.md`, `notes/bugs.md` and `notes/tasks/*.md` hold the user's
  work queue; when asked to do one, read it first, and tick its checkbox / move it to Done or Fixed when finished.
