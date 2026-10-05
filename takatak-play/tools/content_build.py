#!/usr/bin/env python3
"""Convert content (lines.csv, games/*.yaml, sessions/*.yaml, curriculum/weeks.yaml,
centre_profile.yaml, ui/strings.yaml, voice manifest) into JSON for Godot.

Writes content/build/{lines,index,session,curriculum,centre_profile,ui}.json,
content/build/games/<game>.json and content/build/sessions/<session>.json.
Godot reads these at runtime from the content folder (no YAML parsing in GDScript).
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import yaml  # noqa: E402

from content_common import (BUILD, CONTENT, LANGS, content_version, read_centre_profile,  # noqa: E402
                            read_games, read_lines, read_manifest, read_sessions, read_ui_strings,
                            read_weeks, voice_key, write_json)


def build():
    lines = read_lines()
    manifest = read_manifest()
    out_lines, categories = {}, {}
    for lid, e in lines.items():
        variants = []
        for v, data in sorted(e["variants"].items()):
            audio, duration, draft, lipsync = {}, {}, {}, {}
            for lang in LANGS:
                m = manifest.get(voice_key(lid, v, lang))
                if m:
                    audio[lang] = m["path"]
                    duration[lang] = m["duration"]
                    draft[lang] = m.get("draft", False)
                    if m.get("lipsync"):
                        lipsync[lang] = m["lipsync"]
            variants.append({"variant": v, "text": data["text"], "direction": data["direction"],
                             "audio": audio, "duration": duration, "draft": draft, "lipsync": lipsync})
        out_lines[lid] = {"category": e["category"], "uses_name": e["uses_name"], "variants": variants}
        categories.setdefault(e["category"], []).append(lid)
    write_json(os.path.join(BUILD, "lines.json"),
               {"langs": list(LANGS), "lines": out_lines, "categories": categories})
    games = read_games()
    for gid, g in games.items():
        write_json(os.path.join(BUILD, "games", f"{gid}.json"), g)
    sessions = read_sessions()
    for sid, sess in sessions.items():
        write_json(os.path.join(BUILD, "sessions", f"{sid}.json"), sess)
    write_json(os.path.join(BUILD, "curriculum.json"), {"weeks": read_weeks()})
    write_json(os.path.join(BUILD, "centre_profile.json"), read_centre_profile())
    write_json(os.path.join(BUILD, "ui.json"), read_ui_strings())
    write_json(os.path.join(BUILD, "index.json"), {"games": sorted(games), "sessions": sorted(sessions),
                                                   "content_version": content_version()})
    session_yaml = os.path.join(CONTENT, "session.yaml")
    if os.path.exists(session_yaml):
        with open(session_yaml, encoding="utf-8") as f:
            write_json(os.path.join(BUILD, "session.json"), yaml.safe_load(f))
    n_audio = sum(len(v["audio"]) for e in out_lines.values() for v in e["variants"])
    print(f"content build: {len(out_lines)} lines, {n_audio} voice files, {len(games)} games, "
          f"{len(sessions)} sessions → {BUILD}")


if __name__ == "__main__":
    build()
