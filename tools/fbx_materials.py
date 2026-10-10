"""Fix grey imports of color-only FBX models (e.g. Quaternius packs).

Roblox's importer merges a mesh into one MeshPart and drops plain material colors.
This tool works around that in two steps:

  split     FBX -> GLB with one node per material, so Studio imports one MeshPart per material.
            python3 tools/fbx_materials.py split assets/source/House_1.fbx
  colorize  After importing the GLB and saving it as .rbxmx, color each MeshPart from the FBX.
            python3 tools/fbx_materials.py colorize assets/source/House_1.fbx assets/town/House_1.rbxmx
"""
import json
import math
import re
import struct
import sys
import zlib
from pathlib import Path


def parse_fbx(path):
    data = Path(path).read_bytes()
    if not data.startswith(b"Kaydara FBX Binary"):
        sys.exit(f"{path}: only binary FBX is supported")
    wide = struct.unpack_from("<I", data, 23)[0] >= 7500

    def read_prop(pos):
        t = chr(data[pos]); pos += 1
        simple = {"Y": "<h", "C": "<?", "I": "<i", "F": "<f", "D": "<d", "L": "<q"}
        if t in simple:
            fmt = simple[t]
            return struct.unpack_from(fmt, data, pos)[0], pos + struct.calcsize(fmt)
        if t in "fdlib":
            n, encoding, length = struct.unpack_from("<III", data, pos); pos += 12
            raw = data[pos:pos + length]; pos += length
            if encoding == 1:
                raw = zlib.decompress(raw)
            fmt = {"f": "f", "d": "d", "l": "q", "i": "i", "b": "B"}[t]
            return list(struct.unpack(f"<{n}{fmt}", raw)), pos
        if t in "SR":
            n = struct.unpack_from("<I", data, pos)[0]; pos += 4
            raw = data[pos:pos + n]
            return (raw.decode("utf-8", "replace") if t == "S" else raw), pos + n
        raise ValueError(f"unknown FBX property type {t!r}")

    def read_node(pos):
        header = "<QQQ" if wide else "<III"
        end, prop_count, _ = struct.unpack_from(header, data, pos)
        pos += struct.calcsize(header)
        name_len = data[pos]; pos += 1
        name = data[pos:pos + name_len].decode(); pos += name_len
        if end == 0:
            return None, pos
        props = []
        for _ in range(prop_count):
            value, pos = read_prop(pos)
            props.append(value)
        children = []
        while pos < end:
            child, pos = read_node(pos)
            if child is None:
                break
            children.append(child)
        return (name, props, children), end

    nodes, pos = [], 27
    while pos < len(data) - 160:
        node, pos = read_node(pos)
        if node is None:
            break
        nodes.append(node)
    return nodes


def find(nodes, name):
    for node in nodes:
        if node[0] == name:
            yield node
        yield from find(node[2], name)


def child(node, name):
    return next((c for c in node[2] if c[0] == name), None)


def object_name(node):
    return node[1][1].split("\x00")[0]


def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    s = 12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055
    return round(s * 255)


