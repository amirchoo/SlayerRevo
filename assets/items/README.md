# Item models

Synced to `ReplicatedStorage.ItemModels`. A file here named after an item's `Model` in
`src/shared/Config/ShopConfig.luau` (e.g. `HealthPotion.rbxmx`) or
`src/shared/Config/MaterialConfig.luau` (e.g. `CowMeat.rbxmx`) is shown in that item's shop
card, hotbar slot and backpack tile, in place of its flat icon. Materials also use it as their
look when dropped on the ground (LootService).

The meat (`CowMeat`, `ChickenMeat`) is plain Parts made by `tools/box_glb.py` from the all-box
sources in `assets/source/items/` (see `assets/animals/README.md`); the steak is stood on its
edge (`--turn-x 90`) so its face shows in the tile:

    python3 -I tools/box_glb.py assets/source/items/CowMeat.glb assets/items/CowMeat.rbxmx --turn-x 90
    python3 -I tools/box_glb.py assets/source/items/ChickenMeat.glb assets/items/ChickenMeat.rbxmx

`OrcSkin` (an orc's drop) is a hand-made placeholder of plain Parts: a green hide with tan
leather behind, corner flaps and two cords. Swap in a real model under the same name any time.

The cooked food (`CookedCowMeat`, `CookedChickenMeat`) is the same models recolored (browned
meat, golden fat); swap in your own models under those names any time.

Ready to import, in `assets/source/items/`:

| Item          | Import this               | Source                    |
|---------------|---------------------------|---------------------------|
| Health Potion | `HealthPotion.ready.glb`  | Health Potion (your download) |
| Mana Potion   | `ManaPotion.ready.glb`    | Mana Potion (your download)   |

1. In Studio: Import 3D (File > Import 3D) the file from the table above. Keep the default settings.
2. Check the imported Model is named after the item (e.g. `HealthPotion`) and holds two
   MeshParts: the bottle and `Glass`.
3. Right-click it > Save to File, into this folder, as `HealthPotion.rbxmx`.

The `.ready.glb` files are made with
`python3 -I tools/weapon_glb.py <Name>.glb <Name>.ready.glb --split glass`: the glass is kept
as its own MeshPart (any part with "glass" in its name), which the game makes see-through so
the liquid shows. Models stand upright (Y up); they're framed to fill the tile automatically.
