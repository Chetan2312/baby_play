"""Canonical synthetic poses.

Used as unit-test fixtures and as the demo stick figure on the HINT screen.
Coordinates are camera pixels (unmirrored): the person faces the camera, so
their LEFT side appears on the image RIGHT (larger x). Shoulder width = 60 px.
"""
import numpy as np

from .gestures import KEYPOINT_NAMES

_IDX = {n: i for i, n in enumerate(KEYPOINT_NAMES)}
CONF = 0.9

_NEUTRAL_XY = {
    "nose": (320, 100), "l_eye": (330, 90), "r_eye": (310, 90),
    "l_ear": (342, 96), "r_ear": (298, 96),
    "l_shoulder": (350, 150), "r_shoulder": (290, 150),
    "l_elbow": (365, 205), "r_elbow": (275, 205),
    "l_wrist": (370, 255), "r_wrist": (270, 255),
    "l_hip": (340, 255), "r_hip": (300, 255),
    "l_knee": (342, 335), "r_knee": (298, 335),
    "l_ankle": (342, 415), "r_ankle": (298, 415),
}


def make_pose(**overrides):
    kp = np.zeros((17, 3), dtype=np.float64)
    for name, (x, y) in {**_NEUTRAL_XY, **overrides}.items():
        kp[_IDX[name]] = (x, y, CONF)
    return kp


def bbox_of(kp, pad=10):
    xs, ys = kp[:, 0], kp[:, 1]
    return np.array([xs.min() - pad, ys.min() - pad, xs.max() + pad, ys.max() + pad])


NEUTRAL = make_pose()

# check name -> pose that should satisfy it
TARGETS = {
    "touch_nose": make_pose(r_wrist=(318, 112), r_elbow=(285, 190)),
    "touch_head": make_pose(r_wrist=(318, 62), r_elbow=(282, 110)),
    "touch_ear": make_pose(r_wrist=(293, 104), r_elbow=(270, 160)),
    "hands_up": make_pose(l_wrist=(372, 25), r_wrist=(268, 25),
                          l_elbow=(368, 80), r_elbow=(272, 80)),
    "touch_tummy": make_pose(r_wrist=(316, 210), r_elbow=(280, 215)),
    "touch_shoulders": make_pose(l_wrist=(346, 148), r_wrist=(294, 148),
                                 l_elbow=(330, 200), r_elbow=(310, 200)),
    "touch_knees": make_pose(l_wrist=(345, 322), r_wrist=(295, 322),
                             l_elbow=(350, 250), r_elbow=(290, 250)),
    "clap": make_pose(l_wrist=(324, 200), r_wrist=(316, 200),
                      l_elbow=(360, 205), r_elbow=(280, 205)),
    "left_hand_up": make_pose(l_wrist=(372, 25), l_elbow=(368, 80)),
}

# Wrists the hint figure highlights per check
HIGHLIGHT = {
    "touch_nose": ["r_wrist"], "touch_head": ["r_wrist"], "touch_ear": ["r_wrist"],
    "hands_up": ["l_wrist", "r_wrist"], "touch_tummy": ["r_wrist"],
    "touch_shoulders": ["l_wrist", "r_wrist"], "touch_knees": ["l_wrist", "r_wrist"],
    "clap": ["l_wrist", "r_wrist"], "left_hand_up": ["l_wrist"],
}


def highlight_indices(check):
    return [_IDX[n] for n in HIGHLIGHT.get(check, [])]
