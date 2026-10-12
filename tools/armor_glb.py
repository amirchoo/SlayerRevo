"""Prepares a color-only armor set GLB for Studio's Import 3D, one mesh per piece.

    python3 tools/armor_glb.py SOURCE.glb OUT.glb [--info]

The source follows docs/model-brief.md: a node per slot (named ending in the slot, e.g.
`LeatherHelmet`), and pairs as `Left`/`Right` children, worn on a character standing at the
origin facing +Z. Like weapon_glb.py, material colors are baked into a palette texture
(Studio drops plain colors), but each piece stays its own mesh so it can become its own
Accessory:

    Helmet, Chestplate, LeftLeggings, RightLeggings, LeftBoots, RightBoots,
    LeftUpperArm, LeftLowerArm, RightUpperArm, RightLowerArm

Armwear is split into its shoulder and forearm parts (touching parts grouped together, then
sorted by how far they are from the shoulder; an arm may have only one) and each part is
turned to hang straight down, since the brief's
A-pose arms are angled out but a Roblox rig's arms hang down. Positions are otherwise kept,
so the set imports as one Model that's easy to line up with a rig.
"""
import json
import math
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from weapon_glb import PALETTE_BLOCK, apply, linear_to_srgb, mat_mul, node_matrix, png  # noqa: E402

SLOTS = ("Helmet", "Chestplate", "Armwear", "Leggings", "Boots")


def load_pieces(path):
    """Returns {piece name: [(material name, linear RGB, triangle)]}."""
    data = Path(path).read_bytes()
    json_len = struct.unpack_from("<I", data, 12)[0]
    g = json.loads(data[20:20 + json_len])
    bin_start = 20 + json_len + 8

    def read(accessor_index, fmt, width):
        acc = g["accessors"][accessor_index]
        view = g["bufferViews"][acc["bufferView"]]
        off = bin_start + view.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = view.get("byteStride", struct.calcsize(fmt * width))
        return [struct.unpack_from("<" + fmt * width, data, off + i * stride) for i in range(acc["count"])]

    index_formats = {5121: "B", 5123: "H", 5125: "I"}
    pieces = {}

    def visit(node_index, parent, slot):
        node = g["nodes"][node_index]
        m = mat_mul(parent, node_matrix(node))
        name = node.get("name", "")
        slot = next((s for s in SLOTS if name.endswith(s)), slot)
        if "mesh" in node:
            if slot is None:
                sys.exit(f"mesh node {name!r} isn't under a slot node ({', '.join(SLOTS)})")
            side = name if name in ("Left", "Right") else ""
            tris = pieces.setdefault(side + slot, [])
            for prim in g["meshes"][node["mesh"]]["primitives"]:
                positions = [apply(m, p) for p in read(prim["attributes"]["POSITION"], "f", 3)]
                if "indices" in prim:
                    fmt = index_formats[g["accessors"][prim["indices"]]["componentType"]]
                    indices = [i[0] for i in read(prim["indices"], fmt, 1)]
                else:
                    indices = list(range(len(positions)))
                material = g["materials"][prim["material"]] if "material" in prim else {}
                color = material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])[:3]
                mat = (material.get("name", "Default"), tuple(color))
                for t in range(0, len(indices) - 2, 3):
                    tris.append((mat, tuple(positions[indices[t + k]] for k in range(3))))
        for child_index in node.get("children", []):
            visit(child_index, m, slot)

    identity = [[float(i == j) for j in range(4)] for i in range(4)]
    for root in g["scenes"][g.get("scene", 0)]["nodes"]:
        visit(root, identity, None)
    return pieces


def components(tris):
    """Splits triangles into connected pieces (sharing a vertex position)."""
    parent = {}

    def find(k):
        while parent.setdefault(k, k) != k:
            parent[k] = parent[parent[k]]
            k = parent[k]
        return k

    def key(p):
        return tuple(round(c, 4) for c in p)

    for _, t in tris:
        a = find(key(t[0]))
        for p in t[1:]:
            b = find(key(p))
            if a != b:
                parent[b] = a
    groups = {}
    for tri in tris:
        groups.setdefault(find(key(tri[1][0])), []).append(tri)
    return list(groups.values())


