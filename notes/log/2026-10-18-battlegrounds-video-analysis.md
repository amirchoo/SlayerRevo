# Battlegrounds combat video analysed (reference for melee feel and PvP)

**Asked:** analyse the downloaded TikTok (skaterstudios, fists → air combat → weapons) as the target for
smooth animation and future PvP, and work out how its animation and scripting work.

**Done:** studied frame by frame (2 fps overview, 10 fps bursts of the M1 chain, the air combo and the katana).
Wrote it up in [[battlegrounds-combat-reference]]: a beat-by-beat breakdown, why the animation reads as smooth,
the usual battlegrounds scripting pattern (client prediction, server stun state, knockback/ragdoll, air hold,
client-side VFX, impact frames, afterimages, craters, crescent slashes), a comparison with what Slayer Revo has,
what PvP would add, and a suggested build order.

**No code changed.** Not playtested (nothing to test).

**Open:** PvP is still [TBD] in docs/design.md §10; its form (arena, duels, open world) is the user's call.
Which items from the suggested order to build first.
