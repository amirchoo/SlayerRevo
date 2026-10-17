"""The Sword's combo, authored for tools/blender/author_anim.py (run: sh tools/blender/author.sh SwordSwing1).

Each clip is {"hit": seconds or None, "keys": [(time, pose, ease[, {group: ease}])], "loop"?, "upper_body_only"?,
"moving_twin"?, "blend_in"?, "overlap"?, "offhand_space"?, "sudden"?} (see author_anim.py). The optional
{group: ease} gives a body part its own easing out of that key (groups: OVERLAP in author_anim.py).
"moving_twin" also writes <Clip>Moving.rbxmx: the upper body only, played while walking (the legs walk).
`ease` shapes the segment that leaves the key: "smooth" (default), "in" (slow start, arrives
fastest: into a hit), "out" (leaves fast, eases to a stop), "inout", "linear" (a held pose).

A pose (Blender space: X right, Y forward, Z up, studs; the ground is Z = 0):
  grip     where the right hand's center is (it holds the sword)
  blade    which way the blade points from the hand
  edge     which way the cutting edge faces (kept square to the blade): it should lead the cut
  elbow    a point the right elbow bends toward
  lwrist / lelbow   the left wrist, and the point its elbow bends toward
  lfoot / rfoot     (x, y, z, turn[, pitch]) of each foot's center; z = 0.15 is flat on the ground
                    (turn: degrees, + = toes to the left). Knees bend toward a point 3 studs
                    ahead of the foot unless lfoot_knee / rfoot_knee give one.
  hips     offset of the hips from standing (z = -0.3 sinks them 0.3)
  hips_turn / chest   (turn, lean, roll) in degrees: + turn = to the left, + lean = back.
                      The chest's is on top of the hips'.
  head     (turn, look up) in degrees, in the world (the head mostly keeps facing forward)

Standing: the right shoulder is at about (1, 0, 3.76), and the arm reaches about 1.6 studs from
it to the wrist; the report prints GRIP OUT OF REACH if a key asks for more.

The combo is a chain (after Dueling Grounds' katana, notes/log/2026-10-18-sword-katana-redo.md):
each cut ends in a held pose that the next swing starts from, so they share the same dicts.
Hit times match HitDelay in src/shared/Config/CombatConfig.luau (Sword; Emberfang follows it).
"""
import math

WEAPON = "Sword"  # the model in the hand (weapon_model.WEAPONS) for the armor clearance check


def P(base=None, **changes):
    """A pose: `base` with some controls changed."""
    out = dict(base or {})
    out.update(changes)
    return out


def lowered(pose, dz):
    """The same upper-body pose, everything held by the hands moved down dz (the hips sank)."""
    out = dict(pose)
    for key in ("grip", "elbow", "lwrist", "lelbow"):
        x, y, z = out[key]
        out[key] = (x, y, z - dz)
    return out


FEET_READY = {"lfoot": (-0.5, 0.0, 0.15, 0), "rfoot": (0.5, 0.0, 0.15, 0)}

# SwordIdle's upper body (read off the published clip): one hand low by the right hip, the
# blade angled up and forward, the left arm loose. Standing straight, as the idle plays.
IDLE = {
    "grip": (1.94, -0.08, 2.37), "blade": (0.52, 0.75, 0.40), "edge": (-0.35, -0.24, 0.90),
    "elbow": (2.2, -1.2, 3.5), "lwrist": (-1.38, 0.56, 2.33), "lelbow": (-2.0, -2.5, 3.0),
    "hips": (0, 0, 0), "hips_turn": (0, 0, 0), "chest": (-10, 0, 0), "head": (0, 0),
    **FEET_READY,
}
READY_DROP = 0.15
START = P(lowered(IDLE, READY_DROP), hips=(0, 0, -READY_DROP))  # every swing starts and ends here

def two_hands(grip, blade, apart=0.42):
    """Where the left wrist goes to hold the handle below the right hand (toward the pommel)."""
    gx, gy, gz = grip
    bx, by, bz = blade
    n = (bx * bx + by * by + bz * bz) ** 0.5
    return (gx - bx / n * apart, gy - by / n * apart, gz - bz / n * apart)


# Exaggerated after the battlegrounds video (notes/research/battlegrounds-combat-reference.md):
# extreme silhouettes that read at a glance. Deep lunges, the body coiling ~60° one way and
# whipping ~60° the other, the chest over the front knee, a settle after each extreme.
# Each cut goes a different way: 1 down to the left, 2 flat to the right, 3 straight down.

