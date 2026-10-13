"""Generates R15 KeyframeSequence .rbxmx files for the blunderbuss, held one-handed like a big
pistol: the idle (low by the hip, muzzle down), the aim (arm out straight, right shoulder
forward), the shot's kick (the arm thrown up), and the reload (broken open muzzle-down, the
left hand takes a shell from the belt and thumbs it into the breech, then a flick snaps it
shut).

    python3 tools/blunderbuss_anims.py assets/animations

All upper body only, so the legs keep walking. Reuses tools/crossbow_anims.py's IK and
keyframe writer (the right hand holds it the same way: the gun runs along the hand's -Y, its
top toward the hand's -Z; see the tool Grip in src/server/SingleShotService.luau). The left
hand is free here: a pose gives `left_at` (where the left wrist goes, in chest space) unless
it's on the gun (`support` along it from the right hand, as for the crossbow). Publish them,
then put their ids in the Blunderbuss section of src/shared/Config/CombatConfig.luau.
SingleShotClient stretches the reload to the reload time and freezes the aim on its last frame.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import crossbow_anims as crossbow  # noqa: E402
from crossbow_anims import arm, cpose  # noqa: E402
from greatsword_anims import LEFT_SHOULDER, add, scale, sub  # noqa: E402
from sword_anims import dot, identity, rx  # noqa: E402
import math  # noqa: E402

HANG_ELBOW = (-0.2, -0.4, 0.6)  # a loose left arm's elbow points back
HANG = (-1.45, -0.85, -0.2)  # the left wrist hanging by the side, a little forward

shared_rotations = crossbow.joint_rotations
shared_reach = crossbow.reach_errors


def joint_rotations(p):
    joints = shared_rotations(p)
    if p.get("left_at"):
        upper, bend, _, _ = arm(LEFT_SHOULDER, p["left_at"], HANG_ELBOW, -1)
        joints["LeftUpperArm"] = upper
        joints["LeftLowerArm"] = rx(bend)
        joints["LeftHand"] = identity()
    return joints


def reach_errors(p):
    right, left = shared_reach(p)
    if p.get("left_at"):
        upper, _, forearm, origin = arm(LEFT_SHOULDER, p["left_at"], HANG_ELBOW, -1)
        import greatsword_anims as two_hand
        elbow = add(origin, scale(tuple(-upper[i][1] for i in range(3)), two_hand.UPPER_ARM))
        wrist = add(elbow, scale(tuple(-forearm[i][1] for i in range(3)), two_hand.FOREARM_TO_GRIP))
        miss = sub(wrist, p["left_at"])
        left = math.sqrt(dot(miss, miss))
    return right, left


def at(base, **extra):
    """A pose: `base` with `extra` over it. The left hand hangs free unless the pose puts it
    on the gun (support) or somewhere else (left_at)."""
    merged = {**base, **extra}
    left_at = merged.pop("left_at", None)
    if left_at is None and "support" not in merged:
        left_at = HANG
    p = cpose(**merged)
    p["left_at"] = left_at
    return p


# --- poses ---------------------------------------------------------------------------

# Low ready: by the right hip, muzzle down and ahead, body square.
IDLE = {"hilt": (1.35, -0.35, -0.9), "aim": (0, -0.6, -1), "chest": 10, "head": (0, 0)}
# Arm out straight, right shoulder forward, head down a touch to sight along it.
AIM = {"hilt": (1.15, 0.55, -1.55), "aim": (0, 0, -1), "chest": 25, "head": (-6, 0)}
# The kick throws the arm and the muzzle up and rocks the body back.
KICK = {"hilt": (1.2, 0.95, -1.3), "aim": (0, 0.9, -1), "chest": 30, "lean": 8, "head": (2, 0)}
# Reload: broken open in front of the belly, muzzle tipped down and across, the breech (just
# ahead of the hand) facing up.
OPEN = {"hilt": (0.4, 0.0, -0.7), "aim": (-0.3, -1, -0.6), "chest": -10, "lean": -6, "head": (-25, 0)}
BELT = (-0.75, -0.95, -0.55)  # the left hand at a shell pouch on the belt
# Snapped shut: a flick up, then back down to ready.
FLICK = {"hilt": (1.25, 0.3, -1.2), "aim": (0, 0.6, -1), "chest": 15}


ANIMATIONS = {
    "BlunderbussIdle": {  # breathing a little
        "loop": True, "hit": None,
        "keys": [
            (0.0, at(IDLE)),
            (1.5, at(IDLE, hilt=(1.35, -0.32, -0.9), lean=-2)),
            (3.0, at(IDLE)),
        ],
    },
    "BlunderbussAim": {  # swung up to arm's length; held on its last frame
        "loop": False, "hit": None,
        "keys": [
            (0.0, at(IDLE)),
            (0.1, at(IDLE, hilt=(1.25, 0.2, -1.35), aim=(0, -0.2, -1), chest=18)),
            (0.2, at(AIM)),
            (0.4, at(AIM)),
        ],
    },
    "BlunderbussShoot": {  # the kick, then the arm brought back down on aim
        "loop": False, "hit": None,
        "keys": [
            (0.0, at(AIM)),
            (0.05, at(KICK)),
            (0.15, at(KICK, hilt=(1.2, 0.9, -1.35), aim=(0, 0.75, -1), lean=6)),
            (0.45, at(AIM)),
        ],
    },
    "BlunderbussReload": {  # 1.8 s at normal speed (SingleShotClient stretches it to the reload time)
        "loop": False, "hit": None,
        "keys": [
            (0.0, at(IDLE)),
            (0.2, at(OPEN)),  # broken open, muzzle down
            (0.45, at(OPEN, left_at=BELT, head=(-30, -15))),  # a shell from the belt...
            (0.75, at(OPEN, support=0.45, lift=0.3, palm="down")),  # ...over the breech
            (0.95, at(OPEN, support=0.3, lift=0.15, palm="down")),  # thumbed in
            (1.15, at(OPEN, left_at=(-1.3, -0.6, -0.5))),  # hand away
            (1.35, at(FLICK)),  # flicked up: snaps shut
            (1.55, at(FLICK, hilt=(1.3, 0.1, -1.1), aim=(0, 0.1, -1))),
            (1.8, at(IDLE)),
        ],
    },
}


if __name__ == "__main__":
    crossbow.ANIMATIONS = ANIMATIONS  # its writer works through these
    crossbow.joint_rotations = joint_rotations  # with a free left hand
    crossbow.reach_errors = reach_errors
    crossbow.main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
