"""Generates R15 KeyframeSequence .rbxmx files for the two-handed greatsword.

    python3 tools/greatsword_anims.py assets/animations

Poses are described by where the hilt is and which way the blade points (in chest
space); both arms are solved with two-bone IK so each hand lands on the handle (right hand
near the guard, left hand below it). Reuses the math and .rbxmx writer from sword_anims.py.
Keep the slam's "hit" time in sync with Greatsword.HitDelay in src/shared/Config/CombatConfig.luau.

Chest space: X right, Y up, Z back (forward is -Z), origin at the UpperTorso's center.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sword_anims as lib  # noqa: E402  (shared math + XML helpers)
from sword_anims import cross, dot, identity, matmul, norm, rx, ry, turn_angle  # noqa: E402

# Approximate R15 proportions (studs). Hands land close to these even if your avatar
# differs a little; the rig in Studio is the final judge.
RIGHT_SHOULDER = (1.0, 0.55, 0.0)
LEFT_SHOULDER = (-1.0, 0.55, 0.0)
UPPER_ARM = 0.85
FOREARM_TO_GRIP = 1.05  # elbow to where the hand grips (forearm + hand)
HAND_GAP = 0.55  # left hand sits this far down the handle from the right hand


def sub(a, b):
    return tuple(x - y for x, y in zip(a, b))


def add(a, b):
    return tuple(x + y for x, y in zip(a, b))


def scale(a, s):
    return tuple(x * s for x in a)


def transpose(m):
    return [list(row) for row in zip(*m)]


def solve_arm(shoulder, target, elbow_hint):
    """Two-bone IK. Returns (upper-arm rotation, elbow bend degrees, forearm rotation),
    all in chest space, reaching from `shoulder` toward `target` with the elbow bending
    toward `elbow_hint`."""
    to_target = sub(target, shoulder)
    distance = math.sqrt(dot(to_target, to_target))
    distance = max(abs(UPPER_ARM - FOREARM_TO_GRIP) + 0.01, min(distance, UPPER_ARM + FOREARM_TO_GRIP - 0.01))
    straight = norm(to_target)

    # Angle between the upper arm and the shoulder->target line (law of cosines).
    cos_a = (UPPER_ARM ** 2 + distance ** 2 - FOREARM_TO_GRIP ** 2) / (2 * UPPER_ARM * distance)
    a = math.acos(max(-1, min(1, cos_a)))
    hint = sub(elbow_hint, scale(straight, dot(elbow_hint, straight)))
    perp = norm(hint) if dot(hint, hint) > 1e-6 else norm(cross(straight, (0, 0, 1)))
    upper_dir = add(scale(straight, math.cos(a)), scale(perp, math.sin(a)))

    elbow = add(shoulder, scale(upper_dir, UPPER_ARM))
    forearm_dir = norm(sub(add(shoulder, scale(straight, distance)), elbow))
    bend = math.degrees(math.acos(max(-1, min(1, dot(upper_dir, forearm_dir)))))
    # The forearm bends back toward the target, within the shoulder/target/elbow plane.
    # Taking that direction from the plane (not from the forearm) keeps the arm's twist
    # stable even when the arm is nearly straight.
    lean = add(scale(straight, math.sin(a)), scale(perp, -math.cos(a)))

    upper = lib.aim_arm(upper_dir, lean)  # forearm bends toward `lean` with Rx(+bend)
    forearm = matmul(upper, rx(bend))
    return upper, bend, forearm


def hand_rotation(forearm, blade):
    """Wrist rotation (relative to the forearm) that points the hand's local -Z along
    `blade`. The hand's roll follows the elbow's hinge axis (forearm local X), which is
    always across the forearm, so it stays stable whatever angle the blade is at."""
    hinge = tuple(forearm[i][0] for i in range(3))  # forearm local +X in chest space
    across = sub(hinge, scale(blade, dot(hinge, blade)))
    if dot(across, across) < 1e-6:
        across = norm(cross(blade, (0, 1, 0)))
    x = norm(across)
    z = scale(blade, -1)
    y = cross(z, x)
    hand = [[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]]
    return matmul(transpose(forearm), hand)


STAND = (0, 0, 0)


def gpose(hilt, blade, chest=0, hips=0, lean=0, drop=0.0, lleg=STAND, rleg=STAND, head_forward=True):
    """hilt: right-hand grip point in chest space. blade: direction the blade points.
    head_forward: counter-turn the head so it keeps facing forward through twists (off for
    full spins, where the head should turn with the body)."""
    return {"hilt": hilt, "blade": norm(blade), "chest": chest, "hips": hips, "lean": lean,
            "drop": drop, "lleg": lleg, "rleg": rleg, "head_forward": head_forward}


def joint_rotations(p):
    blade = p["blade"]
    right_target = p["hilt"]
    left_target = sub(p["hilt"], scale(blade, HAND_GAP))
    r_upper, r_bend, r_forearm = solve_arm(RIGHT_SHOULDER, right_target, (1, -0.6, 0.4))
    l_upper, l_bend, l_forearm = solve_arm(LEFT_SHOULDER, left_target, (-1, -0.6, 0.4))
    l_hip, l_knee, l_ankle = (rx(a) for a in p["lleg"])
    r_hip, r_knee, r_ankle = (rx(a) for a in p["rleg"])
    return {
        "LowerTorso": ry(p["hips"]),
        "UpperTorso": matmul(ry(p["chest"]), rx(p["lean"])),
        "Head": matmul(rx(-p["lean"]), ry(-(p["chest"] + p["hips"]))) if p["head_forward"] else rx(-p["lean"]),
        "RightUpperArm": r_upper,
        "RightLowerArm": rx(r_bend),
        "RightHand": hand_rotation(r_forearm, blade),
        "LeftUpperArm": l_upper,
        "LeftLowerArm": rx(l_bend),
        "LeftHand": hand_rotation(l_forearm, blade),
        "LeftUpperLeg": l_hip, "LeftLowerLeg": l_knee, "LeftFoot": l_ankle,
        "RightUpperLeg": r_hip, "RightLowerLeg": r_knee, "RightFoot": r_ankle,
    }


# --- poses ---------------------------------------------------------------------------

# Held in front, both hands on the hilt, blade angled up and forward.
HOLD = {"hilt": (0.35, -0.55, -1.0), "blade": (0.15, 0.85, -0.5)}
# Raised over the right shoulder, blade reaching back.
SHOULDERED = {"hilt": (0.75, 1.45, 0.15), "blade": (0.2, 0.45, 1)}
RAISING = {"hilt": (0.5, 0.6, -0.9), "blade": (0.1, 1, 0.1)}  # lifted in front of the face
RAISING_HIGH = {"hilt": (0.65, 1.2, -0.45), "blade": (0.15, 0.85, 0.55)}  # tipping back over the shoulder
OVERHEAD = {"hilt": (0.3, 1.75, -0.45), "blade": (0.1, 1, -0.1)}
COMING_OVER = {"hilt": (0.35, 1.45, -0.95), "blade": (0.05, 0.75, -0.65)}
COMING_DOWN = {"hilt": (0.3, 0.9, -1.2), "blade": (0, 0.3, -1)}
IMPACT = {"hilt": (0.15, -0.5, -1.3), "blade": (0, -0.75, -0.65)}
LIFTING = {"hilt": (0.3, -0.45, -1.15), "blade": (0.1, 0.15, -1)}  # pulled out of the ground, level
LIFTING_UP = {"hilt": (0.33, -0.5, -1.05), "blade": (0.12, 0.6, -0.8)}
# Upright in front of the face, like a shield.
GUARD = {"hilt": (0.2, -0.1, -0.95), "blade": (-0.1, 1, 0.05)}

# Horizontal sweeps (combo swings): the blade stays roughly level and points out from the
# body while the hips and chest turn it through a wide arc in front.
WOUND_RIGHT = {"hilt": (0.75, 0.05, -0.55), "blade": (1, 0.15, 0.35)}  # blade out to the right, tip back
SWEEP_RIGHT = {"hilt": (0.5, -0.05, -0.95), "blade": (0.75, 0.05, -0.65)}
SWEEP_FRONT = {"hilt": (0.15, -0.1, -1.2), "blade": (0, 0, -1)}
SWEEP_LEFT = {"hilt": (-0.25, -0.05, -1.0), "blade": (-0.75, 0.05, -0.65)}
WOUND_LEFT = {"hilt": (-0.45, 0.1, -0.65), "blade": (-1, 0.15, 0.3)}  # blade out to the left, tip back
# Spin finisher: arms out front, blade trailing out to the right as the body turns left.
SPIN_OUT = {"hilt": (0.35, -0.1, -1.1), "blade": (0.85, 0, -0.5)}

SWEEP_STANCE = {"drop": 0.4, "lleg": (30, -50, 20), "rleg": (5, -45, 40)}

COIL = {"drop": 0.35, "lleg": (25, -45, 20), "rleg": (10, -40, 30)}
COIL_DEEP = {"drop": 0.5, "lleg": (32, -60, 28), "rleg": (14, -55, 41)}
DEEP_LUNGE = {"drop": 0.9, "lleg": (70, -95, 25), "rleg": (-15, -110, 70)}

ANIMATIONS = {
    "GreatswordIdle": {
        "loop": True, "upper_body_only": True, "hit": None,
        "keys": [
            (0.0, gpose(**HOLD, chest=-10)),
            (0.8, gpose(**HOLD, chest=-10, lean=-3)),
            (1.6, gpose(**HOLD, chest=-10)),
        ],
    },
    "GreatswordCharge": {  # played while charging; the game freezes it on its last frame
        "loop": False, "upper_body_only": False, "hit": None,
        "keys": [
            (0.00, gpose(**HOLD, chest=-10)),
            (0.12, gpose(**RAISING, chest=-15, drop=0.15, lleg=(12, -24, 12), rleg=(12, -24, 12))),
            (0.24, gpose(**RAISING_HIGH, chest=-28, lean=3, drop=0.25, lleg=(18, -34, 16), rleg=(10, -30, 20))),
            (0.35, gpose(**SHOULDERED, chest=-35, lean=5, **COIL)),
            (1.60, gpose(**SHOULDERED, chest=-45, lean=8, **COIL_DEEP)),  # tension builds
        ],
    },
    "GreatswordSlam": {
        "loop": False, "upper_body_only": False, "hit": 0.13,
        "keys": [
            (0.00, gpose(**SHOULDERED, chest=-45, lean=8, **COIL_DEEP)),
            (0.07, gpose(**OVERHEAD, chest=-15, **COIL)),
            (0.09, gpose(**COMING_OVER, chest=-7, lean=-7, drop=0.45, lleg=(38, -55, 17), rleg=(3, -50, 47))),
            (0.11, gpose(**COMING_DOWN, chest=0, lean=-15, drop=0.6, lleg=(50, -70, 20), rleg=(-5, -60, 65))),
            (0.15, gpose(**IMPACT, chest=10, lean=-30, **DEEP_LUNGE)),
            (0.45, gpose(**IMPACT, chest=10, lean=-30, **DEEP_LUNGE)),
            (0.60, gpose(**LIFTING, chest=0, lean=-15, drop=0.5, lleg=(45, -65, 20), rleg=(-5, -60, 65))),
            (0.72, gpose(**LIFTING_UP, chest=-5, lean=-6, drop=0.2, lleg=(18, -30, 12), rleg=(5, -25, 20))),
            (0.85, gpose(**HOLD, chest=-10)),
        ],
    },
    "GreatswordGuard": {
        "loop": True, "upper_body_only": True, "hit": None,
        "keys": [
            (0.0, gpose(**GUARD, chest=-15)),
            (0.6, gpose(**GUARD, chest=-15, lean=-3)),
            (1.2, gpose(**GUARD, chest=-15)),
        ],
    },
    # Combo swing 1: forehand sweep, right to left. Hit timings match Greatsword.Combo.
    "GreatswordSwing1": {
        "loop": False, "upper_body_only": False, "hit": 0.30,
        "keys": [
            (0.00, gpose(**HOLD, chest=-10)),
            (0.20, gpose(**WOUND_RIGHT, chest=-45, hips=-25, lean=5, **COIL)),
            (0.26, gpose(**SWEEP_RIGHT, chest=-20, hips=-10, **SWEEP_STANCE)),
            (0.30, gpose(**SWEEP_FRONT, chest=5, hips=0, lean=-8, **SWEEP_STANCE)),
            (0.35, gpose(**SWEEP_LEFT, chest=30, hips=20, lean=-6, **SWEEP_STANCE)),
            (0.42, gpose(**WOUND_LEFT, chest=45, hips=30, lean=-4, **SWEEP_STANCE)),
            (0.58, gpose(**WOUND_LEFT, chest=42, hips=28, lean=-2, **COIL)),
            (0.85, gpose(**HOLD, chest=-10)),
        ],
    },
    # Combo swing 2: backhand sweep, left to right.
    "GreatswordSwing2": {
        "loop": False, "upper_body_only": False, "hit": 0.29,
        "keys": [
            (0.00, gpose(**HOLD, chest=-10)),
            (0.19, gpose(**WOUND_LEFT, chest=40, hips=25, lean=5, **COIL)),
            (0.25, gpose(**SWEEP_LEFT, chest=20, hips=10, **SWEEP_STANCE)),
            (0.29, gpose(**SWEEP_FRONT, chest=-5, hips=-5, lean=-8, **SWEEP_STANCE)),
            (0.34, gpose(**SWEEP_RIGHT, chest=-30, hips=-20, lean=-6, **SWEEP_STANCE)),
            (0.41, gpose(**WOUND_RIGHT, chest=-45, hips=-28, lean=-4, **SWEEP_STANCE)),
            (0.58, gpose(**WOUND_RIGHT, chest=-42, hips=-25, lean=-2, **COIL)),
            (0.85, gpose(**HOLD, chest=-10)),
        ],
    },
    # Combo swing 3 (finisher): wind up right, then one full spin with the blade out,
    # hitting all the way around.
    "GreatswordSwing3": {
        "loop": False, "upper_body_only": False, "hit": 0.42,
        "keys": [
            (0.00, gpose(**HOLD, chest=-10, head_forward=False)),
            (0.22, gpose(**WOUND_RIGHT, chest=-50, hips=-40, lean=6, head_forward=False, **COIL_DEEP)),
            (0.30, gpose(**SPIN_OUT, chest=-10, hips=20, lean=-6, head_forward=False, **SWEEP_STANCE)),
            (0.38, gpose(**SPIN_OUT, chest=-10, hips=140, lean=-8, head_forward=False, **SWEEP_STANCE)),
            (0.46, gpose(**SPIN_OUT, chest=-10, hips=260, lean=-8, head_forward=False, **SWEEP_STANCE)),
            (0.54, gpose(**WOUND_LEFT, chest=30, hips=360, lean=-4, head_forward=False, **SWEEP_STANCE)),
            (0.72, gpose(**WOUND_LEFT, chest=25, hips=360, lean=-2, head_forward=False, **COIL)),
            (1.00, gpose(**HOLD, chest=-10, hips=360, head_forward=False)),
        ],
    },
}


MAX_TURN = 100  # degrees; steps bigger than this get a halfway pose inserted


def lerp_pose(a, b, t):
    """Pose partway between a and b (blade direction re-normalized)."""
    mix = lambda x, y: x + (y - x) * t  # noqa: E731
    mix3 = lambda u, v: tuple(mix(x, y) for x, y in zip(u, v))  # noqa: E731
    return {
        "hilt": mix3(a["hilt"], b["hilt"]), "blade": norm(mix3(a["blade"], b["blade"])),
        "chest": mix(a["chest"], b["chest"]), "hips": mix(a["hips"], b["hips"]),
        "lean": mix(a["lean"], b["lean"]), "drop": mix(a["drop"], b["drop"]),
        "lleg": mix3(a["lleg"], b["lleg"]), "rleg": mix3(a["rleg"], b["rleg"]),
        "head_forward": a["head_forward"],
    }


def largest_turn(a, b):
    ra, rb = joint_rotations(a), joint_rotations(b)
    return max(turn_angle(ra[joint], rb[joint]) for joint in ra)


def subdivide(keys, depth=0):
    """Inserts halfway poses wherever a joint would turn more than MAX_TURN in one step,
    so Roblox's shortest-path blending can't take the long way round."""
    result = [keys[0]]
    for (ta, a), (tb, b) in zip(keys, keys[1:]):
        if depth < 4 and largest_turn(a, b) > MAX_TURN:
            middle = ((ta + tb) / 2, lerp_pose(a, b, 0.5))
            result.extend(subdivide([(ta, a), middle, (tb, b)], depth + 1)[1:])
        else:
            result.append((tb, b))
    return result


# --- .rbxmx output -----------------------------------------------------------------

def keyframe_xml(time, p, upper_body_only, depth=2):
    r = joint_rotations(p)

    def chain(names, start_depth):
        xml = ""
        for offset, name in reversed(list(enumerate(names))):
            xml = lib.pose_xml(name, r[name], 1, [xml] if xml else [], start_depth + offset)
        return xml

    torso_depth = depth + 3
    upper = lib.pose_xml("UpperTorso", r["UpperTorso"], 1, [
        chain(["Head"], torso_depth + 1),
        chain(["RightUpperArm", "RightLowerArm", "RightHand"], torso_depth + 1),
        chain(["LeftUpperArm", "LeftLowerArm", "LeftHand"], torso_depth + 1),
    ], torso_depth)
    if upper_body_only:
        lower = lib.pose_xml("LowerTorso", identity(), 0, [upper], depth + 2)
    else:
        lower = lib.pose_xml("LowerTorso", r["LowerTorso"], 1, [
            upper,
            chain(["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], torso_depth),
            chain(["RightUpperLeg", "RightLowerLeg", "RightFoot"], torso_depth),
        ], depth + 2, position=(0, -p["drop"], 0))
    root = lib.pose_xml("HumanoidRootPart", identity(), 0, [lower], depth + 1)
    pad = "\t" * depth
    return (
        f'{pad}<Item class="Keyframe" referent="{lib.next_referent()}"><Properties><string name="Name">Keyframe</string>'
        f'<float name="Time">{time}</float></Properties>\n{root}{pad}</Item>\n'
    )


def hand_gap(p):
    """Distance between where IK put the two grip points (should be ~HAND_GAP if both reach)."""
    def reach(shoulder, target, hint):
        upper, bend, forearm = solve_arm(shoulder, target, hint)
        elbow = add(shoulder, scale(tuple(-upper[i][1] for i in range(3)), UPPER_ARM))
        return add(elbow, scale(tuple(-forearm[i][1] for i in range(3)), FOREARM_TO_GRIP))

    right = reach(RIGHT_SHOULDER, p["hilt"], (1, -0.6, 0.4))
    left = reach(LEFT_SHOULDER, sub(p["hilt"], scale(p["blade"], HAND_GAP)), (-1, -0.6, 0.4))
    return math.sqrt(dot(sub(right, p["hilt"]), sub(right, p["hilt"]))), math.sqrt(dot(sub(left, right), sub(left, right)))


def main(out_dir):
    out = Path(out_dir)
    for name, anim in ANIMATIONS.items():
        anim["keys"] = subdivide(anim["keys"])
        print(f"== {name}" + (f" (hit at {anim['hit']}s)" if anim["hit"] else " (looping)" if anim["loop"] else ""))
        body = ""
        for time, p in anim["keys"]:
            miss, gap = hand_gap(p)
            print(f"  t={time:.2f}  right hand off target {miss:.2f}  hands apart {gap:.2f} (want {HAND_GAP})")
            body += keyframe_xml(time, p, anim["upper_body_only"])
        worst_joint, worst = "", 0
        for (_, a), (_, b) in zip(anim["keys"], anim["keys"][1:]):
            ra, rb = joint_rotations(a), joint_rotations(b)
            for joint in ra:
                angle = turn_angle(ra[joint], rb[joint])
                if angle > worst:
                    worst_joint, worst = joint, angle
        print(f"  largest joint turn between keyframes: {worst:.0f} degrees ({worst_joint})")
        if anim["hit"]:
            body += lib.marker_xml(anim["hit"], "Hit")
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
