"""Generates KeyframeSequence .rbxmx files for the orc (assets/enemies/Orc.rbxmx): idle, walk,
run, attack, flinch, and the parried recoil.

    python3 tools/orc_anims.py assets/animations

Then in Studio, like the other generated clips: put each on the orc rig's AnimSaves, load it in
the Animation Editor, publish, and paste the ids into EnemyConfig.Orc.Animations (the attack
into EnemyConfig.Orc.AttackAnimation). The walk and run print the ground speed they're made
for (WalkClipSpeed / RunClipSpeed there): the game plays them faster or slower to match how
fast the orc really moves, so its feet don't slide. Keep OrcAttack's "hit" in sync with
EnemyConfig.Orc.AttackWindup.

The orc came from Avatar Auto Setup, so its rest pose is a T-pose (arms straight out along
X), not R15's arms-down pose, and it's much smaller (short legs, long arms). The standard R15
clips (Roblox's idle and walk, sword_anims.py's) leave its arms in the wrong place. Here poses
are written the usual way (arms hanging along -Y at rest, as in sword_anims.py) and each arm
joint is converted to the T-pose rig. Joint positions below are the rig's attachments.

Space: X right, Y up, Z back (forward is -Z). Angles in degrees. A Pose's CFrame is the
joint's Transform (child relative to parent at the joint).
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sword_anims as lib  # noqa: E402  (shared math + XML helpers)
from sword_anims import aim_arm, cross, identity, matmul, norm, rx, ry, turn_angle  # noqa: E402


def rz(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def transpose(m):
    return [list(row) for row in zip(*m)]


def mirror(v):
    return (-v[0], v[1], v[2])


# --- the rig (attachment positions in each part's frame, from Orc.rbxmx) --------------------

JOINTS = {  # child part: (parent part, position in parent, position in child)
    "LowerTorso": ("HumanoidRootPart", (0, -1.19, 0), (0, 0.28, 0.09)),
    "UpperTorso": ("LowerTorso", (0.01, 0.65, 0.06), (0.01, -0.95, 0.19)),
    "Head": ("UpperTorso", (0, 0.25, -0.04), (0.07, -0.38, 0.27)),
    "RightUpperArm": ("UpperTorso", (0.64, -0.18, 0.2), (-0.02, -0.08, -0.03)),
    "RightLowerArm": ("RightUpperArm", (0.63, -0.11, -0.01), (-0.25, 0.08, 0.2)),
    "RightHand": ("RightLowerArm", (0.51, 0.09, 0.16), (0.21, -0.01, 0.13)),
    "LeftUpperArm": ("UpperTorso", (-0.64, -0.16, 0.22), (-0.03, -0.05, -0.01)),
    "LeftLowerArm": ("LeftUpperArm", (-0.59, -0.06, -0.01), (0.28, 0.11, 0.19)),
    "LeftHand": ("LeftLowerArm", (-0.5, 0.1, 0.14), (-0.21, 0, 0.11)),
    "RightUpperLeg": ("LowerTorso", (0.48, 0.16, 0.11), (0.05, 0.17, 0.02)),
    "RightLowerLeg": ("RightUpperLeg", (0.03, -0.24, 0.03), (0.01, 0.2, -0.02)),
    "RightFoot": ("RightLowerLeg", (-0.04, -0.2, -0.01), (-0.03, -0.16, 0.14)),
    "LeftUpperLeg": ("LowerTorso", (-0.48, 0.18, 0.12), (-0.05, 0.2, 0.03)),
    "LeftLowerLeg": ("LeftUpperLeg", (-0.06, -0.24, 0.04), (-0.04, 0.18, -0.01)),
    "LeftFoot": ("LeftLowerLeg", (-0.03, -0.19, 0), (-0.04, -0.15, 0.15)),
}
THIGH = 0.44  # hip to knee
SHIN = 0.39  # knee to ankle
REST_LEG = THIGH + SHIN
CLAW = 0.7  # wrist to claw tips (roughly; the hands are big)
# Each arm's rest direction (T-pose) turned onto the hanging arm the poses are written for.
ARM_FIX = {"Right": rz(-90), "Left": rz(90)}


# --- poses -----------------------------------------------------------------------------------

def arm(direction, elbow=30, wrist=0, bend=None):
    """An arm: upper arm along `direction` (chest space), the elbow bent `elbow` degrees toward
    `bend` (default: forward, or up if the arm points forward), the wrist flexed `wrist`."""
    return {"dir": norm(direction), "elbow": elbow, "wrist": wrist, "bend": bend}


def larm(direction, elbow=30, wrist=0, bend=None):
    """The left arm, given as the right arm's mirror image (so poses read the same way)."""
    return arm(mirror(direction), elbow, wrist, mirror(bend) if bend else None)


