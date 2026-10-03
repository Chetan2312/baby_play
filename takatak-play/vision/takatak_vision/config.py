"""Config loading. Relative paths in config.yaml resolve against vision/."""
import os

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # vision/
PROJECT_ROOT = os.path.dirname(ROOT)                                    # takatak-play/


def path(p):
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


def load_yaml(p):
    with open(path(p), encoding="utf-8") as f:
        return yaml.safe_load(f)


def load_config(p="config.yaml"):
    return load_yaml(p)
