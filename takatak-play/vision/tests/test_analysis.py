import json

from takatak_vision import protocol as P
from takatak_vision.analysis import Analyzer
from takatak_vision.config import load_config
from takatak_vision.poses import NEUTRAL, TARGETS, bbox_of
from takatak_vision.tracker import Person

CFG = load_config()
EV = CFG["gesture_events"]


def feed(an, kp, n, t0=0.0, dt=1 / 30):
    events, res = [], None
    for i in range(n):
        persons = [] if kp is None else [Person(bbox_of(kp), 0.9, kp)]
        res = an.process(persons, (640, 360), t0 + i * dt, i)
        events += res.events
    return events, res


def names(events, state=None):
    return [(e["name"], e["state"]) for e in events if state is None or e["state"] == state]


def test_start_held_end_sequence():
    an = Analyzer(CFG)
    feed(an, NEUTRAL, 3)
    ev, _ = feed(an, TARGETS["touch_nose"], EV["hold_frames"] + 2, t0=1.0)
    seq = [s for n, s in names(ev) if n == "touch_nose"]
    assert seq == ["start", "held"]
    starts = [i for i, e in enumerate(ev) if e["name"] == "touch_nose"]
    assert ev[starts[0]]["player"] == ev[starts[1]]["player"]
    ev, _ = feed(an, NEUTRAL, EV["miss_frames"] + 2, t0=2.0)
    assert ("touch_nose", "end") in names(ev)


def test_neutral_is_a_gesture():
    an = Analyzer(CFG)
    ev, _ = feed(an, NEUTRAL, EV["hold_frames"] + 1)
    assert ("neutral", "held") in names(ev)


def test_short_blip_does_not_hold():
    an = Analyzer(CFG)
    feed(an, NEUTRAL, 3)
    ev, _ = feed(an, TARGETS["clap"], EV["hold_frames"] - 2, t0=1.0)
    assert ("clap", "held") not in names(ev)


def test_player_leaving_closes_open_gestures_and_reports_no_player():
    an = Analyzer(CFG)
    feed(an, TARGETS["hands_up"], EV["hold_frames"] + 1)
    ev, res = feed(an, None, 40, t0=1.0)
    assert ("hands_up", "end") in names(ev)
    assert res.no_player_s > 1.0 and res.active_ids == []


def test_pose_message_is_wire_ready():
    an = Analyzer(CFG)
    _, res = feed(an, NEUTRAL, 2)
    m = json.loads(P.dumps(res.pose_msg))
    assert m["t"] == "pose" and len(m["people"]) == 1
    p = m["people"][0]
    assert p["active"] and 0 < p["scale"] < 1
    assert all(0 <= v[0] <= 1 and 0 <= v[1] <= 1.2 for v in p["kp"].values())


def test_difficulty_switch_changes_tolerance():
    # a pose that only the generous toddler tolerances accept
    kp = TARGETS["touch_head"]
    an = Analyzer(CFG)
    an.set_difficulty("toddler")
    ev, _ = feed(an, kp, EV["hold_frames"] + 1)
    assert ("touch_nose", "held") in names(ev)          # toddler nose_dist 0.8 > 0.67
    an2 = Analyzer(CFG)
    an2.set_difficulty("kid")
    ev, _ = feed(an2, kp, EV["hold_frames"] + 1)
    assert ("touch_nose", "held") not in names(ev)


def test_duo_mode_two_active_players():
    an = Analyzer(CFG)
    an.set_mode("duo")
    a, b = NEUTRAL.copy(), NEUTRAL.copy()
    a[:, 0] -= 150
    b[:, 0] += 150
    res = an.process([Person(bbox_of(a), .9, a), Person(bbox_of(b), .9, b)], (640, 360), 0.0, 1)
    assert len(res.active_ids) == 2
