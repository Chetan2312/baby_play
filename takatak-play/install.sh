#!/usr/bin/env bash
# Takatak Play: setup on Raspberry Pi 5 (64-bit Raspberry Pi OS). Also works on a PC
# (x86_64 Linux) for game development with the mock vision server.
#
# What it touches:
#   • apt: Hailo driver/runtime, picamera2, fonts, espeak-ng, ffmpeg. These are system
#     packages by necessity (kernel driver, firmware, libcamera bindings).
#   • ./.env: Python venv (--system-site-packages so it sees picamera2 + hailo).
#   • ./.godot-bin: Godot 4 binary (with --with-godot). Nothing installed system-wide.
#   • /boot/firmware/config.txt only with --pcie-gen3 (backed up first).
#
# Usage: ./install.sh [--with-godot] [--full-upgrade] [--pcie-gen3] [--skip-apt] [--skip-content]
#   GODOT_VERSION=4.4.1 ./install.sh --with-godot     (pick the same version as your PC editor)
set -euo pipefail
cd "$(dirname "$0")"
VENV_DIR="${VENV_DIR:-.env}"
GODOT_VERSION="${GODOT_VERSION:-4.4.1}"

FULL_UPGRADE=0; PCIE_GEN3=0; SKIP_APT=0; WITH_GODOT=0; SKIP_CONTENT=0
for a in "$@"; do
  case "$a" in
    --full-upgrade) FULL_UPGRADE=1 ;;
    --pcie-gen3)    PCIE_GEN3=1 ;;
    --skip-apt)     SKIP_APT=1 ;;
    --with-godot)   WITH_GODOT=1 ;;
    --skip-content) SKIP_CONTENT=1 ;;
    -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
    *) echo "unknown option $a"; exit 2 ;;
  esac
done

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }

say "Platform"
arch=$(uname -m)
model=$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo "not a Pi")
echo "arch: $arch   board: $model"
IS_PI=0; [[ "$model" == *"Raspberry Pi 5"* ]] && IS_PI=1
[[ $IS_PI -eq 1 ]] || warn "Not a Raspberry Pi 5: skipping Hailo/camera parts (mock server still works)."

if [[ $SKIP_APT -eq 0 ]]; then
  say "apt packages"
  sudo apt update
  [[ $FULL_UPGRADE -eq 1 ]] && sudo apt full-upgrade -y
  pkgs=(python3-venv python3-numpy python3-pil python3-pygame python3-opencv python3-yaml
        fonts-noto-core fonts-noto-ui-core espeak-ng ffmpeg curl unzip)
  if [[ $IS_PI -eq 1 ]]; then
    hailo_pkg=""
    for p in hailo-all hailo-h8-all; do
      if apt-cache show "$p" >/dev/null 2>&1; then hailo_pkg=$p; break; fi
    done
    [[ -n "$hailo_pkg" ]] || warn "No hailo-all package in apt; see the Raspberry Pi AI HAT+ docs for your OS."
    pkgs+=($hailo_pkg dkms python3-picamera2 python3-simplejpeg)
  fi
  sudo apt install -y "${pkgs[@]}"
fi

if [[ $PCIE_GEN3 -eq 1 ]]; then
  say "PCIe Gen 3 for the AI HAT"
  CFG=/boot/firmware/config.txt
  if grep -q '^dtparam=pciex1_gen=3' "$CFG"; then echo "already enabled"
  else
    sudo cp "$CFG" "$CFG.takatak.bak"
    echo "dtparam=pciex1_gen=3" | sudo tee -a "$CFG" >/dev/null
    echo "added (backup: $CFG.takatak.bak). Reboot needed."
  fi
fi

say "Python venv ($VENV_DIR)"
[[ -x "$VENV_DIR/bin/python" ]] || python3 -m venv --system-site-packages "$VENV_DIR"
"$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
"$VENV_DIR/bin/python" -m pip install -r vision/requirements.txt

mkdir -p logs vision/models content/names

if [[ $IS_PI -eq 1 ]]; then
  say "Pose model (Hailo-8 yolov8s_pose.hef)"
  vision/tools/fetch_model.sh || warn "Model step failed. Fix it before running the vision service."
fi

if [[ $WITH_GODOT -eq 1 ]]; then
  say "Godot $GODOT_VERSION"
  case "$arch" in
    aarch64) garch=arm64 ;;
    x86_64)  garch=x86_64 ;;
    *) garch=""; warn "no Godot build for $arch" ;;
  esac
  if [[ -n "${garch:-}" ]]; then
    mkdir -p .godot-bin
    zip=".godot-bin/godot_${GODOT_VERSION}_${garch}.zip"
    url="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.${garch}.zip"
    if [[ ! -x .godot-bin/godot ]]; then
      curl -fL -o "$zip" "$url" && unzip -o -q "$zip" -d .godot-bin && rm -f "$zip"
      bin=$(ls .godot-bin/Godot_v*_linux.* 2>/dev/null | grep -v '\.zip$' | head -1)
      [[ -n "$bin" ]] && chmod +x "$bin" && ln -sf "$(basename "$bin")" .godot-bin/godot
    fi
    .godot-bin/godot --version || warn "Godot download failed ($url)"
    echo "(export templates are only needed to export a binary; run.sh runs the project directly)"
  fi
fi

if [[ $SKIP_CONTENT -eq 0 ]]; then
  say "Content: draft voices (espeak-ng) → OGG → build → lint"
  "$VENV_DIR/bin/python" tools/tts_drafts.py || warn "tts drafts failed"
  "$VENV_DIR/bin/python" tools/voice_pipeline.py || warn "voice pipeline failed"
  "$VENV_DIR/bin/python" tools/content_build.py
  "$VENV_DIR/bin/python" tools/content_lint.py || warn "content lint reported errors"
fi

say "Self-check"
"$VENV_DIR/bin/python" - <<'EOF' || true
import importlib
for m in ["numpy", "yaml", "websockets", "PIL", "pygame", "cv2", "simplejpeg", "picamera2", "hailo_platform"]:
    try:
        mod = importlib.import_module(m)
        print(f"  ok   {m} {getattr(mod, '__version__', '')}")
    except Exception as e:
        print(f"  --   {m}: {e}")
try:
    from picamera2 import Picamera2
    for c in Picamera2.global_camera_info():
        print(f"  camera {c.get('Num')}: {c.get('Model')}")
except Exception as e:
    print("  camera list skipped:", e)
EOF
if [[ $IS_PI -eq 1 ]]; then
  command -v hailortcli >/dev/null && hailortcli fw-control identify || warn "hailortcli identify failed (reboot after first install?)"
fi

say "Tests"
"$VENV_DIR/bin/python" -m pytest -q vision/tests tools/tests || warn "tests failed"

cat <<EOF

Done. First Hailo install? sudo reboot

  ./run.sh check        cameras + Hailo
  ./run.sh debug        vision debug viewer (pygame): skeleton, fps, gesture events
  ./run.sh vision       vision service (WebSocket :8765)
  ./run.sh game         Godot client (needs --with-godot or GODOT=/path/to/godot)
  ./run.sh play         vision + game together
  ./run.sh play-mock    mock vision + game (PC, no camera)
EOF
