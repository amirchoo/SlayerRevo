# Sword swings with whole-body motion and a slower tempo; body dash instead of the roll

**Asked:** after playtesting, the user said the roll "is kinda ass": the dash should be a proper body dash
forward, not a full roll. The Sword swings looked off and stiff next to Dueling Grounds, which uses the
whole body. Their light attacks also have a noticeable delay before each swing, which feels more
real. Part of [[main-issue-dueling-vibe]] step 1.

## Dash: body dash (code, nothing to publish)
- [DashEffects](../../src/client/DashEffects.luau):
  - the body snaps low (hips down `POSE_DROP` 0.6) in 0.05 s and leans `POSE_LEAN` 32° into the dash
  - the chest curls a further `POSE_SPINE` 12° (the Waist joint)
  - dashing forward, the legs split like a sprinter's lunge: left leads (55, -75, 20), right pushes
    off behind (-35, -30, 35); sideways or back, both are bent (35, -65, 30)
  - it holds 0.2 s, then eases upright over 0.16 s
- [CombatConfig](../../src/shared/Config/CombatConfig.luau) `Dash`: 52 studs/s for 0.21 s (still about 11 studs).
- This is the first time any dash pose is actually visible. The old lean was hidden by the
  Motor6D/AnimationConstraint bug fixed earlier today ([[2026-10-17-sword-arcs-dodge-roll]]).

## Sword: whole body, elbow, tempo
- [sword_anims.py](../../tools/sword_anims.py) has two new features. Clips that don't use them come out unchanged.
  - `elbow` (pose): bends the right elbow. Negative values fold the forearm back, so the sword is
    cocked behind the shoulder on a wind-up; the arm straightens as it strikes. Before this the sword
    arm never bent at all.
  - `"overlap": True` (swing): the clip is resampled at 30 fps with each part of the body offset in
    time (`LEAD`), so the motion travels through the body like weight transfer instead of everything
    moving as one block:

    | Body part | Offset |
    |---|---|
    | hips and legs | lead by 0.05 s |
    | chest | leads by 0.025 s |
    | head | leads by 0.035 s |
    | sword arm | on the keys, so the hit stays on time |
    | forearm | trails by 0.012 s |
    | hand | trails by 0.02 s (the blade whips last) |
- SwordSwing1–3 rebuilt on this with a deliberate wind-up:

  | Clip | Hit time (s) | Clip length (s) | Wind-up |
  |---|---|---|---|
  | Swing 1 | 0.15 → **0.26** | 0.72 | cocked behind the right shoulder by 0.14, held to 0.20 |
  | Swing 2 | 0.13 → **0.24** | 0.70 | cocked behind the left side |
  | Swing 3 | 0.27 → **0.40** | 0.92 | sinks before the jump, hangs cocked overhead, crashes down |

  Swings 1 and 2 still end fully out to the side and are held.
- CombatConfig, to match:

  | Weapon | HitDelay (swings 1, 2, 3) | Cooldown (swings 1, 2, 3) |
  |---|---|---|
  | Sword and Emberfang | 0.26, 0.24, 0.40 | 0.3/0.3/0.6 → 0.55/0.55/0.85 |
  | Mace | the Sword's ÷ 0.8 | 0.7, 0.7, 1.05 |

  The TrainingStands Emberfang pose moved to 0.5 s (the held crash).
- **Balance note:** a full Sword combo now takes about 1.95 s instead of about 1.2 s, with damage
  unchanged, so damage per second is about 40% lower. Not decided yet whether to raise the damage.

## Fix: dashing flipped the character
`DashEffects.lay` adds the pose on top of whatever the animations set, and takes it back off if
nothing rewrote the joint since (`Transform == what we set`). AnimationConstraint joints hand back a
value a hair off what was set (checked in a playtest: equal=false, difference 0), so the check
always failed and the offset was stacked again every frame, spinning the body over. It now
compares with `CFrame:FuzzyEq(…, 1e-4)` (checked: it matches its own value, but not a 1° change).

## Fix 2: the flip was really the ease-out running away
The fuzzy check above wasn't enough: the dash still flipped the character and made it vanish.
The ease back up used smoothstep `1 - v²(3 - 2v)`, which only behaves for v in 0..1. Past
the end of the dash it grows again instead of staying at 0, so the pose never finished and its
weight kept climbing. In a playtest the hips sank to y = -1,000,000 and spun, which is why the
character disappeared. v is now clamped, and the pose ends on time. Checked in a playtest: a
forward dash then a sideways one each lean and drop, then return to rest and stay there.

## Published
The user published the new clips: SwordSwing1 `101378158511989`, SwordSwing2 `100925354916925`,
SwordSwing3 `78373052274628`. They're in CombatConfig Sword.Combo (Emberfang and Mace use them too) and in the
TrainingStands pose, so the hit timing now matches the animation.

## Loaded into Studio
The three clips went into `Workspace.Rig.AnimSaves` through a temporary Rojo folder
(`src/server/AnimImport/`, removed afterward): SwordSwing1 has 27 keyframes and 390 poses (0.72 s),
SwordSwing2 27 and 390 (0.70 s), SwordSwing3 34 and 495 (0.92 s). They're waiting for the user to publish them.

## To do
- Done: loaded into Studio and published (see above).

## Open
- Not playtested.
