"""Gesture checks. Pure functions: keypoints in, (bool, score) out.

Keypoints are a (17, 3) array of x, y, conf in image pixels (y grows down),
COCO order. L/R are the person's OWN left/right. Display mirroring never
touches these labels.

Every distance is divided by the body scale S (shoulder width), so all
thresholds in config.yaml are unitless multiples of S.
"""
import numpy as np

(NOSE, L_EYE, R_EYE, L_EAR, R_EAR, L_SHOULDER, R_SHOULDER, L_ELBOW, R_ELBOW,
 L_WRIST, R_WRIST, L_HIP, R_HIP, L_KNEE, R_KNEE, L_ANKLE, R_ANKLE) = range(17)

KEYPOINT_NAMES = [
    "nose", "l_eye", "r_eye", "l_ear", "r_ear", "l_shoulder", "r_shoulder",
    "l_elbow", "r_elbow", "l_wrist", "r_wrist", "l_hip", "r_hip",
    "l_knee", "r_knee", "l_ankle", "r_ankle",
]
FACE = (NOSE, L_EYE, R_EYE, L_EAR, R_EAR)
LEFT_SIDE = {L_EYE, L_EAR, L_SHOULDER, L_ELBOW, L_WRIST, L_HIP, L_KNEE, L_ANKLE}

SKELETON = [
    (L_SHOULDER, R_SHOULDER), (L_SHOULDER, L_ELBOW), (L_ELBOW, L_WRIST),
    (R_SHOULDER, R_ELBOW), (R_ELBOW, R_WRIST), (L_SHOULDER, L_HIP),
    (R_SHOULDER, R_HIP), (L_HIP, R_HIP), (L_HIP, L_KNEE), (L_KNEE, L_ANKLE),
    (R_HIP, R_KNEE), (R_KNEE, R_ANKLE), (L_EYE, R_EYE), (NOSE, L_EYE),
    (NOSE, R_EYE), (L_EYE, L_EAR), (R_EYE, R_EAR),
]


def body_scale(kp, bbox, p, min_conf):
    """Shoulder width, floored by a fraction of bbox height (kids turn sideways)."""
    s = None
    ls, rs = kp[L_SHOULDER], kp[R_SHOULDER]
    if ls[2] >= min_conf and rs[2] >= min_conf:
        s = float(np.hypot(ls[0] - rs[0], ls[1] - rs[1]))
    if bbox is not None:
        bbox_h = float(bbox[3] - bbox[1])
        if s is None:
            s = p["scale_bbox_frac"] * bbox_h
        else:
            s = max(s, p["scale_min_bbox_frac"] * bbox_h)
    return s if s and s > 1e-6 else None


class Body:
    """Geometry helpers over one person. Points below min_conf count as missing."""

    def __init__(self, kp, bbox, params, min_conf):
        self.kp = np.asarray(kp, dtype=np.float64)
        self.p = params
        self.min_conf = min_conf
        self.S = body_scale(self.kp, bbox, params, min_conf)

    def pt(self, i):
        return self.kp[i, :2] if self.kp[i, 2] >= self.min_conf else None

    def mid(self, i, j):
        a, b = self.pt(i), self.pt(j)
        if a is not None and b is not None:
            return (a + b) / 2
        return a if a is not None else b

    def shoulder_mid(self):
        return self.mid(L_SHOULDER, R_SHOULDER)

    def hip_mid(self):
        h = self.mid(L_HIP, R_HIP)
        if h is None:
            s = self.shoulder_mid()
            if s is not None:
                h = s + np.array([0.0, self.p["torso_ratio"] * self.S])
        return h

    def nose_y(self):
        n = self.pt(NOSE)
        if n is not None:
            return n[1]
        s = self.shoulder_mid()
        return None if s is None else s[1] - self.p["nose_above_shoulders"] * self.S

    def wrists(self):
        return [w for w in (self.pt(L_WRIST), self.pt(R_WRIST)) if w is not None]

    def d(self, a, b):
        return float(np.hypot(*(a - b))) / self.S


def _near(d, tol):
    return d < tol, float(np.clip(2.0 - d / tol, 0.0, 1.0))


_NO = (False, 0.0)


def touch_nose(b, p):
    nose, ws = b.pt(NOSE), b.wrists()
    if nose is None or not ws:
        return _NO
    return _near(min(b.d(w, nose) for w in ws), p["nose_dist"])


def touch_ear(b, p):
    ears = [e for e in (b.pt(L_EAR), b.pt(R_EAR)) if e is not None]
    ws = b.wrists()
    if not ears or not ws:
        return _NO
    return _near(min(b.d(w, e) for w in ws for e in ears), p["ear_dist"])


