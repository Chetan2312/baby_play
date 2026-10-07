"""Mock vision source: a synthetic child (or a recorded session) instead of camera + Hailo.

Lets the Godot game be built and tested on any PC. The synthetic child goes
through the real Analyzer, so gesture events are exactly what the Pi sends.

Synthetic child control:
  - game sends {"t":"mock_expect","name":"touch_nose"} → child does it after
    `react_s`, holds it for `hold_s`, then returns to neutral
  - stdin commands (tools/mock_server.py): a check name, "neutral", "away", "back"
  - --auto: cycles through all poses by itself
  - "left" / "right" / "middle": the child steps to that side of the SCREEN (lane games)
  - hands (when a game subscribes): a raised RIGHT hand points (index finger), a raised
    LEFT hand is open, so finger games can be built without the hand model
"""
import base64
import io
import json
import math
import random
import threading
import time

import numpy as np

from . import protocol as P
from .analysis import AnalysisResult, Analyzer
from .gestures import SKELETON
from .perf import PerfLog
from .poses import NEUTRAL, TARGETS, bbox_of
from .slots import LatestSlot
from .tracker import Person

FRAME = (640, 360)          # lores-like analysis frame
DISPLAY = (960, 540)        # JPEG size, same as the Pi


def _place(kp):
    out = kp.copy()
    out[:, :2] = out[:, :2] * 0.8 + [64.0, 0.0]
    return out


class MockPerformer:
    def __init__(self, react_s=1.2, hold_s=2.0, auto=False, seed=None):
        self.react_s, self.hold_s, self.auto = react_s, hold_s, auto
        self.rng = random.Random(seed)
        self.present = True
        self._from = _place(NEUTRAL)
        self._to = self._from
        self._blend_t0 = 0.0
        self.current = "neutral"
        self._plan = []          # [(time, pose_name)]
        self._lock = threading.Lock()
        self._next_auto = 0.0
        self.dx = 0.0            # sideways step (camera px; + = screen left, the image is mirrored)

    def _go(self, name, now):
        target = _place(NEUTRAL if name == "neutral" else TARGETS[name])
        self._from = self._pose_at(now)
        self._to = target
        self._blend_t0 = now
        self.current = name

    def _pose_at(self, now):
        a = min(1.0, (now - self._blend_t0) / 0.3)
        a = a * a * (3 - 2 * a)
        return self._from + (self._to - self._from) * a

    def expect(self, name, now=None):
        now = time.monotonic() if now is None else now
        with self._lock:
            self._plan = []
            if name in TARGETS:
                self._plan = [(now + self.react_s, name), (now + self.react_s + self.hold_s, "neutral")]

    def command(self, cmd, now=None):
        now = time.monotonic() if now is None else now
        with self._lock:
            self._plan = []
            if cmd == "away":
                self.present = False
            elif cmd == "back":
                self.present = True
            elif cmd in ("left", "right", "middle"):
                self.dx = {"left": 170.0, "right": -170.0, "middle": 0.0}[cmd]
            elif cmd == "neutral" or cmd in TARGETS:
                self.present = True
                self._go(cmd, now)
            else:
                return False
        return True

    def kp(self, now):
        with self._lock:
            while self._plan and self._plan[0][0] <= now:
                _, name = self._plan.pop(0)
                self._go(name, now)
            if self.auto and not self._plan and now >= self._next_auto:
                name = "neutral" if self.current != "neutral" else self.rng.choice(list(TARGETS))
                self._go(name, now)
                self._next_auto = now + (1.5 if name == "neutral" else 2.5)
            if not self.present:
                return None
            kp = self._pose_at(now).copy()
        sway = math.sin(now * 1.3) * 4.0
        kp[:, 0] += self.dx + sway + np.sin(now * 7 + np.arange(17)) * 0.6
        kp[:, 1] += np.cos(now * 6 + np.arange(17)) * 0.6
        return kp


class _FramePainter:
    """Pre-mirrored synthetic camera image of the performer (Pillow → JPEG)."""

    def __init__(self, quality):
        from PIL import Image, ImageDraw
        self.Image, self.ImageDraw = Image, ImageDraw
        self.quality = quality
        w, h = DISPLAY
        yy, xx = np.mgrid[0:h, 0:w]
        bg = np.zeros((h, w, 3), np.uint8)
        bg[..., 0] = 40 + xx * 60 // w
        bg[..., 1] = 70 + yy * 50 // h
        bg[..., 2] = 110
        self.bg = Image.fromarray(bg)

    def paint(self, kp, label):
        img = self.bg.copy()
        d = self.ImageDraw.Draw(img)
        sx, sy = DISPLAY[0] / FRAME[0], DISPLAY[1] / FRAME[1]

        def P(i):  # mirrored display pixel
            return (DISPLAY[0] - kp[i, 0] * sx, kp[i, 1] * sy)
        if kp is not None:
            for a, b in SKELETON:
                d.line([P(a), P(b)], fill=(250, 220, 190), width=14)
            nx, ny = P(0)
            d.ellipse([nx - 38, ny - 45, nx + 38, ny + 35], fill=(250, 220, 190))
        d.text((16, 12), label, fill=(255, 255, 255))
        out = io.BytesIO()
        img.save(out, "JPEG", quality=self.quality)
        return out.getvalue()


