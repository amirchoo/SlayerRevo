"""Generates R15 KeyframeSequence .rbxmx files for the crossbow: the idle (held low and ready),
the aim (raised to the shoulder, body turned side-on), the shot's kick, and the reload (tipped
down, the string hauled back to the latch with the left hand, a bolt laid in the groove).

    python3 tools/crossbow_anims.py assets/animations

All upper body only, so the legs keep walking. Built on tools/greatsword_anims.py's two-bone
IK: the right hand holds the trigger grip like a pistol (the crossbow runs along the hand's
-Y, its top toward the hand's -Z; see the tool Grip in src/server/SingleShotService.luau), and
the left hand supports it further along or works the string. Poses give the crossbow's
direction in body terms (forward is -Z), turned into chest space through the chest's twist,
so a side-on chest still aims straight ahead. Publish them, then put their ids in the
Crossbow section of src/shared/Config/CombatConfig.luau (the Blunderbuss borrows them).
SingleShotClient stretches the reload
to the reload time and freezes the aim on its last frame.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sword_anims as lib  # noqa: E402
import greatsword_anims as two_hand  # noqa: E402
from sword_anims import apply, cross, dot, identity, matmul, norm, rx, ry, turn_angle  # noqa: E402
from greatsword_anims import LEFT_SHOULDER, RIGHT_SHOULDER, add, scale, solve_arm, sub, transpose  # noqa: E402

RIGHT_ELBOW = (0.9, -0.9, 0.3)  # out and down, like a rifleman's
LEFT_ELBOW = (-0.3, -1, 0.2)  # tucked under the crossbow

# The blocky R15 rig's arms, measured in Studio: shoulder joint to elbow 0.73, elbow to wrist
# 0.76, wrist to the grip attachment 0.275 (along the hand, which isn't in line with the
# forearm when the wrist bends, so the arms are solved to the wrist), and each upper arm hangs
# 0.5 out to the side of its shoulder joint (its own local X), which the shared IK doesn't
# know about; arm() below corrects for it.
two_hand.UPPER_ARM = 0.73
two_hand.FOREARM_TO_GRIP = 0.76  # to the wrist, here
HAND = 0.275
ARM_SIDE_OFFSET = 0.5


def arm(shoulder, target, hint, side):
    """solve_arm, with the upper arm's sideways offset (side: +1 right arm, -1 left): the whole
    arm is shifted along the upper arm's local X, so aim from a shoulder moved by that much
    (which depends on the answer, so a few rounds settle it)."""
    origin = shoulder
    for _ in range(8):
        upper, bend, forearm = solve_arm(origin, target, hint)
        origin = add(shoulder, scale(tuple(upper[i][0] for i in range(3)), ARM_SIDE_OFFSET * side))
    return upper, bend, forearm, origin


def columns(x, y, z):
    return [[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]]


def cpose(hilt, aim, chest=0, lean=0, head=(0, 0), support=0.6, lift=-0.05, palm="up"):
    """hilt: the right hand's grip point in chest space. aim: the way the crossbow points, in
    body terms (forward is -Z). support / lift: where the left hand is, along the crossbow
    from the right hand and up off it (studs). palm: the left palm "up" (under the stock)
    or "down" (on top, working the string), or "side" (against its left side, turning over)."""
    return {"hilt": hilt, "aim": norm(aim), "chest": chest, "lean": lean, "head": head,
            "support": support, "lift": lift, "palm": palm}


def frame(p):
    """The crossbow's forward and top directions in chest space."""
    to_chest = matmul(rx(-p["lean"]), ry(-p["chest"]))
    along = norm(apply(to_chest, p["aim"]))
    world_up = apply(to_chest, (0, 1, 0))
    up = norm(sub(world_up, scale(along, dot(world_up, along))))
    return along, up


def left_target(p):
    along, up = frame(p)
    return add(add(p["hilt"], scale(along, p["support"])), scale(up, p["lift"]))


