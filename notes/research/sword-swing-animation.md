# Research: how games animate sword swings (soulslikes first)

Asked 2026-10-17: the Sword swings "snap back after the animation instead of feeling smooth and
somewhat realistic". Look at how games, soulslikes most of all, animate swings and recover from them.
Applied in [[2026-10-17-sword-recovery-blend]].

## The phases of an attack
Every source splits an attack the same way: **anticipation → strike → follow-through → recovery**.
Dark Souls 3's enemy attacks are a finer cut of it ([Game Developer: Anatomy of an Enemy Attack in Dark Souls 3](https://www.gamedeveloper.com/game-platforms/anatomy-of-an-enemy-attack-in-dark-souls-3)):
1. **Opening pose:** from idle into a pose that telegraphs the attack.
2. **Attack signal:** the swing starts, but it can't hit yet. With the attack, at least ~340 ms.
3. **Attack:** the hit is live for only 2–4 frames.
4. **End pose:** the finished swing, held: ≥ 240 ms as bait, ≥ 170 ms when it leads into the return.
   Skipped or very short inside a combo.
5. **Return:** back from the end pose to idle. Usually the **longest** phase: it's the punish
   window, the price of attacking.

## What makes it read as weight, not snapping
- **Recovery is part of the attack, not an afterthought.** In soulslikes the animated recovery
  *is* the attack's cost, and the animation should match it exactly
  ([Mocap Online: Sword melee animation guide](https://mocaponline.com/blogs/mocap-news/sword-melee-animation-guide)).
  So the return to guard is animated as carefully as the strike, not a quick blend home.
- **Fast in, slow out.** Keep the wind-up and the strike fast, and **slow the deceleration after
  contact** to convey weight. Peak blade speed is about 60–70% through the arc, not at its end.
  The arc carries 30–60° past centre, and a downward strike carries toward the ground before the
  weapon is levered back up (same source).
- **The body keeps going.** The torso rotates a little past the arm before re-centring. A
  two-handed swing is powered by the trunk, not the arms (same source). This is "follow-through
  and overlapping action": the parts lead and drag in turn, and loose ends keep moving after the
  body stops ([Wikipedia](https://en.wikipedia.org/wiki/Follow_through_and_overlapping_action);
  [Game Developer: 12 principles for game animation](https://www.gamedeveloper.com/game-platforms/12-principles-for-game-animation)).
- **Arcs, always.** "Our bodies and joints are made to move in arcs" (12 principles). A return in
  a straight line, all joints arriving at once, is what reads as a snap.
- **Hold the follow-through a beat** to give the sword weight; heavier weapons get a slower wind-up
  and recovery ([Pixelblog 9: Melee attacks](https://slynyrd.com/blog/2018/9/8/pixelblog-9-melee-attacks)).
  But don't overdo the frames on player attacks: sluggish recovery feels unresponsive
  ([Wayline: indie melee combat](https://www.wayline.io/blog/level-up-indie-game-melee-combat)).
- **Combos replace the recovery.** When the next attack follows, its beginning replaces the last
  one's recovery. With no follow-up, the recovery plays out fully
  ([Game Creator melee docs](https://docs.gamecreator.one/melee/melee)). The combo window opens
  about 70% into the recovery ("earlier feels automatic, later feels unresponsive"). Each hit of
  three commits more, and the finisher has the biggest wind-up and slowest recovery (Mocap Online).
- **Soulslikes commit you.** You can't cancel until the animation has played out
  ([Wikipedia: Soulslike](https://en.wikipedia.org/wiki/Soulslike)), so the recovery is visible on
  every swing and has to look good. Elden Ring modders who open dodge windows earlier take care to
  keep "the natural looking recovery animation"
  ([Attack Recovery Overhaul](https://www.nexusmods.com/eldenring/mods/1198)).
- **Rough timings:** a one-handed swing is 0.4–0.8 s in all. At 30 fps a light attack is 20–35
  frames, a heavy one 45–80, and a two-handed heavy's recovery 0.8–1.5 s (Mocap Online; unsourced
  numbers, treat as a guide).

## What our Sword did wrong (before the fix)
1. **The return was a straight 0.22 s blend.** After the held follow-through, every joint went
   straight back to the ready stance at once: 0.50 → 0.72 s for swings 1–2, and 0.66 → 0.92 s
   for swing 3, from a deep lunge with the knee near the ground. No deceleration, no arc, no
   footwork.
2. **Swings were cut, not chained.** The next swing in the combo cut the last one off with a 0.05 s
   blend, and each swing starts from the ready stance. So the body popped toward ready before
   winding up again, even though swing 1 ends out to the left, right where swing 2's backhand
   wind-up starts.
3. **The clip dropped out on its last frame.** A non-looping clip that reaches its end stops, and
   the idle underneath (a separately published clip, not the swings' ready pose) shows at once.

## Ideas not used yet
- **Step-in (root motion):** soulslike attacks carry the character forward a little with each
  swing (a lunge for longer reach). Ours lunge with the legs but don't move the character, apart
  from the Spear/Dual Blade `Lunge` push.
- **Separate follow-through:** let a long trail or swing effect carry the follow-through, so
  control returns sooner (12 principles).
- **A heavier finisher:** swing 3's recovery is now the longest (0.8 s), as soulslikes do.
