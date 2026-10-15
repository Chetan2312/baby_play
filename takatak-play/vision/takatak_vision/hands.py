"""Hand tracking: 21 landmarks per hand (MediaPipe hand landmark model, CPU), fingers, gesture.

The pose model finds each child's wrists and elbows but no fingers, and a child's hand at
play distance is only ~30–40 px in the 960-wide stream. So, in the HIGH-RESOLUTION camera
frame (e.g. 1920×1080 main stream):
  1. a square box per hand, turned so the hand points up: from the hand's own landmarks
     of the previous frame while it stays tracked (landmark_rect), else from the pose
     wrist + elbow (pose_rect). warp_rect() cuts it straight to the model input size;
  2. backend "litert" (default): only the landmark model (hand_landmarks_detector.tflite,
     read from the .task bundle) runs on LiteRT, no palm detector: the box already says
     where the hand is. Hands run in parallel on a small interpreter pool.
     backend "mediapipe": the full Hand Landmarker (palm detector + landmarks), slower;
  3. fingers_extended() / gesture(): which fingers are up → count, open, fist, point.

Landmark order (MediaPipe): 0 wrist · thumb 1–4 · index 5–8 · middle 9–12 · ring 13–16 ·
pinky 17–20 (mcp, pip, dip, tip). Returned landmarks are normalised to the FULL frame,
in camera orientation; mirror_x() converts to display space like the pose keypoints.

Model file: vision/models/hand_landmarker.task (see requirements-hands.txt). Frames stay
in memory; nothing is saved.
"""
import math
import os
import queue
import threading
import time
import zipfile
from concurrent.futures import ThreadPoolExecutor

import numpy as np

from . import protocol as P
from .config import path as vision_path
from .slots import LatestSlot
from .tracker import KeypointSmoother

MODEL = "models/hand_landmarker.task"
MODEL_URL = ("https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/"
             "float16/latest/hand_landmarker.task")
FINGERS = ("thumb", "index", "middle", "ring", "pinky")
CONNECTIONS = ((0, 1), (1, 2), (2, 3), (3, 4), (0, 5), (5, 6), (6, 7), (7, 8), (5, 9), (9, 10), (10, 11),
               (11, 12), (9, 13), (13, 14), (14, 15), (15, 16), (13, 17), (17, 18), (18, 19), (19, 20), (0, 17))
TIPS = (4, 8, 12, 16, 20)
HAND_PER_FOREARM = 0.6
LANDMARK_TFLITE = "hand_landmarks_detector.tflite"   # inside the .task bundle
RECT_POINTS = (0, 1, 2, 3, 5, 6, 9, 10, 13, 14, 17, 18)   # palm + finger bases: steady box size


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


def pose_rect(wrist, elbow, scale=2.4, min_px=64):
    """Turned hand box from the pose: (cx, cy, side, ux, uy) in frame pixels.

    wrist / elbow in frame pixels. (ux, uy): unit vector the fingers point to (elbow →
    wrist); the box centre sits beyond the wrist, side = scale × estimated hand length.
    """
    fx, fy = wrist[0] - elbow[0], wrist[1] - elbow[1]
    n = math.hypot(fx, fy)
    if n < 1e-6:
        return wrist[0], wrist[1], float(min_px), 0.0, -1.0
    side = max(min_px, n * HAND_PER_FOREARM * scale)
    return wrist[0] + fx * 0.45, wrist[1] + fy * 0.45, side, fx / n, fy / n


def landmark_rect(lm, min_px=64):
    """Turned hand box from last frame's landmarks (frame pixels, (21, 2+)), as MediaPipe
    tracks: up = wrist → middle of the knuckles, side = 2 × the palm/finger-base extent."""
    p = np.asarray(lm, dtype=np.float64)[:, :2]
    m = ((p[5] + p[13]) / 2 + p[9]) / 2
    d = m - p[0]
    n = float(np.hypot(*d))
    if n < 1e-6:
        return None
    u = d / n
    r = np.array([-u[1], u[0]])
    pts = p[list(RECT_POINTS)]
    a, b = pts @ r, pts @ u
    size = max(a.max() - a.min(), b.max() - b.min())
    c = r * (a.max() + a.min()) / 2 + u * (b.max() + b.min()) / 2 + u * 0.1 * size
    return float(c[0]), float(c[1]), max(float(min_px), 2.0 * size), float(u[0]), float(u[1])


