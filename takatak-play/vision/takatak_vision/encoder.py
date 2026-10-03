"""Display frames → mirrored JPEG for the game (latest-wins, only while someone subscribes)."""
import threading
import time

import numpy as np

from .slots import LatestSlot

try:
    import simplejpeg
except ImportError:  # dev machines; the Pi gets python3-simplejpeg with picamera2
    simplejpeg = None


def encode_jpeg(rgbx, quality):
    """rgbx: (H, W, 3|4) uint8 in R,G,B(,X) order."""
    rgbx = np.ascontiguousarray(rgbx)
    if simplejpeg is not None:
        cs = "RGBX" if rgbx.shape[2] == 4 else "RGB"
        return simplejpeg.encode_jpeg(rgbx, quality=quality, colorspace=cs, fastdct=True)
    try:
        import cv2
        bgr = cv2.cvtColor(rgbx, cv2.COLOR_RGBA2BGR if rgbx.shape[2] == 4 else cv2.COLOR_RGB2BGR)
        ok, buf = cv2.imencode(".jpg", bgr, [cv2.IMWRITE_JPEG_QUALITY, quality])
        if ok:
            return buf.tobytes()
    except ImportError:
        pass
    import io

    from PIL import Image
    out = io.BytesIO()
    Image.fromarray(rgbx[..., :3]).save(out, "JPEG", quality=quality)
    return out.getvalue()


class FrameEncoder(threading.Thread):
    def __init__(self, camera_slot, quality, max_fps, mirror, rate=None):
        super().__init__(daemon=True, name="encoder")
        self.camera_slot = camera_slot
        self.frames = LatestSlot()      # (frame_id, jpeg bytes)
        self.quality = quality
        self.max_fps = max_fps
        self.mirror = mirror
        self.rate = rate
        self.wanted = threading.Event()  # set while at least one client wants frames
        self._quit = threading.Event()

    def stop(self):
        self._quit.set()
        self.wanted.set()

    def run(self):
        seq, last = 0, 0.0
        while not self._quit.is_set():
            if not self.wanted.wait(0.5):
                continue
            seq, bundle = self.camera_slot.wait_newer(seq, timeout=0.5)
            if bundle is None:
                continue
            period = 1.0 / max(1.0, self.max_fps)
            now = time.monotonic()
            if now - last < period:
                time.sleep(period - (now - last))
            last = time.monotonic()
            img = bundle.main[:, ::-1] if self.mirror else bundle.main
            try:
                jpg = encode_jpeg(img, self.quality)
            except Exception as e:  # noqa: BLE001
                print(f"[encoder] {e}")
                continue
            self.frames.put((bundle.frame_id, jpg))
            if self.rate:
                self.rate.tick()
