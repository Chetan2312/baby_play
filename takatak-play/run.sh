#!/usr/bin/env bash
# Everything runs inside the project venv (.env). Works from the desktop or over SSH.
#   ./run.sh vision [args]    vision service, e.g. --camera noir | --video clip.mp4
#   ./run.sh mock [args]      mock vision server (synthetic child / --auto / --replay file)
#   ./run.sh debug [args]     pygame debug viewer (--mock works without hardware)
#   ./run.sh game [args]      Godot client, e.g. --windowed --deva-test --lang=hi --vision=ws://pi:8765
#   ./run.sh play [args]      vision service + game; stops the service when the game exits
#   ./run.sh play-mock        mock server + game
#   ./run.sh record [args]    record a session (keypoints only by default)
#   ./run.sh clip [args]      DEV ONLY: record a video clip (needs --i-have-consent)
#   ./run.sh content          draft voices → OGG → build JSON → lint
#   ./run.sh test             pytest (vision + content tools)
#   ./run.sh smoke            headless Godot session smoke test (no camera needed)
#   ./run.sh field-build      package a field build into dist/takatak-field
#   ./run.sh check            cameras + Hailo hardware check
#
# Build: vision/game/play run as TAKATAK_BUILD=field (no recording, no tester keys);
# mock/play-mock/debug/record/clip default to dev. Override: TAKATAK_BUILD=dev ./run.sh play
set -euo pipefail
cd "$(dirname "$0")"
ROOT=$(pwd)
VENV_DIR="${VENV_DIR:-.env}"
PY="$ROOT/$VENV_DIR/bin/python"
if [[ ! -x "$PY" ]]; then
  if [[ -f vision/takatak_vision/_build.py ]] && command -v python3 >/dev/null; then
    PY=$(command -v python3)   # field package on a provisioned Pi: system python3
  else
    echo "venv $VENV_DIR missing: run ./install.sh first"; exit 1
  fi
fi

# Started over SSH? Attach to the Pi's desktop session so windows open on the TV.
if [[ -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ]]; then
  export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  for s in "$XDG_RUNTIME_DIR"/wayland-*; do
    [[ -S "$s" ]] && { export WAYLAND_DISPLAY=$(basename "$s"); break; }
  done
  export DISPLAY=:0
fi

find_godot() {
  for g in "${GODOT:-}" "$ROOT/.godot-bin/godot" "$(command -v godot4 || true)" "$(command -v godot || true)"; do
    [[ -n "$g" && -x "$g" ]] && { echo "$g"; return 0; }
  done
  echo "Godot not found: ./install.sh --with-godot, or GODOT=/path/to/godot ./run.sh game" >&2
  return 1
}

run_game() {
  local godot
  godot=$(find_godot)
  [[ -f tools/content_build.py ]] && "$PY" tools/content_build.py >/dev/null
  if [[ ! -d game/.godot ]]; then
    echo "first run: letting Godot scan the project…"
    "$godot" --headless --path game --editor --quit >/dev/null 2>&1 || true
  fi
  # Pi 5 GPU = OpenGL ES 3.1 (no desktop GL 3.3). Ask for GLES directly: Godot's
  # automatic GL→GLES fallback on X11 aborts on the Pi.
  local render=()
  [[ "$(uname -m)" == "aarch64" ]] && render=(--rendering-driver opengl3_es)
  # Display: X11 (XWayland) by default. Godot 4.4's native Wayland can't create an
  # EGL display on the Pi 5. On a PC desktop, Wayland first is fine.
  # Override: GODOT_DISPLAY=wayland ./run.sh game
  local displays=(x11)
  if [[ -n "${GODOT_DISPLAY:-}" ]]; then
    displays=("$GODOT_DISPLAY")
  elif [[ -n "${WAYLAND_DISPLAY:-}" && "$(uname -m)" != "aarch64" ]]; then
    displays=(wayland x11)
  fi
  local d rc t0
  for d in "${displays[@]}"; do
    echo "starting Godot: display=$d ${render[*]}"
    t0=$SECONDS
    set +e
    "$godot" --display-driver "$d" "${render[@]}" --path game -- "$@"
    rc=$?
    set -e
    # normal quit, or it ran for a while (not a startup failure) → done
    if [[ $rc -eq 0 ]] || (( SECONDS - t0 > 10 )); then
      return $rc
    fi
    echo "Godot failed to start with display=$d (exit $rc)"
  done
  return 1
}

BG_PID=""
stop_background() {
  if [[ -n "$BG_PID" ]]; then
    kill -INT "$BG_PID" 2>/dev/null || true
    wait "$BG_PID" 2>/dev/null || true
    BG_PID=""
  fi
}

with_background() {  # run "$@" in background while the game runs, stop it afterwards
  "$@" &
  BG_PID=$!
  trap stop_background EXIT
  sleep 2
  if ! kill -0 "$BG_PID" 2>/dev/null; then
    BG_PID=""
    echo "background service exited (see the error above); not starting the game"
    exit 1
  fi
}

cmd="${1:-help}"
[[ $# -gt 0 ]] && shift
case "$cmd" in
  mock|play-mock|debug|record|clip) export TAKATAK_BUILD="${TAKATAK_BUILD:-dev}" ;;
  *) export TAKATAK_BUILD="${TAKATAK_BUILD:-field}" ;;
esac
need() {  # dev tools are not in field packages
  [[ -e "$1" ]] || { echo "$1 is not part of this build (field package: dev tools are left out)"; exit 1; }
}
case "$cmd" in
  vision)    cd vision && exec "$PY" -m takatak_vision.main "$@" ;;
  mock)      need vision/tools/mock_server.py; exec "$PY" vision/tools/mock_server.py "$@" ;;
  debug)     need vision/tools/debug_view.py; exec "$PY" vision/tools/debug_view.py "$@" ;;
  record)    need vision/tools/record_session.py; exec "$PY" vision/tools/record_session.py "$@" ;;
  clip)      need vision/tools/record_clip.py; exec "$PY" vision/tools/record_clip.py "$@" ;;
  game)      run_game "$@" ;;
  play)      with_background bash -c "cd '$ROOT/vision' && exec '$PY' -m takatak_vision.main"; run_game "$@" ;;
  play-mock) need vision/tools/mock_server.py; with_background "$PY" vision/tools/mock_server.py; run_game --windowed "$@" ;;
  smoke)
    godot=$(find_godot)
    "$PY" tools/content_build.py >/dev/null
    [[ -d game/.godot ]] || "$godot" --headless --path game --editor --quit >/dev/null 2>&1 || true
    tmp=$(mktemp -d)
    "$godot" --headless --path game res://tests/SessionSmoke.tscn -- --usage-dir="$tmp" ;;
  field-build) need tools/make_field_build.py; exec "$PY" tools/make_field_build.py "$@" ;;
  content)
    need tools/content_build.py
    "$PY" tools/tts_drafts.py
    "$PY" tools/voice_pipeline.py
    "$PY" tools/content_build.py
    exec "$PY" tools/content_lint.py ;;
  test)      exec "$PY" -m pytest -q vision/tests tools/tests "$@" ;;
  check)
    hailortcli fw-control identify || true
    rpicam-hello --list-cameras || true
    exec "$PY" -c "from picamera2 import Picamera2; [print(c) for c in Picamera2.global_camera_info()]" ;;
  *) sed -n '2,19p' "$0" ;;
esac