def leg(hip=0, knee=0, splay=4, ankle=None):
    """A leg: thigh swung forward `hip`, knee bent back `knee` (negative), turned out `splay`.
    The ankle keeps the foot flat unless given."""
    return {"hip": hip, "knee": knee, "splay": splay, "ankle": ankle}


def opose(rarm, larm_, lean=-15, pelvis=-8, chest=0, hips=0, roll=0, sway=0.0, lift=0.0,
          lleg=None, rleg=None, head=(0, 0)):
    """One full-body pose. lean: chest tipped back (+) or forward (-) on the hips. pelvis: the
    hips tipped the same way (the legs compensate). chest / hips: twist (+ = turn left).
    roll: hips rocked sideways (+ = right side up). sway: hips shifted right (studs). lift:
    extra height (studs) on top of what keeps the lower foot on the ground. head: (pitch, yaw)
    on top of looking level and forward."""
    return {"rarm": rarm, "larm": larm_, "lean": lean, "pelvis": pelvis, "chest": chest, "hips": hips,
            "roll": roll, "sway": sway, "lift": lift, "lleg": lleg or leg(), "rleg": rleg or leg(), "head": head}


def leg_height(p, side):
    """How far below the hip the ankle is (studs) for this pose."""
    l = p[side]
    tilt = p["pelvis"] + l["hip"]
    return (THIGH * math.cos(math.radians(tilt)) + SHIN * math.cos(math.radians(tilt + l["knee"]))) * math.cos(math.radians(l["splay"]))


def drop(p):
    """How far the hips sink so the lower foot stays on the ground."""
    return REST_LEG - max(leg_height(p, "lleg"), leg_height(p, "rleg")) - p["lift"]


def arm_rotations(a, side):
    """(upper, lower, hand) Transforms for one arm, converted to the T-pose rig."""
    d = a["dir"]
    bend = a["bend"] or ((0, 1, 0) if abs(d[2]) > 0.9 else (0, 0, -1))
    upper = aim_arm(d, bend)  # the arm's local -Z leans toward `bend`; the elbow bends that way
    lower = rx(a["elbow"])
    hand = rx(a["wrist"])
    fix = ARM_FIX[side]
    back = transpose(fix)
    return matmul(upper, fix), matmul(matmul(back, lower), fix), matmul(matmul(back, hand), fix)


def joint_rotations(p):
    rotations = {
        "LowerTorso": matmul(matmul(ry(p["hips"]), rz(-p["roll"])), rx(p["pelvis"])),
        "UpperTorso": matmul(ry(p["chest"]), rx(p["lean"] - p["pelvis"])),
        # Look level and ahead whatever the body does, then (pitch, yaw) on top.
        "Head": matmul(matmul(rx(-p["lean"]), ry(-(p["chest"] + p["hips"]))), matmul(ry(p["head"][1]), rx(p["head"][0]))),
    }
    for side, key in (("Right", "rarm"), ("Left", "larm")):
        upper, lower, hand = arm_rotations(p[key], side)
        rotations[f"{side}UpperArm"], rotations[f"{side}LowerArm"], rotations[f"{side}Hand"] = upper, lower, hand
    for side, key, out in (("Right", "rleg", 1), ("Left", "lleg", -1)):
        l = p[key]
        ankle = l["ankle"] if l["ankle"] is not None else -(p["pelvis"] + l["hip"] + l["knee"])
        rotations[f"{side}UpperLeg"] = matmul(rz(out * l["splay"] + p["roll"] * 0), rx(l["hip"]))
        rotations[f"{side}LowerLeg"] = rx(l["knee"])
        rotations[f"{side}Foot"] = matmul(rx(ankle), rz(-out * l["splay"]))
    return rotations


