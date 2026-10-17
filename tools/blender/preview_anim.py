"""Renders preview frames of R15 animation clips (.rbxmx KeyframeSequences) in Blender, so an
animation can be checked by eye without Studio. Run it through tools/blender/preview.sh:

    sh tools/blender/preview.sh assets/animations/SwordSwing1.rbxmx [more clips] [--views behind,side]

It builds our blocky R15 rig (joint offsets and part sizes read from Workspace.Rig in Studio,
2026-10-18) holding a sword, plays each clip on it the way Roblox does (each pose eased by its
EasingStyle/Direction toward the next keyframe that has that pose), and renders every sample
from a few cameras. The blade tip's path is drawn as an orange line (the swing's arc), and the
frame on the Hit marker is stamped HIT. preview.sh tiles the frames into sheets and a video.

Coordinates: Roblox is X right, Y up, Z back (the character faces -Z). Blender is Z up; the
character faces +Y there.
"""
import argparse
import math
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

import bpy
from mathutils import Matrix, Quaternion, Vector

# --- the rig (Workspace.Rig, blocky R15) -------------------------------------------------

PARTS = {  # name: size (Roblox X, Y, Z)
    "HumanoidRootPart": (2, 2, 1),
    "LowerTorso": (2, 0.4, 1), "UpperTorso": (2, 1.6, 1), "Head": (1.2, 1.2, 1.2),
    "RightUpperArm": (1, 1.169, 1), "RightLowerArm": (1, 1.052, 1), "RightHand": (1, 0.3, 1),
    "LeftUpperArm": (1, 1.169, 1), "LeftLowerArm": (1, 1.052, 1), "LeftHand": (1, 0.3, 1),
    "RightUpperLeg": (1, 1.217, 1), "RightLowerLeg": (1, 1.193, 1), "RightFoot": (1, 0.3, 1),
    "LeftUpperLeg": (1, 1.217, 1), "LeftLowerLeg": (1, 1.193, 1), "LeftFoot": (1, 0.3, 1),
}
# (part1 = the pose's name, part0, C0 position, C1 position), parents before children.
# All the joint attachments are unrotated. Part1 = Part0 * C0 * Transform * C1:Inverse().
JOINTS = [
    ("LowerTorso", "HumanoidRootPart", (0, -1, 0), (0, -0.2, 0)),
    ("UpperTorso", "LowerTorso", (0, 0.2, 0), (0, -0.8, 0)),
    ("Head", "UpperTorso", (0, 0.8, 0), (0, -0.586, 0)),
    ("RightUpperArm", "UpperTorso", (1, 0.563, 0), (-0.5, 0.3943, 0)),
    ("RightLowerArm", "RightUpperArm", (0, -0.3342, 0), (0, 0.2586, 0)),
    ("RightHand", "RightLowerArm", (0, -0.5009, 0), (0, 0.125, 0)),
    ("LeftUpperArm", "UpperTorso", (-1, 0.563, 0), (0.5, 0.3943, 0)),
    ("LeftLowerArm", "LeftUpperArm", (0, -0.3341, 0), (0, 0.2587, 0)),
    ("LeftHand", "LeftLowerArm", (0, -0.5009, 0), (0, 0.125, 0)),
    ("RightUpperLeg", "LowerTorso", (0.5, -0.2, 0), (0, 0.4208, 0)),
    ("RightLowerLeg", "RightUpperLeg", (0, -0.4009, 0), (0, 0.3792, 0)),
    ("RightFoot", "RightLowerLeg", (0, -0.5472, 0), (0, 0.1019, 0)),
    ("LeftUpperLeg", "LowerTorso", (-0.5, -0.2, 0), (0, 0.4208, 0)),
    ("LeftLowerLeg", "LeftUpperLeg", (0, -0.4011, 0), (0, 0.379, 0)),
    ("LeftFoot", "LeftLowerLeg", (0, -0.5472, 0), (0, 0.1019, 0)),
]
ROOT_HEIGHT = 3.0  # HipHeight 2 + half the root part: the feet rest on the ground at 0

COLORS = {
    "UpperTorso": (0.85, 0.85, 0.9), "LowerTorso": (0.25, 0.25, 0.3), "Head": (0.95, 0.8, 0.3),
    "RightUpperArm": (0.75, 0.3, 0.25), "RightLowerArm": (0.85, 0.4, 0.3), "RightHand": (0.95, 0.8, 0.3),
    "LeftUpperArm": (0.25, 0.4, 0.75), "LeftLowerArm": (0.3, 0.5, 0.85), "LeftHand": (0.95, 0.8, 0.3),
    "RightUpperLeg": (0.6, 0.25, 0.2), "RightLowerLeg": (0.7, 0.3, 0.25), "RightFoot": (0.2, 0.2, 0.2),
    "LeftUpperLeg": (0.2, 0.3, 0.6), "LeftLowerLeg": (0.25, 0.35, 0.7), "LeftFoot": (0.2, 0.2, 0.2),
}

