"""Generates the R15 KeyframeSequence .rbxmx files for fighting with a shield: an idle and a
guard (block) for each one-handed weapon (see ShieldConfig.Stances), plus ShieldGuard, the
generic guard used when a weapon has none of its own.

    python3 tools/shield_anims.py assets/animations

Built on tools/sword_anims.py (see its notes on joint frames). The shield is worn on the
outside of the left forearm (its local -X; see src/server/ShieldService.luau), so the forearm
is aimed with that side facing where the shield should face. All of them are upper body only,
so the legs keep walking. Publish them, then put their ids in ShieldConfig.Stances in
src/shared/Config/ShieldConfig.luau.

Each pose prints where the shield faces and the rough clearances (in chest space, studs) between
the shield, the weapon and the body, from an approximate R15 rig: check nothing is negative.
"""
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sword_anims as lib  # noqa: E402
from sword_anims import pose, norm, cross, dot, matmul, apply  # noqa: E402

UP = (0, 1, 0)
FORWARD = (0, 0, -1)
BACK = (0, 0, 1)
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
    "shield" = (upper arm direction, forearm direction, where the shield faces), in chest space."""
    r = _base_rotations(p)
    if p.get("shield"):
        upper_dir, fore_dir, facing = p["shield"]
        upper = limb(upper_dir, LEFT)
        fore = limb(fore_dir, facing)
        r["LeftUpperArm"] = upper
        r["LeftLowerArm"] = matmul(transpose(upper), fore)
    return r


lib.joint_rotations = joint_rotations


def shield_pose(arm_pose, **extra):
    """A sword_anims pose with the shield arm ("shield" as in joint_rotations)."""
    p = pose(**extra)
    p["shield"] = arm_pose
    return p


# --- shield arm poses: (upper arm, forearm, shield facing), chest space ----------------------
# Generic block: upper arm forward and a little down, forearm across the chest toward the
# right, rising slightly, the shield facing forward.
SHIELD_ARM = ((0.1, -0.3, -0.95), (0.93, 0.12, -0.35), FORWARD)
# Relaxed at the side: elbow bent, forearm forward, the shield facing out to the left.
AT_SIDE = ((-0.15, -0.97, -0.15), (0.1, -0.15, -0.98), (-1, 0, -0.35))
# Ready in front of the belly: forearm angled across, the shield turned half forward.
HALF_FRONT = ((0.05, -0.9, -0.45), (0.75, 0.05, -0.65), (-0.5, 0, -1))
# Raised high across the chest, top edge at the eyes (a heavier, rounder cover than SHIELD_ARM).
HIGH_COVER = ((0.15, -0.1, -1), (0.9, 0.35, -0.25), FORWARD)
# Buckler style: the arm pushed out front, forearm upright, the shield held off the body.
OUT_FRONT_LOW = ((0.05, -0.55, -0.85), (0.2, 0.95, -0.15), FORWARD)
OUT_FRONT_HIGH = ((0.1, -0.05, -1), (0.25, 0.95, 0.05), FORWARD)

# --- weapon arm poses ---------------------------------------------------------------------------

def aim(arm, blade):
    """sword_anims arm/wrist/blade_lean for the arm along `arm` with the weapon pointing along
    `blade` (both chest space). The blade turns in the plane of the arm and `blade`, so the
    wrist bends -90 (carrying on the arm's line) to +90 (back toward the shoulder)."""
    a, b = norm(arm), norm(blade)
    along = dot(b, a)
    lean = norm(tuple(b[i] - along * a[i] for i in range(3)))
    return {"arm": arm, "wrist": round(math.degrees(math.asin(-along)), 1), "blade_lean": lean}


# Sword: low at the right hip, point forward and a little up.
SWORD_LOW = aim((0.35, -0.85, -0.4), (0.1, 0.15, -1))
# Sword out at the right shoulder, point forward over the shield's rim (ready to stab).
SWORD_OVER = aim((0.8, 0.3, 0.25), (-0.1, -0.1, -1))
# Mace hanging heavy at the side, its head forward and down.
MACE_LOW = aim((0.25, -0.95, -0.15), (0.2, -0.7, -0.7))
# Mace raised behind the shield, its head up over the right shoulder (ready to come down).
MACE_RAISED = aim((0.75, 0.35, 0.45), (0.1, 0.75, 0.65))
# Axe held low in front of the right thigh, head forward (like AxeIdle).
AXE_LOW = aim((0.3, -0.85, -0.4), (0.25, -0.6, -0.75))
# Axe hooked back at the right side, haft rising forward, ready to chop past the shield's edge.
AXE_HOOKED = aim((0.85, -0.2, 0.35), (0, 0.85, -0.5))
# Rapier en garde, point up toward the eyes (as RapierIdle, with less twist).
RAPIER_GARDE = aim((0.45, -0.45, -0.75), (0.1, 0.35, -0.93))
# Rapier drawn back high, point aimed past the buckler (a thrust waiting to go).
RAPIER_DRAWN = aim((0.7, 0.45, 0.4), (-0.15, -0.15, -1))

RAPIER_TWIST = 15  # chest turned a little left: the sword side leads, the buckler still in front


def stance(arm_pose, weapon, chest=0, lean=0, head=(0, 0), larm=0, breathe=(-4, 0, 0), wrist_breathe=2, period=1.2):
    """A looping, upper-body-only stance that breathes: leans by breathe[0], twists the chest by
    breathe[1] and lifts the shield by breathe[2] (degrees of forearm rise) halfway through."""
    upper, fore, facing = arm_pose
    lifted_fore = norm((fore[0], fore[1] + math.sin(math.radians(breathe[2])), fore[2]))
    weapon2 = {**weapon, "wrist": weapon["wrist"] + wrist_breathe}
    return {
        "hit": None, "loop": True, "upper_body_only": True, "plane": None,
        "keys": [
            (0.0, shield_pose(arm_pose, chest=chest, lean=lean, head=head, **weapon)),
            (period / 2, shield_pose((upper, lifted_fore, facing), chest=chest + breathe[1], lean=lean + breathe[0],
                                     head=head, **weapon2)),
            (period, shield_pose(arm_pose, chest=chest, lean=lean, head=head, **weapon)),
        ],
    }


# Weapon lengths and grip points, for the clearance check (from ModelFit in CombatConfig).
WEAPONS = {"Sword": (5.2, 0.11), "Mace": (4.4, 0.14), "Axe": (3.8, 0.22), "Rapier": (5.2, 0.08)}

ANIMATIONS = {
    # Generic guard (ShieldConfig.GuardAnimation): a weapon with no stance of its own uses it.
    "ShieldGuard": stance(SHIELD_ARM, {"arm": (0.45, -0.75, -0.45), "wrist": -20, "blade_lean": (0.15, 0.45, -0.9)},
                          chest=-20, breathe=(-4, 0, 0), wrist_breathe=0),
    # Sword and board: shield half-forward at the belly, sword low and ready at the hip.
    "SwordShieldIdle": stance(HALF_FRONT, SWORD_LOW, chest=-10, breathe=(-3, 0, 4), period=1.6),
    # Shield up and leading (left shoulder forward), the sword cocked back over its rim.
    "SwordShieldGuard": stance(SHIELD_ARM, SWORD_OVER, chest=-25, lean=-6, breathe=(-3, 0, 3)),
    # Mace: square and heavy, shield at the side, mace hanging.
    "MaceShieldIdle": stance(AT_SIDE, MACE_LOW, breathe=(-3, 0, 4), period=1.8),
    # Hunkered behind a high shield, mace raised over the shoulder to crash down.
    "MaceShieldGuard": stance(HIGH_COVER, MACE_RAISED, chest=-15, lean=-12, head=(8, 0), breathe=(-3, 0, 3)),
    # Axe: shield half-forward, axe low and forward.
    "AxeShieldIdle": stance(HALF_FRONT, AXE_LOW, chest=-5, breathe=(-3, 0, 4), period=1.6),
    # Shield up, axe hooked back at the side ready to chop past its edge.
    "AxeShieldGuard": stance(SHIELD_ARM, AXE_HOOKED, chest=-20, lean=-8, breathe=(-3, 0, 3)),
    # Rapier and buckler: en garde, the buckler held out in front.
    "RapierShieldIdle": stance(OUT_FRONT_LOW, RAPIER_GARDE, chest=RAPIER_TWIST, breathe=(-3, 0, 4), period=1.8),
    # Buckler punched out at face height, the rapier drawn back to thrust past it.
    "RapierShieldGuard": stance(OUT_FRONT_HIGH, RAPIER_DRAWN, chest=RAPIER_TWIST, lean=-5, breathe=(-3, 0, 3)),
}

# --- clearance check (approximate R15 block rig, chest space) ---------------------------------
L_SHOULDER = (-1.5, 0.55, 0)
R_SHOULDER = (1.5, 0.55, 0)
UPPER_ARM = 0.75  # shoulder to elbow
ARM_REACH = 1.9  # shoulder to the grip, arm straight
SHIELD_RADIUS = 1.3
SHIELD_OUT = 0.7  # forearm axis to the shield's middle
SHIELD_ALONG = 0.6  # elbow to the shield's middle, along the forearm
BODY_BOXES = [((-1, -0.8, -0.5), (1, 0.8, 0.5)), ((-1, -1.2, -0.5), (1, -0.8, 0.5))]  # upper, lower torso
HEAD = ((0, 1.35, 0), 0.6)


def add(a, b, s=1.0):
    return tuple(a[i] + b[i] * s for i in range(3))


def box_gap(point, box):
    lo, hi = box
    outside = [max(lo[i] - point[i], 0, point[i] - hi[i]) for i in range(3)]
    if any(outside):
        return math.sqrt(sum(c * c for c in outside))
    return -min(min(point[i] - lo[i], hi[i] - point[i]) for i in range(3))


def body_gap(point):
    center, radius = HEAD
    return min([box_gap(point, box) for box in BODY_BOXES] + [math.dist(point, center) - radius])


def check(name, p, weapon):
    r = joint_rotations(p)
    upper = r["LeftUpperArm"]
    fore = matmul(upper, r["LeftLowerArm"])
    along, face = apply(fore, (0, -1, 0)), apply(fore, (-1, 0, 0))
    elbow = add(L_SHOULDER, apply(upper, (0, -1, 0)), UPPER_ARM)
    center = add(add(elbow, along, SHIELD_ALONG), face, SHIELD_OUT)
    # Points around the shield's rim and across its face.
    side = cross(face, along)
    disc = [center] + [add(add(center, along, f * math.cos(a)), side, f * math.sin(a))
                       for f in (0.5 * SHIELD_RADIUS, SHIELD_RADIUS) for a in [i * math.pi / 8 for i in range(16)]]
    shield_body = min(body_gap(q) for q in disc)

    arm = apply(r["RightUpperArm"], (0, -1, 0))
    blade = apply(matmul(r["RightUpperArm"], r["RightHand"]), (0, 0, -1))
    grip = add(R_SHOULDER, arm, ARM_REACH)
    length, grip_from = WEAPONS[weapon]
    weapon_points = [add(grip, blade, length * (t / 20 - grip_from)) for t in range(21)]
    weapon_body = min(body_gap(q) for q in weapon_points)
    weapon_shield = min(
        max(abs(dot(tuple(q[i] - center[i] for i in range(3)), face)) - 0.15,
            math.dist(q, center) - SHIELD_RADIUS)
        for q in weapon_points
    )
    world = lib.matmul(lib.ry(p["chest"]), lib.rx(p["lean"]))
    print(f"  {name}: shield faces {lib.fmt(apply(world, face))} at {lib.fmt(apply(world, center))}, "
          f"blade {lib.fmt(apply(world, blade))}; clearance shield-body {shield_body:+.2f}, "
          f"weapon-body {weapon_body:+.2f}, weapon-shield {weapon_shield:+.2f}")


def main(out_dir):
    lib.SWINGS = ANIMATIONS
    lib.main(out_dir)
    print("== clearances")
    for name, animation in ANIMATIONS.items():
        weapon = next((w for w in WEAPONS if name.startswith(w)), "Sword")
        check(name, animation["keys"][0][1], weapon)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
