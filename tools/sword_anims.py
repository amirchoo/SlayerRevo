"""Generates R15 KeyframeSequence .rbxmx files for the sword: the 3-hit combo, the
looping guard (block) stance, and the looping heavy spin, all full body.

    python3 tools/sword_anims.py assets/animations

Edit SWINGS below, re-run, then in Studio copy them onto the rig's AnimSaves, load them
in the Clip Editor, and publish. Keep each swing's "hit" time in sync with HitDelay in
src/shared/Config/CombatConfig.luau.

Easing (how a keyframe moves on to the next): a key can be (time, pose, ease) with ease one
of the EASE_* below; without one it's a smooth in-and-out. Strikes read best (the feel of a
dueling game) as: settle into the wind-up (EASE_SETTLE), whip into the hit (EASE_WHIP),
carry through and stop hard (EASE_SETTLE), hold the finished pose a moment (EASE_HOLD), then
recover to the ready stance. See SwordSwing1-3.

Joint frames (R15): X right, Y up, Z back (forward is -Z). A Pose's CFrame is the joint's
Transform: the child part's rotation (and, for the hips/LowerTorso, offset) relative to
its parent. Arms and legs hang along local -Y; Rx(+a) swings a limb forward, Rx(-a) bends
a knee back. The sword (via the tool Grip) points along the hand's local -Z, so with the
wrist flexed by w the blade is along forearm-local (0, sin w, -cos w).
"""
import math
import sys
from pathlib import Path


# --- small 3D math helpers ---------------------------------------------------------

def norm(v):
    length = math.sqrt(sum(c * c for c in v))
    return tuple(c / length for c in v)


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def dot(a, b):
    return sum(x * y for x, y in zip(a, b))


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def apply(m, v):
    return tuple(sum(m[i][k] * v[k] for k in range(3)) for i in range(3))


def rx(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[1, 0, 0], [0, c, -s], [0, s, c]]


def ry(deg):
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return [[c, 0, s], [0, 1, 0], [-s, 0, c]]


def identity():
    return [[1, 0, 0], [0, 1, 0], [0, 0, 1]]


def turn_angle(a, b):
    r = matmul([list(row) for row in zip(*a)], b)
    return math.degrees(math.acos(max(-1, min(1, (r[0][0] + r[1][1] + r[2][2] - 1) / 2))))


def aim_arm(direction, lean):
    """Rotation taking the hanging arm (-Y) to `direction`, with the arm's local -Z (where
    the blade leans) turned as close to `lean` as possible."""
    d = norm(direction)
    u = norm(tuple(lean[i] - dot(lean, d) * d[i] for i in range(3)))
    y = tuple(-c for c in d)
    z = tuple(-c for c in u)
    x = cross(y, z)
    return [[x[0], y[0], z[0]], [x[1], y[1], z[1]], [x[2], y[2], z[2]]]


# --- poses -----------------------------------------------------------------------------

STAND = (0, 0, 0)  # leg: (hip, knee, ankle) degrees

# Easings, as (PoseEasingStyle, PoseEasingDirection): how a keyframe moves on to the next.
# CubicV2 (5) is the one whose In/Out mean what they say (the old Cubic's are swapped).
EASE_SMOOTH = (3, 2)  # Cubic InOut: starts and ends gently (the default)
EASE_WHIP = (5, 0)  # CubicV2 In: starts slow, arrives fastest (into a hit)
EASE_SETTLE = (5, 1)  # CubicV2 Out: leaves fast, eases to a stop (wind-ups, follow-throughs)
EASE_HOLD = (0, 0)  # Linear, between two near-equal poses: a held pose that barely creeps
EASE_LINEAR = (0, 0)  # Linear (resampled keys, see overlapped)


def pose(arm=None, wrist=-60, chest=0, hips=0, lean=0, drop=0.0, larm=0, lelbow=20, lleg=STAND, rleg=STAND, blade_lean=None,
         head_forward=True, head=(0, 0), larm_yaw=0, larm_dir=None, lwrist=0, lblade_lean=None, elbow=0):
    """One full-body pose.
    arm: right-arm direction in chest space (None = hanging). wrist: wrist flex.
    chest / hips: twist in degrees (+ = turn left). lean: chest lean (+ = back).
    drop: how far the hips sink, in studs (negative = rise, e.g. a hop).
    larm / lelbow: left arm swing and elbow bend. lleg / rleg: (hip, knee, ankle).
    blade_lean: fixed direction for the blade's lean instead of following a swing plane
    (with wrist=0 the blade points straight along it).
    head_forward: counter-turn the head so it keeps facing forward through twists
    (False for spins, where the head should turn with the body).
    head: (pitch, yaw) on top of that, in degrees (+ = look up / look left).
    larm_yaw: turns the left arm's swing across the body (- = toward the right).
    larm_dir / lwrist / lblade_lean: aim the left arm like the right (for a blade in the left
    hand; its swing plane is the animation's "lplane"). When set, larm / lelbow are ignored.
    elbow: right elbow bend in degrees: + folds the forearm toward the blade's side (ahead along
    the swing), - folds it back (the blade trails behind: a sword cocked behind the head on a
    wind-up), straightening as it strikes."""
    return {
        "arm": arm, "wrist": wrist, "chest": chest, "hips": hips, "lean": lean, "drop": drop,
        "larm": larm, "lelbow": lelbow, "lleg": lleg, "rleg": rleg, "blade_lean": blade_lean,
        "head_forward": head_forward, "head": head, "larm_yaw": larm_yaw,
        "larm_dir": larm_dir, "lwrist": lwrist, "lblade_lean": lblade_lean, "elbow": elbow,
    }


