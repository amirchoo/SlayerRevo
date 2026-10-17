# MAIN ISSUE: Combat feel and atmosphere like Dueling Grounds

**Priority 3** (since 2026-10-18): the weapon animation remake ([[weapon-anim-remake]]), the Arcane Atelier look
([[arcane-atelier-look]]) and the polish and performance pass ([[perf-polish]]) come first.

Opened 2026-10-17. **Say "do the main issue" in a new session**: Claude reads this note, does the
first unticked step below, ticks it here (with a link to its log note), and logs it as usual.

## Where we left off (end of 2026-10-17 session)
- **2026-10-17, after the perf pass:** the user said the Sword still snaps back after a swing.
  Researched how soulslikes animate swings ([research](../research/sword-swing-animation.md)) and
  gave the Sword swings a real recovery, plus chain and end blending for every combo weapon
  ([log](../log/2026-10-17-sword-recovery-blend.md)). The damage raise is applied too.
  The user published SwordSwing1–3 and the IDs are in ([log](../log/2026-10-18-sword-recovery-ids.md)).
- **2026-10-18:** the user asked to redo the whole Sword animation the way Dueling Grounds does it.
  Studied the recording frame by frame and rebuilt the combo as a chain (each cut starts where the
  last ended), with flick wind-ups and held end poses, plus a katana idle
  ([log](../log/2026-10-18-sword-katana-redo.md)). Published and wired in the same day.
  **Waiting on the user:** play the Sword. If it feels right, the Rapier is next. If the Sword feels right, give the Rapier the same recovery next (the user uses it).
- **Waiting on the user:**
  - a playtest of the new Sword swings and the body dash
  - ~~a decision on Sword, Emberfang and Mace damage~~ **Decided 2026-10-17: raise them back to the old damage
    per second.** Applied 2026-10-17 ([log](../log/2026-10-17-sword-recovery-blend.md)). Proposed (combo time old → new: Sword and Emberfang 1.2 → 1.95 s, ×1.625;
    Mace 1.55 → 2.45 s, ×1.58):

    | Weapon | Damage now (hits 1, 2, 3) | Proposed |
    |---|---|---|
    | Sword | 20, 25, 40 | 33, 41, 65 |
    | Emberfang | 26, 32, 52 | 42, 52, 85 |
    | Mace | 25, 30, 55 | 40, 47, 87 |
  - Ask for a playtest of the swings and dash first thing.
- **If the Sword feels right, the next step is 1b (Axe)**, using the recipe in step 1: `"overlap": True`,
  a negative `elbow` to cock the wind-up, a deliberate wind-up (hit at about 0.25 s), a big arc out to the side,
  a held follow-through, and HitDelay and Cooldown updated to match.
- **If the Sword still feels off, tune it first**, in [sword_anims.py](../../tools/sword_anims.py):
  - `LEAD` sets how much the body overlaps
  - the keys set the poses and timing
  - CombatConfig `Sword.Combo` sets HitDelay and Cooldown

  The user asked for more realism: whole-body motion and a noticeable delay between swings.
- **The dash** is a code-only pose in [DashEffects](../../src/client/DashEffects.luau) (the `POSE_*` values and the leg angles).
  The user rejected a full roll, and wants "a proper body dash forward-ish".
- **How to get clips into Studio and live** (Claude can't publish; Roblox blocks scripts from doing it):
  1. Run `python3 tools/<weapon>_anims.py assets/animations`, then
     `git checkout --` every clip you didn't mean to change (the generator rewrites others with only
     renumbered IDs changed).
  2. Copy the changed `.rbxmx` files into a temporary `src/server/AnimImport/` folder. Rojo syncs it.
  3. In Studio's **edit** mode (not play), clone them into `Workspace.Rig.AnimSaves` with `execute_luau`.
  4. Delete the folder on disk **and** in Studio (Rojo leaves the Studio copy behind).
  5. The user loads each clip in the Animation Editor and publishes it, then sends the IDs. Put them in
     CombatConfig (and TrainingStands for SwordSwing3).
