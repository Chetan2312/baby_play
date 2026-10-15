#!/usr/bin/env bash
# Hand models → vision/models/
#   hand_landmarker.task       MediaPipe Hand Landmarker (float16, ~7.5 MB): palm detector + full landmarks
#   hand_landmark_lite.tflite  lite landmark model (~2 MB), hands.landmarks: lite (newer mediapipe
#                              packages no longer ship it)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p models
fetch() {
  local out=$1 url=$2
  if [[ -f "$out" ]]; then echo "$out exists"; return 0; fi
  curl -fL --retry 2 -o "$out.part" "$url" && mv "$out.part" "$out" && echo "saved $out"
}
fetch models/hand_landmarker.task \
  https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task
fetch models/hand_landmark_lite.tflite \
  https://storage.googleapis.com/mediapipe-assets/hand_landmark_lite.tflite
