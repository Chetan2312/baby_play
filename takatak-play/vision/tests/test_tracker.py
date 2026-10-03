import numpy as np

from takatak.config import load_config
from takatak.gestures import NOSE
from takatak.player import KeypointSmoother, Person, PlayerTracker
from takatak.poses import NEUTRAL, bbox_of

CFG = load_config()


def person(dx=0.0, scale=1.0):
    kp = NEUTRAL.copy()
    kp[:, :2] = kp[:, :2] * scale + [dx, 0]
    return Person(bbox_of(kp), 0.9, kp)


def test_largest_selected_then_sticky():
    tr = PlayerTracker(CFG["player"])
    small, big = person(-200, 0.6), person(150, 1.0)
    (p,) = tr.update([small, big], 0.0)
    first_id = p.track_id
    assert p.bbox[0] == big.bbox[0]
    # an even bigger kid walks past far away: active player stays
    huge = person(-250, 1.4)
    (p,) = tr.update([big, huge], 0.1)
    assert p.track_id == first_id and p.bbox[0] == big.bbox[0]


def test_short_dropout_keeps_identity():
    tr = PlayerTracker(CFG["player"])
    a = person()
    pid = tr.update([a], 0.0)[0].track_id
    assert tr.update([], 0.3) == []
    assert tr.update([person(5)], 0.5)[0].track_id == pid
    tr.update([], 0.6)
    assert tr.update([person(5)], 0.6 + CFG["player"]["lost_grace_s"] + 0.5)[0].track_id != pid


def test_smoother_ema_and_face_memory():
    sm = KeypointSmoother(CFG["smoothing"], CFG["inference"]["min_kp_conf"])
    a = NEUTRAL.copy()
    sm.update(a, 0.0, 1)
    b = a.copy()
    b[:, 0] += 10
    out = sm.update(b, 0.03, 1)
    np.testing.assert_allclose(out[:, 0], a[:, 0] + 10 * CFG["smoothing"]["ema_alpha"])
    hidden = b.copy()
    hidden[NOSE, 2] = 0.05
    out = sm.update(hidden, 0.2, 1)
    assert out[NOSE, 2] >= CFG["inference"]["min_kp_conf"]
    out = sm.update(hidden, 0.2 + CFG["smoothing"]["face_memory_s"] + 0.1, 1)
    assert out[NOSE, 2] < CFG["inference"]["min_kp_conf"]


def test_smoother_resets_on_new_track():
    sm = KeypointSmoother(CFG["smoothing"], CFG["inference"]["min_kp_conf"])
    sm.update(NEUTRAL, 0.0, 1)
    b = NEUTRAL.copy()
    b[:, 0] += 100
    np.testing.assert_allclose(sm.update(b, 0.03, 2), b)