- **Gotchas found tonight:**
  - Player characters use **AnimationConstraint** joints, not Motor6D. Code that poses joints must
    handle both (see `motor`, `getTransform` and `setTransform` in DashEffects).
  - Reading a joint's Transform back is never *exactly* what was set, so compare with `FuzzyEq`.
  - Clamp any smoothstep's input to 0..1, or it grows again past the end.
  - Both bugs made the dash flip the character and make it vanish.

## Goal
Make combat as satisfying to watch and play as the Roblox game **Dueling Grounds** (game ID
94217045453265), so it draws in players. We borrow **its feel and look only**: animations, hit
feedback, lighting, presentation. Not its game concept. Slayer Revo stays a PvE monster-hunting
game (town, hunting grounds, dungeons, bosses).

## What we learned from it
From the user's phone recording (2026-10-17, `~/Downloads/ScreenRecording_10-17-2026 03-32-11_1.MP4`,
Katana 1v1 on the "Classic" night shrine map) and online guides:
- **Lock-on camera:** behind the player and a little right, aimed at the enemy. Up close it's
  high, so the enemy shows above your head.
- **Every clash gets its own short flash** (0.1–0.3 s), and the flash lights the floor:
  - red slash line plus orange sparks on a hit
  - big gold flash flooding the floor on a parry
  - white starburst of crack lines on a clash
  - red X with shatter lines on a guard break
  - blue sparks or electricity on heavies and dodges, and a blue blur behind the dodge
- **Animations:** fast strikes with a short, readable wind-up, a snappy swing and a held
  follow-through. Fighters stay in a low, wide guard stance while circling.
  From the second recording (2026-10-17, `~/Downloads/ScreenRecording_10-17-2026 04-08-16_1.MP4`, 55 s
  of swinging and dodging at 15 fps):
  - the strike crosses a huge arc in 1–2 frames (<0.1 s)
  - the arm ends fully out to the side and holds about 0.25 s
  - the idle holds the katana low and forward
  - the dodge is a full forward roll (about 0.3–0.4 s), then a low crouch (about 0.3 s), then standing
- **Swing trails:** thin and pale, hugging the blade.
- **Atmosphere:**
  - a cold blue-indigo night against deep red lacquered wood
  - high contrast and saturation
  - crisp moon shadows
  - a shiny, reflective stone floor
  - light fog fading the background, so the lit arena is the stage
- **Presentation:**
  - a fighter intro shot with a name card, then a "ROUND 1" stamp
  - mirrored health bars at the top
  - a posture/shield bar at the bottom that glows red on posture damage and gold on parry
  - health bars flash white, then a delayed band drains
- **Mechanics (from guides, for reference only):**
  - light ×3 then heavy
  - tap to parry, hold to block (drains posture)
  - guard break leads to a finisher, then an ultimate window
  - dodge with i-frames, dash attack, jump attack

