#!/usr/bin/env python3
"""M2: check Devanagari shaping on the TV and audio over HDMI.

Shows every prompt/word in all three scripts fullscreen and plays each voice
clip in turn. Also writes logs/text_check.png (text only, no camera) so you can
inspect the shaping remotely. Keys: Space next clip · Esc quit.
"""
import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import pygame  # noqa: E402
from PIL import Image  # noqa: E402

from takatak.audio import AudioPlayer  # noqa: E402
from takatak.config import load_config, load_content, path  # noqa: E402
from takatak.lifecycle import Shutdown  # noqa: E402
from takatak.text import TextRenderer  # noqa: E402
from takatak.ui import BG, LANG_COLORS, open_display  # noqa: E402

SAMPLES = [("नाकाला", "mr"), ("कान", "hi"), ("डोक्याला", "mr"), ("गुडघ्यांना", "mr"),
           ("खांद्यावर", "mr"), ("बायाँ", "hi"), ("कंधों", "hi")]


def save_check_png(text, out):
    rows = []
    for s, lang in SAMPLES:
        tmp = out + f".{len(rows)}.png"
        text.save_png(s, 72, tmp, lang)
        rows.append(Image.open(tmp).copy())
        os.remove(tmp)
    w = max(r.width for r in rows)
    img = Image.new("RGB", (w, sum(r.height for r in rows)), "white")
    y = 0
    for r in rows:
        img.paste(r, (0, y))
        y += r.height
    img.save(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--windowed", action="store_true")
    ap.add_argument("--png-only", action="store_true", help="just write logs/text_check.png")
    args = ap.parse_args()
    cfg = load_config()
    prompts, lines = load_content(cfg)
    langs = cfg["game"]["languages"]
    os.makedirs(path("logs"), exist_ok=True)
    stop = Shutdown()

    pygame.init()
    if args.png_only:
        text = TextRenderer(cfg["fonts"])
        save_check_png(text, path("logs/text_check.png"))
        print("raqm:", text.raqm, "fonts:", text.paths, "\nwrote logs/text_check.png")
        return
    if args.windowed:
        cfg["display"]["fullscreen"] = False
    screen = open_display(cfg["display"])
    text = TextRenderer(cfg["fonts"])
    save_check_png(text, path("logs/text_check.png"))
    audio = AudioPlayer(cfg)
    print("raqm:", text.raqm, "fonts:", text.paths, "audio:", audio.error or "ok")

    clips = [(p["id"], p) for p in prompts] + [(k, None) for k in lines]
    i, started = 0, False
    W, H = screen.get_size()
    u = H / 1080
    clock = pygame.time.Clock()
    while True:
        if stop.requested:
            stop.shutdown(audio.stop, pygame.quit)
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT or (ev.type == pygame.KEYDOWN and ev.key in (pygame.K_ESCAPE, pygame.K_q)):
                stop.shutdown(audio.stop, pygame.quit)
            if ev.type == pygame.KEYDOWN and ev.key == pygame.K_SPACE:
                i = (i + 1) % len(clips)
                started = False
        clip_id, prompt = clips[i]
        if not started:
            audio.say([clip_id], langs, interrupt=True)
            audio.sfx("success")
            started = True
        audio.update(time.monotonic())

        screen.fill(BG)
        y = int(40 * u)
        for s, lang in SAMPLES:
            surf = text.render(s, 64 * u, LANG_COLORS.get(lang, (255, 255, 255)), lang=lang)
            screen.blit(surf, (int(40 * u), y))
            y += surf.get_height() + int(8 * u)
        y = int(60 * u)
        for lang in langs:
            t = prompt["text"][lang] if prompt else lines[clip_id]["text"][lang]
            surf = text.render(t, 80 * u, LANG_COLORS.get(lang, (255, 255, 255)), lang=lang)
            screen.blit(surf, (W - surf.get_width() - int(40 * u), y))
            y += surf.get_height() + int(20 * u)
            if prompt:
                surf = text.render(prompt["word"][lang], 110 * u, (255, 205, 40), lang=lang)
                screen.blit(surf, (W - surf.get_width() - int(40 * u), y))
                y += surf.get_height() + int(30 * u)
        info = f"[{i + 1}/{len(clips)}] {clip_id}   raqm={'OK' if text.raqm else 'MISSING'}   Space=next  Esc=quit"
        surf = text.render(info, 32 * u)
        screen.blit(surf, (int(40 * u), H - surf.get_height() - int(30 * u)))
        pygame.display.flip()
        clock.tick(30)


if __name__ == "__main__":
    main()
