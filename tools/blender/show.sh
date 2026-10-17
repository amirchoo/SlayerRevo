#!/bin/sh
# Opens an authored clip in Blender's window to watch and scrub it (body, sword, the blade tip's
# path, key and hit markers): sh tools/blender/show.sh SwordSwing1 [--no-open]
# Needs build/anim_author/<Clip>.blend, which author.sh saves. See show_anim.py.
set -e
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
clip=$1
src="$ROOT/build/anim_author/$clip.blend"
out="$ROOT/build/anim_author/${clip}_show.blend"
[ -f "$src" ] || { echo "no $src: run sh tools/blender/author.sh $clip first"; exit 1; }
"$BLENDER" -b "$src" -P "$ROOT/tools/blender/show_anim.py" -- "$clip" "$out" 2>&1 | grep -E "^SHOW|Error|Traceback|line [0-9]" || true
[ "$2" = "--no-open" ] || open -a Blender "$out"
