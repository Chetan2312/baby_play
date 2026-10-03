import numpy as np
import pytest

from takatak_vision.postprocess import decode_yolov8_pose, split_outputs

IN = (640, 640)
BINS = 16


def make_raw(cells, sigmoid_on_chip=False, batch=False):
    """cells: list of (stride, gy, gx, score_logit, (l,t,r,b) in strides, kpts (17,2) px)."""
    raw = {}
    for n, s in enumerate((8, 16, 32)):
        g = IN[0] // s
        box = np.zeros((g, g, 4 * BINS), np.float32)
        cls = np.full((g, g, 1), -10.0, np.float32)
        kpt = np.zeros((g, g, 51), np.float32)
        kpt[..., 2::3] = -5.0
        for stride, gy, gx, logit, ltrb, kxy in cells:
            if stride != s:
                continue
            cls[gy, gx, 0] = logit
            for side, bin_ in enumerate(ltrb):
                box[gy, gx, side * BINS + bin_] = 30.0  # one-hot after softmax
            k = kpt[gy, gx].reshape(17, 3)
            k[:, 0] = (kxy[:, 0] / s - gx) / 2
            k[:, 1] = (kxy[:, 1] / s - gy) / 2
            k[:, 2] = 4.0
        if sigmoid_on_chip:
            cls = 1 / (1 + np.exp(-cls))
            kpt[..., 2::3] = 1 / (1 + np.exp(-kpt[..., 2::3]))
        arrs = [box, cls, kpt]
        if batch:
            arrs = [a[None] for a in arrs]
        raw.update({f"yolov8s_pose/conv{n}{i}": a for i, a in enumerate(arrs)})
    return raw


KXY = np.stack([np.linspace(300, 360, 17), np.linspace(130, 210, 17)], axis=1)


@pytest.mark.parametrize("sigmoid_on_chip", [False, True])
@pytest.mark.parametrize("batch", [False, True])
def test_decode_single_person(sigmoid_on_chip, batch):
    raw = make_raw([(16, 10, 20, 5.0, (3, 3, 3, 3), KXY)], sigmoid_on_chip, batch)
    boxes, scores, kpts = decode_yolov8_pose(raw, IN, score_thr=0.5)
    assert boxes.shape == (1, 4)
    np.testing.assert_allclose(boxes[0], [280, 120, 376, 216], atol=0.5)
    assert scores[0] == pytest.approx(1 / (1 + np.exp(-5)), abs=1e-4)
    np.testing.assert_allclose(kpts[0, :, :2], KXY, atol=1e-3)
    assert np.all(kpts[0, :, 2] > 0.95)


def test_nms_suppresses_overlap_and_keeps_separate():
    other = KXY + [200, 0]
    raw = make_raw([
        (16, 10, 20, 5.0, (3, 3, 3, 3), KXY),
        (16, 10, 21, 4.0, (3, 3, 3, 3), KXY),       # same person, lower score
        (32, 5, 15, 3.0, (2, 2, 2, 2), other),       # different person
    ])
    boxes, scores, _ = decode_yolov8_pose(raw, IN, score_thr=0.5, iou_thr=0.7)
    assert len(boxes) == 2
    assert scores[0] > scores[1]


def test_threshold_filters_everything():
    raw = make_raw([(8, 1, 1, -1.0, (1, 1, 1, 1), KXY)])
    boxes, _, kpts = decode_yolov8_pose(raw, IN, score_thr=0.5)
    assert boxes.shape == (0, 4) and kpts.shape == (0, 17, 3)


def test_split_outputs_rejects_unknown():
    with pytest.raises(ValueError):
        split_outputs({"a": np.zeros((80, 80, 7))}, IN)
    with pytest.raises(ValueError):
        split_outputs({"a": np.zeros((80, 80, 1))}, IN)
