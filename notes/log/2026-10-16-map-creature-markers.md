# Orcs and animals on the map

2026-10-16 · not playtested

## Asked
A red icon on the map where orcs are, and brown for cows and chickens.

## Changed
- [Map.luau](../../src/client/Map.luau): markers on the minimap and the world map
- [design.md](../../docs/design.md): the §12 Map row

## How it works
- **Markers:** enemies are red diamonds; wild animals are brown dots. Players stay blue circles.
- **Minimap:** shows only the creatures inside its window. They aren't pinned to the rim, because there are too many.
- **Left off:** dead creatures, other players' sparring orcs, and the tame animals in town.
- **Updates:** the list of creatures is rescanned every 0.25 s (`MOB_SCAN_TIME`); positions update every frame.

## Open
- If the place has streaming turned on, only nearby creatures show. Showing every pack worldwide would need the server to send their positions.
