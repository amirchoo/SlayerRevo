# Chests spill spinning gold coins

**Asked:** a chest drops lots of rotating gold coins; the amount gained is RNG. (Decides the
chest-loot [TBD] for dungeon chests; the world's 12 scenery chests are still [TBD].)

## What happens
- Opening a dungeon chest: banner "The chest spills gold!", the lid swings, and after
  `LID_DELAY` (0.35 s) each member of the run gets their own pile: `ChestCoins.Shown` (20) gold
  coins bursting out of the chest and landing in front of it (within ±70° of its facing,
  1.5–5.5 studs out). Others' piles are hidden (per-player loot, like meat drops).
- Each member's total is rolled separately: `chestRandom:NextInteger(Min, Max)` (25–50,
  [DungeonConfig](../../src/shared/Config/DungeonConfig.luau) `ChestCoins`) and split across
  the coins (some worth one more). Walking within `Loot.PickupRange` (7) picks a coin up and
  pays it into CurrencyService on the server.
- Coins last `COIN_LIFETIME` (900 s) instead of loot's 120 s.

## Code
- [LootService](../../src/server/LootService.luau) `dropCoins(owner, total, from, front, count)`:
  part-built coin (gold metal disc on edge, no shadow), attributes Owner, Item "Coins", Coins
  (worth), From; drops now carry their own lifetime and coin value.
- [LootClient](../../src/client/LootClient.luau): coins pop out like other loot, then spin upright
  at 4.5 rad/s (no tilt), sparkle (no PointLight each: too many), fly into you on pickup, and
  coins picked up within 0.35 s of each other show one "+N Coins".
- Chests carry `front` (DungeonBuilder) so coins land away from the wall.

## Open
- Not playtested. Possible later: a rare jackpot roll, coin sound on pickup, the world chests.
