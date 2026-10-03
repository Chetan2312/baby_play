import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(HERE)), "vision"))

import content_build  # noqa: E402
import content_common as C  # noqa: E402
from content_lint import lint  # noqa: E402


def test_repo_content_lints_clean():
    errors, _ = lint()
    assert errors == []


def test_every_line_has_all_languages():
    for lid, e in C.read_lines().items():
        for v, data in e["variants"].items():
            assert set(data["text"]) == set(C.LANGS), (lid, v)


def test_build_output_shape():
    content_build.build()
    with open(os.path.join(C.BUILD, "lines.json"), encoding="utf-8") as f:
        lines = json.load(f)
    assert lines["langs"] == list(C.LANGS)
    assert "praise" in lines["categories"]
    nose = lines["lines"]["simon_nose"]
    assert nose["category"] == "prompt" and nose["variants"][0]["text"]["mr"] == "नाकाला हात लाव!"
    with open(os.path.join(C.BUILD, "games", "simon_says.json"), encoding="utf-8") as f:
        game = json.load(f)
    assert {p["id"] for p in game["prompts"]} >= set(game["levels"]["kid"])