def load(path):
    """Returns (materials [(name, (r, g, b))] in mesh index order, faces [(material_index, [(pos, normal)])])."""
    nodes = parse_fbx(path)
    objects = next(find(nodes, "Objects"))
    geometries = [n for n in objects[2] if n[0] == "Geometry"]
    models = [n for n in objects[2] if n[0] == "Model"]
    if len(geometries) != 1 or len(models) != 1:
        sys.exit(f"{path}: expected exactly one mesh, found {len(geometries)}")
    geometry, model = geometries[0], models[0]

    material_nodes = {n[1][0]: n for n in objects[2] if n[0] == "Material"}
    materials = []
    for connection in find(nodes, "C"):
        kind, source, target = connection[1][:3]
        if kind == "OO" and target == model[1][0] and source in material_nodes:
            node = material_nodes[source]
            color = (0.8, 0.8, 0.8)
            for prop in find(node[2], "P"):
                if prop[1][0] in ("DiffuseColor", "Diffuse"):
                    color = tuple(prop[1][-3:])
                    break
            materials.append((object_name(node), tuple(linear_to_srgb(c) for c in color)))

    # Bake the model's rotation and scale so the OBJ comes out Y-up like it does in Studio.
    rotation, scale = (0.0, 0.0, 0.0), (1.0, 1.0, 1.0)
    for prop in find(model[2], "P"):
        if prop[1][0] == "Lcl Rotation":
            rotation = tuple(prop[1][-3:])
        elif prop[1][0] == "Lcl Scaling":
            scale = tuple(prop[1][-3:])

    def transform(v, apply_scale=True):
        x, y, z = (v[i] * (scale[i] if apply_scale else 1) for i in range(3))
        rx, ry, rz = (math.radians(a) for a in rotation)  # FBX default order: X, then Y, then Z
        y, z = y * math.cos(rx) - z * math.sin(rx), y * math.sin(rx) + z * math.cos(rx)
        x, z = x * math.cos(ry) + z * math.sin(ry), -x * math.sin(ry) + z * math.cos(ry)
        x, y = x * math.cos(rz) - y * math.sin(rz), x * math.sin(rz) + y * math.cos(rz)
        return (x, y, z)

    vertices = child(geometry, "Vertices")[1][0]
    positions = [transform(vertices[i:i + 3]) for i in range(0, len(vertices), 3)]
    indices = child(geometry, "PolygonVertexIndex")[1][0]

    normals = None
    normal_layer = child(geometry, "LayerElementNormal")
    if normal_layer and child(normal_layer, "MappingInformationType")[1][0] == "ByPolygonVertex":
        raw = child(normal_layer, "Normals")[1][0]
        values = [transform(raw[i:i + 3], apply_scale=False) for i in range(0, len(raw), 3)]
        if child(normal_layer, "ReferenceInformationType")[1][0] == "IndexToDirect":
            values = [values[i] for i in child(normal_layer, "NormalsIndex")[1][0]]
        normals = values

    material_layer = child(geometry, "LayerElementMaterial")
    per_polygon = material_layer and child(material_layer, "MappingInformationType")[1][0] == "ByPolygon"
    material_indices = child(material_layer, "Materials")[1][0] if material_layer else [0]

    faces, corners, polygon = [], [], 0
    for corner_index, index in enumerate(indices):
        last = index < 0
        corners.append((~index if last else index, normals[corner_index] if normals else None))
        if last:
            faces.append((material_indices[polygon] if per_polygon else material_indices[0], corners))
            corners, polygon = [], polygon + 1
    return materials, positions, faces


