"""D8: the field build stores nothing about children and talks to nothing but localhost.

Builds a real field package (tools/make_field_build.py) and inspects it:
  - dev tools that record or download are not in it at all
  - the build is pinned to "field" (TAKATAK_BUILD=dev can't unlock anything)
  - no network clients other than the localhost vision WebSocket
  - no code path that writes frames, audio or images; file writes only where allowed
  - voice temp files go to RAM (tmpfs), child-name clips are off
"""
import os
import re
import subprocess
import sys

import pytest
import yaml

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))

import content_build  # noqa: E402
import make_field_build  # noqa: E402

TEXT_EXT = (".py", ".gd", ".sh", ".yaml", ".yml", ".tscn", ".cfg", ".godot", ".toml", ".txt")

NETWORK = {
    ".py": [r"\bimport requests\b", r"\burllib\b", r"http\.client", r"\bhttpx\b", r"\baiohttp\b",
            r"create_connection", r"\.connect\(\(", r"websockets\.connect", r"websockets\.sync\.client",
            r"\bsmtplib\b", r"\bftplib\b", r"\bparamiko\b"],
    ".gd": [r"\bHTTPRequest\b", r"\bHTTPClient\b", r"\bStreamPeerTCP\b", r"\bPacketPeerUDP\b",
            r"\bWebSocketPeer\b", r"connect_to_url", r"OS\.shell_open", r"\bTCPServer\b", r"\bUDPServer\b"],
    ".sh": [r"\bcurl\b", r"\bwget\b", r"\bssh\b", r"\bscp\b", r"\brsync\b"],
}
NETWORK_ALLOWED = {"game/autoload/VisionClient.gd": {r"\bWebSocketPeer\b", r"connect_to_url"}}

PERSIST = {
    ".py": [r"imwrite", r"VideoWriter", r"start_and_record_video", r"capture_file", r"start_recording",
            r"wave\.open", r"soundfile", r"np\.save", r"pickle\.dump"],
    ".gd": [r"save_png", r"save_jpg", r"save_webp", r"save_exr", r"save_to_wav", r"AudioEffectRecord",
            r"\.save\(\s*\"user://"],
}
# file writes are allowed only here: perf log (fps/temperature), usage counters, centre profile, settings
PY_WRITE_ALLOWED = {"vision/takatak_vision/perf.py"}
GD_WRITE_ALLOWED = {"game/autoload/Stats.gd", "game/autoload/Centre.gd"}


@pytest.fixture(scope="module")
def pkg(tmp_path_factory):
    content_build.build()
    out = tmp_path_factory.mktemp("field") / "takatak-field"
    return str(make_field_build.make(str(out)))


def runtime_files(pkg):
    for dirpath, _, files in os.walk(pkg):
        for fn in files:
            if fn.endswith(TEXT_EXT) or fn == "run.sh":
                p = os.path.join(dirpath, fn)
                yield os.path.relpath(p, pkg).replace(os.sep, "/"), p


def scan(pkg, table, allowed=None):
    hits = []
    for rel, p in runtime_files(pkg):
        ext = os.path.splitext(rel)[1] or ".sh"
        pats = table.get(ext, [])
        if not pats:
            continue
        with open(p, encoding="utf-8", errors="replace") as f:
            text = f.read()
        for pat in pats:
            if allowed and pat in allowed.get(rel, set()):
                continue
            for m in re.finditer(pat, text):
                line = text[:m.start()].count("\n") + 1
                hits.append(f"{rel}:{line}: {pat}")
    return hits


def test_dev_tools_are_left_out(pkg):
    for rel in ("vision/tools", "tools", "install.sh", "game/tests", "vision/tests",
                "content/voice/raw", "content/names", "content/script"):
        assert not os.path.exists(os.path.join(pkg, rel)), rel
    for rel in ("run.sh", "vision/takatak_vision/main.py", "game/project.godot", "content/build/index.json"):
        assert os.path.exists(os.path.join(pkg, rel)), rel


def test_build_is_pinned_to_field(pkg):
    assert os.path.exists(os.path.join(pkg, "game", "BUILD_FIELD"))
    env = dict(os.environ, TAKATAK_BUILD="dev")
    out = subprocess.run([sys.executable, "-c", "from takatak_vision import build; print(build.current())"],
                         cwd=os.path.join(pkg, "vision"), env=env, capture_output=True, text=True, timeout=30)
    assert out.stdout.strip() == "field", out.stderr


def test_no_network_clients(pkg):
    assert scan(pkg, NETWORK, NETWORK_ALLOWED) == []


def test_vision_is_localhost_only(pkg):
    with open(os.path.join(pkg, "vision", "config.yaml"), encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    assert cfg["server"]["host"] == "127.0.0.1"
    with open(os.path.join(pkg, "game", "autoload", "Settings.gd"), encoding="utf-8") as f:
        settings = f.read()
    assert 'LOCAL_VISION_URL := "ws://127.0.0.1:8765"' in settings
    assert re.search(r'--vision=.*\n\s*if is_field\(\):', settings), "field build must ignore --vision"


def test_nothing_saves_frames_audio_or_images(pkg):
    assert scan(pkg, PERSIST) == []


def test_file_writes_only_where_allowed(pkg):
    bad = []
    for rel, p in runtime_files(pkg):
        with open(p, encoding="utf-8", errors="replace") as f:
            text = f.read()
        if rel.endswith(".py") and rel not in PY_WRITE_ALLOWED:
            for m in re.finditer(r"open\([^)]*['\"](w|a|wb|ab|x)b?['\"]", text):
                bad.append(f"{rel}: {m.group(0)}")
        if rel.endswith(".gd") and rel not in GD_WRITE_ALLOWED:
            for m in re.finditer(r"FileAccess\.open\([^)]*WRITE", text):
                bad.append(f"{rel}: {m.group(0)}")
    assert bad == []


def test_jpeg_encoding_stays_in_memory(pkg):
    for rel in ("vision/takatak_vision/encoder.py", "vision/takatak_vision/mock.py"):
        with open(os.path.join(pkg, rel), encoding="utf-8") as f:
            text = f.read()
        for m in re.finditer(r"\.save\((\w+)", text):
            assert re.search(rf"{m.group(1)}\s*=\s*io\.BytesIO\(\)", text), f"{rel}: save() not to BytesIO"


def test_privacy_config(pkg):
    with open(os.path.join(pkg, "vision", "config.yaml"), encoding="utf-8") as f:
        cfg = yaml.safe_load(f)
    assert cfg["privacy"]["save_frames"] is False
    assert cfg["paths"]["tmp_audio"].startswith(("/run/", "/dev/shm/")), "voice temp files must be in RAM"
    with open(os.path.join(pkg, "game", "autoload", "ContentDB.gd"), encoding="utf-8") as f:
        assert 'if root == "" or Settings.is_field():' in f.read(), "child-name clips must be off in field builds"


def test_scanners_catch_planted_violations(tmp_path):
    (tmp_path / "game").mkdir()
    (tmp_path / "vision").mkdir()
    (tmp_path / "vision" / "leak.py").write_text("import requests\ncv2.imwrite('x.png', f)\n")
    (tmp_path / "game" / "Leak.gd").write_text("var h := HTTPRequest.new()\nimg.save_png(\"user://x.png\")\n")
    (tmp_path / "run.sh").write_text("curl http://example.com\n")
    net = scan(str(tmp_path), NETWORK, NETWORK_ALLOWED)
    assert len(net) == 3 and any("leak.py" in h for h in net) and any("Leak.gd" in h for h in net)
    persist = scan(str(tmp_path), PERSIST)
    assert len(persist) == 2
