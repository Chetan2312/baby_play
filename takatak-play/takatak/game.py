"""Game state machine. No pygame/hardware here, so it is unit-testable.

update() is called every UI frame with the active player (or None). `fresh`
is True only when a new inference result arrived, so hold_frames counts
real pose frames. It returns Events for the audio layer.
"""
import random
from dataclasses import dataclass, field
from enum import Enum

from . import gestures as G


class State(str, Enum):
    ATTRACT = "attract"
    GREETING = "greeting"
    ROUND_INTRO = "round_intro"
    LISTENING = "listening"
    HINT = "hint"
    CELEBRATE = "celebrate"
    PAUSED = "paused"
    FINISH = "finish"


ACTIVE = (State.ROUND_INTRO, State.LISTENING, State.HINT)
LANGUAGE_MODES = ("all", "single", "rotate")


@dataclass
class Event:
    kind: str                       # "say" | "sfx"
    clips: list = field(default_factory=list)   # clip ids, spoken per language
    langs: list = field(default_factory=list)
    interrupt: bool = False         # stop current speech first (default: queue after it)


class Game:
    def __init__(self, cfg, prompts, lines, stats=None, camera_name="?"):
        self.g = cfg["game"]
        self.gesture_cfg = cfg["gestures"]
        self.min_conf = cfg["inference"]["min_kp_conf"]
        self.prompts_all = prompts
        self.lines = lines
        self.stats = stats
        self.camera_name = camera_name
        self.rng = random.Random(self.g.get("seed"))
        self.language_mode = self.g["language_mode"]
        self.difficulty = self.g["difficulty"]
        self._reset_session()
        self.state = State.ATTRACT
        self.state_since = 0.0
        self._last_now = None
        self.last_seen = None
        self.present_since = None

    # ---- public controls -------------------------------------------------
    @property
    def params(self):
        return self.gesture_cfg[self.difficulty]

    def languages_for_round(self, round_idx=None):
        langs = list(self.g["languages"])
        if self.language_mode == "single":
            return [self.g["single_language"]]
        if self.language_mode == "rotate":
            i = (self.round_idx if round_idx is None else round_idx) - 1
            return [langs[max(i, 0) % len(langs)]]
        return langs

    def cycle_language_mode(self):
        i = LANGUAGE_MODES.index(self.language_mode)
        self.language_mode = LANGUAGE_MODES[(i + 1) % len(LANGUAGE_MODES)]
        return self.language_mode

    def skip(self, now):
        """Tester Space key."""
        if self.state == State.ATTRACT:
            return self._start_session(now)
        if self.state in ACTIVE or self.state == State.PAUSED:
            self._record("skipped", None)
            return self._next_round(now)
        if self.state in (State.GREETING, State.CELEBRATE):
            return self._next_round(now)
        if self.state == State.FINISH:
            self._goto(State.ATTRACT, now)
        return []

    # ---- main tick -------------------------------------------------------
    def update(self, now, player, fresh, audio_busy):
        dt = 0.0 if self._last_now is None else min(max(now - self._last_now, 0.0), 0.5)
        self._last_now = now
        if player is not None:
            self.last_seen = now
            if self.present_since is None:
                self.present_since = now
        else:
            self.present_since = None
        present_for = 0.0 if self.present_since is None else now - self.present_since
        absent_for = float("inf") if self.last_seen is None else now - self.last_seen
        elapsed = now - self.state_since
        g = self.g
        s = self.state

        if s == State.ATTRACT:
            if present_for >= g["attract_detect_s"]:
                return self._start_session(now)
            return []

        if s == State.GREETING:
            if elapsed >= g["greet_s"] and not audio_busy:
                return self._next_round(now)
            return []

        if s in ACTIVE and absent_for >= g["absent_pause_s"]:
            self._goto(State.PAUSED, now)
            ev = self._say(["come_back"], all_langs=True)
            ev.interrupt = True
            return [ev]

        if s == State.ROUND_INTRO:
            if elapsed >= g["intro_arm_s"]:
                self._goto(State.LISTENING, now)
                self.listen_started = now
            return []

        if s in (State.LISTENING, State.HINT):
            if fresh and player is not None:
                ev = self._check(now, player)
                if ev is not None:
                    return ev
            if not audio_busy:
                self.listen_time += dt
            if self.listen_time >= g["prompt_timeout_s"]:
                if self.attempt <= g["hint_attempts"]:
                    self.attempt += 1
                    self.listen_time = 0.0
                    self._goto(State.HINT, now)
                    return [Event("sfx", ["try_again"]),
                            self._say(["hint", self.prompt["id"]])]
                self._record("timeout", None)
                return [self._say(["next"])] + self._next_round(now)
            return []

        if s == State.CELEBRATE:
            if elapsed >= g["celebrate_s"]:
                return self._next_round(now)
            return []

        if s == State.PAUSED:
            if present_for >= g["resume_detect_s"]:
                return self._intro(now)
            if absent_for >= g["absent_abandon_s"]:
                self._end_session()
                self._goto(State.ATTRACT, now)
            return []

        if s == State.FINISH:
            if elapsed >= g["finish_s"]:
                self._goto(State.ATTRACT, now)
            return []
        return []

    # ---- internals -------------------------------------------------------
    def _reset_session(self):
        self.round_idx = 0
        self.successes = 0
        self.prompt = None
        self.attempt = 1
        self.hold = 0
        self.misses = 0
        self.armed = False
        self.listen_time = 0.0
        self.listen_started = 0.0
        self.prompt_said_at = 0.0
        self.last_word = None
        self.last_check = (False, 0.0)
        self.round_results = []
        self._bag = []
        self._last_prompt_id = None

    def _goto(self, state, now):
        self.state = state
        self.state_since = now

    def _say(self, clips, all_langs=False):
        langs = list(self.g["languages"]) if all_langs else self.languages_for_round()
        return Event("say", list(clips), langs)

    def _pool(self):
        if self.difficulty == "toddler":
            return [p for p in self.prompts_all if p["level"] == "toddler"]
        return list(self.prompts_all)

    def _draw_prompt(self):
        if not self._bag:
            self._bag = self._pool()
            self.rng.shuffle(self._bag)
            if len(self._bag) > 1 and self._bag[-1]["id"] == self._last_prompt_id:
                self._bag[0], self._bag[-1] = self._bag[-1], self._bag[0]
        p = self._bag.pop()
        self._last_prompt_id = p["id"]
        return p

    def _start_session(self, now):
        self._reset_session()
        if self.stats:
            self.stats.start_session(camera=self.camera_name, difficulty=self.difficulty,
                                     languages=self.g["languages"],
                                     language_mode=self.language_mode,
                                     rounds_planned=self.g["rounds"])
        self._goto(State.GREETING, now)
        return [Event("sfx", ["start"]), self._say(["greeting"], all_langs=True)]

    def _next_round(self, now):
        if self.round_idx >= self.g["rounds"]:
            self._end_session()
            self._goto(State.FINISH, now)
            return [Event("sfx", ["success"]), self._say(["finish"], all_langs=True)]
        self.round_idx += 1
        self.prompt = self._draw_prompt()
        self.attempt = 1
        return self._intro(now)

    def _intro(self, now):
        self.hold = self.misses = 0
        self.armed = False
        self.listen_time = 0.0
        self.prompt_said_at = now
        self._goto(State.ROUND_INTRO, now)
        return [self._say([self.prompt["id"]])]

    def _check(self, now, player):
        p = self.params
        if not self.armed:
            neutral = G.is_neutral(player.kp, player.bbox, p, self.min_conf)
            if neutral or now - self.listen_started >= self.g["rearm_gap_s"]:
                self.armed = True
            else:
                return None
        ok, score = G.evaluate(self.prompt["check"], player.kp, player.bbox, p, self.min_conf)
        self.last_check = (ok, score)
        if ok:
            self.hold += 1
            self.misses = 0
        else:
            self.misses += 1
            if self.misses > self.g["hold_miss_frames"]:
                self.hold = 0
        if self.hold >= self.g["hold_frames"]:
            self.successes += 1
            self.last_word = self.prompt["word"]
            self._record("success", now - self.prompt_said_at)
            self.armed = False
            self._goto(State.CELEBRATE, now)
            return [Event("sfx", ["success"])]
        return None

    def _record(self, result, tts):
        self.round_results.append(result)
        if self.stats:
            self.stats.record(self.prompt["id"] if self.prompt else None, result, tts,
                              self.language_mode)

    def _end_session(self):
        if self.stats:
            self.stats.end_session(successes=self.successes, rounds_played=self.round_idx)

    @property
    def hold_fraction(self):
        return min(1.0, self.hold / max(1, self.g["hold_frames"]))
