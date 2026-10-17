"""Authors R15 animation clips in Blender and bakes them into .rbxmx KeyframeSequences. Run it
through tools/blender/author.sh:

    sh tools/blender/author.sh SwordSwing1 [more clips]

The clips themselves are written as data in tools/blender/*_clips.py (see sword_clips.py for
the format). Each key is a whole-body pose given by controls, not joint angles:
  * the sword: where the hand grips it, which way the blade points, which way its edge faces
  * the left wrist, the elbows' and knees' pole points (which way they bend)
  * the hips (offset and turn), the chest (turn and lean), the head's look
  * each foot's spot on the ground and its turn
Blender solves the arms and legs by IK, so a foot keyed in place stays planted and the blade
goes exactly where it's keyed. Between keys every control follows a real f-curve (Bezier, or an
ease in/out per key). The result is sampled 60 times a second into the clip, with Linear easing
between samples, so Roblox plays the same curves.

The rig is preview_anim.py's (the joint offsets of Workspace.Rig), so a baked clip previews
exactly as it will play. Each clip's rig and keys are also saved as build/anim_author/<Clip>.blend
for a look in Blender.

Coordinates in the clip files are Blender's: X right, Y forward, Z up, in studs, with the ground
at Z = 0 and the character's root above the origin.
"""
import argparse
import importlib.util
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

sys.path.insert(0, str(Path(__file__).parent))
import preview_anim as rig  # noqa: E402

TO_BLENDER = rig.TO_BLENDER
TO_ROBLOX = TO_BLENDER.inverted()
SAMPLE_RATE = 60  # samples per second in the baked clip
FPS = 60  # Blender scene frame rate (keys can sit on fractional frames)

# Easing names used by the clip files, for the segment from a key to the next one.
EASES = {
    "smooth": ("BEZIER", None),  # auto-clamped Bezier: flows through the keys
    "in": ("CUBIC", "EASE_IN"),  # starts slow, arrives fastest (a whip into the hit)
    "out": ("CUBIC", "EASE_OUT"),  # leaves fast, eases to a stop (a flick, a follow-through)
    "inout": ("CUBIC", "EASE_IN_OUT"),
    "linear": ("LINEAR", None),  # constant speed (a held pose that barely creeps)
}

GRIP_TO_WRIST = Vector((0, 0.125, 0))  # hand-local (Roblox): the wrist joint from the hand's center
FOOT_TO_ANKLE = Vector((0, 0.1019, 0))  # foot-local (Roblox): the ankle joint from the foot's center


def roblox_vec(v):
    """Blender-space vector to Roblox space."""
    return (TO_ROBLOX.to_3x3() @ Vector(v))


def rot_roblox(yaw=0.0, pitch=0.0, roll=0.0):
    """Roblox-axis rotation: yaw about Y (+ = turn left), pitch about X (+ = tip back / look up),
    roll about Z. Applied yaw, then pitch, then roll."""
    return (Matrix.Rotation(math.radians(yaw), 4, "Y") @ Matrix.Rotation(math.radians(pitch), 4, "X")
            @ Matrix.Rotation(math.radians(roll), 4, "Z"))


# --- the rig -------------------------------------------------------------------------------

def rest_world():
    """Rest CFrames (Roblox space) of every part, and of every joint (the pose's pivot)."""
    parts = rig.solve({}, 0)
    joints = {}
    for part1, part0, c0, _ in rig.JOINTS:
        joints[part1] = parts[part0] @ rig.translation(c0)
    return parts, joints


def frame_along(direction, hint=Vector((1, 0, 0))):
    """A rotation (Roblox space) whose Y axis is `direction`."""
    y = Vector(direction).normalized()
    x = (hint - hint.dot(y) * y)
    if x.length < 1e-4:
        x = Vector((0, 0, 1)) - y.z * y
    x.normalize()
    z = x.cross(y)
    m = Matrix((x, y, z)).transposed()
    return m.to_4x4()


