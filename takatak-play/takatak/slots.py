"""Latest-result-wins handoff between threads (queue of size 1, never backs up)."""
import threading


class LatestSlot:
    def __init__(self):
        self._cond = threading.Condition()
        self._item = None
        self._seq = 0

    def put(self, item):
        with self._cond:
            self._item = item
            self._seq += 1
            self._cond.notify_all()

    def get(self):
        with self._cond:
            return self._seq, self._item

    def wait_newer(self, seq, timeout=None):
        with self._cond:
            self._cond.wait_for(lambda: self._seq > seq, timeout)
            return self._seq, self._item

    def clear(self):
        with self._cond:
            self._item = None
            self._seq += 1
