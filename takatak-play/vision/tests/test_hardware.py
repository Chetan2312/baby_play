import os
import subprocess
import sys

import pytest

from takatak_vision import build, camera, hardware
from takatak_vision import config as C


def test_profiles_pick_their_own_model_folder():
    dev = C.load_config(profile="devrig")
    kit = C.load_config(profile="kit")
    assert dev["profile"]["accelerator"] == "hailo8" and kit["profile"]["accelerator"] == "hailo10h"
    assert kit["model"] == os.path.join("models/hailo10h", "yolov8s_pose.hef")
    assert dev["model"] in (os.path.join("models/hailo8", "yolov8s_pose.hef"),
                            os.path.join("models", "yolov8s_pose.hef"))   # legacy fallback
    assert dev["camera"] == "wide" and kit["camera"] == "imx500"


def test_legacy_flat_model_is_used_only_for_hailo8(tmp_path, monkeypatch):
    (tmp_path / "models").mkdir()
    (tmp_path / "models" / "yolov8s_pose.hef").write_bytes(b"hef")
    monkeypatch.setattr(C, "ROOT", str(tmp_path))
    cfg = C.apply_profile({"hardware": {"profile": "devrig"}, "model": "yolov8s_pose.hef", "camera": "default"})
    assert cfg["model"] == os.path.join("models", "yolov8s_pose.hef") and "model_note" in cfg["profile"]
    cfg = C.apply_profile({"hardware": {"profile": "kit"}, "model": "yolov8s_pose.hef", "camera": "default"})
    assert cfg["model"] == os.path.join("models/hailo10h", "yolov8s_pose.hef")


def test_explicit_camera_wins_and_bad_profile_fails():
    cfg = C.apply_profile({"hardware": {"profile": "kit"}, "model": "m.hef", "camera": "wide"})
    assert cfg["camera"] == "wide"
    with pytest.raises(C.ConfigError):
        C.apply_profile({"hardware": {"profile": "laptop"}, "model": "m.hef"})


@pytest.mark.parametrize("text,arch", [
    ("Device Architecture: HAILO8\n", "hailo8"),
    ("Device Architecture: HAILO8L\n", "hailo8l"),
    ("Device Architecture: HAILO10H\n", "hailo10h"),
    ("garbage", None),
])
def test_parse_identify(text, arch):
    assert hardware.parse_identify(text) == arch


def test_parse_asound_cards():
    text = (" 0 [vc4hdmi0       ]: vc4-hdmi - vc4-hdmi-0\n"
            "                      vc4-hdmi-0\n"
            " 2 [Lite           ]: USB-Audio - ReSpeaker Lite\n")
    assert hardware.parse_asound_cards(text) == ["vc4-hdmi-0", "ReSpeaker Lite"]


def test_network_state(tmp_path):
    for iface, state in (("lo", "unknown"), ("eth0", "down"), ("wlan0", "down")):
        (tmp_path / iface).mkdir()
        (tmp_path / iface / "operstate").write_text(state + "\n")
    assert hardware.network_state(str(tmp_path)) == "offline"
    (tmp_path / "wlan0" / "operstate").write_text("up\n")
    assert hardware.network_state(str(tmp_path)) == "online"


def test_profile_errors_are_friendly():
    kit = C.load_config(profile="kit")["profile"]
    assert hardware.profile_errors(kit, "hailo10h", True, ["imx500"]) == []
    errs = hardware.profile_errors(kit, "hailo8", True, ["imx708_wide"])
    assert len(errs) == 2 and "hardware.profile" in errs[0]
    assert "not found" in hardware.profile_errors(kit, None, False, [])[0]


@pytest.mark.parametrize("models,which,expected", [
    (["imx708_wide", "imx708_wide_noir"], "noir", (1, "noir")),
    (["imx708_wide", "imx708_wide_noir"], "wide", (0, "wide")),
    (["imx708_wide_noir"], "wide", (0, "noir")),        # only one camera: use it
    (["imx500"], "imx500", (0, "imx500")),
    (["imx500"], "wide", (0, "imx500")),
])
def test_find_camera_num(monkeypatch, models, which, expected):
    monkeypatch.setattr(camera, "list_cameras", lambda: [{"Num": i, "Model": m} for i, m in enumerate(models)])
    assert camera.find_camera_num(which, C.load_config()) == expected


def test_no_camera_is_a_friendly_error(monkeypatch):
    monkeypatch.setattr(camera, "list_cameras", lambda: [])
    with pytest.raises(camera.CameraError, match="No camera"):
        camera.find_camera_num("wide", C.load_config())


def test_build_defaults_to_field(monkeypatch):
    monkeypatch.delenv("TAKATAK_BUILD", raising=False)
    assert build.is_field()
    monkeypatch.setenv("TAKATAK_BUILD", "dev")
    assert build.current() == "dev"
    monkeypatch.setenv("TAKATAK_BUILD", "whatever")
    assert build.is_field()


def test_recording_tools_refuse_in_field_build():
    tools = os.path.join(os.path.dirname(C.ROOT), "vision", "tools")
    env = {k: v for k, v in os.environ.items() if k != "TAKATAK_BUILD"}
    for tool in ("record_session.py", "record_clip.py"):
        r = subprocess.run([sys.executable, os.path.join(tools, tool), "--i-have-consent"],
                           capture_output=True, text=True, env=env, timeout=30)
        assert r.returncode != 0 and "disabled in field builds" in r.stderr, tool
