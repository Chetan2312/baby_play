#!/usr/bin/env bash
# Put a Hailo-8 (NOT 8L) yolov8s_pose.hef into models/.
#  1. already there → verify
#  2. copy from /usr/share/hailo-models (apt hailo-models, version-matched)
#  3. download from the Hailo Model Zoo, matched to the installed HailoRT
# Override: HEF_URL=https://... tools/fetch_model.sh   or copy a file to models/ yourself.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=models/yolov8s_pose.hef
mkdir -p models

verify() {
  if ! command -v hailortcli >/dev/null; then
    echo "  (hailortcli missing, skipping HEF check)"; return 0
  fi
  local info
  info=$(hailortcli parse-hef "$OUT" 2>&1 || true)
  if grep -qi "HAILO8L" <<<"$info"; then
    echo "!! $OUT is compiled for Hailo-8L. The AI HAT+ 26 TOPS is Hailo-8: replace it."
    return 1
  fi
  if grep -qi "HAILO8" <<<"$info"; then
    echo "OK: $OUT is a Hailo-8 HEF"
  else
    echo "?? could not confirm the HEF architecture:"; echo "$info" | head -5
  fi
}

if [[ -f "$OUT" && -z "${HEF_URL:-}" ]]; then
  echo "$OUT exists"; verify; exit $?
fi

if [[ -z "${HEF_URL:-}" ]]; then
  for f in /usr/share/hailo-models/yolov8s_pose_h8.hef /usr/share/hailo-models/yolov8s_pose.hef \
           $(ls /usr/share/hailo-models/*pose*.hef 2>/dev/null | grep -vi h8l || true); do
    if [[ -f "$f" ]]; then
      echo "copying $f"; cp "$f" "$OUT"
      verify && exit 0
      rm -f "$OUT"
    fi
  done
fi

urls=()
if [[ -n "${HEF_URL:-}" ]]; then
  urls+=("$HEF_URL")
else
  rt=$(hailortcli --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1 || true)
  case "$rt" in
    4.17) zoo=(v2.11.0) ;;
    4.18) zoo=(v2.12.0) ;;
    4.19) zoo=(v2.13.0) ;;
    4.20) zoo=(v2.14.0) ;;
    4.21) zoo=(v2.15.0) ;;
    4.22) zoo=(v2.16.0) ;;
    *)    zoo=(v2.16.0 v2.15.0 v2.14.0 v2.13.0) ;;
  esac
  echo "HailoRT ${rt:-unknown} → trying Model Zoo ${zoo[*]}"
  for v in "${zoo[@]}"; do
    urls+=("https://hailo-model-zoo.s3.eu-west-2.amazonaws.com/ModelZoo/Compiled/$v/hailo8/yolov8s_pose.hef")
  done
fi

for u in "${urls[@]}"; do
  echo "downloading $u"
  if curl -fL --retry 2 -o "$OUT.part" "$u"; then
    mv "$OUT.part" "$OUT"
    verify && exit 0
  fi
  rm -f "$OUT.part"
done

cat <<EOF
!! Could not get a Hailo-8 yolov8s_pose.hef automatically.
   Get it from the Hailo Model Zoo (Compiled → hailo8 → yolov8s_pose.hef) for
   your HailoRT version ($(hailortcli --version 2>/dev/null || echo '?')), or from the
   hailo-rpi5-examples download_resources.sh, and copy it to $OUT.
EOF
exit 1