def split(fbx_path):
    materials, positions, faces = load(fbx_path)
    # FBX units here are centimeters; glTF uses meters.
    positions = [(x / 100, y / 100, z / 100) for x, y, z in positions]

    binary = bytearray()
    buffer_views, accessors, meshes, nodes, gltf_materials = [], [], [], [], []

    def add_view(data, target):
        while len(binary) % 4:
            binary.append(0)
        buffer_views.append({"buffer": 0, "byteOffset": len(binary), "byteLength": len(data), "target": target})
        binary.extend(data)
        return len(buffer_views) - 1

    for material_index, (name, srgb) in enumerate(materials):
        vertex_ids, vertex_data, triangle_indices = {}, [], []
        for m, corners in faces:
            if m != material_index:
                continue
            ids = []
            for vertex, normal in corners:
                key = (vertex, normal)
                if key not in vertex_ids:
                    vertex_ids[key] = len(vertex_data)
                    vertex_data.append((positions[vertex], normal))
                ids.append(vertex_ids[key])
            for i in range(1, len(ids) - 1):  # fan-triangulate quads/ngons
                triangle_indices += [ids[0], ids[i], ids[i + 1]]
        if not triangle_indices:
            continue

        points = [p for p, _ in vertex_data]
        position_view = add_view(struct.pack(f"<{len(points) * 3}f", *[c for p in points for c in p]), 34962)
        accessors.append({
            "bufferView": position_view, "componentType": 5126, "count": len(points), "type": "VEC3",
            "min": [min(p[i] for p in points) for i in range(3)], "max": [max(p[i] for p in points) for i in range(3)],
        })
        attributes = {"POSITION": len(accessors) - 1}

        if all(n for _, n in vertex_data):
            unit = []
            for _, (x, y, z) in vertex_data:
                length = math.sqrt(x * x + y * y + z * z) or 1
                unit += [x / length, y / length, z / length]
            normal_view = add_view(struct.pack(f"<{len(unit)}f", *unit), 34962)
            accessors.append({"bufferView": normal_view, "componentType": 5126, "count": len(vertex_data), "type": "VEC3"})
            attributes["NORMAL"] = len(accessors) - 1

        index_view = add_view(struct.pack(f"<{len(triangle_indices)}I", *triangle_indices), 34963)
        accessors.append({"bufferView": index_view, "componentType": 5125, "count": len(triangle_indices), "type": "SCALAR"})

        linear = [((c / 255 + 0.055) / 1.055) ** 2.4 if c / 255 > 0.04045 else c / 255 / 12.92 for c in srgb]
        gltf_materials.append({"name": name, "pbrMetallicRoughness": {"baseColorFactor": linear + [1.0], "metallicFactor": 0.0, "roughnessFactor": 0.9}})
        meshes.append({"name": name, "primitives": [{"attributes": attributes, "indices": len(accessors) - 1, "material": len(gltf_materials) - 1}]})
        nodes.append({"name": name, "mesh": len(meshes) - 1})
        print(f"  {name}: {len(triangle_indices) // 3} triangles")

    while len(binary) % 4:
        binary.append(0)
    document = {
        "asset": {"version": "2.0", "generator": "tools/fbx_materials.py"},
        "scene": 0,
        "scenes": [{"name": Path(fbx_path).stem, "nodes": list(range(len(nodes)))}],
        "nodes": nodes, "meshes": meshes, "materials": gltf_materials,
        "accessors": accessors, "bufferViews": buffer_views, "buffers": [{"byteLength": len(binary)}],
    }
    json_chunk = json.dumps(document, separators=(",", ":")).encode()
    json_chunk += b" " * (-len(json_chunk) % 4)
    total = 12 + 8 + len(json_chunk) + 8 + len(binary)
    out = Path(fbx_path).with_suffix(".glb")
    out.write_bytes(
        struct.pack("<4sII", b"glTF", 2, total)
        + struct.pack("<I4s", len(json_chunk), b"JSON") + json_chunk
        + struct.pack("<I4s", len(binary), b"BIN\0") + bytes(binary)
    )
    print(f"wrote {out}")


def colorize(fbx_path, rbxmx_path):
    materials, _, _ = load(fbx_path)
    colors = dict(materials)
    text = Path(rbxmx_path).read_text()
    item_pattern = re.compile(r'(<Item class="MeshPart"[^>]*>\s*<Properties>)(.*?)(</Properties>)', re.S)
    colored = []

    def recolor(match):
        props = match.group(2)
        name = re.search(r'<string name="Name">([^<]*)</string>', props).group(1)
        # Exact name first; otherwise the longest material name contained in the part name.
        key = name if name in colors else max((k for k in colors if k in name), key=len, default=None)
        if key is None:
            print(f"  ! no material matches part {name!r}; left unchanged")
            return match.group(0)
        r, g, b = colors[key]
        packed = 0xFF000000 | (r << 16) | (g << 8) | b
        props = re.sub(r'<Color3uint8 name="Color3uint8">\d+</Color3uint8>', "", props)
        props = f'\n\t\t\t<Color3uint8 name="Color3uint8">{packed}</Color3uint8>' + props
        colored.append(f"{name} -> {key} {colors[key]}")
        return match.group(1) + props + match.group(3)

    text = item_pattern.sub(recolor, text)
    Path(rbxmx_path).write_text(text)
    print("\n".join(f"  {line}" for line in colored) or "  no MeshParts found")
    print(f"updated {rbxmx_path}")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "split":
        split(sys.argv[2])
    elif len(sys.argv) == 4 and sys.argv[1] == "colorize":
        colorize(sys.argv[2], sys.argv[3])
    else:
        sys.exit(__doc__)
