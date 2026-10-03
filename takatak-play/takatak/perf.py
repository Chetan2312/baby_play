"""FPS counters for camera / inference / UI, logged to a file every few seconds."""
import os
import time


class Rate:
    def __init__(self):
        self.n = 0
        self.t0 = time.monotonic()
        self.value = 0.0

    def tick(self, n=1):
        self.n += n

    def sample(self, now):
        dt = now - self.t0
        if dt > 0:
            self.value = self.n / dt
        self.n, self.t0 = 0, now
        return self.value


class Mean:
    def __init__(self):
        self.total, self.n, self.value = 0.0, 0, 0.0

    def add(self, x):
        self.total += x
        self.n += 1

    def sample(self):
        if self.n:
            self.value = self.total / self.n
        self.total, self.n = 0.0, 0
        return self.value


class PerfLog:
    def __init__(self, path, every_s):
        self.path = path
        self.every_s = every_s
        self.rates = {"cam": Rate(), "inf": Rate(), "ui": Rate()}
        self.latency_ms = Mean()
        self._next = time.monotonic() + every_s
        os.makedirs(os.path.dirname(path), exist_ok=True)

    def summary(self):
        r = self.rates
        return (f"cam {r['cam'].value:4.1f}  inf {r['inf'].value:4.1f}  "
                f"ui {r['ui'].value:4.1f} fps  lat {self.latency_ms.value:3.0f} ms")

    def maybe_log(self, now, extra=""):
        if now < self._next:
            return
        self._next = now + self.every_s
        for r in self.rates.values():
            r.sample(now)
        self.latency_ms.sample()
        line = f"{time.strftime('%Y-%m-%d %H:%M:%S')}  {self.summary()}  {extra}\n"
        try:
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(line)
        except OSError:
            pass
