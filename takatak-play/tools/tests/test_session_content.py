"""Session, curriculum, centre profile and UI-string content (anganwadi demo build)."""
import copy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), "vision"))

import content_build  # noqa: E402
import content_common as C  # noqa: E402
import content_lint as L  # noqa: E402


def test_build_writes_session_curriculum_profile_ui():
    content_build.build()

    def read(*p):
        with open(os.path.join(C.BUILD, *p), encoding="utf-8") as f:
            return json.load(f)

    idx = read("index.json")
    assert "standard_v1" in idx["sessions"] and len(idx["content_version"]) == 10
    sess = read("sessions", "standard_v1.json")
    assert [s["id"] for s in sess["steps"]] == ["greet", "warmup", "theme", "talkback", "cooldown", "goodbye"]
    assert sess["steps"][-1]["then"] == "end_session"
    weeks = read("curriculum.json")["weeks"]
    assert [w["week"] for w in weeks] == [1, 2, 3, 4, 5]
    assert weeks[2]["theme_id"] == "farm_animals"
    centre = read("centre_profile.json")
    assert centre["current_week"] == 3 and centre["language_mode"] == "mr_first"
    assert read("ui.json")["idle_hint"]["mr"]


def test_demo_defaults_match_the_proposal():
    c = C.read_centre_profile()
    assert (c["language_mode"], c["primary_language"], c["current_week"]) == ("mr_first", "mr", 3)
    assert (c["max_sessions_per_day"], c["max_minutes_per_day"]) == (2, 40)
    assert c["sponsor_branding"] == "none"


def test_session_lint_catches_broken_steps():
    lines, games = C.read_lines(), C.read_games()
    sess = copy.deepcopy(C.read_sessions())
    s = sess["standard_v1"]
    s["fallback_game"] = "nope"
    s["steps"][0]["line"] = "no_such_line"
    s["steps"][1]["minutes"] = 0
    s["steps"].append({"id": "x", "type": "dance"})
    errors, _ = L.lint_sessions(sess, lines, games)
    text = "\n".join(errors)
    for needle in ("fallback_game", "no_such_line", "minutes must be > 0", "unknown type 'dance'"):
        assert needle in text, needle


def test_missing_games_are_warnings_not_errors():
    errors, warnings = L.lint_sessions(C.read_sessions(), C.read_lines(), C.read_games())
    assert errors == []
    assert any("call_response" in w and "plays simon_says" in w for w in warnings)


def test_week_lint():
    weeks = copy.deepcopy(C.read_weeks())
    weeks[1]["week"] = 1
    del weeks[0]["title"]["hi"]
    weeks[3]["games"] = []
    errors, warnings = L.lint_weeks(weeks, C.read_games())
    text = "\n".join(errors)
    assert "duplicate week" in text and "title missing hi" in text and "no games" in text
    assert sum("aadharshila_ref is TODO" in w for w in warnings) == 5


def test_centre_lint():
    weeks, sessions = C.read_weeks(), C.read_sessions()
    assert L.lint_centre(C.read_centre_profile(), weeks, sessions) == []
    bad = dict(C.read_centre_profile(), language_mode="hinglish", current_week=9, session_minutes=45,
               slots=6, supervisor_pin=1234, sponsor_branding="acme")
    text = "\n".join(L.lint_centre(bad, weeks, sessions))
    for k in ("language_mode", "current_week", "session_minutes", "slots", "supervisor_pin", "sponsor_branding"):
        assert k in text, k


def test_unreviewed_text_is_listed_and_blocks_release():
    todo = L.unreviewed()
    kinds = {k for k, _ in todo}
    assert {"line", "week title", "ui string"} <= kinds
    assert ("line", "session_greet") in todo
    errors, _ = L.lint(release=True)
    assert any("not reviewed by a native speaker" in e for e in errors)


def test_ui_strings_have_marathi_and_english():
    assert L.lint_ui(C.read_ui_strings()) == []
    assert L.lint_ui({"x": {"mr": "अ"}}) == ["ui string x: missing en"]
