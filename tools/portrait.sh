#!/bin/bash
# Usage: tools/portrait.sh <out_prefix> <rig/species id> [bone|body] [zoom]  -> <out_prefix>_sheet.png
cd "$(dirname "$0")/.."
timeout 900 godot --headless --import >/dev/null 2>&1
timeout 900 xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --resolution 1280x720 -s res://tests/visual/portrait.gd -- "$@" 2>&1 | grep -E "SCRIPT ERROR|shader|Shader" | head -20
COLS=2 python3 tools/contact_sheet.py "$1_sheet.png" "$1"_0.png "$1"_1.png "$1"_2.png "$1"_3.png
