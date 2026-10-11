#!/bin/sh
# Parses every Luau script in src/ (with StyLua, which reads full Luau syntax) and prints any
# syntax errors. `rojo build` doesn't parse scripts, so run this before testing in Studio.
#     sh tools/check_syntax.sh
status=0
for f in $(find src -name "*.luau"); do
	out=$(stylua --syntax luau - < "$f" 2>&1 >/dev/null)
	if [ -n "$out" ]; then
		echo "== $f"
		echo "$out"
		status=1
	fi
done
[ $status -eq 0 ] && echo "All scripts parse."
exit $status