TAIL_OF = {  # where each bone's tail is: the next joint, or an offset for the end bones
    "LowerTorso": "UpperTorso", "UpperTorso": "Head",
    "RightUpperArm": "RightLowerArm", "RightLowerArm": "RightHand",
    "LeftUpperArm": "LeftLowerArm", "LeftLowerArm": "LeftHand",
    "RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot",
    "LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot",
}
END_OFFSET = {"Head": (0, 1.2, 0), "RightHand": (0, -0.3, 0), "LeftHand": (0, -0.3, 0),
              "RightFoot": (0, -0.15, -0.5), "LeftFoot": (0, -0.15, -0.5)}
UPRIGHT = {"LowerTorso", "UpperTorso", "Head"}  # rest rotation = the part's (bone axes = Roblox axes)


def new_empty(name, matrix=None, parent=None, size=0.3, shape="PLAIN_AXES"):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_type = shape
    obj.empty_display_size = size
    bpy.context.scene.collection.objects.link(obj)
    if parent is not None:
        obj.parent = parent
        obj.matrix_parent_inverse = Matrix.Identity(4)
    if matrix is not None:
        obj.matrix_basis = matrix
    return obj


def build_rig():
    parts, joints = rest_world()
    arm_data = bpy.data.armatures.new("R15")
    arm = bpy.data.objects.new("R15", arm_data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="EDIT")
    rest_bone = {}
    for part1, part0, _, _ in rig.JOINTS:
        head = joints[part1].to_translation()
        tail = joints[TAIL_OF[part1]].to_translation() if part1 in TAIL_OF else head + Vector(END_OFFSET[part1])
        rot = Matrix.Identity(4) if part1 in UPRIGHT else frame_along(tail - head)
        eb = arm_data.edit_bones.new(part1)
        eb.head, eb.tail = (0, 0, 0), (0, (tail - head).length, 0)
        eb.matrix = TO_BLENDER @ Matrix.Translation(head) @ rot
        if part0 in arm_data.edit_bones:
            eb.parent = arm_data.edit_bones[part0]
        rest_bone[part1] = eb.matrix.copy()
    bpy.ops.object.mode_set(mode="POSE")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    # The legs are dead straight at rest, and Blender's IK can't start bending a straight chain,
    # so it starts from a slight knee bend (the IK result replaces it).
    for side in ("Left", "Right"):
        arm.pose.bones[f"{side}UpperLeg"].rotation_quaternion = Quaternion((1, 0, 0), math.radians(-8))
        arm.pose.bones[f"{side}LowerLeg"].rotation_quaternion = Quaternion((1, 0, 0), math.radians(16))

    part_rest = {name: TO_BLENDER @ m for name, m in parts.items()}  # Blender space
    ctl = {}
    # The sword: its control sits at the hand's center with the hand's axes (blade along local
    # -Z, edge along +Y). It points its -Z at the Tip and turns its +Y toward the Edge point.
    ctl["Sword"] = new_empty("SwordCtl", part_rest["RightHand"], size=0.4, shape="ARROWS")
    ctl["Tip"] = new_empty("BladeTip", Matrix.Translation(part_rest["RightHand"] @ Vector((0, 0, -4))), size=0.25, shape="SPHERE")
    ctl["Edge"] = new_empty("EdgeAim", Matrix.Translation(part_rest["RightHand"] @ Vector((0, 2, 0))), size=0.15)
    c = ctl["Sword"].constraints.new("DAMPED_TRACK")
    c.target, c.track_axis = ctl["Tip"], "TRACK_NEGATIVE_Z"
    c = ctl["Sword"].constraints.new("LOCKED_TRACK")
    c.target, c.track_axis, c.lock_axis = ctl["Edge"], "TRACK_Y", "LOCK_Z"
    hand_align = new_empty("HandAlign", part_rest["RightHand"].inverted() @ rest_bone["RightHand"], parent=ctl["Sword"], size=0.1)
    wrist = new_empty("WristTarget", Matrix.Translation(GRIP_TO_WRIST), parent=ctl["Sword"], size=0.1)
    ctl["Elbow"] = new_empty("ElbowPole", Matrix.Translation((3, -1.5, 3.5)), size=0.2, shape="CUBE")
    ik(arm, "RightLowerArm", wrist, ctl["Elbow"])
    copy_rotation(arm, "RightHand", hand_align)

    ctl["LWrist"] = new_empty("LWrist", Matrix.Translation(TO_BLENDER @ joints["LeftHand"].to_translation()), size=0.25, shape="SPHERE")
    ctl["LElbow"] = new_empty("LElbowPole", Matrix.Translation((-3, -1.5, 3.5)), size=0.2, shape="CUBE")
    ik(arm, "LeftLowerArm", ctl["LWrist"], ctl["LElbow"])

    for side in ("Left", "Right"):
        foot = new_empty(f"{side}FootCtl", part_rest[f"{side}Foot"], size=0.4, shape="ARROWS")
        ctl[f"{side}Foot"] = foot
        align = new_empty(f"{side}FootAlign", part_rest[f"{side}Foot"].inverted() @ rest_bone[f"{side}Foot"], parent=foot, size=0.1)
        ankle = new_empty(f"{side}Ankle", Matrix.Translation(FOOT_TO_ANKLE), parent=foot, size=0.1)
        ctl[f"{side}Knee"] = new_empty(f"{side}KneePole", Matrix.Translation((0, 3, 1.5)), size=0.2, shape="CUBE")
        ik(arm, f"{side}LowerLeg", ankle, ctl[f"{side}Knee"])
        copy_rotation(arm, f"{side}Foot", align)

    # The head looks where HeadAim faces (in the world), mostly: a little of the body's turn
    # still comes through.
    ctl["Head"] = new_empty("HeadAim", rest_bone["Head"], size=0.5, shape="SINGLE_ARROW")
    copy_rotation(arm, "Head", ctl["Head"], influence=0.85)

    calibrate_poles(arm, joints)
    return arm, ctl, rest_bone, part_rest


