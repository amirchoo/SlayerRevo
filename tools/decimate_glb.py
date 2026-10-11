"""Joins a GLB's meshes and decimates them to a triangle budget, with headless Blender.

    /Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \\
        --python tools/decimate_glb.py -- SOURCE.glb OUT.glb TRIANGLES

Studio's Import 3D takes at most 20,000 triangles per mesh, and tools/weapon_glb.py merges a
model into one mesh, so run this first on heavier models (then weapon_glb.py on OUT.glb).
"""
import bpy, sys
src, out, target = sys.argv[-3], sys.argv[-2], int(sys.argv[-1])
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)
meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
obj = bpy.context.view_layer.objects.active
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
def tris(o):
    return sum(len(p.vertices) - 2 for p in o.data.polygons)
before = tris(obj)
mod = obj.modifiers.new("dec", 'DECIMATE')
mod.ratio = min(1.0, target / before)
bpy.ops.object.modifier_apply(modifier="dec")
print(f"DECIMATE {before} -> {tris(obj)}")
bpy.ops.export_scene.gltf(filepath=out, export_format='GLB', use_selection=False)
