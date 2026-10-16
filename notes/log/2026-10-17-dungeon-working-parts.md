# Dungeon gates, chests and exit editable in Studio

**Asked:** couldn't select the arch (a gate in the locked Guide) to tweak it; make everything
in the dungeon customizable in Studio, like the town.

## How it works now
The saved layout (`workspace.DungeonLayouts.Grimgorg`) is copied into each run as saved:
terrain, **Decor**, and now **Working** (replaces the locked Guide). Working holds the gates,
chests and exit; [DungeonBuilder](../../src/server/DungeonBuilder.luau) `readWorking` finds them
by attributes, wherever they stand:
- **Gate** model: `Gate` true, `Room` (Rooms index, 0 arena, -1 none: stays open), `Squares`
  (grid square indices it closes, for orc routing), `Lift` (studs). What lifts is its `Door`
  child; GateSeals (invisible side walls) are inside the gate model now. Saved **shut**: a run
  takes the door's saved place as closed. A missing arena gate is rebuilt from the map.
- **Chest** model: `Chest` true; opens via a fresh prompt on `PromptAnchor` (made if missing),
  `Lid` swings about its pivot; coins spill toward the model's front (-LookVector of its pivot).
  Copy-pasting a chest makes another working chest.
- **Exit** model: `Exit` true; prompt made on its `Portal` part if missing.
- Generated runs (no saved layout) go through the same path: `buildWorking` then `readWorking`.
- [tools/dungeon_layout.lua](../../tools/dungeon_layout.lua): new `REBUILD_WORKING` flag redoes only
  the working parts, keeping terrain and Decor. Used it to convert the saved layout (Guide
  removed; 3 gates, 4 chests, 1 exit; 113 Decor pieces kept).

## Tested (edit mode)
A run built from a copy with one chest moved and one pasted: 5 chests (moved one where it was
put), exit prompt, room gates open and mapped to 4 squares, arena gate shut, lifts 15 and
closes back exactly; a chest opened. Test terrain cleared.

## Open
- Not playtested. Spawn point, orc drop spots and patrol routes still come from the Map.

## Follow-up: clicking selected the whole group
Asked: "i cant seem to inspect each item to change its attribute". Decor, Working and
GrimgorgEntrance were Models, so a click in the viewport selected the whole group. They're now
Folders like `workspace.Town` (converted in Studio by moving the children, nothing rebuilt).
DungeonBuilder moves each child on its own (`shift`), and `loadLayout` reads an older save's
Models the same way. Tested in edit mode: a run built 3000 studs over put all 113 Decor
pieces, the chests and the exit exactly 3000 over; the arena gate lifts 15 and closes back.
