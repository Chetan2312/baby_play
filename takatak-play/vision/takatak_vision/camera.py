"""Camera thread: Picamera2 dual stream (main → display, lores → inference).

main  : XBGR8888 → numpy [R,G,B,255] per pixel → JPEG "RGBX" (encoder.py), 960x540
lores : RGB888   → numpy [B,G,R] (Picamera2 naming), swapped to RGB in pose.py

Sensors are matched by model name (imx708_wide vs *_noir vs imx500), falling
back to camera_index in config. With a single camera connected, whatever is there
is used (the kit has only the AI Camera; the dev rig may run with one of its two).
Errors become a message string for the UI, not a crash.

IMX500 (AI Camera): used here as a plain camera feeding the Hailo. On-sensor
inference is a later optimisation (docs/model_matrix.md).

Rotation (camera mounted sideways or upside down): both streams are turned right after
capture, so pose, hands and the picture all see an upright image. right / left give a
portrait frame (e.g. 1080x1920); the encoder and the game follow the frame's shape.
"""
import threading
import time
from dataclasses import dataclass

import numpy as np

from .hardware import camera_kind
from .slots import LatestSlot

# rotation name → np.rot90 k (quarter turns counter-clockwise); right = 90° clockwise
ROTATIONS = {"normal": 0, "right": -1, "inverted": 2, "left": 1}


def rotate_frame(img, rotation):
    """Turn an (H, W, C) frame; a contiguous copy unless rotation is normal."""
    k = ROTATIONS[rotation]
    return img if k == 0 else np.ascontiguousarray(np.rot90(img, k))


def rotated_size(size, rotation):
    """(w, h) after rotation: right / left swap the sides."""
    w, h = size
    return (h, w) if ROTATIONS[rotation] % 2 else (w, h)


class CameraError(Exception):
    pass


@dataclass
class FrameBundle:
    main: np.ndarray    # (H, W, 4) RGBX
    lores: np.ndarray   # (h, w, 3) BGR
    t: float            # capture time (monotonic)
    camera: str
    frame_id: int = 0


def lores_size_for(main_size, input_size):
    w, h = main_size
    lh = int(round(input_size * h / w / 2)) * 2
    return (input_size, lh)


def list_cameras():
    from picamera2 import Picamera2
    return Picamera2.global_camera_info()


def find_camera_num(which, cfg):
    """→ (camera number, actual kind). Raises CameraError with a friendly message."""
    infos = list_cameras()
    if not infos:
        raise CameraError("No camera detected. Check ribbon cables, then: rpicam-hello --list-cameras")
    cams = [(i.get("Num", n), str(i.get("Model", "")).lower()) for n, i in enumerate(infos)]
    hits = [num for num, m in cams if camera_kind(m) == which]
    if which == "wide":
        hits.sort(key=lambda num: "wide" not in dict(cams)[num])
    if hits:
        return hits[0], which
    if len(cams) == 1:   # single-camera setup: use what is there
        num, m = cams[0]
        print(f"[camera] '{which}' not connected; using the only camera ({m})")
        return num, camera_kind(m)
    idx = cfg["camera_index"].get(which)
    if idx is not None and idx < len(infos):
        return idx, camera_kind(cams[idx][1])
    found = ", ".join(m for _, m in cams)
    raise CameraError(f"'{which}' camera not found (found: {found})")