def ik(arm, bone, target, pole):
    c = arm.pose.bones[bone].constraints.new("IK")
    c.target, c.pole_target, c.chain_count = target, pole, 2
    c.use_stretch = False
    c.iterations = 500


def copy_rotation(arm, bone, target, influence=1.0):
    c = arm.pose.bones[bone].constraints.new("COPY_ROTATION")
    c.target = target
    c.influence = influence


def calibrate_poles(arm, joints):
    """Finds each IK chain's pole angle, so the elbow or knee bends toward its pole point."""
    tests = {  # lower bone: (target, pole) for a clearly bent limb (Blender space)
        "RightLowerArm": ((1.6, 0.9, 3.0), (3.0, -1.5, 3.5)),
        "LeftLowerArm": ((-1.6, 0.9, 3.0), (-3.0, -1.5, 3.5)),
        "RightLowerLeg": ((0.5, 0.6, 0.7), (0.5, 3.0, 1.5)),
        "LeftLowerLeg": ((-0.5, 0.6, 0.7), (-0.5, 3.0, 1.5)),
    }
    target = new_empty("CalTarget")
    pole = new_empty("CalPole")
    for bone, (t, p) in tests.items():
        c = arm.pose.bones[bone].constraints["IK"]
        saved = c.target, c.pole_target
        c.target, c.pole_target = target, pole
        target.location, pole.location = t, p
        best = None
        for step in range(-180, 180, 5):  # coarse scan, then a fine one around the best
            c.pole_angle = math.radians(step)
            off = pole_offset(arm, bone, Vector(p))
            if best is None or abs(off) < abs(best[0]):
                best = (off, c.pole_angle)
        for step in range(-50, 51):
            c.pole_angle = best[1] + math.radians(step / 10)
            off = pole_offset(arm, bone, Vector(p))
            if abs(off) < abs(best[0]):
                best = (off, c.pole_angle)
        c.pole_angle = best[1]
        c.target, c.pole_target = saved
        print(f"AUTHOR pole {bone}: {math.degrees(best[1]):.1f} deg (off by {math.degrees(best[0]):.2f})")
    bpy.data.objects.remove(target)
    bpy.data.objects.remove(pole)


