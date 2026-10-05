#!/usr/bin/env python3
"""DEV ONLY: record the vision service's message stream to JSONL for replay
(tools/mock_server.py --replay) and for tuning motion detectors offline.

By default only JSON messages (keypoints, gestures, status) are saved: no images.
--with-frames also saves the JPEG frames. That is video of people: use only
with consent, never share, never commit (logs/ is gitignored).
"""
import argparse
import base64
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from takatak_vision import protocol as P  # noqa: E402
from takatak_vision.build import require_dev  # noqa: E402
from takatak_vision.config import load_config, path  # noqa: E402

WARNING = """
############################################################
#  --with-frames SAVES IMAGES OF PEOPLE.                   #
#  Record only yourself / consenting family or testers.   #
#  Files stay in logs/sessions/. Never share or commit.   #
############################################################
"""


def main():
    require_dev("record_session.py")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--url", default=None)
    ap.add_argument("--seconds", type=float, default=30)
    ap.add_argument("--name", default="")
    ap.add_argument("--with-frames", action="store_true")
    ap.add_argument("--i-have-consent", action="store_true")
    args = ap.parse_args()
    if args.with_frames:
        print(WARNING)
        if not args.i_have_consent:
            sys.exit("--with-frames needs --i-have-consent")
    from websockets.sync.client import connect

    cfg = load_config()
    url = args.url or f"ws://{cfg['server']['host']}:{cfg['server']['port']}"
    out_dir = path(cfg["paths"]["sessions"])
    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{time.strftime('%Y%m%d_%H%M%S')}{'_' + args.name if args.name else ''}.jsonl")
    n_msgs = n_frames = 0
    with connect(url, max_size=2 ** 22) as ws, open(out, "w", encoding="utf-8") as f:
        ws.send(json.dumps({"t": "subscribe", "frames": args.with_frames}))
        t0 = time.monotonic()
        print(f"recording {args.seconds:.0f}s from {url} → {out}")
        while time.monotonic() - t0 < args.seconds:
            try:
                raw = ws.recv(timeout=1.0)
            except TimeoutError:
                continue
            rt = round(time.monotonic() - t0, 3)
            if isinstance(raw, bytes):
                if not args.with_frames:
                    continue
                kind, fid, payload = P.unpack_binary(raw)
                if kind == P.KIND_FRAME:
                    f.write(json.dumps({"rt": rt, "frame_id": fid,
                                        "frame": base64.b64encode(payload).decode()}) + "\n")
                    n_frames += 1
            else:
                f.write(json.dumps({"rt": rt, "msg": json.loads(raw)}, ensure_ascii=False) + "\n")
                n_msgs += 1
    print(f"saved {n_msgs} messages, {n_frames} frames → {out}")


if __name__ == "__main__":
    main()
