"""Real hardware source: camera → pose → analysis, and camera → JPEG.

A "source" is what server.py talks to. tools/mock_server.py provides another
one with the same attributes, so the server code is identical in both.
"""
import time

from .analysis import Analyzer
from .button import GpioButton
from .camera import CameraThread, VideoThread, lores_size_for
from .config import path
from .encoder import FrameEncoder
from .perf import PerfLog
from .pose import InferenceThread


def read_temp_c():
    try:
        with open("/sys/class/thermal/thermal_zone0/temp") as f:
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
        self.perf = PerfLog(path(cfg["paths"]["perf_log"]), cfg["perf"]["log_every_s"])
        main_size = tuple(cfg["camera_opts"]["main_size"])
        self.analyzer = Analyzer(cfg, lores_size_for(main_size, cfg["inference"]["input_size"]))
        if video:
            self.cam = VideoThread(cfg, video, self.perf.rates["cam"])
        else:
            self.cam = CameraThread(cfg, self.perf.rates["cam"])
        self.inf = InferenceThread(cfg, self.cam.slot, self.analyzer, self.perf)
        self.enc = FrameEncoder(self.cam.slot, scfg["jpeg_quality"], scfg["frame_fps"],
                                self.mirror, self.perf.rates["frames"])
        self.results = self.inf.results
        self.frames = self.enc.frames
        self._throttled = False

    @property
    def camera_name(self):
        return self.cam.active or self.cfg["camera"]

    @property
    def models(self):
        return [] if self.inf.error else ["pose"]

    def _button(self, state):
        if self.on_button is not None:
            self.on_button(state)

    def errors(self):
        out = list(self.hardware.get("errors", []))
        for src in (self.cam, self.inf, self.button):
            if src.error:
                out.append(src.error)
        return out

    def start(self):
        for t in (self.cam, self.inf, self.enc):
            t.start()
        self.button.start()

    def stop(self):
        self.button.stop()
        for t in (self.cam, self.inf, self.enc):
            t.stop()
        for t in (self.cam, self.inf, self.enc):
            t.join(timeout=2)

    # game controls
    def set_camera(self, which):
        self.cam.request_switch(which)

    def set_players(self, mode):
        self.analyzer.set_mode(mode)

    def set_difficulty(self, difficulty):
        self.analyzer.set_difficulty(difficulty)

    def set_frames_wanted(self, wanted):
        (self.enc.wanted.set if wanted else self.enc.wanted.clear)()

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
