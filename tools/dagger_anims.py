"""Generates R15 KeyframeSequence .rbxmx files for the dagger: a low knife-fighter's idle, a
4-hit combo that mixes slashes and stabs (forehand slash, backhand slash, gut stab, rising
stab), a tight guard, and the backstab heavy (a crouched wind-up, then a lunge into one deep
stab).

    python3 tools/dagger_anims.py assets/animations

Built on tools/sword_anims.py (one-handed, right hand; see its notes on joint frames). The
knife is short, so the moves stay close to the body: small steps, quick wrists. With the arm
straight, a wrist near -90 carries the blade on along the arm's line (a stab).
Keep each move's "hit" time in sync with HitDelay in the Dagger section of
src/shared/Config/CombatConfig.luau (the backstab's with Heavy.HitDelay).
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sword_anims as lib  # noqa: E402
from sword_anims import COIL_BACK, NEUTRAL, pose  # noqa: E402

UP = (0, 1, 0)
FORWARD = (0, 0, -1)

# Footwork: light, short steps (a knife fighter never over-commits, except on the backstab).
READY = {"drop": 0.25, "lleg": (18, -32, 14), "rleg": (8, -30, 22)}
STEP_LEFT = {"drop": 0.35, "lleg": (32, -42, 10), "rleg": (-12, -24, 36)}  # left foot in
STEP_RIGHT = {"drop": 0.35, "lleg": (-12, -24, 36), "rleg": (32, -42, 10)}  # right foot in
CROUCH = {"drop": 0.55, "lleg": (30, -60, 30), "rleg": (20, -60, 40)}  # low, ready to spring
LUNGE = {"drop": 0.8, "lleg": (-30, -10, 40), "rleg": (62, -78, 16)}  # right foot far forward

# The free hand held up in front, open, to fend off and to balance.
FEND = {"larm": 55, "lelbow": 70}
FEND_LOW = {"larm": 30, "lelbow": 55}
THROWN_BACK = {"larm": -30, "lelbow": 30}  # flung back on the backstab

# Held low in front, point up toward the enemy's chest.
LOW_READY = {"arm": (0.3, -0.6, -0.72), "wrist": -45, "blade_lean": UP}
STAB_DRAWN = {"arm": (0.45, -0.45, -0.25), "wrist": -70, "blade_lean": UP}  # pulled back by the ribs
STAB_OUT = {"arm": (0.15, -0.12, -1), "wrist": -88, "blade_lean": UP}  # arm and blade one line, gut height
STAB_RISING = {"arm": (0.15, 0.3, -0.95), "wrist": -88, "blade_lean": UP}  # driven up under the ribs
STAB_LOW_BACK = {"arm": (0.4, -0.75, 0.25), "wrist": -60, "blade_lean": UP}  # dropped low and back to come up
GUARD = {"arm": (0.35, -0.15, -0.92), "wrist": 0, "blade_lean": (-1, 0.35, 0)}  # forearm up, blade across

# Backstab: drawn back at the hip with the point forward, body hunched like a predator.
DRAWN = {"arm": (0.6, -0.5, 0.6), "wrist": 0, "blade_lean": FORWARD}
DRAWN_DEEP = {"arm": (0.65, -0.45, 0.62), "wrist": 0, "blade_lean": FORWARD}


def ready(**extra):
    return pose(**LOW_READY, **FEND, **extra)


ANIMATIONS = {
    "DaggerIdle": {  # low and ready, free hand up; upper body only, so the legs walk
        "hit": None, "loop": True, "upper_body_only": True, "plane": None,
        "keys": [
            (0.0, ready(lean=-6)),
            (0.8, pose(lean=-9, **{**LOW_READY, "wrist": -50}, larm=58, lelbow=74)),
            (1.6, ready(lean=-6)),
        ],
    },
    "DaggerSlash1": {  # a quick forehand slash across the chest, right to left
        "hit": 0.1,
        "plane": ((0.85, 0.15, -0.3), (-0.6, 0.0, -0.75)),
        "keys": [
            (0.00, pose(arm=(0.3, -0.6, -0.72), wrist=-40, **FEND, **READY)),
            (0.05, pose(arm=(0.85, 0.15, -0.3), wrist=-45, chest=-25, hips=-10, **FEND_LOW, **COIL_BACK)),
            (0.10, pose(arm=(0.1, 0.05, -1), wrist=-50, chest=5, hips=5, lean=-8, **FEND_LOW, **STEP_LEFT)),
            (0.14, pose(arm=(-0.6, 0.0, -0.75), wrist=-50, chest=28, hips=12, lean=-10, larm=10, lelbow=40, **STEP_LEFT)),
            (0.32, NEUTRAL),
        ],
    },
    "DaggerSlash2": {  # the backhand: back across, left to right, stepping with the right foot
        "hit": 0.1,
        "plane": ((-0.7, 0.1, -0.6), (0.85, 0.0, -0.4)),
        "keys": [
            (0.00, pose(arm=(-0.3, -0.3, -0.85), wrist=-40, **FEND_LOW, **READY)),
            (0.05, pose(arm=(-0.7, 0.1, -0.6), wrist=-45, chest=30, hips=12, **FEND_LOW, **COIL_BACK)),
            (0.10, pose(arm=(0.05, 0.05, -1), wrist=-50, chest=0, hips=-8, lean=-8, **FEND, **STEP_RIGHT)),
            (0.14, pose(arm=(0.85, 0.0, -0.4), wrist=-50, chest=-28, hips=-14, lean=-10, **FEND, **STEP_RIGHT)),
            (0.32, NEUTRAL),
        ],
    },
    "DaggerStab3": {  # a short, straight stab to the gut, right shoulder driving in
        "hit": 0.1, "plane": None,
        "keys": [
            (0.00, ready(**READY)),
            (0.05, pose(chest=10, **STAB_DRAWN, **FEND, **READY)),
            (0.10, pose(chest=22, lean=-10, **STAB_OUT, **FEND_LOW, **STEP_RIGHT)),
            (0.17, pose(chest=22, lean=-10, **STAB_OUT, **FEND_LOW, **STEP_RIGHT)),
            (0.32, ready(**READY)),
        ],
    },
    "DaggerStab4": {  # finisher: drop low, then spring in with a rising stab up under the ribs
        "hit": 0.16, "plane": None,
        "keys": [
            (0.00, ready(**READY)),
            (0.08, pose(chest=12, lean=8, **STAB_LOW_BACK, **FEND, **CROUCH)),
            (0.12, pose(chest=16, lean=-2, arm=(0.3, -0.45, -0.75), wrist=-80, blade_lean=UP, **FEND_LOW, **READY)),
            (0.16, pose(chest=20, lean=-12, **STAB_RISING, **FEND_LOW, **STEP_RIGHT)),
            (0.30, pose(chest=20, lean=-10, **STAB_RISING, **FEND_LOW, **STEP_RIGHT)),
            (0.52, ready(**READY)),
        ],
    },
    "DaggerGuard": {  # looping block: forearm up, blade across the face; upper body only
        "hit": None, "loop": True, "upper_body_only": True, "plane": None,
        "keys": [
            (0.0, pose(chest=-15, lean=-4, **GUARD, larm=75, lelbow=85)),
            (0.6, pose(chest=-15, lean=-7, **GUARD, larm=75, lelbow=85)),
            (1.2, pose(chest=-15, lean=-4, **GUARD, larm=75, lelbow=85)),
        ],
    },
    # Heavy wind-up: hunched, knife drawn back at the hip with the point forward, held on its
    # last frame while charging. Upper body only, so the legs can still creep while aiming.
    "DaggerWindUp": {
        "hit": None, "upper_body_only": True, "plane": None,
        "keys": [
            (0.00, ready()),
            (0.15, pose(chest=-12, lean=-12, **DRAWN, **FEND)),
            (0.60, pose(chest=-16, lean=-16, **DRAWN_DEEP, larm=60, lelbow=75)),  # coiled
        ],
    },
    # Heavy release: the game lunges you forward; one deep stab at full stretch, held, then
    # recover. "hit" matches Dagger.Heavy.HitDelay.
    "DaggerBackstab": {
        "hit": 0.12, "plane": None,
        "keys": [
            (0.00, pose(chest=-16, lean=-16, **DRAWN_DEEP, larm=60, lelbow=75, **CROUCH)),
            (0.06, pose(chest=5, lean=-12, **STAB_DRAWN, **FEND_LOW, **STEP_RIGHT)),
            (0.12, pose(chest=22, lean=-22, **STAB_OUT, **THROWN_BACK, **LUNGE)),
            (0.40, pose(chest=20, lean=-20, **STAB_OUT, **THROWN_BACK, **LUNGE)),
            (0.70, ready(**READY)),
        ],
    },
}


def main(out_dir):
    lib.SWINGS = ANIMATIONS
    lib.main(out_dir)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