NEUTRAL = pose(wrist=0, lelbow=0)

# Footwork building blocks. A foot stays flat when ankle = -(hip + knee).
READY = {"drop": 0.15, "lleg": (12, -24, 12), "rleg": (12, -24, 12)}
LUNGE_LEFT = {"drop": 0.5, "lleg": (45, -55, 10), "rleg": (-25, -20, 45)}  # left foot forward
LUNGE_RIGHT = {"drop": 0.5, "lleg": (-25, -20, 45), "rleg": (45, -55, 10)}  # right foot forward
COIL_BACK = {"drop": 0.35, "lleg": (30, -45, 15), "rleg": (20, -45, 25)}  # weight on the back leg
TUCKED = {"drop": -0.7, "lleg": (50, -85, 35), "rleg": (40, -75, 35)}  # in the air
DEEP_LUNGE = {"drop": 0.95, "lleg": (70, -95, 25), "rleg": (-15, -110, 70)}  # back knee near the ground

# Guard: sword held level across the chest, blade pointing left, left hand bracing it,
# chest angled sideways. Upper body only, so the legs keep walking while blocking.
# Breathes a little so a long block isn't frozen.
# Spin (heavy attack): low wide stance, sword arm held out to the right with the blade
# extending it and leaning into the spin. The hips turn a full circle per loop in 120°
# steps (each step blends the short way, so the spin keeps going the same direction).
SPIN_TIME = 0.5  # one full turn; matches Sword.Heavy.TickInterval (one hit per spin)
SPIN_BODY = {"arm": (1, -0.05, -0.25), "wrist": -55, "blade_lean": (0, 0, -1), "chest": 10, "lean": -10,
             "larm": 25, "lelbow": 60, "drop": 0.4, "lleg": (20, -40, 20), "rleg": (20, -40, 20),
             "head_forward": False}

# Mace ground pound: the swing plane runs from overhead (tipped back) down to the ground in front.
MACE_PLANE = ((0.1, 0.95, 0.35), (0.05, 0, -1))
MACE_RAISED_ARM = {"arm": (0.12, 0.95, 0.4), "wrist": -80, "larm": 70, "lelbow": 45}  # head tipped back over the head
KNEEL = {"drop": 1.0, "lleg": (75, -100, 25), "rleg": (5, -120, 85)}  # right knee near the ground

GUARD_ARM = {"arm": (0.25, -0.1, -1), "wrist": 0, "blade_lean": (-1, 0.15, 0), "chest": -25, "larm": 65, "lelbow": 70}

