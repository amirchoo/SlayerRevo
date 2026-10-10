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
- Name RemoteEvents clearly and put them in ReplicatedStorage/Remotes
