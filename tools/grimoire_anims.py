"""Generates R15 KeyframeSequence .rbxmx files for the grimoire. The idea: a reader who never
puts the book down. The left hand holds it open in front of the chest, the head bowed over its
pages; to attack, the head comes up and the free right hand is thrust out at the target, palm
first, while the book stays up.

    python3 tools/grimoire_anims.py assets/animations

Built on tools/sword_anims.py (see its notes on joint frames). Here `arm` is the free right
hand; the left arm (larm/lelbow, swung across the body by larm_yaw) holds the book. The
keyframes aim straight ahead; StaffClient turns the head and the right arm the rest of the way
onto the real target while a spell is cast (CombatConfig's AimWithHand). Keep each animation's
"hit" time in sync with CastDelay / BlastDelay in the Grimoire section of
src/shared/Config/CombatConfig.luau.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sword_anims as lib  # noqa: E402
from sword_anims import pose  # noqa: E402

PALM = (0, 1, 0.3)  # where the back of the right hand faces (keeps the arm from twisting)

# The book: held up in front of the chest, across toward the middle, tipped back to be read.
BOOK = {"larm": 38, "lelbow": 45, "larm_yaw": -28}
BOOK_HIGH = {"larm": 60, "lelbow": 40, "larm_yaw": -22}  # lifted up while channelling
READING = (-28, 12)  # head: bowed over the pages (pitch, yaw)
LOOKING = (0, 0)  # head: up, at the target (StaffClient aims it the rest of the way)

# The right hand: resting on the book's edge, then reaching over it to turn a page.
AT_BOOK = {"arm": (-0.3, -0.7, -0.6), "wrist": -15, "blade_lean": PALM}
TURNING = {"arm": (-0.6, -0.45, -0.65), "wrist": -30, "blade_lean": PALM}
# Aiming: the arm drawn back to the shoulder, then thrust straight out at the target.
DRAWN = {"arm": (0.55, 0.2, -0.35), "wrist": 10, "blade_lean": PALM}
AIMED = {"arm": (0.05, 0.08, -1), "wrist": 0, "blade_lean": PALM}
AIMED_HIGH = {"arm": (0.05, 0.2, -1), "wrist": 0, "blade_lean": PALM}  # reaching, gathering power

STEP = {"drop": 0.25, "lleg": (30, -40, 10), "rleg": (-10, -25, 35)}  # a step in with the left foot
READY = {"drop": 0.1, "lleg": (8, -16, 8), "rleg": (8, -16, 8)}


def reading(**extra):
    return pose(**{"chest": 5, "head": READING, **AT_BOOK, **BOOK, **extra})


ANIMATIONS = {
    "GrimoireIdle": {  # reading: head down over the book, turning a page now and then
        "hit": None, "loop": True, "upper_body_only": True, "plane": None,
        "keys": [
            (0.0, reading()),
            (1.2, reading(lean=-3, head=(-25, 6))),
            (2.4, reading()),
            (2.8, reading(**TURNING, head=(-24, 4))),  # reaching across...
            (3.1, reading(**AT_BOOK, head=(-20, 12))),  # ...and the page flicks over
            (4.0, reading()),
        ],
    },
    "GrimoireCast": {  # eyes up from the page, the hand flung out at the target
        "hit": 0.14, "upper_body_only": True, "plane": None,
        "keys": [
            (0.00, reading()),
            (0.07, pose(chest=-12, lean=3, head=LOOKING, **DRAWN, **BOOK)),
            (0.14, pose(chest=14, lean=-6, head=LOOKING, **AIMED, **BOOK)),
            (0.32, pose(chest=12, lean=-5, head=LOOKING, **AIMED, **BOOK)),
            (0.60, reading()),
        ],
    },
    "GrimoireCharge": {  # the book lifted, the hand held out at the target: held on its last frame
        "hit": None, "upper_body_only": True, "plane": None,
        "keys": [
            (0.00, reading()),
            (0.25, pose(chest=8, lean=4, head=LOOKING, **AIMED_HIGH, **BOOK_HIGH)),
            (1.00, pose(chest=10, lean=6, head=LOOKING, **{**AIMED_HIGH, "arm": (0.05, 0.25, -1)}, **BOOK_HIGH)),
        ],
    },
    "GrimoireBlast": {  # a step in and a push of the open hand, loosing the spell
        "hit": 0.15, "plane": None,
        "keys": [
            (0.00, pose(chest=10, lean=6, head=LOOKING, **AIMED_HIGH, **BOOK_HIGH, **READY)),
            (0.08, pose(chest=-10, lean=2, head=LOOKING, **DRAWN, **BOOK, **READY)),
            (0.15, pose(chest=18, lean=-12, head=LOOKING, **AIMED, **BOOK, **STEP)),
            (0.45, pose(chest=16, lean=-10, head=LOOKING, **AIMED, **BOOK, **STEP)),
            (0.80, reading(**READY)),
        ],
    },
}


def main(out_dir):
    lib.SWINGS = ANIMATIONS
    lib.main(out_dir)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "assets/animations")
