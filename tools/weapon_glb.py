"""Prepares a color-only weapon model (GLB or OBJ+MTL) for Studio's Import 3D.

    python3 tools/weapon_glb.py SOURCE OUT.glb [--drop MATERIAL] [--split MATERIAL] [--turn-y DEGREES] [--turn-x DEGREES]
                                [--turn-z DEGREES] [--info]

Studio's importer drops plain material colors (a multi-color model comes in grey). This
bakes every material's color into a small palette texture instead, which Studio does import,
and writes a single-mesh GLB with all node transforms (scale, rotation) applied.

The game fits weapon models along their own axes (src/server/WeaponModels.luau), so the
output should be in this pose: length along Y with the handle at -Y, thinnest side along Z.
Use --info to see the model's extent per axis, and --turn-* (applied in X, Y, Z order) to
get it there. --drop leaves a material out (e.g. a bow's string, which the game draws itself).
--split writes a material as its own mesh (e.g. a potion's glass, which the game makes see-through).
"""
import json
import math
import struct
import sys
import zlib
from pathlib import Path

PALETTE_BLOCK = 16  # pixels per color, so texture filtering never blends neighbors


# --- math -------------------------------------------------------------------------------

def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def node_matrix(node):
    if "matrix" in node:
        m = node["matrix"]  # column-major
        return [[m[c * 4 + r] for c in range(4)] for r in range(4)]
    tx, ty, tz = node.get("translation", (0, 0, 0))
    qx, qy, qz, qw = node.get("rotation", (0, 0, 0, 1))
    sx, sy, sz = node.get("scale", (1, 1, 1))
    r = [
        [1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw)],
        [2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw)],
        [2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)],
    ]
    return [
        [r[0][0] * sx, r[0][1] * sy, r[0][2] * sz, tx],
        [r[1][0] * sx, r[1][1] * sy, r[1][2] * sz, ty],
        [r[2][0] * sx, r[2][1] * sy, r[2][2] * sz, tz],
        [0, 0, 0, 1],
    ]


def apply(m, p):
    return tuple(m[i][0] * p[0] + m[i][1] * p[1] + m[i][2] * p[2] + m[i][3] for i in range(3))


def turn(axis, degrees):
    c, s = math.cos(math.radians(degrees)), math.sin(math.radians(degrees))
    if axis == "x":
        r = [[1, 0, 0], [0, c, -s], [0, s, c]]
    elif axis == "y":
        r = [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    else:
        r = [[c, -s, 0], [s, c, 0], [0, 0, 1]]
    return [row + [0] for row in r] + [[0, 0, 0, 1]]


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


# --- loading: returns [(material name, linear RGB, [triangle (p0, p1, p2)])] -----------

def load_glb(path):
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
    groups = {}

    def visit(node_index, parent):
        node = g["nodes"][node_index]
        m = mat_mul(parent, node_matrix(node))
        if "mesh" in node:
            for prim in g["meshes"][node["mesh"]]["primitives"]:
                positions = [apply(m, p) for p in read(prim["attributes"]["POSITION"], "f", 3)]
                if "indices" in prim:
                    fmt = index_formats[g["accessors"][prim["indices"]]["componentType"]]
                    indices = [i[0] for i in read(prim["indices"], fmt, 1)]
                else:
                    indices = list(range(len(positions)))
                material = g["materials"][prim["material"]] if "material" in prim else {}
                name = material.get("name", "Default")
                color = material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])[:3]
                tris = groups.setdefault(name, (color, []))[1]
                for t in range(0, len(indices) - 2, 3):
                    tris.append(tuple(positions[indices[t + k]] for k in range(3)))
        for child_index in node.get("children", []):
            visit(child_index, m)

    identity = [[float(i == j) for j in range(4)] for i in range(4)]
    for root in g["scenes"][g.get("scene", 0)]["nodes"]:
        visit(root, identity)
    return [(name, color, tris) for name, (color, tris) in groups.items()]


