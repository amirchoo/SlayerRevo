"""Plays a weapon's whole combo the way the game chains it, for watching in Blender and as videos.
Run it through tools/blender/combo.sh:

    sh tools/blender/combo.sh Sword

Each swing starts when the one before it can chain (its Cooldown), blending in over CHAIN_FADE while
the one before fades out, as ComboWeaponClient does; the first blends in from the idle over
SWING_FADE_IN, and the last fades back into the idle over END_FADE before its end. The blend is
Roblox's: each clip's weight ramps linearly and the poses are mixed by weight.

It writes build/anim_author/<Name>Combo_show.blend (the body and sword keyed on every frame, so it plays
at full speed even on a slow computer, with a marker on each swing and hit and the blade tip's path)
and build/anim_video/<Name>Combo/{behind,side}_60fps.mp4 and *_quarter_speed.mp4.
"""
import argparse
import subprocess
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).parent))
import author_anim as author  # noqa: E402
import preview_anim as rig  # noqa: E402
import weapon_model  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]

FPS = 60
SWING_FADE_IN = 0.08  # ComboWeaponClient
CHAIN_FADE = 0.15
END_FADE = 0.25
IDLE_BEFORE = 0.4  # seconds of idle before the first swing and after the last
IDLE_AFTER = 0.6


def ramp(t, start, length):
    return 1.0 if length <= 0 else min(max((t - start) / length, 0.0), 1.0)


