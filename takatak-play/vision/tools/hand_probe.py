#!/usr/bin/env python3
"""DEV ONLY: live hand tracking — 21 landmarks per hand, all five fingers, finger count,
open / fist / POINT (index only). One command, no vision service:

  ./run.sh handprobe                       full screen
  ./run.sh handprobe --windowed            1280×720 window
  ./run.sh handprobe --video clip.mp4      a recorded clip instead of the camera (PC testing)

Setup once (needs internet once): .env/bin/pip install -r vision/requirements-hands.txt
                                  and vision/tools/fetch_hand_model.sh
It runs the camera + pose model itself, so stop the vision service / game first (they
hold the camera).

How: the pose model finds each active player's wrists and elbows; a box around each hand
is cut from a HIGH-RESOLUTION frame (--main-size, default 1920×1080) and given to the
MediaPipe Hand Landmarker (CPU). Shown: the boxes, the 21 points and bones per hand,
"L 5 open" / "R 1 POINT" labels, zoomed hand views top right, and timings.
The picture is only shown on screen: nothing is recorded or saved.
Keys: Esc / Q quit (a summary is printed in the terminal).
"""
import argparse
import collections
import os
import statistics
import sys
import time

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from takatak_vision import hands as H  # noqa: E402
from takatak_vision.build import require_dev  # noqa: E402
from takatak_vision.config import load_config  # noqa: E402
from takatak_vision.lifecycle import Shutdown  # noqa: E402

GREEN, GOLD, RED, WHITE, SKY, GREY = (110, 230, 110), (255, 205, 40), (255, 100, 90), (255, 255, 255), \
    (90, 200, 255), (160, 160, 170)
GESTURE_COL = {"point": GREEN, "open": SKY, "fist": GOLD, "other": WHITE}
INSET = 280


