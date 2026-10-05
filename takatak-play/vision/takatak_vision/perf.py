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
    def __init__(self, path, every_s, names=("cam", "pose", "frames")):
        self.path = path
        self.every_s = every_s
        self.rates = {n: Rate() for n in names}
        self.latency_ms = Mean()          # pose: capture → result
        self.means = {"hand_ms": Mean(), "hand_latency_ms": Mean()}   # hand model per hand · capture → hands
        self._next = time.monotonic() + every_s
        os.makedirs(os.path.dirname(path), exist_ok=True)

    def fps(self):
        return {n: r.value for n, r in self.rates.items()}

    def latencies(self):
        """→ {"pose": ms, "hand_ms": ms, "hand_latency_ms": ms} (last sampled values)."""
        return {"pose": self.latency_ms.value, **{k: m.value for k, m in self.means.items()}}

    def summary(self):
        rates = "  ".join(f"{n} {r.value:4.1f}" for n, r in self.rates.items())
        hands = "  ".join(f"{k} {m.value:3.0f}" for k, m in self.means.items() if m.value)
        return f"{rates} fps  lat {self.latency_ms.value:3.0f} ms" + (f"  {hands}" if hands else "")

    def maybe_log(self, now, extra=""):
        if now < self._next:
            return
        self._next = now + self.every_s
        for r in self.rates.values():
            r.sample(now)
        self.latency_ms.sample()
        for m in self.means.values():
            m.sample()
        line = f"{time.strftime('%Y-%m-%d %H:%M:%S')}  {self.summary()}  {extra}\n"
        try:
            with open(self.path, "a", encoding="utf-8") as f:
                f.write(line)
        except OSError:
            pass