def mix(entries):
    """Weighted blend of joint transforms [(weight, matrix)], as Roblox mixes playing tracks."""
    total, q, p = 0.0, None, None
    for weight, m in entries:
        if weight <= 1e-6:
            continue
        total += weight
        mq, mp = m.to_quaternion(), m.to_translation()
        if q is None:
            q, p = mq, mp
        else:
            if q.dot(mq) < 0:
                mq = -mq
            u = weight / total
            q, p = q.slerp(mq, u), p.lerp(mp, u)
    if q is None:
        return Matrix.Identity(4)
    return Matrix.Translation(p) @ q.to_matrix().to_4x4()


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("name")
    parser.add_argument("--clips", required=True, help="comma-separated .rbxmx paths, in combo order")
    parser.add_argument("--cooldowns", required=True, help="comma-separated: seconds until each swing can chain")
    parser.add_argument("--blend", required=True)
    parser.add_argument("--video", required=True)
    parser.add_argument("--blade", type=float, default=5.2)
    parser.add_argument("--grip", type=float, default=0.11)
    parser.add_argument("--no-video", action="store_true")
    parser.add_argument("--model", help="the weapon whose real model to show (weapon_model.WEAPONS), instead of boxes")
    args = parser.parse_args(argv)

    clips = [rig.read_clip(p) for p in args.clips.split(",")]
    cooldowns = [float(c) for c in args.cooldowns.split(",")]
    # Each swing: when it starts, how it blends in, and when it starts fading out.
    plan, t = [], IDLE_BEFORE
    for i, (name, _loop, tracks, hit, end) in enumerate(clips):
        last = i == len(clips) - 1
        fade_in = SWING_FADE_IN if i == 0 else CHAIN_FADE
        if last:
            stop, fade_out = t + end - END_FADE, END_FADE
        else:
            stop, fade_out = t + cooldowns[i], CHAIN_FADE
        plan.append({"name": name, "tracks": tracks, "start": t, "fade_in": fade_in, "stop": stop,
                     "fade_out": fade_out, "hit": hit, "end": end})
        if not last:
            t += cooldowns[i]
    total = plan[-1]["stop"] + plan[-1]["fade_out"] + IDLE_AFTER
    # The idle under it all: the pose every swing starts and ends on (the first swing's first frame).
    idle_tracks = plan[0]["tracks"]

    def world_at(time):
        world = {"HumanoidRootPart": rig.translation((0, rig.ROOT_HEIGHT, 0))}
        for part1, part0, c0, c1 in rig.JOINTS:
            entries = [(1.0, rig.sample(idle_tracks[part1], 0) if part1 in idle_tracks else Matrix.Identity(4))]
            for swing in plan:
                w = ramp(time, swing["start"], swing["fade_in"]) * (1 - ramp(time, swing["stop"], swing["fade_out"]))
                if w > 0 and part1 in swing["tracks"]:
                    # A playing Action track at full weight hides the idle (higher priority).
                    entries[0] = (entries[0][0] * (1 - w), entries[0][1])
                    entries.append((w, rig.sample(swing["tracks"][part1], time - swing["start"])))
            transform = mix(entries)
            world[part1] = world[part0] @ rig.translation(c0) @ transform @ rig.translation(c1).inverted()
        return world

    rig.clear_scene()
    parts, sword, ahead_len = rig.build(args.blade, args.grip)
    scene = bpy.context.scene
    model = None
    if args.model:
        # The real weapon instead of the box sword (Texture color mode shows its texture).
        for obj, _, _ in sword.values():
            bpy.data.objects.remove(obj)
        sword = {}
        model, ahead_len = weapon_model.load(ROOT, args.model)
        scene.display.shading.color_type = "TEXTURE"
    scene.render.fps = FPS
    frames = int(round(total * FPS))
    scene.frame_start, scene.frame_end = 0, frames
    tip_points = []
    last_q = {}

    def key(obj, frame):
        """Keys obj's location, quaternion turn (on the same side as last frame's, so the blend
        between frames takes the short way round) and scale."""
        obj.rotation_mode = "QUATERNION"
        q = obj.matrix_world.to_quaternion()
        prev = last_q.get(obj.name)
        if prev is not None and prev.dot(q) < 0:
            q.negate()
        loc, _, scale = obj.matrix_world.decompose()
        obj.location, obj.rotation_quaternion, obj.scale = loc, q, scale
        last_q[obj.name] = q
        obj.keyframe_insert("location", frame=frame)
        obj.keyframe_insert("rotation_quaternion", frame=frame)
        obj.keyframe_insert("scale", frame=frame)

    for frame in range(frames + 1):
        world = world_at(frame / FPS)
        for part, obj in parts.items():
            rig.place(obj, world[part], rig.PARTS[part])
            key(obj, frame)
        for obj, size, offset in sword.values():
            rig.place(obj, world["RightHand"] @ rig.translation(offset), size)
            key(obj, frame)
        if model is not None:
            model.matrix_world = rig.TO_BLENDER @ world["RightHand"]
            key(model, frame)
        tip_points.append(rig.TO_BLENDER @ world["RightHand"] @ Vector((0, 0, -ahead_len)))
    rig.draw_path(tip_points, "BladeTipPath")
    for obj in bpy.data.objects:  # keys on every frame: plain linear between them
        if obj.animation_data and obj.animation_data.action:
            for fc in author.action_fcurves(obj.animation_data.action):
                for kp in fc.keyframe_points:
                    kp.interpolation = "LINEAR"

    scene.timeline_markers.clear()
    for i, swing in enumerate(plan):
        scene.timeline_markers.new(f"swing {i + 1}", frame=round(swing["start"] * FPS))
        if swing["hit"] is not None:
            scene.timeline_markers.new(f"HIT {i + 1}", frame=round((swing["start"] + swing["hit"]) * FPS))
    scene.sync_mode = "FRAME_DROP"
    location, target = rig.VIEWS["behind"]
    look = Vector(target) - Vector(location)
    for screen in bpy.data.screens:
        for area in screen.areas:
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.type = "SOLID"
                    space.shading.color_type = "TEXTURE" if model is not None else "OBJECT"
                    space.shading.show_shadows = False
                    space.shading.show_object_outline = False
                    space.region_3d.view_perspective = "PERSP"
                    space.region_3d.view_location = Vector(target)
                    space.region_3d.view_rotation = look.to_track_quat("-Z", "Y")
                    space.region_3d.view_distance = look.length
    blend = Path(args.blend) / f"{args.name}Combo_show.blend"
    blend.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend))
    print(f"COMBO wrote {blend} ({total:.2f} s: " + ", ".join(
        f"{s['name']} at {s['start']:.2f}" for s in plan) + ")")

    if args.no_video:
        return
    out = Path(args.video) / f"{args.name}Combo"
    out.mkdir(parents=True, exist_ok=True)
    scene.render.resolution_x, scene.render.resolution_y = 720, 600
    scene.render.image_settings.file_format = "PNG"
    for view in ("behind", "side"):
        scene.camera = rig.look_from(view, *rig.VIEWS[view])
        for frame in range(frames + 1):
            scene.frame_set(frame)
            scene.render.filepath = str(out / f"{view}_{frame:04d}.png")
            bpy.ops.render.render(write_still=True)
        for speed, label in ((FPS, "60fps"), (FPS / 4, "quarter_speed")):
            subprocess.run(["ffmpeg", "-v", "error", "-y", "-framerate", str(speed), "-i", str(out / f"{view}_%04d.png"),
                            "-c:v", "libx264", "-pix_fmt", "yuv420p", "-r", str(FPS), str(out / f"{view}_{label}.mp4")], check=True)
        for png in out.glob(f"{view}_*.png"):
            png.unlink()
        print(f"COMBO video {out / f'{view}_60fps.mp4'}")


if __name__ == "__main__":
    main()
