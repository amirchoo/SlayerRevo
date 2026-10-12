"""Stitches top-down Studio captures of the world into assets/map/world.png.

    python3 tools/stitch_map.py OUT.png r1c1.jpg r1c2.jpg r2c1.jpg ... r4c2.jpg

Captures are taken in Studio edit mode (atmosphere, clouds, bloom off; noon) in a camera grid: 4 rows (north to south) by 2
columns (west to east), each centered on a 1024 x 512-stud tile, looking straight down from
2926 studs above the ground with a 10 degree field of view (so 512 studs fill the image
height). The result covers the world from -1024 to 1024 on X and Z, north at the top.
"""
import math
import sys

from PIL import Image

TILE_STUDS = (1024, 512)
FOV = 10
HEIGHT = 2926
OUT_SIZE = 1024
WORLD = 2048


def main(argv):
    out, files = argv[1], argv[2:]
    if len(files) != 8:
        sys.exit(__doc__)
    canvas = Image.new("RGB", (OUT_SIZE, OUT_SIZE))
    scale = OUT_SIZE / WORLD
    for index, path in enumerate(files):
        row, col = divmod(index, 2)
        image = Image.open(path).convert("RGB")
        w, h = image.size
        studs_tall = 2 * HEIGHT * math.tan(math.radians(FOV / 2))
        px_per_stud = h / studs_tall
        crop_w, crop_h = TILE_STUDS[0] * px_per_stud, TILE_STUDS[1] * px_per_stud
        left, top = (w - crop_w) / 2, (h - crop_h) / 2
        tile = image.crop((round(left), round(top), round(left + crop_w), round(top + crop_h)))
        size = (round(TILE_STUDS[0] * scale), round(TILE_STUDS[1] * scale))
        canvas.paste(tile.resize(size, Image.LANCZOS), (col * size[0], row * size[1]))
    canvas.save(out)
    print("wrote", out, canvas.size)


main(sys.argv)
