"""Prepares a rigged, animated, color-only GLB (an NPC or creature) for Studio's Import 3D,
keeping its skeleton, skin weights and animation clips intact.

    python3 -I tools/npc_glb.py SOURCE OUT.glb [--turn-y DEGREES] [--clip NAME]... [--info]

tools/weapon_glb.py can't be used for these: it rebuilds the model from loose triangles, so it
drops the skin, bones and clips (and re-centers the model). This only does the two things
Studio needs:
* Bakes every material's flat color into one small palette texture (Studio's importer drops
  plain material colors), and joins the mesh into a single primitive using it, so it imports
  as one MeshPart. Vertices shared by two materials are split so each gets its own color.
* --turn-y turns the whole model around Y (e.g. 180: models designed facing +Z, Roblox faces
  -Z). Vertices, normals and the bind matrices are turned, and so is each skeleton root bone
  (its rest pose and its animation keys). Every other bone keeps its own local axes, so
  bone-space values like an eyelid's open/shut angle stay the same.
--clip keeps only the named animation clips (repeat it for several), e.g. to import one clip
per file. --info prints the model, skeleton and clips (and warns about clips that don't move)
without writing anything; pass /dev/null as OUT with it.
"""
import json
import math
import struct
import sys
import zlib
from pathlib import Path

PALETTE_BLOCK = 16  # pixels per color, so texture filtering never blends neighbors

COMPONENT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
WIDTH = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT2": 4, "MAT3": 9, "MAT4": 16}
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963


# --- reading -------------------------------------------------------------------------------

def load(path):
    data = Path(path).read_bytes()
    magic, version = struct.unpack_from("<II", data, 0)
    if magic != 0x46546C67 or version != 2:
        sys.exit(f"{path} isn't a glTF 2.0 .glb")
    json_len = struct.unpack_from("<I", data, 12)[0]
    gltf = json.loads(data[20:20 + json_len])
    bin_start = 20 + json_len + 8
    if any("sparse" in a for a in gltf["accessors"]):
        sys.exit("sparse accessors aren't supported")
    if len(gltf.get("buffers", [])) != 1:
        sys.exit("expected exactly one (embedded) buffer")
    return gltf, data[bin_start:]


def read_accessor(gltf, binary, index):
    """Returns the accessor's elements as tuples of numbers."""
    acc = gltf["accessors"][index]
    view = gltf["bufferViews"][acc["bufferView"]]
    fmt = "<" + COMPONENT[acc["componentType"]] * WIDTH[acc["type"]]
    stride = view.get("byteStride") or struct.calcsize(fmt)
    offset = view.get("byteOffset", 0) + acc.get("byteOffset", 0)
    return [struct.unpack_from(fmt, binary, offset + i * stride) for i in range(acc["count"])]


# --- math ----------------------------------------------------------------------------------

def turn_y(degrees):
    """(3x3 rotation matrix, quaternion xyzw) for a turn around Y."""
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]], (0.0, math.sin(a / 2), 0.0, math.cos(a / 2))


def rotate(m, v):
    return tuple(m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2] for i in range(3))


def quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by,
            aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw,
            aw * bw - ax * bx - ay * by - az * bz)


def mat4_times_rot_inverse(col_major, r):
    """M * R^-1 for a column-major 4x4 M and a 3x3 rotation R (R^-1 = R^T)."""
    m = [[col_major[c * 4 + row] for c in range(4)] for row in range(4)]
    r4 = [[r[j][i] for j in range(3)] + [0] for i in range(3)] + [[0, 0, 0, 1]]  # R^T
    out = [[sum(m[i][k] * r4[k][j] for k in range(4)) for j in range(4)] for i in range(4)]
    return tuple(out[row][c] for c in range(4) for row in range(4))


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055


def png(width, height, pixels):
    """pixels: rows of (r, g, b) bytes."""
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in pixels)

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


# --- info ----------------------------------------------------------------------------------