# Swing 1: a deep lunge. The left foot steps far forward, the right one stays and pivots.
STEP_LEFT = {"lfoot": (-0.85, 1.85, 0.15, 18), "rfoot": (0.6, -0.3, 0.15, -35)}

S1_END = P(START, grip=(-0.75, 2.3, 2.2), blade=(-0.88, 0.3, -0.38), edge=(0.2, -0.9, 0.3),
           elbow=(0.6, 2.4, 4.4), lwrist=(-1.6, -0.65, 2.05), lelbow=(-2.4, -0.6, 2.4),
           hips=(0, 0.9, -0.9), hips_turn=(32, 0, 0), chest=(28, -24, 0), head=(5, -12), **STEP_LEFT)
# Eases a touch back out of the extreme (rises a little, untwists a little): the settle.
S1_HELD = P(S1_END, grip=(-0.7, 2.23, 2.31), blade=(-0.86, 0.26, -0.43), hips=(0, 0.85, -0.8),
            hips_turn=(29, 0, 0), chest=(25, -20, 0))

# Swing 2: from swing 1's lunge the body whips all the way round the other way, the feet planted,
# and the blade sweeps flat and wide across to the far right (a full crescent).
S2_END = P(S1_HELD, grip=(1.85, 0.5, 2.85), blade=(0.85, -0.5, -0.1), edge=(-0.45, -0.8, 0.1),
           elbow=(2.6, -1.5, 4.3), lwrist=(-1.2, 1.9, 2.6), lelbow=(-2.2, -1.2, 2.0),
           hips=(0.1, 0.75, -0.85), hips_turn=(-30, 0, 0), chest=(-30, -16, 0), head=(-8, -6))
S2_HELD = P(S2_END, grip=(1.8, 0.53, 2.9), blade=(0.86, -0.46, -0.12), hips=(0.1, 0.72, -0.78),
            hips_turn=(-27, 0, 0), chest=(-27, -13, 0))

# Swing 3: the finisher. Both hands on the sword: gather low, leap, hang at the top with the blade
# raised behind the head, then slam straight down into a deep squat.
SQUARE = {"lfoot": (-0.95, 0.9, 0.15, 15), "rfoot": (0.95, 0.1, 0.15, -15)}
# Both elbows bend forward and out through the whole leap, slam and squat (in front of the body, a pole
# is never in line with arms that swing from overhead to low in front; moving poles would cross them).
S3_RPOLE, S3_LPOLE = (2.0, 2.5, 2.5), (-2.0, 2.5, 2.5)
S3_BLADE_END = (0.0, 0.94, -0.33)
S3_GRIP_END = (0.05, 1.85, 1.95)
S3_END = P(S2_HELD, grip=S3_GRIP_END, blade=S3_BLADE_END, edge=(0.0, -0.33, -0.94),
           elbow=S3_RPOLE, lwrist=two_hands(S3_GRIP_END, S3_BLADE_END), lelbow=S3_LPOLE,
           hips=(0, 0.75, -1.15), hips_turn=(0, 0, 0), chest=(0, -30, 0), head=(0, -15), **SQUARE)
S3_HELD = P(S3_END, grip=(0.05, 1.82, 2.03), blade=(0.0, 0.95, -0.3), lwrist=two_hands((0.05, 1.82, 2.03), (0.0, 0.95, -0.3)),
            hips=(0, 0.7, -1.05), chest=(0, -26, 0))

S3_TOP = P(S2_HELD, grip=(0.15, 0.75, 4.75), blade=(0.0, -0.75, 0.66), edge=(0.0, 0.66, 0.75),
          lwrist=two_hands((0.15, 0.75, 4.75), (0.0, -0.75, 0.66)), elbow=S3_RPOLE, lelbow=S3_LPOLE,
          hips=(0, 0.6, 0.45), hips_turn=(0, 0, 0), chest=(0, 14, 0), head=(0, 10),
          lfoot=(-0.8, 0.95, 1.15, 12, 20), rfoot=(0.8, 0.25, 1.05, -12, -20))

# --- The rest of the Sword (the remake, 2026-10-18; notes/research/weapon-animation-research.md) ---

def spun(pose, deg):
    """The whole pose turned `deg` degrees to the left about the character's centre (Z): every
    world-space control moves round, and the hips, head and feet turn with it."""
    a = math.radians(deg)
    c, s_ = math.cos(a), math.sin(a)

    def rot(v):
        x, y, z = v[:3]
        return (x * c - y * s_, x * s_ + y * c, z) + tuple(v[3:])

    out = dict(pose)
    for key in ("grip", "blade", "edge", "elbow", "lwrist", "lelbow"):
        out[key] = rot(pose[key])
    for key in ("lfoot", "rfoot"):
        x, y, z, yaw, *rest = pose[key]
        out[key] = rot((x, y, z)) + (yaw + deg,) + tuple(rest)
    turn, *tilt = pose.get("hips_turn", (0, 0, 0))
    out["hips_turn"] = (turn + deg, *tilt)
    hyaw, hpitch = pose.get("head", (0, 0))
    out["head"] = (hyaw + deg, hpitch)
    return out


