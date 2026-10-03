"""Active player selection, simple tracking and keypoint smoothing.

Returns a LIST of players so Demo 2 (two kids racing) can reuse this.
"""
import itertools
from dataclasses import dataclass

import numpy as np

from .gestures import FACE


@dataclass(eq=False)
class Person:
    bbox: np.ndarray      # x1, y1, x2, y2 (frame pixels)
    score: float
    kp: np.ndarray        # (17, 3) x, y, conf


@dataclass
class Player:
    track_id: int
    bbox: np.ndarray
    kp: np.ndarray
    score: float


def _center(b):
    return np.array([(b[0] + b[2]) / 2, (b[1] + b[3]) / 2])


def _area(b):
    return max(0.0, b[2] - b[0]) * max(0.0, b[3] - b[1])


class PlayerTracker:
    def __init__(self, pcfg, frame_size=(640, 360)):
        self.mode = pcfg["mode"]
        self.lost_grace_s = pcfg["lost_grace_s"]
        self.max_jump = pcfg["max_jump"]
        self.max_players = pcfg.get("max_players", 1)
        self.frame_size = frame_size
        self._ids = itertools.count(1)
        self.tracks = []  # dicts: id, bbox, last_seen

    def reset(self):
        self.tracks = []

    def _pick(self, persons):
        if self.mode == "center":
            fc = np.array(self.frame_size) / 2
            return min(persons, key=lambda p: np.hypot(*(_center(p.bbox) - fc)))
        return max(persons, key=lambda p: _area(p.bbox))

    def update(self, persons, now):
        persons = list(persons)
        players = []
        alive = []
        for t in self.tracks:
            if now - t["last_seen"] > self.lost_grace_s:
                continue  # lost: a new detection gets a new identity
            match = None
            if persons:
                c = _center(t["bbox"])
                h = max(1.0, t["bbox"][3] - t["bbox"][1])
                best = min(persons, key=lambda p: np.hypot(*(_center(p.bbox) - c)))
                if np.hypot(*(_center(best.bbox) - c)) <= self.max_jump * h:
                    match = best
            if match is not None:
                persons.remove(match)
                t["bbox"], t["last_seen"] = match.bbox, now
                players.append(Player(t["id"], match.bbox, match.kp, match.score))
                alive.append(t)
            else:
                alive.append(t)  # keep identity through a short dropout
        self.tracks = alive
        while persons and len(self.tracks) < self.max_players:
            p = self._pick(persons)
            persons.remove(p)
            t = {"id": next(self._ids), "bbox": p.bbox, "last_seen": now}
            self.tracks.append(t)
            players.append(Player(t["id"], p.bbox, p.kp, p.score))
        order = {t["id"]: i for i, t in enumerate(self.tracks)}
        return sorted(players, key=lambda p: order[p.track_id])


class KeypointSmoother:
    """EMA on keypoints + short memory of face points hidden by a hand."""

    def __init__(self, scfg, min_conf):
        self.alpha = scfg["ema_alpha"]
        self.face_memory_s = scfg["face_memory_s"]
        self.min_conf = min_conf
        self.reset()

    def reset(self):
        self.track_id = None
        self.prev = None
        self.last_good = {}

    def update(self, kp, now, track_id=None):
        if track_id != self.track_id:
            self.reset()
            self.track_id = track_id
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
