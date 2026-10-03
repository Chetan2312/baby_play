"""Hailo-8 YOLOv8-pose inference thread.

Uses picamera2.devices.Hailo like picamera2 examples/hailo/pose_estimation.py.
The lores frame is letterboxed into the model input (no resize when the lores
width equals the model width, which camera.py arranges), and results come
back in LORES pixel coordinates, which are isotropic so gestures can use
plain distances.
"""
import os
import threading
import time
from dataclasses import dataclass

import numpy as np

from .config import path as project_path
from .player import Person
from .postprocess import decode_yolov8_pose
from .slots import LatestSlot


class PoseError(Exception):
    pass


@dataclass
class PoseResult:
    persons: list
    frame_size: tuple    # (w, h) of the lores frame the coordinates refer to
    t_capture: float
    t_done: float
    camera: str


class PoseEngine:
    def __init__(self, cfg):
        hef = project_path(cfg["model"])
        if not os.path.exists(hef):
            raise PoseError(f"Model not found: {cfg['model']}  (run ./install.sh or tools/fetch_model.sh)")
        try:
            from picamera2.devices import Hailo
        except ImportError as e:
            raise PoseError(f"Hailo bindings missing ({e}); run install.sh") from e
        try:
            self.hailo = Hailo(hef)
        except Exception as e:  # noqa: BLE001
            raise PoseError(f"Hailo could not load the model: {e}. "
                            "Check the AI HAT (hailortcli fw-control identify) and that the HEF "
                            "is compiled for Hailo-8, not Hailo-8L.") from e
        self.inf = cfg["inference"]
        h, w, _ = self.hailo.get_input_shape()
        self.input_hw = (h, w)
        self._buf = np.full((h, w, 3), self.inf["pad_value"], dtype=np.uint8)
        self._geom = None

    def _letterbox(self, frame):
        fh, fw = frame.shape[:2]
        h, w = self.input_hw
        if self._geom is None or self._geom[0] != (fh, fw):
            s = min(w / fw, h / fh)
            nw, nh = int(round(fw * s)), int(round(fh * s))
            ox, oy = (w - nw) // 2, (h - nh) // 2
            self._buf[:] = self.inf["pad_value"]
            self._geom = ((fh, fw), s, nw, nh, ox, oy)
        _, s, nw, nh, ox, oy = self._geom
        if (nw, nh) != (fw, fh):
            import cv2
            frame = cv2.resize(frame, (nw, nh))
        dst = self._buf[oy:oy + nh, ox:ox + nw]
        if self.inf["swap_rb"]:
            dst[...] = frame[..., ::-1]
        else:
            dst[...] = frame
        return s, ox, oy

    def infer(self, lores):
        s, ox, oy = self._letterbox(lores)
        raw = self.hailo.run(self._buf)
        try:
            boxes, scores, kpts = decode_yolov8_pose(
                raw, self.input_hw, self.inf["min_person_conf"], self.inf["nms_iou"],
                self.inf["max_people"])
        except ValueError as e:
            shapes = {k: getattr(v, "shape", None) for k, v in raw.items()} if isinstance(raw, dict) else "?"
            raise PoseError(f"HEF outputs don't look like yolov8 pose: {e} {shapes}") from e
        persons = []
        for b, sc, k in zip(boxes, scores, kpts):
            b = (b - [ox, oy, ox, oy]) / s
            k = k.astype(np.float64)
            k[:, 0] = (k[:, 0] - ox) / s
            k[:, 1] = (k[:, 1] - oy) / s
            persons.append(Person(b, float(sc), k))
        return persons

    def close(self):
        try:
            self.hailo.close()
        except Exception:  # noqa: BLE001
            pass


class InferenceThread(threading.Thread):
    def __init__(self, cfg, camera_slot, perf=None):
        super().__init__(daemon=True, name="inference")
        self.cfg = cfg
        self.camera_slot = camera_slot
        self.results = LatestSlot()
        self.perf = perf
        self.error = None
        self.status = "loading pose model…"
        self._quit = threading.Event()

    def stop(self):
        self._quit.set()

    def run(self):
        try:
            engine = PoseEngine(self.cfg)
        except PoseError as e:
            self.error, self.status = str(e), ""
            return
        self.status = ""
        seq = 0
        try:
            while not self._quit.is_set():
                seq, bundle = self.camera_slot.wait_newer(seq, timeout=0.5)
                if bundle is None:
                    continue
                try:
                    persons = engine.infer(bundle.lores)
                except PoseError as e:
                    self.error = str(e)
                    return
                now = time.monotonic()
                self.results.put(PoseResult(persons, (bundle.lores.shape[1], bundle.lores.shape[0]),
                                            bundle.t, now, bundle.camera))
                if self.perf:
                    self.perf.rates["inf"].tick()
                    self.perf.latency_ms.add((now - bundle.t) * 1000)
        except Exception as e:  # noqa: BLE001
            self.error = f"Inference stopped: {e}"
        finally:
            engine.close()