def rect_matrix(rect, size):
    """2×3 affine: model input pixel (a, b) → frame pixel. Input "up" = the hand's up."""
    cx, cy, side, ux, uy = rect
    rx, ry = -uy, ux
    k = side / size
    return np.array([[k * rx, -k * ux, cx - side / 2 * (rx - ux)],
                     [k * ry, -k * uy, cy - side / 2 * (ry - uy)]])


def warp_rect(frame, rect, size):
    """Cut the turned box out of the frame as a (size, size, 3) uint8 image (outside = black)."""
    import cv2
    out = cv2.warpAffine(frame, rect_matrix(rect, size), (size, size),
                         flags=cv2.INTER_LINEAR | cv2.WARP_INVERSE_MAP, borderMode=cv2.BORDER_CONSTANT)
    return np.ascontiguousarray(out[..., :3])


def rect_to_frame(lm_norm, rect, frame_w, frame_h):
    """Landmarks normalised to the box → normalised to the full frame."""
    m = rect_matrix(rect, 1.0)
    p = np.asarray(lm_norm, dtype=np.float64)
    out = np.array(p, copy=True)
    out[:, 0] = (m[0, 0] * p[:, 0] + m[0, 1] * p[:, 1] + m[0, 2]) / frame_w
    out[:, 1] = (m[1, 0] * p[:, 0] + m[1, 1] * p[:, 1] + m[1, 2]) / frame_h
    return out


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


def crop_to_frame(lm_crop, roi, frame_w, frame_h):
    x0, y0, x1, y1 = roi
    out = np.array(lm_crop, dtype=np.float64, copy=True)
    out[:, 0] = (x0 + out[:, 0] * (x1 - x0)) / frame_w
    out[:, 1] = (y0 + out[:, 1] * (y1 - y0)) / frame_h
    return out


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

    def track_crop(self, key, crop, t_ms):
        """crop: (h, w, 3) uint8 RGB hand box · t_ms: monotonic ms.
        → {"lm_crop": (21, 3) normalised to the crop, "fingers", "count", "gesture", "score"}
        or None when no hand is found."""
        ch, cw = crop.shape[:2]
        if cw < 16 or ch < 16:
            return None
        img = self._mp.Image(image_format=self._mp.ImageFormat.SRGB, data=np.ascontiguousarray(crop[..., :3]))
        ts = max(int(t_ms), self._ts.get(key, 0) + 1)   # VIDEO mode needs rising timestamps
        res = self._tracker(key).detect_for_video(img, ts)
        self._ts[key] = ts
        if not res.hand_landmarks:
            return None
        lm = np.array([[p.x, p.y, p.z] for p in res.hand_landmarks[0]])
        ext = fingers_extended(lm[:, :2] * [cw, ch])
        score = float(res.handedness[0][0].score) if res.handedness else 0.0
        return {"lm_crop": lm, "fingers": ext, "count": int(sum(ext)), "gesture": gesture(ext), "score": score}

    def track(self, key, frame_rgb, roi, t_ms):
        """frame_rgb: (H, W, 3+) uint8 camera frame · roi: from hand_roi() · t_ms: monotonic ms.
        → like track_crop() plus "landmarks": (21, 3) normalised to the full frame."""
        x0, y0, x1, y1 = roi
        res = self.track_crop(key, frame_rgb[y0:y1, x0:x1], t_ms)
        if res is not None:
            res["landmarks"] = crop_to_frame(res["lm_crop"], roi, frame_rgb.shape[1], frame_rgb.shape[0])
        return res

    def close(self):
        self.forget(set())


# ---- backends: same interface, run(jobs, t_ms) → {key: track_crop result | None} --------

class InProcessHands:
    """Hand model in this process (tools, tests)."""

    def __init__(self, tracker):
        self.tracker = tracker

    def run(self, jobs, t_ms):
        return {key: self.tracker.track_crop(key, crop, t_ms) for key, crop in jobs}

    def forget(self, keys):
        self.tracker.forget(set(keys))

    def close(self):
        self.tracker.close()


def _load_interpreter_class():
    try:
        from ai_edge_litert.interpreter import Interpreter
        return Interpreter
    except ImportError:
        pass
    try:
        from tflite_runtime.interpreter import Interpreter
        return Interpreter
    except ImportError:
        pass
    try:
        from tensorflow.lite import Interpreter
        return Interpreter
    except ImportError as e:
        raise HandsError(f"LiteRT not installed ({e}): .env/bin/pip install -r vision/requirements-hands.txt") from e


