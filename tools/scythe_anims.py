"""Generates R15 KeyframeSequence .rbxmx files for the scythe: a one-handed idle (the shaft
held low at the hip and slung diagonally up behind the back, the blade arching over the left
shoulder), the 3-reap combo (a wide forehand sweep, a full spin, an overhead
crescent), the guard (shaft across the body), and the heavy reap (reach far out and hook,
yank back, then cut).

    python3 tools/scythe_anims.py assets/animations

Built on the greatsword generator's two-hand IK, like the spear: the right hand holds the
shaft low and the left hand further up it (toward the blade). "blade" is the way the shaft
points from the hands to the scythe's head. Every reap turns the body the same way (to the
left), so the blade leads them all.
Keep each reap's "hit" time in sync with HitDelay in the Scythe section of
src/shared/Config/CombatConfig.luau, and ScytheReap's two markers with Heavy.HookDelay
and Heavy.CutDelay.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import greatsword_anims as two_hand  # noqa: E402
import sword_anims as lib  # noqa: E402
from greatsword_anims import gpose  # noqa: E402
from sword_anims import identity, matmul, rx  # noqa: E402

# Negative gap: the left hand sits *ahead* of the right hand, toward the blade.
two_hand.HAND_GAP = -0.75

# Ready: shaft upright beside the right shoulder, leaning back a little, so the blade rides
# high above the head.
READY = {"hilt": (0.6, -0.55, -0.45), "blade": (0.2, 1, 0.2)}
# Sweeps: the shaft reaches out level and the body turns it through a wide arc.
WOUND_RIGHT = {"hilt": (-0.3, 0, -0.5), "blade": (1, 0.1, 0.4)}  # out to the right, head back
SWEEP_RIGHT = {"hilt": (-0.3, -0.1, -0.6), "blade": (0.75, 0, -0.65)}
SWEEP_FRONT = {"hilt": (-0.1, -0.15, -0.7), "blade": (0, -0.05, -1)}
SWEEP_LEFT = {"hilt": (-0.25, -0.15, -0.95), "blade": (-0.75, 0, -0.65)}
WOUND_LEFT = {"hilt": (-0.45, 0, -0.6), "blade": (-1, 0.1, 0.35)}  # carried through to the left
SPIN_OUT = {"hilt": (-0.35, -0.1, -0.65), "blade": (0.85, -0.05, -0.5)}
# Overhead crescent: drawn back over the right shoulder, then brought over and down in front.
SHOULDERED = {"hilt": (0.3, 0.9, -0.3), "blade": (0.15, 0.55, 1)}
OVERHEAD = {"hilt": (0.0, 1.0, -0.4), "blade": (0.05, 1, -0.15)}
COMING_DOWN = {"hilt": (0.0, 0.4, -0.9), "blade": (0, 0.4, -1)}
CRESCENT_LOW = {"hilt": (-0.1, -0.05, -0.7), "blade": (0, -0.55, -0.85)}
# Heavy reap: drawn back, then thrust far out level (the hook), then yanked back in close.
DRAWN = {"hilt": (0.5, -0.2, 0.35), "blade": (0.1, 0.35, -1)}
REACHING = {"hilt": (-0.3, 0.2, -1.0), "blade": (-0.05, 0.15, -1)}
YANKED = {"hilt": (0.45, -0.3, 0.2), "blade": (0.15, 0.3, -1)}
# Guard: the shaft held across the body, blade up to the left.
GUARD = {"hilt": (0.6, -0.2, -0.75), "blade": (-0.9, 0.45, -0.1)}

# Idle: one-handed. The right arm hangs relaxed, a little back, the hand at the hip; the shaft
# runs from the butt (near the ground, out by the right foot) diagonally up behind the back, so
# the blade arches high over the left shoulder. The left arm hangs free (see one_handed).
# The arm is posed directly (FK): the blocky rig's shoulders pivot off the arm's center line,
# which the IK doesn't model, so a hand reaching back would land off target.
SLUNG = {"hilt": (1.5, -0.5, -0.1), "blade": (-0.68, 0.62, 0.38)}
SLUNG_ARM = (-22, 6, 30)  # swing (+ forward), out (+ away from the body), elbow bend

READY_LEGS = {"drop": 0.15, "lleg": (12, -24, 12), "rleg": (12, -24, 12)}
COIL = {"drop": 0.35, "lleg": (25, -45, 20), "rleg": (10, -40, 30)}
COIL_DEEP = {"drop": 0.5, "lleg": (32, -60, 28), "rleg": (14, -55, 41)}
SWEEP_STANCE = {"drop": 0.4, "lleg": (30, -50, 20), "rleg": (5, -45, 40)}
LUNGE = {"drop": 0.6, "lleg": (55, -70, 15), "rleg": (-25, -25, 50)}
LEAN_BACK = {"drop": 0.4, "lleg": (10, -40, 30), "rleg": (35, -55, 20)}  # weight on the back foot


def ready(**extra):
    return gpose(**READY, chest=-15, **extra)


def rz(deg):
    import math
    c, s_ = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[c, -s_, 0], [s_, c, 0], [0, 0, 1]]


def one_handed(p, right_arm, left_arm=(6, 18), roll=0):
    """`p` held in the right hand only. right_arm: (swing, out, elbow) degrees, posed directly
    (its "hilt" is then only a note of where the hand ends up); the hand turns the shaft along
    "blade". left_arm: (swing, elbow) degrees, hanging free. roll: turns the scythe around its
    shaft (degrees), to choose which way the blade faces."""
    return {**p, "right_arm": right_arm, "free_left": left_arm, "roll": roll}


def slung(arm=SLUNG_ARM, **extra):
    return one_handed(gpose(**{**SLUNG, "chest": 12, "lean": -2, **extra}), arm, roll=SLUNG_ROLL)


SLUNG_ROLL = -90  # the blade hangs down behind the left shoulder

# The two-hand generator always puts both hands on the shaft; one_handed poses free the left
# arm and can roll the right hand around the shaft.
_joint_rotations = two_hand.joint_rotations
_lerp_pose = two_hand.lerp_pose


def joint_rotations(p):
    r = _joint_rotations(p)
    if p.get("right_arm"):
        swing, out, elbow = p["right_arm"]
        upper = matmul(rz(out), rx(swing))
        r["RightUpperArm"] = upper
        r["RightLowerArm"] = rx(elbow)
        r["RightHand"] = two_hand.hand_rotation(matmul(upper, rx(elbow)), p["blade"])
    if p.get("free_left"):
        swing, elbow = p["free_left"]
        r["LeftUpperArm"] = rx(swing)
        r["LeftLowerArm"] = rx(elbow)
        r["LeftHand"] = identity()
    if p.get("roll"):
        r["RightHand"] = matmul(r["RightHand"], rz(p["roll"]))
    return r


def lerp_pose(a, b, t):
    mixed = _lerp_pose(a, b, t)
    for key in ("right_arm", "free_left", "roll"):
        if key in a:
            mixed[key] = a[key]
    return mixed


two_hand.joint_rotations = joint_rotations
two_hand.lerp_pose = lerp_pose


ANIMATIONS = {
    "ScytheIdle": {  # upper body only, so the legs walk
        "loop": True, "upper_body_only": True, "hit": None,
        "keys": [
            (0.0, slung()),
            (1.1, slung(arm=(-22, 7, 34), lean=-4)),  # a slow breath
            (2.2, slung()),
        ],
    },
    "ScytheGuard": {
        "loop": True, "upper_body_only": True, "hit": None,
        "keys": [
            (0.0, gpose(**GUARD, chest=-20)),
            (0.6, gpose(**GUARD, chest=-20, lean=-3)),
            (1.2, gpose(**GUARD, chest=-20)),
        ],
    },
    # Reap 1: a wide forehand sweep, right to left.
    "ScytheSlash1": {
        "loop": False, "upper_body_only": False, "hit": 0.2,
        "keys": [
            (0.00, ready(**READY_LEGS)),
            (0.12, gpose(**WOUND_RIGHT, chest=-45, hips=-30, lean=5, **COIL)),
            (0.17, gpose(**SWEEP_RIGHT, chest=-20, hips=-10, **SWEEP_STANCE)),
            (0.20, gpose(**SWEEP_FRONT, chest=5, hips=0, lean=-8, **SWEEP_STANCE)),
            (0.25, gpose(**SWEEP_LEFT, chest=30, hips=20, lean=-6, **SWEEP_STANCE)),
            (0.31, gpose(**WOUND_LEFT, chest=45, hips=30, lean=-4, **SWEEP_STANCE)),
            (0.45, gpose(**WOUND_LEFT, chest=42, hips=28, lean=-2, **COIL)),
            (0.65, ready(**READY_LEGS)),
        ],
    },
    # Reap 2: wind back to the right, then a full turn with the scythe out, all around.
    "ScytheSlash2": {
        "loop": False, "upper_body_only": False, "hit": 0.25,
        "keys": [
            (0.00, ready(head_forward=False, **READY_LEGS)),
            (0.12, gpose(**WOUND_RIGHT, chest=-50, hips=-40, lean=6, head_forward=False, **COIL_DEEP)),
            (0.18, gpose(**SPIN_OUT, chest=-10, hips=20, lean=-6, head_forward=False, **SWEEP_STANCE)),
            (0.25, gpose(**SPIN_OUT, chest=-10, hips=140, lean=-8, head_forward=False, **SWEEP_STANCE)),
            (0.32, gpose(**SPIN_OUT, chest=-10, hips=260, lean=-8, head_forward=False, **SWEEP_STANCE)),
            (0.38, gpose(**WOUND_LEFT, chest=30, hips=360, lean=-4, head_forward=False, **SWEEP_STANCE)),
            (0.52, gpose(**WOUND_LEFT, chest=25, hips=360, lean=-2, head_forward=False, **COIL)),
            (0.75, ready(hips=360, head_forward=False, **READY_LEGS)),
        ],
    },
    # Reap 3 (finisher): drawn back over the shoulder, then a huge crescent over the head and
    # down in front, stepping in (the game lunges you).
    "ScytheSlash3": {
        "loop": False, "upper_body_only": False, "hit": 0.26,
        "keys": [
            (0.00, ready(**READY_LEGS)),
            (0.14, gpose(**SHOULDERED, chest=-40, lean=8, **COIL_DEEP)),
            (0.20, gpose(**OVERHEAD, chest=-15, lean=0, **COIL)),
            (0.23, gpose(**COMING_DOWN, chest=0, lean=-12, **SWEEP_STANCE)),
            (0.27, gpose(**CRESCENT_LOW, chest=10, lean=-28, **LUNGE)),
            (0.55, gpose(**CRESCENT_LOW, chest=10, lean=-26, **LUNGE)),
            (0.90, ready(**READY_LEGS)),
        ],
    },
    # Heavy: draw back, thrust the scythe far out (the hook lands at "hit"), yank it back in
    # (the hooked enemy is dragged in), then one hard sweep all around (the "Cut" marker).
    "ScytheReap": {
        "loop": False, "upper_body_only": False, "hit": 0.3, "cut": 0.78,
        "keys": [
            (0.00, ready(**READY_LEGS)),
            (0.16, gpose(**DRAWN, chest=-35, lean=6, **COIL)),
            (0.28, gpose(**REACHING, chest=10, lean=-20, **LUNGE)),
            (0.36, gpose(**REACHING, chest=10, lean=-18, **LUNGE)),
            (0.55, gpose(**YANKED, chest=-30, lean=8, **LEAN_BACK)),
            (0.66, gpose(**WOUND_RIGHT, chest=-50, hips=-35, lean=6, **COIL_DEEP)),
            (0.74, gpose(**SWEEP_RIGHT, chest=-20, hips=-10, **SWEEP_STANCE)),
            (0.78, gpose(**SWEEP_FRONT, chest=5, hips=0, lean=-10, **SWEEP_STANCE)),
            (0.84, gpose(**SWEEP_LEFT, chest=30, hips=20, lean=-8, **SWEEP_STANCE)),
            (0.92, gpose(**WOUND_LEFT, chest=45, hips=30, lean=-4, **SWEEP_STANCE)),
            (1.05, gpose(**WOUND_LEFT, chest=40, hips=28, lean=-2, **COIL)),
            (1.30, ready(**READY_LEGS)),
        ],
    },
}


def main(out_dir):
    cuts = {name: anim.pop("cut") for name, anim in ANIMATIONS.items() if "cut" in anim}
    two_hand.ANIMATIONS = ANIMATIONS
    two_hand.main(out_dir)
    # The reap's second marker (the cut), next to the "Hit" (the hook) the generator writes.
    for name, cut in cuts.items():
        path = Path(out_dir) / f"{name}.rbxmx"
        xml = path.read_text()
        closing = "\t</Item>\n</roblox>\n"
        path.write_text(xml[: -len(closing)] + lib.marker_xml(cut, "Cut") + closing)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
