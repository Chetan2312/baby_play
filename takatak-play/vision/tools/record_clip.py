#!/usr/bin/env python3
"""DEV ONLY: record a short test clip for offline gesture tuning.

PRIVACY: this saves video. Only record yourself, your own family or testers
who have given consent. Never commit clips (logs/clips/ is gitignored).
Replay a clip through the pipeline with:  ./run.sh debug --video logs/clips/<file>.mp4
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from takatak.camera import CameraError, find_camera_num  # noqa: E402
from takatak.config import load_config, path  # noqa: E402

WARNING = """
############################################################
#  DEV ONLY — THIS RECORDS VIDEO OF PEOPLE.                #
#  Record only yourself / consenting family or testers.   #
#  Files stay on this device in logs/clips/. Never share. #
############################################################
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--camera", choices=["wide", "noir"], default="wide")
    ap.add_argument("--seconds", type=int, default=20)
    ap.add_argument("--i-have-consent", action="store_true", required=True,
                    help="confirm everyone in frame consented to being recorded")
    args = ap.parse_args()
    print(WARNING)
    cfg = load_config()
    from picamera2 import Picamera2

    try:
        num = find_camera_num(args.camera, cfg)
    except CameraError as e:
        sys.exit(str(e))
    out_dir = path("logs/clips")
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{time.strftime('%Y%m%d_%H%M%S')}_{args.camera}.mp4")
    cam = Picamera2(num)
    cam.configure(cam.create_video_configuration(main={"size": tuple(cfg["camera_opts"]["main_size"])}))
    print(f"recording {args.seconds}s from {args.camera} → {out}")
    cam.start_and_record_video(out, duration=args.seconds)
    cam.close()
    print("saved", out)


if __name__ == "__main__":
    main()
