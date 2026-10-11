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

## Design
- Read `docs/design.md` before building any system: it's the source of truth for game direction.
  Its §12 lists where already-built systems differ from it (the built version wins).
- Work one system/phase at a time; don't decide its [TBD] items without asking.
