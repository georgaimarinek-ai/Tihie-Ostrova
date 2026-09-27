#!/usr/bin/env bash
# One command before saying "done" (CLAUDE.md): content, balance, generated docs, Godot tests, scene smoke.
#   GODOT=/path/to/godot tools/verify.sh
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"

echo "== content =="
python3 tools/validate_content.py
echo "== balance targets =="
python3 tools/progression_sim.py --check | tail -4
echo "== generated docs =="
python3 tools/gen_content_doc.py --check
echo "== godot import =="
"$GODOT" --headless --path . --import >/tmp/fog-isles-import.log 2>&1 || { cat /tmp/fog-isles-import.log; exit 1; }
if grep -E "SCRIPT ERROR|Parse Error" /tmp/fog-isles-import.log; then exit 1; fi
echo "== unit tests =="
"$GODOT" --headless --path . -s res://tests/run_tests.gd 2>&1 | grep -v -E "^ALSA|^$" | tail -n 60
test "${PIPESTATUS[0]}" -eq 0
echo "== main scene smoke =="
"$GODOT" --headless --path . -- --smoke 2>&1 | grep -E "SMOKE OK|ERROR|SCRIPT"
echo "verify: OK"
