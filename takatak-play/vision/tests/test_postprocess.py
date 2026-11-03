import numpy as np
import pytest

from takatak_vision.postprocess import decode_ultralytics_pose, decode_yolov8_pose, split_outputs

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


def make_ultralytics(people, n=5040):
    """people: list of (anchor, (cx, cy, w, h), score, kxy (17,2)) → (1, 56, n) like the IR output."""
    out = np.zeros((1, 56, n), np.float32)
    for anchor, (cx, cy, w, h), score, kxy in people:
        out[0, :4, anchor] = cx, cy, w, h
        out[0, 4, anchor] = score
        k = np.concatenate([kxy, np.full((17, 1), 0.9)], axis=1)
        out[0, 5:, anchor] = k.reshape(-1)
    return out


def test_decode_ultralytics_single_person():
    out = make_ultralytics([(100, (330, 170, 80, 120), 0.9, KXY)])
    boxes, scores, kpts = decode_ultralytics_pose(out, 0.5)
    assert boxes.shape == (1, 4) and kpts.shape == (1, 17, 3)
    np.testing.assert_allclose(boxes[0], [290, 110, 370, 230])
    np.testing.assert_allclose(kpts[0, :, :2], KXY, atol=1e-4)
    np.testing.assert_allclose(kpts[0, :, 2], 0.9, atol=1e-6)
    assert scores[0] == pytest.approx(0.9)


def test_decode_ultralytics_nms_and_threshold():
    out = make_ultralytics([
        (10, (330, 170, 80, 120), 0.9, KXY),
        (11, (332, 171, 80, 120), 0.8, KXY),        # same person, other anchor → suppressed
        (500, (100, 170, 60, 100), 0.7, KXY - 200),  # second person
        (900, (500, 170, 60, 100), 0.3, KXY),        # below threshold
    ])
    boxes, scores, _ = decode_ultralytics_pose(out, 0.5, 0.7)
    np.testing.assert_allclose(scores, [0.9, 0.7])
    assert decode_ultralytics_pose(out, 0.95)[0].shape == (0, 4)
    assert len(decode_ultralytics_pose(out, 0.5, 0.7, max_det=1)[0]) == 1


def test_decode_ultralytics_rejects_other_layouts():
    with pytest.raises(ValueError):
        decode_ultralytics_pose(np.zeros((1, 84, 100)))
