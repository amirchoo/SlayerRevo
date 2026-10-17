# How each weapon works, and how to animate it

Research for the weapon animation remake ([[weapon-anim-remake]]), done 2026-10-18 before the remake
starts (the user: "research about each weapon type so you'll know how it works and how you can animate it
with more details"). Real technique first, then how action games stylise it, then what that means in our
style ([[animation-style]]: exaggerated, battlegrounds-like, snappy front, held back half). Each weapon's
moves and hit times are from `CombatConfig`; keep the hit times unless the user agrees to a change.

Every weapon also gets a **walk (carry) clip** in the remake (the user's call, 2026-10-18, after the
Arcane Atelier video, [[arcane-atelier-reference]]): see "The walk" at the end.

## What makes a weapon look heavy or light (applies to all)
- **Timing is the weight.** Heavy = longer wind-up, a hang at the top, longer held end pose; light =
  almost no wind-up, short holds. The pose can be just as big either way. ([Gnomon: stylized attacks](https://bmc.thegnomonworkshop.com/workshops/animating-stylized-attacks-in-maya))
- **Follow-through is where the player feels the effort**, because games leave little room for
  anticipation: push the follow-through pose further, keep the hit time fixed. ([Polycount critique](https://polycount.com/discussion/comment/2507079))
- **Startup / active / recovery**: our HitDelay is the startup; the cooldown is the recovery. A heavy
  weapon spends its time in startup and recovery, never in a slow cut: the cut itself is always fast.
- **Heavy weapons are driven by the legs and hips**, not the arms: the hips turn first, the arms and
  head of the weapon lag and then whip through. A big two-handed blow turns the body to face the other
  way by the end. ([sledgehammer/war hammer notes](https://graphsearch.epfl.ch/en/concept/13802), [kettlebell swing](https://evofitness.de/en/magazine/training/tutorial-kb-2-hand-swing))
- **The weapon's head lags the hands** (overlap): the heavier the head, the more frames of lag.
  Our script already has a blade lag of 1 frame; heavies want 2–3.
- **VFX carry the arc** (Arcane Atelier): the clearest frames are the wind-up and the end pose, so those
  two silhouettes must read on a phone.

## Light weapons
### Rapier (the user's own weapon; first after the Sword)
- **Real:** a thrusting sword. The fencing lunge: **the arm extends first, then the body goes**; the back
  leg drives off the ball of the foot and straightens, the front knee bends over the foot, the back foot
  turns. The free arm is thrown back (and often down) for balance as the body goes forward. The lunge is
  for covering distance: there's no blade work during it.
  ([Biggs, the lunge](https://davidbiggs.substack.com/p/the-lunge-and-its-mechanics-part), [Windsor, Max your lunge](https://www.guywindsor.net/wp-content/uploads/2013/03/Max-Your-Lunge-2007.pdf))
- **Body:** side-on (profile) to the target: the right shoulder forward, the chest turned ~60–80° so
  the arm reaches further and the body is a thin target.
- **Our moves:** Thrust1–3 (hits 0.12, 0.11, 0.20; Thrust3 lunges 32, knockback), WindUp + Flurry
  (3–8 stabs, 0.08 s apart).
- **In our style:** each thrust from a different line (high outside, low inside, then a full lunge), so
  it's not one stab three times. Hand turned palm-down (pronated) on the hit. Thrust1–2: the arm snaps
  out from the hip with a small hop of the front foot; Thrust3 = an exaggerated fencing lunge: feet ~2.5
  studs apart, back leg straight, free arm flung back, chest low over the front knee, a hold, then a
  quick recovery back to guard. Flurry: the body stays planted and leaning in, only the arm pistons;
  vary the height of each stab a little so it reads as many.
- **Walk:** light and springy, the blade tip up and forward, the free hand up behind (fencer's pose),
  small bounce. The one weapon that should *not* trail.

### Dagger
- **Real:** fast cuts and stabs at contact range; the body stays close and low, the free hand is up to
  grab or guard.
- **Our moves:** Slash1–2, Stab3–4 (hits 0.10 ×3, 0.16; Stab4 lunges 18), Guard, WindUp + Backstab.
- **In our style:** tiny wind-ups (2–3 frames), wrist-driven slashes in an X (forehand, backhand), then
  a short stab and a dashing lunge stab. A crouched, forward-leaning stance. Ends barely hold.
  The Backstab: a coil (the dagger drawn back by the ear) and a full-body drive.
- **Walk:** a low prowl, the dagger held low by the hip, blade forward, the off hand loose.

### Dual Blade (needs left-hand weapon controls first)
- **Real / games:** alternating blades read better than both at once: while one cuts, the other chambers
  for the next cut, so the loop never stops. ([Enshrouded dual wield request](https://enshrouded.featureupvote.com/suggestions/523961/comment/592234))
  Watch out for an idle that doesn't match the attacks' grip ([Dark Souls II thread](https://steamcommunity.com/app/236430/discussions/0/627456486330713645/?l=german)).
- **Our moves:** Slash1 (right), Slash2 (left), Slash3 (right, spinning), Slash4 (both, lunge 24, a
  cross); hits ~0.10–0.16. Guard, WindUp + Rush.
- **In our style:** the right cut chambers the left behind the body, then the left whips out; Slash3 a
  full spin with both arms out wide (a whirl); Slash4 both blades crossed high then torn apart in an X.
  **Controls needed:** a second weapon in the left hand (lgrip, lblade, ledge) in the authoring script.
- **Walk:** both blades held low and back, arms swinging a little wide.

## Medium weapons
### Sword (combo done) and Emberfang (shares the Sword's clips)
- The combo is the reference. The rest: Idle (check it fits the new combo's stance), Guard (blade
  across the body, the off hand bracing the flat), Spin (heavy: a full turn with the arm out, the blade
  flat, a crouch into it and a skid out).
- **Walk:** the Arcane Atelier carry: the sword low in the right hand, tip down and trailing behind, the
  arm hanging back, swaying with the steps.

### Axe
- **Real:** the weight is all in the head. A chop is a lever: the hands lead, the head lags, then snaps
  through; it buries into what it hits, so the follow-through stops short and has to be pulled out.
- **Our moves:** Chop1–3 (hits 0.20, 0.17, 0.31; Chop3 knockback 25), WindUp + Cleave (a leap, Bleed;
  the cleave holds the axe the other way round: `FlipGrip`).
- **In our style:** diagonal and overhead chops (not flat sweeps: that's the sword), with a short hard
  stop at the hit (a "thunk"), shoulders hunched over it, then a tug to pull it free. Chop3: a two-handed
  overhead from a big back-arch. The cleave: a leap with the axe over the head and a crashing landing.
- **Walk:** the axe hanging from one hand, head down by the knee, swinging like a pendulum.

### Mace (gets its own combo; today it reuses the Sword's old swings)
- **Real:** a blunt weight on a short handle: short, hard, bludgeoning blows; less wrist, more shoulder.
- **In our style:** overhand smashes and a backhand clubbing blow, short arcs, a bounce-back at the hit
  (it rebounds instead of cutting through). WindUp + Slam (Quake): raised overhead in both hands,
  driven into the ground.
- **Walk:** resting on the shoulder or hanging heavy, head down.

### Spear
- **Real:** two-handed; **the rear hand drives** and the front hand guides. Two thrusts: shove with both
  hands (shorter, harder), or "shoot" it through the front hand with the rear hand (longer reach). The
  body is side-on, the rear side moving out of the line as the front foot steps.
  ([Shaolin spear thrust vs shoot](https://shaolin.org/video-clips-3/weapons/spear-2/spear13.html), [Wudang qiang](https://wiki.wudang.academy/article/weapons-qiang))
- **Our moves:** Thrust1–3 (hits 0.13, 0.12, 0.20; Thrust3 lunges 40, knockback 18), WindUp + Lunge.
- **In our style:** Thrust1 a quick shove, Thrust2 a "shoot" (the shaft slides forward through the left
  hand; the left hand stays, the right hand travels), Thrust3 a running lunge with the whole body behind
  it. The shaft stays nearly level and on the line to the target; the tip leads, never wobbles.
  Two-handed: `"offhand_space": "world"` (the left hand on the shaft); a slide needs the left hand keyed
  along the shaft rather than at a fixed grip point.
- **Walk:** the spear sloped over the shoulder or held at the balance point, tip forward and up, butt
  trailing low.

## Heavy weapons
### Hammer
- **Real:** legs and hips first; the arms raise it, the drop does the work; it hits the ground and stays
  there a beat. Two-handed: the body turns to face the other way by the end of a big swing.
- **Our moves:** Pound (0.36, shockwave), Swing (0.33, 220° arc), Crush (0.46, lunge 18, shockwave),
  Guard, WindUp + Slam (Quake, charged).
- **In our style:** long wind-ups with a **hang at the top** (2–4 frames held), a fast drop, the head
  lagging 2–3 frames behind the hands, a squash at impact (knees bend, the body sinks), a hold with the
  head in the dirt, and a heave to lift it. The Swing: a hip-led horizontal sweep that drags the body
  round. The Slam: a leap or a full overhead, the body almost folding over it at impact.
- **Walk:** the hammer on the shoulder, or dragged by the handle, head scraping behind: the heaviest
  carry.

### Greatsword
- **Real / games:** a long, heavy two-hander: hip-led sweeps whose momentum carries the body; the
  wind-up loads the back leg. Monster Hunter-style: slow, wide arcs and a charged overhead slam.
- **Our moves:** Swing1–2 (0.30, 0.29, 200° arcs), Swing3 (0.42, a 360° spin, knockback 30), Charge
  (frozen on its last frame) + Slam (0.13 after release), Guard.
- **In our style:** wide horizontal sweeps with the whole body turning; Swing3 a full spin that the blade
  pulls you through; the Charge: the blade raised high behind the head, the body coiled and trembling;
  the Slam: everything comes down together (a "sudden" slam).
- **Walk:** dragged: the tip on the ground behind, or rested on the shoulder.

### Scythe
- **Real / games:** the cut is a **pull**: the curved blade hooks in and is drawn back toward you
  (reaping), sweeping low and wide. Hold briefly at the top, then start the cut fast and slow toward the
  end for weight. ([gamedev.net scythe critique](https://gamedev.net/forums/topic/706618-feedback-on-attack-animation))
- **Our moves:** Slash1 (forehand sweep, 200°), Slash2 (full spin, 360°), Slash3 (crescent, lunge 20,
  knockback 18), hits 0.20–0.26; Guard; Reap (heavy: hook then cut).
- **In our style:** big, graceful arcs; the left hand high on the snath, the right low; the blade sweeps
  past at knee-to-waist height and is drawn back. The spin uses the scythe's momentum; Slash3 a rising
  crescent. The Reap: the hook (a pull that drags the target in), a beat, then the cut.
- **Walk:** carried upright like the Grim Reaper, or over the shoulder with the blade hanging behind.

## Ranged and casting (new controls first, as the remake note says)
### Bow
- **Real:** side-on stance; draw with the back, not the arm, to a fixed **anchor** (the jaw or the
  corner of the mouth); release by relaxing the fingers; **follow-through**: the bow arm stays pointed,
  the draw hand flies back toward the shoulder. ([shot process](https://startarchery.co.uk/learn/what-is-a-shot-process), [4-H handbook](https://4h.extension.msstate.edu/sites/default/files/2024-02/P3249_web.pdf))
- **Our clips:** Idle, Charge (drawing, held on its last frame), Shoot. The bow is in the right hand
  (`Hand = "Right"`), so the draw hand is the left; check against the bow model before posing.
- **In our style:** a snappy raise, a big draw with the elbow high and the chest opening, a shake at full
  draw (or let VFX do it), the release flinging the draw hand back.
- **Walk:** the bow held low in one hand, string forward.

### Crossbow
- **Real:** stock to the shoulder, cheek on the stock; a light crossbow is spanned with a **goat's-foot
  lever** (hooked on the stock, pulled back) or a belt hook (squat and stand). ([Tod's Workshop spanning methods](https://todsworkshop.com/blogs/blog/crossbows-spanning-methods))
- **Our clips:** Idle (held low), Aim (raised, held), Shoot (the kick), Reload (stretched to 1.3 s).
- **In our style:** Shoot: a sharp kick up and back through the shoulders. Reload: tip down, foot on the
  stirrup, a lever pull, a bolt slapped in: readable in 1.3 s.
- **Walk:** held across the body in both hands, muzzle down.

### Blunderbuss
- **Our clips:** Idle (low by the hip, muzzle down), Aim (arm out straight), Shoot (the kick throws the arm
  up), Reload (broken open, a shell from the belt thumbed in, flicked shut; it borrows the crossbow's now).
- **In our style:** a huge recoil: arm thrown up, a step back, the body rocks. A swaggering reload with a
  flick shut.
- **Walk:** propped on the shoulder, muzzle up.

### Staff and Grimoire
- **Games:** a cast reads as anticipation (staff pulled back low, body coiled) → a peak where the
  silhouette changes most (staff thrust forward, robe and arms flared) → recovery to the idle.
  ([caster sheet breakdown](https://www.summerengine.com/asset-store/cultist-attack-sheet-4dir-x-4f-02c530b5))
- **Staff clips:** Idle, Cast (light), Charge (raised while charging), Blast (heavy release), Slam (Fire's
  heavy, not made yet). Cast: a quick jab of the staff head toward the target. Charge: raised overhead,
  the body opening up. Blast: thrust out with both hands, a step in. Slam: the butt driven into the ground.
- **Grimoire clips:** Idle, Cast, Charge, Blast (`Grip` turns the book): the book open in one hand, the
  other hand does the gesture (a palm push to cast, both hands up to charge, a push to release).
- **Walk:** the staff used like a walking stick, planted every other step; the grimoire held to the
  chest.

## The walk (carry) clip, for every weapon
- **What it is:** an upper-body-only loop (`upper_body_only`, like the `Moving` twins) played instead of
  the weapon's idle while you're moving, so the legs keep Roblox's walk and the arms carry the weapon.
  Blends back to the idle stance when you stop. Code: `ComboWeaponClient` (and the bow/crossbow/staff
  clients) switch idle ↔ walk on `Humanoid.MoveDirection` (a short blend, ~0.2 s).
- **How to make it heavy** (Arcane Atelier and the sources): the weapon trails behind the hand and lags
  it ([student walk cycles](https://abarai.myblog.arts.ac.uk/category/3d-computer-animation-fundamentals/page/2/)); the chest and shoulder angle round to support the arm; the weight shifts
  side to side with the steps; the push-off is late and slow for a heavy load. The arm swings back with
  each step and the weapon swings a beat later.
- **Timing:** match Roblox's default walk cycle so the arm swing lands with the steps (measure the
  default walk's cycle length at our WalkSpeed before authoring). Light weapons bounce; heavy ones sway.
