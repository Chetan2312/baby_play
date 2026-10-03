#!/usr/bin/env python3
"""Takatak Play — Demo 1: Simon Says body parts (trilingual).

Keys: Space skip · S skeleton · L language mode · C switch camera · D debug · Esc quit
"""
import argparse
import os
import sys
import time

import pygame

from takatak.audio import AudioPlayer
from takatak.camera import CameraThread, VideoThread
from takatak.config import load_config, load_content, path
from takatak.game import Game
from takatak.perf import PerfLog
from takatak.player import KeypointSmoother, PlayerTracker
from takatak.pose import InferenceThread
from takatak.stats import StatsLogger
from takatak.text import TextRenderer
from takatak.ui import GameView, Renderer, open_display


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--camera", choices=["wide", "noir", "auto"])
    ap.add_argument("--difficulty", choices=["toddler", "kid"])
    ap.add_argument("--rounds", type=int)
    ap.add_argument("--language-mode", choices=["all", "single", "rotate"])
    ap.add_argument("--windowed", action="store_true")
    ap.add_argument("--video", help="DEV ONLY: use a recorded clip instead of the camera")
    return ap.parse_args(argv)


def build(args):
    cfg = load_config(args.config)
    if args.camera:
        cfg["camera"] = args.camera
    if args.difficulty:
        cfg["game"]["difficulty"] = args.difficulty
    if args.rounds:
        cfg["game"]["rounds"] = args.rounds
    if args.language_mode:
        cfg["game"]["language_mode"] = args.language_mode
    if args.windowed:
        cfg["display"]["fullscreen"] = False
    if cfg["privacy"]["save_frames"]:
        print("WARNING: privacy.save_frames is true. The game never saves frames; set it back to false.")
    return cfg


def start_pipeline(cfg, video, perf):
    cam = VideoThread(cfg, video, perf.rates["cam"]) if video else CameraThread(cfg, perf.rates["cam"])
    cam.start()
    inf = InferenceThread(cfg, cam.slot, perf)
    inf.start()
    return cam, inf


def status_messages(cam, inf, audio, text):
    msgs = []
    for src in (cam, inf):
        if src.error:
            msgs.append(src.error)
        elif src.status:
            msgs.append(src.status)
    for m in (audio.error, text.warning):
        if m:
            msgs.append(m)
    return msgs


def main(argv=None):
    args = parse_args(argv)
    cfg = build(args)
    prompts, lines = load_content(cfg)
    os.makedirs(path("logs"), exist_ok=True)

    pygame.mixer.pre_init(cfg["audio"]["frequency"], -16, 2, cfg["audio"]["buffer"])
    pygame.init()
    screen = open_display(cfg["display"])
    text = TextRenderer(cfg["fonts"])
    audio = AudioPlayer(cfg)
    perf = PerfLog(path(cfg["paths"]["perf_log"]), cfg["perf"]["log_every_s"])
    stats = StatsLogger(path(cfg["paths"]["stats_dir"]))

    cam, inf = start_pipeline(cfg, args.video, perf)
    min_conf = cfg["inference"]["min_kp_conf"]
    tracker = PlayerTracker(cfg["player"])
    smoother = KeypointSmoother(cfg["smoothing"], min_conf)
    game = Game(cfg, prompts, lines, stats, camera_name=cfg["camera"])
    renderer = Renderer(screen, text, cfg["display"])
    view = GameView(renderer, lines)

    show_skeleton = cfg["display"]["show_skeleton"]
    show_debug = cfg["display"]["show_debug"]
    clock = pygame.time.Clock()
    res_seq = 0
    player = None
    last = time.monotonic()
    running = True
    try:
        while running:
            for ev in pygame.event.get():
                if ev.type == pygame.QUIT:
                    running = False
                elif ev.type == pygame.KEYDOWN:
                    k = ev.key
                    if k in (pygame.K_ESCAPE, pygame.K_q):
                        running = False
                    elif k == pygame.K_SPACE:
                        audio.handle(game.skip(time.monotonic()))
                    elif k == pygame.K_s:
                        show_skeleton = not show_skeleton
                    elif k == pygame.K_d:
                        show_debug = not show_debug
                    elif k == pygame.K_l:
                        print(f"[game] language mode: {game.cycle_language_mode()}")
                    elif k == pygame.K_c:
                        cam.request_switch()
                        tracker.reset()
                        smoother.reset()
                        player = None

            now = time.monotonic()
            dt, last = now - last, now

            seq, res = inf.results.get()
            fresh = seq != res_seq and res is not None
            if fresh:
                res_seq = seq
                tracker.frame_size = res.frame_size
                players = tracker.update(res.persons, now)
                player = players[0] if players else None
                if player is not None:
                    player.kp = smoother.update(player.kp, now, player.track_id)
            game.camera_name = cam.active or cfg["camera"]

            audio.handle(game.update(now, player, fresh, audio.busy))
            audio.update(now)

            _, bundle = cam.slot.get()
            renderer.draw_feed(bundle)
            if show_skeleton and player is not None:
                renderer.draw_skeleton(player.kp, min_conf)
            view.render(game, player, now, dt)
            msgs = status_messages(cam, inf, audio, text)
            if msgs:
                renderer.messages(msgs)
            if show_debug:
                renderer.corner_text(f"{perf.summary()}  |  {cam.active}  {game.state.value}  "
                                     f"{game.difficulty}  {game.language_mode}  "
                                     f"hold {game.hold}/{game.g['hold_frames']}")
            pygame.display.flip()
            perf.rates["ui"].tick()
            perf.maybe_log(now, f"cam={cam.active} state={game.state.value}")
            clock.tick(cfg["display"]["fps"])
    finally:
        game._end_session()
        cam.stop()
        inf.stop()
        audio.stop()
        cam.join(timeout=2)
        inf.join(timeout=2)
        pygame.quit()
    return 0


if __name__ == "__main__":
    sys.exit(main())