def centroid(tris):
    pts = [p for _, t in tris for p in t]
    return [sum(p[i] for p in pts) / len(pts) for i in range(3)]


SHOULDER = (1.0, 4.0)  # where the brief's 5-stud A-pose arm meets the body (|X|, Y)
TOUCH = 0.05  # parts this close count as one piece
UPPER_REACH = 1.35  # clusters centered nearer the shoulder than this are the upper arm


def clusters(tris):
    """Connected parts, merged when their surfaces come within TOUCH of each other (a bracer
    made of stacked slabs is one cluster; a shoulder pad with a gap below it is another)."""
    groups = []
    for part in components(tris):
        points = sorted({tuple(round(c, 3) for c in p) for _, t in part for p in t})
        groups.append((part, points))

    def touching(a, b):
        for p in a:
            for q in b:
                if abs(p[1] - q[1]) <= TOUCH and abs(p[0] - q[0]) <= TOUCH and abs(p[2] - q[2]) <= TOUCH:
                    return True
        return False

    merged = True
    while merged:
        merged = False
        for i in range(len(groups)):
            for j in range(i + 1, len(groups)):
                if touching(groups[i][1], groups[j][1]):
                    groups[i] = (groups[i][0] + groups[j][0], groups[i][1] + groups[j][1])
                    del groups[j]
                    merged = True
                    break
            if merged:
                break
    return [g[0] for g in groups]


def shoulder_distance(tris):
    c = centroid(tris)
    return math.hypot(abs(c[0]) - SHOULDER[0], c[1] - SHOULDER[1])


def split_arm(tris):
    """(upper, lower): the shoulder part and the forearm part of one arm piece; either may be
    empty (an arm with only a bracer, say)."""
    upper, lower = [], []
    for cluster in clusters(tris):
        (upper if shoulder_distance(cluster) < UPPER_REACH else lower).extend(cluster)
    return upper, lower


def hang_down(upper, lower):
    """Turns both arm parts around their own centers so the arm points straight down. The arm's
    angle is taken from the shoulder to the forearm part (or the upper part, if that's all)."""
    far = lower or upper
    c = centroid(far)
    side = 1 if c[0] > 0 else -1
    dx, dy = c[0] - side * SHOULDER[0], c[1] - SHOULDER[1]
    angle = math.atan2(dx, -dy)  # how far the arm swings out from straight down, in the XY plane
    cs, sn = math.cos(-angle), math.sin(-angle)

    def turn(tris):
        if not tris:
            return tris
        center = centroid(tris)
        out = []
        for mat, t in tris:
            q = []
            for p in t:
                x, y = p[0] - center[0], p[1] - center[1]
                q.append((center[0] + cs * x - sn * y, center[1] + sn * x + cs * y, p[2]))
            out.append((mat, tuple(q)))
        return out

    return turn(upper), turn(lower), math.degrees(angle)


