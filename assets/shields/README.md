# Shield models

Synced to `ServerStorage.ShieldModels`. A file here named after a shield's id in
`src/shared/Config/ShieldConfig.luau` (e.g. `WardenShield.rbxmx`) replaces that shield's
placeholder look.

Ready to import, in `assets/source/weapons/`:

| Shield       | Import this                | Source                   |
|--------------|----------------------------|--------------------------|
| WardenShield | `WardenShield.ready.glb`   | Warden Shield (your download) |

1. In Studio: Import 3D (File > Import 3D) the file from the table above. Keep the default settings.
2. Rename the imported Model after the shield (e.g. `WardenShield`).
3. Right-click it > Save to File, into this folder, as `WardenShield.rbxmx`.

It's fitted automatically (see `src/server/ShieldService.luau`): scaled so it's
`ShieldConfig.Diameter` studs across, and worn face out on the left forearm (with a one-handed
weapon out) or on the back. The model should be round side along X/Y, thin along Z, with
its face toward -Z once imported (Import 3D turns models 180 degrees, so that's +Z in the
`.glb`). If it's worn backwards, set `ShieldConfig.FlipFace = true`.
