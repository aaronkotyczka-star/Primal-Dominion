#!/bin/bash
# Parse-checks all GDScript files; prints unique errors with locations.
cd "$(dirname "$0")/.."
timeout 600 godot --headless --import > /tmp/claude-0/import.log 2>&1
for f in $(find src tests -name "*.gd"); do
  timeout 60 godot --headless --check-only -s "res://$f" 2>&1 | grep -A1 -E "SCRIPT ERROR|Parse Error" | grep -v -E "^--$" | paste - - | grep "res://$f" | sed 's/\s\+/ /g'
done | sort -u
