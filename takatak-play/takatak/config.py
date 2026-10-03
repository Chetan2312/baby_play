"""Config + content loading. Paths in config are relative to the project root."""
import os

import yaml

from .gestures import CHECKS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def path(p):
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


def load_yaml(p):
    with open(path(p), encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_config(p="config.yaml"):
    return load_yaml(p)


def load_content(cfg):
    prompts = load_yaml(cfg["content"]["prompts"])
    lines = load_yaml(cfg["content"]["lines"])
    langs = cfg["game"]["languages"]
    for pr in prompts:
        if pr["check"] not in CHECKS:
            raise ValueError(f"prompt {pr['id']}: unknown check {pr['check']!r}")
        for lang in langs:
            if lang not in pr["text"] or lang not in pr["word"]:
                raise ValueError(f"prompt {pr['id']}: missing language {lang!r}")
    return prompts, lines