def load_obj(path):
    colors = {}
    mtl_path = Path(path).with_suffix(".mtl")
    current = None
    if mtl_path.exists():
        for line in mtl_path.read_text().splitlines():
            parts = line.split()
            if parts and parts[0] == "newmtl":
                current = parts[1]
            elif parts and parts[0] == "Kd" and current:
                colors[current] = [float(v) for v in parts[1:4]]
    verts, groups, current = [], {}, "Default"
    for line in Path(path).read_text().splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "v":
            verts.append(tuple(float(v) for v in parts[1:4]))
        elif parts[0] == "usemtl":
            current = parts[1]
        elif parts[0] == "f":
            ids = [int(p.split("/")[0]) for p in parts[1:]]
            ids = [i - 1 if i > 0 else len(verts) + i for i in ids]
            tris = groups.setdefault(current, [])
            for k in range(1, len(ids) - 1):  # fan-triangulate quads/ngons
                tris.append((verts[ids[0]], verts[ids[k]], verts[ids[k + 1]]))
    return [(name, colors.get(name, [0.8, 0.8, 0.8]), tris) for name, tris in groups.items()]


# --- output --------------------------------------------------------------------------------

def png(width, height, pixels):
    """pixels: rows of (r, g, b) bytes."""
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in pixels)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def write_glb(groups, out_path, split=()):
    """Writes one mesh of every group, plus one more per material named in `split` (all
    sharing the palette), so Studio imports those as their own MeshParts, named after them."""
    count = len(groups)
    side = 1
    while side * side < count:
        side += 1
    size = side * PALETTE_BLOCK
    pixels = [[(0, 0, 0)] * size for _ in range(size)]
    stem = Path(out_path).stem.split(".")[0]
    parts = {stem: ([], [], [])}
    for name in split:
        parts[name[:1].upper() + name[1:]] = ([], [], [])
    for index, (name, color, tris) in enumerate(groups):
        bx, by = index % side, index // side
        rgb = tuple(round(linear_to_srgb(c) * 255) for c in color)
        for y in range(by * PALETTE_BLOCK, (by + 1) * PALETTE_BLOCK):
            for x in range(bx * PALETTE_BLOCK, (bx + 1) * PALETTE_BLOCK):
                pixels[y][x] = rgb
        uv = ((bx + 0.5) / side, (by + 0.5) / side)
        positions, normals, uvs = parts[name[:1].upper() + name[1:] if name in split else stem]
        for a, b, c in tris:
            e1 = [b[i] - a[i] for i in range(3)]
            e2 = [c[i] - a[i] for i in range(3)]
            n = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
            length = math.sqrt(sum(v * v for v in n)) or 1
            n = tuple(v / length for v in n)
            for p in (a, b, c):
                positions.append(p)
                normals.append(n)
                uvs.append(uv)

    def pad(b):
        return b + b"\x00" * (-len(b) % 4)

    chunks, views, accessors, meshes, nodes = [], [], [], [], []
    total = 0

    def add_chunk(data, target=None):
        nonlocal total
        view = {"buffer": 0, "byteOffset": total, "byteLength": len(data)}
        if target:
            view["target"] = target
        chunks.append(pad(data))
        total += len(chunks[-1])
        views.append(view)
        return len(views) - 1

    image_view = add_chunk(png(size, size, pixels))
    triangles = 0
    for part_name, (positions, normals, uvs) in parts.items():
        if not positions:
            continue
        n = len(positions)
        triangles += n // 3
        lo = [min(p[i] for p in positions) for i in range(3)]
        hi = [max(p[i] for p in positions) for i in range(3)]
        first = len(accessors)
        accessors.append({"bufferView": add_chunk(b"".join(struct.pack("<fff", *p) for p in positions), 34962),
                          "componentType": 5126, "count": n, "type": "VEC3", "min": lo, "max": hi})
        accessors.append({"bufferView": add_chunk(b"".join(struct.pack("<fff", *v) for v in normals), 34962),
                          "componentType": 5126, "count": n, "type": "VEC3"})
        accessors.append({"bufferView": add_chunk(b"".join(struct.pack("<ff", *u) for u in uvs), 34962),
                          "componentType": 5126, "count": n, "type": "VEC2"})
        meshes.append({"primitives": [{"attributes": {"POSITION": first, "NORMAL": first + 1, "TEXCOORD_0": first + 2}, "material": 0}]})
        nodes.append({"name": part_name, "mesh": len(meshes) - 1})

    gltf = {
        "asset": {"version": "2.0", "generator": "SlayerRevo weapon_glb.py"},
        "scene": 0,
        "scenes": [{"nodes": list(range(len(nodes)))}],
        "nodes": nodes,
        "meshes": meshes,
        "materials": [{"name": "Palette", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 0.8}}],
        "textures": [{"source": 0, "sampler": 0}],
        "samplers": [{"magFilter": 9728, "minFilter": 9728}],
        "images": [{"bufferView": image_view, "mimeType": "image/png"}],
        "buffers": [{"byteLength": total}],
        "bufferViews": views,
        "accessors": accessors,
    }
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode()
    json_bytes += b" " * (-len(json_bytes) % 4)
    body = b"".join(chunks)
    glb = (struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_bytes) + 8 + len(body))
           + struct.pack("<I", len(json_bytes)) + b"JSON" + json_bytes
           + struct.pack("<I", len(body)) + b"BIN\x00" + body)
    Path(out_path).write_bytes(glb)
    return triangles


