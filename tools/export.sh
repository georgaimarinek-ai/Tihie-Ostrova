#!/usr/bin/env sh
# Export every preset of export_presets.cfg (docs/08_NEXT.md stage 15): Windows, Linux and the two Steam Next Fest
# demos. Needs the export templates of this Godot version in ~/.local/share/godot/export_templates/<version>/
# (Editor → Manage Export Templates, or unpack Godot_v<version>_export_templates.tpz there and rename
# "templates" to "<version>"). GODOT points at the editor binary; the builds land in build/ (gitignored).
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
export_one() {
	mkdir -p "$(dirname "$2")"
	echo "== $1 → $2 =="
	"$GODOT" --headless --path . --export-release "$1" "$2" 2>&1 | grep -iE 'error|fail|DONE' | grep -v ALSA || true
	test -f "$2"
}
export_one "Linux" build/linux/FogIsles.x86_64
export_one "Windows" build/windows/FogIsles.exe
export_one "Linux Demo" build/demo-linux/FogIslesDemo.x86_64
export_one "Windows Demo" build/demo-windows/FogIslesDemo.exe
echo "== smoke: the Linux build starts a world =="
./build/linux/FogIsles.x86_64 --headless --fixed-fps 60 -- --smoke 2>&1 | grep SMOKE
ls -la build/*/
