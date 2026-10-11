"""Generates R15 KeyframeSequence .rbxmx files for the spear.

    python3 tools/spear_anims.py assets/animations

Built on the greatsword generator's two-hand IK: the right hand holds the shaft further
back and the left hand further forward (toward the spearhead), with the head pointing
along the "blade" direction. Keep each thrust's "hit" time in sync with HitDelay in the
Spear section of src/shared/Config/CombatConfig.luau.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import greatsword_anims as two_hand  # noqa: E402
import sword_anims as lib  # noqa: E402
from greatsword_anims import gpose  # noqa: E402

# Negative gap: the left hand sits *ahead* of the right hand, toward the spearhead.
two_hand.HAND_GAP = -0.8

# Ready: spear held at the hip, point angled up and forward.
READY = {"hilt": (0.65, -0.5, -0.35), "blade": (0, 0.35, -1)}
DRAWN_BACK = {"hilt": (0.75, -0.4, 0.25), "blade": (0, 0.2, -1)}
THRUST = {"hilt": (0.15, -0.05, -0.8), "blade": (-0.12, 0.05, -1)}
DRAWN_BACK_HIGH = {"hilt": (0.75, -0.2, 0.2), "blade": (0, 0.3, -1)}
THRUST_HIGH = {"hilt": (0.15, 0.15, -0.75), "blade": (-0.12, 0.15, -1)}
COILED = {"hilt": (0.85, -0.35, 0.5), "blade": (0.05, 0.25, -1)}
LUNGE = {"hilt": (0.1, 0.0, -0.85), "blade": (-0.12, 0.02, -1)}
# Heavy (charged lunge): drawn far back at shoulder height, then driven out at full stretch.
DRAWN_FAR = {"hilt": (0.9, -0.15, 0.7), "blade": (0.05, 0.12, -1)}
LUNGE_FULL = {"hilt": (0.15, 0.05, -0.75), "blade": (-0.1, 0.0, -1)}
# Guard: shaft held diagonally across the body.
GUARD = {"hilt": (0.55, -0.35, -0.6), "blade": (-0.65, 0.75, -0.15)}

COIL_BACK = {"drop": 0.3, "lleg": (28, -45, 17), "rleg": (15, -40, 25)}
LUNGE_LEGS = {"drop": 0.55, "lleg": (50, -60, 10), "rleg": (-25, -20, 45)}
LUNGE_DEEP = {"drop": 0.8, "lleg": (65, -80, 15), "rleg": (-35, -15, 50)}

ANIMATIONS = {
    "SpearIdle": {
        "loop": True, "upper_body_only": True, "hit": None,
        "keys": [
            (0.0, gpose(**READY, chest=-20)),
            (0.8, gpose(**READY, chest=-20, lean=-3)),
            (1.6, gpose(**READY, chest=-20)),
        ],
    },
    "SpearThrust1": {  # quick jab
        "loop": False, "upper_body_only": True, "hit": 0.13,
        "keys": [
            (0.00, gpose(**READY, chest=-20)),
            (0.08, gpose(**DRAWN_BACK, chest=-30)),
            (0.14, gpose(**THRUST, chest=5, lean=-8)),
            (0.32, gpose(**READY, chest=-20)),
        ],
    },
    "SpearThrust2": {  # second jab, a little higher and snappier
        "loop": False, "upper_body_only": True, "hit": 0.12,
        "keys": [
            (0.00, gpose(**READY, chest=-20)),
            (0.07, gpose(**DRAWN_BACK_HIGH, chest=-32)),
            (0.13, gpose(**THRUST_HIGH, chest=8, lean=-6)),
            (0.30, gpose(**READY, chest=-20)),
        ],
    },
    "SpearThrust3": {  # coil, then a full-body lunging thrust (the client also lunges forward)
        "loop": False, "upper_body_only": False, "hit": 0.2,
        "keys": [
            (0.00, gpose(**READY, chest=-20)),
            (0.12, gpose(**COILED, chest=-40, lean=5, **COIL_BACK)),
            (0.21, gpose(**LUNGE, chest=10, lean=-15, **LUNGE_LEGS)),
            (0.40, gpose(**LUNGE, chest=10, lean=-15, **LUNGE_LEGS)),
            (0.65, gpose(**READY, chest=-20)),
        ],
    },
    "SpearGuard": {
        "loop": True, "upper_body_only": True, "hit": None,
        "keys": [
            (0.0, gpose(**GUARD, chest=-15)),
            (0.6, gpose(**GUARD, chest=-15, lean=-3)),
            (1.2, gpose(**GUARD, chest=-15)),
        ],
    },
    # Heavy wind-up: drawn far back and held (the game freezes it on its last frame while
    # charging). Upper body only, so the legs can still shuffle while aiming.
    "SpearWindUp": {
        "loop": False, "upper_body_only": True, "hit": None,
        "keys": [
            (0.00, gpose(**READY, chest=-20)),
            (0.25, gpose(**DRAWN_FAR, chest=-50, lean=5)),
            (1.00, gpose(**DRAWN_FAR, chest=-55, lean=8)),  # tension builds
        ],
    },
    # Heavy release: driven forward at full stretch in a deep lunge (the client lunges the
    # player forward at the same time). Keep "hit" in sync with Spear.Heavy.HitDelay.
    "SpearLunge": {
        "loop": False, "upper_body_only": False, "hit": 0.15,
        "keys": [
            (0.00, gpose(**DRAWN_FAR, chest=-55, lean=8, **COIL_BACK)),
            (0.15, gpose(**LUNGE_FULL, chest=15, lean=-20, **LUNGE_DEEP)),
            (0.45, gpose(**LUNGE_FULL, chest=15, lean=-18, **LUNGE_DEEP)),
            (0.75, gpose(**READY, chest=-20)),
        ],
    },
}


def main(out_dir):
    two_hand.ANIMATIONS = ANIMATIONS
    two_hand.main(out_dir)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
