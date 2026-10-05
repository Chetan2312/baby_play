import json

import pytest

from takatak_vision import protocol as P
from takatak_vision.gestures import KEYPOINT_NAMES
from takatak_vision.poses import NEUTRAL, bbox_of


def test_binary_roundtrip():
    data = P.pack_binary(P.KIND_FRAME, 881, b"\xff\xd8jpeg")
    assert data[0] == 0x01 and len(data) == 5 + 6
    assert P.unpack_binary(data) == (P.KIND_FRAME, 881, b"\xff\xd8jpeg")
    assert P.unpack_binary(P.pack_binary(P.KIND_MASK, 2 ** 32 + 5, b""))[1] == 5
    with pytest.raises(P.ProtocolError):
        P.unpack_binary(b"\x01\x00")


def test_every_message_has_type_and_ts():
    for m in (P.hello("wide", ["pose"], False), P.pose(1, []), P.gesture(3, "clap", "held", 0.9),
              P.status({"cam": 30}, 61.2), P.no_player(3.2), P.button("down"), P.pong(), P.error("x")):
        d = json.loads(P.dumps(m))
        assert d["t"] in P.VISION_TYPES and isinstance(d["ts"], int)


def test_hello_carries_hardware():
    hw = {"profile": "devrig", "accelerator": "hailo8", "cameras": ["imx708_wide"], "network": "offline"}
    d = json.loads(P.dumps(P.hello("wide", ["pose"], False, hardware=hw)))
    assert d["hardware"] == hw
    assert json.loads(P.dumps(P.hello("wide", [], False)))["hardware"] == {}


def test_button_rejects_bad_state():
    assert P.button("up")["state"] == "up"
    with pytest.raises(P.ProtocolError):
        P.button("pressed")


def test_gesture_rejects_bad_state():
    with pytest.raises(P.ProtocolError):
        P.gesture(1, "clap", "maybe", 1.0)


def test_mirroring_and_normalisation():
    assert P.to_display(160, 90, 640, 360, mirror=True) == (0.75, 0.25)
    assert P.to_display(160, 90, 640, 360, mirror=False) == (0.25, 0.25)
    assert P.bbox_to_display([100, 36, 300, 324], 640, 360, True) == pytest.approx([0.53125, 0.1, 0.84375, 0.9], abs=1e-4)


def test_person_wire_keeps_anatomical_names():
    kp = NEUTRAL
    w = P.person_to_wire(3, True, 0.91, bbox_of(kp), kp, 60.0, 640, 360, mirror=True)
    assert list(w["kp"]) == KEYPOINT_NAMES
    # child's left wrist is at camera-right (x=370) → mirrored display x < 0.5 (screen left)
    assert w["kp"]["l_wrist"][0] == pytest.approx(1 - 370 / 640, abs=1e-4)
    assert w["kp"]["l_wrist"][0] < 0.5 < w["kp"]["r_wrist"][0]
    assert w["scale"] == pytest.approx(60 / 640, abs=1e-4)
    assert w["bbox"][0] < w["bbox"][2]
    json.dumps(w)  # serialisable (no numpy types)


@pytest.mark.parametrize("text,expected", [
    ('{"t":"subscribe"}', {"t": "subscribe", **P.SUBSCRIBE_DEFAULTS}),
    ('{"t":"subscribe","frames":false,"motion":["hop"]}',
     {"t": "subscribe", "frames": False, "mask": False, "loudness": False, "motion": ["hop"]}),
    ('{"t":"set_players","mode":"duo"}', {"t": "set_players", "mode": "duo"}),
    ('{"t":"set_camera","camera":"noir"}', {"t": "set_camera", "camera": "noir"}),
    ('{"t":"set_camera","camera":"imx500"}', {"t": "set_camera", "camera": "imx500"}),
    ('{"t":"set_difficulty","difficulty":"kid"}', {"t": "set_difficulty", "difficulty": "kid"}),
    ('{"t":"mic_listen_start","purpose":"echo","max_s":3}',
     {"t": "mic_listen_start", "purpose": "echo", "max_s": 3.0}),
    ('{"t":"mock_expect","name":"touch_nose"}', {"t": "mock_expect", "name": "touch_nose"}),
    ('{"t":"ping"}', {"t": "ping"}),
])
def test_parse_client_valid(text, expected):
    assert P.parse_client(text) == expected


@pytest.mark.parametrize("text", [
    "not json", "[]", '{"t":"nope"}', '{"t":"subscribe","frames":"yes"}',
    '{"t":"subscribe","motion":["moonwalk"]}', '{"t":"set_players","mode":"trio"}',
    '{"t":"set_camera"}', '{"t":"mic_listen_start","max_s":99}',
    '{"t":"mock_expect","name":"backflip"}',
])
def test_parse_client_invalid(text):
    with pytest.raises(P.ProtocolError):
        P.parse_client(text)
