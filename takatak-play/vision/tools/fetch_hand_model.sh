#!/usr/bin/env bash
# MediaPipe Hand Landmarker model (float16, ~7.5 MB) → vision/models/hand_landmarker.task
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=models/hand_landmarker.task
URL=https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
mkdir -p models
if [[ -f "$OUT" ]]; then echo "$OUT exists"; exit 0; fi
curl -fL --retry 2 -o "$OUT.part" "$URL" && mv "$OUT.part" "$OUT" && echo "saved $OUT"