def _landmark_model_bytes(model_path):
    """The landmark model: a .tflite file, or read from the MediaPipe .task bundle (a zip)."""
    if model_path.endswith(".tflite"):
        with open(model_path, "rb") as f:
            return f.read()
    try:
        with zipfile.ZipFile(model_path) as z:
            return z.read(LANDMARK_TFLITE)
    except (zipfile.BadZipFile, KeyError) as e:
        raise HandsError(f"{os.path.basename(model_path)}: no {LANDMARK_TFLITE} inside ({e})") from e


class LiteRTHands:
    """Landmark model only (no palm detector) on LiteRT, `workers` interpreters in parallel
    (LiteRT releases the Python lock while it runs). Jobs are hand boxes already cut to
    `input_size`, hand pointing up."""

    def __init__(self, model=MODEL, min_conf=0.4, workers=2, threads=2):
        model_path = vision_path(model)
        if not os.path.exists(model_path):
            raise HandsError(f"hand model missing: {model} (download: curl -L -o vision/{model} {MODEL_URL})")
        Interpreter = _load_interpreter_class()
        data = _landmark_model_bytes(model_path)
        self.min_conf = min_conf
        self._pool = queue.Queue()
        for _ in range(max(1, int(workers))):
            it = Interpreter(model_content=data, num_threads=max(1, int(threads)))
            it.allocate_tensors()
            self._pool.put(it)
        it = self._pool.queue[0]
        inp = it.get_input_details()[0]
        self.input_size = int(inp["shape"][1])
        self._in = inp["index"]
        outs = sorted(it.get_output_details(), key=lambda d: d["name"])
        self._lm = next(d["index"] for d in outs if int(np.prod(d["shape"])) == 63)   # screen landmarks
        self._presence = next(d["index"] for d in outs if int(np.prod(d["shape"])) == 1)
        self._exec = ThreadPoolExecutor(max_workers=max(1, int(workers)), thread_name_prefix="hand-litert")

    def track_crop(self, crop):
        """crop: (S, S, 3) uint8 RGB, S = input_size → result dict like HandTracker.track_crop, or None."""
        x = crop.astype(np.float32)[None] * (1.0 / 255.0)
        it = self._pool.get()
        try:
            it.set_tensor(self._in, x)
            it.invoke()
            lm = it.get_tensor(self._lm).reshape(21, 3).astype(np.float64)
            presence = float(it.get_tensor(self._presence).ravel()[0])
        finally:
            self._pool.put(it)
        if not 0.0 <= presence <= 1.0:                 # a model that outputs a logit
            presence = 1.0 / (1.0 + math.exp(-presence))
        if presence < self.min_conf:
            return None
        ext = fingers_extended(lm[:, :2])
        lm[:, :2] /= self.input_size
        return {"lm_crop": lm, "fingers": ext, "count": int(sum(ext)), "gesture": gesture(ext), "score": presence}

    def run(self, jobs, t_ms):
        if len(jobs) == 1:
            key, crop = jobs[0]
            return {key: self.track_crop(crop)}
        futs = {key: self._exec.submit(self.track_crop, crop) for key, crop in jobs}
        return {key: f.result() for key, f in futs.items()}

    def forget(self, keys):
        pass                                           # stateless: the thread keeps the boxes

    def close(self):
        self._exec.shutdown(wait=False)


def _worker_main(conn, model, min_conf):
    """Child process: owns the MediaPipe trackers. Messages: ("track", (jobs, t_ms)) →
    ("result", {key: res}) · ("forget", keys) · None = quit."""
    try:
        tracker = HandTracker(model, min_conf)
    except HandsError as e:
        conn.send(("error", str(e)))
        return
    conn.send(("ready", None))
    try:
        while True:
            msg = conn.recv()
            if msg is None:
                break
            kind, payload = msg
            if kind == "forget":
                tracker.forget(set(payload))
            elif kind == "track":
                jobs, t_ms = payload
                conn.send(("result", {key: tracker.track_crop(key, crop, t_ms) for key, crop in jobs}))
    except (EOFError, KeyboardInterrupt):
        pass
    finally:
        tracker.close()