def pole_offset(arm, bone, pole):
    """Signed angle (radians) from the pole's direction to the bend's direction, around the limb."""
    bpy.context.view_layer.update()
    lower = arm.pose.bones[bone]
    upper = lower.parent
    a, mid, b = upper.head, upper.tail, lower.tail
    axis = (b - a).normalized()

    def flat(v):
        v = v - a
        return (v - v.dot(axis) * axis).normalized()

    bend, want = flat(mid), flat(pole)
    return math.atan2(want.cross(bend).dot(axis), want.dot(bend))


# --- poses --------------------------------------------------------------------------------

BLADE_REACH = 4.0  # how far out along the blade its Tip control sits (direction is all that counts)


def pose_controls(p):
    """{control: (location, rotation quaternion or None)} for one pose (see sword_clips.py)."""
    grip = Vector(p["grip"])
    blade = Vector(p["blade"]).normalized()
    edge = Vector(p["edge"])
    edge = (edge - edge.dot(blade) * blade).normalized()
    out = {
        "Sword": (grip, None),
        "Tip": (grip + blade * BLADE_REACH, None),
        "Edge": (grip + blade * 1.5 + edge * 2.0, None),
        "Elbow": (Vector(p["elbow"]), None),
        "LWrist": (Vector(p["lwrist"]), None),
        "LElbow": (Vector(p["lelbow"]), None),
    }
    for side, key in (("Left", "lfoot"), ("Right", "rfoot")):
        x, y, z, yaw = p[key][:4]
        pitch = p[key][4] if len(p[key]) > 4 else 0.0
        turn = Matrix.Rotation(math.radians(yaw), 4, "Z") @ Matrix.Rotation(math.radians(pitch), 4, "X")
        out[f"{side}Foot"] = (Vector((x, y, z)), (turn @ TO_BLENDER).to_quaternion())
        ahead = (turn.to_3x3() @ Vector((0, 1, 0)))
        knee = p.get(f"{key}_knee")
        out[f"{side}Knee"] = (Vector(knee) if knee else Vector((x, y, 1.4)) + ahead * 3.0, None)
    yaw, pitch = p.get("head", (0, 0))
    out["Head"] = (None, (TO_BLENDER @ rot_roblox(yaw, pitch)).to_quaternion())
    return out


def bone_rotations(p):
    """{bone: (location or None, quaternion)} for the keyed (FK) bones, in bone space."""
    hx, hy, hz = p.get("hips", (0, 0, 0))
    out = {
        "LowerTorso": (roblox_vec((hx, hy, hz)), rot_roblox(*p.get("hips_turn", (0,))).to_quaternion()),
        "UpperTorso": (None, rot_roblox(*p.get("chest", (0,))).to_quaternion()),
    }
    return out


def key_clip(arm, ctl, clip):
    scene = bpy.context.scene
    last_q = {}
    key_frames = []

    def same_side(name, q):
        prev = last_q.get(name)
        if prev is not None and prev.dot(q) < 0:
            q = -q
        last_q[name] = q
        return q

    for key in clip["keys"]:
        t, p = key[0], key[1]
        frame = t * FPS
        key_frames.append((frame, key[2] if len(key) > 2 else "smooth"))
        for name, (loc, q) in pose_controls(p).items():
            obj = ctl[name]
            if loc is not None:
                obj.location = loc
                obj.keyframe_insert("location", frame=frame)
            if q is not None:
                obj.rotation_mode = "QUATERNION"
                obj.rotation_quaternion = same_side(name, q)
                obj.keyframe_insert("rotation_quaternion", frame=frame)
        for name, (loc, q) in bone_rotations(p).items():
            pb = arm.pose.bones[name]
            if loc is not None:
                pb.location = loc
                pb.keyframe_insert("location", frame=frame)
            pb.rotation_quaternion = same_side("bone " + name, q)
            pb.keyframe_insert("rotation_quaternion", frame=frame)

    # Each key's easing applies to the segment that leaves it.
    actions = [o.animation_data.action for o in [arm, *ctl.values()] if o.animation_data and o.animation_data.action]
    for action in actions:
        for fcurve in action_fcurves(action):
            for kp in fcurve.keyframe_points:
                ease = min(key_frames, key=lambda k: abs(k[0] - kp.co.x))[1]
                interp, easing = EASES[ease]
                kp.interpolation = interp
                if easing:
                    kp.easing = easing
                kp.handle_left_type = kp.handle_right_type = "AUTO_CLAMPED"
            fcurve.update()
    scene.frame_start, scene.frame_end = 0, math.ceil(clip["keys"][-1][0] * FPS)


