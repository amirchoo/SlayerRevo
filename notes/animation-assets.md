# Animation assets: which ones the game uses

Roblox can't delete an asset, only archive it. Publishing "as new" makes a new asset each time,
so duplicates pile up. **Publish over the existing asset instead** (same ID, no code change).

Read on 2026-10-18 from every ID in `src/` (MarketplaceService:GetProductInfo): 95 animations are
in use. Every name is unique except these Sword clips, which have **two live copies each**:

| Name | In use by | ID | Renamed to (2026-10-18, done) |
|---|---|---|---|
| SwordSwing1 | Sword, Emberfang | 90592657091699 | (keep) |
| SwordSwing2 | Sword, Emberfang | 99968467521543 | (keep) |
| SwordSwing3 | Sword, Emberfang, training stand | 98009756362330 | (keep) |
| SwordIdle | Sword, Emberfang | 128056004893251 | (keep) |
| SwordSwing1 | Mace (pinned to the old swing) | 105789243194617 | MaceSwing1 |
| SwordSwing2 | Mace | 125525200710497 | MaceSwing2 |
| SwordSwing3 | Mace | 108194359632313 | MaceSwing3 |
| SwordIdle | Mace | 138485130990728 | MaceIdle |

Any SwordSwing1–3 or SwordIdle with **another ID** isn't used anywhere and can be archived. Known unused
(from git history): 140482095490161, 125447325276884, 112266188901588 (Oct 10) and 101378158511989,
100925354916925, 78373052274628 (Oct 16). All six are renamed **OLD SwordSwing1–3** (2026-10-18).
Open Cloud can't archive animations, so archiving is by hand on the dashboard.

`python3 tools/roblox_assets.py info|rename|archive|restore <id>` does this through Open Cloud with the
key in `~/.config/slayerrevo/roblox-api-key` (Assets API read + write).

## Cleaning up (Creator Dashboard)
create.roblox.com → Creations → Development Items → Animations. Open a card to see its ID (in the
page address). Rename: open the card and edit its name (the ID doesn't change). Archive: the card's
⋯ menu → Archive. Only archive IDs that aren't in the table above: an archived animation may stop
loading in the game. Archived assets can be restored from the Archived tab.

To re-check which IDs are in use: ask Claude to "list the animation assets in use" (it reads the
IDs in `src/` and names them through Studio).
