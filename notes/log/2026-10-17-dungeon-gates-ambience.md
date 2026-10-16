# Dungeon gates fixed, grim dark ambience

**Asked:** a gate looked broken (a portcullis frame standing free in a wide cave, a gap beside
it, the lifted door poking out above); make the dungeon grim, dull and dark.

## Gates
The carved rock was cut back past the grid everywhere, gates included, so a 14-wide gate stood
in a ~20-wide passage. Now [DungeonTerrain](../../src/server/DungeonTerrain.luau) takes the gate
points (`DungeonBuilder.gatePoints`: every `+` square and across the arena doorway) and fades
the cut-back to nothing within a square of them (`roughness`, full again 1.5 squares further).
Measured at the saved layout's gates: room gates 11.7–14.5 wide, ceiling ~16.6; arena gate
15–18 wide (inside its 18.9 frame), ceiling 17.3. The frames and the lifted door sink into rock.
`carve` also takes `within` (redo just part of a layout): used to re-carve only the three gate
areas of the saved layout, so hand edits elsewhere were kept. One torch near a gate was moved
onto the new wall and one buried rock removed.

## Ambience
- `LightingConfig.Dungeon`: no sun (Brightness 0), dim cold ambient (34,33,38), almost no sky
  reflection, Saturation -0.35, Contrast 0.18, a dark murky Atmosphere, weaker bloom, no sun
  rays. [DayNight](../../src/client/DayNight.luau) switches to it while the player has the
  `Dungeon` attribute and puts the world's look back after.
- Torch and brazier light dimmer and less orange: `TORCH_LIGHT` (22, 1.3), `BRAZIER_LIGHT`
  (38, 1.6), colour `COLORS.FireLight` in DungeonBuilder; the saved layout's 50 lights updated.

## Open
- Not playtested: check it isn't too dark to fight in (raise `Dungeon.Lighting.Ambient` or the
  torch brightness if so).