def wrists(p):
    """Where each wrist goes so its hand's grip point lands on target (both hands point their
    fingers along the crossbow)."""
    along, _ = frame(p)
    return sub(p["hilt"], scale(along, HAND)), sub(left_target(p), scale(along, HAND))


def joint_rotations(p):
    along, up = frame(p)
    right_wrist, left_wrist = wrists(p)
    r_upper, r_bend, r_forearm, _ = arm(RIGHT_SHOULDER, right_wrist, RIGHT_ELBOW, 1)
    l_upper, l_bend, l_forearm, _ = arm(LEFT_SHOULDER, left_wrist, LEFT_ELBOW, -1)

    # Right hand: fingers (-Y) along the crossbow, thumb side (-Z) on top.
    y, z = scale(along, -1), scale(up, -1)
    right_hand = columns(cross(y, z), y, z)
    # Left hand: fingers along it too; the palm (a left hand's +X) up under it or down on it.
    lx = {"up": up, "down": scale(up, -1), "side": cross(along, up)}[p["palm"]]
    ly = scale(along, -1)
    left_hand = columns(lx, ly, cross(lx, ly))

    chest = p["chest"]
    return {
        "LowerTorso": identity(),
        "UpperTorso": matmul(ry(chest), rx(p["lean"])),
        "Head": matmul(matmul(rx(-p["lean"]), ry(-chest)), matmul(ry(p["head"][1]), rx(p["head"][0]))),
        "RightUpperArm": r_upper,
        "RightLowerArm": rx(r_bend),
        "RightHand": matmul(transpose(r_forearm), right_hand),
        "LeftUpperArm": l_upper,
        "LeftLowerArm": rx(l_bend),
        "LeftHand": matmul(transpose(l_forearm), left_hand),
        "LeftUpperLeg": identity(), "LeftLowerLeg": identity(), "LeftFoot": identity(),
        "RightUpperLeg": identity(), "RightLowerLeg": identity(), "RightFoot": identity(),
    }


# --- poses ---------------------------------------------------------------------------

# Positions were picked (by a search) so both hands reach and the stock behind the right hand
# stays out of the torso and head: the body turns side-on (left shoulder forward), so the
# stock runs back past the right shoulder and the left hand reaches the front.
# Held ready in front of the chest, pointing ahead and down, left hand under the front.
IDLE = {"hilt": (0.0, 0.6, -1.2), "aim": (0, -0.45, -1), "chest": -50, "support": 0.4}
# Raised to the eye, fully side-on, head bent to the sights.
AIM = {"hilt": (0.0, 1.0, -1.0), "aim": (0, 0, -1), "chest": -60, "head": (-8, 0), "support": 0.4}
KICK = {"hilt": (0.05, 1.1, -0.9), "aim": (0, 0.25, -1), "chest": -56, "lean": 6, "head": (-2, 0), "support": 0.35}
# Reload: tipped down in front, the left hand hauls the string back to the latch, then lays a
# bolt in the groove.
TIPPED = {"hilt": (0.2, 0.4, -1.0), "aim": (0, -0.6, -0.8), "chest": -60, "lean": -8, "head": (-25, 0)}
ON_STRING = {"support": 0.6, "lift": 0.25, "palm": "down"}
STRING_BACK = {"support": 0.15, "lift": 0.3, "palm": "down"}
BOLT_FRONT = {"support": 0.75, "lift": 0.35, "palm": "down"}
BOLT_LAID = {"support": 0.4, "lift": 0.3, "palm": "down"}


def at(base, **extra):
    return cpose(**{**base, **extra})


