# Animation style: how Slayer Revo's weapon animations are made

The source of truth for how every weapon animation looks and is built. Set by the user on 2026-10-18
after the Sword combo redo ("this is how I imagine it would be"); every weapon gets remade this way
([[weapon-anim-remake]]). The reference is the battlegrounds TikTok the user sent, broken down in
[[battlegrounds-combat-reference]]. The finished example to copy is the Sword combo in
`tools/blender/sword_clips.py` ([log](../notes/log/2026-10-18-sword-combo-exaggerated.md)).

## Who does what
- **Claude authors every clip** in Blender from scripts; the user can't animate and only watches,
  says what feels off, and publishes in Studio.
- **The user's feedback is the input that matters.** Generic animation advice is already applied here;
  ask what feels off (floaty cut, slow wind-up, stiff recovery) or for a reference clip.

## The look
1. **Exaggerate, like the video. Never realistic.** Extreme silhouettes that read at a glance on a phone:
   - deep lunges: feet ~2 studs apart, hips ~0.75–0.9 studs down and forward;
   - the body coils ~50–60° one way in the wind-up (and leans away), then whips 50–65° the other way
     through the cut;
   - the chest goes over the front knee in the follow-through, then **settles** a touch (rises a little,
     untwists a little) into the held pose;
   - finishers can leave the ground (Sword 3: crouch, tucked leap, hang at the top, slam into a squat).
2. **Each combo step cuts a different way** (Sword: down-left, flat right, straight down), so a combo
   never looks like a loop and no two steps look alike.
3. **Snappy front, held back half.** Contact ~0.1–0.2 s after the press; the end pose holds and
   settles. The first key leaves fast ("out" ease); the whip into the hit arrives fastest ("in").
4. **Clean cuts:** at the hit the arm reaches out (elbow 30–90° of bend), the blade points *across* its
   path, not along it, and the edge leads the cut (the AUTHOR line "edge leads by" ~0.8 or more). A lunge
   pushing the hand along the blade reads as a stab.
5. **Overlapping action** (built into the script): hips lead 2 frames, chest and feet 1, the blade
   trails the hand 1, the free arm 2, the head 3; on the hit key the hips, chest and weapon land
   together. Change per clip with `"overlap"` when a move needs it (two-handed: offhand and blade 0;
   a slam: the whole body together; a long step: feet land after the hips).
6. **Smooth, no pops:** no joint stops dead, jumps off from rest or reverses in one frame, and nothing
   flips, except moments meant to snap (a foot stamp, a jump's take-off, a slam's landing), marked
   `"sudden"`.

## The tools (all in `tools/blender/`)
| Command | What it does |
|---|---|
| `sh tools/blender/author.sh <Clip...> [--views behind,side]` | Builds clips from `*_clips.py`, writes `assets/animations/<Clip>.rbxmx` (+ `<Clip>Moving` upper-body twins), prints the AUTHOR report, renders preview sheets in `build/anim_preview/`. |
| `sh tools/blender/combo.sh <Weapon>` | The whole combo chained the way the game chains it (cooldowns, 0.15 s blends), with the **real weapon model**, as a Blender file plus 60 fps and quarter-speed videos, opened for the user. Add a weapon to `combo.sh` and `weapon_model.WEAPONS`. |
| `sh tools/blender/show.sh <Clip>` | One clip in Blender's window (body, sword, tip path, key/hit markers). |

The clip format is documented at the top of `sword_clips.py` and in `author_anim.py`: poses are
controls (grip, blade, edge, elbow, left wrist/elbow, feet, hips, chest, head), not joint angles;
Blender's IK solves the limbs. Key options: `ease` per key, `{group: ease}` per body part,
`"overlap"`, `"offhand_space": "world"` (left hand on the handle), `"blend_in"` (0.15 for chained steps),
`"sudden"`, `"moving_twin"`, `"hit"` (must match the weapon's HitDelay in CombatConfig).

## The loop for every clip
1. Write the key poses in `tools/blender/<weapon>_clips.py`, starting from the weapon's idle/ready pose;
   each combo step starts from the previous step's held pose (they share the same dicts).
2. Author into the scratchpad first (`Blender -b --factory-startup -P tools/blender/author_anim.py --
   <Clip> --out <scratch> --blend <scratch>`), and read the report:
   - **no** `OUT OF REACH`, `TIP IN THE GROUND`, `ARM NEARLY STRAIGHT` (except the idle's own pose);
   - **0 FLIPs** and ~0 CORNERs outside `"sudden"` moments;
   - edge leads ≥ ~0.8; tip speed at the hit ~250–300 studs/s for a sword cut.
3. Fix what it flags (the fixes that worked are below), re-run, then author for real and **look at**
   the preview sheets (`build/anim_preview/<Clip>/behind_sheet.png`, side too).
4. Run `combo.sh` for the whole combo and its frame-by-frame check. **No preview videos for the user**
   (the user, 2026-10-18: they cost tokens); say what changed and let them judge it in Studio. Still
   renders can't catch keying bugs: check the saved file plays back right.
5. When the user likes it: stage into `Workspace.Rig.AnimSaves` (temporary `src/server/AnimImport/`
   folder, then delete it on disk and in Studio), and give them the table of clips and the existing
   asset IDs to **publish over** (no new assets). Keep clips under ~350 KB.
6. Log it, commit, push.

## Fixes that worked (Sword, 2026-10-18)
| Symptom in the report | Cause | Fix |
|---|---|---|
| Elbow or knee FLIP mid-move | its pole crossed the limb's line | keep poles on one side for the whole move; for two-handed or overhead moves, poles forward and out (in front of the body never lines up with the arms) |
| Joint snaps, `ARM NEARLY STRAIGHT` | a limb near full stretch: tiny hand moves swing the joint | pull the target in so the elbow keeps 30°+ of bend; let the foot land after the hips on a long step |
| Free hand out of reach mid-move | hand path in a straight line while the body whips round | built in now (the free hand and poles ride with the chest); arc the hand round the side instead of past the shoulder |
| Blade spins 180° in a frame | (fixed in the script: the blade is keyed as a rotation) | keep the edge direction consistent between keys (no accidental 180° roll: at the top of an overhead the edge faces where it's about to go) |
| Arm stutters through the hit (fast, slow, very fast) | hips/chest arriving a frame before the weapon | built in: they land together on the hit key |
| Hand rolls ~90° in the last frame before a hit | a big blade turn eased into one frame | give the blade the whole whip (`"overlap": {"blade": 0}`) |
| Foot slams in at full speed, knee snaps | the foot shares the hit's "in" ease | per-part ease on that key: `{"feet": "inout"}` |
| Legs lock straight in a leap | hips up, feet barely off the ground | tuck the feet high at the top |

## Around the animation (not in Blender)
The animation is one layer of how a hit feels. The others are tuned in `CombatConfig.Hitstop` and
`CombatConfig.HitImpact` (exaggerated 2026-10-18: rolling camera jolt, zoom punch, flash-then-silhouette
impact frame; the user: "perfect"), dash afterimages, and still to come: slash crescents, enemy
reactions per hit, dust and craters ([[battlegrounds-combat]]).

The Arcane Atelier video ([[arcane-atelier-reference]]) shows why the VFX matter so much: big, bright
crescent arcs and an impact ring cover the body on almost every frame of a swing, so the eye follows the
arc, not the limbs. Keep the wind-up and end poses strong and readable, since those are what show
between the effects. The same video carries the sword low and trailing while walking, so it looks heavy;
we have no weapon walk clip yet (the idle plays over the default walk) — a candidate, not decided
([[arcane-atelier-look]]).
