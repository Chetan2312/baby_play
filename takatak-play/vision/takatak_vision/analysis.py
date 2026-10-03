"""Per-frame analysis: persons → tracked players → wire pose message + gesture events.

Shared by the real service (pose.InferenceThread) and tools/mock_server.py,
so the mock exercises the same tracking and gesture logic.

Gesture events per active player and check (plus "neutral"):
  start  after `start_frames` consecutive true frames
  held   after `hold_frames` consecutive true frames (sent once)
  end    after more than `miss_frames` false frames following a start
"""
import threading
from dataclasses import dataclass, field

from . import gestures as G
from . import protocol as P
from .tracker import SmootherBank, Tracker


@dataclass
class AnalysisResult:
    frame_id: int
    t_capture: float
    pose_msg: dict
    events: list = field(default_factory=list)
    active_ids: list = field(default_factory=list)
    no_player_s: float = 0.0


class _GestureState:
    __slots__ = ("count", "misses", "started", "held", "score")

    def __init__(self):
        self.count = self.misses = 0
        self.started = self.held = False
        self.score = 0.0


class Analyzer:
    def __init__(self, cfg, frame_size=(640, 360)):
        self.cfg = cfg
        self.mirror = cfg["display"]["mirror"]
        self.min_conf = cfg["inference"]["min_kp_conf"]
        self.ev_cfg = cfg["gesture_events"]
        self.tracker = Tracker(cfg["tracker"], frame_size, self.mirror)
        self.smoothers = SmootherBank(cfg["smoothing"], self.min_conf)
        self.difficulty = cfg["gestures"]["default_difficulty"]
        self.frame_size = frame_size
        self._states = {}           # (player_id, name) -> _GestureState
        self._last_active = None
        self._lock = threading.Lock()

    # ---- settings from the game (any thread) ----
    def set_mode(self, mode):
        with self._lock:
            self.tracker.set_mode(mode)

    def set_difficulty(self, difficulty):
        with self._lock:
            self.difficulty = difficulty

    @property
    def params(self):
        return self.cfg["gestures"][self.difficulty]

    # ---- per frame ----
    def process(self, persons, frame_size, now, frame_id, t_capture=None):
        with self._lock:
            if frame_size != self.frame_size:
                self.frame_size = frame_size
                self.tracker.frame_size = frame_size
            tracks = self.tracker.update(persons, now)
            self.smoothers.update(tracks, now)
            events = []
            active = [t for t in tracks if t.active]
            for t in active:
                events += self._gestures(t, now)
            events += self._forget_states({t.id for t in active})
            if active:
                self._last_active = now
            no_player_s = 0.0 if active else (
                now - self._last_active if self._last_active is not None else float("inf"))
            fw, fh = frame_size
            people = []
            for t in tracks:
                S = G.body_scale(t.kp, t.bbox, self.params, self.min_conf)
                people.append(P.person_to_wire(t.id, t.active, t.score, t.bbox, t.kp, S,
                                               fw, fh, self.mirror))
            return AnalysisResult(frame_id, now if t_capture is None else t_capture,
                                  P.pose(frame_id, people), events,
                                  [t.id for t in active], no_player_s)

    def _gestures(self, t, now):
        p = self.params
        results = G.evaluate_all(t.kp, t.bbox, p, self.min_conf)
        results["neutral"] = (G.is_neutral(t.kp, t.bbox, p, self.min_conf), 1.0)
        start_n = self.ev_cfg["start_frames"]
        hold_n = self.ev_cfg["hold_frames"]
        miss_n = self.ev_cfg["miss_frames"]
        out = []
        for name, (ok, score) in results.items():
            st = self._states.setdefault((t.id, name), _GestureState())
            st.score = score
            if ok:
                st.count += 1
                st.misses = 0
                if not st.started and st.count >= start_n:
                    st.started = True
                    out.append(P.gesture(t.id, name, "start", score))
                if st.started and not st.held and st.count >= hold_n:
                    st.held = True
                    out.append(P.gesture(t.id, name, "held", score))
            else:
                st.misses += 1
                if st.misses > miss_n:
                    if st.started:
                        out.append(P.gesture(t.id, name, "end", score))
                    st.count = 0
                    st.started = st.held = False
        return out

    def _forget_states(self, active_ids):
        """Player no longer active → close any open gestures so the game never sticks."""
        out = []
        for key in [k for k in self._states if k[0] not in active_ids]:
            st = self._states.pop(key)
            if st.started:
                out.append(P.gesture(key[0], key[1], "end", 0.0))
        return out
