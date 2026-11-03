"""YOLOv8-pose inference thread. The profile's accelerator picks the engine:
  hailo8 / hailo10h : HailoPoseEngine, HEF per profile, via picamera2.devices.Hailo like
                      picamera2 examples/hailo/pose_estimation.py
  openvino          : OpenVinoPoseEngine, Ultralytics IR (model.xml) on the Intel iGPU (n150)

The lores frame is letterboxed into the model input (no resize when the lores
width equals the model width, which camera.py arranges), and results come
back in LORES pixel coordinates (isotropic, so gestures use plain distances).
analysis.Analyzer converts them to mirrored, normalised display space for the wire.
"""
import os
import threading
import time

import numpy as np

from .config import path as project_path
from .tracker import Person
from .postprocess import decode_ultralytics_pose, decode_yolov8_pose
from .slots import LatestSlot


class PoseError(Exception):
    pass


class LetterboxEngine:
    """Shared by the engines: lores frame → padded model input (self._buf, HWC uint8),
    and model-input pixels → lores pixels."""

    def _setup(self, cfg, input_hw):
        self.inf = cfg["inference"]
        h, w = input_hw
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

    @staticmethod
    def _to_persons(boxes, scores, kpts, s, ox, oy):
        persons = []
        for b, sc, k in zip(boxes, scores, kpts):
            b = (b - [ox, oy, ox, oy]) / s
            k = k.astype(np.float64)
            k[:, 0] = (k[:, 0] - ox) / s
            k[:, 1] = (k[:, 1] - oy) / s
            persons.append(Person(b, float(sc), k))
        return persons


class HailoPoseEngine(LetterboxEngine):
    warning = None

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
            if "OUT_OF_PHYSICAL_DEVICES" in str(e) or "not enough free devices" in str(e):
                raise PoseError("Hailo AI HAT is busy: another program is using it "
                                "(old vision service? pkill -INT -f takatak_vision.main)") from e
            accel = cfg.get("profile", {}).get("accelerator", "hailo8")
            raise PoseError(f"Hailo could not load the model: {e}. "
                            "Check the AI HAT (hailortcli fw-control identify) and that the HEF "
                            f"is compiled for {accel} (profile '{cfg.get('profile', {}).get('name', '?')}').") from e
        h, w, _ = self.hailo.get_input_shape()
        self._setup(cfg, (h, w))

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
        return self._to_persons(boxes, scores, kpts, s, ox, oy)

    def close(self):
        try:
            self.hailo.close()
        except Exception:  # noqa: BLE001
            pass


def openvino_model_xml(model):
    """cfg["model"] → the IR's .xml: the model folder's model.xml, or an .xml path as given."""
    p = project_path(model)
    return os.path.join(p, "model.xml") if os.path.isdir(p) else p


class OpenVinoPoseEngine(LetterboxEngine):
    """Ultralytics YOLOv8-pose IR on OpenVINO. Input: float 0-1 RGB NCHW; output (1, 56, N).
    A GPU that fails to load falls back to the CPU, with self.warning for the status line."""

    def __init__(self, cfg):
        self.warning = None
        xml = openvino_model_xml(cfg["model"])
        if not os.path.exists(xml):
            raise PoseError(f"Model not found: {cfg['model']}  (run tools/fetch_model.sh, or "
                            "export it with tools/export_pose_openvino.py)")
        try:
            import openvino as ov
        except ImportError as e:
            raise PoseError(f"OpenVINO not installed ({e}): .env/bin/pip install -r vision/requirements-pc.txt") from e
        core = ov.Core()
        cache = self._cache_dir(cfg["inference"].get("cache_dir"))
        if cache:
            core.set_property({"CACHE_DIR": cache})
        device = cfg.get("profile", {}).get("device", "GPU")
        try:
            model = core.read_model(xml)
        except Exception as e:  # noqa: BLE001
            raise PoseError(f"OpenVINO could not read {cfg['model']}: {e}") from e
        try:
            compiled = core.compile_model(model, device, {"PERFORMANCE_HINT": "LATENCY"})
        except Exception as e:  # noqa: BLE001
            if device == "CPU":
                raise PoseError(f"OpenVINO could not load the model on the CPU: {e}") from e
            self.warning = (f"Pose on the CPU (slow): OpenVINO {device} not available ({(str(e).splitlines() or ['?'])[0]}). "
                            "Check intel-opencl-icd: clinfo -l")
            print(f"[pose] {self.warning}")
            device = "CPU"
            compiled = core.compile_model(model, device, {"PERFORMANCE_HINT": "LATENCY"})
        self.device = device
        self.request = compiled.create_infer_request()
        _, c, h, w = compiled.input(0).shape
        if c != 3:
            raise PoseError(f"{cfg['model']}: expected an NCHW RGB input, got {compiled.input(0).shape}")
        self._setup(cfg, (int(h), int(w)))
        self._x = np.empty((1, 3, int(h), int(w)), dtype=np.float32)
        print(f"[pose] OpenVINO {device}: {cfg['model']} input {w}x{h}")

    @staticmethod
    def _cache_dir(p):
        if not p:
            return None
        p = os.path.expanduser(p)
        try:
            os.makedirs(p, exist_ok=True)
        except OSError:
            return None   # no cache: GPU kernels compile on every start (slower start only)
        return p

    def infer(self, lores):
        s, ox, oy = self._letterbox(lores)
        np.multiply(self._buf.transpose(2, 0, 1)[None], 1.0 / 255.0, out=self._x)
        out = self.request.infer({0: self._x})[0]
        try:
            boxes, scores, kpts = decode_ultralytics_pose(
                out, self.inf["min_person_conf"], self.inf["nms_iou"], self.inf["max_people"])
        except ValueError as e:
            raise PoseError(f"model output doesn't look like an Ultralytics yolov8 pose export: {e}") from e
        return self._to_persons(boxes, scores, kpts, s, ox, oy)

    def close(self):
        self.request = None


def PoseEngine(cfg):
    """The pose engine for the profile's accelerator."""
    if cfg.get("profile", {}).get("accelerator") == "openvino":
        return OpenVinoPoseEngine(cfg)
    return HailoPoseEngine(cfg)


class InferenceThread(threading.Thread):
    """camera bundle → pose engine → Analyzer → AnalysisResult in self.results."""

    def __init__(self, cfg, camera_slot, analyzer, perf=None):
        super().__init__(daemon=True, name="inference")
        self.cfg = cfg
        self.camera_slot = camera_slot
        self.analyzer = analyzer
        self.results = LatestSlot()
        self.perf = perf
        self.error = None
        self.warning = None    # engine still runs, e.g. OpenVINO fell back from the GPU to the CPU
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
        self.warning, self.status = engine.warning, ""
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
                size = (bundle.lores.shape[1], bundle.lores.shape[0])
                self.results.put(self.analyzer.process(persons, size, now, bundle.frame_id, bundle.t))
                if self.perf:
                    self.perf.rates["pose"].tick()
                    self.perf.latency_ms.add((now - bundle.t) * 1000)
        except Exception as e:  # noqa: BLE001
            self.error = f"Inference stopped: {e}"
        finally:
            engine.close()
