#!/bin/sh
# Renders preview sheets and videos of animation clips in Blender (no window), so a clip can be
# checked by eye before it's published:
#
#   sh tools/blender/preview.sh assets/animations/SwordSwing1.rbxmx [more .rbxmx] [--views behind,side] [--fps 30]
#
# Writes build/anim_preview/<Clip>/<view>_sheet.png (every frame, tiled 8 across, stamped with
# its time; HIT on the hit frame) and <Clip>/behind.mp4 (real speed). Options after the clips
# go to preview_anim.py (--views behind,side,front,top  --fps  --res 360x300  --blade  --grip).
set -e
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT="$ROOT/build/anim_preview"
mkdir -p "$OUT"
FPS=30
prev=""
for arg in "$@"; do
	[ "$prev" = "--fps" ] && FPS=$arg
	prev=$arg
done

"$BLENDER" -b --factory-startup -P "$ROOT/tools/blender/preview_anim.py" -- "$@" --out "$OUT" 2>&1 | grep -E "^PREVIEW|Error|Traceback|line [0-9]" || true

for clip in "$@"; do
	case "$clip" in *.rbxmx) ;; *) continue ;; esac
	name=$(basename "$clip" .rbxmx)
	dir="$OUT/$name"
	[ -d "$dir" ] || { echo "no frames for $name"; continue; }
	for first in "$dir"/*_000.png; do
		view=$(basename "$first" _000.png)
		count=$(ls "$dir/${view}"_[0-9][0-9][0-9].png | wc -l | tr -d ' ')
		rows=$(( (count + 7) / 8 ))
		ffmpeg -v error -y -framerate "$FPS" -i "$dir/${view}_%03d.png" -vf "tile=8x${rows}:padding=2" -frames:v 1 "$dir/${view}_sheet.png"
		echo "SHEET $dir/${view}_sheet.png ($count frames)"
	done
	if [ -f "$dir/behind_000.png" ]; then
		ffmpeg -v error -y -framerate "$FPS" -i "$dir/behind_%03d.png" -c:v libx264 -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" "$dir/behind.mp4"
		echo "VIDEO $dir/behind.mp4"
	fi
done