def action_fcurves(action):
    if hasattr(action, "fcurves") and len(action.fcurves):
        return list(action.fcurves)
    # Blender 4.4+ layered actions
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in strip.channelbags:
                out.extend(bag.fcurves)
    return out


# --- baking -------------------------------------------------------------------------------

def sample(arm, rest_bone, part_rest, t):
    """Each joint's Transform (Roblox space) at time t."""
    scene = bpy.context.scene
    frame = t * FPS
    scene.frame_set(int(math.floor(frame)), subframe=frame - math.floor(frame))
    depsgraph = bpy.context.evaluated_depsgraph_get()
    pose = arm.evaluated_get(depsgraph).pose
    world = {"HumanoidRootPart": rig.translation((0, rig.ROOT_HEIGHT, 0))}
    transforms = {}
    for part1, part0, c0, c1 in rig.JOINTS:
        delta = pose.bones[part1].matrix @ rest_bone[part1].inverted()
        world[part1] = TO_ROBLOX @ delta @ part_rest[part1]
        transforms[part1] = (world[part0] @ rig.translation(c0)).inverted() @ world[part1] @ rig.translation(c1)
    return transforms, world


def bake(arm, rest_bone, part_rest, clip, name):
    end = clip["keys"][-1][0]
    times = sorted({round(i / SAMPLE_RATE, 5) for i in range(int(round(end * SAMPLE_RATE)) + 1)}
                   | {round(k[0], 5) for k in clip["keys"]} | ({round(clip["hit"] + d, 5) for d in (-1 / SAMPLE_RATE, 0, 1 / SAMPLE_RATE)} if clip.get("hit") is not None else set()))
    frames = []
    worst_slip = 0.0
    for t in times:
        transforms, world = sample(arm, rest_bone, part_rest, t)
        for part, m in transforms.items():
            if part != "LowerTorso":
                worst_slip = max(worst_slip, m.to_translation().length)
        frames.append((t, transforms, world))
    print(f"AUTHOR {name}: {len(frames)} samples over {end:.2f} s (joint gap {worst_slip:.4f} studs)")
    return frames


# Keyframe thinning: a sample is dropped when playing straight from the kept one before it to
# the next kept one (Roblox's Linear blend) lands within these of it, for every joint. Holds and
# slow parts thin out; fast cuts keep every sample. Keeps the files small enough to publish.
THIN_ANGLE = 1.5  # degrees
THIN_MOVE = 0.02  # studs (the hips)


def blend_off(a, b, mid, u):
    """How far (degrees, studs) a Linear blend of a to b at u misses mid, over all joints."""
    worst_angle, worst_move = 0.0, 0.0
    for part, m in mid.items():
        qa, qb = a[part].to_quaternion(), b[part].to_quaternion()
        q = qa.slerp(qb, u)
        worst_angle = max(worst_angle, math.degrees(q.rotation_difference(m.to_quaternion()).angle))
        p = a[part].to_translation().lerp(b[part].to_translation(), u)
        worst_move = max(worst_move, (p - m.to_translation()).length)
    return worst_angle, worst_move


def thin(frames, clip):
    keep_times = {round(k[0], 5) for k in clip["keys"]}
    if clip.get("hit") is not None:
        keep_times.add(round(clip["hit"], 5))
    kept = [0]
    i = 0
    while i < len(frames) - 1:
        j = i + 1
        while j + 1 < len(frames) and round(frames[j][0], 5) not in keep_times:
            ok = True
            for k in range(i + 1, j + 1):
                u = (frames[k][0] - frames[i][0]) / (frames[j + 1][0] - frames[i][0])
                angle, move = blend_off(frames[i][1], frames[j + 1][1], frames[k][1], u)
                if angle > THIN_ANGLE or move > THIN_MOVE:
                    ok = False
                    break
            if not ok:
                break
            j += 1
        kept.append(j)
        i = j
    return [frames[k] for k in kept]