def synthetic_hands(people):
    """Fake 21-point hands for raised arms (display coords): right = point, left = open."""
    out = []
    for p in people:
        if not p.get("active"):
            continue
        for side in ("l", "r"):
            w, e = p["kp"].get(f"{side}_wrist"), p["kp"].get(f"{side}_elbow")
            if not (w and e and w[2] > 0.35 and e[2] > 0.35 and w[1] < e[1] + 0.01):
                continue
            d = np.array([w[0] - e[0], w[1] - e[1]])
            n = np.linalg.norm(d) or 1.0
            d = d / n
            perp = np.array([-d[1], d[0]])
            L = n * 0.6
            base = np.array(w[:2])
            pts = [base]
            pointing = side == "r"
            for k, off in enumerate((-0.45, -0.2, 0.0, 0.2, 0.4)):   # thumb, index … pinky
                up = (k == 1) if pointing else True
                for j in range(1, 5):
                    reach = L * (0.3 + 0.18 * j) if up else L * (0.35 + 0.05 * j)
                    pts.append(base + d * reach + perp * L * off * (1.0 if up else 0.5))
            ext = [k == 1 if pointing else True for k in range(5)]
            out.append(P.hand_to_wire(p["id"], side, pts, ext, sum(ext), "point" if pointing else "open"))
    return out


class MockSource:
    camera_name = "mock"
    mic = False
    mirror = True
    hardware = {"profile": "mock", "accelerator": None, "accelerator_expected": None,
                "accelerator_present": False, "cameras": ["mock"], "audio": [], "mic": False,
                "network": "unknown", "errors": []}
    on_button = None

    def __init__(self, cfg, performer=None, replay=None, pose_hz=25.0, frame_hz=20.0):
        self.cfg = cfg
        self.performer = performer or MockPerformer()
        self.replay = replay
        self.pose_hz, self.frame_hz = pose_hz, frame_hz
        self.analyzer = Analyzer(cfg, FRAME)
        self.results = LatestSlot()
        self.frames = LatestSlot()
        self.hands_results = LatestSlot()
        self._want_hands = threading.Event()
        self.perf = PerfLog("/tmp/takatak_mock_perf.log", 3600, ("cam", "pose", "frames", "hands"))
        self.models = ["pose"]
        self._want_frames = threading.Event()
        self._quit = threading.Event()
        self._threads = []
        self.last_kp = None

    def errors(self):
        return []

    # game controls
    def set_camera(self, which):
        print(f"[mock] set_camera {which} (ignored)")

    def set_players(self, mode):
        self.analyzer.set_mode(mode)

    def set_difficulty(self, difficulty):
        self.analyzer.set_difficulty(difficulty)

    def set_frames_wanted(self, wanted):
        (self._want_frames.set if wanted else self._want_frames.clear)()

    def set_hands_wanted(self, wanted):
        (self._want_hands.set if wanted else self._want_hands.clear)()

    def mock_expect(self, name):
        if name:
            print(f"[mock] game expects {name}")
            self.performer.expect(name)

    def tick(self):
        now = time.monotonic()
        for r in self.perf.rates.values():
            r.sample(now)
        return None

    # threads
    def start(self):
        target = self._replay_loop if self.replay else self._pose_loop
        self._threads = [threading.Thread(target=target, daemon=True, name="mock-pose")]
        if not self.replay:
            self._threads.append(threading.Thread(target=self._frame_loop, daemon=True, name="mock-frames"))
        for t in self._threads:
            t.start()

    def stop(self):
        self._quit.set()
        for t in self._threads:
            t.join(timeout=2)

    def _pose_loop(self):
        fid = 0
        while not self._quit.is_set():
            now = time.monotonic()
            kp = self.performer.kp(now)
            self.last_kp = kp
            persons = [] if kp is None else [Person(bbox_of(kp), 0.9, kp)]
            fid += 1
            res = self.analyzer.process(persons, FRAME, now, fid)
            self.results.put(res)
            if self._want_hands.is_set():
                self.hands_results.put(P.hands(fid, synthetic_hands(res.pose_msg["people"])))
                self.perf.rates["hands"].tick()
            self.perf.rates["pose"].tick()
            self.perf.rates["cam"].tick()
            time.sleep(1.0 / self.pose_hz)

    def _frame_loop(self):
        painter = _FramePainter(self.cfg["server"]["jpeg_quality"])
        fid = 0
        while not self._quit.is_set():
            if not self._want_frames.wait(0.5):
                continue
            fid += 1
            self.frames.put((fid, painter.paint(self.last_kp, f"MOCK CAMERA  doing: {self.performer.current}")))
            self.perf.rates["frames"].tick()
            time.sleep(1.0 / self.frame_hz)

    def _replay_loop(self):
        """Replay a tools/record_session.py JSONL file in a loop, with original timing."""
        while not self._quit.is_set():
            with open(self.replay, encoding="utf-8") as f:
                lines = [json.loads(x) for x in f if x.strip()]
            t0 = time.monotonic()
            pending = []
            for rec in lines:
                if self._quit.is_set():
                    return
                delay = t0 + rec["rt"] - time.monotonic()
                if delay > 0:
                    time.sleep(delay)
                if "frame" in rec:
                    self.frames.put((rec.get("frame_id", 0), base64.b64decode(rec["frame"])))
                    continue
                msg = rec["msg"]
                if msg["t"] == "pose":
                    self.results.put(AnalysisResult(msg["frame_id"], time.monotonic(), msg, pending,
                                                    [p["id"] for p in msg["people"] if p["active"]]))
                    pending = []
                    self.perf.rates["pose"].tick()
                elif msg["t"] == "no_player":
                    self.results.put(AnalysisResult(0, time.monotonic(), {"t": "pose", "ts": msg["ts"],
                                                    "frame_id": 0, "people": []}, pending, [],
                                                    msg["seconds"]))
                    pending = []
                elif msg["t"] in ("gesture", "motion", "loudness", "keyword"):
                    pending.append(msg)
