"""Turns a model built only from boxes (GLB) into a Roblox model of Parts (.rbxmx).

    python3 -I tools/box_glb.py SOURCE.glb OUT.rbxmx [--turn-y DEGREES] [--turn-x DEGREES] [--solid] [--info]

For blocky, color-only models (the Cow, Chicken, their meat, the Knight Statue): every mesh
in them is one box (upright or turned any way), so each becomes a Part of the same size,
place, turn and color, with no Import 3D step, no
uploaded meshes, and exact colors. Group nodes (e.g. a leg made of shin, foot and toe) become
Models of the same name, which AnimalService rigs as limbs.

--turn-y / --turn-x (multiples of 90, applied Y then X) turn the model: Roblox models face -Z,
so a model facing +Z (head at +Z) needs --turn-y 180. 1 unit = 1 stud; the game scales it.
--solid makes the Parts collide (scenery like the statue); otherwise nothing bumps into them
(animals are moved by their own invisible root; loot floats).
Fails if any mesh isn't a box (use tools/weapon_glb.py and Import 3D for those).
"""
import json
import math
import struct
import sys
from pathlib import Path
from xml.sax.saxutils import escape

COMPONENT_SIZES = {5120: 1, 5121: 1, 5122: 2, 5123: 2, 5125: 4, 5126: 4}
COMPONENT_FORMATS = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
TYPE_COUNTS = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
SMOOTH_PLASTIC = 272


def load_glb(path):
    data = Path(path).read_bytes()
    json_length = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20 : 20 + json_length])
    offset = 20 + json_length
    binary = b""
    if offset < len(data):
        bin_length = struct.unpack_from("<I", data, offset)[0]
        binary = data[offset + 8 : offset + 8 + bin_length]
    return gltf, binary


def read_accessor(gltf, binary, index):
    accessor = gltf["accessors"][index]
    view = gltf["bufferViews"][accessor["bufferView"]]
    count = accessor["count"]
    width = TYPE_COUNTS[accessor["type"]]
    size = COMPONENT_SIZES[accessor["componentType"]]
    stride = view.get("byteStride") or width * size
    start = view.get("byteOffset", 0) + accessor.get("byteOffset", 0)
    fmt = "<" + COMPONENT_FORMATS[accessor["componentType"]] * width
    return [struct.unpack_from(fmt, binary, start + i * stride) for i in range(count)]


def srgb(linear):
    linear = max(0.0, min(1.0, linear))
    value = linear * 12.92 if linear <= 0.0031308 else 1.055 * linear ** (1 / 2.4) - 0.055
    return round(value * 255)


