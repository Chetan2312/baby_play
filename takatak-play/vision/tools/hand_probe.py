#!/usr/bin/env python3
"""DEV ONLY: is finger tracking feasible on this kit? Run with the vision service running
and a child (or an adult at a child's play distance) moving on the mat:

  ./run.sh vision &      then      .env/bin/python vision/tools/hand_probe.py --seconds 20

Reports, from pose keypoints only (no images are read or saved):
  - hand size in pixels of the camera's main stream and of full sensor resolution
    (hand length ≈ 0.6 × forearm). Finger models (21-point hand landmarks) need the hand
    to be roughly ≥ 80–100 px across in the crop they are given.
  - pose message rate (what the game's pointer gets per second)
  - hand-landmark / palm-detection HEFs installed for the Hailo (apt hailo-models)
"""
import argparse
import glob
import json
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from takatak_vision.config import load_config  # noqa: E402

HAND_PER_FOREARM = 0.6
SENSOR_W = {"wide": 4608, "noir": 4608, "imx500": 4056}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default=None)
    ap.add_argument("--seconds", type=float, default=20)
    args = ap.parse_args()
    from websockets.sync.client import connect

    cfg = load_config()
    url = args.url or f"ws://{cfg['server']['host']}:{cfg['server']['port']}"
    main_w = cfg["camera_opts"]["main_size"][0]
    sizes, poses, camera = [], 0, cfg["camera"]
    try:
        ws = connect(url, max_size=2 ** 22)
    except OSError as e:
        sys.exit(f"Can't reach the vision service at {url} ({e}).\n"
                 "Start it first in another terminal:  ./run.sh vision\n"
                 "and wait for '[server] listening', then run this probe again.")
    with ws:
        ws.send(json.dumps({"t": "subscribe", "frames": False}))
        t0 = time.monotonic()
        print(f"probing {args.seconds:.0f}s from {url} … move your hands on the mat")
        while time.monotonic() - t0 < args.seconds:
            try:
                raw = ws.recv(timeout=1.0)
            except TimeoutError:
                continue
            if isinstance(raw, bytes):
                continue
            msg = json.loads(raw)
            if msg.get("t") == "hello":
                camera = msg.get("camera") or camera
            if msg.get("t") != "pose":
                continue
            poses += 1
            for p in msg.get("people", []):
                if not p.get("active"):
                    continue
                for side in ("l", "r"):
                    w, e = p["kp"].get(f"{side}_wrist"), p["kp"].get(f"{side}_elbow")
                    if w and e and w[2] > 0.4 and e[2] > 0.4:
                        fx = (w[0] - e[0]) * main_w
                        fy = (w[1] - e[1]) * main_w * 9 / 16
                        sizes.append((fx * fx + fy * fy) ** 0.5 * HAND_PER_FOREARM)
    secs = args.seconds
    print(f"\npose rate: {poses / secs:.1f} /s")
    if not sizes:
        print("no active player's forearm seen: stand on the mat and move your arms, then retry")
    else:
        med = statistics.median(sizes)
        sensor = med * SENSOR_W.get(camera, 4608) / main_w
        print(f"hand length, main stream ({main_w}px wide): median {med:.0f}px "
              f"(10–90 %: {sorted(sizes)[len(sizes) // 10]:.0f}–{sorted(sizes)[len(sizes) * 9 // 10]:.0f}px)")
        print(f"hand length at full sensor resolution ({camera}): ≈ {sensor:.0f}px")
        verdict = ("OK from the main stream" if med >= 80 else
                   "only with high-resolution hand crops from the sensor" if sensor >= 80 else
                   "too small even at full resolution: finger tracking not reliable at this distance")
        print(f"finger tracking: {verdict}")
    hefs = sorted(glob.glob("/usr/share/hailo-models/*hand*") + glob.glob("/usr/share/hailo-models/*palm*")
                  + glob.glob(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                           "models", "*", "*hand*")))
    print("hand-landmark HEFs:", ", ".join(hefs) if hefs else "none installed (check the Hailo Model Zoo "
          "for hand_landmark_lite / palm_detection_lite compiled for your accelerator)")


if __name__ == "__main__":
    main()