## Steps (do one per session, in order unless the user says otherwise)
- [x] Lock-on duel framing ([log](../log/2026-10-17-duel-lock-on-camera.md))
- [x] Every hit lights up and flares; bigger gold parry flash; moonlit night grade ([log](../log/2026-10-17-hit-flares-night-grade.md))
- [x] Lock-on up close: high and further round so the enemy stays visible; orcs die whole ([log](../log/2026-10-17-lock-on-close-range-orc-death.md))
- **1. Swing timing** (biggest gap), done weapon by weapon:
  - How swings are made: each weapon's clips come from a Python generator in `tools/` (`<weapon>_anims.py`).
    The generator writes `.rbxmx` files to `assets/animations/`. The user publishes them in Studio, and the
    asset IDs go in `CombatConfig`.
  - The recipe, measured from the second recording (shared easings in [sword_anims.py](../../tools/sword_anims.py)).
    Easing alone wasn't enough (1a felt the same); the **big arc and the long hold** are what sell it:
    - coil fast and hold it a beat so it reads (`EASE_SETTLE`, then `EASE_HOLD`)
    - whip through a **big arc** in about 0.05–0.1 s (`EASE_WHIP` into the hit, `EASE_SETTLE` out)
    - end with the arm **fully out to the side** and keep the twist about 35° so it doesn't swing behind
      (check the generator's pose readout)
    - **hold** the follow-through about 0.2 s, then recover to the ready stance
    - alternate the sides (forehand left, backhand right); overheads hang up high a beat before crashing down
  - Keep every `"hit"` time equal to `HitDelay` in CombatConfig.
  - [x] 1a. Shared easing support, plus Sword swings 1–3 (Emberfang and Mace use them too) ([log](../log/2026-10-17-sword-swing-easing.md)).
    Published 2026-10-17, but it felt the same, so it was redone in 1a-2.
  - [x] 1a-2. Sword swings rebuilt with big arcs, fast strikes and held follow-throughs, from the second
    recording ([log](../log/2026-10-17-sword-arcs-dodge-roll.md)). Published 2026-10-17 (IDs in the config); needs a playtest.
  - [x] 1a-3. Dash as a dodge roll: **rejected** by the user ("kinda ass"); replaced in 1a-4.
  - [x] 1a-4. **Body dash** (low lean into the dash, sprinter's split legs) and **whole-body Sword swings**:
    the generator's `overlap` (hips lead, blade whips last) and `elbow` (cocked wind-up), plus a slower
    tempo (hit at about 0.25 s, swings about 0.55 s apart, as in Dueling Grounds)
    ([log](../log/2026-10-17-sword-whole-body-body-dash.md)). Published 2026-10-17; the dash flip is fixed; **needs a playtest by the user.** Damage
    per second is about 40% lower; ask whether to raise the damage.
  - [x] 1a-5. Sword redone katana-style: a chained combo (each cut starts where the last ended),
    flick wind-ups, held end poses, a katana idle; the Mace keeps the old swings
    ([log](../log/2026-10-18-sword-katana-redo.md)). Published 2026-10-18; needs a playtest.
  - For every remaining weapon: turn on `"overlap": True`, cock the wind-up with a negative `elbow`, and
    give light attacks a deliberate wind-up (hit at about 0.25 s rather than 0.13–0.15 s).
  - [ ] 1b. Axe (its chops are in sword_anims.py)
  - [ ] 1c. Spear and Rapier
  - [ ] 1d. Dagger and Dual Blade
  - [ ] 1e. Scythe
  - [ ] 1f. Greatsword and Hammer (greatsword_anims.py has its own `keyframe_xml`, so pass `ease` through it as in sword_anims.py)
  - [ ] 1g. Heavies, finishers and orc attacks (sword spin, mace slam, axe cleave, and so on)
  - [ ] 1h. Combat stance: a katana-style idle (blade held low and forward in one hand, as in the
    recording), and a low guard walk or strafe while locked on
- [ ] **2. Distinct clash feedback:**
  - a white starburst when attacks collide
  - a red X with shatter lines, a big shake and a red posture glow when a guard or poise breaks (Grimgorg's stagger)
  - Needs a server event for stagger and clash; the effects stay visual-only on the client.
- [ ] **3. Boss arena atmosphere (Grimgorg first):**
  - a polished, reflective floor that catches the hit flashes
  - a strong rim light colour
  - darker surroundings and fog, so the fight is the brightest thing on screen
  - Town stays warm and friendly (design doc), so this applies to arenas only.
- [ ] **4. Boss-fight presentation:**
  - an intro camera pan to the boss with a name card
  - a big boss health bar across the top
  - a fight-start stamp
  - a slow-motion final blow with a "SLAIN" stamp
- [ ] **5. Trails and sound layering:**
  - thinner, paler trails on sword-type weapons
  - hits layer a metal ring and a body thud
  - a distinct high clang for parries
- [ ] **6. Death effect:** a dark dissolve with embers as a killed enemy fades (it already topples whole).
- [ ] **7. Re-check against a new recording:**
  - Record fighting only, no menus, ideally on PC so the camera matches ours.
  - Time their combos, dodges and the ultimate frame by frame.
  - Tune our animation speeds and hitstop to match.

## Rules for this issue
- Visual and feel only. The server still decides every hit, damage and outcome.
- Don't copy their assets, names or maps; build our own versions.
- Don't decide design-doc [TBD] items without asking.
- No Studio playtests unless the user asks; list what to check instead.