def turn(point, turn_y, turn_x):
    x, y, z = point
    for _ in range((turn_y // 90) % 4):  # +90 about Y: (x, z) -> (z, -x)
        x, z = z, -x
    for _ in range((turn_x // 90) % 4):  # +90 about X: (y, z) -> (-z, y)
        y, z = -z, y
    return (x, y, z)


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(v):
    length = math.sqrt(dot(v, v))
    return tuple(x / length for x in v)


def align(axes, size):
    """The box's axes reordered (with their sizes) closest to X, Y, Z and pointing the positive
    way, so an upright box gets no rotation."""
    ordered, sizes = [], []
    for world in ((1, 0, 0), (0, 1, 0), (0, 0, 1)):
        index = max((i for i in range(3) if axes[i] not in ordered), key=lambda i: abs(dot(axes[i], world)))
        best = axes[index]
        ordered.append(best if dot(best, world) >= 0 else tuple(-x for x in best))
        sizes.append(size[index])
    if dot(cross(ordered[0], ordered[1]), ordered[2]) < 0:
        ordered[2] = tuple(-x for x in ordered[2])
    return ordered, sizes


def mesh_box(gltf, binary, mesh_index, name):
    """The mesh's box as (center, axes, size) and its material index; fails if it isn't a box.
    The axes (right, up, back: a rotation's columns) come from its face normals."""
    primitives = gltf["meshes"][mesh_index]["primitives"]
    if len(primitives) != 1:
        sys.exit(f"{name}: has {len(primitives)} materials; each mesh must be one colored box")
    primitive = primitives[0]
    points = read_accessor(gltf, binary, primitive["attributes"]["POSITION"])
    normals = read_accessor(gltf, binary, primitive["attributes"]["NORMAL"]) if "NORMAL" in primitive["attributes"] else []
    # The face directions, one per opposite pair.
    axes = []
    for normal in normals:
        n = unit(normal)
        if all(abs(dot(n, a)) < 0.99 for a in axes):
            axes.append(n)
    if len(axes) != 3 or any(abs(dot(axes[i], axes[j])) > 1e-3 for i, j in ((0, 1), (0, 2), (1, 2))):
        sys.exit(f"{name}: isn't a box (its faces don't point three square-on ways)")
    ordered, _ = align(axes, [0, 0, 0])
    size, center = [], [0.0, 0.0, 0.0]
    for axis in ordered:
        along = [dot(p, axis) for p in points]
        low, high = min(along), max(along)
        size.append(high - low)
        for i in range(3):
            center[i] += axis[i] * (low + high) / 2
    for point in points:
        for axis, extent in zip(ordered, size):
            offset = dot([point[i] - center[i] for i in range(3)], axis)
            if abs(abs(offset) - extent / 2) > 1e-3:
                sys.exit(f"{name}: isn't a box (a corner sits inside its bounds)")
    return center, ordered, size, primitive.get("material")


def has_transform(node):
    return any(key in node for key in ("matrix", "translation", "rotation", "scale"))


def build(gltf, binary, node_index, turn_y, turn_x, counter, solid=False):
    """The rbxmx <Item> for a node (a Part for a mesh, a Model for a group), as lines."""
    node = gltf["nodes"][node_index]
    name = node.get("name") or f"Part{node_index}"
    if has_transform(node):
        sys.exit(f"{name}: has a node transform; only models with baked positions are supported")
    counter[0] += 1
    referent = f"RBX{counter[0]}"
    lines = []
    if "mesh" in node:
        center, axes, size, material = mesh_box(gltf, binary, node["mesh"], name)
        center = turn(center, turn_y, turn_x)
        axes, size = align([turn(a, turn_y, turn_x) for a in axes], size)
        # Rows of the rotation matrix: R[r][c] = axes[c][r].
        rotation = "".join(f"<R{r}{c}>{axes[c][r]:.6f}</R{r}{c}>" for r in range(3) for c in range(3))
        color = (1, 1, 1, 1)
        if material is not None:
            color = gltf["materials"][material].get("pbrMetallicRoughness", {}).get("baseColorFactor", color)
        rgb = (srgb(color[0]) << 16) | (srgb(color[1]) << 8) | srgb(color[2])
        lines.append(f'<Item class="Part" referent="{referent}"><Properties>')
        lines.append(f'<string name="Name">{escape(name)}</string>')
        lines.append('<bool name="Anchored">true</bool>')
        lines.append(f'<bool name="CanCollide">{"true" if solid else "false"}</bool>')
        lines.append(
            '<CoordinateFrame name="CFrame">'
            + "".join(f"<{axis}>{value:.4f}</{axis}>" for axis, value in zip("XYZ", center))
            + rotation
            + "</CoordinateFrame>"
        )
        lines.append(f'<Color3uint8 name="Color3uint8">{0xFF000000 | rgb}</Color3uint8>')
        lines.append(f'<token name="Material">{SMOOTH_PLASTIC}</token>')
        lines.append('<token name="TopSurface">0</token><token name="BottomSurface">0</token>')
        lines.append(
            '<Vector3 name="size">' + "".join(f"<{axis}>{value:.4f}</{axis}>" for axis, value in zip("XYZ", size)) + "</Vector3>"
        )
        lines.append("</Properties>")
    else:
        lines.append(f'<Item class="Model" referent="{referent}"><Properties>')
        lines.append(f'<string name="Name">{escape(name)}</string>')
        lines.append("</Properties>")
    for child in node.get("children", []):
        lines.extend(build(gltf, binary, child, turn_y, turn_x, counter, solid))
    lines.append("</Item>")
    return lines


def main(argv):
    args = list(argv)
    options = {"--turn-y": 0, "--turn-x": 0}
    info = "--info" in args
    if info:
        args.remove("--info")
    solid = "--solid" in args
    if solid:
        args.remove("--solid")
    for flag in options:
        if flag in args:
            at = args.index(flag)
            options[flag] = int(args[at + 1])
            if options[flag] % 90 != 0:
                sys.exit(f"{flag} must be a multiple of 90")
            del args[at : at + 2]
    if len(args) != 2:
        sys.exit(__doc__)
    source, out = args
    gltf, binary = load_glb(source)
    scene = gltf["scenes"][gltf.get("scene", 0)]
    roots = scene["nodes"]
    counter = [0]
    lines = []
    for root in roots:
        lines.extend(build(gltf, binary, root, options["--turn-y"], options["--turn-x"], counter, solid))
    if len(roots) != 1 or "mesh" in gltf["nodes"][roots[0]]:
        # Wrap loose parts in a Model named after the file.
        lines = [f'<Item class="Model" referent="RBX0"><Properties><string name="Name">{escape(Path(out).stem)}</string></Properties>'] + lines + ["</Item>"]
    if info:
        parts = sum(1 for line in lines if line.startswith('<Item class="Part"'))
        print(f"{source}: {parts} boxes")
    Path(out).write_text('<roblox version="4">\n' + "\n".join(lines) + "\n</roblox>\n")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main(sys.argv[1:])
