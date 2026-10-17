# Battlegrounds-style combat: reference breakdown

Source: TikTok by skaterstudios ("Day 2 learning scripting / air combat / weapons"),
`~/Downloads/v29025g50000dal5dlnog65oqfnmnrdg.MP4`, 22.5 s, 576×1024 at 30 fps (about 18 s of gameplay).
Studied frame by frame at 10 fps. This is the target feel for melee and for future PvP.
Related: [[main-issue-dueling-vibe]], [[sword-swing-animation]].

## What's on screen, beat by beat

| Time | What happens |
|---|---|
| 0:00–0:02 | Fist M1 chain against "Dummy [Hard]". Every hit: the attacker steps in, the dummy flinches with a different pose, a white slash arc, a white flash on the target, small "-1" numbers. |
| 0:00.3–0:00.8 | **Afterimages**: 3–4 see-through white copies of the attacker trail behind a fast move (a dash-punch). |
| 0:01.6 | **Impact frame**: one frame where the target goes dark/black with a red blood burst and red star-shaped slash lines. It sells the hit more than anything else. |
| 0:02–0:02.5 | Combo ender: the dummy is knocked far back and ragdolls; white **speed lines** cross the screen, then the attacker dashes after it (white burst at their feet). |
| 0:03 | Gold ring with sparks around both: a counter or perfect-block burst. |
| 0:04 | Big red magic-circle slash: a special or ultimate move (a red ring decal with slash marks, filling the screen). |
| 0:06–0:09 | **Air combat**: an uppercut launches the dummy and the attacker jumps after it. Both **hang in the air** while an air combo lands (white lightning streaks), then a **down-slam**: the dummy drives into the floor, a **crater of rock chunks** bursts out, dust rises, the camera shakes. |
| 0:11–0:14 | **Weapons**: a long katana. Each swing leaves a wide, **crescent-shaped white slash** (a mesh, not a thin trail) the full length of the arc, with orange sparks on contact. The target gets red cross-shaped cut marks. |
| 0:15–0:18 | Rapier or thin-blade moves: gold spark bursts, thin thrust lines. |

## Why it feels smooth (the animation side)

1. **Almost no wind-up, long follow-through.** Contact comes 2–4 frames (≈0.07–0.13 s) after input.
   The pose then *holds* in the extended position for several frames before recovering. Responsiveness
   comes from the short front; weight comes from the held back half.
2. **Whole-body poses, not arm swings.** Hips and torso twist hard into every hit, the back foot pivots,
   and the head leads. The silhouettes are extreme (a deep lunge, a full spin), so they read even at small size.
3. **Every M1 is a different pose** (left, right, low, then the ender), so a chain never looks like a loop.
4. **The target animates too.** A unique flinch per hit direction, and a stagger that moves the whole
   body. Half of the "smooth animation" in the video is actually the *victim's* reactions.
5. **Root motion / step-in.** The attacker slides forward a stud or two on each hit and keeps the distance
   to the target constant, so hits never whiff in a chain.
6. **Short blends** (≈0.05 s fade-in) between combo steps, so one clip snaps into the next with no float.

## How it's scripted (standard battlegrounds pattern)

These games (TSB, Dueling Grounds, this one) nearly all use this layout:

- **Client predicts, server decides.** Pressing M1 plays the swing at once on your screen and sends a
  remote. The server checks cooldown, combo step, and whether you're stunned, then runs the hitbox itself
  at the swing's hit time (a box via `GetPartBoundsInBox`), or checks a client-reported hit against distance
  and timing.
