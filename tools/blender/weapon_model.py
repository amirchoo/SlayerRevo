"""Loads a weapon's real model (the .glb Studio imported) into Blender, fitted into the hand the way
the game fits it, so previews show the actual weapon instead of boxes.

The game's chain (src/server/WeaponModels.luau, src/shared/HandGrip.luau, WeaponService):
  hand -> RightGripAttachment (0, -0.15, 0), turned -90 deg about X (Workspace.Rig)
       -> the tool's Grip inverted (Sword: CFrame.new(0, 0, -0.3) * CFrame.Angles(pi/2, 0, 0))
       -> the grip part: blade along its +Z, the model's thin side (its Z) along its X
  and the model is scaled so its Y size is ModelFit.Length, held ModelFit.GripFrom of the way up
  from the handle end. Studio's Import 3D turns a .glb 180 deg about Y, which is kept here too.

The mesh comes out in the RightHand part's space (Roblox axes), so placing it is just
  obj.matrix_world = TO_BLENDER @ <the hand's world CFrame>
"""
import math

import bpy
from mathutils import Matrix, Vector

# Roblox CFrame.Angles(a, 0, 0) as a 4x4.
def _rot_x(a):
    return Matrix.Rotation(a, 4, "X")


# Per weapon: the model file and the tool's Grip (from WeaponService), plus CombatConfig ModelFit.
WEAPONS = {
    "Sword": {
        "model": "assets/source/weapons/ShortSword.glb",
        "grip": Matrix.Translation((0, 0, -0.3)) @ _rot_x(math.pi / 2),
        "length": 5.2,
        "grip_from": 0.11,
    },
}
GRIP_ATTACHMENT = Matrix.Translation((0, -0.149954513, 0)) @ _rot_x(-math.pi / 2)  # Workspace.Rig.RightHand


def load(root, weapon="Sword", name="WeaponModel"):
    """Imports the weapon's model and returns one mesh object whose vertices are in the hand's
    space (Roblox axes). Its materials (and texture) come with it."""
    spec = WEAPONS[weapon]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(root / spec["model"]))
    imported = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in imported if o.type == "MESH"]

    # Every vertex in glTF's own axes (Y up): Blender's importer turned (x, y, z) into (x, -z, y).
    points = []
    for obj in meshes:
        for v in obj.data.vertices:
            b = obj.matrix_world @ v.co
            points.append(Vector((b.x, b.z, -b.y)))
    # Studio's Import 3D turns it 180 degrees about Y; then scale its Y size to the weapon's length.
    turned = [Vector((-p.x, p.y, -p.z)) for p in points]
    lo = Vector((min(p.x for p in turned), min(p.y for p in turned), min(p.z for p in turned)))
    hi = Vector((max(p.x for p in turned), max(p.y for p in turned), max(p.z for p in turned)))
    scale = spec["length"] / (hi.y - lo.y)
    center = (lo + hi) / 2
    length = spec["length"]
    grip_point_y = -length / 2 + length * spec["grip_from"]  # handle end at -Y
    # Model space -> grip part space: x = model Z (thin side), y = model X, z = model Y (along the blade).
    hand_from_grip = GRIP_ATTACHMENT @ spec["grip"].inverted()

    def to_hand(b):
        g = Vector((b.x, b.z, -b.y))
        r = (Vector((-g.x, g.y, -g.z)) - center) * scale
        d = Vector((r.x, r.y - grip_point_y, r.z))
        return hand_from_grip @ Vector((d.z, d.x, d.y))

    for obj in meshes:
        world = obj.matrix_world.copy()
        mesh = obj.data
        for v in mesh.vertices:
            v.co = to_hand(world @ v.co)
        obj.parent = None
        obj.matrix_world = Matrix.Identity(4)
    if len(meshes) > 1:
        for o in bpy.data.objects:
            o.select_set(False)
        for o in meshes:
            o.select_set(True)
        bpy.context.view_layer.objects.active = meshes[0]
        bpy.ops.object.join()
    model = meshes[0]
    model.name = name
    for o in imported:
        if o is not model and o.name in bpy.data.objects:
            bpy.data.objects.remove(o)
    return model, length * (1 - spec["grip_from"]) + 0.3  # the tip's distance from the hand along -Z