# --- forward kinematics (to check poses) -----------------------------------------------------

def frames(p):
    """World (HumanoidRootPart-space) rotation and position of every part."""
    r = joint_rotations(p)
    out = {"HumanoidRootPart": (identity(), (0.0, 0.0, 0.0))}
    offsets = {"LowerTorso": (p["sway"], -drop(p), 0)}

    def place(part):
        if part in out:
            return out[part]
        parent, at_parent, at_child = JOINTS[part]
        prot, ppos = place(parent)
        joint = tuple(ppos[i] + lib.apply(prot, at_parent)[i] for i in range(3))
        offset = offsets.get(part, (0, 0, 0))
        joint = tuple(joint[i] + lib.apply(prot, offset)[i] for i in range(3))
        rot = matmul(prot, r[part])
        pos = tuple(joint[i] - lib.apply(rot, at_child)[i] for i in range(3))
        out[part] = (rot, pos)
        return out[part]

    for part in JOINTS:
        place(part)
    return out


def joint_world(f, part):
    """Where `part`'s joint to its parent is."""
    parent, at_parent, _ = JOINTS[part]
    prot, ppos = f[parent]
    return tuple(ppos[i] + lib.apply(prot, at_parent)[i] for i in range(3))


REST_ANKLE_Y = None


def check(p):
    """Claw tips' and ankles' height above the rest-pose ankles (claws shouldn't go below ~-0.2)."""
    f = frames(p)
    report = {}
    for side, out in (("Right", 1), ("Left", -1)):
        rot, _ = f[f"{side}Hand"]
        wrist = joint_world(f, f"{side}Hand")
        tip = tuple(wrist[i] + lib.apply(rot, (out * CLAW, 0, 0))[i] for i in range(3))
        report[side[0] + "claw"] = tip[1] - REST_ANKLE_Y
        report[side[0] + "ankle"] = joint_world(f, f"{side}Foot")[1] - REST_ANKLE_Y
    return report, f


# --- the clips -------------------------------------------------------------------------------

# Hanging arms: long, bent, claws forward of the knees.
R_HANG = arm((0.3, -0.92, -0.2), elbow=35, wrist=10)
L_HANG = larm((0.3, -0.92, -0.2), elbow=35, wrist=10)
STANCE_L = leg(14, -28, splay=7)
STANCE_R = leg(14, -28, splay=7)


def idle_pose(t):
    """The idle at phase t (0..1): hunched, breathing heavily, shoulders rolling, looking about."""
    w = 2 * math.pi * t
    breath = math.sin(w)
    return opose(
        arm((0.3 + 0.03 * breath, -0.92, -0.2 - 0.04 * breath), elbow=35 + 4 * breath, wrist=10),
        larm((0.3 + 0.03 * breath, -0.92, -0.2 - 0.04 * breath), elbow=35 + 4 * breath, wrist=10),
        lean=-17 + 3 * breath, pelvis=-8, chest=3 * math.sin(w + 0.6),
        lleg=STANCE_L, rleg=STANCE_R, lift=-0.015 * (1 - breath),
        head=(6 + 3 * breath, 10 * math.sin(w * 0.5 + 0.3) if t < 1 else 10 * math.sin(0.3)),
    )


def gait_pose(phase, g):
    """A walk or run at `phase` (radians; the right foot is furthest forward at pi/2)."""
    def one(ph):
        hip = g["hip0"] + g["amp"] * math.sin(ph)
        swing = max(0.0, math.cos(ph))  # forward swing: foot off the ground
        knee = -(g["knee0"] + g["knee1"] * swing ** 1.3)
        return leg(hip, knee, splay=g["splay"])

    right, left = one(phase), one(phase + math.pi)
    s = math.sin(phase)
    # Arms swing against the legs: the right arm forward when the left leg is.
    def swing_arm(amount):
        a = math.radians(amount)
        return (0.3, -math.cos(a), -math.sin(a))

    return opose(
        arm(swing_arm(-g["arm"] * s + g["arm0"]), elbow=g["elbow"] + g["elbow1"] * max(0.0, -s), wrist=10),
        larm(swing_arm(g["arm"] * s + g["arm0"]), elbow=g["elbow"] + g["elbow1"] * max(0.0, s), wrist=10),
        lean=g["lean"], pelvis=g["pelvis"], hips=g["yaw"] * s, chest=-g["yaw"] * 1.4 * s,
        roll=g["roll"] * math.cos(phase), sway=g["sway"] * math.cos(phase),
        lift=g["bounce"] * abs(math.cos(phase)), lleg=left, rleg=right, head=(g["look"], 0),
    )