class CameraThread(threading.Thread):
    def __init__(self, cfg, perf_rate=None):
        super().__init__(daemon=True, name="camera")
        self.cfg = cfg
        self.copts = cfg["camera_opts"]
        self.main_size = tuple(self.copts["main_size"])
        self.lores_size = lores_size_for(self.main_size, cfg["inference"]["input_size"])
        self.slot = LatestSlot()
        self.rate = perf_rate
        self.error = None
        self.status = "starting camera…"
        self.active = None
        self._want = cfg["camera"]
        self.rotation = self.copts.get("rotation", "normal")
        self._frame_id = 0
        self._quit = threading.Event()
        self._switch = threading.Event()

    # UI thread API
    def set_rotation(self, rotation):
        rotated_size((1, 1), rotation)   # KeyError on an unknown name
        self.rotation = rotation         # read once per frame by the capture loop

    def request_switch(self, which=None):
        if which is None:
            which = "noir" if self.active == "wide" else "wide"
        self._want = which
        self._switch.set()

    def stop(self):
        self._quit.set()
        self._switch.set()

    # thread
    def _open(self, which):
        from picamera2 import Picamera2
        num, kind = find_camera_num(which, self.cfg)
        cam = Picamera2(num)
        controls = {"FrameRate": float(self.copts["framerate"]), **(self.copts.get("controls") or {})}
        config = cam.create_preview_configuration(
            main={"size": self.main_size, "format": "XBGR8888"},
            lores={"size": self.lores_size, "format": "RGB888"},
            controls=controls, buffer_count=4)
        cam.configure(config)
        cam.start()
        return cam, kind

    @staticmethod
    def _grab(cam):
        req = cam.capture_request()
        try:
            main = req.make_array("main")
            lores = req.make_array("lores")
        finally:
            req.release()
        return main, lores

    def _auto_pick(self):
        """Measure brightness on the colour camera; dark room → NoIR."""
        try:
            if len(list_cameras()) == 1:   # nothing to choose between
                return camera_kind(list_cameras()[0].get("Model", ""))
        except Exception:  # noqa: BLE001
            pass
        try:
            cam, _ = self._open("wide")
        except Exception:
            return "noir"
        try:
            for _ in range(int(self.copts["auto_probe_frames"])):  # let AE settle
                _, lores = self._grab(cam)
            luma = float(lores[::8, ::8].mean())
        finally:
            cam.close()
        pick = "wide" if luma >= self.copts["auto_brightness_threshold"] else "noir"
        print(f"[camera] auto: mean luma {luma:.0f} → {pick}")
        return pick

    def run(self):
        try:
            import picamera2  # noqa: F401
        except ImportError:
            self.error = "picamera2 not installed (run install.sh on the Pi)"
            return
        while not self._quit.is_set():
            which = self._want
            if which == "auto":
                self.status = "auto-selecting camera…"
                which = self._auto_pick()
            self._switch.clear()
            self.status = f"starting {which} camera…"
            try:
                cam, which = self._open(which)
            except Exception as e:  # noqa: BLE001 - any libcamera failure → on-screen message
                self.error = f"Camera '{which}': {e}"
                self.active = which
                self._switch.wait(2.0)
                continue
            self.error, self.active, self.status = None, which, ""
            try:
                while not self._switch.is_set():
                    main, lores = self._grab(cam)
                    rot = self.rotation
                    if rot != "normal":
                        main, lores = rotate_frame(main, rot), rotate_frame(lores, rot)
                    if not main.flags.c_contiguous:
                        main = np.ascontiguousarray(main)
                    self._frame_id += 1
                    self.slot.put(FrameBundle(main, lores, time.monotonic(), which, self._frame_id))
                    if self.rate:
                        self.rate.tick()
            except Exception as e:  # noqa: BLE001
                self.error = f"Camera '{which}' stopped: {e}"
                time.sleep(1.0)
            finally:
                cam.close()
            self.slot.clear()


class VideoThread(threading.Thread):
    """DEV ONLY: play a recorded clip as if it were the camera (offline tuning)."""

    def __init__(self, cfg, path, perf_rate=None):
        super().__init__(daemon=True, name="video")
        self.path = path
        self.main_size = tuple(cfg["camera_opts"]["main_size"])
        self.lores_size = lores_size_for(self.main_size, cfg["inference"]["input_size"])
        self.slot = LatestSlot()
        self.rate = perf_rate
        self.error = None
        self.status = ""
        self.active = "video"
        self.rotation = cfg["camera_opts"].get("rotation", "normal")
        self._frame_id = 0
        self._quit = threading.Event()

    def request_switch(self, which=None):
        pass

    def set_rotation(self, rotation):
        rotated_size((1, 1), rotation)
        self.rotation = rotation

    def stop(self):
        self._quit.set()

    def run(self):
        import cv2
        cap = cv2.VideoCapture(self.path)
        if not cap.isOpened():
            self.error = f"cannot open video {self.path}"
            return
        period = 1.0 / (cap.get(cv2.CAP_PROP_FPS) or 30.0)
        while not self._quit.is_set():
            t0 = time.monotonic()
            ok, frame = cap.read()
            if not ok:
                cap.set(cv2.CAP_PROP_POS_FRAMES, 0)
                continue
            main = cv2.cvtColor(cv2.resize(frame, self.main_size), cv2.COLOR_BGR2RGBA)
            lores = cv2.resize(frame, self.lores_size)  # BGR like Picamera2 RGB888
            rot = self.rotation
            main, lores = rotate_frame(main, rot), rotate_frame(lores, rot)
            self._frame_id += 1
            self.slot.put(FrameBundle(main, lores, time.monotonic(), "video", self._frame_id))
            if self.rate:
                self.rate.tick()
            time.sleep(max(0.0, period - (time.monotonic() - t0)))
        cap.release()