# Guard: the blade held level across the face, pointing left, the edge out; the left hand braces the
# flat near its middle. The chest turns the right shoulder forward and hunches behind the blade.
# Clear of armor (a chestplate sticks out ~0.6 studs in front of the chest, sleeves ~0.8 round the
# arms): the blade 1.5 studs out, the chest square behind it (turned, its corner reached the blade),
# leaning in for the reach. The left elbow drops under the blade so the forearm comes up to it from
# below, not along it.
GUARD_GRIP, GUARD_BLADE = (0.85, 1.5, 3.35), (-0.97, 0.18, 0.12)
GUARD = P(IDLE, grip=GUARD_GRIP, blade=GUARD_BLADE, edge=(0.1, 0.95, -0.25),
          elbow=(2.3, 0.6, 2.2), lwrist=(-0.8, 1.72, 3.5), lelbow=(-0.7, 0.6, 1.6),
          chest=(0, -14, 0), head=(0, -2))
GUARD_IN = P(GUARD, grip=(0.84, 1.47, 3.31), lwrist=(-0.81, 1.69, 3.46), chest=(0, -12, 0))  # breathing in

# Spin (heavy, loops 0.5 s a turn = Sword.Heavy.TickInterval): a low, wide whirl, the sword arm flung
# out to the right with the blade level as its extension, the free arm out the other way, the body
# leaning in and the head looking where it's turning (left). Turned a full circle by `spun`.
SPIN_TIME = 0.5
SPIN = P(IDLE, grip=(2.35, 0.35, 2.75), blade=(0.96, 0.25, -0.05), edge=(-0.25, 0.97, -0.1),
         elbow=(2.0, -1.4, 3.4), lwrist=(-1.95, -0.35, 2.9), lelbow=(-1.8, -1.8, 3.6),
         hips=(0, 0, -0.6), hips_turn=(0, 0, 0), chest=(0, -18, 0), head=(25, -5),
         lfoot=(-1.05, 0.35, 0.15, 25), rfoot=(1.05, -0.35, 0.15, -25))
SPIN_STEPS = 30  # a key on every 60 fps sample: between keys the hand would cut a straight chord across the circle

# Walk (carry, after the Arcane Atelier video): the sword hangs low in the right hand, the tip
# trailing behind just off the ground, the arm swinging back and forth with the steps and the
# blade a beat behind it, so it reads as a heavy blade being carried. Upper body only: the legs
# keep Roblox's walk/run, and WeaponWalk keeps this in step with it. One cycle = two steps.
WALK_TIME = 1.0
WALK_MID = P(IDLE, grip=(1.25, -0.3, 2.8), blade=(0.25, -0.84, -0.44), edge=(0.0, 0.3, -1.0),
             elbow=(2.2, -1.6, 3.2), lwrist=(-1.15, 0.0, 2.5), lelbow=(-2.0, -1.4, 3.0),
             chest=(0, -6, 0), head=(0, -2))
# The right arm back (left foot forward) and forward (right foot forward); the left arm opposite.
# The chest counter-turns against the hips and leans away from the sword's weight.
WALK_BACK = P(WALK_MID, grip=(1.22, -0.72, 2.87), blade=(0.22, -0.9, -0.38), lwrist=(-1.1, 0.42, 2.55),
              chest=(-6, -6, 3))
WALK_FWD = P(WALK_MID, grip=(1.25, 0.12, 2.8), blade=(0.28, -0.8, -0.53), lwrist=(-1.12, -0.38, 2.5),
             chest=(6, -6, 3))
WALK_UP = {"grip": 0.06, "lwrist": 0.04}  # the passing positions ride a little higher


def lifted(pose, by):
    out = dict(pose)
    for key, dz in by.items():
        x, y, z = out[key]
        out[key] = (x, y, z + dz)
    return out