# (time, pose). Each swing's "plane" is two arm directions it sweeps between; the blade
# leans along that motion so the arm's twist stays consistent between keyframes.
SWINGS = {
    # Swings 1-3 (after Dueling Grounds' katana): a deliberate wind-up (about a quarter second,
    # the sword cocked with the elbow bent, held a beat so it reads), a strike that whips
    # through a big arc and ends with the arm fully out to the side, held, then back to the
    # ready stance. "overlap" spreads it through the whole body (hips lead, the blade whips
    # last; see overlapped). Hit times match HitDelay in CombatConfig.
    "SwordSwing1": {  # forehand: cock over the right shoulder, sweep across and out to the far left
        "hit": 0.26,
        "overlap": True,
        "plane": ((0.6, 0.8, 0.25), (0.15, 0.3, -1)),
        "keys": [
            (0.00, pose(arm=(0.3, -0.6, -0.75), wrist=-40, elbow=0, **READY), EASE_SETTLE),
            (0.14, pose(arm=(0.6, 0.8, 0.25), elbow=-70, wrist=-50, chest=-40, hips=-22, lean=5, larm=45, lelbow=60,
                        **COIL_BACK), EASE_HOLD),  # cocked, held a beat
            (0.20, pose(arm=(0.62, 0.82, 0.3), elbow=-80, wrist=-50, chest=-45, hips=-25, lean=8, larm=50, lelbow=60,
                        **COIL_BACK), EASE_WHIP),
            (0.26, pose(arm=(0.15, 0.3, -1), elbow=10, chest=5, hips=12, lean=-12, larm=0, lelbow=30,
                        **LUNGE_LEFT), EASE_SETTLE),  # the hit, mid-arc
            (0.32, pose(arm=(-0.8, 0.05, -0.6), elbow=0, chest=25, hips=12, lean=-16, larm=-55, lelbow=30,
                        **LUNGE_LEFT), EASE_HOLD),  # fully out to the left
            (0.50, pose(arm=(-0.8, 0.0, -0.62), elbow=5, chest=23, hips=11, lean=-15, larm=-50, lelbow=30,
                        **LUNGE_LEFT)),  # held
            (0.72, pose(arm=(0.3, -0.6, -0.75), wrist=-40, elbow=0, **READY)),  # back to the ready stance
        ],
    },
    "SwordSwing2": {  # backhand: cock across to the left shoulder, sweep back and out to the far right
        "hit": 0.24,
        "overlap": True,
        "plane": ((-0.9, 0.2, -0.2), (0.05, 0.1, -1)),
        "keys": [
            (0.00, pose(arm=(0.2, -0.5, -0.85), wrist=-40, elbow=0, **READY), EASE_SETTLE),
            (0.13, pose(arm=(-0.9, 0.2, -0.2), elbow=-75, chest=40, hips=18, lean=5, larm=-40, lelbow=50,
                        **COIL_BACK), EASE_HOLD),  # cocked, held a beat
            (0.18, pose(arm=(-0.92, 0.22, -0.15), elbow=-85, chest=44, hips=20, lean=8, larm=-42, lelbow=50,
                        **COIL_BACK), EASE_WHIP),
            (0.24, pose(arm=(0.05, 0.1, -1), elbow=10, chest=0, hips=-12, lean=-12, larm=0, lelbow=30,
                        **LUNGE_RIGHT), EASE_SETTLE),  # the hit, mid-arc
            (0.30, pose(arm=(0.8, 0.05, -0.6), elbow=0, chest=-25, hips=-12, lean=-14, larm=50, lelbow=30,
                        **LUNGE_RIGHT), EASE_HOLD),  # fully out to the right
            (0.48, pose(arm=(0.8, 0.0, -0.62), elbow=5, chest=-23, hips=-11, lean=-13, larm=45, lelbow=30,
                        **LUNGE_RIGHT)),  # held
            (0.70, pose(arm=(0.2, -0.5, -0.85), wrist=-40, elbow=0, **READY)),  # back to the ready stance
        ],
    },
    "SwordGuard": {  # looping block stance (no hit; loops while the player holds block)
        "hit": None,
        "loop": True,
        "upper_body_only": True,
        "plane": None,
        "keys": [
            (0.0, pose(lean=0, **GUARD_ARM)),
            (0.6, pose(lean=-4, **GUARD_ARM)),
            (1.2, pose(lean=0, **GUARD_ARM)),
        ],
    },
    "SwordSwing3": {  # leaping overhead slam: sink low, spring up with the sword cocked behind the head, crash down
        "hit": 0.40,
        "overlap": True,
        "plane": ((0.1, 0.95, 0.3), (0.05, 0.5, -0.85)),
        "keys": [
            (0.00, pose(arm=(0.2, -0.5, -0.85), wrist=-40, elbow=0, **READY), EASE_SETTLE),
            (0.14, pose(arm=(0.2, -0.5, -0.85), wrist=-40, elbow=-25, lean=12, drop=0.6, larm=-20,
                        lleg=(45, -85, 40), rleg=(45, -85, 40)), EASE_SETTLE),  # sink before the jump
            (0.28, pose(arm=(0.1, 0.95, 0.3), elbow=-60, lean=20, larm=70, lelbow=40, **TUCKED), EASE_HOLD),  # in the air, cocked
            (0.33, pose(arm=(0.1, 0.95, 0.35), elbow=-70, lean=23, larm=72, lelbow=40, **TUCKED), EASE_WHIP),  # then crash down
            (0.40, pose(arm=(0.05, -0.45, -0.9), elbow=0, lean=-30, larm=-25, **DEEP_LUNGE), EASE_HOLD),  # the hit, held
            (0.66, pose(arm=(0.05, -0.47, -0.88), elbow=5, lean=-32, larm=-27, **DEEP_LUNGE)),
            (0.92, pose(arm=(0.2, -0.5, -0.85), wrist=-40, elbow=0, **READY)),  # back to the ready stance
        ],
    },
    "SwordSpin": {  # heavy attack: loops while the player holds left-click
        "hit": None,
        "loop": True,
        "plane": None,
        "keys": [
            (0.0, pose(hips=0, **SPIN_BODY)),
            (SPIN_TIME / 3, pose(hips=120, **SPIN_BODY)),
            (SPIN_TIME * 2 / 3, pose(hips=240, **SPIN_BODY)),
            (SPIN_TIME, pose(hips=360, **SPIN_BODY)),
        ],
    },
    # Mace heavy (ground pound). The wind-up raises the mace high overhead and is held on its
    # last frame while charging; upper body only, so the legs can still shuffle.
    "MaceWindUp": {
        "hit": None,
        "upper_body_only": True,
        "plane": MACE_PLANE,
        "keys": [
            (0.00, pose(arm=(0.2, -0.5, -0.85), wrist=-40)),
            (0.15, pose(arm=(0.2, 0.3, -0.95), wrist=-50, lean=5, chest=-8, larm=40, lelbow=40)),
            (0.30, pose(**MACE_RAISED_ARM, lean=15, chest=-15)),
            (1.00, pose(**MACE_RAISED_ARM, lean=22, chest=-20)),  # tension builds
        ],
    },
    # Release: a small hop, then the mace crashes into the ground in front, dropping to one
    # knee. Keep "hit" in sync with Mace.Heavy.HitDelay in src/shared/Config/CombatConfig.luau.
    "MaceSlam": {
        "hit": 0.18,
        "plane": MACE_PLANE,
        "keys": [
            (0.00, pose(**MACE_RAISED_ARM, lean=22, chest=-20, **READY)),
            (0.07, pose(arm=(0.1, 0.9, -0.3), wrist=-30, lean=10, larm=60, lelbow=40, drop=-0.4,
                        lleg=(40, -60, 20), rleg=(30, -50, 20))),
            (0.13, pose(arm=(0.05, 0.2, -1), wrist=-40, lean=-10, larm=20, drop=0.2,
                        lleg=(45, -60, 15), rleg=(10, -50, 40))),
            (0.18, pose(arm=(0.05, 0, -1), wrist=-70, lean=-35, larm=-20, **KNEEL)),  # head in the ground
            (0.50, pose(arm=(0.05, 0, -1), wrist=-70, lean=-32, larm=-20, **KNEEL)),
            (0.80, NEUTRAL),
        ],
    },
    # Orc attack (no weapon: a claw swipe). Rears back with both arms up and holds it there,
    # straining further, as the parry/dodge cue; then snaps through in a few frames and lands
    # fully extended exactly on the hit (the pose hitstop freezes). "hit" matches the Orc's
    # AttackWindup in src/shared/Config/EnemyConfig.luau.
    "DemonClaw": {
        "hit": 0.4,
        "plane": ((0.35, 0.85, 0.4), (-0.35, -0.45, -0.8)),
        "keys": [
            (0.00, pose(arm=(0.15, -0.9, -0.3), wrist=0, larm=10, **READY)),
            (0.10, pose(arm=(0.35, 0.1, -0.95), wrist=-10, chest=-10, lean=5, larm=90, lelbow=30, **READY)),
            (0.20, pose(arm=(0.35, 0.85, 0.4), wrist=-20, chest=-25, hips=-10, lean=15, larm=165, lelbow=35, **COIL_BACK)),
            (0.34, pose(arm=(0.38, 0.8, 0.48), wrist=-25, chest=-30, hips=-12, lean=19, larm=170, lelbow=35, **COIL_BACK)),  # held, straining
            (0.37, pose(arm=(0.3, 0.6, -0.6), wrist=-30, chest=-5, lean=0, larm=130, lelbow=30, drop=0.3,
                        lleg=(35, -50, 15), rleg=(10, -35, 25))),
            (0.40, pose(arm=(-0.35, -0.45, -0.8), wrist=-40, chest=25, hips=10, lean=-20, larm=60, lelbow=40, **LUNGE_LEFT)),
            (0.65, pose(arm=(-0.4, -0.55, -0.7), wrist=-35, chest=22, hips=8, lean=-17, larm=50, lelbow=40, **LUNGE_LEFT)),
            (1.00, NEUTRAL),
        ],
    },
    # An enemy whose attack was parried: the claw arm is knocked wide up and back, the torso
    # thrown open, the head snapped back, a stagger step backward; held, wide open, for the
    # whole stun. 0.5 s long like Blocking.ParryStun (EnemyEffects.recoil stretches it to fit).
    "EnemyParried": {
        "hit": None,
        "plane": None,
        "keys": [
            (0.00, pose(arm=(0.3, 0.2, -0.95), wrist=0, blade_lean=(0, 0, -1), larm=60, lelbow=40, head_forward=False, **READY)),
            (0.05, pose(arm=(0.75, 0.75, 0.5), wrist=0, blade_lean=(0, 0, -1), chest=-22, lean=30, larm=-45, lelbow=55,
                        head=(32, 8), drop=0.3, lleg=(-22, -30, 52), rleg=(22, -42, 20), head_forward=False)),
            (0.12, pose(arm=(0.8, 0.7, 0.55), wrist=0, blade_lean=(0, 0, -1), chest=-25, lean=34, larm=-50, lelbow=60,
                        head=(36, 10), drop=0.35, lleg=(-24, -34, 58), rleg=(24, -46, 22), head_forward=False)),
            (0.30, pose(arm=(0.75, 0.72, 0.5), wrist=0, blade_lean=(0, 0, -1), chest=-23, lean=30, larm=-45, lelbow=55,
                        head=(30, 8), drop=0.32, lleg=(-22, -32, 54), rleg=(22, -44, 22), head_forward=False)),
            (0.50, pose(arm=(0.72, 0.72, 0.45), wrist=0, blade_lean=(0, 0, -1), chest=-22, lean=28, larm=-42, lelbow=55,
                        head=(28, 8), drop=0.3, lleg=(-22, -30, 52), rleg=(22, -42, 20), head_forward=False)),
        ],
    },
    # --- One-handed axe. Hit times match the Axe section of src/shared/Config/CombatConfig.luau.
    # The axe's edge faces where the hand leads (the game turns the model so it does), so each
    # chop leans along its swing like the sword's do.
    "AxeIdle": {  # held low in front, head forward; upper body only so the legs walk
        "hit": None,
        "loop": True,
        "upper_body_only": True,
        "plane": None,
        "keys": [
            (0.0, pose(arm=(0.25, -0.85, -0.45), wrist=-70, blade_lean=(0, 0, -1), larm=8)),
            (0.8, pose(arm=(0.25, -0.83, -0.48), wrist=-68, blade_lean=(0, 0, -1), larm=10, lean=-3)),
            (1.6, pose(arm=(0.25, -0.85, -0.45), wrist=-70, blade_lean=(0, 0, -1), larm=8)),
        ],
    },
    "AxeChop1": {  # diagonal chop from over the right shoulder down to the left hip
        "hit": 0.2,
        "plane": ((0.55, 0.8, 0.3), (0.1, 0.1, -1)),
        "keys": [
            (0.00, pose(arm=(0.3, -0.6, -0.75), wrist=-40, **READY)),
            (0.07, pose(arm=(0.55, 0.15, -0.8), wrist=-45, chest=-18, hips=-8, lean=4, larm=20, **COIL_BACK)),
            (0.13, pose(arm=(0.55, 0.8, 0.3), wrist=-50, chest=-35, hips=-15, lean=8, larm=40, **COIL_BACK)),
            (0.20, pose(arm=(0.1, 0.1, -1), wrist=-60, chest=0, hips=10, lean=-12, larm=0, **LUNGE_LEFT)),
            (0.26, pose(arm=(-0.45, -0.55, -0.75), wrist=-60, chest=28, hips=20, lean=-18, larm=-35, **LUNGE_LEFT)),
            (0.50, NEUTRAL),
        ],
    },
    "AxeChop2": {  # backhand hack, left to right, stepping with the right foot
        "hit": 0.17,
        "plane": ((-0.8, 0.05, -0.6), (0, 0.05, -1)),
        "keys": [
            (0.00, pose(arm=(0.2, -0.5, -0.85), wrist=-40, **READY)),
            (0.10, pose(arm=(-0.8, 0.05, -0.6), wrist=-55, chest=38, hips=15, larm=-35, **COIL_BACK)),
            (0.17, pose(arm=(0, 0.05, -1), wrist=-60, chest=0, hips=-10, lean=-10, larm=0, **LUNGE_RIGHT)),
            (0.23, pose(arm=(0.85, 0.05, -0.5), wrist=-60, chest=-32, hips=-22, lean=-10, larm=35, **LUNGE_RIGHT)),
            (0.48, NEUTRAL),
        ],
    },
    "AxeChop3": {  # finisher: crouch, hop, and bring the axe straight down overhead
        "hit": 0.31,
        "plane": ((0.1, 0.95, 0.3), (0.05, -0.45, -0.9)),
        "keys": [
            (0.00, pose(arm=(0.2, -0.5, -0.85), wrist=-40, drop=0.45, lleg=(35, -70, 35), rleg=(35, -70, 35))),
            (0.12, pose(arm=(0.3, 0.3, -0.9), wrist=-45, lean=8, larm=60, lelbow=40, drop=0.2, lleg=(20, -40, 20), rleg=(20, -40, 20))),
            (0.20, pose(arm=(0.1, 0.95, 0.3), wrist=-60, lean=20, larm=70, lelbow=40, **TUCKED)),
            (0.27, pose(arm=(0.05, 0.5, -0.85), wrist=-60, lean=0, larm=40, drop=-0.3, lleg=(40, -60, 20), rleg=(20, -40, 20))),
            (0.31, pose(arm=(0.05, -0.45, -0.9), wrist=-65, lean=-30, larm=-25, **DEEP_LUNGE)),
            (0.48, pose(arm=(0.05, -0.45, -0.9), wrist=-65, lean=-30, larm=-25, **DEEP_LUNGE)),
            (0.75, NEUTRAL),
        ],
    },
    # Heavy (leaping cleave). The wind-up raises the axe high behind the head with the free
    # hand up for balance, held on its last frame while charging; upper body only.
    "AxeWindUp": {
        "hit": None,
        "upper_body_only": True,
        "plane": MACE_PLANE,
        "keys": [
            (0.00, pose(arm=(0.2, -0.5, -0.85), wrist=-40)),
            (0.15, pose(arm=(0.25, 0.3, -0.95), wrist=-50, lean=5, chest=-10, larm=60, lelbow=40)),
            (0.30, pose(arm=(0.15, 0.95, 0.35), wrist=-80, lean=18, chest=-20, larm=150, lelbow=50)),
            (1.00, pose(arm=(0.12, 0.95, 0.4), wrist=-80, lean=24, chest=-24, larm=155, lelbow=45)),  # tension builds
        ],
    },
    # Release: spring forward (the game lunges the player) and chop down into the ground,
    # landing on one knee. "hit" matches Axe.Heavy.HitDelay.
    "AxeCleave": {
        "hit": 0.15,
        "plane": MACE_PLANE,
        "keys": [
            (0.00, pose(arm=(0.12, 0.95, 0.4), wrist=-80, lean=24, chest=-24, larm=155, lelbow=45, **COIL_BACK)),
            (0.07, pose(arm=(0.1, 0.9, -0.3), wrist=-40, lean=8, larm=120, lelbow=40, drop=-0.5,
                        lleg=(45, -70, 25), rleg=(30, -55, 25))),
            (0.15, pose(arm=(0.05, 0, -1), wrist=-70, lean=-35, larm=-10, **KNEEL)),
            (0.45, pose(arm=(0.05, 0, -1), wrist=-70, lean=-32, larm=-10, **KNEEL)),
            (0.75, NEUTRAL),
        ],
    },
    # Enemies reacting to a hit: a quick jolt back (torso and head snap back, arms fly up a
    # little, knees give), then recovering. Played by EnemyEffects.flinch.
    "EnemyFlinch": {
        "hit": None,
        "plane": None,
        "keys": [
            (0.00, pose(arm=(0.1, -1, 0.05), wrist=0, blade_lean=(0, 0, -1), lelbow=0, head_forward=False)),
            (0.06, pose(arm=(0.35, -0.75, 0.45), wrist=0, blade_lean=(0, 0, -1), lean=20, chest=-8, larm=-25, lelbow=45,
                        drop=0.2, lleg=(-8, -18, 26), rleg=(12, -30, 18), head_forward=False)),
            (0.14, pose(arm=(0.3, -0.8, 0.35), wrist=0, blade_lean=(0, 0, -1), lean=15, chest=-6, larm=-20, lelbow=40,
                        drop=0.15, lleg=(-6, -14, 20), rleg=(10, -24, 14), head_forward=False)),
            (0.35, pose(arm=(0.1, -1, 0.05), wrist=0, blade_lean=(0, 0, -1), lelbow=0, head_forward=False)),
        ],
    },
    # --- Staff (one-handed, held a little below the middle). A wrist near +90 stands the staff
    # up when the arm hangs; near -90 it continues the arm's line. Hit times match the Staff
    # section of src/shared/Config/CombatConfig.luau (CastDelay, BlastDelay).
    "StaffIdle": {  # held upright at your side; upper body only so the legs walk
        "hit": None,
        "loop": True,
        "upper_body_only": True,
        "plane": None,
        "keys": [
            (0.0, pose(arm=(0.25, -0.9, -0.3), wrist=80, blade_lean=(0, 0, -1), larm=5)),
            (0.8, pose(arm=(0.25, -0.88, -0.33), wrist=78, blade_lean=(0, 0, -1), larm=7, lean=-3)),
            (1.6, pose(arm=(0.25, -0.9, -0.3), wrist=80, blade_lean=(0, 0, -1), larm=5)),
        ],
    },
    "StaffCast": {  # a quick thrust that sends the missile off
        "hit": 0.14,
        "upper_body_only": True,
        "plane": ((0.35, -0.2, 0.35), (0.1, 0.2, -1)),
        "keys": [
            (0.00, pose(arm=(0.25, -0.9, -0.3), wrist=70)),
            (0.07, pose(arm=(0.35, -0.2, 0.35), wrist=40, chest=-20, larm=20)),
            (0.105, pose(arm=(0.35, 0.05, -0.6), wrist=10, chest=-5, larm=5)),
            (0.14, pose(arm=(0.1, 0.2, -1), wrist=-20, chest=10, lean=-8, larm=-10)),
            (0.40, pose(arm=(0.25, -0.9, -0.3), wrist=70)),
        ],
    },
    "StaffCharge": {  # raised high overhead, held on its last frame while charging
        "hit": None,
        "upper_body_only": True,
        "plane": ((0.15, 0.95, 0.15), (0.1, 0.2, -1)),
        "keys": [
            (0.00, pose(arm=(0.25, -0.9, -0.3), wrist=70)),
            (0.15, pose(arm=(0.3, 0.2, -0.9), wrist=0, larm=60, lelbow=40)),
            (0.30, pose(arm=(0.15, 0.95, 0.15), wrist=-80, lean=10, chest=-10, larm=140, lelbow=30)),
            (1.00, pose(arm=(0.15, 0.95, 0.12), wrist=-80, lean=14, chest=-12, larm=145, lelbow=30)),
        ],
    },
    "StaffBlast": {  # drive the staff forward in a lunge, releasing the blast
        "hit": 0.12,
        "plane": ((0.15, 0.95, 0.15), (0.1, 0.2, -1)),
        "keys": [
            (0.00, pose(arm=(0.15, 0.95, 0.12), wrist=-80, lean=14, chest=-12, larm=145, lelbow=30, **COIL_BACK)),
            (0.06, pose(arm=(0.15, 0.6, -0.8), wrist=-60, lean=0, larm=110, lelbow=30, drop=0.3,
                        lleg=(30, -45, 15), rleg=(15, -40, 25))),
            (0.12, pose(arm=(0.1, 0.15, -1), wrist=-85, lean=-15, larm=60, lelbow=20, **LUNGE_LEFT)),
            (0.45, pose(arm=(0.1, 0.15, -1), wrist=-85, lean=-13, larm=55, lelbow=20, **LUNGE_LEFT)),
            (0.60, pose(arm=(0.2, -0.45, -0.85), wrist=-30, lean=-5, larm=20, lelbow=20, **READY)),
            (0.80, NEUTRAL),
        ],
    },
    # Fire's heavy: the staff, raised overhead, is slammed down into the ground in front.
    # "hit" matches Staff.BlastDelay.
    "StaffSlam": {
        "hit": 0.12,
        "plane": ((0.15, 0.95, 0.15), (0.05, -0.35, -0.95)),
        "keys": [
            (0.00, pose(arm=(0.15, 0.95, 0.12), wrist=-80, lean=14, chest=-12, larm=145, lelbow=30, **COIL_BACK)),
            (0.06, pose(arm=(0.1, 0.55, -0.85), wrist=-70, lean=0, larm=110, lelbow=30, drop=-0.2,
                        lleg=(30, -45, 15), rleg=(20, -40, 20))),
            (0.12, pose(arm=(0.05, -0.35, -0.95), wrist=-85, lean=-30, larm=40, lelbow=30, **KNEEL)),
            (0.45, pose(arm=(0.05, -0.35, -0.95), wrist=-85, lean=-28, larm=40, lelbow=30, **KNEEL)),
            (0.65, pose(arm=(0.2, -0.6, -0.75), wrist=-30, lean=-8, larm=15, lelbow=20, **READY)),
            (0.85, NEUTRAL),
        ],
    },
}


