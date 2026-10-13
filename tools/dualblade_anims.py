"""Generates R15 KeyframeSequence .rbxmx files for the dual blades: a low two-blade idle, the
4-cut combo (right, left, a spinning right sweep, then both blades crossing), the crossed
guard, the heavy's gathering wind-up, and the rush (a spinning loop, both blades out).

    python3 tools/dualblade_anims.py assets/animations

Built on tools/sword_anims.py (see its notes on joint frames), using its left-arm aiming
(larm_dir / lwrist / lblade_lean, and "lplane" for a left-hand swing). Arm directions are in
chest space: X right, Y up, -Z forward; mirror() flips one to the other side.
Keep each slash's "hit" time in sync with HitDelay in the DualBlade section of
src/shared/Config/CombatConfig.luau, and the rush's turn with Heavy.TickInterval.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sword_anims as lib  # noqa: E402
from sword_anims import pose  # noqa: E402

FORWARD = (0, 0, -1)


def mirror(v):
    return (-v[0], v[1], v[2])


def swap_legs(p):
    """The same footwork on the other foot."""
    return {**p, "lleg": p["rleg"], "rleg": p["lleg"]}


# Both blades held low in front, points forward (a light, ready stance).
LOW_R = (0.35, -0.8, -0.45)
LOW = {"arm": LOW_R, "wrist": -70, "blade_lean": FORWARD, "larm_dir": mirror(LOW_R), "lwrist": -70, "lblade_lean": FORWARD}
# The free blade while the other one cuts: tucked in by the hip, point forward.
R_TUCKED = {"arm": (0.3, -0.85, -0.3), "wrist": -75, "blade_lean": FORWARD}
L_TUCKED = {"larm_dir": mirror((0.3, -0.85, -0.3)), "lwrist": -75, "lblade_lean": FORWARD}

READY = lib.READY
COIL_BACK = lib.COIL_BACK
LUNGE_LEFT = lib.LUNGE_LEFT  # left foot forward
LUNGE_RIGHT = lib.LUNGE_RIGHT
SPRING = {"drop": 0.5, "lleg": (40, -70, 30), "rleg": (40, -70, 30)}  # crouched to spring

# Right-hand diagonal cut, from over the right shoulder down across to the left hip.
DIAG_PLANE = ((0.6, 0.75, 0.3), (0.15, 0.15, -1))
# Horizontal sweep, right to left, at chest height.
SWEEP_PLANE = ((0.9, 0.1, 0.3), (0, 0.05, -1))

# Rush: both arms out to the sides with the blades extending them, a low wide stance; the
# hips turn a full circle per loop in 120 degree steps (each blends the short way round).
RUSH_TIME = 0.3  # one full turn; matches DualBlade.Heavy.TickInterval
RUSH_BODY = {
    "arm": (1, -0.05, -0.25), "wrist": -55, "blade_lean": FORWARD,
    "larm_dir": mirror((1, -0.05, -0.25)), "lwrist": -55, "lblade_lean": FORWARD,
    "lean": -12, "drop": 0.45, "lleg": (25, -45, 20), "rleg": (25, -45, 20), "head_forward": False,
}

# Guard: the blades crossed in an X in front of the chest, points up and out.
GUARD = {
    "arm": (0.15, 0.05, -1), "wrist": 0, "blade_lean": (-0.7, 0.7, 0),
    "larm_dir": (-0.15, 0.05, -1), "lwrist": 0, "lblade_lean": (0.7, 0.7, 0),
}

# Gathering for the rush: leaning forward, both arms swept back low, blades trailing behind.
DRAWN_R = (0.55, -0.5, 0.65)
# (a wrist near -90 makes each blade carry on along its arm's line, back and down)
DRAWN = {"arm": DRAWN_R, "wrist": -80, "blade_lean": (0, -1, 0.3), "larm_dir": mirror(DRAWN_R), "lwrist": -80, "lblade_lean": (0, -1, 0.3)}
DRAWN_DEEP_R = (0.6, -0.4, 0.7)
DRAWN_DEEP = {**DRAWN, "arm": DRAWN_DEEP_R, "larm_dir": mirror(DRAWN_DEEP_R)}


def idle(**extra):
    return pose(**{**LOW, **extra})


ANIMATIONS = {
    "DualBladeIdle": {  # upper body only, so the legs walk
        "hit": None, "loop": True, "upper_body_only": True, "plane": None,
        "keys": [
            (0.0, idle()),
            (0.8, idle(lean=-3, wrist=-66, lwrist=-66)),
            (1.6, idle()),
        ],
    },
    "DualBladeSlash1": {  # right blade: a quick diagonal cut, stepping in on the left foot
        "hit": 0.1, "plane": DIAG_PLANE,
        "keys": [
            (0.00, idle(**READY)),
            (0.06, pose(arm=(0.6, 0.75, 0.3), chest=-30, hips=-10, **L_TUCKED, **COIL_BACK)),
            (0.10, pose(arm=(0.15, 0.15, -1), chest=0, hips=10, lean=-10, **L_TUCKED, **LUNGE_LEFT)),
            (0.14, pose(arm=(-0.45, -0.5, -0.85), chest=25, hips=15, lean=-12, **L_TUCKED, **LUNGE_LEFT)),
            (0.30, idle(**READY)),
        ],
    },
    "DualBladeSlash2": {  # left blade: the mirror cut, stepping in on the right foot
        "hit": 0.1, "plane": None, "lplane": (mirror(DIAG_PLANE[0]), mirror(DIAG_PLANE[1])),
        "keys": [
            (0.00, idle(**READY)),
            (0.06, pose(larm_dir=mirror((0.6, 0.75, 0.3)), chest=30, hips=10, **R_TUCKED, **swap_legs(COIL_BACK))),
            (0.10, pose(larm_dir=mirror((0.15, 0.15, -1)), chest=0, hips=-10, lean=-10, **R_TUCKED, **LUNGE_RIGHT)),
            (0.14, pose(larm_dir=mirror((-0.45, -0.5, -0.85)), chest=-25, hips=-15, lean=-12, **R_TUCKED, **LUNGE_RIGHT)),
            (0.30, idle(**READY)),
        ],
    },
    "DualBladeSlash3": {  # right blade: a wide sweep, the body turning into it (left blade trails)
        "hit": 0.11, "plane": SWEEP_PLANE,
        "keys": [
            (0.00, idle(**READY)),
            (0.06, pose(arm=(0.9, 0.1, 0.3), chest=-40, hips=-25, larm_dir=(-0.5, -0.75, 0.2), lwrist=-60, lblade_lean=FORWARD, **COIL_BACK)),
            (0.11, pose(arm=(0, 0.05, -1), chest=0, hips=5, lean=-8, larm_dir=(-0.55, -0.75, 0.05), lwrist=-60, lblade_lean=FORWARD, **LUNGE_LEFT)),
            (0.16, pose(arm=(-0.8, 0.0, -0.55), chest=40, hips=25, lean=-8, larm_dir=(-0.6, -0.7, 0.2), lwrist=-60, lblade_lean=FORWARD, **LUNGE_LEFT)),
            (0.34, idle(**READY)),
        ],
    },
    "DualBladeSlash4": {  # both blades raised wide, then crossing down in front in an X (the game lunges you)
        "hit": 0.16, "plane": DIAG_PLANE, "lplane": (mirror(DIAG_PLANE[0]), mirror(DIAG_PLANE[1])),
        "keys": [
            (0.00, idle(**READY)),
            (0.10, pose(arm=(0.6, 0.75, 0.3), larm_dir=mirror((0.6, 0.75, 0.3)), lean=12, **SPRING)),
            (0.16, pose(arm=(0.1, 0.1, -1), larm_dir=mirror((0.1, 0.1, -1)), lean=-12, **LUNGE_LEFT)),
            (0.22, pose(arm=(-0.4, -0.5, -0.8), larm_dir=mirror((-0.4, -0.5, -0.8)), lean=-18, **LUNGE_LEFT)),
            (0.32, pose(arm=(-0.4, -0.5, -0.8), larm_dir=mirror((-0.4, -0.5, -0.8)), lean=-18, **LUNGE_LEFT)),
            (0.55, idle(**READY)),
        ],
    },
    "DualBladeGuard": {  # looping block stance; upper body only
        "hit": None, "loop": True, "upper_body_only": True, "plane": None,
        "keys": [
            (0.0, pose(**GUARD)),
            (0.6, pose(lean=-4, **GUARD)),
            (1.2, pose(**GUARD)),
        ],
    },
    # Heavy: gathering, held on its last frame until the rush starts. Upper body only, so the
    # legs can still shuffle.
    "DualBladeWindUp": {
        "hit": None, "upper_body_only": True, "plane": None,
        "keys": [
            (0.00, idle()),
            (0.12, pose(lean=-6, arm=(0.8, -0.55, -0.1), wrist=-60, blade_lean=(0, -1, -0.3),
                        larm_dir=mirror((0.8, -0.55, -0.1)), lwrist=-60, lblade_lean=(0, -1, -0.3))),
            (0.25, pose(lean=-14, **DRAWN)),
            (0.60, pose(lean=-20, **DRAWN_DEEP)),  # tension builds
        ],
    },
    "DualBladeRush": {  # loops while rushing
        "hit": None, "loop": True, "plane": None,
        "keys": [
            (0.0, pose(hips=0, **RUSH_BODY)),
            (RUSH_TIME / 3, pose(hips=120, **RUSH_BODY)),
            (RUSH_TIME * 2 / 3, pose(hips=240, **RUSH_BODY)),
            (RUSH_TIME, pose(hips=360, **RUSH_BODY)),
        ],
    },
}


def main(out_dir):
    lib.SWINGS = ANIMATIONS
    lib.main(out_dir)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
