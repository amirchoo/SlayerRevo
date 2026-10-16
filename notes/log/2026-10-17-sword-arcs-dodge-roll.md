# Sword swings with big arcs and holds; dodge roll (after a Dueling Grounds recording)

**Asked:** the first eased Sword swings ([[2026-10-17-sword-swing-easing]]) still felt the same.
The user recorded Dueling Grounds again (55 s, `~/Downloads/ScreenRecording_10-17-2026 04-08-16_1.MP4`:
katana swings and dodges in the lobby) and asked to replicate the swings and the dash, and to
add this to the main issue ([[main-issue-dueling-vibe]]).

## What the recording shows (15 fps, cropped on the character)
- **Idle:** katana held low, forward and to the right, in one hand.
- **Light swings:**
  - the wind-up is visible and held a moment
  - the strike crosses a huge arc in **1–2 frames (<0.1 s)**
  - the arm ends **fully out to the side**, blade flat, and is held there about **0.25 s**
  - the next swing comes back the other way (forehand to the left, backhand to the right)
  - an overhead swing hangs up high for a beat, then crashes down
- **Strikes** often end in a deep, low lunge.
- **Dodge:** a full **forward roll**: tuck, go head over heels in about 0.3–0.4 s, land in a low
  crouch (about 0.3 s), then stand.

Our first pass only added about 0.06 s of hold and kept the small arcs that stop in front of the body,
so it read the same.

## What changed
- [sword_anims.py](../../tools/sword_anims.py) SwordSwing1–3. Hit times are unchanged (0.15, 0.13,
  0.27), so `HitDelay` still matches:
  1. **SwordSwing1 (forehand):**
     - coils over the right shoulder by 0.08 s and holds until 0.11
     - whips through the hit at 0.15
     - is fully out to the left by 0.20
     - holds until 0.40, then is back to the ready stance at 0.60
  2. **SwordSwing2 (backhand):** the same shape to the right, timed coil 0.06, hit 0.13, out 0.18,
     held until 0.38, ready at 0.58.
  3. **SwordSwing3 (leap):** hangs overhead from 0.16 to 0.21, crashes into the hit at 0.27,
     holds the deep lunge until 0.52, ready at 0.75.

  Chest and hip twist were kept to about 35°, so the arm ends straight out to the side and not
  behind the character (checked with the generator's pose readout). Emberfang and Mace use these
  clips too.
- [DashEffects](../../src/client/DashEffects.luau): the dash lean is replaced by a **roll**, laid
  over the running animations each frame:
  - one full tumble toward the dash direction, eased in and out, over `ROLL_TIME` (0.3 s); it works
    sideways and backward too, so it reads as a sideways or backward roll when locked on
  - it turns about a point `ROLL_PIVOT` (0.6 studs) above the hips, with the hips dropped
    `ROLL_DROP` (1.1 studs) and the knees tucked to the chest
  - then a crouch for `LAND_TIME` (0.22 s) that rises back up

  The i-frames are unchanged (DashService still decides them).
- [CombatConfig](../../src/shared/Config/CombatConfig.luau) `Dash`: Speed 60→40, Duration
  0.18→0.28, so you still cover about 11 studs, but the movement lasts as long as the roll.

## Published
Claude rebuilt the clips in Studio's `Workspace.Rig.AnimSaves`; scripts can't publish animations
(AssetService.CreateAssetVersionAsync isn't available), so the user published them as new assets
(2026-10-17): SwordSwing1 `84991010546558`, SwordSwing2 `126545925834466`, SwordSwing3
`129628167382020`. They're in CombatConfig Sword.Combo and the TrainingStands Emberfang pose.

## Was to do (the user)
- Publish SwordSwing1–3 again from `assets/animations/` (Insert from File into the rig's AnimSaves,
  load in the Animation Editor, publish). **Overwriting** the assets published earlier today
  (104914800619644, 138065173637024, 89799472238550) keeps the IDs; otherwise send Claude the new ones.
- The roll needs no publishing (it's code). Playtest it.

## Fix: the roll (and the old dash lean) never showed
Player characters use **AnimationConstraint** joints (Roblox's newer avatar joints), not Motor6D.
DashEffects only looked for Motor6D, found none and silently skipped the pose, so even the old
lean never appeared. It now takes either kind (like StaffClient, VillagerAnimator and CookingPose).
Checked in a playtest: 0.22 s into a dash the hips are 0.47 studs lower and the body has turned 73°.
The new Sword swings were also checked in the playtest: they load (0.60, 0.58 and 0.75 s), and
SwordSwing1 frozen at 0.3 s shows the arm and blade out to the left in a low lunge.

## Open
- Not playtested. Possible issues: the roll pivot or drop could put the head through the floor or
  float too high (`ROLL_PIVOT` and `ROLL_DROP` in DashEffects); the dash now feels slower to start
  (it's at 40 studs/s instead of 60).
- Not done yet: a katana-style idle (blade low and forward), the low lunge-stance walk, the
  roll's arm pose (arms currently keep the walk animation's swing).
