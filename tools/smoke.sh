#!/bin/bash
# Headless smoke run: starts a new game and runs N frames; prints errors compactly.
cd "$(dirname "$0")/.."
N=${1:-900}
shift
timeout 600 godot --headless --path . --quit-after $N -- --autostart "$@" > /tmp/claude-0/run.log 2>&1
grep -E "^E +[0-9]+->|SCRIPT ERROR|ERROR:|error\(|Error|at: " /tmp/claude-0/run.log | grep -v -E "ALSA|audio_driver|init_output_device|initialize \(servers/audio" | uniq | head -${LINES_OUT:-60}
