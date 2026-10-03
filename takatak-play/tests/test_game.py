import numpy as np

from takatak.config import load_config, load_content
from takatak.game import Game, State
from takatak.player import Player
from takatak.poses import NEUTRAL, TARGETS, bbox_of

CFG = load_config()
PROMPTS, LINES = load_content(CFG)


class FakeStats:
    def __init__(self):
        self.rounds, self.sessions, self.ended = [], 0, 0

    def start_session(self, **kw):
        self.sessions += 1

    def record(self, prompt_id, result, tts, mode):
        self.rounds.append((prompt_id, result))

    def end_session(self, **kw):
        self.ended += 1


def player(kp):
    return Player(1, bbox_of(kp), kp, 0.9)


class Sim:
    def __init__(self, **game_over):
        cfg = {**CFG, "game": {**CFG["game"], "seed": 1, **game_over}}
        self.stats = FakeStats()
        self.game = Game(cfg, PROMPTS, LINES, self.stats)
        self.t = 0.0
        self.events = []

    def run(self, seconds, kp_fn, dt=1 / 30, audio_busy=False):
        end = self.t + seconds
        while self.t < end:
            self.t += dt
            kp = kp_fn(self.game) if callable(kp_fn) else kp_fn
            p = None if kp is None else player(kp)
            self.events += self.game.update(self.t, p, True, audio_busy)


def act(game):
    """A perfect player: does whatever is asked, otherwise stands neutral."""
    if game.state in (State.LISTENING, State.HINT):
        return TARGETS[game.prompt["check"]]
    return NEUTRAL


def test_full_session_all_success():
    sim = Sim()
    g = sim.game
    sim.run(0.5, None)
    assert g.state == State.ATTRACT
    while g.state != State.FINISH and sim.t < 120:
        sim.run(1 / 30, act)
    assert sim.stats.sessions == 1 and sim.stats.ended == 1
    assert [r for _, r in sim.stats.rounds] == ["success"] * CFG["game"]["rounds"]
    assert g.successes == CFG["game"]["rounds"]
    assert g.state == State.FINISH


def test_toddler_pool_only_toddler_prompts():
    sim = Sim(difficulty="toddler")
    sim.run(60, act)
    levels = {p["level"] for p in PROMPTS if p["id"] in {pid for pid, _ in sim.stats.rounds}}
    assert levels == {"toddler"}


def test_no_immediate_repeat():
    sim = Sim(difficulty="kid", rounds=30)
    sim.run(200, act)
    ids = [pid for pid, _ in sim.stats.rounds]
    assert all(a != b for a, b in zip(ids, ids[1:]))


def test_timeout_gives_hint_then_moves_on():
    sim = Sim(rounds=1)
    g = sim.game
    sim.run(5, NEUTRAL)  # greet + intro, child just stands
    assert g.state == State.LISTENING
    sim.run(CFG["game"]["prompt_timeout_s"] + 0.2, NEUTRAL)
    assert g.state == State.HINT
    kinds = [(e.kind, e.clips) for e in sim.events]
    assert ("sfx", ["try_again"]) in kinds
    sim.run(CFG["game"]["prompt_timeout_s"] + 0.2, NEUTRAL)
    assert sim.stats.rounds == [(g.prompt["id"], "timeout")]
    assert g.state == State.FINISH


def test_timeout_paused_while_audio_plays():
    sim = Sim(rounds=1)
    sim.run(5, NEUTRAL)
    sim.run(30, NEUTRAL, audio_busy=True)
    assert sim.game.state == State.LISTENING


def test_hold_frames_required():
    sim = Sim(rounds=1)
    g = sim.game
    sim.run(5, NEUTRAL)
    target = TARGETS[g.prompt["check"]]
    for _ in range(CFG["game"]["hold_frames"] - 1):
        sim.run(1 / 30, target)
    assert g.state == State.LISTENING
    sim.run(1 / 30, target)
    assert g.state == State.CELEBRATE


def test_requires_neutral_or_gap_before_arming():
    sim = Sim(rounds=2, rearm_gap_s=100)
    g = sim.game
    sim.run(5, NEUTRAL)
    sim.run(1, lambda gm: TARGETS[gm.prompt["check"]])
    assert g.state == State.CELEBRATE
    first = g.prompt["check"]
    # Child keeps the old pose through celebration into round 2
    sim.run(CFG["game"]["celebrate_s"] + CFG["game"]["intro_arm_s"] + 0.5, TARGETS[first])
    assert g.state == State.LISTENING and not g.armed
    sim.run(0.2, NEUTRAL)
    assert g.armed


def test_absent_pauses_and_resumes():
    sim = Sim(rounds=3)
    g = sim.game
    sim.run(5, NEUTRAL)
    pid = g.prompt["id"]
    sim.run(CFG["game"]["absent_pause_s"] + 0.2, None)
    assert g.state == State.PAUSED
    assert any(e.clips == ["come_back"] and e.interrupt for e in sim.events)
    sim.run(1.5, NEUTRAL)
    assert g.state in (State.ROUND_INTRO, State.LISTENING) and g.prompt["id"] == pid


def test_abandon_returns_to_attract():
    sim = Sim()
    sim.run(5, NEUTRAL)
    sim.run(CFG["game"]["absent_pause_s"] + CFG["game"]["absent_abandon_s"] + 1, None)
    assert sim.game.state == State.ATTRACT
    assert sim.stats.ended == 1


def test_skip_and_language_modes():
    sim = Sim(rounds=2)
    g = sim.game
    assert g.skip(0.0)  # space in attract starts a session
    assert g.state == State.GREETING
    g.skip(0.1)
    assert g.state == State.ROUND_INTRO and g.round_idx == 1
    g.skip(0.2)
    assert sim.stats.rounds[-1][1] == "skipped"
    assert g.languages_for_round() == CFG["game"]["languages"]
    assert g.cycle_language_mode() == "single"
    assert g.languages_for_round() == [CFG["game"]["single_language"]]
    assert g.cycle_language_mode() == "rotate"
    assert len(g.languages_for_round()) == 1
    assert g.cycle_language_mode() == "all"