def downscale(rgb, w, h):
    try:
        import cv2
        return cv2.resize(rgb, (w, h), interpolation=cv2.INTER_AREA)
    except ImportError:
        sy, sx = max(1, rgb.shape[0] // h), max(1, rgb.shape[1] // w)
        return np.ascontiguousarray(rgb[::sy, ::sx])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--windowed", action="store_true")
    ap.add_argument("--video", help="recorded clip instead of the camera")
    ap.add_argument("--camera", choices=["wide", "noir", "imx500", "auto"])
    ap.add_argument("--main-size", default="1920x1080", help="camera frame the hands are cut from")
    ap.add_argument("--box-scale", type=float, default=2.4, help="hand box side ÷ estimated hand length")
    args = ap.parse_args()
    require_dev("hand_probe.py")
    cfg = load_config()
    if args.camera:
        cfg["camera"] = args.camera
    mw, mh = (int(v) for v in args.main_size.lower().split("x"))
    cfg["camera_opts"]["main_size"] = [mw, mh]
    try:
        tracker = H.HandTracker()
    except H.HandsError as e:
        sys.exit(str(e))
    if not args.video:
        from takatak_vision.main import port_in_use
        if port_in_use(cfg["server"]["host"], cfg["server"]["port"]):
            sys.exit("The vision service (or the game) is running and holds the camera.\n"
                     "Stop it first:  pkill -INT -f takatak_vision.main   then run ./run.sh handprobe again.")
    import pygame
    from takatak_vision.pipeline import HardwareSource

    stop = Shutdown()
    source = HardwareSource(cfg, args.video)
    source.start()
    source.set_frames_wanted(False)        # we draw the raw frame ourselves; no JPEG needed
    mirror = cfg["display"]["mirror"]

    pygame.init()
    if args.windowed:
        screen = pygame.display.set_mode((1280, 720))
    else:
        screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
        pygame.mouse.set_visible(False)
    pygame.display.set_caption("Takatak hand tracking")
    W, H_ = screen.get_size()
    u = H_ / 1080
    font = pygame.font.SysFont(None, int(40 * u))
    small = pygame.font.SysFont(None, int(30 * u))
    clock = pygame.time.Clock()

    def text(s, pos, f=font, color=WHITE):
        img = f.render(s, True, color)
        bg = pygame.Surface((img.get_width() + 12, img.get_height() + 6), pygame.SRCALPHA)
        bg.fill((0, 0, 0, 170))
        screen.blit(bg, (pos[0] - 6, pos[1] - 3))
        screen.blit(img, pos)
        return img.get_height() + 10

    hand_ms = collections.deque(maxlen=120)
    found = collections.deque(maxlen=300)
    gestures = collections.Counter()
    sizes = []
    people, res_seq, poses, t0 = [], 0, 0, time.monotonic()
    loop_t, loop_fps = time.monotonic(), 0.0
    try:
        while not stop.requested:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT or (ev.type == pygame.KEYDOWN and ev.key in (pygame.K_ESCAPE, pygame.K_q)):
                    stop.request()
            seq, r = source.results.get()
            if r is not None and seq != res_seq:
                res_seq, people = seq, r.pose_msg["people"]
                poses += 1
            _, bundle = source.cam.slot.get()
            if bundle is None:
                screen.fill((18, 22, 48))
                y = 16
                for e in source.errors() or ["waiting for the camera…"]:
                    y += text(e, (16, y), small, RED)
                pygame.display.flip()
                clock.tick(30)
                continue
            frame = bundle.main                        # (mh, mw, 4) RGBX, camera orientation
            fh, fw = frame.shape[:2]
            # picture: fit to screen, mirrored like the game
            s = min(W / fw, H_ / fh)
            dw, dh = int(fw * s), int(fh * s)
            ox, oy = (W - dw) // 2, (H_ - dh) // 2
            small_rgb = downscale(frame[..., :3], dw, dh)
            if mirror:
                small_rgb = np.ascontiguousarray(small_rgb[:, ::-1])
            screen.fill((0, 0, 0))
            screen.blit(pygame.image.frombuffer(small_rgb.tobytes(), (small_rgb.shape[1], small_rgb.shape[0]), "RGB"),
                        (ox, oy))

            def to_screen(xn, yn):   # camera-normalised → screen (mirrored)
                return int(ox + ((1.0 - xn) if mirror else xn) * dw), int(oy + yn * dh)

            now_ms = time.monotonic() * 1000
            keys, insets = set(), []
            for p in people:
                if not p.get("active"):
                    continue
                for side in ("l", "r"):
                    w, e = p["kp"].get(f"{side}_wrist"), p["kp"].get(f"{side}_elbow")
                    if not (w and e and w[2] > 0.35 and e[2] > 0.35):
                        continue
                    # wire coords are display (mirrored) → back to camera orientation
                    wc = ((1.0 - w[0]) if mirror else w[0], w[1])
                    ec = ((1.0 - e[0]) if mirror else e[0], e[1])
                    roi = H.hand_roi(wc, ec, fw, fh, scale=args.box_scale)
                    key = (p["id"], side)
                    keys.add(key)
                    t = time.monotonic()
                    hand = tracker.track(key, frame, roi, now_ms)
                    hand_ms.append((time.monotonic() - t) * 1000)
                    found.append(hand is not None)
                    sizes.append((roi[2] - roi[0]) / args.box_scale)
                    a, b = to_screen(roi[0] / fw, roi[1] / fh), to_screen(roi[2] / fw, roi[3] / fh)
                    box = pygame.Rect(min(a[0], b[0]), min(a[1], b[1]), abs(b[0] - a[0]), abs(b[1] - a[1]))
                    col = GESTURE_COL[hand["gesture"]] if hand else GREY
                    pygame.draw.rect(screen, col, box, max(2, int(4 * u)))
                    if hand is None:
                        text(f"{side.upper()} no hand", (box.x, box.y - int(34 * u)), small, GREY)
                        continue
                    gestures[hand["gesture"]] += 1
                    pts = [to_screen(x, y) for x, y, _ in hand["landmarks"]]
                    for i, j in H.CONNECTIONS:
                        pygame.draw.line(screen, col, pts[i], pts[j], max(2, int(3 * u)))
                    for i, pt in enumerate(pts):
                        pygame.draw.circle(screen, WHITE if i in H.TIPS else col, pt, max(3, int(5 * u)))
                    label = f"{side.upper()} {hand['count']} {hand['gesture'].upper()}"
                    text(label, (box.x, box.y - int(34 * u)), small, col)
                    insets.append((frame, roi, hand, label, col))
            tracker.forget(keys)
            # zoomed hand views, top right
            iy = 16
            for frame_, roi, hand, label, col in insets[:3]:
                x0, y0, x1, y1 = roi
                crop = downscale(np.ascontiguousarray(frame_[y0:y1, x0:x1, :3]), INSET, INSET)
                if mirror:
                    crop = np.ascontiguousarray(crop[:, ::-1])
                ix = W - INSET - 16
                screen.blit(pygame.image.frombuffer(crop.tobytes(), (INSET, INSET), "RGB"), (ix, iy))
                cw, ch = x1 - x0, y1 - y0
                ipts = []
                for x, y, _ in hand["landmarks"]:
                    cx = (x * fw - x0) / cw
                    ipts.append((int(ix + ((1 - cx) if mirror else cx) * INSET), int(iy + (y * fh - y0) / ch * INSET)))
                for i, j in H.CONNECTIONS:
                    pygame.draw.line(screen, col, ipts[i], ipts[j], 3)
                for i, pt in enumerate(ipts):
                    pygame.draw.circle(screen, WHITE if i in H.TIPS else col, pt, 5)
                pygame.draw.rect(screen, col, (ix, iy, INSET, INSET), 3)
                fingers = " ".join(n[0].upper() if up else "·" for n, up in zip(H.FINGERS, hand["fingers"]))
                text(f"{label}   {fingers}", (ix, iy + INSET + 6), small, col)
                iy += INSET + int(50 * u)
            # numbers
            now = time.monotonic()
            loop_fps = 0.9 * loop_fps + 0.1 / max(1e-3, now - loop_t)
            loop_t = now
            y = 16
            y += text(f"loop {loop_fps:4.1f} fps · pose {poses / max(1e-3, now - t0):4.1f}/s · "
                      f"hand model {statistics.mean(hand_ms) if hand_ms else 0:4.1f} ms/hand · "
                      f"found {100 * sum(found) / max(1, len(found)):3.0f} %", (16, y))
            y += text(f"camera frame {fw}×{fh} · hand ~{statistics.median(sizes[-60:]) if sizes else 0:.0f}px · "
                      "colours: green POINT · blue open · gold fist · white other · grey no hand", (16, y), small,
                      (210, 210, 220))
            for e in source.errors():
                y += text(e, (16, y), small, RED)
            pygame.display.flip()
            clock.tick(60)
    finally:
        el = time.monotonic() - t0
        print(f"\npose rate {poses / max(el, 1e-6):.1f}/s · hand model "
              f"{statistics.mean(hand_ms) if hand_ms else 0:.1f} ms/hand · hand found in "
              f"{100 * sum(found) / max(1, len(found)):.0f} % of boxes · hand ≈ "
              f"{statistics.median(sizes) if sizes else 0:.0f}px in the {mw}×{mh} frame")
        print("gestures seen:", dict(gestures) or "none")
        stop.shutdown(tracker.close, source.stop, pygame.quit)


if __name__ == "__main__":
    main()