def attach_eases(swings):
    """Folds each key's optional easing, (time, pose, ease), into its pose as p["ease"]."""
    for swing in swings.values():
        swing["keys"] = [(key[0], dict(key[1], ease=key[2]) if len(key) > 2 else key[1]) for key in swing["keys"]]


def resolve_arm_leans():
    """Turns each pose's arm direction into (direction, lean) along its swing's plane.
    Recovery poses (no arm) drop the arm while keeping the last lean, so it doesn't twist."""
    attach_eases(SWINGS)
    for swing in SWINGS.values():
        axis = norm(cross(norm(swing["plane"][0]), norm(swing["plane"][1]))) if swing["plane"] else None
        lean = None
        resolved = []
        for time, p in swing["keys"]:
            p = dict(p)
            if p["blade_lean"] is not None:
                lean = p["blade_lean"]
                p["arm"] = (norm(p["arm"]), lean)
            elif p["arm"] is None:
                p["arm"] = ((0, -1, 0), lean or (0, 0, -1))
            else:
                direction = norm(p["arm"])
                lean = cross(axis, direction)
                p["arm"] = (direction, lean)
            resolved.append((time, p))
        swing["keys"] = resolved
        resolve_left_arm(swing)


def resolve_left_arm(swing):
    """Same as the right arm's, for poses that aim the left arm (larm_dir)."""
    plane = swing.get("lplane")
    axis = norm(cross(norm(plane[0]), norm(plane[1]))) if plane else None
    lean = None
    resolved = []
    for time, p in swing["keys"]:
        p = dict(p)
        if p["larm_dir"] is not None:
            direction = norm(p["larm_dir"])
            if p["lblade_lean"] is not None:
                lean = p["lblade_lean"]
            elif axis is not None:
                lean = cross(axis, direction)
            else:
                lean = lean or (0, 0, -1)
            p["larm_dir"] = (direction, lean)
        resolved.append((time, p))
    swing["keys"] = resolved


