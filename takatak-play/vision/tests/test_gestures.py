import numpy as np
import pytest

from takatak_vision import gestures as G
from takatak_vision.config import load_config
from takatak_vision.poses import NEUTRAL, TARGETS, bbox_of

CFG = load_config()
MIN_CONF = CFG["inference"]["min_kp_conf"]
LEVELS = ["toddler", "kid"]


def run(name, kp, level):
    return G.evaluate(name, kp, bbox_of(kp), CFG["gestures"][level], MIN_CONF)


def test_every_check_has_a_fixture():
    assert set(TARGETS) == set(G.CHECKS)


@pytest.mark.parametrize("level", LEVELS)
@pytest.mark.parametrize("name", sorted(G.CHECKS))
def test_target_pose_passes(name, level):
    ok, score = run(name, TARGETS[name], level)
    assert ok, f"{name} should pass on its target pose ({level})"
    assert score == pytest.approx(1.0)


@pytest.mark.parametrize("level", LEVELS)
@pytest.mark.parametrize("name", sorted(G.CHECKS))
def test_neutral_pose_fails(name, level):
    ok, _ = run(name, NEUTRAL, level)
    assert not ok, f"{name} must not fire on a neutral pose ({level})"


@pytest.mark.parametrize("level", LEVELS)
@pytest.mark.parametrize("name", sorted(G.CHECKS))
def test_scale_and_translation_invariant(name, level):
    kp = TARGETS[name].copy()
    kp[:, :2] = kp[:, :2] * 2.3 + np.array([-150.0, 40.0])
    assert run(name, kp, level)[0]
    small = TARGETS[name].copy()
    small[:, :2] = small[:, :2] * 0.4
    assert run(name, small, level)[0]


@pytest.mark.parametrize("level", LEVELS)
def test_left_hand_up_is_not_hands_up(level):
    assert not run("hands_up", TARGETS["left_hand_up"], level)[0]
    assert not run("left_hand_up", TARGETS["hands_up"], level)[0]


@pytest.mark.parametrize("level", LEVELS)
def test_right_hand_up_is_not_left_hand_up(level):
    # Mirror confusion: the child raises their RIGHT hand.
    kp = TARGETS["left_hand_up"].copy()
    kp[G.L_WRIST, :2], kp[G.R_WRIST, :2] = NEUTRAL[G.L_WRIST, :2], (268, 25)
    assert not run("left_hand_up", kp, level)[0]


def test_occluded_nose_without_memory_fails():
    kp = TARGETS["touch_nose"].copy()
    kp[G.NOSE, 2] = 0.05
    assert not run("touch_nose", kp, "kid")[0]


def test_missing_shoulders_fall_back_to_bbox_scale():
    kp = TARGETS["touch_tummy"].copy()
    kp[[G.L_SHOULDER, G.R_SHOULDER], 2] = 0.0
    kp[[G.L_HIP, G.R_HIP], 2] = 0.0
    assert G.body_scale(kp, bbox_of(kp), CFG["gestures"]["kid"], MIN_CONF) is not None
    # no shoulders → no torso reference → tummy can't be judged, must not crash
    assert run("touch_tummy", kp, "kid") == (False, 0.0)
    assert run("touch_nose", TARGETS["touch_nose"], "kid")[0]


def test_no_scale_returns_false():
    kp = NEUTRAL.copy()
    kp[:, 2] = 0.0
    assert G.evaluate("touch_nose", kp, None, CFG["gestures"]["kid"], MIN_CONF) == (False, 0.0)


def test_sideways_child_scale_floor():
    kp = TARGETS["touch_nose"].copy()
    kp[G.L_SHOULDER, 0] = kp[G.R_SHOULDER, 0] + 2  # shoulders collapse when turned
    s = G.body_scale(kp, bbox_of(kp), CFG["gestures"]["kid"], MIN_CONF)
    assert s >= CFG["gestures"]["kid"]["scale_min_bbox_frac"] * (bbox_of(kp)[3] - bbox_of(kp)[1]) - 1e-9


@pytest.mark.parametrize("level", LEVELS)
def test_neutral_detection(level):
    p = CFG["gestures"][level]
    assert G.is_neutral(NEUTRAL, bbox_of(NEUTRAL), p, MIN_CONF)
    for name in ("hands_up", "touch_tummy", "clap", "touch_nose", "touch_shoulders"):
        kp = TARGETS[name]
        assert not G.is_neutral(kp, bbox_of(kp), p, MIN_CONF), name
    hidden = NEUTRAL.copy()
    hidden[[G.L_WRIST, G.R_WRIST], 2] = 0.0
    assert G.is_neutral(hidden, bbox_of(NEUTRAL), p, MIN_CONF)


def test_evaluate_all_keys():
    res = G.evaluate_all(NEUTRAL, bbox_of(NEUTRAL), CFG["gestures"]["kid"], MIN_CONF)
    assert set(res) == set(G.CHECKS)
