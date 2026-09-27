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
python3 tools/gen_i18n.py --check
echo "== godot import =="
"$GODOT" --headless --path . --import >/tmp/fog-isles-import.log 2>&1 || { cat /tmp/fog-isles-import.log; exit 1; }
if grep -E "SCRIPT ERROR|Parse Error" /tmp/fog-isles-import.log; then exit 1; fi
echo "== unit tests =="
"$GODOT" --headless --path . -s res://tests/run_tests.gd --fixed-fps 60 2>&1 | grep -v -E "^ALSA|^$" | tail -n 60
test "${PIPESTATUS[0]}" -eq 0
echo "== main scene smoke =="
"$GODOT" --headless --path . -- --smoke 2>&1 | grep -E "SMOKE OK|ERROR|SCRIPT" | tee /tmp/fog-isles-smoke.log
grep -q "SMOKE OK" /tmp/fog-isles-smoke.log
if grep -E "SCRIPT ERROR|^ERROR" /tmp/fog-isles-smoke.log; then exit 1; fi
echo "== phase 0 slice smoke =="
"$GODOT" --headless --path . res://src/scenes/main.tscn -- --smoke 2>&1 | grep -E "SMOKE OK|ERROR|SCRIPT" | tee /tmp/fog-isles-smoke0.log
grep -q "SMOKE OK" /tmp/fog-isles-smoke0.log
echo "verify: OK"
