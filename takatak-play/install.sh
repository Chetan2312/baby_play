#!/usr/bin/env bash
# Takatak Play: one-shot setup on Raspberry Pi 5 (64-bit Raspberry Pi OS).
#
# What it touches:
#   • apt: Hailo driver/runtime, picamera2, pygame, fonts, espeak-ng. These are
#     system packages by necessity (kernel driver, firmware, libcamera bindings)
#     and cannot be pip-installed.
#   • Everything Python-only goes into ./.env (a venv with
#     --system-site-packages so it can see picamera2 + hailo bindings).
#   • Nothing outside this folder except apt and (with --pcie-gen3) config.txt.
#
# Usage:  ./install.sh [--full-upgrade] [--pcie-gen3] [--skip-apt]
set -euo pipefail
cd "$(dirname "$0")"
PROJECT_DIR=$(pwd)
VENV_DIR="${VENV_DIR:-.env}"

FULL_UPGRADE=0; PCIE_GEN3=0; SKIP_APT=0
for a in "$@"; do
  case "$a" in
    --full-upgrade) FULL_UPGRADE=1 ;;
    --pcie-gen3)    PCIE_GEN3=1 ;;
    --skip-apt)     SKIP_APT=1 ;;
    -h|--help) sed -n '2,14p' "$0"; exit 0 ;;
    *) echo "unknown option $a"; exit 2 ;;
  esac
done

say() { printf '\n\033[1;36m== %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!! %s\033[0m\n' "$*"; }

say "Checking platform"
arch=$(uname -m)
model=$(tr -d '\0' </proc/device-tree/model 2>/dev/null || echo unknown)
echo "arch: $arch   board: $model"
[[ "$arch" == "aarch64" ]] || warn "Expected aarch64 (64-bit Pi OS). Continuing anyway."
[[ "$model" == *"Raspberry Pi 5"* ]] || warn "This is not a Raspberry Pi 5."
. /etc/os-release 2>/dev/null && echo "os: ${PRETTY_NAME:-?}"

if [[ $SKIP_APT -eq 0 ]]; then
  say "apt packages"
  sudo apt update
  if [[ $FULL_UPGRADE -eq 1 ]]; then
    sudo apt full-upgrade -y
  else
    echo "(skipping full-upgrade; pass --full-upgrade if Hailo complains about the kernel/firmware)"
  fi

  # Hailo meta-package name differs between OS releases
  hailo_pkg=""
  for p in hailo-all hailo-h8-all; do
    if apt-cache show "$p" >/dev/null 2>&1; then hailo_pkg=$p; break; fi
  done
  if [[ -z "$hailo_pkg" ]]; then
    warn "No hailo-all package found in apt. Check the Raspberry Pi AI HAT+ docs for your OS release."
  fi

  sudo apt install -y $hailo_pkg dkms \
    python3-venv python3-picamera2 python3-opencv python3-numpy python3-pil python3-pygame \
    fonts-noto-core fonts-noto-ui-core libraqm0 espeak-ng ffmpeg curl
fi

if [[ $PCIE_GEN3 -eq 1 ]]; then
  say "PCIe Gen 3 for the AI HAT"
  CFG=/boot/firmware/config.txt
  if grep -q '^dtparam=pciex1_gen=3' "$CFG"; then
    echo "already enabled"
  else
    sudo cp "$CFG" "$CFG.takatak.bak"
    echo "dtparam=pciex1_gen=3" | sudo tee -a "$CFG" >/dev/null
    echo "added (backup: $CFG.takatak.bak). Reboot needed."
  fi
fi

say "Python venv in $VENV_DIR"
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  python3 -m venv --system-site-packages "$VENV_DIR"
fi
"$VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null
# numpy / pillow / pygame / opencv come from apt so they match picamera2 + hailo builds.
"$VENV_DIR/bin/python" -m pip install -r requirements.txt

say "Project folders"
mkdir -p logs/stats models assets/audio/{en,hi,mr} assets/sfx assets/fonts

say "Pose model (Hailo-8 yolov8s_pose.hef)"
tools/fetch_model.sh || warn "Model step failed. Fix it before running the game (see README)."

say "Placeholder audio (espeak-ng)"
"$VENV_DIR/bin/python" tools/make_placeholder_audio.py || warn "placeholder audio failed"

say "Self-check"
"$VENV_DIR/bin/python" - <<'EOF' || true
import importlib
ok = True
for m in ["numpy", "yaml", "PIL", "pygame", "cv2", "picamera2", "hailo_platform"]:
    try:
        mod = importlib.import_module(m)
        print(f"  ok   {m} {getattr(mod, '__version__', '')}")
    except Exception as e:
        ok = False
        print(f"  FAIL {m}: {e}")
try:
    from PIL import features
    print("  raqm (Devanagari shaping):", "ok" if features.check("raqm") else "MISSING (apt install libraqm0)")
except Exception as e:
    print("  raqm check failed:", e)
try:
    from picamera2 import Picamera2
    for c in Picamera2.global_camera_info():
        print(f"  camera {c.get('Num')}: {c.get('Model')}  {c.get('Id', '')}")
except Exception as e:
    print("  camera list failed:", e)
EOF
command -v hailortcli >/dev/null && hailortcli fw-control identify || warn "hailortcli identify failed (reboot after first install?)"

say "Unit tests"
"$VENV_DIR/bin/python" -m pytest -q tests || warn "tests failed"

cat <<EOF

Done. If this was the first Hailo install: sudo reboot

Next (from $PROJECT_DIR):
  ./run.sh check        # cameras + Hailo
  ./run.sh text         # M2: Devanagari + HDMI audio
  ./run.sh debug        # M1/M3: live skeleton, fps, gesture checks
  ./run.sh              # M4: the game
EOF
