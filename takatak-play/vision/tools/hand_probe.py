#!/usr/bin/env python3
"""DEV ONLY: is finger tracking feasible on this kit? One command, no vision service:

  ./run.sh handprobe              window: camera + arms + a box around each estimated hand
  ./run.sh handprobe --no-window --seconds 20      terminal only
  ./run.sh handprobe --mock       synthetic child, no camera (to try the tool on a PC)

It runs the camera and pose model itself (like ./run.sh debug), so stop the vision service
or the game first: they hold the camera. Stand on the mat at the children's play distance
and move your hands.

From pose keypoints (hand length ≈ 0.6 × forearm) it shows, live:
  - each hand's size in pixels of the main camera stream, as a coloured box:
      green  ≥ MIN_HAND_PX: finger models can work from the normal stream
      gold   only from high-resolution hand crops taken from the full sensor
      red    too small even at full sensor resolution
  - running median and 10–90 % range, pose rate, verdict
  - hand-landmark / palm-detection HEFs installed for the Hailo
The picture is only shown on screen: nothing is recorded or saved.
Keys: R reset the numbers · Esc / Q quit (the summary is printed in the terminal).
"""
import argparse
import glob
import io
import os
import statistics
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from takatak_vision.build import require_dev  # noqa: E402
from takatak_vision.config import load_config  # noqa: E402
from takatak_vision.lifecycle import Shutdown  # noqa: E402

HAND_PER_FOREARM = 0.6
MIN_HAND_PX = 80           # rough minimum hand size for 21-point hand-landmark models
SENSOR_W = {"wide": 4608, "noir": 4608, "imx500": 4056}
GREEN, GOLD, RED, WHITE, SKY = (110, 230, 110), (255, 205, 40), (255, 100, 90), (255, 255, 255), (90, 200, 255)


def hand_hefs():
    here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return sorted(glob.glob("/usr/share/hailo-models/*hand*") + glob.glob("/usr/share/hailo-models/*palm*")
                  + glob.glob(os.path.join(here, "models", "*", "*hand*"))
                  + glob.glob(os.path.join(here, "models", "*", "*palm*")))


def hands_of(people, main_w, main_h):
    """→ [(centre_norm (x, y), hand_len_px, side)] for active players' raised-or-not hands."""
    out = []
    for p in people:
        if not p.get("active"):
            continue
        for side in ("l", "r"):
            w, e = p["kp"].get(f"{side}_wrist"), p["kp"].get(f"{side}_elbow")
            if not (w and e and w[2] > 0.4 and e[2] > 0.4):
                continue
            fx, fy = (w[0] - e[0]) * main_w, (w[1] - e[1]) * main_h
            size = (fx * fx + fy * fy) ** 0.5 * HAND_PER_FOREARM
            centre = (w[0] + (w[0] - e[0]) * 0.5, w[1] + (w[1] - e[1]) * 0.5)
            out.append((centre, size, side))
    return out


def classify(px, sensor_scale):
    if px >= MIN_HAND_PX:
        return "ok", GREEN
    if px * sensor_scale >= MIN_HAND_PX:
        return "crop", GOLD
    return "small", RED


VERDICT = {
    "ok": "finger tracking OK from the main camera stream",
    "crop": "finger tracking only with high-resolution hand crops from the sensor",
    "small": "hands too small even at full resolution: finger tracking not reliable here",
}


