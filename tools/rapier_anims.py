"""Generates R15 KeyframeSequence .rbxmx files for the rapier: a fencer's en garde idle,
three elegant thrusts, the heavy's coiled wind-up, and the rapid-thrust flurry (looped).

    python3 tools/rapier_anims.py assets/animations

Built on tools/sword_anims.py (one-handed, right hand; see its notes on joint frames).
The fencer stands side-on, right shoulder leading (the chest turned left), the free hand
raised behind for balance. With the arm straight, a wrist near -90 makes the blade carry
on along the arm's line (a thrust); smaller values tip it toward blade_lean.
Keep each thrust's "hit" time in sync with HitDelay in the Rapier section of
src/shared/Config/CombatConfig.luau, and the flurry's stab rhythm with Heavy.Interval.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sword_anims as lib  # noqa: E402
from sword_anims import pose  # noqa: E402

UP = (0, 1, 0)
FORWARD = (0, 0, -1)

# Side-on stance: right foot forward, knees soft, back foot turned out.
STANCE = {"drop": 0.3, "rleg": (25, -35, 10), "lleg": (-12, -30, 42)}
ADVANCE = {"drop": 0.35, "rleg": (35, -40, 5), "lleg": (-18, -25, 43)}  # a small step in
LUNGE = {"drop": 0.75, "rleg": (60, -65, 5), "lleg": (-35, -5, 40)}  # front knee over the toe, back leg long
COILED = {"drop": 0.4, "rleg": (15, -30, 15), "lleg": (5, -55, 50)}  # weight sunk on the back leg

# The free hand curled up behind the head (the classic fencer's balance).
BACK_HAND = {"larm": 155, "lelbow": 65}
BACK_HAND_LOW = {"larm": 120, "lelbow": 55}  # thrown back a little lower on a lunge

TWIST = 30  # chest turned left: the right shoulder leads
# Arm directions are in chest space; with the chest turned, (0.5, y, -0.86) is straight ahead.
EN_GARDE = {"arm": (0.5, -0.45, -0.75), "wrist": -50, "blade_lean": UP}  # point up toward the eyes
EXTENDED = {"arm": (0.5, 0.05, -0.86), "wrist": -88, "blade_lean": UP}  # arm and blade one line
EXTENDED_HIGH = {"arm": (0.48, 0.22, -0.85), "wrist": -88, "blade_lean": UP}
EXTENDED_LOW = {"arm": (0.52, -0.12, -0.85), "wrist": -88, "blade_lean": UP}
RETRACTED = {"arm": (0.55, -0.35, -0.6), "wrist": -70, "blade_lean": UP}  # pulled back, point still on target
# Wind-up: the sword arm drawn back and out to the right, the point still aimed ahead.
DRAWN = {"arm": (0.7, -0.2, 0.7), "wrist": 0, "blade_lean": FORWARD}
DRAWN_DEEP = {"arm": (0.75, -0.15, 0.65), "wrist": 0, "blade_lean": FORWARD}

FLURRY_STAB = 0.09  # seconds per stab; matches Rapier.Heavy.Interval


def guard(**extra):
    return pose(chest=TWIST, **EN_GARDE, **BACK_HAND, **extra)


ANIMATIONS = {
    "RapierIdle": {  # en garde; upper body only, so the legs walk
        "hit": None, "loop": True, "upper_body_only": True, "plane": None,
        "keys": [
            (0.0, guard()),
            (0.9, pose(chest=TWIST, lean=-3, **{**EN_GARDE, "wrist": -47}, **BACK_HAND)),
            (1.8, guard()),
        ],
    },
    "RapierThrust1": {  # a crisp straight thrust with a small advance
        "hit": 0.12, "plane": None,
        "keys": [
            (0.00, guard(**STANCE)),
            (0.06, pose(chest=TWIST - 5, **RETRACTED, **BACK_HAND, **STANCE)),
            (0.12, pose(chest=TWIST, lean=-8, **EXTENDED, **BACK_HAND, **ADVANCE)),
            (0.20, pose(chest=TWIST, lean=-8, **EXTENDED, **BACK_HAND, **ADVANCE)),
            (0.36, guard(**STANCE)),
        ],
    },
    "RapierThrust2": {  # a thrust to the high line, the wrist turned over with a flourish
        "hit": 0.11, "plane": None,
        "keys": [
            (0.00, guard(**STANCE)),
            (0.05, pose(chest=TWIST + 5, **{**RETRACTED, "wrist": -60}, **BACK_HAND, **STANCE)),
            (0.11, pose(chest=TWIST + 5, lean=-6, **EXTENDED_HIGH, **BACK_HAND, **ADVANCE)),
            (0.19, pose(chest=TWIST + 5, lean=-6, **EXTENDED_HIGH, **BACK_HAND, **ADVANCE)),
            (0.34, guard(**STANCE)),
        ],
    },
    "RapierThrust3": {  # the full lunge: sink, then drive out long and low (the game lunges you forward)
        "hit": 0.2, "plane": None,
        "keys": [
            (0.00, guard(**STANCE)),
            (0.11, pose(chest=TWIST + 10, lean=5, **RETRACTED, **BACK_HAND, **COILED)),
            (0.20, pose(chest=TWIST, lean=-14, **EXTENDED_LOW, **BACK_HAND_LOW, **LUNGE)),
            (0.42, pose(chest=TWIST, lean=-12, **EXTENDED_LOW, **BACK_HAND_LOW, **LUNGE)),
            (0.68, guard(**STANCE)),
        ],
    },
    # Heavy wind-up: the arm drawn back like a coiled spring, held on its last frame while
    # charging. Upper body only, so the legs can still shuffle while aiming.
    "RapierWindUp": {
        "hit": None, "upper_body_only": True, "plane": None,
        "keys": [
            (0.00, guard()),
            (0.20, pose(chest=TWIST + 15, lean=4, **DRAWN, **BACK_HAND)),
            (1.00, pose(chest=TWIST + 20, lean=6, **DRAWN_DEEP, **BACK_HAND)),  # tension builds
        ],
    },
    # Heavy release: rapid thrusts from a planted lunge, alternating high and low, two stabs
    # per loop (the game plays it for as many stabs as the charge earned).
    "RapierFlurry": {
        "hit": None, "loop": True, "plane": None,
        "keys": [
            (0.0, pose(chest=TWIST, lean=-6, **RETRACTED, **BACK_HAND_LOW, **LUNGE)),
            (FLURRY_STAB / 2, pose(chest=TWIST, lean=-10, **EXTENDED_HIGH, **BACK_HAND_LOW, **LUNGE)),
            (FLURRY_STAB, pose(chest=TWIST, lean=-6, **RETRACTED, **BACK_HAND_LOW, **LUNGE)),
            (FLURRY_STAB * 1.5, pose(chest=TWIST, lean=-10, **EXTENDED_LOW, **BACK_HAND_LOW, **LUNGE)),
            (FLURRY_STAB * 2, pose(chest=TWIST, lean=-6, **RETRACTED, **BACK_HAND_LOW, **LUNGE)),
        ],
    },
}


def main(out_dir):
    lib.SWINGS = ANIMATIONS
    lib.main(out_dir)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
