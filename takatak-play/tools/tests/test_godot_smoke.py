"""Headless Godot: the session flow end to end (game/tests/SessionSmoke.tscn), and a field
package boots. Skipped when no Godot binary is found (GODOT=…, .godot-bin/godot, PATH)."""
import os
import shutil
import subprocess
import sys

import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import content_build  # noqa: E402
import make_field_build  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(HERE))


def find_godot():
    for g in (os.environ.get("GODOT"), os.path.join(ROOT, ".godot-bin", "godot"),
              shutil.which("godot4"), shutil.which("godot")):
        if g and os.access(g, os.X_OK):
            return g
    return None


GODOT = find_godot()
pytestmark = pytest.mark.skipif(GODOT is None, reason="no Godot binary (set GODOT=/path/to/godot)")


def godot(project, *args, timeout=180):
    if not os.path.isdir(os.path.join(project, ".godot")):
        subprocess.run([GODOT, "--headless", "--path", project, "--editor", "--quit"],
                       capture_output=True, timeout=timeout)
    return subprocess.run([GODOT, "--headless", "--path", project, *args], capture_output=True,
                          text=True, timeout=timeout)


def test_session_smoke(tmp_path):
    content_build.build()
    r = godot(os.path.join(ROOT, "game"), "res://tests/SessionSmoke.tscn", "--", f"--usage-dir={tmp_path}")
    assert "SMOKE OK" in r.stdout, r.stdout[-3000:] + r.stderr[-2000:]
    assert "SCRIPT ERROR" not in r.stderr, r.stderr[-3000:]


def test_field_package_boots(tmp_path):
    content_build.build()
    pkg = make_field_build.make(str(tmp_path / "pkg"))
    env = dict(os.environ, TAKATAK_BUILD="dev")   # must not matter: the package is pinned
    r = subprocess.run([GODOT, "--headless", "--path", os.path.join(pkg, "game"), "--editor", "--quit"],
                       capture_output=True, timeout=180)
    r = subprocess.run([GODOT, "--headless", "--path", os.path.join(pkg, "game"), "--quit-after", "120",
                        "--", f"--usage-dir={tmp_path / 'usage'}"], capture_output=True, text=True,
                       timeout=180, env=env)
    assert "[settings] build=field" in r.stdout, r.stdout[-2000:]
    assert "SCRIPT ERROR" not in r.stderr and "Parse Error" not in r.stderr, r.stderr[-3000:]
