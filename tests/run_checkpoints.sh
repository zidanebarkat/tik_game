#!/usr/bin/env bash
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/home/dev/godot441/Godot_v4.4.1-stable_linux.x86_64}"
PASS_ALL=1
for n in 0 1 2 3 4 5 6 7 9 10 11 12 13 14 16 ground surface; do
    echo "===== checkpoint$n ====="
    case "$n" in
        ground) script="tests/checkpoint_ground.gd"; marker="PART1 GROUND RESULT fail=" ;;
        surface) script="tests/checkpoint_surface.gd"; marker="PART4 SURFACE RESULT fail=" ;;
        *) script="tests/checkpoint${n}.gd"; marker="CHECKPOINT${n} RESULT pass=" ;;
    esac
    out=$("$GODOT" --path . --headless -s "$script" 2>&1)
    status=$?
    echo "$out" | grep -E "^(PASS|FAIL|CHECKPOINT|PART[0-9]|SCRIPT ERROR|Parse Error|ERROR)" || true
    if ! echo "$out" | grep -q "$marker"; then
        echo "!! checkpoint$n did not complete (exit=$status)"
        echo "$out" | tail -20
        PASS_ALL=0
    elif echo "$out" | grep -q "fail=[1-9]"; then
        PASS_ALL=0
    fi
done
if [ "$PASS_ALL" -eq 1 ]; then
    echo "ALL CHECKPOINTS PASS"
else
    echo "SOME CHECKPOINTS FAILED"
    exit 1
fi
