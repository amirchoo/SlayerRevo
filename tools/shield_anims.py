"""Generates the R15 KeyframeSequence .rbxmx for blocking with a shield (ShieldGuard): the
left forearm raised across the chest so the shield on it faces forward, the weapon held
ready low at the right side. One pose for every one-handed weapon (see ShieldConfig).

    python3 tools/shield_anims.py assets/animations

Built on tools/sword_anims.py (see its notes on joint frames). The shield is worn on the
outside of the left forearm (its local -X; see src/server/ShieldService.luau), so the
forearm is aimed with that side facing forward. Publish it, then put its id in
ShieldConfig.GuardAnimation in src/shared/Config/ShieldConfig.luau.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sword_anims as lib  # noqa: E402
from sword_anims import pose, norm, cross, dot, matmul, apply, rx, ry  # noqa: E402

FORWARD = (0, 0, -1)
LEFT = (-1, 0, 0)


def limb(down, outside):
    """Rotation whose local -Y (along the limb) is `down` and whose local -X (the outside of a
    left arm) is as close to `outside` as possible."""
    d = norm(down)
    o = norm(tuple(outside[i] - dot(outside, d) * d[i] for i in range(3)))
    y = tuple(-c for c in d)
    x = tuple(-c for c in o)
    z = cross(x, y)
    return [[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]]


def transpose(m):
    return [list(row) for row in zip(*m)]


_base_rotations = lib.joint_rotations


def joint_rotations(p):
    """sword_anims' joints, with the left arm bent to hold the shield when a pose has one:
    "shield" = (upper arm direction, forearm direction), in chest space."""
    r = _base_rotations(p)
    if p.get("shield"):
        upper_dir, fore_dir = p["shield"]
        upper = limb(upper_dir, LEFT)
        fore = limb(fore_dir, FORWARD)  # the shield side faces forward
        r["LeftUpperArm"] = upper
        r["LeftLowerArm"] = matmul(transpose(upper), fore)
    return r


lib.joint_rotations = joint_rotations


def shield_pose(lean=0, **extra):
    p = pose(lean=lean, **extra)
    p["shield"] = SHIELD_ARM
    return p


# Upper arm forward and a little down, forearm across the chest toward the right, rising slightly.
SHIELD_ARM = ((0.1, -0.3, -0.95), (0.93, 0.12, -0.35))
# Left shoulder leading; the weapon held low at the right side, pointing ahead.
GUARD = {"chest": -20, "arm": (0.45, -0.75, -0.45), "wrist": -20, "blade_lean": (0.15, 0.45, -0.9)}

ANIMATIONS = {
    "ShieldGuard": {  # looping block stance; upper body only, so the legs keep walking
        "hit": None,
        "loop": True,
        "upper_body_only": True,
        "plane": None,
        "keys": [
            (0.0, shield_pose(lean=0, **GUARD)),
            (0.6, shield_pose(lean=-4, **GUARD)),
            (1.2, shield_pose(lean=0, **GUARD)),
        ],
    },
}


def main(out_dir):
    lib.SWINGS = ANIMATIONS
    lib.main(out_dir)
    # Where the shield faces (the forearm's -X) in character space: should be about forward (-Z).
    _, p = ANIMATIONS["ShieldGuard"]["keys"][0]
    r = joint_rotations(p)
    chest = matmul(ry(p["hips"]), matmul(ry(p["chest"]), rx(p["lean"])))
    fore = matmul(matmul(chest, r["LeftUpperArm"]), r["LeftLowerArm"])
    face = apply(fore, (-1, 0, 0))
    print("shield faces " + lib.fmt(face) + ", forearm along " + lib.fmt(apply(fore, (0, -1, 0))))


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