class HandWorker:
    """Hand model in its OWN PROCESS (another CPU core, no Python GIL shared with the camera,
    pose and JPEG threads). Only the small hand crops cross the pipe (~100 KB each)."""

    def __init__(self, model=MODEL, min_conf=0.4, start_timeout_s=60.0, reply_timeout_s=2.0):
        import multiprocessing as mproc
        ctx = mproc.get_context("spawn")   # a clean child: no camera / Hailo state inherited
        self.conn, child = ctx.Pipe()
        self.proc = ctx.Process(target=_worker_main, args=(child, model, min_conf), daemon=True,
                                name="takatak-hands")
        self.proc.start()
        child.close()
        self.reply_timeout_s = reply_timeout_s
        if not self.conn.poll(start_timeout_s):
            self.close()
            raise HandsError("hand worker didn't start")
        kind, payload = self.conn.recv()
        if kind == "error":
            self.close()
            raise HandsError(payload)

    def run(self, jobs, t_ms):
        self.conn.send(("track", (jobs, t_ms)))
        if not self.conn.poll(self.reply_timeout_s):
            raise HandsError("hand worker stopped answering")
        return self.conn.recv()[1]

    def forget(self, keys):
        self.conn.send(("forget", list(keys)))

    def close(self):
        try:
            self.conn.send(None)
        except (OSError, ValueError):
            pass
        self.proc.join(timeout=2)
        if self.proc.is_alive():
            self.proc.terminate()


