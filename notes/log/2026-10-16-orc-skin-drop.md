# Orc Skin drop

2026-10-16 · not playtested

## Asked
Orcs should drop an item, such as orc skin, that can be sold.

## Changed
- [MaterialConfig.luau](../../src/shared/Config/MaterialConfig.luau): the `OrcSkin` material, plus a shared `Drop` type (AnimalConfig uses it too)
- [EnemyConfig.luau](../../src/shared/Config/EnemyConfig.luau): a `Drops` field; the Orc drops 1 Orc Skin, 60% of the time
- [EnemyService.luau](../../src/server/EnemyService.luau): drops loot for the killer on death (sparring enemies drop nothing)
- [ShopConfig.luau](../../src/shared/Config/ShopConfig.luau): Greta the butcher buys it for 20 coins and doesn't sell it
- [ShopPanel.luau](../../src/client/ShopPanel.luau) and [ShopService.luau](../../src/server/ShopService.luau): items in `ShopConfig.SellCategory` are sell-only (only on the Sell tab, and can't be bought)
- [OrcSkin.rbxmx](../../assets/items/OrcSkin.rbxmx): a placeholder model made of plain Parts

## Choices (easy to change)
- Who buys it: Greta. The Armorer would fit too.
- Price: 20 coins (cow meat sells for 15).
- Drop rate: 60%, one per kill.

## Open
- Crafting is still [TBD] in design.md. The skin could become a crafting material later.
- The model is a placeholder; swap in a real one under the same name.
