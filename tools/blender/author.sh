#!/bin/sh
# Authors animation clips in Blender (no window) from tools/blender/*_clips.py, bakes them into
# assets/animations/<Clip>.rbxmx, and renders their previews:
#
#   sh tools/blender/author.sh SwordSwing1 [more clips] [--no-preview] [--views behind,side]
#
# Each clip's rig is also saved as build/anim_author/<Clip>.blend. See author_anim.py.
set -e
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
clips=""
preview=1
views=""
prev=""
for arg in "$@"; do
	if [ "$prev" = "--views" ]; then views="--views $arg"; prev=""; continue; fi
	case "$arg" in
		--no-preview) preview=0 ;;
		--views) ;;
		*) clips="$clips $arg" ;;
	esac
	prev=$arg
done

"$BLENDER" -b --factory-startup -P "$ROOT/tools/blender/author_anim.py" -- $clips \
	--out "$ROOT/assets/animations" --blend "$ROOT/build/anim_author" 2>&1 | grep -E "^AUTHOR|Error|Traceback|line [0-9]" || true

if [ "$preview" = 1 ]; then
	files=""
	for clip in $clips; do files="$files $ROOT/assets/animations/$clip.rbxmx"; done
	sh "$ROOT/tools/blender/preview.sh" $files $views
fi