class HandThread(threading.Thread):
    """Camera frames + latest pose → hand landmarks for the game (protocol "hands").

    Runs only while `wanted` is set (a game subscribed to hands). Per frame, for each active
    player's (raised) hand: turned box in the high-resolution main frame (from the hand's
    own last landmarks while tracked, else from the pose wrist/elbow) → hand model
    (hands.backend) → One Euro (hand-tuned, on capture time) → display space. Focus: a hand
    that is pointing is tracked every frame, the other hands every `other_every` frames
    (their last result is re-sent in between).
    """

    def __init__(self, cfg, camera_slot, pose_slot, mirror, rate=None, tracker=None, perf=None):
        super().__init__(daemon=True, name="hands")
        self.hcfg = cfg.get("hands") or {}
        self.scfg = dict(cfg["smoothing"], filter="one_euro")
        self.scfg["one_euro"] = dict(cfg["smoothing"].get("one_euro") or {}, **(self.hcfg.get("one_euro") or {}))
        self.camera_slot = camera_slot
        self.pose_slot = pose_slot
        self.mirror = mirror
        self.rate = rate
        self.perf = perf
        self.results = LatestSlot()          # protocol "hands" message dicts
        self.wanted = threading.Event()
        self.error = None
        self.ready = False
        self._backend = InProcessHands(tracker) if tracker is not None else None
        self._smoothers = {}
        self._last = {}                      # key → last wire dict (re-sent for skipped hands)
        self._rects = {}                     # key → box from last frame's landmarks (camera frame px)
        self._frame_n = 0
        self._quit = threading.Event()

    def stop(self):
        self._quit.set()
        self.wanted.set()

    def _open(self):
        if self._backend is None:
            model, conf = self.hcfg.get("model", MODEL), float(self.hcfg.get("min_conf", 0.4))
            if self.hcfg.get("backend", "litert") == "litert":
                self._backend = LiteRTHands(model, conf, self.hcfg.get("workers", 2), self.hcfg.get("threads", 2))
            elif self.hcfg.get("process", False):
                self._backend = HandWorker(model, conf)
            else:
                self._backend = InProcessHands(HandTracker(model, conf))
        self.ready = True

    def process(self, frame, people, frame_id, t_ms):
        """One camera frame (camera orientation) + pose people (display coords) → message."""
        fh, fw = frame.shape[:2]
        only_raised = bool(self.hcfg.get("only_raised", True))
        scale = float(self.hcfg.get("box_scale", 2.4))
        other_every = max(1, int(self.hcfg.get("other_every", 3)))
        self._frame_n += 1
        size = int(getattr(self._backend, "input_size", None) or 256)
        pointing = {k for k, h in self._last.items() if h["gesture"] == "point"}
        jobs, rects, keys, carried = [], {}, set(), []
        cam = (lambda q: (((1.0 - q[0]) if self.mirror else q[0]) * fw, q[1] * fh))   # display → camera px
        for p in people:
            if not p.get("active"):
                continue
            for side in ("l", "r"):
                w, e = p["kp"].get(f"{side}_wrist"), p["kp"].get(f"{side}_elbow")
                if not (w and e and w[2] > 0.35 and e[2] > 0.35):
                    continue
                if only_raised and not w[1] < e[1] + 0.01:
                    continue
                key = (int(p["id"]), side)
                keys.add(key)
                if pointing and key not in pointing and key in self._last and self._frame_n % other_every:
                    carried.append(self._last[key])      # focus on the pointing hand this frame
                    continue
                wp, ep = cam(w), cam(e)
                rect = self._rects.get(key)
                if rect is not None and math.hypot(rect[0] - wp[0], rect[1] - wp[1]) > rect[2]:
                    rect = None                          # pose wrist is elsewhere: find the hand again
                rect = rect or pose_rect(wp, ep, scale=scale)
                rects[key] = rect
                jobs.append((key, warp_rect(frame, rect, size)))
        t0 = time.monotonic()
        results = self._backend.run(jobs, t_ms) if jobs else {}
        if self.perf is not None and jobs:
            self.perf.means["hand_ms"].add((time.monotonic() - t0) * 1000 / len(jobs))
        out = list(carried)
        for key, rect in rects.items():
            hand = results.get(key)
            if hand is None:
                self._smoothers.pop(key, None)
                self._last.pop(key, None)
                self._rects.pop(key, None)
                continue
            lm = rect_to_frame(hand["lm_crop"], rect, fw, fh)
            self._rects[key] = landmark_rect(lm[:, :2] * [fw, fh])   # raw (unsmoothed): next box
            lm = self._smooth(key, lm, fw, fh, t_ms / 1000.0)
            disp = mirror_x(lm) if self.mirror else lm
            wire = P.hand_to_wire(key[0], key[1], disp, hand["fingers"], hand["count"], hand["gesture"])
            self._last[key] = wire
            out.append(wire)
        if set(self._smoothers) - keys:
            self._backend.forget(keys)
        for k in list(self._smoothers):
            if k not in keys:
                del self._smoothers[k]
        for k in list(self._last):
            if k not in keys:
                del self._last[k]
        for k in list(self._rects):
            if k not in keys:
                del self._rects[k]
        return P.hands(frame_id, out, ts=t_ms)

    def _smooth(self, key, lm, fw, fh, now):
        """One Euro on the 21 points, in the same pixel units as the pose filter (640 wide)."""
        sm = self._smoothers.get(key)
        if sm is None:
            sm = self._smoothers[key] = KeypointSmoother(self.scfg, 0.0)
        k = 640.0
        arr = np.c_[lm[:, 0] * k, lm[:, 1] * k * fh / fw, np.ones(len(lm))]
        arr = sm.update(arr, now)
        out = np.array(lm, copy=True)
        out[:, 0] = arr[:, 0] / k
        out[:, 1] = arr[:, 1] / (k * fh / fw)
        return out

    def run(self):
        seq = 0
        while not self._quit.is_set():
            if not self.wanted.wait(0.5):
                continue
            if not self.ready:
                try:
                    self._open()
                except HandsError as e:
                    self.error = str(e)
                    self._quit.wait(5.0)      # don't retry in a tight loop
                    continue
            seq, bundle = self.camera_slot.wait_newer(seq, timeout=0.5)
            if bundle is None or not self.wanted.is_set():
                continue
            _, res = self.pose_slot.get()
            people = res.pose_msg["people"] if res is not None else []
            try:
                msg = self.process(bundle.main, people, bundle.frame_id, bundle.t * 1000)   # capture time
            except HandsError as e:            # worker died / stuck: restart it
                self.error = f"Hand tracking: {e}"
                self._close_backend()
                self.ready = False
                continue
            except Exception as e:  # noqa: BLE001 - keep the service up; show it on the status line
                self.error = f"Hand tracking: {e}"
                continue
            self.error = None
            self.results.put(msg)
            if self.perf is not None:
                self.perf.means["hand_latency_ms"].add((time.monotonic() - bundle.t) * 1000)
            if self.rate:
                self.rate.tick()
        self._close_backend()

    def _close_backend(self):
        if self._backend is not None:
            try:
                self._backend.close()
            except Exception:  # noqa: BLE001
                pass
            self._backend = None