def describe(gltf, binary):
    nodes = gltf["nodes"]
    names = [n.get("name", f"node{i}") for i, n in enumerate(nodes)]
    for mesh in gltf["meshes"]:
        tris = 0
        for prim in mesh["primitives"]:
            count = gltf["accessors"][prim["indices"]]["count"] if "indices" in prim else gltf["accessors"][prim["attributes"]["POSITION"]]["count"]
            tris += count // 3
        attrs = sorted({a for p in mesh["primitives"] for a in p["attributes"]})
        print(f"  mesh {mesh.get('name', '?')}: {len(mesh['primitives'])} primitives, {tris} triangles, attributes {attrs}")
        pos = gltf["accessors"][mesh["primitives"][0]["attributes"]["POSITION"]]
        size = [hi - lo for hi, lo in zip(pos["max"], pos["min"])]
        print("    size  X %.2f  Y %.2f  Z %.2f   min Y %.2f" % (*size, pos["min"][1]))
    for m in gltf.get("materials", []):
        color = m.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])[:3]
        hexed = "".join(f"{round(linear_to_srgb(c) * 255):02X}" for c in color)
        print(f"  material {m.get('name', '?')}: #{hexed}")
    for skin in gltf.get("skins", []):
        print(f"  skin: {len(skin['joints'])} joints: {', '.join(names[j] for j in skin['joints'])}")
    for anim in gltf.get("animations", []):
        times = [t for s in anim["samplers"] for (t,) in read_accessor(gltf, binary, s["input"])]
        moving = set()
        for ch in anim["channels"]:
            out = read_accessor(gltf, binary, anim["samplers"][ch["sampler"]]["output"])
            if any(max(abs(x - y) for x, y in zip(out[0], key)) > 1e-4 for key in out):
                moving.add(names[ch["target"]["node"]])
        keys = max(len(read_accessor(gltf, binary, s["input"])) for s in anim["samplers"])
        note = f"{len(moving)} bones move" if moving else "WARNING: no bone moves (a held pose, not an animation)"
        print(f"  clip {anim.get('name', '?')}: {max(times) - min(times):.2f} s, {keys} keys per track, "
              f"{len(anim['channels'])} tracks, {note}")


# --- converting ----------------------------------------------------------------------------

