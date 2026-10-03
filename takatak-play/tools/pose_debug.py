#!/usr/bin/env python3
"""M1/M3: live mirrored feed + skeleton + keypoint indices + fps + gesture checks.

Keys: C switch camera · T toggle difficulty (tolerances) · I toggle indices · Esc quit
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pygame  # noqa: E402

from main import start_pipeline, status_messages  # noqa: E402
from takatak import gestures as G  # noqa: E402
from takatak.audio import AudioPlayer  # noqa: E402
from takatak.config import load_config, path  # noqa: E402
from takatak.lifecycle import Shutdown  # noqa: E402
from takatak.perf import PerfLog  # noqa: E402
from takatak.player import KeypointSmoother, PlayerTracker  # noqa: E402
from takatak.text import TextRenderer  # noqa: E402
from takatak.ui import GOLD, GREEN, Renderer, open_display  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--camera", choices=["wide", "noir", "auto"])
    ap.add_argument("--windowed", action="store_true")
    ap.add_argument("--video", help="DEV ONLY: recorded clip instead of camera")
    args = ap.parse_args()
    cfg = load_config()
    if args.camera:
        cfg["camera"] = args.camera
    if args.windowed:
        cfg["display"]["fullscreen"] = False
    stop = Shutdown()

    pygame.init()
    screen = open_display(cfg["display"])
    text = TextRenderer(cfg["fonts"])
    audio = AudioPlayer(cfg)
    perf = PerfLog(path("logs/pose_debug_perf.log"), cfg["perf"]["log_every_s"])
    cam, inf = start_pipeline(cfg, args.video, perf)
    r = Renderer(screen, text, cfg["display"])
    min_conf = cfg["inference"]["min_kp_conf"]
    tracker = PlayerTracker(cfg["player"])
    smoother = KeypointSmoother(cfg["smoothing"], min_conf)
    levels = list(cfg["gestures"])
    level = cfg["game"]["difficulty"]
    labels = True
    seq0, persons, player = 0, [], None
    clock = pygame.time.Clock()
    u = r.u
    running = True
    try:
        while running and not stop.requested:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT or (ev.type == pygame.KEYDOWN and ev.key in (pygame.K_ESCAPE, pygame.K_q)):
                    running = False
                elif ev.type == pygame.KEYDOWN and ev.key == pygame.K_c:
                    cam.request_switch()
                    tracker.reset()
                elif ev.type == pygame.KEYDOWN and ev.key == pygame.K_t:
                    level = levels[(levels.index(level) + 1) % len(levels)]
                elif ev.type == pygame.KEYDOWN and ev.key == pygame.K_i:
                    labels = not labels
            now = time.monotonic()
            seq, res = inf.results.get()
            if seq != seq0 and res is not None:
                seq0 = seq
                persons = res.persons
                tracker.frame_size = res.frame_size
                ps = tracker.update(persons, now)
                player = ps[0] if ps else None
                if player is not None:
                    player.kp = smoother.update(player.kp, now, player.track_id)

            _, bundle = cam.slot.get()
            r.draw_feed(bundle)
            if r._map is not None:
                for p in persons:
                    pygame.draw.rect(screen, (150, 150, 150), r.bbox_to_screen(p.bbox), 2)
                    r.draw_skeleton(p.kp, min_conf, labels=False)
                if player is not None:
                    r.draw_glow(player.bbox, now)
                    r.draw_skeleton(player.kp, min_conf, labels=labels)

            lines = [f"{perf.summary()}", f"camera: {cam.active}   people: {len(persons)}   "
                     f"tolerances: {level} (T)"]
            if player is not None:
                p = cfg["gestures"][level]
                S = G.body_scale(player.kp, player.bbox, p, min_conf)
                lines.append(f"S = {S:.1f}px" if S else "S = ?")
                res_all = G.evaluate_all(player.kp, player.bbox, p, min_conf)
                y = int(160 * u)
                for name, (ok, score) in res_all.items():
                    s = text.render(f"{'YES' if ok else ' - '} {name}  {score:.2f}", 34 * u,
                                    GREEN if ok else (220, 220, 220))
                    r.panel((r.W - s.get_width() - int(50 * u), y - 4, s.get_width() + 30, s.get_height() + 8), 160)
                    screen.blit(s, (r.W - s.get_width() - int(35 * u), y))
                    y += s.get_height() + int(10 * u)
                neutral = G.is_neutral(player.kp, player.bbox, p, min_conf)
                s = text.render(f"neutral: {neutral}", 34 * u, GOLD)
                screen.blit(s, (r.W - s.get_width() - int(35 * u), y + 10))
            y = int(16 * u)
            for line in lines:
                s = text.render(line, 30 * u)
                r.panel((10, y - 4, s.get_width() + 24, s.get_height() + 8), 170)
                screen.blit(s, (22, y))
                y += s.get_height() + int(12 * u)
            msgs = status_messages(cam, inf, audio, text)
            if msgs:
                r.messages(msgs)
            pygame.display.flip()
            perf.rates["ui"].tick()
            perf.maybe_log(now, f"cam={cam.active}")
            clock.tick(cfg["display"]["fps"])
    finally:
        print("[exit] closing camera and Hailo…", flush=True)
        stop.shutdown(cam.stop, inf.stop, lambda: cam.join(timeout=2),
                      lambda: inf.join(timeout=2), pygame.quit)


if __name__ == "__main__":
    main()