WALK = {"period": 0.62, "hip0": 8, "amp": 32, "knee0": 12, "knee1": 50, "splay": 6, "arm": 20, "arm0": 8,
        "elbow": 35, "elbow1": 15, "lean": -16, "pelvis": -8, "yaw": 8, "roll": 5, "sway": 0.05,
        "bounce": 0.03, "look": 8}
RUN = {"period": 0.38, "hip0": 14, "amp": 48, "knee0": 22, "knee1": 80, "splay": 5, "arm": 42, "arm0": 15,
       "elbow": 70, "elbow1": 20, "lean": -30, "pelvis": -14, "yaw": 10, "roll": 6, "sway": 0.04,
       "bounce": 0.07, "look": 22}


def cycle(g, samples=16):
    keys = []
    for i in range(samples + 1):
        t = i / samples
        keys.append((round(g["period"] * t, 4), gait_pose(2 * math.pi * t, g)))
    return keys


def ground_speed(g, samples=400):
    """The speed (studs/s) the planted foot slides back at: the speed the clip is made for."""
    total, count = 0.0, 0
    dt = g["period"] / samples
    for i in range(samples):
        ph = 2 * math.pi * i / samples
        if math.cos(ph) >= -0.2:  # only well into the stance (foot planted)
            continue
        a, b = gait_pose(ph, g), gait_pose(ph + 2 * math.pi / samples, g)
        fa, fb = frames(a), frames(b)
        za = joint_world(fa, "RightFoot")[2] - fa["HumanoidRootPart"][1][2]
        zb = joint_world(fb, "RightFoot")[2] - fb["HumanoidRootPart"][1][2]
        total += (zb - za) / dt
        count += 1
    return total / count


IDLE_END = idle_pose(0)

# The attack: rear back with the right claw high behind the head and hold it (the cue to
# parry or dash), then a 3-frame snap into a full-extension smash on the hit, then recover.
WOUND = opose(
    arm((0.45, 0.75, 0.5), elbow=75, wrist=-20, bend=(0, 0.3, -1)), larm((0.25, -0.15, -1), elbow=20, wrist=0),
    lean=14, pelvis=-2, chest=-35, hips=-12, lleg=leg(26, -34, splay=8), rleg=leg(-12, -30, splay=6), head=(4, 20),
)
RAISING = opose(  # on the way up: the claw lifted out to the side, the body starting to turn
    arm((0.7, 0.25, -0.35), elbow=60, wrist=-10, bend=(0, 0.6, -0.8)), larm((0.3, -0.5, -0.8), elbow=25, wrist=0),
    lean=0, pelvis=-6, chest=-18, hips=-6, lleg=leg(20, -32, splay=8), rleg=leg(2, -30, splay=6), head=(5, 10),
)
STRAINING = opose(
    arm((0.45, 0.8, 0.58), elbow=82, wrist=-25, bend=(0, 0.3, -1)), larm((0.28, -0.1, -1), elbow=15, wrist=0),
    lean=18, pelvis=0, chest=-40, hips=-14, lleg=leg(28, -36, splay=8), rleg=leg(-14, -32, splay=6), head=(6, 24),
)
# Through the strike the elbow bends along the swing's plane, so the arm doesn't twist mid-snap.
STRIKE_AXIS = norm(cross(norm((0.45, 0.8, 0.58)), norm((-0.15, -0.45, -0.85))))


def along_strike(direction):
    return cross(STRIKE_AXIS, norm(direction))


