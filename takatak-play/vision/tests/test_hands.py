import math
import os

import numpy as np
import pytest

from takatak_vision import hands as H
from takatak_vision.config import path as vision_path

FINGER_X = {"index": -0.3, "middle": -0.05, "ring": 0.2, "pinky": 0.45}


def synthetic_hand(up=("thumb", "index", "middle", "ring", "pinky"), angle=0.0):
    """21 landmarks, wrist at the origin, fingers pointing up (−y); angle rotates the hand."""
    p = np.zeros((21, 2))
    p[1:5] = [(-0.4, -0.3), (-0.7, -0.6), (-0.9, -0.85), (-1.1, -1.1) if "thumb" in up else (-0.1, -0.85)]
    for i, name in enumerate(("index", "middle", "ring", "pinky")):
        x, base = FINGER_X[name], 5 + 4 * i
        p[base] = (x, -1.0)
        p[base + 1] = (x, -1.4)
        if name in up:
            p[base + 2], p[base + 3] = (x, -1.65), (x, -1.9)
        else:                                  # curled back towards the palm
            p[base + 2], p[base + 3] = (x, -1.25), (x, -1.05)
    c, s = math.cos(angle), math.sin(angle)
    return p @ np.array([[c, -s], [s, c]]).T


@pytest.mark.parametrize("up,count,gest", [
    (("thumb", "index", "middle", "ring", "pinky"), 5, "open"),
    ((), 0, "fist"),
    (("index",), 1, "point"),
    (("thumb", "index"), 2, "point"),          # thumb doesn't spoil a point
    (("index", "middle"), 2, "other"),
])
@pytest.mark.parametrize("angle", [0.0, math.pi / 2, 2.5])
def test_fingers_and_gesture(up, count, gest, angle):
    ext = H.fingers_extended(synthetic_hand(up, angle))
    assert sum(ext) == count, ext
    assert H.gesture(ext) == gest


def test_hand_roi_follows_the_forearm_and_stays_in_frame():
    x0, y0, x1, y1 = H.hand_roi((0.5, 0.4), (0.5, 0.5), 1920, 1080)
    side = x1 - x0
    assert side == y1 - y0
    forearm = 0.1 * 1080
    assert side == pytest.approx(forearm * H.HAND_PER_FOREARM * 2.4, abs=2)
    assert (y0 + y1) / 2 < 0.4 * 1080                       # centre beyond the wrist (up the arm)
    x0, y0, x1, y1 = H.hand_roi((0.99, 0.01), (0.9, 0.1), 1920, 1080)
    assert x0 >= 0 and y0 >= 0 and x1 <= 1920 and y1 <= 1080
    assert H.hand_roi((0.5, 0.5), (0.5, 0.5), 1920, 1080)[2] - H.hand_roi((0.5, 0.5), (0.5, 0.5), 1920, 1080)[0] == 64


def test_mirror_x():
    lm = np.array([[0.2, 0.3, 0.0]])
    assert H.mirror_x(lm)[0, 0] == pytest.approx(0.8)


def test_missing_model_is_a_friendly_error(tmp_path):
    with pytest.raises(H.HandsError, match="hand model missing"):
        H.HandTracker(model=str(tmp_path / "nope.task"))


@pytest.mark.skipif(not os.path.exists(vision_path(H.MODEL)), reason="hand model not downloaded")
def test_tracker_runs_on_an_empty_frame():
    pytest.importorskip("mediapipe")
    tr = H.HandTracker()
    frame = np.zeros((1080, 1920, 4), np.uint8)
    assert tr.track((1, "l"), frame, (900, 400, 1100, 600), 1) is None
    assert tr.track((1, "l"), frame, (900, 400, 1100, 600), 1) is None   # same timestamp is fine
    tr.close()