# Roblox space to Blender space: (x, y, z) -> (x, -z, y).
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def translation(v):
    return Matrix.Translation(Vector(v))


# --- reading a clip ---------------------------------------------------------------------

def read_clip(path):
    """Returns (name, loop, {pose name: [(time, matrix, style, direction, weight)]}, hit time, end)."""
    root = ET.parse(path).getroot()
    seq = root.find("Item")
    props = seq.find("Properties")
    name = props.find("string[@name='Name']").text
    loop = props.find("bool[@name='Loop']").text == "true"
    tracks, hit, end = {}, None, 0.0
    for kf in seq.findall("Item[@class='Keyframe']"):
        kprops = kf.find("Properties")
        time = float(kprops.find("float[@name='Time']").text)
        if kf.find("Item[@class='KeyframeMarker']") is not None:
            hit = time
            continue
        end = max(end, time)
        for pose in kf.iter("Item"):
            if pose.get("class") != "Pose":
                continue
            pp = pose.find("Properties")
            cf = pp.find("CoordinateFrame")
            g = {c.tag: float(c.text) for c in cf}
            m = Matrix((
                (g["R00"], g["R01"], g["R02"], g["X"]),
                (g["R10"], g["R11"], g["R12"], g["Y"]),
                (g["R20"], g["R21"], g["R22"], g["Z"]),
                (0, 0, 0, 1),
            ))
            tracks.setdefault(pp.find("string[@name='Name']").text, []).append((
                time, m,
                int(pp.find("token[@name='EasingStyle']").text),
                int(pp.find("token[@name='EasingDirection']").text),
                float(pp.find("float[@name='Weight']").text),
            ))
    for keys in tracks.values():
        keys.sort(key=lambda k: k[0])
    return name, loop, tracks, hit, end


def eased(style, direction, u):
    """Roblox PoseEasingStyle (Linear 0, Constant 1, Elastic 2, Cubic 3, Bounce 4, CubicV2 5)
    and direction (In 0, Out 1, InOut 2). The old Cubic's In and Out are swapped."""
    if style == 0:
        return u
    if style == 1:
        return 0.0
    if style == 3 and direction in (0, 1):
        direction = 1 - direction
    if direction == 0:
        return u ** 3
    if direction == 1:
        return 1 - (1 - u) ** 3
    return 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2


def sample(keys, t):
    """The pose's Transform at t (identity for weight-0 placeholder poses)."""
    keys = [k for k in keys if k[4] > 0]
    if not keys:
        return Matrix.Identity(4)
    if t <= keys[0][0]:
        return keys[0][1]
    for a, b in zip(keys, keys[1:]):
        if t <= b[0]:
            u = eased(a[2], a[3], (t - a[0]) / (b[0] - a[0]) if b[0] > a[0] else 1)
            qa, qb = a[1].to_quaternion(), b[1].to_quaternion()
            q = qa.slerp(qb, u)
            p = a[1].to_translation().lerp(b[1].to_translation(), u)
            return Matrix.Translation(p) @ q.to_matrix().to_4x4()
    return keys[-1][1]


def solve(tracks, t):
    """World CFrames (Roblox space) of every part at t."""
    world = {"HumanoidRootPart": translation((0, ROOT_HEIGHT, 0))}
    for part1, part0, c0, c1 in JOINTS:
        transform = sample(tracks[part1], t) if part1 in tracks else Matrix.Identity(4)
        world[part1] = world[part0] @ translation(c0) @ transform @ translation(c1).inverted()
    return world


# --- the scene ----------------------------------------------------------------------------

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def unit_cube(name, color):
    mesh = bpy.data.meshes.new(name)
    v = [(x, y, z) for x in (-1, 1) for y in (-1, 1) for z in (-1, 1)]
    f = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(v, [], f)
    obj = bpy.data.objects.new(name, mesh)
    obj.color = (*color, 1)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def place(obj, roblox_cframe, size):
    obj.matrix_world = TO_BLENDER @ roblox_cframe @ Matrix.Diagonal((size[0] / 2, size[1] / 2, size[2] / 2, 1))


def look_from(name, location, target):
    cam_data = bpy.data.cameras.new(name)
    cam_data.lens = 35
    cam = bpy.data.objects.new(name, cam_data)
    cam.location = Vector(location)
    cam.rotation_euler = (Vector(target) - Vector(location)).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.collection.objects.link(cam)
    return cam


# Blender space (Z up, the character faces +Y). "behind" is the lock-on camera's angle: behind,
# a little right and above, looking past the player.
VIEWS = {
    "behind": ((3.5, -9.5, 6.0), (0, 2.0, 2.4)),
    "side": ((11.0, 1.0, 3.2), (0, 1.0, 2.4)),
    "front": ((1.5, 10.5, 4.0), (0, 0, 2.4)),
    "top": ((0.01, 1.0, 13.0), (0, 1.0, 0)),
}


