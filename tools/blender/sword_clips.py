"""The Sword's combo, authored for tools/blender/author_anim.py (run: sh tools/blender/author.sh SwordSwing1).

Each clip is {"hit": seconds or None, "keys": [(time, pose, ease)], "loop"?, "upper_body_only"?}.
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

# Swing 1's stance: the left foot has stepped forward, the right stays.
STEP_LEFT = {"lfoot": (-0.65, 0.75, 0.15, 10), "rfoot": (0.5, 0.0, 0.15, -10)}

S1_END = P(START, grip=(-0.7, 1.3, 2.75), blade=(-0.8, -0.15, -0.58), edge=(0.15, -0.95, 0.3),
           elbow=(0.5, 1.5, 4.8), lwrist=(-1.25, -0.9, 2.3), lelbow=(-2.0, 0.5, 3.0),
           hips=(0, 0.22, -0.3), hips_turn=(8, 0, 0), chest=(14, -14, 0), head=(5, -5), **STEP_LEFT)
S1_HELD = P(S1_END, grip=(-0.67, 1.25, 2.74), blade=(-0.8, -0.2, -0.56), chest=(13, -13, 0))

S2_END = P(S1_HELD, grip=(2.3, 0.45, 2.75), blade=(0.98, -0.15, -0.1), edge=(-0.15, -0.98, 0.1),
           elbow=(2.0, -1.5, 4.5), lwrist=(-0.75, 1.8, 2.55), lelbow=(-2.0, 0.0, 1.5),
           hips=(0.05, 0.15, -0.32), hips_turn=(-8, 0, 0), chest=(-20, -12, 0), head=(-5, -5))
S2_HELD = P(S2_END, grip=(2.28, 0.42, 2.71), blade=(0.97, -0.19, -0.12), chest=(-19, -11, 0))

# Swing 3's stance: a deep step, the left foot further forward, the hips low.
DEEP_STEP = {"lfoot": (-0.7, 1.15, 0.15, 10), "rfoot": (0.55, -0.35, 0.15, -15)}
S3_END = P(S2_HELD, grip=(-0.6, 1.15, 2.5), blade=(-0.95, -0.05, -0.3), edge=(-0.1, -0.95, -0.3),
           elbow=(0.5, 2.0, 4.5), lwrist=(-1.3, -0.7, 2.0), lelbow=(-2.0, 0.5, 3.0),
           hips=(0, 0.45, -0.6), hips_turn=(14, 0, 0), chest=(18, -18, 0), head=(5, -12), **DEEP_STEP)
S3_HELD = P(S3_END, grip=(-0.62, 1.12, 2.47), blade=(-0.95, -0.08, -0.32), chest=(17, -19, 0))

CLIPS = {
    "SwordSwing1": {  # forehand: flick up beside the right shoulder, cut down across to low left
        "hit": 0.18,
        "keys": [
            (0.00, START, "out"),
            (0.08, P(START, grip=(1.35, 0.15, 3.65), blade=(0.2, -0.3, 0.93), edge=(-0.45, 0.85, 0.0),
                     elbow=(3.0, -0.5, 2.5), lwrist=(-1.0, 1.0, 2.8), lelbow=(-2.5, -1.0, 2.0),
                     hips=(0, 0, -0.25), hips_turn=(-10, 0, 0), chest=(-12, 6, 0),
                     lfoot=(-0.55, 0.25, 0.3, 5)), "linear"),  # flicked up, the blade standing beside the shoulder
            (0.12, P(START, grip=(1.4, 0.05, 3.7), blade=(0.25, -0.4, 0.88), edge=(-0.45, 0.85, 0.0),
                     elbow=(3.0, -0.5, 2.5), lwrist=(-1.05, 1.0, 2.85), lelbow=(-2.5, -1.0, 2.0),
                     hips=(0, 0.05, -0.27), hips_turn=(-11, 0, 0), chest=(-13, 7, 0),
                     lfoot=(-0.6, 0.45, 0.35, 8)), "in"),  # coiled a touch more: then the whip
            (0.18, P(START, grip=(0.55, 1.35, 3.2), blade=(-0.6, 0.78, -0.18), edge=(-0.45, -0.3, -0.85),
                     elbow=(2.0, 0.5, 4.5), lwrist=(-1.3, -0.3, 2.3), lelbow=(-2.0, 0.0, 3.0),
                     hips=(0, 0.2, -0.3), hips_turn=(8, 0, 0), chest=(0, -10, 0), **STEP_LEFT), "out"),  # the hit, mid-arc
            (0.24, S1_END, "linear"),  # out low to the left
            (0.50, S1_HELD, "smooth"),  # held (swing 2 starts here)
            (0.66, P(START, grip=(0.45, 1.5, 2.2), blade=(-0.9, 0.3, 0.2), edge=(0.0, -0.4, 0.9),
                     elbow=(1.5, 1.0, 4.5), lwrist=(-1.35, -0.4, 2.1), lelbow=(-2.0, -1.0, 3.0),
                     hips=(0, 0.1, -0.25), hips_turn=(5, 0, 0), chest=(6, -6, 0),
                     lfoot=(-0.55, 0.35, 0.28, 5)), "smooth"),  # the spent blade swings low back across, the foot draws in
            (0.90, START),
        ],
    },
    "SwordSwing2": {  # backhand: from swing 1's held pose, roll the blade over, cut flat out to the right
        "hit": 0.15,
        "keys": [
            (0.00, S1_HELD, "out"),
            (0.035, P(S1_HELD, grip=(-0.55, 0.85, 2.95), blade=(-0.95, -0.25, 0.1), edge=(0.0, -0.3, 1.0),
                      chest=(20, -6, 0), hips_turn=(12, 0, 0)), "out"),  # the wrist rolls the blade over the top
            (0.07, P(S1_HELD, grip=(-0.4, 0.45, 3.2), blade=(-0.6, -0.78, 0.15), edge=(-0.79, 0.62, 0.0),
                     elbow=(1.5, -1.5, 4.5), chest=(24, 2, 0), hips_turn=(14, 0, 0)), "linear"),  # cocked across the left side, blade trailing
            (0.10, P(S1_HELD, grip=(-0.42, 0.4, 3.22), blade=(-0.55, -0.82, 0.15), edge=(-0.82, 0.55, 0.0),
                     elbow=(1.5, -1.5, 4.5), chest=(26, 3, 0), hips_turn=(15, 0, 0)), "in"),
            (0.125, P(S1_HELD, grip=(-0.1, 0.95, 3.1), blade=(-0.7, 0.7, 0.05), edge=(0.7, 0.7, 0.0),
                      elbow=(1.8, -1.0, 4.5), chest=(12, -4, 0), hips_turn=(6, 0, 0)), "linear"),  # mid-whip
            (0.15, P(S1_HELD, grip=(0.6, 1.4, 2.95), blade=(0.3, 0.95, -0.05), edge=(0.95, -0.3, 0.0),
                     elbow=(2.0, -1.0, 4.5), lwrist=(-1.0, 1.0, 2.4), lelbow=(-2.0, -1.0, 2.0),
                     chest=(-4, -10, 0), hips_turn=(-6, 0, 0), hips=(0.03, 0.18, -0.32)), "out"),  # the hit, mid-arc
            (0.21, S2_END, "linear"),  # out to the right
            (0.48, S2_HELD, "smooth"),  # held (swing 3 starts here)
            (0.64, P(START, grip=(2.1, 0.0, 2.15), blade=(0.9, 0.0, 0.45), edge=(-0.4, -0.3, 0.85),
                     elbow=(2.5, -1.5, 3.5), lwrist=(-1.2, 1.1, 2.1), lelbow=(-2.0, -2.0, 2.5),
                     hips=(0, 0.1, -0.25), hips_turn=(-5, 0, 0), chest=(-14, -4, 0),
                     lfoot=(-0.55, 0.35, 0.28, 5)), "smooth"),  # dropping back toward the hip, the foot draws in
            (0.88, START),
        ],
    },
    "SwordSwing3": {  # overhead: raise the blade cocked behind the head, hold a beat, cut down to low left
        "hit": 0.38,
        "keys": [
            (0.00, S2_HELD, "out"),
            (0.13, P(S2_HELD, grip=(0.45, 0.25, 4.7), blade=(0.15, -0.8, -0.58), edge=(0.0, -0.58, 0.8),
                     elbow=(3.0, 0.0, 4.5), lwrist=(-1.0, 1.2, 3.3), lelbow=(-2.5, 0.0, 2.0),
                     hips=(0, 0.05, -0.25), hips_turn=(-8, 0, 0), chest=(-12, 10, 0), head=(0, 5)), "linear"),  # cocked behind the head
            (0.31, P(S2_HELD, grip=(0.5, 0.15, 4.72), blade=(0.2, -0.85, -0.5), edge=(0.0, -0.5, 0.85),
                     elbow=(3.0, 0.0, 4.5), lwrist=(-1.05, 1.15, 3.35), lelbow=(-2.5, 0.0, 2.0),
                     hips=(0, 0.0, -0.28), hips_turn=(-10, 0, 0), chest=(-13, 13, 0), head=(0, 5),
                     lfoot=(-0.68, 0.85, 0.22, 10)), "in"),  # held a beat so it reads, then the cut
            (0.345, P(S2_HELD, grip=(0.35, 0.85, 4.6), blade=(0.0, 0.35, 0.94), edge=(0.0, 0.94, -0.35),
                      elbow=(3.0, 0.5, 4.5), lwrist=(-1.2, 0.6, 2.8), lelbow=(-2.5, 0.0, 2.0),
                      hips=(0, 0.25, -0.45), hips_turn=(0, 0, 0), chest=(0, 0, 0), head=(0, 0),
                      lfoot=(-0.7, 1.05, 0.2, 10)), "linear"),  # over the top
            (0.38, P(S3_END, grip=(0.1, 1.45, 3.65), blade=(-0.3, 0.93, -0.2), edge=(-0.1, -0.2, -0.97),
                     elbow=(2.0, 1.0, 4.5), hips=(0, 0.4, -0.58), chest=(8, -16, 0), head=(0, -8)), "out"),  # the hit, mid-arc
            (0.45, S3_END, "linear"),  # low to the left, deep in the step
            (0.75, S3_HELD, "smooth"),  # held
            (0.93, P(START, grip=(0.8, 0.9, 1.75), blade=(0.85, 0.3, -0.25), edge=(0.4, -0.3, 0.85),
                     elbow=(1.5, 1.0, 4.0), lwrist=(-1.35, -0.4, 1.9), lelbow=(-2.0, -1.0, 3.0),
                     hips=(0, 0.3, -0.45), hips_turn=(4, 0, 0), chest=(8, -10, 0),
                     lfoot=(-0.62, 0.6, 0.3, 5), rfoot=(0.52, -0.15, 0.15, -5)), "smooth"),  # levering the blade up, rising out of the step
            (1.20, START),
        ],
    },
}