def summary(sizes, poses, secs, camera, main_w):
    lines = [f"pose rate: {poses / max(secs, 1e-6):.1f} /s"]
    if not sizes:
        lines.append("no active player's forearm seen: stand on the mat and move your arms")
    else:
        s = sorted(sizes)
        med = statistics.median(s)
        scale = SENSOR_W.get(camera, 4608) / main_w
        lines.append(f"hand length, main stream ({main_w}px wide): median {med:.0f}px "
                     f"(10–90 %: {s[len(s) // 10]:.0f}–{s[len(s) * 9 // 10]:.0f}px, {len(s)} samples)")
        lines.append(f"hand length at full sensor resolution ({camera}): ≈ {med * scale:.0f}px")
        lines.append("verdict: " + VERDICT[classify(med, scale)[0]])
    hefs = hand_hefs()
    lines.append("hand-landmark HEFs: " + (", ".join(os.path.basename(h) for h in hefs) if hefs else
                 "none installed (Hailo Model Zoo: hand_landmark_lite / palm_detection_lite)"))
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seconds", type=float, default=0, help="stop after this long (0 = until Esc; "
                    "--no-window defaults to 20)")
    ap.add_argument("--no-window", action="store_true")
    ap.add_argument("--windowed", action="store_true", help="1280×720 window instead of full screen")
    ap.add_argument("--mock", action="store_true", help="synthetic child, no hardware")
    ap.add_argument("--camera", choices=["wide", "noir", "imx500", "auto"])
    args = ap.parse_args()
    require_dev("hand_probe.py")
    cfg = load_config()
    if args.camera:
        cfg["camera"] = args.camera
    secs_limit = args.seconds or (20.0 if args.no_window else 0.0)
    if not args.mock:
        from takatak_vision.main import port_in_use
        if port_in_use(cfg["server"]["host"], cfg["server"]["port"]):
            sys.exit("The vision service (or the game) is running and holds the camera.\n"
                     "Stop it first:  pkill -INT -f takatak_vision.main   then run ./run.sh handprobe again.")
    stop = Shutdown()
    if args.mock:
        from takatak_vision.mock import MockPerformer, MockSource
        source = MockSource(cfg, MockPerformer(auto=True))
    else:
        from takatak_vision.pipeline import HardwareSource
        source = HardwareSource(cfg)
    source.start()
    source.set_frames_wanted(not args.no_window)
    main_w, main_h = cfg["camera_opts"]["main_size"]
    sizes, poses, res_seq = [], 0, 0
    t0 = time.monotonic()
    camera = str(source.camera_name)

    screen = None
    if not args.no_window:
        import pygame
        pygame.init()
        if args.windowed:
            screen = pygame.display.set_mode((1280, 720))
        else:
            screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
            pygame.mouse.set_visible(False)
        pygame.display.set_caption("Takatak hand probe")
        W, H = screen.get_size()
        u = H / 1080
        font = pygame.font.SysFont(None, int(40 * u))
        small = pygame.font.SysFont(None, int(30 * u))
        clock = pygame.time.Clock()
        frame_surf, frame_rect, frame_seq, people = None, pygame.Rect(0, 0, W, H), 0, []

        def to_screen(x, y):
            return int(frame_rect.x + x * frame_rect.w), int(frame_rect.y + y * frame_rect.h)

        def text(s, pos, f=font, color=WHITE):
            img = f.render(s, True, color)
            bg = pygame.Surface((img.get_width() + 12, img.get_height() + 6), pygame.SRCALPHA)
            bg.fill((0, 0, 0, 170))
            screen.blit(bg, (pos[0] - 6, pos[1] - 3))
            screen.blit(img, pos)
            return img.get_height() + 10
    else:
        print(f"probing {secs_limit:.0f}s … stand on the mat and move your hands")

    try:
        while not stop.requested and (secs_limit <= 0 or time.monotonic() - t0 < secs_limit):
            seq, r = source.results.get()
            new_pose = r is not None and seq != res_seq
            if new_pose:
                res_seq = seq
                poses += 1
                people = r.pose_msg["people"] if screen is not None else r.pose_msg["people"]
                for _, size, _ in hands_of(r.pose_msg["people"], main_w, main_h):
                    sizes.append(size)
            camera = str(source.camera_name)
            if screen is None:
                time.sleep(0.01)
                continue
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT or (ev.type == pygame.KEYDOWN and ev.key in (pygame.K_ESCAPE, pygame.K_q)):
                    stop.request()
                elif ev.type == pygame.KEYDOWN and ev.key == pygame.K_r:
                    sizes, poses, t0 = [], 0, time.monotonic()
            fseq, item = source.frames.get()
            if item is not None and fseq != frame_seq:
                frame_seq = fseq
                img = pygame.image.load(io.BytesIO(item[1]), "f.jpg")
                fw, fh = img.get_size()
                s = max(W / fw, H / fh)
                frame_rect = pygame.Rect(0, 0, int(fw * s), int(fh * s))
                frame_rect.center = (W // 2, H // 2)
                frame_surf = pygame.transform.scale(img, frame_rect.size)
            if frame_surf is not None:
                screen.blit(frame_surf, frame_rect)
            else:
                screen.fill((18, 22, 48))
            scale = SENSOR_W.get(camera, 4608) / main_w
            px_per_main = frame_rect.w / main_w
            for p in people:
                if not p.get("active"):
                    continue
                kp = p["kp"]
                for a, b, col in (("l_shoulder", "l_elbow", SKY), ("l_elbow", "l_wrist", SKY),
                                  ("r_shoulder", "r_elbow", GOLD), ("r_elbow", "r_wrist", GOLD)):
                    if kp[a][2] > 0.3 and kp[b][2] > 0.3:
                        pygame.draw.line(screen, col, to_screen(*kp[a][:2]), to_screen(*kp[b][:2]), max(2, int(6 * u)))
            for centre, size, side in hands_of(people, main_w, main_h):
                _, col = classify(size, scale)
                half = max(6, int(size * px_per_main / 2))
                cx, cy = to_screen(*centre)
                pygame.draw.rect(screen, col, (cx - half, cy - half, half * 2, half * 2), max(2, int(5 * u)))
                text(f"{side.upper()} {size:.0f}px", (cx - half, cy - half - int(36 * u)), small, col)
            y = 16
            for i, line in enumerate(summary(sizes, poses, time.monotonic() - t0, camera, main_w)):
                col = WHITE
                if line.startswith("verdict"):
                    col = GREEN if "OK" in line else (GOLD if "crops" in line else RED)
                y += text(line, (16, y), font if i < 4 else small, col)
            y += text(f"box colours: green ≥ {MIN_HAND_PX}px usable · gold needs sensor crops · red too small"
                      "      R reset · Esc quit", (16, y), small, (200, 200, 210))
            for e in source.errors():
                y += text(e, (16, y), small, RED)
            pygame.display.flip()
            clock.tick(30)
    finally:
        elapsed = time.monotonic() - t0
        print()
        for line in summary(sizes, poses, elapsed, camera, main_w):
            print(line)
        steps = [source.stop]
        if screen is not None:
            steps.append(pygame.quit)
        stop.shutdown(*steps)


if __name__ == "__main__":
    main()