def describe(groups):
    """Extent per axis, and how wide the model is along its longest axis (to find the handle)."""
    pts = [p for _, _, tris in groups for t in tris for p in t]
    lo = [min(p[i] for p in pts) for i in range(3)]
    hi = [max(p[i] for p in pts) for i in range(3)]
    size = [h - l for h, l in zip(hi, lo)]
    print("  size  X %.2f  Y %.2f  Z %.2f" % tuple(size))
    axis = size.index(max(size))
    print(f"  width along {'XYZ'[axis]} (low end first):")
    for b in range(10):
        a0, a1 = lo[axis] + size[axis] * b / 10, lo[axis] + size[axis] * (b + 1) / 10
        sl = [p for p in pts if a0 <= p[axis] <= a1]
        widths = [max(p[i] for p in sl) - min(p[i] for p in sl) if sl else 0 for i in range(3) if i != axis]
        print(f"    {b * 10:3d}-{b * 10 + 10:3d}%  " + "  ".join(f"{w:.2f}" for w in widths))
    for name, color, tris in groups:
        mp = [p for t in tris for p in t]
        print(f"  {name}: {len(tris)} tris, color {[round(c, 2) for c in color]}, "
              f"min {[round(min(p[i] for p in mp), 2) for i in range(3)]} max {[round(max(p[i] for p in mp), 2) for i in range(3)]}")


def main(argv):
    args = argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    source, out = args[0], args[1]
    drop, split, turns, info = set(), set(), [], False
    i = 2
    while i < len(args):
        if args[i] == "--drop":
            drop.add(args[i + 1])
            i += 2
        elif args[i] == "--split":
            split.add(args[i + 1])
            i += 2
        elif args[i] in ("--turn-x", "--turn-y", "--turn-z"):
            turns.append((args[i][-1], float(args[i + 1])))
            i += 2
        elif args[i] == "--info":
            info = True
            i += 1
        else:
            sys.exit(f"unknown option {args[i]}")
    groups = load_obj(source) if source.lower().endswith(".obj") else load_glb(source)
    groups = [g for g in groups if g[0] not in drop]
    order = {"x": 0, "y": 1, "z": 2}
    m = [[float(r == c) for c in range(4)] for r in range(4)]
    for axis, degrees in sorted(turns, key=lambda t: order[t[0]]):
        m = mat_mul(turn(axis, degrees), m)
    groups = [(name, color, [tuple(apply(m, p) for p in t) for t in tris]) for name, color, tris in groups]
    # Center it, so it imports where expected.
    pts = [p for _, _, tris in groups for t in tris for p in t]
    center = [(min(p[i] for p in pts) + max(p[i] for p in pts)) / 2 for i in range(3)]
    groups = [(name, color, [tuple(tuple(p[i] - center[i] for i in range(3)) for p in t) for t in tris])
              for name, color, tris in groups]
    describe(groups)
    if not info:
        print(f"wrote {out}: {write_glb(groups, out, split)} triangles, {len(groups)} colors")


if __name__ == "__main__":
    main(sys.argv)
