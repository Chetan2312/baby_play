import numpy as np

from takatak_vision.config import load_config
from takatak_vision.gestures import NOSE
from takatak_vision.poses import NEUTRAL, bbox_of
from takatak_vision.tracker import KeypointSmoother, Person, Tracker

CFG = load_config()


def person(dx=0.0, scale=1.0):
    kp = NEUTRAL.copy()
    kp[:, :2] = kp[:, :2] * scale + [dx, 0]
    return Person(bbox_of(kp), 0.9, kp)


def tracker(mode="single"):
    return Tracker({**CFG["tracker"], "mode": mode}, (640, 360), mirror=True)


def active(tracks):
    return [t for t in tracks if t.active]


def test_largest_selected_then_sticky():
    tr = tracker()
    small, big = person(-200, 0.6), person(150, 1.0)
    (a,) = active(tr.update([small, big], 0.0))
    assert a.bbox[0] == big.bbox[0]
    huge = person(-250, 1.4)  # bigger kid walks past: active stays
    (b,) = active(tr.update([big, huge], 0.1))
    assert b.id == a.id


def test_all_people_get_stable_ids():
    tr = tracker()
    ids1 = {t.id for t in tr.update([person(-200), person(150)], 0.0)}
    ids2 = {t.id for t in tr.update([person(-195), person(155)], 0.05)}
    assert ids1 == ids2 and len(ids1) == 2


def test_short_dropout_keeps_identity_long_one_does_not():
    tr = tracker()
    pid = active(tr.update([person()], 0.0))[0].id
    assert tr.update([], 0.3) == []
    assert active(tr.update([person(5)], 0.5))[0].id == pid
    tr.update([], 0.6)
    later = 0.6 + CFG["tracker"]["lost_grace_s"] + 0.5
    assert active(tr.update([person(5)], later))[0].id != pid


def test_duo_picks_one_per_half_in_display_space():
    tr = tracker("duo")
    # camera x < 320 → display right half (mirrored)
    cam_left, cam_right = person(-150), person(150)
    act = active(tr.update([cam_left, cam_right], 0.0))
    assert len(act) == 2
    by_slot = {t.slot: t for t in act}
    assert by_slot[0].bbox[0] == cam_right.bbox[0]   # display-left = camera-right
    assert by_slot[1].bbox[0] == cam_left.bbox[0]


def test_mode_switch_resets_active():
    tr = tracker("duo")
    tr.update([person(-150), person(150)], 0.0)
    tr.set_mode("single")
    assert len(active(tr.update([person(-150), person(150)], 0.05))) == 1


def test_smoother_ema_and_face_memory():
    sm = KeypointSmoother(CFG["smoothing"], CFG["inference"]["min_kp_conf"])
    a = NEUTRAL.copy()
    sm.update(a, 0.0)
    b = a.copy()
    b[:, 0] += 10
    out = sm.update(b, 0.03)
    np.testing.assert_allclose(out[:, 0], a[:, 0] + 10 * CFG["smoothing"]["ema_alpha"])
    hidden = b.copy()
    hidden[NOSE, 2] = 0.05
    assert sm.update(hidden, 0.2)[NOSE, 2] >= CFG["inference"]["min_kp_conf"]
    late = 0.2 + CFG["smoothing"]["face_memory_s"] + 0.1
    assert sm.update(hidden, late)[NOSE, 2] < CFG["inference"]["min_kp_conf"]
