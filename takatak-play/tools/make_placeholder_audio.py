#!/usr/bin/env python3
"""Generate placeholder voice clips (espeak-ng) and sound effects.

Writes assets/audio_placeholder/<lang>/<id>.wav for every prompt + line, and
assets/audio_placeholder/sfx/{success,try_again,start}.wav (soft synth tones).
Replace with real recorded voice in assets/audio/<lang>/ before kid testing:
toddlers respond far better to a warm human voice.
"""
import argparse
import math
import os
import shutil
import struct
import subprocess
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from takatak.config import load_config, load_content, path  # noqa: E402

VOICES = {"en": "en", "hi": "hi", "mr": "mr"}
RATE = 44100


def speak(text, lang, out, speed):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(["espeak-ng", "-v", VOICES.get(lang, lang), "-s", str(speed), "-w", out, text],
                   check=True)


def tone_file(out, notes, volume=0.35):
    """notes: [(freq_hz, seconds)] — soft bell-ish tones with fade, no harsh edges."""
    os.makedirs(os.path.dirname(out), exist_ok=True)
    frames = bytearray()
    for freq, dur in notes:
        n = int(RATE * dur)
        for i in range(n):
            t = i / RATE
            env = min(1.0, t / 0.01) * math.exp(-3.5 * t / dur)
            v = env * (math.sin(2 * math.pi * freq * t) + 0.3 * math.sin(4 * math.pi * freq * t))
            frames += struct.pack("<h", int(max(-1, min(1, v * volume)) * 32767))
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(bytes(frames))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--speed", type=int, default=135, help="espeak words per minute")
    ap.add_argument("--force", action="store_true", help="overwrite existing clips")
    args = ap.parse_args()
    cfg = load_config()
    prompts, lines = load_content(cfg)
    out_root = path(cfg["paths"]["audio_placeholder"])
    langs = cfg["game"]["languages"]

    items = [(p["id"], p["text"]) for p in prompts]
    for key, line in lines.items():
        say = line.get("say") or line["text"]
        items.append((key, {lg: t.replace("{n}", "").strip() for lg, t in say.items()}))

    if shutil.which("espeak-ng") is None:
        print("espeak-ng not found: sudo apt install espeak-ng")
    else:
        for clip_id, texts in items:
            for lang in langs:
                out = os.path.join(out_root, lang, f"{clip_id}.wav")
                if os.path.exists(out) and not args.force:
                    continue
                speak(texts[lang], lang, out, args.speed)
                print("voice", out)

    sfx = {
        "success": [(523.25, 0.12), (659.25, 0.12), (783.99, 0.12), (1046.5, 0.45)],
        "try_again": [(587.33, 0.22), (523.25, 0.35)],   # gentle, never a "buzzer"
        "start": [(659.25, 0.12), (987.77, 0.35)],
    }
    for name, notes in sfx.items():
        out = os.path.join(out_root, "sfx", f"{name}.wav")
        if not os.path.exists(out) or args.force:
            tone_file(out, notes)
            print("sfx  ", out)
    print("done.")


if __name__ == "__main__":
    main()
