"""Generates R15 KeyframeSequence .rbxmx files for the two-handed hammer: the idle (resting
on the right shoulder), the guard (haft across the body), the 3-blow combo (an overhead pound
into the ground, a wide sweeping swing, a leaping crush), and the heavy (raised high behind
the head while charging, then slammed into the ground).

    python3 tools/hammer_anims.py assets/animations

Built on the greatsword generator's two-hand IK: the right hand holds the top of the grip
and the left hand below it. "blade" is the way the haft points from the hands to the head.
Keep each blow's "hit" time in sync with HitDelay in the Hammer section of
src/shared/Config/CombatConfig.luau, and HammerSlam's with Heavy.HitDelay.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import greatsword_anims as two_hand  # noqa: E402
from greatsword_anims import gpose  # noqa: E402

two_hand.HAND_GAP = 0.7  # a long grip: hands well apart

# Resting on the right shoulder: hands low in front, the haft over the shoulder, head behind.
SHOULDER_REST = {"hilt": (0.1, 0.0, -0.6), "blade": (0.45, 0.75, 0.5)}
# Overhead pound: lifted up in front, over the head, then brought down onto the ground ahead.
LIFTED = {"hilt": (0.4, 0.5, -0.95), "blade": (-0.15, 1, 0.15)}
OVERHEAD = {"hilt": (0.3, 1.6, -0.3), "blade": (-0.3, 0.55, 1)}  # head hanging back behind
COMING_OVER = {"hilt": (0.3, 1.35, -0.95), "blade": (0.05, 0.8, -0.6)}
COMING_DOWN = {"hilt": (0.25, 0.6, -1.25), "blade": (0, 0.1, -1)}
IMPACT = {"hilt": (0.15, -0.55, -1.3), "blade": (0, 0.2, -1)}  # the head on the ground ahead (the lean tips it down)
LIFTING = {"hilt": (0.3, -0.45, -1.1), "blade": (0.1, 0.1, -1)}
# Sweeps: the haft out level, swung through a wide arc by the hips and chest.
WOUND_RIGHT = {"hilt": (0.75, 0.05, -0.55), "blade": (1, 0.1, 0.4)}
SWEEP_RIGHT = {"hilt": (0.5, -0.1, -0.95), "blade": (0.75, -0.05, -0.65)}
SWEEP_FRONT = {"hilt": (0.15, -0.15, -1.2), "blade": (0, -0.1, -1)}
SWEEP_LEFT = {"hilt": (-0.25, -0.1, -1.0), "blade": (-0.75, -0.05, -0.65)}
WOUND_LEFT = {"hilt": (-0.45, 0.05, -0.65), "blade": (-1, 0.1, 0.3)}
# Heavy wind-up: raised high and far back behind the head, the back arched.
RAISED_HIGH = {"hilt": (0.1, 1.7, 0.15), "blade": (0.2, 0.9, 0.4)}
# Guard: the haft held across the body, head up to the right.
GUARD = {"hilt": (-0.2, -0.1, -0.85), "blade": (0.9, 0.45, -0.1)}

READY_LEGS = {"drop": 0.15, "lleg": (12, -24, 12), "rleg": (12, -24, 12)}
COIL = {"drop": 0.35, "lleg": (25, -45, 20), "rleg": (10, -40, 30)}
COIL_DEEP = {"drop": 0.5, "lleg": (32, -60, 28), "rleg": (14, -55, 41)}
SWEEP_STANCE = {"drop": 0.4, "lleg": (30, -50, 20), "rleg": (5, -45, 40)}
POUND_STANCE = {"drop": 0.6, "lleg": (50, -70, 20), "rleg": (-5, -60, 65)}
DEEP_LUNGE = {"drop": 0.9, "lleg": (70, -95, 25), "rleg": (-15, -110, 70)}


def rest(**extra):
    return gpose(**SHOULDER_REST, **{"chest": -12, **extra})


ANIMATIONS = {
    "HammerIdle": {  # upper body only, so the legs walk
        "loop": True, "upper_body_only": True, "hit": None,
        "keys": [
            (0.0, rest()),
            (1.0, rest(lean=-3)),
            (2.0, rest()),
        ],
    },
    "HammerGuard": {
        "loop": True, "upper_body_only": True, "hit": None,
        "keys": [
            (0.0, gpose(**GUARD, chest=-20)),
            (0.6, gpose(**GUARD, chest=-20, lean=-3)),
            (1.2, gpose(**GUARD, chest=-20)),
        ],
    },
    # Blow 1: lift it off the shoulder and pound it into the ground in front.
    "HammerPound": {
        "loop": False, "upper_body_only": False, "hit": 0.36,
        "keys": [
            (0.00, rest(**READY_LEGS)),
            (0.14, gpose(**LIFTED, chest=-15, lean=4, **COIL)),
            (0.26, gpose(**OVERHEAD, chest=-10, lean=10, **COIL_DEEP)),
            (0.31, gpose(**COMING_OVER, chest=-5, lean=-5, **COIL)),
            (0.34, gpose(**COMING_DOWN, chest=0, lean=-15, **POUND_STANCE)),
            (0.37, gpose(**IMPACT, chest=8, lean=-28, **POUND_STANCE)),
            (0.62, gpose(**IMPACT, chest=8, lean=-26, **POUND_STANCE)),
            (0.80, gpose(**LIFTING, chest=0, lean=-12, **COIL)),
            (1.05, rest(**READY_LEGS)),
        ],
    },
    # Blow 2: a wide, heavy sweep from right to left.
    "HammerSwing": {
        "loop": False, "upper_body_only": False, "hit": 0.33,
        "keys": [
            (0.00, rest(**READY_LEGS)),
            (0.22, gpose(**WOUND_RIGHT, chest=-50, hips=-30, lean=6, **COIL_DEEP)),
            (0.29, gpose(**SWEEP_RIGHT, chest=-20, hips=-10, **SWEEP_STANCE)),
            (0.33, gpose(**SWEEP_FRONT, chest=5, hips=0, lean=-8, **SWEEP_STANCE)),
            (0.38, gpose(**SWEEP_LEFT, chest=30, hips=20, lean=-6, **SWEEP_STANCE)),
            (0.46, gpose(**WOUND_LEFT, chest=48, hips=32, lean=-4, **SWEEP_STANCE)),
            (0.66, gpose(**WOUND_LEFT, chest=44, hips=28, lean=-2, **COIL)),
            (1.00, rest(**READY_LEGS)),
        ],
    },
    # Blow 3 (finisher): a big wind-up high behind the head, a step in (the game lunges you),
    # and a crushing pound into the ground.
    "HammerCrush": {
        "loop": False, "upper_body_only": False, "hit": 0.46,
        "keys": [
            (0.00, rest(**READY_LEGS)),
            (0.14, gpose(**LIFTED, chest=-20, lean=5, **COIL)),
            (0.32, gpose(**RAISED_HIGH, chest=-10, lean=14, **COIL_DEEP)),
            (0.39, gpose(**OVERHEAD, chest=-12, lean=4, **COIL)),
            (0.42, gpose(**COMING_OVER, chest=-5, lean=-8, **POUND_STANCE)),
            (0.44, gpose(**COMING_DOWN, chest=0, lean=-18, **POUND_STANCE)),
            (0.47, gpose(**IMPACT, chest=10, lean=-32, **DEEP_LUNGE)),
            (0.85, gpose(**IMPACT, chest=10, lean=-30, **DEEP_LUNGE)),
            (1.05, gpose(**LIFTING, chest=0, lean=-14, **POUND_STANCE)),
            (1.35, rest(**READY_LEGS)),
        ],
    },
    # Heavy: raised high behind the head; the game freezes it on its last frame while charging.
    "HammerWindUp": {
        "loop": False, "upper_body_only": False, "hit": None,
        "keys": [
            (0.00, rest(**READY_LEGS)),
            (0.15, gpose(**LIFTED, chest=-15, lean=4, **COIL)),
            (0.35, gpose(**OVERHEAD, chest=-25, lean=10, **COIL)),
            (0.50, gpose(**RAISED_HIGH, chest=-10, lean=14, **COIL_DEEP)),
            (1.50, gpose(**RAISED_HIGH, chest=-15, lean=18, **COIL_DEEP)),  # tension builds
        ],
    },
    "HammerSlam": {
        "loop": False, "upper_body_only": False, "hit": 0.2,
        "keys": [
            (0.00, gpose(**RAISED_HIGH, chest=-15, lean=18, **COIL_DEEP)),
            (0.09, gpose(**OVERHEAD, chest=-12, lean=4, **COIL)),
            (0.13, gpose(**COMING_OVER, chest=-5, lean=-8, **POUND_STANCE)),
            (0.17, gpose(**COMING_DOWN, chest=0, lean=-18, **POUND_STANCE)),
            (0.21, gpose(**IMPACT, chest=10, lean=-34, **DEEP_LUNGE)),
            (0.70, gpose(**IMPACT, chest=10, lean=-32, **DEEP_LUNGE)),
            (0.90, gpose(**LIFTING, chest=0, lean=-14, **POUND_STANCE)),
            (1.20, rest(**READY_LEGS)),
        ],
    },
}


if __name__ == "__main__":
    two_hand.ANIMATIONS = ANIMATIONS
    two_hand.main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