def report(frames, clip, name):
    """Checks the bake against the keys: how close the grip came, where the blade pointed."""
    by_time = {round(t, 5): world for t, _, world in frames}
    for key in clip["keys"]:
        t, p = key[0], key[1]
        world = by_time.get(round(t, 5))
        if world is None:
            continue
        hand = TO_BLENDER @ world["RightHand"]
        grip = hand.to_translation()
        blade = (hand.to_3x3() @ Vector((0, 0, -1))).normalized()
        miss = (grip - Vector(p["grip"])).length
        tip = grip + blade * 4.63
        lf = (TO_BLENDER @ world["LeftFoot"]).to_translation()
        rf = (TO_BLENDER @ world["RightFoot"]).to_translation()
        lw = (TO_BLENDER @ world["LeftHand"] @ GRIP_TO_WRIST)
        lmiss = (lw - Vector(p["lwrist"])).length
        fmiss = max((lf - Vector(p["lfoot"][:3])).length, (rf - Vector(p["rfoot"][:3])).length)
        flags = []
        if miss > 0.05:
            flags.append(f"GRIP OUT OF REACH by {miss:.2f}")
        if lmiss > 0.05:
            flags.append(f"LEFT HAND OUT OF REACH by {lmiss:.2f}")
        if fmiss > 0.05:
            flags.append(f"FOOT OUT OF REACH by {fmiss:.2f}")
        if tip.z < 0.05:
            flags.append(f"TIP IN THE GROUND ({tip.z:.2f})")
        print(f"AUTHOR   t={t:.3f} grip ({grip.x:+.2f},{grip.y:+.2f},{grip.z:+.2f}) "
              f"blade ({blade.x:+.2f},{blade.y:+.2f},{blade.z:+.2f}) tip z {tip.z:.2f} " + " ".join(flags))
    hit = clip.get("hit")
    if hit is not None:
        # The edge should lead the blade's motion on the hit.
        t0, t1 = hit - 1 / SAMPLE_RATE, hit + 1 / SAMPLE_RATE
        tips, edge = [], None
        for t, _, world in frames:
            if abs(t - round(t0, 5)) < 1e-4 or abs(t - round(t1, 5)) < 1e-4:
                hand = TO_BLENDER @ world["RightHand"]
                tips.append(hand @ Vector((0, 0, -4.63)))
            if abs(t - hit) < 1e-4:
                edge = ((TO_BLENDER @ world["RightHand"]).to_3x3() @ Vector((0, 1, 0))).normalized()
        if len(tips) == 2 and edge is not None:
            motion = (tips[1] - tips[0])
            speed = motion.length * SAMPLE_RATE / 2
            print(f"AUTHOR   hit at {hit}: tip speed {speed:.0f} studs/s, edge leads by {edge.dot(motion.normalized()):+.2f} (1 = square on)")


# --- writing the .rbxmx -----------------------------------------------------------------------

HIERARCHY = ("HumanoidRootPart", [
    ("LowerTorso", [
        ("UpperTorso", [
            ("Head", []),
            ("RightUpperArm", [("RightLowerArm", [("RightHand", [])])]),
            ("LeftUpperArm", [("LeftLowerArm", [("LeftHand", [])])]),
        ]),
        ("LeftUpperLeg", [("LeftLowerLeg", [("LeftFoot", [])])]),
        ("RightUpperLeg", [("RightLowerLeg", [("RightFoot", [])])]),
    ]),
])
UPPER_BODY = {"UpperTorso", "Head", "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand"}


class Refs:
    def __init__(self):
        self.n = 0

    def next(self):
        self.n += 1
        return f"RBX{self.n:08X}"


