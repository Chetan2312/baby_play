"""Shared helpers for the content tools (lines.csv, games/*.yaml, voice files)."""
import csv
import glob
import json
import os

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # takatak-play/
CONTENT = os.path.join(ROOT, "content")
LINES_CSV = os.path.join(CONTENT, "script", "lines.csv")
GAMES_DIR = os.path.join(CONTENT, "games")
BUILD = os.path.join(CONTENT, "build")
VOICE = os.path.join(CONTENT, "voice")
MANIFEST = os.path.join(VOICE, "voice_manifest.json")
LANGS = ("mr", "hi", "en")
CATEGORIES = ("greeting", "prompt", "praise", "encourage", "hint", "callback", "transition",
              "story", "finish", "goodbye", "word")


def read_lines():
    """→ {line_id: {"category", "uses_name", "variants": {variant: {"text": {lang}, "direction"}}}}"""
    lines = {}
    with open(LINES_CSV, encoding="utf-8", newline="") as f:
        for n, row in enumerate(csv.DictReader(f), start=2):
            lid = row["line_id"].strip()
            if not lid:
                continue
            entry = lines.setdefault(lid, {"category": row["category"].strip(),
                                           "uses_name": row["uses_name"].strip().lower() == "true",
                                           "variants": {}, "rows": []})
            entry["rows"].append(n)
            v = entry["variants"].setdefault(int(row["variant"]), {"text": {}, "direction": row["direction"]})
            v["text"][row["lang"].strip()] = row["text"].strip()
    return lines


def read_games():
    games = {}
    for p in sorted(glob.glob(os.path.join(GAMES_DIR, "*.yaml"))):
        with open(p, encoding="utf-8") as f:
            g = yaml.safe_load(f)
        games[g["game"]] = g
    return games


def voice_key(line_id, variant, lang):
    return f"{lang}/{line_id}_v{variant}"


def read_manifest():
    if not os.path.exists(MANIFEST):
        return {}
    with open(MANIFEST, encoding="utf-8") as f:
        return json.load(f)


def write_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)