SNAP = opose(
    arm((0.3, 0.6, -0.75), elbow=35, wrist=-10, bend=along_strike((0.3, 0.6, -0.75))), larm((0.35, -0.6, -0.3), elbow=30, wrist=0),
    lean=-8, pelvis=-8, chest=-5, hips=0, lleg=leg(34, -40, splay=8), rleg=leg(-14, -24, splay=6), head=(0, 4),
)
SMASH = opose(
    arm((-0.15, -0.45, -0.85), elbow=5, wrist=-15, bend=along_strike((-0.15, -0.45, -0.85))), larm((0.5, -0.5, 0.4), elbow=30, wrist=0),
    lean=-34, pelvis=-16, chest=28, hips=12, lleg=leg(52, -62, splay=8), rleg=leg(-24, -10, splay=6), head=(-6, -10),
)
SMASH_HELD = opose(
    arm((-0.15, -0.5, -0.8), elbow=8, wrist=-15, bend=along_strike((-0.15, -0.5, -0.8))), larm((0.5, -0.55, 0.35), elbow=32, wrist=0),
    lean=-31, pelvis=-15, chest=25, hips=10, lleg=leg(50, -60, splay=8), rleg=leg(-22, -10, splay=6), head=(-4, -8),
)
# Pulling the claw back out of the ground (turning the arm back over on the way to the idle).
RECOVER = opose(
    arm((0.2, -0.65, -0.65), elbow=25, wrist=0, bend=(-0.6, -0.6, -0.4)), larm((0.35, -0.7, 0.05), elbow=30, wrist=5),
    lean=-24, pelvis=-12, chest=12, hips=5, lleg=leg(34, -48, splay=8), rleg=leg(-6, -22, splay=7), head=(2, -4),
)

# Hit: a jolt back (chest and head snap back, arms fly up a bit, knees give), then recover.
FLINCH = opose(
    arm((0.5, -0.6, 0.45), elbow=45, wrist=20), larm((0.5, -0.6, 0.45), elbow=45, wrist=20),
    lean=6, pelvis=2, chest=-6, lleg=leg(-4, -36, splay=7), rleg=leg(16, -40, splay=7), head=(22, -6), lift=-0.06,
)
FLINCH_EASE = opose(
    arm((0.45, -0.7, 0.3), elbow=40, wrist=15), larm((0.45, -0.7, 0.3), elbow=40, wrist=15),
    lean=0, pelvis=-2, chest=-4, lleg=leg(2, -32, splay=7), rleg=leg(15, -36, splay=7), head=(14, -4), lift=-0.04,
)

# Parried: the claw arm knocked wide up and back, chest thrown open, head snapped back, a
# stagger step back on the left foot; held, wide open, through the whole stun.
def parried(k):
    return opose(
        arm((0.75, 0.6 + 0.05 * k, 0.55), elbow=15, wrist=-30, bend=(0, 0.3, -1)),
        larm((0.85, -0.25, 0.45 + 0.05 * k), elbow=25, wrist=10),
        lean=22 + 6 * k, pelvis=4 + 2 * k, chest=-24 - 4 * k, hips=-6,
        lleg=leg(-26 - 4 * k, -12, splay=9), rleg=leg(24, -46 - 4 * k, splay=6), head=(30 + 8 * k, 10 + 3 * k),
    )


ANIMATIONS = {
    "OrcIdle": {"loop": True, "linear": False, "hit": None,
                "keys": [(round(2.4 * i / 6, 3), idle_pose(i / 6)) for i in range(7)]},
    "OrcWalk": {"loop": True, "linear": True, "hit": None, "keys": cycle(WALK), "gait": WALK},
    "OrcRun": {"loop": True, "linear": True, "hit": None, "keys": cycle(RUN), "gait": RUN},
    "OrcAttack": {"loop": False, "linear": False, "hit": 0.4, "keys": [
        (0.00, IDLE_END),
        (0.10, RAISING),
        (0.20, WOUND),
        (0.34, STRAINING),  # held: the parry/dodge cue
        (0.37, SNAP),
        (0.40, SMASH),  # the hit: full extension (hitstop freezes on it)
        (0.62, SMASH_HELD),
        (0.78, RECOVER),
        (1.00, IDLE_END),
    ]},
    "OrcFlinch": {"loop": False, "linear": False, "hit": None, "keys": [
        (0.00, IDLE_END), (0.06, FLINCH), (0.16, FLINCH_EASE), (0.38, IDLE_END),
    ]},
    "OrcParried": {"loop": False, "linear": False, "hit": None, "keys": [
        (0.00, parried(0.4)), (0.05, parried(0.8)), (0.11, parried(1.0)), (0.30, parried(0.85)), (0.50, parried(0.8)),
    ]},
}