def leg(hip, knee, ankle):
    return rx(hip), rx(knee), rx(ankle)


def joint_rotations(p):
    """Returns {part name: 3x3 rotation} for one pose."""
    l_hip, l_knee, l_ankle = leg(*p["lleg"])
    r_hip, r_knee, r_ankle = leg(*p["rleg"])
    return {
        "LowerTorso": ry(p["hips"]),
        "UpperTorso": matmul(ry(p["chest"]), rx(p["lean"])),
        # Keep looking forward through the twist and lean (or just level the head, for spins).
        "Head": matmul(
            matmul(rx(-p["lean"]), ry(-(p["chest"] + p["hips"]))) if p["head_forward"] else rx(-p["lean"]),
            matmul(ry(p["head"][1]), rx(p["head"][0])),
        ),
        "RightUpperArm": aim_arm(*p["arm"]),
        "RightLowerArm": rx(p.get("elbow", 0)),
        "RightHand": rx(p["wrist"]),
        "LeftUpperArm": aim_arm(*p["larm_dir"]) if p["larm_dir"] else matmul(ry(p["larm_yaw"]), rx(p["larm"])),
        "LeftLowerArm": identity() if p["larm_dir"] else rx(p["lelbow"]),
        "LeftHand": rx(p["lwrist"]) if p["larm_dir"] else identity(),
        "LeftUpperLeg": l_hip, "LeftLowerLeg": l_knee, "LeftFoot": l_ankle,
        "RightUpperLeg": r_hip, "RightLowerLeg": r_knee, "RightFoot": r_ankle,
    }


