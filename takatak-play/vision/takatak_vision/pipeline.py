"""Real hardware source: camera → pose → analysis, and camera → JPEG.

A "source" is what server.py talks to. tools/mock_server.py provides another
one with the same attributes, so the server code is identical in both.
"""
import glob
import os
import time

from .analysis import Analyzer
from .button import GpioButton
from .camera import CameraThread, VideoThread, lores_size_for, rotated_size
from .camera_v4l2 import V4l2CameraThread
from .config import path
from .encoder import FrameEncoder
from .hands import HandThread
from .perf import PerfLog
from .pose import InferenceThread


CAMERAS = {"picamera2": CameraThread, "v4l2": V4l2CameraThread}
CPU_ZONES = ("x86_pkg_temp",)   # x86: thermal_zone0 is usually acpitz (the board, not the CPU)
_temp_path = None


def cpu_temp_path(sys_thermal="/sys/class/thermal"):
    """The CPU's thermal zone: x86_pkg_temp on Intel, else thermal_zone0 (cpu-thermal on the Pi)."""
    for zone in sorted(glob.glob(os.path.join(sys_thermal, "thermal_zone*"))):
        try:
            with open(os.path.join(zone, "type")) as f:
                if f.read().strip() in CPU_ZONES:
                    return os.path.join(zone, "temp")
        except OSError:
            continue
    return os.path.join(sys_thermal, "thermal_zone0", "temp")


def read_temp_c():
    global _temp_path
    if _temp_path is None:
        _temp_path = cpu_temp_path()
    try:
        with open(_temp_path) as f:
            return int(f.read().strip()) / 1000.0
    except (OSError, ValueError):
        return None


class HardwareSource:
    mic = False   # Phase P5

    def __init__(self, cfg, video=None, hardware=None):
        self.cfg = cfg
        self.hardware = dict(hardware or {})   # boot probe (hardware.probe) for hello
        self.on_button = None                  # set by VisionServer
        self.button = GpioButton(cfg, self._button)
        scfg = cfg["server"]
        self.mirror = cfg["display"]["mirror"]
        self.perf = PerfLog(path(cfg["paths"]["perf_log"]), cfg["perf"]["log_every_s"],
                            ("cam", "pose", "frames", "hands"))
        main_size = tuple(cfg["camera_opts"]["main_size"])
        self.analyzer = Analyzer(cfg, lores_size_for(main_size, cfg["inference"]["input_size"]))
        if video:
            self.cam = VideoThread(cfg, video, self.perf.rates["cam"])
        else:
            backend = cfg.get("profile", {}).get("camera_backend", "picamera2")
            self.cam = CAMERAS[backend](cfg, self.perf.rates["cam"])
        self.inf = InferenceThread(cfg, self.cam.slot, self.analyzer, self.perf)
        self.enc = FrameEncoder(self.cam.slot, scfg["jpeg_quality"], scfg["frame_fps"],
                                self.mirror, self.perf.rates["frames"],
                                cfg["camera_opts"].get("transport_size"))
        self.results = self.inf.results
        self.frames = self.enc.frames
        self.hands = None
        if (cfg.get("hands") or {}).get("enabled", False):
            self.hands = HandThread(cfg, self.cam.slot, self.inf.results, self.mirror, self.perf.rates["hands"],
                                    perf=self.perf)
        self.hands_results = self.hands.results if self.hands else None
        self._throttled = False

    @property
    def camera_name(self):
        return self.cam.active or self.cfg["camera"]

    @property
    def models(self):
        out = [] if self.inf.error else ["pose"]
        if self.hands and self.hands.ready:
            out.append("hands")
        return out

    def _button(self, state):
        if self.on_button is not None:
            self.on_button(state)

    def errors(self):
        out = list(self.hardware.get("errors", []))
        for src in (self.cam, self.inf, self.button):
            if src.error:
                out.append(src.error)
        if self.inf.warning:
            out.append(self.inf.warning)
        if self.hands and self.hands.error and self.hands.wanted.is_set():
            out.append(self.hands.error)
        return out

    def start(self):
        for t in (self.cam, self.inf, self.enc):
            t.start()
        if self.hands:
            self.hands.start()
        self.button.start()

    def stop(self):
        self.button.stop()
        threads = [t for t in (self.cam, self.inf, self.enc, self.hands) if t is not None]
        for t in threads:
            t.stop()
        for t in threads:
            t.join(timeout=2)

    # game controls
    def set_camera(self, which):
        self.cam.request_switch(which)

    def set_rotation(self, rotation):
        if rotation != self.cam.rotation:
            print(f"[camera] rotation {rotation}")
        self.cam.set_rotation(rotation)

    @property
    def rotation(self):
        return self.cam.rotation

    @property
    def frame_size(self):
        """Display frame (w, h): the transport size, turned like the camera picture."""
        copts = self.cfg["camera_opts"]
        return rotated_size(tuple(copts.get("transport_size") or copts["main_size"]), self.cam.rotation)

    def set_players(self, mode):
        self.analyzer.set_mode(mode)

    def set_difficulty(self, difficulty):
        self.analyzer.set_difficulty(difficulty)

    def set_frames_wanted(self, wanted):
        (self.enc.wanted.set if wanted else self.enc.wanted.clear)()

    def set_hands_wanted(self, wanted):
        if self.hands:
            (self.hands.wanted.set if wanted else self.hands.wanted.clear)()

    def mock_expect(self, name):
        pass  # only the mock performer acts on this

    def tick(self):
        """Called ~1 Hz by the server: thermal throttling + perf log."""
        temp = read_temp_c()
        th = self.cfg["thermal"]
        if temp is not None:
            if temp >= th["throttle_c"] and not self._throttled:
                self._throttled = True
                self.enc.max_fps = th["throttled_frame_fps"]
                print(f"[thermal] {temp:.0f}°C → frames {self.enc.max_fps} fps")
            elif temp < th["throttle_c"] - th["hysteresis_c"] and self._throttled:
                self._throttled = False
                self.enc.max_fps = self.cfg["server"]["frame_fps"]
        self.perf.maybe_log(time.monotonic(), f"camera={self.camera_name} temp={temp}")
        return temp
