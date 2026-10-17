"""Dresses up an authored clip's rig (build/anim_author/<Clip>.blend, saved by author_anim.py) so it
can be watched and scrubbed in Blender's window. Run it through tools/blender/show.sh:

    sh tools/blender/show.sh SwordSwing1

It adds the blocky R15 body and the sword (the same boxes as the preview renders) on the rig's
bones, the ground, the path the blade's tip takes (orange), timeline markers on every key and on
the hit, names on the controls, and a viewport looking from behind like the lock-on camera.
Saved as build/anim_author/<Clip>_show.blend; the clip and its .rbxmx aren't touched.
"""
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).parent))
import author_anim as author  # noqa: E402
import preview_anim as rig  # noqa: E402

BLADE_LENGTH = 5.2  # sword Length (CombatConfig ModelFit), as preview.sh uses
GRIP_FROM = 0.11


def bone_parent(obj, arm, bone, matrix_world):
    obj.parent = arm
    obj.parent_type = "BONE"
    obj.parent_bone = bone
    bpy.context.view_layer.update()
    obj.matrix_world = matrix_world


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    name, out = argv[0], Path(argv[1])
    scene = bpy.context.scene
    arm = bpy.data.objects["R15"]
    clip = author.load_clips()[name]

    # Lay the body and the sword on the bones at rest, then let the animation move them.
    arm.data.pose_position = "REST"
    bpy.context.view_layer.update()
    parts, _ = author.rest_world()
    part_rest = {p: rig.TO_BLENDER @ m for p, m in parts.items()}
    cubes, sword, ahead_len = rig.build(BLADE_LENGTH, GRIP_FROM)
    for part, obj in cubes.items():
        size = rig.PARTS[part]
        bone_parent(obj, arm, part, part_rest[part] @ Matrix.Diagonal((size[0] / 2, size[1] / 2, size[2] / 2, 1)))
    hand = part_rest["RightHand"]
    for obj, size, offset in sword.values():
        bone_parent(obj, arm, "RightHand", hand @ rig.translation(offset) @ Matrix.Diagonal((size[0] / 2, size[1] / 2, size[2] / 2, 1)))
    tip = bpy.data.objects.new("TipPoint", None)
    scene.collection.objects.link(tip)
    bone_parent(tip, arm, "RightHand", hand @ Matrix.Translation((0, 0, -ahead_len)))
    arm.data.pose_position = "POSE"
    arm.show_in_front = False

    # Bake the IK into plain keys on every frame and drop the constraints: solving four IK limbs
    # live (500 iterations each) is too slow to play at 60 fps on a slow computer.
    for obj in bpy.data.objects:
        obj.select_set(False)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.object.mode_set(mode="POSE")
    bpy.ops.pose.select_all(action="SELECT")
    bpy.ops.nla.bake(frame_start=scene.frame_start, frame_end=scene.frame_end, only_selected=True,
                     visual_keying=True, clear_constraints=True, use_current_action=True, bake_types={"POSE"})
    bpy.ops.object.mode_set(mode="OBJECT")
    arm.hide_set(True)  # the body shows the pose; the bones only clutter it

    # The blade tip's path over the whole clip.
    points = []
    for frame in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(frame)
        points.append(tip.matrix_world.translation.copy())
    rig.draw_path(points, "BladeTipPath")
    scene.frame_set(0)

    # Markers: every key of the clip file, and the hit.
    scene.timeline_markers.clear()
    for index, key in enumerate(clip["keys"]):
        scene.timeline_markers.new(f"key {index + 1}", frame=round(key[0] * author.FPS))
    if clip.get("hit") is not None:
        scene.timeline_markers.new("HIT", frame=round(clip["hit"] * author.FPS))

    # The controls the clip file keys: names on, drawn over the body.
    for obj in bpy.data.objects:
        if obj.type == "EMPTY" and obj.parent is None:
            obj.show_name = True
            obj.show_in_front = True
    for obj in bpy.data.objects:
        obj.select_set(False)
    sword_ctl = bpy.data.objects["SwordCtl"]
    sword_ctl.select_set(True)
    bpy.context.view_layer.objects.active = sword_ctl  # the timeline shows its keys

    scene.sync_mode = "FRAME_DROP"  # plays at real speed
    scene.render.fps = author.FPS
    location, target = rig.VIEWS["behind"]
    look = Vector(target) - Vector(location)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type != "VIEW_3D":
                continue
            for space in area.spaces:
                if space.type != "VIEW_3D":
                    continue
                space.shading.type = "SOLID"
                space.shading.color_type = "OBJECT"
                space.shading.show_shadows = False  # cheap to draw, so playback keeps up
                space.overlay.show_relationship_lines = False
                space.shading.show_object_outline = False
                space.shading.show_cavity = False
                space.region_3d.view_perspective = "PERSP"
                space.region_3d.view_location = Vector(target)
                space.region_3d.view_rotation = look.to_track_quat("-Z", "Y")
                space.region_3d.view_distance = look.length
    bpy.ops.wm.save_as_mainfile(filepath=str(out))
    print(f"SHOW wrote {out}")


if __name__ == "__main__":
    main()