def describe(p):
    """World-space (character-space) arm and blade directions, for checking a pose."""
    r = joint_rotations(p)
    arm = matmul(matmul(r["LowerTorso"], r["UpperTorso"]), r["RightUpperArm"])
    hand = matmul(matmul(arm, r["RightLowerArm"]), r["RightHand"])
    return apply(arm, (0, -1, 0)), apply(hand, (0, 0, -1))


# --- .rbxmx output -----------------------------------------------------------------

_referent = 0


def next_referent():
    global _referent
    _referent += 1
    return f"RBX{_referent:08X}"


def cframe_xml(rotation, position=(0, 0, 0)):
    values = "".join(f"<R{i}{j}>{rotation[i][j]:.6f}</R{i}{j}>" for i in range(3) for j in range(3))
    x, y, z = position
    return f'<CoordinateFrame name="CFrame"><X>{x:.4f}</X><Y>{y:.4f}</Y><Z>{z:.4f}</Z>{values}</CoordinateFrame>'


def pose_xml(name, rotation, weight, children, depth, position=(0, 0, 0), ease=EASE_SMOOTH):
    pad = "\t" * depth
    style, direction = ease
    return (
        f'{pad}<Item class="Pose" referent="{next_referent()}"><Properties>{cframe_xml(rotation, position)}'
        f'<token name="EasingDirection">{direction}</token><token name="EasingStyle">{style}</token>'
        f'<string name="Name">{name}</string><float name="Weight">{weight}</float></Properties>\n'
        f'{"".join(children)}{pad}</Item>\n'
    )


