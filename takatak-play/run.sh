#!/usr/bin/env bash
# Run inside the project venv (.env). Works from the desktop or over SSH.
#   ./run.sh [game args]      the game (e.g. --camera noir --difficulty kid --windowed)
#   ./run.sh debug [args]     tools/pose_debug.py
#   ./run.sh text  [args]     tools/text_audio_check.py
#   ./run.sh audio [args]     tools/make_placeholder_audio.py
#   ./run.sh record [args]    tools/record_test_clip.py (DEV ONLY)
#   ./run.sh test             pytest
#   ./run.sh check            cameras + Hailo hardware check
set -euo pipefail
cd "$(dirname "$0")"
VENV_DIR="${VENV_DIR:-.env}"
PY="$VENV_DIR/bin/python"
[[ -x "$PY" ]] || { echo "venv $VENV_DIR missing: run ./install.sh first"; exit 1; }

# Started over SSH? Attach to the Pi's desktop session so the TV shows the window.
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  for s in "$XDG_RUNTIME_DIR"/wayland-*; do
    [[ -S "$s" ]] && { export WAYLAND_DISPLAY=$(basename "$s"); break; }
  done
  export DISPLAY=:0
fi

cmd="${1:-game}"
case "$cmd" in
  debug)  shift; exec "$PY" tools/pose_debug.py "$@" ;;
  text)   shift; exec "$PY" tools/text_audio_check.py "$@" ;;
  audio)  shift; exec "$PY" tools/make_placeholder_audio.py "$@" ;;
  record) shift; exec "$PY" tools/record_test_clip.py "$@" ;;
  test)   shift; exec "$PY" -m pytest -q tests "$@" ;;
  check)
    hailortcli fw-control identify || true
    rpicam-hello --list-cameras || true
    exec "$PY" -c "from picamera2 import Picamera2; [print(c) for c in Picamera2.global_camera_info()]" ;;
  game)   shift || true; exec "$PY" main.py "$@" ;;
  *)      exec "$PY" main.py "$@" ;;
esac
