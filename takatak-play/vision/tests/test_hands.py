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


def test_mock_child_steps_sideways():
    from takatak_vision.mock import MockPerformer
    m = MockPerformer()
    x0 = m.kp(0.0)[:, 0].mean()
    assert m.command("left") and m.kp(0.0)[:, 0].mean() > x0 + 100      # camera +x = screen left (mirrored)
    assert m.command("right") and m.kp(0.0)[:, 0].mean() < x0 - 100
    assert m.command("middle") and abs(m.kp(0.0)[:, 0].mean() - x0) < 10


def test_warp_and_back_land_on_the_same_frame_point():
    pytest.importorskip("cv2")
    frame = np.zeros((1080, 1920, 4), np.uint8)
    frame[300:304, 1000:1004, :3] = 255                                 # a dot near the hand
    for wrist, elbow in (((1000, 400), (1000, 600)), ((1000, 400), (850, 520))):   # upright, tilted arm
        rect = H.pose_rect(wrist, elbow)
        crop = H.warp_rect(frame, rect, 224)
        assert crop.shape == (224, 224, 3)
        ys, xs = np.nonzero(crop[..., 0] > 128)
        back = H.rect_to_frame(np.array([[xs.mean() / 224, ys.mean() / 224, 0.0]]), rect, 1920, 1080)
        assert back[0, 0] * 1920 == pytest.approx(1002, abs=3) and back[0, 1] * 1080 == pytest.approx(302, abs=3)


def test_pose_rect_points_up_the_forearm():
    cx, cy, side, ux, uy = H.pose_rect((500, 400), (500, 600))
    assert (ux, uy) == pytest.approx((0, -1)) and cy < 400 and side == pytest.approx(200 * H.HAND_PER_FOREARM * 2.4)
    rect = H.pose_rect((10, 10), (10, 10))                               # zero forearm: no crash
    assert rect[2] == 64


@pytest.mark.parametrize("angle", [0.0, 0.7, -1.2, math.pi])
def test_landmark_rect_follows_the_hand(angle):
    lm = synthetic_hand(angle=angle) * 100 + [960, 540]                  # hand ~190 px tall
    cx, cy, side, ux, uy = H.landmark_rect(lm)
    up = np.array([math.sin(angle), -math.cos(angle)])                   # synthetic fingers point up, turned
    assert np.dot([ux, uy], up) > 0.95
    assert np.all(np.hypot(lm[:, 0] - cx, lm[:, 1] - cy) < side * 0.75)  # whole hand inside the box


class StubLiteRT:
    """Stands in for LiteRTHands: a pointing hand, upright in every box it is given."""
    input_size = 224

    def __init__(self):
        self.calls = []

    def run(self, jobs, t_ms):
        out = {}
        for key, crop in jobs:
            self.calls.append((key, crop.shape))
            lm = synthetic_hand(("index",))
            lm = (lm - lm.min(0)) / (lm.max(0) - lm.min(0)) * 0.5 + 0.25   # hand fills the middle half
            ext = H.fingers_extended(lm)
            out[key] = {"lm_crop": np.c_[lm, np.zeros(21)], "fingers": ext, "count": sum(ext),
                        "gesture": H.gesture(ext), "score": 0.9}
        return out

    def forget(self, keys):
        pass

    def close(self):
        pass


def test_hand_thread_tracks_from_its_own_landmarks_and_stamps_capture_time():
    pytest.importorskip("cv2")
    from takatak_vision.config import load_config
    from takatak_vision.slots import LatestSlot
    th = H.HandThread(load_config(), LatestSlot(), LatestSlot(), mirror=True)
    th._backend = StubLiteRT()
    frame = np.zeros((1080, 1920, 4), np.uint8)
    p = person(0.3, 0.7)
    msg = th.process(frame, [p], 1, 1000.0)
    assert msg["ts"] == 1000 and len(msg["hands"]) == 1
    first = th._rects[(5, "l")]
    assert th._backend.calls[-1][1] == (224, 224, 3)
    th.process(frame, [p], 2, 1033.0)
    assert th._rects[(5, "l")] != H.pose_rect((0.6 * 1920, 0.3 * 1080), (0.6 * 1920, 0.5 * 1080))
    assert first is not None
    p_far = person(0.3, 0.7, x_l=0.9)                                    # pose wrist jumped away: re-find
    th.process(frame, [p_far], 3, 1066.0)
    cx = th._rects[(5, "l")][0]
    assert abs(cx - 0.1 * 1920) < abs(cx - 0.6 * 1920)
    th.process(frame, [person(0.7, 0.7)], 4, 1100.0)                     # arm down: box forgotten
    assert (5, "l") not in th._rects


@pytest.mark.skipif(not os.path.exists(vision_path(H.MODEL)), reason="hand model not downloaded")
def test_litert_backend_runs_the_landmark_model():
    pytest.importorskip("cv2")
    try:
        be = H.LiteRTHands(workers=2, threads=1)
    except H.HandsError as e:
        pytest.skip(str(e))
    try:
        assert be.input_size == 224
        blank = np.zeros((224, 224, 3), np.uint8)
        assert be.run([((1, "l"), blank)], 0) == {(1, "l"): None}                       # no hand
        assert be.run([((1, "l"), blank), ((1, "r"), blank)], 0) == {(1, "l"): None, (1, "r"): None}
        be.min_conf = 0.0                                                                 # force a result
        res = be.track_crop(blank)
        assert res["lm_crop"].shape == (21, 3) and res["gesture"] in ("point", "open", "fist", "other")
    finally:
        be.close()


def test_litert_reports_a_missing_model(tmp_path):
    with pytest.raises(H.HandsError, match="hand model missing"):
        H.LiteRTHands(model=str(tmp_path / "nope.task"))


@pytest.mark.skipif(not os.path.exists(vision_path(H.MODEL)), reason="hand model not downloaded")
def test_lite_model_is_found_in_the_mediapipe_package(tmp_path, monkeypatch):
    import zipfile
    pkg = tmp_path / "mediapipe" / "modules" / "hand_landmark"
    pkg.mkdir(parents=True)
    (tmp_path / "mediapipe" / "__init__.py").write_text("")
    # stand-in with the same inputs/outputs: the full landmark model from the .task
    (pkg / H.LITE_TFLITE).write_bytes(zipfile.ZipFile(vision_path(H.MODEL)).read(H.LANDMARK_TFLITE))
    monkeypatch.syspath_prepend(str(tmp_path))
    monkeypatch.delitem(__import__("sys").modules, "mediapipe", raising=False)
    if os.path.exists(vision_path(os.path.join("models", H.LITE_TFLITE))):
        pytest.skip("a local lite model takes precedence")
    assert H.lite_model_path() == str(pkg / H.LITE_TFLITE)
    try:
        be = H.LiteRTHands(landmarks="lite")
    except H.HandsError as e:
        pytest.skip(str(e))
    assert be.run([((1, "l"), np.zeros((224, 224, 3), np.uint8))], 0) == {(1, "l"): None}
    be.close()


def test_lite_model_missing_is_a_friendly_error(monkeypatch):
    import importlib.util
    monkeypatch.setattr(importlib.util, "find_spec", lambda name: None)
    monkeypatch.setattr(H, "vision_path", lambda p: "/nonexistent/" + p)
    with pytest.raises(H.HandsError, match="hand_landmark_lite.tflite not found"):
        H.lite_model_path()
