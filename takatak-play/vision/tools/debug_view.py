#!/usr/bin/env python3
"""Debug viewer (pygame): runs the vision pipeline in-process and draws exactly
what the game receives: the mirrored JPEG, the normalised keypoints and the
gesture events, plus fps and live check scores.

Can't share the camera with a running vision service: stop that first.

Keys: C switch camera · T toddler/kid · M single/duo · I keypoint names · Esc/Q quit
  --mock   use the synthetic child instead of camera + Hailo (works on a PC)
"""
import argparse
import collections
import io
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pygame  # noqa: E402

from takatak_vision.config import load_config  # noqa: E402
from takatak_vision.gestures import KEYPOINT_NAMES, LEFT_SIDE, SKELETON  # noqa: E402
from takatak_vision.lifecycle import Shutdown  # noqa: E402

GOLD, GREEN, SKY, ORANGE, WHITE = (255, 205, 40), (120, 230, 120), (90, 200, 255), (255, 150, 60), (255, 255, 255)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--camera", choices=["wide", "noir", "auto"])
    ap.add_argument("--windowed", action="store_true")
    ap.add_argument("--video", help="DEV ONLY: recorded clip instead of camera")
    ap.add_argument("--mock", action="store_true", help="synthetic child, no hardware")
    args = ap.parse_args()
    cfg = load_config()
    if args.camera:
        cfg["camera"] = args.camera
    stop = Shutdown()

    if args.mock:
        from takatak_vision.mock import MockPerformer, MockSource
        source = MockSource(cfg, MockPerformer(auto=True))
    else:
        from takatak_vision.pipeline import HardwareSource
        source = HardwareSource(cfg, args.video)
    source.start()
    source.set_frames_wanted(True)

    pygame.init()
    if args.windowed:
        screen = pygame.display.set_mode((1280, 720))
    else:
        screen = pygame.display.set_mode((0, 0), pygame.FULLSCREEN)
        pygame.mouse.set_visible(False)
    pygame.display.set_caption("Takatak vision debug")
    W, H = screen.get_size()
    u = H / 1080
    font = pygame.font.SysFont(None, int(40 * u))
    small = pygame.font.SysFont(None, int(28 * u))
    clock = pygame.time.Clock()

    gesture_log = collections.deque(maxlen=10)
    states = {}            # (player, name) -> state
    res_seq = frame_seq = 0
    frame_surf, frame_rect, res = None, pygame.Rect(0, 0, W, H), None
    labels = True
    difficulty = cfg["gestures"]["default_difficulty"]
    mode = cfg["tracker"]["mode"]
    ui_frames, ui_t0, ui_fps = 0, time.monotonic(), 0.0

    def to_screen(x, y):
        return int(frame_rect.x + x * frame_rect.w), int(frame_rect.y + y * frame_rect.h)

    def text(s, pos, f=font, color=WHITE):
        img = f.render(s, True, color)
        bg = pygame.Surface((img.get_width() + 12, img.get_height() + 6), pygame.SRCALPHA)
        bg.fill((0, 0, 0, 160))
        screen.blit(bg, (pos[0] - 6, pos[1] - 3))
        screen.blit(img, pos)
        return img.get_height() + 10

    running = True
    try:
        while running and not stop.requested:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    running = False
                elif ev.type == pygame.KEYDOWN:
                    if ev.key in (pygame.K_ESCAPE, pygame.K_q):
                        running = False
                    elif ev.key == pygame.K_c:
                        source.set_camera("noir" if source.camera_name == "wide" else "wide")
                    elif ev.key == pygame.K_t:
                        difficulty = "kid" if difficulty == "toddler" else "toddler"
                        source.set_difficulty(difficulty)
                    elif ev.key == pygame.K_m:
                        mode = "duo" if mode == "single" else "single"
                        source.set_players(mode)
                    elif ev.key == pygame.K_i:
                        labels = not labels

            seq, item = source.frames.get()
            if item is not None and seq != frame_seq:
                frame_seq = seq
                img = pygame.image.load(io.BytesIO(item[1]), "f.jpg")
                fw, fh = img.get_size()
                s = max(W / fw, H / fh)
                frame_rect = pygame.Rect(0, 0, int(fw * s), int(fh * s))
                frame_rect.center = (W // 2, H // 2)
                frame_surf = pygame.transform.scale(img, frame_rect.size)
            seq, r = source.results.get()
            if r is not None and seq != res_seq:
                res_seq, res = seq, r
                for e in r.events:
                    states[(e["player"], e["name"])] = e["state"]
                    gesture_log.appendleft(f"p{e['player']} {e['name']} {e['state']} {e['confidence']:.2f}")

            if frame_surf is not None:
                screen.blit(frame_surf, frame_rect)
            else:
                screen.fill((18, 22, 48))

            if res is not None:
                for p in res.pose_msg["people"]:
                    kp = p["kp"]
                    x1, y1 = to_screen(p["bbox"][0], p["bbox"][1])
                    x2, y2 = to_screen(p["bbox"][2], p["bbox"][3])
                    pygame.draw.rect(screen, GOLD if p["active"] else (150, 150, 150),
                                     (x1, y1, x2 - x1, y2 - y1), 6 if p["active"] else 2)
                    text(f"id {p['id']}{' ACTIVE' if p['active'] else ''}", (x1, y1 - 40), small)
                    for a, b in SKELETON:
                        na, nb = KEYPOINT_NAMES[a], KEYPOINT_NAMES[b]
                        if kp[na][2] >= cfg["inference"]["min_kp_conf"] and kp[nb][2] >= cfg["inference"]["min_kp_conf"]:
                            col = SKY if a in LEFT_SIDE and b in LEFT_SIDE else (
                                ORANGE if a not in LEFT_SIDE and b not in LEFT_SIDE else WHITE)
                            pygame.draw.line(screen, col, to_screen(*kp[na][:2]), to_screen(*kp[nb][:2]),
                                             max(2, int(6 * u)))
                    for i, n in enumerate(KEYPOINT_NAMES):
                        if kp[n][2] >= cfg["inference"]["min_kp_conf"]:
                            pt = to_screen(*kp[n][:2])
                            pygame.draw.circle(screen, GOLD, pt, max(3, int(8 * u)))
                            if labels:
                                screen.blit(small.render(n, True, WHITE), (pt[0] + 8, pt[1] - 10))

            ui_frames += 1
            now = time.monotonic()
            if now - ui_t0 >= 1.0:
                ui_fps, ui_frames, ui_t0 = ui_frames / (now - ui_t0), 0, now
                source.tick()
            fps = source.perf.fps()
            y = 16
            y += text(f"{'  '.join(f'{k} {v:4.1f}' for k, v in fps.items())}  ui {ui_fps:4.1f} fps   "
                      f"lat {source.perf.latency_ms.value:3.0f} ms", (16, y))
            y += text(f"camera: {source.camera_name}   tolerances: {difficulty} (T)   players: {mode} (M)", (16, y))
            if res is not None:
                y += text(f"active: {res.active_ids}   no_player: {res.no_player_s:.1f}s", (16, y))
            for e in source.errors():
                y += text(e, (16, y), color=ORANGE)

            # live check states for active players, right column
            y = 16
            on = sorted((k, v) for k, v in states.items() if v != "end")
            for (pid, name), st in on:
                y += text(f"p{pid} {name}: {st}", (W - int(460 * u), y), color=GREEN if st == "held" else GOLD)
            y = H - int(40 * u) * (len(gesture_log) + 1)
            for line in gesture_log:
                y += text(line, (16, y), small)
            pygame.display.flip()
            clock.tick(30)
    finally:
        print("[exit] closing vision pipeline…", flush=True)
        stop.shutdown(source.stop, pygame.quit)


if __name__ == "__main__":
    main()
