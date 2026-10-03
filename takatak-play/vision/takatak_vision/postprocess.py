"""YOLOv8-pose decoding for the raw Hailo outputs (pure numpy, unit-tested).

Same maths as picamera2 examples/hailo/pose_utils.py (DFL box decode,
keypoints = (2*raw + grid) * stride), but output tensors are matched by SHAPE
instead of hard-coded layer names, so any yolov8*_pose HEF build works:
for each stride there is a box tensor (4*bins ch), a class tensor (1 ch) and
a keypoint tensor (17*3 ch). Only anchors above the score threshold are decoded.
"""
import numpy as np

NUM_KPTS = 17


def _sigmoid(x):
    return 1.0 / (1.0 + np.exp(-x))


def _needs_sigmoid(x):
    # Hailo HEFs sometimes apply the sigmoid on-chip; logits fall outside [0, 1].
    return x.size > 0 and (float(x.min()) < 0.0 or float(x.max()) > 1.0)


def split_outputs(raw, input_hw, num_kpts=NUM_KPTS):
    """Group raw outputs per stride → list of (stride, box, cls, kpt), each (H, W, C)."""
    arrays = list(raw.values()) if isinstance(raw, dict) else list(raw)
    groups = {}
    for a in arrays:
        a = np.asarray(a)
        while a.ndim > 3:
            a = a[0]
        if a.ndim != 3:
            raise ValueError(f"unexpected output shape {a.shape}")
        h, w, c = a.shape
        if c == num_kpts * 3:
            kind = "kpt"
        elif c == 1:
            kind = "cls"
        elif c % 4 == 0 and c >= 16:
            kind = "box"
        else:
            raise ValueError(f"unexpected output channels {a.shape}")
        groups.setdefault((h, w), {})[kind] = a
    out = []
    for (h, w), g in groups.items():
        if set(g) != {"box", "cls", "kpt"}:
            shapes = {k: v.shape for k, v in g.items()}
            raise ValueError(f"incomplete output group at {h}x{w}: {shapes}")
        out.append((input_hw[0] / h, g["box"], g["cls"], g["kpt"]))
    if not out:
        raise ValueError("no outputs")
    return sorted(out, key=lambda t: t[0])


def nms(boxes, scores, iou_thr):
    order = np.argsort(-scores)
    keep = []
    areas = (boxes[:, 2] - boxes[:, 0]) * (boxes[:, 3] - boxes[:, 1])
    while order.size:
        i = order[0]
        keep.append(i)
        rest = order[1:]
        xx1 = np.maximum(boxes[i, 0], boxes[rest, 0])
        yy1 = np.maximum(boxes[i, 1], boxes[rest, 1])
        xx2 = np.minimum(boxes[i, 2], boxes[rest, 2])
        yy2 = np.minimum(boxes[i, 3], boxes[rest, 3])
        inter = np.clip(xx2 - xx1, 0, None) * np.clip(yy2 - yy1, 0, None)
        iou = inter / (areas[i] + areas[rest] - inter + 1e-9)
        order = rest[iou <= iou_thr]
    return np.array(keep, dtype=int)


def decode_yolov8_pose(raw, input_hw, score_thr=0.5, iou_thr=0.7, max_det=10,
                       num_kpts=NUM_KPTS):
    """→ (boxes (N,4) xyxy, scores (N,), kpts (N,17,3)) in model-input pixels."""
    all_b, all_s, all_k = [], [], []
    for stride, box, cls, kpt in split_outputs(raw, input_hw, num_kpts):
        w = cls.shape[1]
        scores = cls.reshape(-1).astype(np.float32)
        if _needs_sigmoid(scores):
            scores = _sigmoid(scores)
        idx = np.nonzero(scores > score_thr)[0]
        if idx.size == 0:
            continue
        gy, gx = np.divmod(idx, w)
        gx = gx.astype(np.float32)
        gy = gy.astype(np.float32)

        bins = box.shape[2] // 4
        d = box.reshape(-1, 4, bins)[idx].astype(np.float32)
        d = np.exp(d - d.max(axis=-1, keepdims=True))
        d /= d.sum(axis=-1, keepdims=True)
        dist = (d * np.arange(bins, dtype=np.float32)).sum(-1) * stride  # l, t, r, b
        cx, cy = (gx + 0.5) * stride, (gy + 0.5) * stride
        all_b.append(np.stack([cx - dist[:, 0], cy - dist[:, 1],
                               cx + dist[:, 2], cy + dist[:, 3]], axis=1))
        all_s.append(scores[idx])

        k = kpt.reshape(-1, num_kpts, 3)[idx].astype(np.float32)
        kc = kpt[..., 2::3]
        out = np.empty_like(k)
        out[..., 0] = (k[..., 0] * 2.0 + gx[:, None]) * stride
        out[..., 1] = (k[..., 1] * 2.0 + gy[:, None]) * stride
        out[..., 2] = _sigmoid(k[..., 2]) if _needs_sigmoid(kc) else k[..., 2]
        all_k.append(out)

    if not all_b:
        return np.zeros((0, 4)), np.zeros((0,)), np.zeros((0, num_kpts, 3))
    boxes, scores, kpts = np.concatenate(all_b), np.concatenate(all_s), np.concatenate(all_k)
    keep = nms(boxes, scores, iou_thr)[:max_det]
    return boxes[keep], scores[keep], kpts[keep]
