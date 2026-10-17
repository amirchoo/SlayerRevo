#!/bin/sh
# Plays a weapon's whole combo chained the way the game chains it: a Blender file to watch and
# 60 fps / quarter-speed videos (see combo_anim.py). Opens both unless --no-open.
#
#   sh tools/blender/combo.sh Sword [--no-open] [--no-video]
#
# The clips and cooldowns per weapon are listed below (cooldowns from CombatConfig <Weapon>.Combo).
set -e
BLENDER=${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
A="$ROOT/assets/animations"
weapon=$1
shift
case "$weapon" in
	Sword) clips="$A/SwordSwing1.rbxmx,$A/SwordSwing2.rbxmx,$A/SwordSwing3.rbxmx"; cooldowns="0.55,0.55,0.85"; model="--model Sword" ;;
	*) echo "no combo listed for $weapon (add it in combo.sh)"; exit 1 ;;
esac
open_it=1
extra=""
for arg in "$@"; do
	case "$arg" in
		--no-open) open_it=0 ;;
		--no-video) extra="--no-video" ;;
	esac
done
"$BLENDER" -b --factory-startup -P "$ROOT/tools/blender/combo_anim.py" -- "$weapon" --clips "$clips" --cooldowns "$cooldowns" \
	--blend "$ROOT/build/anim_author" --video "$ROOT/build/anim_video" $model $extra 2>&1 | grep -E "^COMBO|Error|Traceback|line [0-9]" || true
if [ "$open_it" = 1 ]; then
	open -a Blender "$ROOT/build/anim_author/${weapon}Combo_show.blend"
	[ -n "$extra" ] || open "$ROOT/build/anim_video/${weapon}Combo/behind_60fps.mp4" "$ROOT/build/anim_video/${weapon}Combo/side_quarter_speed.mp4"
fi
