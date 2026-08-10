#!/usr/bin/env bash
# Long-session launcher + watchdog for tik_game.
# Runs the main scene with the fixed engine (4.4.1), capped FPS, and an
# optional gift bridge + simulator. Watches the game every few seconds and
# automatically restarts it on any abnormal exit (crash/kill) so the session
# stays playable over long runs.
#
# Usage:
#   ./run_game.sh                 # rendered game, bridge+simulator on
#   HEADLESS=1 ./run_game.sh      # headless server-style game
#   NO_BRIDGE=1 ./run_game.sh     # game only, no bridge/simulator
#   STOP_AFTER=300 ./run_game.sh  # quit cleanly after 300s (checked mid-run)
#   MAX_FPS=30 ./run_game.sh      # render FPS cap (default 30)
#
# Exit / restart control:
#   touch /tmp/tik_game_stop      # stop (exit cleanly) within ~5s
#   kill -TERM $pid               # stop (exit cleanly) within ~5s
#   ./run_game.sh --stop          # convenience: same as the touch above
set -u
cd "$(dirname "$0")"
PROJECT_DIR="$(pwd)"

GODOT="${GODOT:-/home/dev/godot441/Godot_v4.4.1-stable_linux.x86_64}"
export DISPLAY="${DISPLAY:-:0}"
MAX_FPS="${MAX_FPS:-30}"
STOP_FILE="${STOP_FILE:-/tmp/tik_game_stop}"
HEADLESS="${HEADLESS:-0}"
NO_BRIDGE="${NO_BRIDGE:-0}"
STOP_AFTER="${STOP_AFTER:-0}"
LOG_DIR="${TIK_LOG_DIR:-logs}"
BRIDGE_DIR="tools/bridge"
POLL_SECS="${POLL_SECS:-5}"
BACKOFF_MAX="${BACKOFF_MAX:-30}"

RENDER_ARGS=()
if [ "$HEADLESS" = "1" ]; then
    RENDER_ARGS+=(--headless)
else
    RENDER_ARGS+=(--max-fps "$MAX_FPS")
fi

if [ "${1:-}" = "--stop" ]; then
    touch "$STOP_FILE"
    echo "stop requested ($STOP_FILE); game will exit within ~${POLL_SECS}s"
    exit 0
fi
rm -f "$STOP_FILE"

mkdir -p "$LOG_DIR"
GAME_LOG="$LOG_DIR/game.log"
WATCH_LOG="$LOG_DIR/watchdog.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$WATCH_LOG"; }

start_bridge() {
    node "$BRIDGE_DIR/src/server.js" >> "$LOG_DIR/bridge.log" 2>&1 &
    BRIDGE_PID=$!
    sleep 1
    INTERVAL_MS=150 COMMANDER_CHANCE=0.6 node "$BRIDGE_DIR/src/simulator.js" >> "$LOG_DIR/simulator.log" 2>&1 &
    SIM_PID=$!
    sleep 1
    log "bridge + simulator started (ws://127.0.0.1:8080)"
}

stop_sidecars() {
    [ -n "${SIM_PID:-}" ] && kill "$SIM_PID" 2>/dev/null
    [ -n "${BRIDGE_PID:-}" ] && kill "$BRIDGE_PID" 2>/dev/null
}

log "launcher started (godot=$GODOT max_fps=$MAX_FPS headless=$HEADLESS stop_after=$STOP_AFTER)"
if [ "$NO_BRIDGE" = "1" ]; then
    log "bridge disabled (NO_BRIDGE=1)"
else
    start_bridge
fi

START_EPOCH=$(date +%s)
RESTART=0
BACKOFF=0
RUNNING=0
while :; do
    # Stop conditions checked every poll.
    if [ -f "$STOP_FILE" ]; then
        log "stop file present, shutting down"
        [ "$RUNNING" -eq 1 ] && kill "$GAME_PID" 2>/dev/null
        break
    fi
    if [ "$STOP_AFTER" -gt 0 ] && [ $(( $(date +%s) - START_EPOCH )) -ge "$STOP_AFTER" ]; then
        log "STOP_AFTER=$STOP_AFTER reached, shutting down"
        [ "$RUNNING" -eq 1 ] && kill "$GAME_PID" 2>/dev/null
        break
    fi

    if [ "$RUNNING" -eq 0 ]; then
        if [ "$RESTART" -gt 0 ]; then
            log "restarting game (restart #$RESTART)"
        fi
        if [ "$BACKOFF" -gt 0 ]; then
            sleep "$BACKOFF"
            log "backoff done"
        fi
        RUN_START=$(date +%s)
        log "game start"
        "$GODOT" --path "$PROJECT_DIR" "${RENDER_ARGS[@]}" >> "$GAME_LOG" 2>&1 &
        GAME_PID=$!
        RUNNING=1
        continue
    fi

    if ! kill -0 "$GAME_PID" 2>/dev/null; then
        wait "$GAME_PID" 2>/dev/null
        EXIT=$?
        RUN_ELAPSED=$(( $(date +%s) - RUN_START ))
        RUNNING=0
        log "game exited with code $EXIT after ${RUN_ELAPSED}s"
        if [ -f "$STOP_FILE" ]; then
            log "stop file present, not restarting"
            break
        fi
        if [ "$EXIT" -eq 0 ] || [ "$RUN_ELAPSED" -ge 60 ]; then
            BACKOFF=0
        else
            BACKOFF=$(( (BACKOFF > 0 ? BACKOFF : 5) * 2 ))
            [ "$BACKOFF" -gt "$BACKOFF_MAX" ] && BACKOFF="$BACKOFF_MAX"
            log "short/abnormal run (${RUN_ELAPSED}s, exit=$EXIT), backoff ${BACKOFF}s next"
        fi
        RESTART=$((RESTART + 1))
        continue
    fi

    sleep "$POLL_SECS"
done

stop_sidecars
log "launcher exiting"
exit 0
