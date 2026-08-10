#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/home/dev/godot441/Godot_v4.4.1-stable_linux.x86_64}"
SECONDS="${STRESS_SECONDS:-90}"
MAX_FPS="${STRESS_MAX_FPS:-30}"
BRIDGE_DIR="tools/bridge"
EXTRA_ARGS="${STRESS_EXTRA_ARGS:-}"
if [ "${STRESS_HEADLESS:-0}" = "1" ]; then
    RENDER_ARGS="--headless"
    MODE_TEXT="headless"
else
    RENDER_ARGS="--max-fps $MAX_FPS"
    MODE_TEXT="rendering (max-fps $MAX_FPS)"
fi

echo "===== stress_live: bridge + simulator + game (${MODE_TEXT}) for ${SECONDS}s ====="
ulimit -c unlimited 2>/dev/null || true
rm -f /tmp/stress_bridge.log /tmp/stress_sim.log /tmp/stress_game.log
rm -f core core.*

# 1) bridge
node "$BRIDGE_DIR/src/server.js" > /tmp/stress_bridge.log 2>&1 &
BRIDGE_PID=$!
sleep 1
# 2) fast simulator
INTERVAL_MS=150 COMMANDER_CHANCE=0.6 node "$BRIDGE_DIR/src/simulator.js" > /tmp/stress_sim.log 2>&1 &
SIM_PID=$!
sleep 1

# 3) the actual game
# shellcheck disable=SC2086
"$GODOT" --path . $EXTRA_ARGS $RENDER_ARGS -s tests/stress_live.gd -- "$SECONDS" > /tmp/stress_game.log 2>&1
EXIT=$?

kill "$SIM_PID" "$BRIDGE_PID" 2>/dev/null
wait 2>/dev/null

echo "game exit code: $EXIT"
echo "---- game tail ----"
tail -15 /tmp/stress_game.log
if [ "$EXIT" -eq 0 ]; then
    echo "RESULT: NO CRASH (exit=0)"
elif [ "$EXIT" -eq 139 ]; then
    echo "RESULT: SIGSEGV REPRODUCED"
    ls -la core* 2>/dev/null || echo "no core file captured"
elif [ "$EXIT" -eq 124 ]; then
    echo "RESULT: timeout (no crash within window)"
else
    echo "RESULT: exit=$EXIT (see log)"
fi