def convert(gltf, binary, degrees, clips):
    nodes = gltf["nodes"]
    if len(gltf["meshes"]) != 1:
        sys.exit("expected exactly one mesh")
    if clips:
        missing = set(clips) - {a.get("name") for a in gltf.get("animations", [])}
        if missing:
            sys.exit(f"no clip named {', '.join(sorted(missing))}")
        gltf["animations"] = [a for a in gltf.get("animations", []) if a.get("name") in clips]
    r, q = turn_y(degrees)
    turning = abs(degrees) % 360 > 1e-9

    # Every accessor's elements, decoded; replaced ones are swapped in below.
    values = {i: read_accessor(gltf, binary, i) for i in range(len(gltf["accessors"]))}

    # One primitive, palette colors: copy each primitive's vertices (splitting shared ones).
    mesh = gltf["meshes"][0]
    prims = mesh["primitives"]
    attr_names = sorted(set.intersection(*(set(p["attributes"]) for p in prims)))
    if any(p.get("mode", 4) != 4 for p in prims):
        sys.exit("only triangle lists are supported")
    materials = gltf.get("materials", [])
    count = max(len(materials), 1)
    side = 1
    while side * side < count:
        side += 1
    size = side * PALETTE_BLOCK
    pixels = [[(0, 0, 0)] * size for _ in range(size)]
    for index, material in enumerate(materials or [{}]):
        color = material.get("pbrMetallicRoughness", {}).get("baseColorFactor", [1, 1, 1, 1])[:3]
        rgb = tuple(round(linear_to_srgb(c) * 255) for c in color)
        bx, by = index % side, index // side
        for y in range(by * PALETTE_BLOCK, (by + 1) * PALETTE_BLOCK):
            for x in range(bx * PALETTE_BLOCK, (bx + 1) * PALETTE_BLOCK):
                pixels[y][x] = rgb

    merged = {name: [] for name in attr_names}
    uvs, indices = [], []
    template = {name: prims[0]["attributes"][name] for name in attr_names}
    for prim in prims:
        material = prim.get("material", 0)
        uv = ((material % side + 0.5) / side, (material // side + 0.5) / side)
        source = {name: values[prim["attributes"][name]] for name in attr_names}
        vertex_count = len(source["POSITION"])
        old = [i for (i,) in values[prim["indices"]]] if "indices" in prim else list(range(vertex_count))
        remap = {}
        for i in old:
            if i not in remap:
                remap[i] = len(uvs)
                for name in attr_names:
                    merged[name].append(source[name][i])
                uvs.append(uv)
            indices.append((remap[i],))
    if "TEXCOORD_0" in merged:
        del merged["TEXCOORD_0"]  # replaced by the palette's

    if turning:
        merged["POSITION"] = [rotate(r, p) for p in merged["POSITION"]]
        if "NORMAL" in merged:
            merged["NORMAL"] = [rotate(r, n) for n in merged["NORMAL"]]
        if "TANGENT" in merged:
            merged["TANGENT"] = [(*rotate(r, t[:3]), t[3]) for t in merged["TANGENT"]]

    # Turn the skeleton: its root bones (joints whose parent isn't a joint), and the bind matrices.
    parent = {child: i for i, n in enumerate(nodes) for child in n.get("children", [])}
    turned_roots = set()
    if turning:
        for skin in gltf.get("skins", []):
            joints = set(skin["joints"])
            for j in joints:
                if parent.get(j) in joints:
                    continue
                # Anything above the skeleton must not move it, or the turn wouldn't be around the origin.
                ancestor = parent.get(j)
                while ancestor is not None:
                    a = nodes[ancestor]
                    if a.get("matrix") or a.get("translation", [0, 0, 0]) != [0, 0, 0] or a.get("rotation", [0, 0, 0, 1]) != [0, 0, 0, 1] or a.get("scale", [1, 1, 1]) != [1, 1, 1]:
                        sys.exit(f"node {a.get('name')} above the skeleton has a transform; not supported")
                    ancestor = parent.get(ancestor)
                turned_roots.add(j)
            if "inverseBindMatrices" in skin:
                i = skin["inverseBindMatrices"]
                values[i] = [mat4_times_rot_inverse(m, r) for m in values[i]]
        for j in turned_roots:
            node = nodes[j]
            if "matrix" in node:
                sys.exit(f"bone {node.get('name')} uses a matrix; not supported")
            node["translation"] = list(rotate(r, node.get("translation", [0, 0, 0])))
            node["rotation"] = list(quat_mul(q, tuple(node.get("rotation", [0, 0, 0, 1]))))
        for anim in gltf.get("animations", []):
            done = set()
            for ch in anim["channels"]:
                target = ch["target"]
                if target.get("node") not in turned_roots or target["path"] not in ("translation", "rotation"):
                    continue
                sampler = anim["samplers"][ch["sampler"]]
                out = sampler["output"]
                if out in done:
                    continue
                done.add(out)
                # (CUBICSPLINE tangents are in the same list and turn the same way as the values.)
                if target["path"] == "translation":
                    values[out] = [rotate(r, t) for t in values[out]]
                else:
                    values[out] = [quat_mul(q, tuple(v)) for v in values[out]]

    # Build the output: every accessor tightly packed in its own buffer view.
    accessors = gltf["accessors"]
    new_accessors, views, chunks = [], [], []
    total = 0

    def add_view(data, target=None, stride=None):
        nonlocal total
        view = {"buffer": 0, "byteOffset": total, "byteLength": len(data)}
        if target:
            view["target"] = target
        if stride:
            view["byteStride"] = stride
        data += b"\x00" * (-len(data) % 4)
        chunks.append(data)
        total += len(data)
        views.append(view)
        return len(views) - 1

    def add_accessor(base, elements, target=None):
        acc = {k: v for k, v in base.items() if k not in ("bufferView", "byteOffset", "min", "max", "count")}
        comp = COMPONENT[acc["componentType"]]
        width = WIDTH[acc["type"]]
        element_size = struct.calcsize("<" + comp * width)
        stride = None
        pad = b""
        if target == ARRAY_BUFFER and element_size % 4:
            pad = b"\x00" * (-element_size % 4)
            stride = element_size + len(pad)
        data = b"".join(struct.pack("<" + comp * width, *e) + pad for e in elements)
        acc["bufferView"] = add_view(data, target, stride)
        acc["count"] = len(elements)
        if "min" in base or target == ARRAY_BUFFER:
            acc["min"] = [min(e[k] for e in elements) for k in range(width)]
            acc["max"] = [max(e[k] for e in elements) for k in range(width)]
        new_accessors.append(acc)
        return len(new_accessors) - 1

    vertex_accessors = set(a for p in prims for a in p["attributes"].values()) | set(p["indices"] for p in prims if "indices" in p)
    remap_accessor = {}
    for i, acc in enumerate(accessors):
        if i not in vertex_accessors:
            remap_accessor[i] = add_accessor(acc, values[i])
    attributes = {name: add_accessor(accessors[template[name]], merged[name], ARRAY_BUFFER) for name in merged}
    attributes["TEXCOORD_0"] = add_accessor({"componentType": 5126, "type": "VEC2"}, uvs, ARRAY_BUFFER)
    index_type = 5123 if len(uvs) < 65536 else 5125
    index_accessor = add_accessor({"componentType": index_type, "type": "SCALAR"}, indices, ELEMENT_ARRAY_BUFFER)
    image_view = add_view(png(size, size, pixels))

    mesh["primitives"] = [{"attributes": attributes, "indices": index_accessor, "material": 0, "mode": 4}]
    for skin in gltf.get("skins", []):
        if "inverseBindMatrices" in skin:
            skin["inverseBindMatrices"] = remap_accessor[skin["inverseBindMatrices"]]
    for anim in gltf.get("animations", []):
        for sampler in anim["samplers"]:
            sampler["input"] = remap_accessor[sampler["input"]]
            sampler["output"] = remap_accessor[sampler["output"]]
    gltf["accessors"] = new_accessors
    gltf["bufferViews"] = views
    gltf["buffers"] = [{"byteLength": total}]
    gltf["materials"] = [{"name": "Palette", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicFactor": 0, "roughnessFactor": 0.85}}]
    gltf["textures"] = [{"source": 0, "sampler": 0}]
    gltf["samplers"] = [{"magFilter": 9728, "minFilter": 9728}]
    gltf["images"] = [{"bufferView": image_view, "mimeType": "image/png"}]
    gltf["asset"]["generator"] = "SlayerRevo npc_glb.py"
    return gltf, b"".join(chunks), len(indices) // 3, len(uvs), len(materials)


def write(gltf, body, out_path):
    json_bytes = json.dumps(gltf, separators=(",", ":")).encode()
    json_bytes += b" " * (-len(json_bytes) % 4)
    glb = (struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(json_bytes) + 8 + len(body))
           + struct.pack("<I", len(json_bytes)) + b"JSON" + json_bytes
           + struct.pack("<I", len(body)) + b"BIN\x00" + body)
    Path(out_path).write_bytes(glb)


def main(argv):
    args = argv[1:]
    if len(args) < 2:
        sys.exit(__doc__)
    source, out = args[0], args[1]
    degrees, clips, info = 0.0, [], False
    i = 2
    while i < len(args):
        if args[i] == "--turn-y":
            degrees = float(args[i + 1])
            i += 2
        elif args[i] == "--clip":
            clips.append(args[i + 1])
            i += 2
        elif args[i] == "--info":
            info = True
            i += 1
        else:
            sys.exit(f"unknown option {args[i]}")
    gltf, binary = load(source)
    describe(gltf, binary)
    if info:
        return
    gltf, body, triangles, vertices, colors = convert(gltf, binary, degrees, clips)
    write(gltf, body, out)
    print(f"wrote {out}: {triangles} triangles, {vertices} vertices, {colors} colors, "
          f"{len(gltf.get('animations', []))} clips, turned {degrees:g} degrees")


if __name__ == "__main__":
    main(sys.argv)