def keyframe_xml(time, p, depth=2, upper_body_only=False):
    r = p.get("_rot") or joint_rotations(p)
    ease = p.get("ease") or EASE_SMOOTH

    def chain(names, start_depth):
        # Builds a nested pose chain, e.g. UpperLeg > LowerLeg > Foot.
        xml = ""
        for offset, name in reversed(list(enumerate(names))):
            xml = pose_xml(name, r[name], 1, [xml] if xml else [], start_depth + offset, ease=ease)
        return xml

    torso_depth = depth + 3
    upper = pose_xml("UpperTorso", r["UpperTorso"], 1, [
        chain(["Head"], torso_depth + 1),
        chain(["RightUpperArm", "RightLowerArm", "RightHand"], torso_depth + 1),
        chain(["LeftUpperArm", "LeftLowerArm"] + (["LeftHand"] if p["larm_dir"] else []), torso_depth + 1),
    ], torso_depth, ease=ease)
    if upper_body_only:
        # Hips and legs left to the walk/idle animations (weight-0 placeholder).
        lower = pose_xml("LowerTorso", identity(), 0, [upper], depth + 2, ease=ease)
    else:
        lower = pose_xml("LowerTorso", r["LowerTorso"], 1, [
            upper,
            chain(["LeftUpperLeg", "LeftLowerLeg", "LeftFoot"], torso_depth),
            chain(["RightUpperLeg", "RightLowerLeg", "RightFoot"], torso_depth),
        ], depth + 2, position=(0, -p["drop"], 0), ease=ease)
    root = pose_xml("HumanoidRootPart", identity(), 0, [lower], depth + 1, ease=ease)  # placeholder
    pad = "\t" * depth
    return (
        f'{pad}<Item class="Keyframe" referent="{next_referent()}"><Properties><string name="Name">Keyframe</string>'
        f'<float name="Time">{time}</float></Properties>\n{root}{pad}</Item>\n'
    )


