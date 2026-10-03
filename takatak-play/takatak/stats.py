"""Session stats → JSON. Stores only timestamps, prompt ids and outcomes. Never images."""
import json
import os
import time


class StatsLogger:
    def __init__(self, stats_dir):
        self.dir = stats_dir
        os.makedirs(stats_dir, exist_ok=True)
        self.session = None
        self.path = None

    def start_session(self, **meta):
        stamp = time.strftime("%Y%m%d_%H%M%S")
        self.path = os.path.join(self.dir, f"session_{stamp}.json")
        self.session = {"started": time.strftime("%Y-%m-%dT%H:%M:%S"), **meta, "rounds": []}
        self._write()

    def record(self, prompt_id, result, time_to_success, language_mode):
        if self.session is None:
            return
        self.session["rounds"].append({
            "t": time.strftime("%Y-%m-%dT%H:%M:%S"),
            "prompt": prompt_id,
            "result": result,  # success | timeout | skipped
            "time_to_success_s": None if time_to_success is None else round(time_to_success, 2),
            "language_mode": language_mode,
        })
        self._write()

    def end_session(self, **summary):
        if self.session is None:
            return
        self.session["ended"] = time.strftime("%Y-%m-%dT%H:%M:%S")
        self.session.update(summary)
        self._write()
        self.session = None

    def _write(self):
        tmp = self.path + ".tmp"
        try:
            with open(tmp, "w", encoding="utf-8") as f:
                json.dump(self.session, f, ensure_ascii=False, indent=1)
            os.replace(tmp, self.path)
        except OSError:
            pass
