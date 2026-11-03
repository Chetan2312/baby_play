"""USB webcam (UVC) via V4L2: the camera back-end of the n150 profile.

Same public surface and FrameBundle as camera.CameraThread, so server, pose, hands and
encoder don't know which camera back-end runs:

main  : MJPEG from the camera, decoded by simplejpeg (libjpeg-turbo) straight to RGBX
lores : main resized to the pose input width, BGR (like Picamera2 "RGB888")

OpenCV's own MJPEG decode in its V4L2 reader is slow (measured on the N150: 14 fps at
1080p against 28 fps raw), so OpenCV only hands over the compressed frame.

There is one USB camera: any set_camera request (wide / noir / imx500 / usb / auto) uses it.
Rotation is always done in software (UVC cameras don't flip on the sensor).
Unplugged camera → friendly error, retried every 2 s; replugging recovers.
"""
import glob
import subprocess
import threading
import time

import numpy as np

from .camera import FrameBundle, lores_size_for, rotate_frame, rotated_size
from .slots import LatestSlot

BY_ID = "/dev/v4l/by-id/*-video-index0"


def find_device(device="auto"):
    """'auto' → the first USB camera's stable by-id path (capture node), else /dev/video0."""
    if device and device != "auto":
        return device
    found = sorted(glob.glob(BY_ID))
    return found[0] if found else "/dev/video0"


def set_controls(device, controls):
    """Apply v4l2 controls (v4l2-ctl -c name=value). → error string or None."""
    if not controls:
        return None
    arg = ",".join(f"{k}={int(v)}" for k, v in controls.items())
    try:
        out = subprocess.run(["v4l2-ctl", "-d", device, "-c", arg], capture_output=True, text=True, timeout=3)
    except (OSError, subprocess.TimeoutExpired) as e:
        return f"v4l2-ctl: {e}"
    return (out.stderr.strip() or f"v4l2-ctl exit {out.returncode}") if out.returncode else None


class V4l2CameraThread(threading.Thread):
    def __init__(self, cfg, perf_rate=None):
        super().__init__(daemon=True, name="camera")
        self.cfg = cfg
        self.copts = cfg["camera_opts"]
        self.vopts = self.copts.get("v4l2") or {}
        self.main_size = tuple(self.copts["main_size"])
        self.lores_size = lores_size_for(self.main_size, cfg["inference"]["input_size"])
        self.slot = LatestSlot()
        self.rate = perf_rate
        self.error = None
        self.status = "starting camera…"
        self.active = None
        self.rotation = self.copts.get("rotation", "normal")
        self.hw_flip = False
        self._frame_id = 0
        self._quit = threading.Event()
        self._switch = threading.Event()

    # UI thread API
    def set_rotation(self, rotation):
        rotated_size((1, 1), rotation)   # KeyError on an unknown name
        self.rotation = rotation         # read once per frame by the capture loop

    def request_switch(self, which=None):
        pass                             # one USB camera: nothing to switch to

    def stop(self):
        self._quit.set()
        self._switch.set()

    # thread
    def _open(self, device):
        import cv2
        warn = set_controls(device, self.vopts.get("controls"))
        if warn:
            print(f"[camera] controls: {warn}")
        cap = cv2.VideoCapture(device, cv2.CAP_V4L2)
        if not cap.isOpened():
            raise OSError(f"cannot open {device}")
        w, h = self.main_size
        cap.set(cv2.CAP_PROP_FOURCC, cv2.VideoWriter_fourcc(*"MJPG"))
        cap.set(cv2.CAP_PROP_FRAME_WIDTH, w)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, h)
        cap.set(cv2.CAP_PROP_FPS, float(self.copts["framerate"]))
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)
        cap.set(cv2.CAP_PROP_CONVERT_RGB, 0)   # hand over the MJPEG bytes, simplejpeg decodes
        got = (int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)), int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)))
        if got != (w, h):
            print(f"[camera] asked for {w}x{h} MJPG, camera gives {got[0]}x{got[1]}")
        return cap

    def _frames(self, main):
        """Decoded RGBX main → (main, lores BGR), both turned by the current rotation."""
        import cv2
        if main.shape[1::-1] != self.main_size:
            main = cv2.resize(main, self.main_size, interpolation=cv2.INTER_AREA)
        lores = cv2.cvtColor(cv2.resize(main, self.lores_size, interpolation=cv2.INTER_AREA),
                             cv2.COLOR_RGBA2BGR)
        rot = self.rotation
        if rot != "normal":
            main, lores = rotate_frame(main, rot), rotate_frame(lores, rot)
        return main, lores

    def run(self):
        try:
            import cv2  # noqa: F401
            import simplejpeg
        except ImportError as e:
            self.error = f"USB camera needs opencv + simplejpeg ({e}): pip install -r vision/requirements-pc.txt"
            return
        while not self._quit.is_set():
            device = find_device(self.vopts.get("device", "auto"))
            self.status = "starting usb camera…"
            try:
                cap = self._open(device)
            except Exception as e:  # noqa: BLE001 - unplugged / busy → on-screen message, retry
                self.error = f"USB camera: {e}. Check the cable (v4l2-ctl --list-devices)"
                self.active = "usb"
                self._switch.wait(2.0)
                continue
            self.error, self.active, self.status = None, "usb", ""
            print(f"[camera] usb: {device}")
            bad = 0
            try:
                while not self._quit.is_set():
                    ok, buf = cap.read()
                    t = time.monotonic()
                    if not ok:
                        raise OSError("no frame (unplugged?)")
                    try:
                        main = simplejpeg.decode_jpeg(buf.tobytes(), colorspace="RGBX")
                    except ValueError as e:   # a truncated USB frame now and then: skip it
                        bad += 1
                        if bad >= 30:
                            raise OSError(f"30 broken frames in a row ({e})") from e
                        continue
                    bad = 0
                    main, lores = self._frames(main)
                    self._frame_id += 1
                    self.slot.put(FrameBundle(np.ascontiguousarray(main), lores, t, "usb", self._frame_id))
                    if self.rate:
                        self.rate.tick()
            except Exception as e:  # noqa: BLE001
                self.error = f"USB camera stopped: {e}"
                self._switch.wait(1.0)
            finally:
                cap.release()
            self.slot.clear()