def touch_head(b, p):
    nose, ws = b.pt(NOSE), b.wrists()
    eyes = b.mid(L_EYE, R_EYE)
    ref = eyes if eyes is not None else nose
    if ref is None or not ws:
        return _NO
    cx = nose[0] if nose is not None else ref[0]
    best = _NO
    for w in ws:
        above = (ref[1] - w[1]) / b.S
        dx = abs(w[0] - cx) / b.S
        ok = p["head_above_eyes"] <= above <= p["head_max_above_eyes"] and dx < p["head_x"]
        score = float(np.clip(above / p["head_above_eyes"], 0, 1)) * float(dx < p["head_x"])
        if ok or score > best[1]:
            best = (ok, score)
        if ok:
            break
    return best


def hands_up(b, p):
    lw, rw, ny = b.pt(L_WRIST), b.pt(R_WRIST), b.nose_y()
    if lw is None or rw is None or ny is None:
        return _NO
    margin = min(ny - lw[1], ny - rw[1]) / b.S
    thr = p["hands_up_above_nose"]
    return margin > thr, float(np.clip(margin / thr, 0, 1))


def touch_tummy(b, p):
    sm, hm, ws = b.shoulder_mid(), b.hip_mid(), b.wrists()
    if sm is None or hm is None or not ws:
        return _NO
    target = sm + p["tummy_frac"] * (hm - sm)
    return _near(min(b.d(w, target) for w in ws), p["tummy_dist"])


def touch_shoulders(b, p):
    lw, rw = b.pt(L_WRIST), b.pt(R_WRIST)
    sh = [s for s in (b.pt(L_SHOULDER), b.pt(R_SHOULDER)) if s is not None]
    if lw is None or rw is None or not sh:
        return _NO
    d = max(min(b.d(lw, s) for s in sh), min(b.d(rw, s) for s in sh))
    return _near(d, p["shoulder_dist"])


def touch_knees(b, p):
    lw, rw = b.pt(L_WRIST), b.pt(R_WRIST)
    knees = [k for k in (b.pt(L_KNEE), b.pt(R_KNEE)) if k is not None]
    if lw is None or rw is None or not knees:
        return _NO
    d = max(min(b.d(lw, k) for k in knees), min(b.d(rw, k) for k in knees))
    return _near(d, p["knee_dist"])


def clap(b, p):
    lw, rw, sm, hm = b.pt(L_WRIST), b.pt(R_WRIST), b.shoulder_mid(), b.hip_mid()
    if lw is None or rw is None or sm is None or hm is None:
        return _NO
    m = p["clap_y_margin"] * b.S
    in_band = all(sm[1] - m <= w[1] <= hm[1] + m for w in (lw, rw))
    ok, score = _near(b.d(lw, rw), p["clap_dist"])
    return ok and in_band, score if in_band else score * 0.5


def left_hand_up(b, p):
    lw, rw, ny, sm = b.pt(L_WRIST), b.pt(R_WRIST), b.nose_y(), b.shoulder_mid()
    if lw is None or ny is None or sm is None:
        return _NO
    up = (ny - lw[1]) / b.S
    # A missing right wrist is almost always a hand hanging by the side.
    right_down = rw is None or rw[1] > sm[1] + p["other_hand_below_shoulders"] * b.S
    ok = up > p["left_up_above_nose"] and right_down
    return ok, float(np.clip(up + 0.5, 0, 1)) * (1.0 if right_down else 0.5)


CHECKS = {
    "touch_nose": touch_nose,
    "touch_ear": touch_ear,
    "touch_head": touch_head,
    "hands_up": hands_up,
    "touch_tummy": touch_tummy,
    "touch_shoulders": touch_shoulders,
    "touch_knees": touch_knees,
    "clap": clap,
    "left_hand_up": left_hand_up,
}


def evaluate(name, kp, bbox, params, min_conf):
    """Run one named check. Returns (passed, score 0..1)."""
    b = Body(kp, bbox, params, min_conf)
    if b.S is None:
        return _NO
    return CHECKS[name](b, params)


def evaluate_all(kp, bbox, params, min_conf):
    return {name: evaluate(name, kp, bbox, params, min_conf) for name in CHECKS}


def is_neutral(kp, bbox, params, min_conf):
    """Hands down (well below shoulders) or not visible: safe to arm the next check."""
    b = Body(kp, bbox, params, min_conf)
    ws = b.wrists()
    if not ws:
        return True
    sm = b.shoulder_mid()
    if sm is None or b.S is None:
        return False
    return all(w[1] > sm[1] + params["neutral_below_shoulders"] * b.S for w in ws)
