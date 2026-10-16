# Music, ambience, coin pickup sound

**Asked:** a coin pickup sound, and songs and environment ambience for the whole game.

## What plays
- New client [Soundscape](../../src/client/Soundscape.luau), checked every 0.5 s:
  place = **Boss** (in a dungeon run, a boss with BossState Intro/Fight within 160 studs),
  **Dungeon** (the `Dungeon` attribute), **Town** (SafeZone), else **Wilds**.
  - Music: a shuffled playlist per place (`Sounds.Music`), crossfading over 2.5 s when the place
    changes; when a track ends the next one starts after 4–10 s. Overall volume
    `MUSIC_VOLUME` 0.4 (a "Music" SoundGroup in SoundService).
  - Ambience loops (an "Ambience" SoundGroup), faded in/out: `WindWilds` in the wilds,
    `CaveAmbience` in dungeons (boss fights too), `CaveTrickle` in dungeons.
- TownAmbience's birdsong/crickets are now silent in a dungeon run.
- [LootClient](../../src/client/LootClient.luau): `CoinPickup` on each coin picked up (at most
  one clink per 0.05 s, pitch varies a little).

## Tracks (all checked to load in Studio; not listened to)
In [Sounds.luau](../../src/shared/Sounds.luau), swap any Id freely:
- Town: The Miller's Drowsy Afternoon, Leaves on the Old Bridge, Fog Along the Village Path
- Wilds: Soaring Wings E, sweeping ("Serenity" 9048483776 didn't load, left out)
- Dungeon: burial, Disturb, Grave for a mage
- Boss: Epic Boss Battle, First Phase
- Ambience: Ambient wind 5799870105, Cave Ambience 273398061, Water Cave Trickle 9120505297
- Coin: Coin Pickup 113730061669739 (alternatives 4612374807, 93529351909119)

## Open
- Not playtested or listened to: the picks are by title. Swap any that don't fit.
- No music/sound volume setting in the UI yet.
