#!/bin/bash
# Usage: tools/render.sh <script> [args...]  (re-imports, then runs script under Xvfb)
cd "$(dirname "$0")/.."
timeout 600 godot --headless --import >/dev/null 2>&1
S=$1; shift
timeout 1200 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 --quit-after 20000 -s "$S" -- "$@" 2>&1 | grep -v -E "ALSA|audio|^\s*at:|^$|ERR_CANT_OPEN|dummy driver"
