#!/usr/bin/env bash
# LIVE end-to-end wiring test: starts the real node bridge + simulator, then
# runs checkpoint15 which drives the game over the real websocket connection.
#
#   ./tests/e2e_live.sh
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/home/dev/godot441/Godot_v4.4.1-stable_linux.x86_64}"
PORT="${PORT:-8080}"
E2E_DIR="${TMPDIR:-/tmp}/tik_e2e"
mkdir -p "$E2E_DIR"

if ! command -v node >/dev/null 2>&1; then
    echo "ERROR: node not found (required for the bridge + simulator)" >&2
    exit 1
fi
if (exec 3<>"/dev/tcp/127.0.0.1/$PORT") 2>/dev/null; then
    exec 3>&- 3<&-
    echo "ERROR: port $PORT already in use (bridge running?)" >&2
    exit 1
fi

node tools/bridge/src/server.js > "$E2E_DIR/bridge.log" 2>&1 &
BRIDGE_PID=$!
sleep 1
INTERVAL_MS=100 COMMANDER_CHANCE=0.7 node tools/bridge/src/simulator.js > "$E2E_DIR/simulator.log" 2>&1 &
SIM_PID=$!

cleanup() {
    kill "$SIM_PID" "$BRIDGE_PID" 2>/dev/null || true
    wait "$SIM_PID" 2>/dev/null || true
    wait "$BRIDGE_PID" 2>/dev/null || true
}
trap cleanup EXIT

echo "==> bridge + simulator up (port $PORT), running checkpoint15 (E2E)..."
timeout 90 "$GODOT" --path . --headless -s tests/checkpoint15.gd 2>&1 | \
    grep -E "PASS|FAIL|RESULT|SCRIPT ERROR" | head -40
EXIT="${PIPESTATUS[0]}"
echo "==> E2E checkpoint exit: $EXIT"
exit "$EXIT"
