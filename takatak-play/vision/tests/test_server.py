"""End-to-end: real VisionServer + MockSource over a real WebSocket."""
import asyncio
import json
import socket
import time

import pytest

websockets = pytest.importorskip("websockets")

from takatak_vision import protocol as P  # noqa: E402
from takatak_vision.config import load_config  # noqa: E402
from takatak_vision.mock import MockPerformer, MockSource  # noqa: E402
from takatak_vision.server import VisionServer  # noqa: E402


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


async def recv_until(ws, pred, timeout=6.0):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        raw = await asyncio.wait_for(ws.recv(), end - time.monotonic())
        msg = raw if isinstance(raw, bytes) else json.loads(raw)
        if pred(msg):
            return msg
    raise AssertionError("timeout")


def test_end_to_end_with_mock():
    cfg = load_config()
    port = free_port()
    cfg["server"]["port"] = port
    cfg["server"]["status_every_s"] = 0.3
    source = MockSource(cfg, MockPerformer(react_s=0.2, hold_s=1.0), pose_hz=30, frame_hz=15)
    source.start()
    server = VisionServer(cfg, source)

    async def scenario():
        stop, ready = asyncio.Event(), asyncio.Event()
        task = asyncio.create_task(server.serve(stop, ready))
        await ready.wait()
        url = f"ws://127.0.0.1:{port}"
        async with websockets.connect(url, max_size=2 ** 22) as ws:
            hello = await recv_until(ws, lambda m: isinstance(m, dict))
            assert hello["t"] == "hello" and hello["version"] == P.VERSION and hello["mirror"]
            assert hello["hardware"]["profile"] == "mock"
            server.button_threadsafe("down")   # GPIO thread → every client
            btn = await recv_until(ws, lambda m: isinstance(m, dict) and m["t"] == "button")
            assert btn["state"] == "down"
            await ws.send(json.dumps({"t": "subscribe", "frames": True, "hands": True}))
            pose = await recv_until(ws, lambda m: isinstance(m, dict) and m["t"] == "pose")
            assert pose["people"] and pose["people"][0]["active"]
            frame = await recv_until(ws, lambda m: isinstance(m, bytes))
            kind, _, jpg = P.unpack_binary(frame)
            assert kind == P.KIND_FRAME and jpg[:2] == b"\xff\xd8"
            await ws.send(json.dumps({"t": "mock_expect", "name": "hands_up"}))
            hands = await recv_until(ws, lambda m: isinstance(m, dict) and m["t"] == "hands" and len(m["hands"]) == 2)
            assert {h["side"]: h["gesture"] for h in hands["hands"]} == {"r": "point", "l": "open"}   # mock
            await ws.send(json.dumps({"t": "mock_expect", "name": "touch_nose"}))
            held = await recv_until(ws, lambda m: isinstance(m, dict) and m["t"] == "gesture"
                                    and m["name"] == "touch_nose" and m["state"] == "held")
            assert held["confidence"] > 0.5
            await ws.send(json.dumps({"t": "ping"}))
            await recv_until(ws, lambda m: isinstance(m, dict) and m["t"] == "pong")
            await ws.send("garbage")
            err = await recv_until(ws, lambda m: isinstance(m, dict) and m["t"] == "error")
            assert "JSON" in err["text"]
            status = await recv_until(ws, lambda m: isinstance(m, dict) and m["t"] == "status")
            assert "pose" in status["fps"] and status["frame_size"] == [960, 540]
            await ws.send(json.dumps({"t": "set_rotation", "rotation": "inverted"}))
            status = await recv_until(ws, lambda m: isinstance(m, dict) and m["t"] == "status")
            assert status["rotation"] == "inverted"
            await ws.send(json.dumps({"t": "subscribe", "frames": False}))
        # game disconnects and comes back: service keeps going
        async with websockets.connect(url, max_size=2 ** 22) as ws:
            assert (await recv_until(ws, lambda m: isinstance(m, dict)))["t"] == "hello"
            source.performer.command("away")
            np_msg = await recv_until(ws, lambda m: isinstance(m, dict) and m["t"] == "no_player")
            assert np_msg["seconds"] >= cfg["server"]["no_player_after_s"]
        stop.set()
        await task

    try:
        asyncio.run(scenario())
    finally:
        source.stop()
