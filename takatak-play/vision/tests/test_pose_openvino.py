import os

import numpy as np
import pytest

from takatak_vision import pose
from takatak_vision.config import load_config, path

ov = pytest.importorskip("openvino")


@pytest.fixture
def cfg():
    c = load_config(profile="n150")
    if not os.path.exists(pose.openvino_model_xml(c["model"])):
        pytest.skip(f"no IR at {path(c['model'])}")
    c["profile"]["device"] = "CPU"      # CI / any PC; the GPU path is the same API
    c["inference"]["cache_dir"] = None
    return c


def test_factory_picks_the_engine_by_accelerator(cfg):
    engine = pose.PoseEngine(cfg)
    assert isinstance(engine, pose.OpenVinoPoseEngine) and engine.input_hw == (384, 640)
    assert engine.infer(np.zeros((360, 640, 3), np.uint8)) == []   # empty frame: nobody


def test_letterbox_maps_back_to_lores_pixels(cfg):
    engine = pose.PoseEngine(cfg)
    s, ox, oy = engine._letterbox(np.zeros((360, 640, 3), np.uint8))
    assert (s, ox, oy) == (1.0, 0, 12)
    out = np.zeros((1, 56, 10), np.float32)
    out[0, :5, 0] = 320, 192, 100, 200, 0.9          # box centred in the model input
    out[0, 5::3, 0], out[0, 6::3, 0], out[0, 7::3, 0] = 320, 112, 0.9
    engine.request = type("R", (), {"infer": lambda self, x: {0: out}})()
    (p,) = engine.infer(np.zeros((360, 640, 3), np.uint8))
    np.testing.assert_allclose(p.bbox, [270, 80, 370, 280])
    np.testing.assert_allclose(p.kp[:, 1], 100)


def test_missing_model_is_a_friendly_error(cfg):
    cfg["model"] = "models/openvino/nope"
    with pytest.raises(pose.PoseError, match="Model not found"):
        pose.PoseEngine(cfg)