- **Stun is a state, not an animation.** Getting hit sets a short "Stunned" timer (an attribute) on the
  victim, about 0.4–0.6 s per M1, slightly longer than the gap between hits. That's what makes a 4–5 hit
  combo *true* (it can't be escaped). While stunned, the server ignores the victim's attacks, and their
  client blocks input and slows walking.
- **Knockback** comes from a velocity mover (LinearVelocity / AlignPosition) for a fixed time. The ender
  pushes far and switches the victim to ragdoll (Motor6Ds/joints turned into BallSocketConstraints) for about 1 s.
- **Air combos**: the launcher gives both bodies an upward velocity, then an AlignPosition / zero-gravity
  hold keeps both floating while the air hits land. The slam pulls the victim down fast; on landing it
  spawns the crater.
- **VFX are client-side.** The server fires one "effect" remote to everyone (effect name, position, target),
  and each client spawns the particles, slash meshes, crater rocks and impact frame locally, so the server
  stays light.
- **Hitstop + camera.** A 0.05–0.1 s freeze of both animations, a small FOV punch (+3–5° then back),
  and a short shake scaled by hit strength.
- **Impact frame**: for one or two frames, a full-screen ColorCorrection (inverted or very high contrast)
  plus a black Highlight on the target, then off.
- **Afterimages**: clone the character's visible parts each 0.03 s during a dash, make them see-through
  and white (or a Highlight), and fade them out over about 0.2 s.
- **Craters**: a ring of 8–14 cubes placed by raycasting down around the impact, tilted outward, tweened
  up from below the floor, then sunk away after a few seconds. Debris chunks get an outward velocity.
- **Slash crescents**: a flat curved MeshPart (or a Beam) with a white-to-clear gradient, placed along the swing arc
  and tweened in scale and transparency over 0.15 s. That's why the arcs look wide and clean, unlike a Trail.

## How Slayer Revo compares today

| Feature | Us | Notes |
|---|---|---|
| Hitstop | ✅ `HitFeel.luau`, `CombatConfig.Hitstop` (0.04–0.1 s) | Matches the video. |
| Step-in / lunge per hit | ✅ `ComboWeaponClient` (Lunge, stepIn) | |
| Hit flares, parry flash | ✅ (main issue step) | |
| Camera shake | ✅ on block, when hurt, greatsword, shockwave | No shake *when you land* a hit yet, and no FOV punch. |
| Lock-on duel camera | ✅ `LockOn.luau` | |
| Enemy flinch | ✅ `EnemyEffects` (one flinch clip) | The video uses a different flinch per hit plus a stagger. |
| Player hit reactions / stun | ❌ | Needed for PvP. |
| Knockback + ragdoll ender | ❌ (only `Push` on block) | |
| Afterimages on dash | ✅ `DashEffects.luau` (pooled trail) | |
| Impact frame | ❌ | Cheap to add, big payoff. |
| Wide crescent slashes | partly (trails) | Main issue step 5 (trails) could switch to crescent meshes. |
| Air launch / air combo / slam crater | ❌ | Biggest piece of work. |
| Hitting players | ❌, on purpose: `MeleeHitbox` skips players (co-op, no friendly fire) | |

## What PvP would need on top

The user's plan (2026-10-18): on-the-spot duels, started from an "interact" button on another player
(Duel is its first option). Duel rules are still open in `docs/design.md` §10.

- A shared **stun/state module** (Stunned, Blocking, Ragdolled, Airborne, Iframes) that the server owns and
  every action checks. Players and enemies would both use it.
- `MeleeHitbox` gains a "may hit this player" check (in an arena, or both players in a duel).
- **Knockback on players**: players own their character's physics, so the server puts the mover on the
  victim and, to keep it smooth, also tells the victim's client to apply it right away.
- **Lag fairness**: the hitbox runs on the server against positions rewound by about half the attacker's ping
  (or a client-reported hit, checked for range and timing). Without this, hits feel random above ~100 ms.
- **Anti-exploit**: rate-limit attack remotes (`RemoteGuard.luau` exists), cap knockback, and never accept
  damage, stun or position values from the client.
- Block / parry / guard-break and **combo escape** (a burst or dash-out that costs a resource), so a
  true combo can't chain forever. Video games cap a chain at about 4–5 M1 + 1 skill.

## Suggested order (cheapest feel first)

1. ✅ Impact frame + FOV punch + shake on landing a hit ([log](../log/2026-10-18-hit-impact-frame.md)).
2. ✅ Afterimages on dash ([log](../log/2026-10-18-dash-afterimages.md)).
3. A different flinch per combo step + a knockback-and-ragdoll ender (works on enemies now, players later).
4. Crescent slash meshes instead of trails for the sword and katana.
5. Stun-state module (needed by both PvE bosses and PvP).
6. Launcher → air combo → slam crater.
7. PvP itself, once the design question is answered.
