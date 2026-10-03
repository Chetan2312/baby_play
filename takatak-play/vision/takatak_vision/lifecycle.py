"""Clean, guaranteed shutdown for the pygame apps.

- Ctrl+C / SIGTERM / SIGHUP set a flag (checked every frame) instead of raising
  KeyboardInterrupt somewhere inside pygame or a lock. A second Ctrl+C exits
  immediately.
- shutdown() runs each cleanup step guarded, under a watchdog: picamera2 and
  Hailo can leave non-daemon threads or block in close(), which would keep
  the process (and the fullscreen window) alive. When the watchdog fires, or
  when cleanup finishes, the process ends via os._exit.
"""
import os
import signal
import sys
import threading


class Shutdown:
    def __init__(self, watchdog_s=5.0):
        self.requested = False
        self.watchdog_s = watchdog_s
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            try:
                signal.signal(sig, self._on_signal)
            except (ValueError, OSError):
                pass

    def _on_signal(self, signum, _frame):
        if self.requested:
            print("\n[exit] forced", flush=True)
            os._exit(130)
        print(f"\n[exit] {signal.Signals(signum).name} received, shutting down…", flush=True)
        self.requested = True

    def request(self):
        self.requested = True

    def shutdown(self, *steps, code=0):
        """Run cleanup callables in order, then hard-exit the process."""
        def _watchdog():
            print(f"[exit] cleanup stuck > {self.watchdog_s:.0f}s, forcing exit", flush=True)
            os._exit(code)

        timer = threading.Timer(self.watchdog_s, _watchdog)
        timer.daemon = True
        timer.start()
        for step in steps:
            try:
                step()
            except Exception as e:  # noqa: BLE001 - keep going, we're exiting
                print(f"[exit] cleanup step failed: {e}", flush=True)
        sys.stdout.flush()
        sys.stderr.flush()
        os._exit(code)
