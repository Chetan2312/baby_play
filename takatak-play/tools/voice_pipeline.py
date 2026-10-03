#!/usr/bin/env python3
"""Studio recordings / TTS drafts → game-ready voice files + lipsync + manifest.

Sources (studio wins over draft):
  content/voice/raw/<line_id>_v<variant>_<lang>.wav        (studio, 48 kHz/24-bit mono)
  content/voice/drafts/<lang>/<line_id>_v<variant>.wav      (tts_drafts.py)
Steps per file (ffmpeg):
  trim leading/trailing silence (keep 80 ms) → high-pass 80 Hz →
  loudness −18 LUFS, true peak ≤ −1 dBTP → OGG Vorbis q5
  → content/voice/processed/<lang>/<line_id>_v<variant>.ogg
Rhubarb Lip Sync (if `rhubarb` is on PATH; --recognizer phonetic for mr/hi)
  → content/voice/lipsync/<lang>/<line_id>_v<variant>.json
Manifest → content/voice/voice_manifest.json (durations, draft flag), then
run tools/content_build.py so Godot sees the new files.
Incremental: a file is redone only when its source is newer.
"""
import argparse
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from content_common import LANGS, MANIFEST, VOICE, read_lines, voice_key, write_json  # noqa: E402

FILTERS = ("silenceremove=start_periods=1:start_silence=0.08:start_threshold=-45dB,"
           "areverse,silenceremove=start_periods=1:start_silence=0.08:start_threshold=-45dB,areverse,"
           "highpass=f=80,loudnorm=I=-18:TP=-1:LRA=11")


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
                          "-of", "default=nw=1:nk=1", path], capture_output=True, text=True, check=True)
    return round(float(out.stdout.strip()), 3)


def source_for(lid, v, lang):
    studio = os.path.join(VOICE, "raw", f"{lid}_v{v}_{lang}.wav")
    if os.path.exists(studio):
        return studio, False
    draft = os.path.join(VOICE, "drafts", lang, f"{lid}_v{v}.wav")
    if os.path.exists(draft):
        return draft, True
    return None, None


def process(src, ogg, lipsync, lang, rhubarb):
    os.makedirs(os.path.dirname(ogg), exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        clean = os.path.join(tmp, "clean.wav")
        run(["ffmpeg", "-y", "-i", src, "-af", FILTERS, "-ar", "48000", "-ac", "1", clean])
        run(["ffmpeg", "-y", "-i", clean, "-c:a", "libvorbis", "-q:a", "5", ogg])
        if rhubarb:
            os.makedirs(os.path.dirname(lipsync), exist_ok=True)
            rec = "phonetic" if lang in ("mr", "hi") else "pocketSphinx"
            try:
                run([rhubarb, "-f", "json", "--recognizer", rec, "-o", lipsync, clean])
            except subprocess.CalledProcessError as e:
                print(f"  rhubarb failed for {ogg}: {e.stderr.decode()[:200]}")
                return False
    return True


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    if shutil.which("ffmpeg") is None:
        sys.exit("ffmpeg not found (sudo apt install ffmpeg)")
    rhubarb = shutil.which("rhubarb")
    if not rhubarb:
        print("note: rhubarb not on PATH → no lipsync files (mascot falls back to amplitude mouth)")
    manifest, done, kept, missing = {}, 0, 0, 0
    for lid, e in read_lines().items():
        for v in e["variants"]:
            for lang in LANGS:
                src, draft = source_for(lid, v, lang)
                if src is None:
                    missing += 1
                    continue
                rel = f"voice/processed/{lang}/{lid}_v{v}.ogg"
                ogg = os.path.join(VOICE, "processed", lang, f"{lid}_v{v}.ogg")
                lip_rel = f"voice/lipsync/{lang}/{lid}_v{v}.json"
                lip = os.path.join(VOICE, "lipsync", lang, f"{lid}_v{v}.json")
                fresh = os.path.exists(ogg) and os.path.getmtime(ogg) >= os.path.getmtime(src)
                if args.force or not fresh:
                    process(src, ogg, lip, lang, rhubarb)
                    done += 1
                else:
                    kept += 1
                manifest[voice_key(lid, v, lang)] = {
                    "path": rel, "duration": duration(ogg), "draft": draft,
                    "source": os.path.relpath(src, VOICE),
                    "lipsync": lip_rel if os.path.exists(lip) else None,
                }
    write_json(MANIFEST, manifest)
    print(f"voice pipeline: {done} processed, {kept} up to date, {missing} without a source → {MANIFEST}")


if __name__ == "__main__":
    main()