def cframe_xml(m, with_position):
    p = m.to_translation() if with_position else Vector((0, 0, 0))
    r = m.to_3x3().normalized()
    values = "".join(f"<R{i}{j}>{r[i][j]:.6f}</R{i}{j}>" for i in range(3) for j in range(3))
    return f'<CoordinateFrame name="CFrame"><X>{p.x:.4f}</X><Y>{p.y:.4f}</Y><Z>{p.z:.4f}</Z>{values}</CoordinateFrame>'


def pose_xml(node, transforms, depth, refs, upper_only):
    name, children = node
    weight = 1
    if name == "HumanoidRootPart" or (upper_only and name not in UPPER_BODY):
        weight = 0
    m = transforms.get(name, Matrix.Identity(4)) if weight else Matrix.Identity(4)
    inner = "".join(pose_xml(c, transforms, depth + 1, refs, upper_only) for c in children
                    if not (upper_only and c[0] in ("LeftUpperLeg", "RightUpperLeg")))
    pad = "\t" * depth
    return (
        f'{pad}<Item class="Pose" referent="{refs.next()}"><Properties>{cframe_xml(m, name == "LowerTorso")}'
        f'<token name="EasingDirection">0</token><token name="EasingStyle">0</token>'
        f'<string name="Name">{name}</string><float name="Weight">{weight}</float></Properties>\n'
        f'{inner}{pad}</Item>\n'
    )


def write_rbxmx(path, name, frames, clip):
    refs = Refs()
    upper_only = clip.get("upper_body_only", False)
    body = ""
    for t, transforms, _ in frames:
        body += (
            f'\t\t<Item class="Keyframe" referent="{refs.next()}"><Properties><string name="Name">Keyframe</string>'
            f'<float name="Time">{t:.5g}</float></Properties>\n'
            f'{pose_xml(HIERARCHY, transforms, 3, refs, upper_only)}\t\t</Item>\n'
        )
    if clip.get("hit") is not None:
        body += (
            f'\t\t<Item class="Keyframe" referent="{refs.next()}"><Properties><string name="Name">Hit</string>'
            f'<float name="Time">{clip["hit"]}</float></Properties>\n'
            f'\t\t\t<Item class="KeyframeMarker" referent="{refs.next()}"><Properties><string name="Name">Hit</string>'
            f'<string name="Value"></string></Properties></Item>\n\t\t</Item>\n'
        )
    loop = "true" if clip.get("loop") else "false"
    xml = (
        '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
        'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
        f'\t<Item class="KeyframeSequence" referent="{refs.next()}"><Properties><bool name="Loop">{loop}</bool>'
        f'<string name="Name">{name}</string><token name="Priority">{clip.get("priority", 2)}</token></Properties>\n'
        f'{body}\t</Item>\n</roblox>\n'
    )
    Path(path).write_text(xml)


# --- main -----------------------------------------------------------------------------------

def load_clips():
    clips = {}
    for path in sorted(Path(__file__).parent.glob("*_clips.py")):
        spec = importlib.util.spec_from_file_location(path.stem, path)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        clips.update(module.CLIPS)
    return clips


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("clips", nargs="+")
    parser.add_argument("--out", required=True, help="where the .rbxmx files go")
    parser.add_argument("--blend", required=True, help="where the .blend files go")
    args = parser.parse_args(argv)
    clips = load_clips()
    for name in args.clips:
        if name not in clips:
            print(f"AUTHOR no clip named {name} (have: {', '.join(clips)})")
            continue
        clip = clips[name]
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.context.scene.render.fps = FPS
        arm, ctl, rest_bone, part_rest = build_rig()
        key_clip(arm, ctl, clip)
        frames = bake(arm, rest_bone, part_rest, clip, name)
        report(frames, clip, name)
        out = Path(args.out) / f"{name}.rbxmx"
        thinned = thin(frames, clip)
        print(f"AUTHOR {name}: {len(thinned)} keyframes kept of {len(frames)} samples")
        write_rbxmx(out, name, thinned, clip)
        Path(args.blend).mkdir(parents=True, exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=str(Path(args.blend) / f"{name}.blend"))
        print(f"AUTHOR wrote {out}")


if __name__ == "__main__":
    main()
