"""Hand tracking: 21 landmarks per hand (MediaPipe Hand Landmarker, CPU), fingers, gesture.

The pose model finds each child's wrists and elbows but no fingers, and a child's hand at
play distance is only ~30–40 px in the 960-wide stream. So:
  1. hand_roi(): a square box around each hand, from the pose wrist + elbow, in a
     HIGH-RESOLUTION camera frame (e.g. 1920×1080 main stream);
  2. the crop goes to the hand landmarker (one tracker per player hand, VIDEO mode, so
     palm detection is skipped while the hand stays tracked);
  3. fingers_extended() / gesture(): which fingers are up → count, open, fist, point.

Landmark order (MediaPipe): 0 wrist · thumb 1–4 · index 5–8 · middle 9–12 · ring 13–16 ·
pinky 17–20 (mcp, pip, dip, tip). Returned landmarks are normalised to the FULL frame,
in camera orientation; mirror_x() converts to display space like the pose keypoints.

Model file: vision/models/hand_landmarker.task (see requirements-hands.txt). Frames stay
in memory; nothing is saved.
"""
import math
import os

import numpy as np

from .config import path as vision_path

MODEL = "models/hand_landmarker.task"
MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/"
             "float16/latest/hand_landmarker.task")
FINGERS = ("thumb", "index", "middle", "ring", "pinky")
CONNECTIONS = ((0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (5, 9), (9, 10), (10, 11),
               (11, 12), (9, 13), (13, 14), (14, 15), (15, 16), (13, 17), (17, 18), (18, 19), (19, 20), (0, 17))
TIPS = (4, 8, 12, 16, 20)
HAND_PER_FOREARM = 0.6


class HandsError(Exception):
    pass


def hand_roi(wrist, elbow, frame_w, frame_h, scale=2.4, min_px=64):
    """Square crop (x0, y0, x1, y1) in frame pixels around a hand.

    wrist / elbow: (x, y) normalised to the frame (camera orientation). The box centre
    sits beyond the wrist along the forearm; its side is scale × the estimated hand length.
    """
    wx, wy = wrist[0] * frame_w, wrist[1] * frame_h
    ex, ey = elbow[0] * frame_w, elbow[1] * frame_h
    fx, fy = wx - ex, wy - ey
    hand = math.hypot(fx, fy) * HAND_PER_FOREARM
    side = max(min_px, hand * scale)
    cx, cy = wx + fx * 0.45, wy + fy * 0.45
    x0, y0 = int(round(cx - side / 2)), int(round(cy - side / 2))
    x0 = min(max(0, x0), max(0, frame_w - int(side)))
    y0 = min(max(0, y0), max(0, frame_h - int(side)))
    x1, y1 = min(frame_w, x0 + int(side)), min(frame_h, y0 + int(side))
    return x0, y0, x1, y1


def fingers_extended(lm):
    """lm: (21, 2+) landmarks (any consistent units) → [thumb, index, middle, ring, pinky] bools.

    A finger is up when its tip is clearly farther from the wrist than its middle joint
    (works in any hand rotation). Thumb: tip clearly farther from the index knuckle than
    the thumb's own middle joint.
    """
    p = np.asarray(lm, dtype=np.float64)[:, :2]
    d = lambda a, b: float(np.linalg.norm(p[a] - p[b]))  # noqa: E731
    out = [d(4, 5) > d(3, 5) * 1.25 and d(4, 17) > d(5, 17) * 0.9]
    for mcp, pip, tip in ((5, 6, 8), (9, 10, 12), (13, 14, 16), (17, 18, 20)):
        out.append(d(tip, 0) > d(pip, 0) * 1.2 and d(tip, mcp) > d(pip, mcp) * 1.5)
    return out


def gesture(ext):
    """→ "point" (index only; thumb ignored) | "open" | "fist" | "other"."""
    thumb, index, middle, ring, pinky = ext
    if index and not (middle or ring or pinky):
        return "point"
    if sum(ext) >= 4:
        return "open"
    if not (index or middle or ring or pinky):
        return "fist"
    return "other"


def mirror_x(lm):
    out = np.array(lm, dtype=np.float64, copy=True)
    out[:, 0] = 1.0 - out[:, 0]
    return out


class HandTracker:
    """One MediaPipe Hand Landmarker per (player, side); feed crops, get full-frame landmarks."""

    def __init__(self, model=MODEL, min_conf=0.4):
        model_path = vision_path(model)
        if not os.path.exists(model_path):
            raise HandsError(f"hand model missing: {model} (download: curl -L -o vision/{model} {MODEL_URL})")
        try:
            import mediapipe as mp
            from mediapipe.tasks import python as mpt
            from mediapipe.tasks.python import vision
        except ImportError as e:
            raise HandsError(f"mediapipe not installed ({e}): .env/bin/pip install -r vision/requirements-hands.txt") from e
        self._mp, self._mpt, self._vision = mp, mpt, vision
        self.model_path = model_path
        self.min_conf = min_conf
        self._trackers = {}
        self._ts = {}

    def _tracker(self, key):
        tr = self._trackers.get(key)
        if tr is None:
            v = self._vision
            opts = v.HandLandmarkerOptions(
                base_options=self._mpt.BaseOptions(model_asset_path=self.model_path),
                running_mode=v.RunningMode.VIDEO, num_hands=1,
                min_hand_detection_confidence=self.min_conf, min_hand_presence_confidence=self.min_conf,
                min_tracking_confidence=self.min_conf)
            tr = self._trackers[key] = v.HandLandmarker.create_from_options(opts)
            self._ts[key] = 0
        return tr

    def forget(self, keep_keys):
        for k in list(self._trackers):
            if k not in keep_keys:
                self._trackers.pop(k).close()
                self._ts.pop(k, None)

    def track(self, key, frame_rgb, roi, t_ms):
        """frame_rgb: (H, W, 3+) uint8 camera frame · roi: from hand_roi() · t_ms: monotonic ms.
        → {"landmarks": (21, 3) normalised to the full frame, "fingers", "count", "gesture",
           "score"} or None when no hand is found in the box."""
        x0, y0, x1, y1 = roi
        if x1 - x0 < 16 or y1 - y0 < 16:
            return None
        crop = np.ascontiguousarray(frame_rgb[y0:y1, x0:x1, :3])
        img = self._mp.Image(image_format=self._mp.ImageFormat.SRGB, data=crop)
        ts = max(int(t_ms), self._ts.get(key, 0) + 1)   # VIDEO mode needs rising timestamps
        res = self._tracker(key).detect_for_video(img, ts)
        self._ts[key] = ts
        if not res.hand_landmarks:
            return None
        h, w = frame_rgb.shape[:2]
        cw, ch = x1 - x0, y1 - y0
        lm = np.array([[(x0 + p.x * cw) / w, (y0 + p.y * ch) / h, p.z] for p in res.hand_landmarks[0]])
        crop_px = np.array([[p.x * cw, p.y * ch] for p in res.hand_landmarks[0]])
        ext = fingers_extended(crop_px)
        score = float(res.handedness[0][0].score) if res.handedness else 0.0
        return {"landmarks": lm, "fingers": ext, "count": int(sum(ext)), "gesture": gesture(ext), "score": score}

    def close(self):
        self.forget(set())
