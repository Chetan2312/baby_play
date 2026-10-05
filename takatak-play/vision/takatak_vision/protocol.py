"""WebSocket protocol: the single source of truth.

Keep game/autoload/VisionClient.gd in sync with this file and docs/protocol.md.

Text frames are JSON objects with "t" (type) and "ts" (monotonic ms).
Binary frames: 1 byte kind, 4 bytes frame_id (uint32 LE), then the payload.

Coordinates sent to the game are normalised 0-1 in DISPLAY space, already
mirrored when display mirroring is on (x_display = 1 - x_camera). Keypoint
names stay anatomical: "l_wrist" is the child's own left wrist.
"""
import json
import struct
import time

from .gestures import CHECKS, KEYPOINT_NAMES

VERSION = 1
DEFAULT_PORT = 8765

KIND_FRAME = 0x01   # JPEG
KIND_MASK = 0x02    # 8-bit mask (Phase P6)
_HDR = struct.Struct("<BI")

GESTURE_STATES = ("start", "held", "end")
GESTURE_NAMES = tuple(CHECKS) + ("neutral",)
MOTION_NAMES = ("hop", "flap", "stomp", "run_on_spot", "freeze", "wave", "crouch",
                "crawl_low", "jump")
PLAYER_MODES = ("single", "duo")
CAMERAS = ("wide", "noir", "imx500", "auto")
DIFFICULTIES = ("toddler", "kid")
BUTTON_STATES = ("down", "up")

# vision → game
VISION_TYPES = ("hello", "pose", "hands", "gesture", "motion", "loudness", "echo_ready", "keyword",
                "status", "no_player", "button", "pong", "error")
HAND_GESTURES = ("point", "open", "fist", "other")
# game → vision ("set_difficulty" picks static gesture tolerances; "mock_expect" is
# honoured only by tools/mock_server.py so games can be built without a camera)
GAME_TYPES = ("subscribe", "set_players", "set_camera", "set_difficulty",
              "mic_listen_start", "mic_listen_stop", "ping", "mock_expect")

SUBSCRIBE_DEFAULTS = {"frames": True, "mask": False, "loudness": False, "motion": [], "hands": False}


class ProtocolError(ValueError):
    pass


def now_ms():
    return int(time.monotonic() * 1000)


def message(t, ts=None, **fields):
    return {"t": t, "ts": now_ms() if ts is None else int(ts), **fields}


def dumps(msg):
    return json.dumps(msg, separators=(",", ":"), ensure_ascii=False)


# ---- binary ---------------------------------------------------------------
def pack_binary(kind, frame_id, payload):
    return _HDR.pack(kind, frame_id & 0xFFFFFFFF) + payload


def unpack_binary(data):
    if len(data) < _HDR.size:
        raise ProtocolError("binary frame too short")
    kind, frame_id = _HDR.unpack_from(data)
    return kind, frame_id, data[_HDR.size:]


# ---- coordinates ----------------------------------------------------------
def to_display(x, y, frame_w, frame_h, mirror):
    nx, ny = x / frame_w, y / frame_h
    return (1.0 - nx if mirror else nx), ny


def bbox_to_display(b, frame_w, frame_h, mirror):
    x1, y1 = to_display(b[0], b[1], frame_w, frame_h, mirror)
    x2, y2 = to_display(b[2], b[3], frame_w, frame_h, mirror)
    return [round(min(x1, x2), 4), round(y1, 4), round(max(x1, x2), 4), round(y2, 4)]


def person_to_wire(pid, active, conf, bbox, kp, scale_px, frame_w, frame_h, mirror):
    kpd = {}
    for name, (x, y, c) in zip(KEYPOINT_NAMES, kp):
        dx, dy = to_display(x, y, frame_w, frame_h, mirror)
        kpd[name] = [round(dx, 4), round(dy, 4), round(float(c), 3)]
    return {
        "id": int(pid),
        "active": bool(active),
        "conf": round(float(conf), 3),
        "bbox": bbox_to_display(bbox, frame_w, frame_h, mirror),
        "scale": round(float(scale_px) / frame_w, 4) if scale_px else 0.0,
        "kp": kpd,
    }


# ---- vision → game builders ----------------------------------------------
def hello(camera, models, mic, errors=(), mirror=True, hardware=None):
    """hardware: boot probe for the status screen (hardware.probe), {} when unknown."""
    return message("hello", version=VERSION, camera=camera, models=list(models), mic=bool(mic),
                   mirror=bool(mirror), errors=list(errors), hardware=dict(hardware or {}))


