#!/usr/bin/env python3
"""Package a field build: everything an anganwadi kit runs, nothing that records.

  python tools/make_field_build.py --out dist/takatak-field [--with-godot]

Left out entirely (not just switched off):
  vision/tools/   record_session, record_clip, debug_view, mock_server, fetch_model (curl)
  tools/          TTS drafts, voice pipeline, content build/lint, this script
  install.sh      provisioning (apt, downloads): run it from a dev checkout first
  game/tests, logs, tests, studio recordings (content/voice/raw), child-name clips
Pinned to field: vision/takatak_vision/_build.py (BUILD = "field") and game/BUILD_FIELD,
which no environment variable can override.

Run ./run.sh content (or tools/content_build.py) before packaging: the package carries
content/build and the processed voice files, not the content sources.
"""
import argparse
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

INCLUDE = [
    "run.sh",
    "README.md",
    "vision/takatak_vision",
    "vision/config.yaml",
    "vision/requirements.txt",
    "vision/pyproject.toml",
    "vision/models",
    "game",
    "content/build",
    "content/voice/processed",
    "content/voice/lipsync",
    "docs/data_policy.md",
    "docs/protocol.md",
]
EXCLUDE_DIRS = {"__pycache__", ".pytest_cache", ".godot", "tests"}
EXCLUDE_FILES = {"_build.py"}


def _ignore(_dir, names):
    return [n for n in names if n in EXCLUDE_DIRS or n in EXCLUDE_FILES or n.endswith((".pyc", ".part"))]


def make(out, with_godot=False, root=ROOT):
    if not os.path.exists(os.path.join(root, "content", "build", "index.json")):
        raise SystemExit("content/build missing: run tools/content_build.py first")
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)
    for rel in INCLUDE:
        src = os.path.join(root, rel)
        if not os.path.exists(src):
            continue
        dst = os.path.join(out, rel)
        if os.path.isdir(src):
            shutil.copytree(src, dst, ignore=_ignore)
        else:
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            shutil.copy2(src, dst)
    with open(os.path.join(out, "vision", "takatak_vision", "_build.py"), "w", encoding="utf-8") as f:
        f.write('"""Written by tools/make_field_build.py: this package is a field build."""\nBUILD = "field"\n')
    with open(os.path.join(out, "game", "BUILD_FIELD"), "w", encoding="utf-8") as f:
        f.write("field build: no recording, no tester keys, no child names, localhost only\n")
    os.makedirs(os.path.join(out, "logs"), exist_ok=True)
    if with_godot:
        godot = os.path.realpath(os.path.join(root, ".godot-bin", "godot"))
        if not os.path.exists(godot):
            raise SystemExit("no .godot-bin/godot: ./install.sh --with-godot first")
        os.makedirs(os.path.join(out, ".godot-bin"))
        shutil.copy2(godot, os.path.join(out, ".godot-bin", "godot"))
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", default=os.path.join(ROOT, "dist", "takatak-field"))
    ap.add_argument("--with-godot", action="store_true", help="copy .godot-bin/godot into the package")
    args = ap.parse_args()
    out = make(os.path.abspath(args.out), args.with_godot)
    print(f"field build → {out}")
    print("Run it with: ./run.sh play   (system python3 with python3-websockets/python3-yaml, or a .env venv)")


if __name__ == "__main__":
    sys.exit(main())