# --- .rbxmx output ---------------------------------------------------------------------------

def pose_xml(name, rotation, weight, children, depth, linear, position=(0, 0, 0)):
    pad = "\t" * depth
    style = 0 if linear else 3  # Linear for sampled cycles (no stop at every key), else Cubic
    return (
        f'{pad}<Item class="Pose" referent="{lib.next_referent()}"><Properties>{lib.cframe_xml(rotation, position)}'
        f'<token name="EasingDirection">2</token><token name="EasingStyle">{style}</token>'
        f'<string name="Name">{name}</string><float name="Weight">{weight}</float></Properties>\n'
        f'{"".join(children)}{pad}</Item>\n'
    )


def keyframe_xml(time, p, linear, depth=2):
    r = joint_rotations(p)

    def chain(names, start):
        xml = ""
        for offset, name in reversed(list(enumerate(names))):
            xml = pose_xml(name, r[name], 1, [xml] if xml else [], start + offset, linear)
        return xml

    torso = depth + 3
    upper = pose_xml("UpperTorso", r["UpperTorso"], 1, [
        chain(["Head"], torso + 1),
        chain(["RightUpperArm", "RightLowerArm", "RightHand"], torso + 1),
        chain(["LeftUpperArm", "LeftLowerArm", "LeftHand"], torso + 1),
    ], torso, linear)
    lower = pose_xml("LowerTorso", r["LowerTorso"], 1, [
        upper,
        chain(["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], torso),
        chain(["RightUpperLeg", "RightLowerLeg", "RightFoot"], torso),
    ], depth + 2, linear, position=(p["sway"], -drop(p), 0))
    root = pose_xml("HumanoidRootPart", identity(), 0, [lower], depth + 1, linear)
    pad = "\t" * depth
    return (
        f'{pad}<Item class="Keyframe" referent="{lib.next_referent()}"><Properties><string name="Name">Keyframe</string>'
        f'<float name="Time">{time}</float></Properties>\n{root}{pad}</Item>\n'
    )


def main(out_dir):
    global REST_ANKLE_Y
    rest = opose(arm((0, -1, 0), elbow=0), larm((0, -1, 0), elbow=0), lean=0, pelvis=0, lleg=leg(splay=0), rleg=leg(splay=0))
    rest_frames = frames(rest)
    REST_ANKLE_Y = joint_world(rest_frames, "RightFoot")[1]
    assert abs(drop(rest)) < 1e-6

    out = Path(out_dir)
    for name, anim in ANIMATIONS.items():
        print(f"== {name}" + (f" (hit at {anim['hit']}s)" if anim["hit"] else " (looping)" if anim["loop"] else ""))
        if "gait" in anim:
            print(f"  made for {ground_speed(anim['gait']):.2f} studs/s")
        body = ""
        lowest = 9.0
        for time, p in anim["keys"]:
            report, _ = check(p)
            lowest = min(lowest, report["Rclaw"], report["Lclaw"])
            if not anim["linear"]:
                print(f"  t={time:.2f}  drop {drop(p):+.2f}  claws R {report['Rclaw']:+.2f} L {report['Lclaw']:+.2f}  "
                      f"ankles L {report['Lankle']:+.2f} R {report['Rankle']:+.2f}")
            body += keyframe_xml(time, p, anim["linear"])
        worst_joint, worst = "", 0
        for (_, a), (_, b) in zip(anim["keys"], anim["keys"][1:]):
            ra, rb = joint_rotations(a), joint_rotations(b)
            for joint in ra:
                angle = turn_angle(ra[joint], rb[joint])
                if angle > worst:
                    worst_joint, worst = joint, angle
        print(f"  lowest claw {lowest:+.2f}; largest joint turn between keyframes: {worst:.0f} degrees ({worst_joint})")
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
