#!/usr/bin/env bash
# Build standalone release bundles for Gift Siege.
#
#   ./build_release.sh                 # export Linux + Windows, package + zip
#   PLATFORMS=linux ./build_release.sh # only Linux
#   PLATFORMS=windows ./build_release.sh
#
# Requirements:
#   - Godot 4.4.1 export templates installed for the target platform(s).
#     Install via the editor (Editor -> Manage Export Templates) or:
#       ~/.local/share/godot/export_templates/4.4.1.stable/
#     The actual binary export is the LAST step; this script just wraps it.
set -euo pipefail
cd "$(dirname "$0")"

GODOT="${GODOT:-/home/dev/godot441/Godot_v4.4.1-stable_linux.x86_64}"
TEMPLATES="${HOME}/.local/share/godot/export_templates/4.4.1.stable"
GAME="gift_siege"
DIST="dist"
PLATFORMS="${PLATFORMS:-linux windows}"

LINUX_TMPL="$TEMPLATES/linux_release.x86_64"
WIN_TMPL="$TEMPLATES/windows_release_x86_64.exe"

need_templates() {
    local which="$1"
    echo "ERROR: missing Godot 4.4.1 export template: $which" >&2
    echo "Install all templates first (Editor -> Manage Export Templates)." >&2
    exit 1
}

has_node() { command -v node >/dev/null 2>&1; }

for p in $PLATFORMS; do
    case "$p" in
        linux)   [ -f "$LINUX_TMPL" ] || need_templates "$LINUX_TMPL" ;;
        windows) [ -f "$WIN_TMPL" ]   || need_templates "$WIN_TMPL" ;;
        *) echo "unknown platform: $p" >&2; exit 1 ;;
    esac
done

mkdir -p "$DIST"

for p in $PLATFORMS; do
    case "$p" in
        linux)
            OUT="$DIST/linux"
            EXE="$OUT/$GAME.x86_64"
            echo "==> Exporting Linux (release) -> $EXE"
            rm -rf "$OUT"; mkdir -p "$OUT"
            "$GODOT" --headless --path . --export-release "Linux" "$EXE"
            chmod +x "$EXE"
            ;;
        windows)
            OUT="$DIST/windows"
            EXE="$OUT/$GAME.exe"
            echo "==> Exporting Windows (release) -> $EXE"
            rm -rf "$OUT"; mkdir -p "$OUT"
            "$GODOT" --headless --path . --export-release "Windows Desktop" "$EXE"
            ;;
    esac

    # Ship the live bridge (optional sidecar) with the game.
    if [ -d "tools/bridge" ]; then
        cp -r tools/bridge "$OUT/bridge"
        find "$OUT/bridge" -name ".bin" -type d -prune -exec rm -rf {} + 2>/dev/null || true
    fi

    # One-click launcher: starts the bridge (if present) then the game.
    if [ "$p" = "linux" ]; then
        cat > "$OUT/run_standalone.sh" <<'EOF'
#!/usr/bin/env bash
# Starts the optional live bridge, then launches Gift Siege.
cd "$(dirname "$0")"
if [ -x bridge/src/server.js ] && command -v node >/dev/null 2>&1; then
    (cd bridge && node src/server.js) &
    BRIDGE_PID=$!
fi
./gift_siege.x86_64 "$@"
[ -n "${BRIDGE_PID:-}" ] && kill "$BRIDGE_PID" 2>/dev/null
EOF
        chmod +x "$OUT/run_standalone.sh"
    else
        cat > "$OUT/run_standalone.bat" <<'EOF'
@echo off
REM Starts the optional live bridge, then launches Gift Siege.
cd /d "%~dp0"
if exist bridge\src\server.js (
    start /b node bridge\src\server.js
)
gift_siege.exe %*
EOF
    fi

    cat > "$OUT/README.txt" <<EOF
Gift Siege ($p)
==============

Run:
  Linux   : ./run_standalone.sh   (or ./gift_siege.x86_64)
  Windows : run_standalone.bat    (or gift_siege.exe)

Live TikTok interaction (optional):
  The game works fully standalone without it. To enable live gifts from a
  TikTok LIVE, start the bridge with your username:

    TIKTOK_USERNAME=your_live_username node bridge/src/server.js

  Then open the gift panel at http://127.0.0.1:8080 and link your viewers.
  Without TIKTOK_USERNAME the bridge runs in test mode (simulated gifts) -
  handy for local playtesting. Requires Node.js 18+.

Controls (in-game):
  M          toggle / cycle spectate camera
  F7-F10     lighting presets (sunset / night / rain / day)
  B          battle registry summary (console)
  F5         debug battle
  Right-click drag / wheel : rotate / zoom RTS camera
EOF
done

# Zip bundles.
echo "==> Packaging"
for p in $PLATFORMS; do
    case "$p" in
        linux)   (cd "$DIST" && zip -qr "$GAME-linux.zip" linux) ;;
        windows) (cd "$DIST" && zip -qr "$GAME-windows.zip" windows) ;;
    esac
done

echo "==> Done. Artifacts in $DIST/:"
ls -lh "$DIST" | grep -E "$GAME|linux|windows" || true