ANIMATIONS = {
    "CrossbowIdle": {  # breathing a little
        "loop": True, "hit": None,
        "keys": [
            (0.0, at(IDLE)),
            (1.5, at(IDLE, hilt=(0.0, 0.63, -1.2), lean=-2)),
            (3.0, at(IDLE)),
        ],
    },
    "CrossbowAim": {  # raised to the shoulder; held on its last frame
        "loop": False, "hit": None,
        "keys": [
            (0.0, at(IDLE)),
            (0.1, at(IDLE, hilt=(0.0, 0.8, -1.1), aim=(0, -0.2, -1), chest=-55)),
            (0.2, at(AIM)),
            (0.4, at(AIM)),
        ],
    },
    "CrossbowShoot": {  # the kick, then settling back on aim
        "loop": False, "hit": None,
        "keys": [
            (0.0, at(AIM)),
            (0.05, at(KICK)),
            (0.3, at(AIM)),
        ],
    },
    "CrossbowReload": {  # 1.3 s at normal speed (CrossbowClient stretches it to the reload time)
        "loop": False, "hit": None,
        "keys": [
            (0.0, at(IDLE)),
            (0.1, at({**IDLE, **TIPPED}, hilt=(0.1, 0.5, -1.1), aim=(0, -0.55, -0.85), support=0.5, lift=0.1, palm="side")),
            (0.2, at(TIPPED, **ON_STRING)),
            (0.3, at(TIPPED, **{**ON_STRING, "lift": 0.15})),  # grip the string
            (0.6, at({**TIPPED, **STRING_BACK, "lean": -4})),  # haul it back to the latch
            (0.7, at(TIPPED, **STRING_BACK)),
            (0.85, at(TIPPED, **BOLT_FRONT)),  # a bolt in from the front...
            (1.05, at(TIPPED, **BOLT_LAID)),  # ...slid down the groove
            (1.17, at(IDLE, support=0.4, lift=0.1, palm="side")),
            (1.3, at(IDLE)),
        ],
    },
}


def reach_errors(p):
    """How far each hand ends up from where it was meant to be (the IK clamps an arm that
    can't reach), so a pose asking too much shows up in the output."""
    def reach(shoulder, target, hint, side):
        upper, _, forearm, origin = arm(shoulder, target, hint, side)
        elbow = add(origin, scale(tuple(-upper[i][1] for i in range(3)), two_hand.UPPER_ARM))
        hand = add(elbow, scale(tuple(-forearm[i][1] for i in range(3)), two_hand.FOREARM_TO_GRIP))
        miss = sub(hand, target)
        return math.sqrt(dot(miss, miss))

    right_wrist, left_wrist = wrists(p)
    return reach(RIGHT_SHOULDER, right_wrist, RIGHT_ELBOW, 1), reach(LEFT_SHOULDER, left_wrist, LEFT_ELBOW, -1)


def main(out_dir):
    two_hand.joint_rotations = joint_rotations  # its keyframe writer uses our joints
    out = Path(out_dir)
    for name, anim in ANIMATIONS.items():
        print(f"== {name}" + (" (looping)" if anim["loop"] else ""))
        body = ""
        for time, p in anim["keys"]:
            right_miss, left_miss = reach_errors(p)
            wrist = turn_angle(identity(), joint_rotations(p)["RightHand"])
            print(f"  t={time:.2f}  hands off target: right {right_miss:.2f}  left {left_miss:.2f}  right wrist {wrist:.0f} deg")
            body += two_hand.keyframe_xml(time, p, True)
        worst_joint, worst = "", 0
        for (_, a), (_, b) in zip(anim["keys"], anim["keys"][1:]):
            ra, rb = joint_rotations(a), joint_rotations(b)
            for joint in ra:
                angle = turn_angle(ra[joint], rb[joint])
                if angle > worst:
                    worst_joint, worst = joint, angle
        print(f"  largest joint turn between keyframes: {worst:.0f} degrees ({worst_joint})")
        loop = "true" if anim["loop"] else "false"
        xml = (
            '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
            f'\t<Item class="KeyframeSequence" referent="{lib.next_referent()}"><Properties><bool name="Loop">{loop}</bool>'
            f'<string name="Name">{name}</string><token name="Priority">2</token></Properties>\n{body}\t</Item>\n</roblox>\n'
        )
        (out / f"{name}.rbxmx").write_text(xml)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