def pose(frame_id, people, ts=None):
    return message("pose", ts, frame_id=int(frame_id), people=people)


def hand_to_wire(player, side, landmarks_display, fingers, count, hand_gesture):
    """landmarks_display: (21, 2+) normalised display coords (already mirrored)."""
    if hand_gesture not in HAND_GESTURES:
        raise ProtocolError(f"bad hand gesture {hand_gesture!r}")
    kp = [[round(float(x), 4), round(float(y), 4)] for x, y in ((p[0], p[1]) for p in landmarks_display)]
    return {"player": int(player), "side": side, "gesture": hand_gesture, "count": int(count),
            "fingers": [bool(f) for f in fingers], "tip": kp[8], "kp": kp}


def hands(frame_id, hand_list, ts=None):
    """Latest-wins like pose. Sent for every processed frame while subscribed, even when
    empty, so the game knows hand tracking is running."""
    return message("hands", ts, frame_id=int(frame_id), hands=list(hand_list))


def gesture(player, name, state, confidence, ts=None):
    if state not in GESTURE_STATES:
        raise ProtocolError(f"bad gesture state {state!r}")
    return message("gesture", ts, player=int(player), name=name, state=state,
                   confidence=round(float(confidence), 3))


def status(fps, temp_c=None, errors=(), camera=None, latency=None):
    """latency: {"pose": ms, "hand_ms": ms, "hand_latency_ms": ms} (capture → result)."""
    return message("status", fps={k: round(float(v), 1) for k, v in fps.items()},
                   temp_c=None if temp_c is None else round(float(temp_c), 1),
                   errors=list(errors), camera=camera,
                   latency_ms={k: round(float(v)) for k, v in (latency or {}).items()})


def no_player(seconds):
    return message("no_player", seconds=round(float(seconds), 2))


def button(state):
    """GPIO worker button edge. The game's InputRouter turns edges into short/long presses."""
    if state not in BUTTON_STATES:
        raise ProtocolError(f"bad button state {state!r}")
    return message("button", state=state)


def pong():
    return message("pong")


def error(text):
    return message("error", text=str(text))


# ---- game → vision parsing ------------------------------------------------
def _bool(d, k, default):
    v = d.get(k, default)
    if not isinstance(v, bool):
        raise ProtocolError(f"{k} must be a bool")
    return v


def _choice(d, k, options):
    v = d.get(k)
    if v not in options:
        raise ProtocolError(f"{k} must be one of {options}, got {v!r}")
    return v


def parse_client(text):
    """Validate a game → vision JSON message and fill defaults."""
    try:
        d = json.loads(text)
    except (TypeError, ValueError) as e:
        raise ProtocolError(f"invalid JSON: {e}") from e
    if not isinstance(d, dict):
        raise ProtocolError("message must be an object")
    t = d.get("t")
    if t not in GAME_TYPES:
        raise ProtocolError(f"unknown message type {t!r}")
    out = {"t": t}
    if t == "subscribe":
        for k, default in SUBSCRIBE_DEFAULTS.items():
            if k == "motion":
                m = d.get("motion", [])
                if not isinstance(m, list) or any(x not in MOTION_NAMES for x in m):
                    raise ProtocolError(f"motion must be a list of {MOTION_NAMES}")
                out["motion"] = list(m)
            else:
                out[k] = _bool(d, k, default)
    elif t == "set_players":
        out["mode"] = _choice(d, "mode", PLAYER_MODES)
    elif t == "set_camera":
        out["camera"] = _choice(d, "camera", CAMERAS)
    elif t == "set_difficulty":
        out["difficulty"] = _choice(d, "difficulty", DIFFICULTIES)
    elif t == "mic_listen_start":
        out["purpose"] = str(d.get("purpose", "echo"))
        max_s = d.get("max_s", 3)
        if not isinstance(max_s, (int, float)) or not 0 < max_s <= 10:
            raise ProtocolError("max_s must be a number in (0, 10]")
        out["max_s"] = float(max_s)
    elif t == "mock_expect":
        name = d.get("name")
        if name is not None and name not in GESTURE_NAMES + MOTION_NAMES:
            raise ProtocolError(f"unknown gesture {name!r}")
        out["name"] = name
    return out