def build(blade_length, grip_from):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    shading = scene.display.shading
    shading.light = "STUDIO"
    shading.color_type = "OBJECT"
    shading.show_shadows = True
    shading.show_cavity = False
    world = bpy.data.worlds.new("World")
    world.color = (0.55, 0.58, 0.62)
    scene.world = world

    ground = unit_cube("Ground", (0.42, 0.4, 0.36))
    ground.matrix_world = Matrix.Translation((0, 0, -0.05)) @ Matrix.Diagonal((12, 12, 0.05, 1))
    # A line straight ahead, so turns of the body read against it.
    ahead = unit_cube("Ahead", (0.3, 0.28, 0.25))
    ahead.matrix_world = Matrix.Translation((0, 6, 0.0)) @ Matrix.Diagonal((0.05, 6, 0.02, 1))

    parts = {name: unit_cube(name, COLORS[name]) for name in PARTS if name != "HumanoidRootPart"}
    # The sword, in the hand's space: the blade runs along -Z, the hand holding it grip_from of
    # the way up from the pommel (as WeaponModels fits it).
    behind = blade_length * grip_from
    ahead_len = blade_length - behind
    guard_at = -0.35
    sword = {
        "Handle": (unit_cube("Handle", (0.15, 0.1, 0.08)), (0.18, 0.18, behind - guard_at), (0, 0, (behind + guard_at) / 2)),
        "Guard": (unit_cube("Guard", (0.6, 0.5, 0.1)), (0.2, 0.6, 0.08), (0, 0, guard_at)),
        "Blade": (unit_cube("Blade", (0.85, 0.87, 0.92)), (0.06, 0.28, ahead_len + guard_at), (0, 0, (guard_at - ahead_len) / 2)),
        "Tip": (unit_cube("Tip", (0.9, 0.15, 0.1)), (0.14, 0.34, 0.3), (0, 0, -ahead_len + 0.15)),
    }
    return parts, sword, ahead_len


def tip_path(tracks, end, ahead_len, step=1 / 120):
    points, t = [], 0.0
    while t <= end + 1e-6:
        hand = solve(tracks, t)["RightHand"]
        points.append(TO_BLENDER @ hand @ Vector((0, 0, -ahead_len)))
        t += step
    return points


def draw_path(points, name="Path"):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = 0.035
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for p, co in zip(spline.points, points):
        p.co = (co.x, co.y, co.z, 1)
    obj = bpy.data.objects.new(name, curve)
    obj.color = (1.0, 0.45, 0.05, 1)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def render_clip(path, out_dir, fps, views, resolution, blade_length, grip_from):
    name, loop, tracks, hit, end = read_clip(path)
    clear_scene()
    parts, sword, ahead_len = build(blade_length, grip_from)
    path_obj = draw_path(tip_path(tracks, end, ahead_len))
    scene = bpy.context.scene
    scene.render.resolution_x, scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.use_stamp = True
    for flag in ("date", "time", "render_time", "frame", "frame_range", "memory", "hostname", "camera",
                 "lens", "scene", "marker", "filename", "sequencer_strip", "note"):
        setattr(scene.render, f"use_stamp_{flag}", flag == "note")
    scene.render.stamp_font_size = 14
    scene.render.stamp_background = (0, 0, 0, 0.6)
    cams = {v: look_from(v, *VIEWS[v]) for v in views}

    clip_dir = Path(out_dir) / name
    clip_dir.mkdir(parents=True, exist_ok=True)
    times = [i / fps for i in range(int(round(end * fps)) + 1)]
    if hit is not None and all(abs(t - hit) > 1e-4 for t in times):
        times = sorted(times + [hit])
    for index, t in enumerate(times):
        world = solve(tracks, t)
        for part, obj in parts.items():
            place(obj, world[part], PARTS[part])
        for obj, size, offset in sword.values():
            place(obj, world["RightHand"] @ translation(offset), size)
        label = f"{name}  t={t:.3f}s"
        if hit is not None and abs(t - hit) < 1e-4:
            label += "  HIT"
        scene.render.stamp_note_text = label
        for view, cam in cams.items():
            scene.camera = cam
            scene.render.filepath = str(clip_dir / f"{view}_{index:03d}.png")
            bpy.ops.render.render(write_still=True)
    print(f"PREVIEW {name}: {len(times)} frames x {len(views)} views, {end:.2f} s, hit {hit}, loop {loop} -> {clip_dir}")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("clips", nargs="+")
    parser.add_argument("--out", required=True)
    parser.add_argument("--fps", type=float, default=30)
    parser.add_argument("--views", default="behind,side,front")
    parser.add_argument("--res", default="360x300")
    parser.add_argument("--blade", type=float, default=5.2, help="sword Length (CombatConfig ModelFit)")
    parser.add_argument("--grip", type=float, default=0.11, help="sword GripFrom (CombatConfig ModelFit)")
    args = parser.parse_args(argv)
    res = tuple(int(v) for v in args.res.split("x"))
    for clip in args.clips:
        render_clip(clip, args.out, args.fps, args.views.split(","), res, args.blade, args.grip)


if __name__ == "__main__":
    main()