def marker_xml(time, name, depth=2):
    pad = "\t" * depth
    return (
        f'{pad}<Item class="Keyframe" referent="{next_referent()}"><Properties><string name="Name">{name}</string>'
        f'<float name="Time">{time}</float></Properties>\n'
        f'{pad}\t<Item class="KeyframeMarker" referent="{next_referent()}"><Properties><string name="Name">{name}</string>'
        f'<string name="Value"></string></Properties></Item>\n{pad}</Item>\n'
    )


def fmt(v):
    return "(" + ", ".join(f"{c:+.2f}" for c in v) + ")"


# --- whole-body overlap ---------------------------------------------------------------
# With every joint keyed together the body moves as one stiff block. With "overlap" on, a
# swing is resampled every SAMPLE_STEP with each part of the body offset in time: the hips
# and legs lead (they're ahead of the keys), the chest follows, the arm is on the keys (so the
# hit lands on time), and the forearm and hand trail a touch behind it, so a strike unrolls up
# the body and the blade whips last, like real weight transfer.
SAMPLE_STEP = 1 / 30
LEAD = {  # seconds each joint runs ahead of the keys (negative = behind)
    "LowerTorso": 0.05, "LeftUpperLeg": 0.05, "LeftLowerLeg": 0.05, "LeftFoot": 0.05,
    "RightUpperLeg": 0.05, "RightLowerLeg": 0.05, "RightFoot": 0.05,
    "UpperTorso": 0.025, "Head": 0.035, "LeftUpperArm": 0.01, "LeftLowerArm": 0.0, "LeftHand": 0.0,
    "RightUpperArm": 0.0, "RightLowerArm": -0.012, "RightHand": -0.02,
}


def ease_value(ease, u):
    """How far along (0..1) a segment is at u, for a key's (PoseEasingStyle, Direction)."""
    style, direction = ease or EASE_SMOOTH
    if style == 0:
        return u
    if style == 1:
        return 0.0
    if style == 5 and direction == 0:
        return u * u * u
    if style == 5 and direction == 1:
        return 1 - (1 - u) ** 3
    return 4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2


def mix(a, b, u):
    """Blends two resolved pose values: numbers, tuples of numbers, or (direction, lean)."""
    if a is None or b is None:
        return a if u < 0.5 else b
    if isinstance(a, bool) or isinstance(a, str):
        return a
    if isinstance(a, (int, float)):
        return a + (b - a) * u
    if isinstance(a[0], tuple):  # (direction, lean)
        return tuple(norm(tuple(x + (y - x) * u for x, y in zip(va, vb))) for va, vb in zip(a, b))
    return tuple(x + (y - x) * u for x, y in zip(a, b))


def pose_at(keys, t):
    """The resolved pose at time t, following each segment's easing."""
    if t <= keys[0][0]:
        return keys[0][1]
    for (ta, a), (tb, b) in zip(keys, keys[1:]):
        if t <= tb:
            u = ease_value(a.get("ease"), (t - ta) / (tb - ta))
            return {k: mix(a[k], b.get(k), u) if k != "ease" else None for k in a}
    return keys[-1][1]


def overlapped(keys):
    """Resamples resolved keys with each joint offset by LEAD (see above)."""
    end = keys[-1][0]
    times = sorted({round(i * SAMPLE_STEP, 4) for i in range(int(end / SAMPLE_STEP) + 1)} | {k[0] for k in keys})
    out = []
    for t in times:
        by_joint = {}
        for joint, lead in LEAD.items():
            sample = pose_at(keys, min(end, max(0.0, t + lead)))
            by_joint[joint] = joint_rotations(sample)[joint]
        hips = pose_at(keys, min(end, t + LEAD["LowerTorso"]))
        p = dict(hips, ease=EASE_LINEAR, _rot=by_joint)
        p["larm_dir"] = keys[0][1]["larm_dir"]
        out.append((t, p))
    return out



def main(out_dir):
    resolve_arm_leans()
    out = Path(out_dir)
    for name, swing in SWINGS.items():
        print(f"== {name}" + (f" (hit at {swing['hit']}s)" if swing["hit"] else " (looping)"))
        body = ""
        for time, p in swing["keys"]:
            arm, blade = describe(p)
            print(f"  t={time:.2f}  arm {fmt(arm)}  blade {fmt(blade)}  hips drop {p['drop']:+.2f}")
        written = overlapped(swing["keys"]) if swing.get("overlap") else swing["keys"]
        if swing.get("overlap"):
            print(f"  whole-body overlap: {len(written)} keyframes")
        for time, p in written:
            body += keyframe_xml(time, p, upper_body_only=swing.get("upper_body_only", False))
        worst_joint, worst = "", 0
        for (_, a), (_, b) in zip(written, written[1:]):
            ra, rb = a.get("_rot") or joint_rotations(a), b.get("_rot") or joint_rotations(b)
            for joint in ra:
                angle = turn_angle(ra[joint], rb[joint])
                if angle > worst:
                    worst_joint, worst = joint, angle
        print(f"  largest joint turn between keyframes: {worst:.0f} degrees ({worst_joint})")
        if swing["hit"]:
            body += marker_xml(swing["hit"], "Hit")
        loop = "true" if swing.get("loop") else "false"
        xml = (
            '<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" '
            'xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">\n'
            f'\t<Item class="KeyframeSequence" referent="{next_referent()}"><Properties><bool name="Loop">{loop}</bool>'
            f'<string name="Name">{name}</string><token name="Priority">2</token></Properties>\n{body}\t</Item>\n</roblox>\n'
        )
        (out / f"{name}.rbxmx").write_text(xml)
    print("forward is -Z, right is +X, up is +Y")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
