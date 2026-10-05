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


class StubTracker:
    """Stands in for MediaPipe: 'finds' a hand in every box (pointing unless told otherwise)."""

    def __init__(self, up=("index",), up_by_side=None):
        self.calls = []
        self.up = up
        self.up_by_side = up_by_side or {}

    def track_crop(self, key, crop, t_ms):
        self.calls.append((key, crop.shape))
        lm = synthetic_hand(self.up_by_side.get(key[1], self.up))
        lm = (lm - lm.min(0)) / (lm.max(0) - lm.min(0))
        ext = H.fingers_extended(lm)
        return {"lm_crop": np.c_[lm, np.zeros(21)], "fingers": ext, "count": sum(ext),
                "gesture": H.gesture(ext), "score": 1.0}

    def forget(self, keys):
        pass

    def close(self):
        pass


def person(lw_y, rw_y, x_l=0.4, x_r=0.6):
    return {"id": 5, "active": True, "kp": {"l_wrist": [x_l, lw_y, 0.9], "l_elbow": [x_l, 0.5, 0.9],
                                            "r_wrist": [x_r, rw_y, 0.9], "r_elbow": [x_r, 0.5, 0.9]}}


def test_hand_thread_tracks_raised_hands_and_mirrors():
    from takatak_vision.config import load_config
    from takatak_vision.slots import LatestSlot
    cfg = load_config()
    stub = StubTracker()
    th = H.HandThread(cfg, LatestSlot(), LatestSlot(), mirror=True, tracker=stub)
    frame = np.zeros((1080, 1920, 4), np.uint8)
    msg = th.process(frame, [person(0.3, 0.7)], 1, 1000.0)            # left raised, right hanging
    assert msg["t"] == "hands" and len(msg["hands"]) == 1
    h = msg["hands"][0]
    assert h["side"] == "l" and h["gesture"] == "point" and h["player"] == 5
    (key, shape), = stub.calls
    assert key == (5, "l") and shape[0] == shape[1] and shape[2] == 3
    # display x of the left wrist is 0.4: cut at camera x 0.6 (mirrored), and the landmarks
    # come back in display space, near the display wrist
    assert abs(h["kp"][0][0] - 0.4) < 0.08
    assert th.process(frame, [person(0.7, 0.7)], 2, 1033.0)["hands"] == []   # arms down


def test_mock_hands_right_points_left_open():
    from takatak_vision.mock import synthetic_hands
    hs = synthetic_hands([person(0.3, 0.3)])
    by_side = {h["side"]: h for h in hs}
    assert by_side["r"]["gesture"] == "point" and by_side["l"]["gesture"] == "open"
    assert by_side["r"]["tip"][1] < 0.3                                  # tip beyond the wrist (up)
    assert synthetic_hands([person(0.7, 0.7)]) == []


def test_encoder_downscale():
    from takatak_vision.encoder import downscale
    img = np.zeros((1080, 1920, 4), np.uint8)
    assert downscale(img, (960, 540)).shape == (540, 960, 4)
    assert downscale(img, (1920, 1080)) is img


def test_focus_on_the_pointing_hand():
    from takatak_vision.config import load_config
    from takatak_vision.slots import LatestSlot
    cfg = load_config()
    cfg["hands"]["other_every"] = 3
    stub = StubTracker(up_by_side={"l": ("index",), "r": ("thumb", "index", "middle", "ring", "pinky")})
    th = H.HandThread(cfg, LatestSlot(), LatestSlot(), mirror=True, tracker=stub)
    frame = np.zeros((1080, 1920, 4), np.uint8)
    both_up = [person(0.3, 0.3)]
    th.process(frame, both_up, 1, 0.0)                 # first frame: both tracked; left points, right open
    stub.calls.clear()
    for n in range(2, 8):
        msg = th.process(frame, both_up, n, n * 33.0)
        assert len(msg["hands"]) == 2                  # the other hand is still reported
    tracked = [k for k, _ in stub.calls]
    assert tracked.count((5, "l")) == 6                # pointing hand: every frame
    assert 1 <= tracked.count((5, "r")) <= 3           # other hand: every 3rd frame


def test_worker_reports_a_missing_model(tmp_path):
    with pytest.raises(H.HandsError, match="hand model missing"):
        H.HandWorker(model=str(tmp_path / "nope.task"), start_timeout_s=30)


@pytest.mark.skipif(not os.path.exists(vision_path(H.MODEL)), reason="hand model not downloaded")
def test_worker_process_runs_the_model():
    pytest.importorskip("mediapipe")
    w = H.HandWorker()
    try:
        out = w.run([((1, "l"), np.zeros((200, 200, 3), np.uint8))], 1)
        assert out == {(1, "l"): None}
        w.forget([])
    finally:
        w.close()
    assert not w.proc.is_alive()
