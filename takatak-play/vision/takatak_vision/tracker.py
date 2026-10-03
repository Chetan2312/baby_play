"""Multi-person tracking with stable IDs, active-player selection, keypoint smoothing.

Modes:
  single: one active player (largest or most central), sticky until lost.
  duo:    two active players, one per half of the play zone in DISPLAY space
          (left mat / right mat), so siblings can stand side by side.
"""
import itertools
from dataclasses import dataclass, field

import numpy as np

from .gestures import FACE


@dataclass(eq=False)
class Person:
    bbox: np.ndarray      # x1, y1, x2, y2 (lores frame pixels)
    score: float
    kp: np.ndarray        # (17, 3) x, y, conf


@dataclass(eq=False)
class Track:
    id: int
    bbox: np.ndarray
    kp: np.ndarray
    score: float
    last_seen: float
    visible: bool = True
    active: bool = False
    slot: int = -1        # active slot index (0 = single/left, 1 = right)
    extra: dict = field(default_factory=dict)


def _center(b):
    return np.array([(b[0] + b[2]) / 2, (b[1] + b[3]) / 2])


def _area(b):
    return max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1])


class Tracker:
    def __init__(self, tcfg, frame_size=(640, 360), mirror=True):
        self.select = tcfg["select"]               # largest | center
        self.lost_grace_s = tcfg["lost_grace_s"]
        self.max_jump = tcfg["max_jump"]
        self.mode = tcfg.get("mode", "single")
        self.frame_size = frame_size
        self.mirror = mirror
        self._ids = itertools.count(1)
        self.tracks = []
        self.active = {}  # slot -> track id

    def reset(self):
        self.tracks = []
        self.active = {}

    def set_mode(self, mode):
        if mode != self.mode:
            self.mode = mode
            self.active = {}

    def _display_x(self, b):
        x = _center(b)[0] / self.frame_size[0]
        return 1.0 - x if self.mirror else x

    def _match(self, persons, now):
        persons = list(persons)
        for t in self.tracks:
            t.visible = False
        alive = []
        for t in sorted(self.tracks, key=lambda t: -t.last_seen):
            if now - t.last_seen > self.lost_grace_s:
                continue
            alive.append(t)
            if not persons:
                continue
            c = _center(t.bbox)
            h = max(1.0, t.bbox[3] - t.bbox[1])
            best = min(persons, key=lambda p: np.hypot(*(_center(p.bbox) - c)))
            if np.hypot(*(_center(best.bbox) - c)) <= self.max_jump * h:
                persons.remove(best)
                t.bbox, t.kp, t.score, t.last_seen, t.visible = best.bbox, best.kp, best.score, now, True
        for p in persons:
            alive.append(Track(next(self._ids), p.bbox, p.kp, p.score, now))
        self.tracks = alive

    def _pick(self, candidates):
        if not candidates:
            return None
        if self.select == "center":
            fc = np.array(self.frame_size) / 2
            return min(candidates, key=lambda t: np.hypot(*(_center(t.bbox) - fc)))
        return max(candidates, key=lambda t: _area(t.bbox))

    def _assign(self):
        by_id = {t.id: t for t in self.tracks}
        slots = [0] if self.mode == "single" else [0, 1]
        for s in list(self.active):
            if s not in slots or self.active[s] not in by_id:
                del self.active[s]      # lost beyond grace (or mode changed)
        taken = set(self.active.values())
        for s in slots:
            if s in self.active:
                continue
            cands = [t for t in self.tracks if t.visible and t.id not in taken]
            if self.mode == "duo":
                cands = [t for t in cands if (self._display_x(t.bbox) < 0.5) == (s == 0)]
            pick = self._pick(cands)
            if pick is not None:
                self.active[s] = pick.id
                taken.add(pick.id)
        for t in self.tracks:
            t.active, t.slot = False, -1
        for s, tid in self.active.items():
            by_id[tid].active, by_id[tid].slot = True, s

    def update(self, persons, now):
        """→ visible tracks (active ones first, by slot)."""
        self._match(persons, now)
        self._assign()
        vis = [t for t in self.tracks if t.visible]
        return sorted(vis, key=lambda t: (not t.active, t.slot, t.id))

    @property
    def active_visible(self):
        return [t for t in self.tracks if t.active and t.visible]


class KeypointSmoother:
    """EMA on keypoints + short memory of face points hidden by a hand."""

    def __init__(self, scfg, min_conf):
        self.alpha = scfg["ema_alpha"]
        self.face_memory_s = scfg["face_memory_s"]
        self.min_conf = min_conf
        self.prev = None
        self.last_good = {}

    def update(self, kp, now):
        kp = np.asarray(kp, dtype=np.float64)
        out = kp.copy()
        for i in range(len(kp)):
            if kp[i, 2] >= self.min_conf:
                if self.prev is not None and self.prev[i, 2] >= self.min_conf:
                    out[i, :2] = self.alpha * kp[i, :2] + (1 - self.alpha) * self.prev[i, :2]
                self.last_good[i] = (out[i].copy(), now)
            elif i in FACE and i in self.last_good:
                saved, t = self.last_good[i]
                if now - t <= self.face_memory_s:
                    out[i] = saved
        self.prev = out
        return out


class SmootherBank:
    """One smoother per track id; forgets ids that disappear."""

    def __init__(self, scfg, min_conf):
        self.scfg, self.min_conf = scfg, min_conf
        self.by_id = {}

    def update(self, tracks, now):
        ids = {t.id for t in tracks}
        for tid in list(self.by_id):
            if tid not in ids:
                del self.by_id[tid]
        for t in tracks:
            sm = self.by_id.setdefault(t.id, KeypointSmoother(self.scfg, self.min_conf))
            t.kp = sm.update(t.kp, now)