def write_glb(pieces, out_path):
    """pieces: {name: [(mat, triangle)]}. One mesh per piece, all sharing a palette texture."""
    mats = sorted({mat for tris in pieces.values() for mat, _ in tris})
    side = 1
    while side * side < len(mats):
        side += 1
    size = side * PALETTE_BLOCK
    pixels = [[(0, 0, 0)] * size for _ in range(size)]
    uv_of = {}
    for index, mat in enumerate(mats):
        bx, by = index % side, index // side
        rgb = tuple(round(linear_to_srgb(c) * 255) for c in mat[1])
        for y in range(by * PALETTE_BLOCK, (by + 1) * PALETTE_BLOCK):
            for x in range(bx * PALETTE_BLOCK, (bx + 1) * PALETTE_BLOCK):
                pixels[y][x] = rgb
        uv_of[mat] = ((bx + 0.5) / side, (by + 0.5) / side)

    blob, views, accessors, nodes, meshes = b"", [], [], [], []

    def add_view(data, target=None):
        nonlocal blob
        view = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            view["target"] = target
        views.append(view)
        blob += data + b"\x00" * (-len(data) % 4)
        return len(views) - 1

    for name, tris in pieces.items():
        positions, normals, uvs = [], [], []
        for mat, (a, b, c) in tris:
            e1 = [b[i] - a[i] for i in range(3)]
            e2 = [c[i] - a[i] for i in range(3)]
            n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            length = math.sqrt(sum(v * v for v in n)) or 1
            for p in (a, b, c):
                positions.append(p)
                normals.append(tuple(v / length for v in n))
                uvs.append(uv_of[mat])
        count = len(positions)
        first = len(accessors)
        accessors += [
            {"bufferView": add_view(b"".join(struct.pack("<fff", *p) for p in positions), 34962),
             "componentType": 5126, "count": count, "type": "VEC3",
             "min": [min(p[i] for p in positions) for i in range(3)],
             "max": [max(p[i] for p in positions) for i in range(3)]},
            {"bufferView": add_view(b"".join(struct.pack("<fff", *n) for n in normals), 34962),
             "componentType": 5126, "count": count, "type": "VEC3"},
            {"bufferView": add_view(b"".join(struct.pack("<ff", *u) for u in uvs), 34962),
             "componentType": 5126, "count": count, "type": "VEC2"},
        ]
        meshes.append({"name": name, "primitives": [
            {"attributes": {"POSITION": first, "NORMAL": first + 1, "TEXCOORD_0": first + 2}, "material": 0}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})

    image_view = add_view(png(size, size, pixels))
    nodes.append({"name": Path(out_path).stem.split(".")[0], "children": list(range(len(nodes)))})
    gltf = {
        "asset": {"version": "2.0", "generator": "SlayerRevo armor_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": [len(nodes) - 1]}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": [{"name": "Palette", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 0.8}}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728}],
        "images": [{"bufferView": image_view, "mimeType": "image/png"}],
        "buffers": [{"byteLength": len(blob)}],
        "bufferViews": views,
        "accessors": accessors,
    }
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode()
    json_bytes += b" " * (-len(json_bytes) % 4)
    glb = (struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_bytes) + 8 + len(blob))
           + struct.pack("<I", len(json_bytes)) + b"JSON" + json_bytes
           + struct.pack("<I", len(blob)) + b"BIN\x00" + blob)
    Path(out_path).write_bytes(glb)


def main(argv):
    args = argv[1:]
    if len(args) < 2 or any(a not in ("--info",) for a in args[2:]):
        sys.exit(__doc__)
    source, out, info = args[0], args[1], "--info" in args[2:]
    pieces = load_pieces(source)
    for side in ("Left", "Right"):
        arm = pieces.pop(f"{side}Armwear", None)
        if arm:
            upper, lower, angle = hang_down(*split_arm(arm))
            print(f"  {side} arm: turned {angle:.0f} degrees to hang down"
                  + ("" if upper else " (no shoulder part)") + ("" if lower else " (no forearm part)"))
            if upper:
                pieces[f"{side}UpperArm"] = upper
            if lower:
                pieces[f"{side}LowerArm"] = lower
    for name, tris in pieces.items():
        pts = [p for _, t in tris for p in t]
        lo = [round(min(p[i] for p in pts), 2) for i in range(3)]
        hi = [round(max(p[i] for p in pts), 2) for i in range(3)]
        print(f"  {name}: {len(tris)} tris, min {lo} max {hi}")
    if not info:
        write_glb(pieces, out)
        print(f"wrote {out}: {len(pieces)} pieces")


if __name__ == "__main__":
    main(sys.argv)
