#!/usr/bin/env python3
"""Fail the build on broken content.

Errors (exit 1):
  - a line_id/variant missing one of mr/hi/en, empty text, unknown category
  - a game references an unknown line, or a prompt check the vision service doesn't know
  - manifest points at a missing voice file
  - draft voice files present with --release
Warnings:
  - no voice file yet for a line (errors with --strict-audio)
  - fewer praise/encourage variants than the brief asks for
"""
import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "vision"))

from content_common import (CATEGORIES, CONTENT, LANGS, read_games, read_lines,  # noqa: E402
                            read_manifest, voice_key)

MIN_POOL = {"praise": 25, "encourage": 15}


def lint(strict_audio=False, release=False):
    errors, warnings = [], []
    lines = read_lines()
    for lid, e in lines.items():
        if e["category"] not in CATEGORIES:
            errors.append(f"{lid}: unknown category {e['category']!r}")
        for v, data in e["variants"].items():
            for lang in LANGS:
                t = data["text"].get(lang)
                if not t:
                    errors.append(f"{lid} v{v}: missing {lang}")
                elif "{" in t or "}" in t:
                    errors.append(f"{lid} v{v} {lang}: placeholders are not speakable: {t!r}")
    for cat, n in MIN_POOL.items():
        have = sum(len(e["variants"]) for e in lines.values() if e["category"] == cat)
        if have < n:
            warnings.append(f"category {cat}: {have} variants, brief asks for ≥ {n} per language")

    try:
        from takatak_vision.gestures import CHECKS
    except ImportError:
        CHECKS = None
    for gid, g in read_games().items():
        refs = [g.get("intro_line")] + [p.get(k) for p in g.get("prompts", []) for k in ("line", "word")]
        for r in refs:
            if r and r not in lines:
                errors.append(f"game {gid}: unknown line {r!r}")
        prefix = g.get("hint_prefix")
        if prefix and not any(lid.startswith(prefix) for lid in lines):
            errors.append(f"game {gid}: no lines with hint_prefix {prefix!r}")
        ids = {p["id"] for p in g.get("prompts", [])}
        for level, pool in (g.get("levels") or {}).items():
            for pid in pool:
                if pid not in ids:
                    errors.append(f"game {gid}: level {level} lists unknown prompt {pid!r}")
        if CHECKS is not None:
            for p in g.get("prompts", []):
                if p.get("check") and p["check"] not in CHECKS:
                    errors.append(f"game {gid}: prompt {p['id']} has unknown check {p['check']!r}")

    manifest = read_manifest()
    missing_audio = 0
    for lid, e in lines.items():
        for v in e["variants"]:
            for lang in LANGS:
                m = manifest.get(voice_key(lid, v, lang))
                if m is None:
                    missing_audio += 1
                    continue
                if not os.path.exists(os.path.join(CONTENT, m["path"])):
                    errors.append(f"{lid} v{v} {lang}: manifest file missing {m['path']}")
                if release and m.get("draft"):
                    errors.append(f"{lid} v{v} {lang}: draft voice in a release build")
    if missing_audio:
        msg = f"{missing_audio} line/language combinations have no voice file yet (run ./run.sh content)"
        (errors if strict_audio else warnings).append(msg)
    return errors, warnings


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--strict-audio", action="store_true")
    ap.add_argument("--release", action="store_true", help="also fail on draft voices")
    args = ap.parse_args()
    errors, warnings = lint(args.strict_audio, args.release)
    for w in warnings:
        print("warning:", w)
    for e in errors:
        print("ERROR:", e)
    print(f"content lint: {len(errors)} errors, {len(warnings)} warnings")
    sys.exit(1 if errors else 0)


if __name__ == "__main__":
    main()
