"""Config loading. Relative paths in config.yaml resolve against vision/.

load_config() also applies the hardware profile (hardware.profile → profiles.<name>):
  - cfg["model"] becomes <models_dir>/<model>, so a Hailo-8 HEF is never loaded on a
    Hailo-10H (or the other way round). A HEF in the old flat models/ folder is still
    used for the devrig profile, with a note, until fetch_model.sh moves it.
  - camera: default → the profile's default_camera.
  - cfg["profile"] holds {name, accelerator, models_dir, cameras, default_camera, camera_backend}.
  - profiles.<name>.overrides (optional) is merged over the rest of the config, so a
    profile can change e.g. hands.workers or thermal.throttle_c without touching the others.

The profile comes from (first wins): the profile argument (--profile), the
TAKATAK_PROFILE environment variable, then hardware.profile in config.yaml.
"""
import os

import yaml

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))   # vision/
PROJECT_ROOT = os.path.dirname(ROOT)                                    # takatak-play/

PROFILES = ("devrig", "kit", "n150")
DEFAULT_PROFILES = {
    "devrig": {"accelerator": "hailo8", "models_dir": "models/hailo8", "camera_backend": "picamera2",
               "cameras": ["wide", "noir"], "default_camera": "wide"},
    "kit": {"accelerator": "hailo10h", "models_dir": "models/hailo10h", "camera_backend": "picamera2",
            "cameras": ["imx500"], "default_camera": "imx500"},
    "n150": {"accelerator": "openvino", "device": "GPU", "models_dir": "models/openvino",
             "camera_backend": "v4l2", "cameras": ["usb"], "default_camera": "usb"},
}


class ConfigError(ValueError):
    pass


def path(p):
    return p if os.path.isabs(p) else os.path.join(ROOT, p)


def load_yaml(p):
    with open(path(p), encoding="utf-8") as f:
        return yaml.safe_load(f)


def merge(base, over):
    """Recursive dict merge: over wins; nested dicts are merged, everything else replaced."""
    for k, v in over.items():
        if isinstance(v, dict) and isinstance(base.get(k), dict):
            merge(base[k], v)
        else:
            base[k] = v
    return base


def apply_profile(cfg, profile=None):
    """Resolve hardware.profile into cfg["profile"], cfg["model"] and cfg["camera"]."""
    name = (profile or os.environ.get("TAKATAK_PROFILE")
            or (cfg.get("hardware") or {}).get("profile", "devrig"))
    if name not in PROFILES:
        raise ConfigError(f"hardware.profile must be one of {PROFILES}, got {name!r}")
    prof = dict(DEFAULT_PROFILES[name])
    prof.update((cfg.get("profiles") or {}).get(name) or {})
    prof["name"] = name
    cfg.setdefault("hardware", {})["profile"] = name
    merge(cfg, prof.pop("overrides", None) or {})
    cfg["profile"] = prof
    model_file = os.path.basename(prof.get("model") or cfg.get("model_file") or cfg["model"])
    cfg["model_file"] = model_file
    model = os.path.join(prof["models_dir"], model_file)
    legacy = os.path.join("models", model_file)
    if (not os.path.exists(path(model)) and prof["accelerator"] == "hailo8"
            and os.path.exists(path(legacy))):
        prof["model_note"] = f"using legacy {legacy}; run tools/fetch_model.sh to move it to {model}"
        model = legacy
    cfg["model"] = model
    if cfg.get("camera", "default") == "default":
        cfg["camera"] = prof["default_camera"]
    return cfg


def load_config(p="config.yaml", profile=None):
    return apply_profile(load_yaml(p), profile)