CLIPS = {
    "SwordSwing1": {
        "moving_twin": True,  # forehand: coil back, blade cocked behind the right shoulder, lunge and cut down across to low left
        "hit": 0.18,
        "sudden": [(0.14, 0.2)],  # the front foot stamping down as the blade lands
        "overlap": {"feet": 1},  # the hips drive forward and the front foot lands just after them (leading, the leg would lock straight mid-step)
        "keys": [
            (0.00, START, "out"),
            (0.10, P(START, grip=(1.5, -0.35, 3.85), blade=(0.3, -0.85, 0.43), edge=(-0.5, 0.25, 0.8),
                     elbow=(3.0, -1.2, 2.8), lwrist=(-1.45, 1.1, 2.55), lelbow=(-2.0, 1.4, 2.2),
                     hips=(0, -0.15, -0.15), hips_turn=(-28, 0, 0), chest=(-28, 14, 0), head=(0, 4),
                     lfoot=(-0.7, 0.6, 0.55, 12)), "in", {"feet": "inout"}),  # coiled back, leaning away, the blade behind the shoulder, the front foot up: then the whip (the foot travels and settles into the stamp)
            (0.18, P(START, grip=(0.2, 2.45, 2.95), blade=(-0.35, 0.88, 0.3), edge=(-0.6, 0.0, -0.8),
                     elbow=(2.4, 1.3, 4.2), lwrist=(-1.65, -0.45, 2.05), lelbow=(-2.4, -0.8, 2.4),
                     hips=(0, 0.65, -0.7), hips_turn=(12, 0, 0), chest=(6, -14, 0), head=(0, -6), **STEP_LEFT), "out"),  # the hit, mid-arc: the foot lands as the blade passes
            (0.24, S1_END, "linear"),  # out low to the left, deep in the lunge, the body wound past the cut
            (0.50, S1_HELD, "smooth"),  # held, settling (swing 2 starts here)
            (0.68, P(START, grip=(0.7, 1.0, 2.35), blade=(-0.9, 0.3, 0.2), edge=(0.0, -0.4, 0.9),
                     elbow=(1.5, 1.0, 4.5), lwrist=(-1.35, -0.4, 2.1), lelbow=(-2.0, -1.0, 3.0),
                     hips=(0, 0.35, -0.4), hips_turn=(10, 0, 0), chest=(8, -6, 0),
                     lfoot=(-0.65, 0.8, 0.3, 8), rfoot=(0.52, -0.1, 0.15, -12)), "smooth"),  # rising out of the lunge, the front foot drawing back
            (0.92, START),
        ],
    },
    "SwordSwing2": {
        "moving_twin": True,  # backhand: from swing 1's lunge, roll the blade over and whip the whole body round, cutting flat out to the far right
        "hit": 0.15,
        "blend_in": 0.15,  # chained from swing 1 (ComboWeaponClient CHAIN_FADE)
        "overlap": {"blade": 0},  # the backhand turns the blade ~150° into the hit: it needs the whole whip, not one frame less
        "keys": [
            (0.00, S1_HELD, "out"),
            (0.07, P(S1_HELD, grip=(-0.75, 1.3, 3.15), blade=(-0.55, -0.83, 0.1), edge=(-0.83, 0.55, 0.0),
                     elbow=(1.2, -1.2, 4.6), lwrist=(-1.5, -0.9, 2.3), lelbow=(-2.0, -1.5, 2.4), chest=(34, -6, 0), hips_turn=(36, 0, 0),
                     hips=(0, 0.85, -0.75)), "in"),  # wound up even further left, the blade rolled over and trailing behind: then the whip
            (0.15, P(S1_HELD, grip=(0.65, 1.4, 2.95), blade=(0.3, 0.95, -0.05), edge=(0.95, -0.3, 0.0),
                     elbow=(2.4, -0.6, 4.4), lwrist=(-1.1, 1.3, 2.4), lelbow=(-2.0, -1.5, 2.2),
                     chest=(-4, -14, 0), hips_turn=(-6, 0, 0), hips=(0.05, 0.85, -0.85), head=(-1, -9)), "out"),  # the hit, mid-arc, at full reach
            (0.22, S2_END, "linear"),  # out to the far right, the body wound round past the cut
            (0.48, S2_HELD, "smooth"),  # held, settling (swing 3 starts here)
            (0.66, P(START, grip=(2.1, 0.1, 2.2), blade=(0.9, 0.0, 0.45), edge=(-0.4, -0.3, 0.85),
                     elbow=(2.5, -1.5, 3.5), lwrist=(-1.2, 1.1, 2.1), lelbow=(-2.0, -2.0, 2.5),
                     hips=(0, 0.35, -0.4), hips_turn=(-8, 0, 0), chest=(-14, -4, 0),
                     lfoot=(-0.65, 0.8, 0.3, 8), rfoot=(0.52, -0.1, 0.15, -12)), "smooth"),  # rising out of the lunge, the front foot drawing back
            (0.90, START),
        ],
    },
    "SwordSwing3": {
        "moving_twin": True,  # finisher: both hands, gather low, leap, hang at the top with the blade behind the head, slam straight down
        "hit": 0.38,
        "blend_in": 0.15,  # chained from swing 2
        "overlap": {"offhand": 0, "blade": 0, "hips": 0, "chest": 0, "feet": 0, "head": 2},  # both hands on the handle, and the body comes down with them (hips leading would drop the shoulders away from the raised hands and lock the arms straight)
        "offhand_space": "world",  # and the left hand stays on the handle between keys
        "sudden": [(0.12, 0.18), (0.41, 0.46)],  # the spring off the ground, and the slam stopping dead on landing
        "keys": [
            (0.00, S2_HELD, "out"),
            (0.12, P(S2_HELD, grip=(0.4, 1.15, 3.15), blade=(0.25, 0.3, 0.92), edge=(0.0, 0.95, -0.3),
                     lwrist=two_hands((0.4, 1.15, 3.15), (0.25, 0.3, 0.92)), elbow=(1.5, 0.5, 4.8), lelbow=S3_LPOLE,
                     hips=(0, 0.75, -1.0), hips_turn=(-6, 0, 0), chest=(-6, -16, 0), head=(0, -2)), "out"),  # gathered: both hands on it, squatting deep in the lunge
            (0.26, S3_TOP, "linear"),  # the top of the leap: tucked, arched back, the blade raised behind the head
            (0.32, S3_TOP, "in"),  # hangs a beat at the top so it reads, then the slam
            (0.38, P(S3_END, grip=(0.1, 1.25, 3.75), blade=(0.0, 0.95, 0.3), edge=(0.0, 0.3, -0.95),
                     lwrist=two_hands((0.1, 1.25, 3.75), (0.0, 0.95, 0.3)), elbow=S3_RPOLE, lelbow=S3_LPOLE,
                     hips=(0, 0.7, -0.5), chest=(0, -16, 0), head=(0, -8)), "out"),  # the hit, coming down: the feet land as the blade passes
            (0.45, S3_END, "linear"),  # driven down into a deep squat, the blade low in front
            (0.80, S3_HELD, "smooth"),  # held, settling
            (1.00, P(START, grip=(0.9, 0.9, 1.8), blade=(0.85, 0.3, -0.25), edge=(0.4, -0.3, 0.85),
                     elbow=(2.2, 0.4, 2.0), lwrist=(-1.2, 0.7, 2.1), lelbow=(-2.2, 0.3, 1.6),
                     hips=(0, 0.35, -0.5), hips_turn=(4, 0, 0), chest=(8, -10, 0),
                     lfoot=(-0.7, 0.6, 0.3, 8), rfoot=(0.6, -0.05, 0.15, -8)), "smooth"),  # the right hand takes the blade up, rising, the feet drawing in
            (1.20, START),
        ],
    },
    "SwordGuard": {
        # Looping block stance (loops while block is held): the blade level across the face, the left
        # hand bracing the flat, breathing. Upper body only, so the legs keep walking while blocking.
        "loop": True,
        "upper_body_only": True,
        "hit": None,
        "offhand_space": "world",  # the left hand stays on the blade
        "overlap": {},
        "keys": [
            (0.0, GUARD),
            (0.8, GUARD_IN),
            (1.6, GUARD),
        ],
    },
    "SwordSpin": {
        # Heavy: loops while left-click is held, one full turn per hit (TickInterval 0.5 s).
        "loop": True,
        "hit": None,
        "overlap": {},  # a steady whirl: everything turns together
        "keys": [(SPIN_TIME * i / SPIN_STEPS, spun(SPIN, 360 * i / SPIN_STEPS), "linear") for i in range(SPIN_STEPS + 1)],
    },
    "SwordWalk": {
        # The carry while walking (upper body only, in step with the legs: see WeaponWalk).
        "loop": True,
        "upper_body_only": True,
        "hit": None,
        # The heavy blade swings a quarter cycle behind the hand: keyed into the poses (overlap
        # offsets would leave the loop's first and last keys in place and jolt at the seam).
        "overlap": {},
        "keys": [
            (0.0, P(WALK_BACK, blade=WALK_MID["blade"])),
            (0.25, P(lifted(WALK_MID, WALK_UP), blade=WALK_BACK["blade"])),
            (0.5, P(WALK_FWD, blade=WALK_MID["blade"])),
            (0.75, P(lifted(WALK_MID, WALK_UP), blade=WALK_FWD["blade"])),
            (1.0, P(WALK_BACK, blade=WALK_MID["blade"])),
        ],
    },
}
