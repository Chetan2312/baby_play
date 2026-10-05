# Vision ↔ Game protocol (v1)

Additions since Phase 2 (`hello.hardware`, `button`, `imx500`) are additive: the version stays 1.

Source of truth: `vision/takatak_vision/protocol.py`. Mirror: `game/autoload/VisionClient.gd`.
Tests: `vision/tests/test_protocol.py`, `vision/tests/test_server.py`.

The game connects to `ws://127.0.0.1:8765` and reconnects every 2 s. The vision
service keeps running when the game disconnects.

## Framing

- **Text frames:** JSON objects. Every message has `t` (the type) and `ts` (monotonic milliseconds).
- **Binary frames:** 1 byte `kind` (`0x01` = JPEG frame, `0x02` = mask), then 4 bytes `frame_id` (uint32 LE), then the payload.

## Coordinates

- Values are normalised 0–1 in **display space** (origin top-left, y down).
- When `hello.mirror` is true, they are **already mirrored**. So is the frame. The game never mirrors anything.
- Keypoint names are anatomical: `l_wrist` is the child's own left wrist. The mirror moves it to the screen's left.
- `scale` is the shoulder width ÷ frame width. Use it to size hit areas.

Keypoints: `nose l_eye r_eye l_ear r_ear l_shoulder r_shoulder l_elbow r_elbow l_wrist r_wrist l_hip r_hip l_knee r_knee l_ankle r_ankle`, each `[x, y, conf]`.

## Vision → Game

| `t` | Fields | Notes |
|---|---|---|
| `hello` | `version, camera, models[], mic, mirror, errors[], hardware{}` | Sent first on every connection. `hardware`: boot probe for the status screen: `profile, accelerator, accelerator_expected, accelerator_present, model, cameras[], audio[], mic, network, errors[]` (`{}` when unknown) |
| `pose` | `frame_id, people[{id, active, conf, bbox[x1,y1,x2,y2], scale, kp{}}]` | Every inference frame. Latest wins (a slow client skips some). Includes everyone; `active` marks player(s) |
| `gesture` | `player, name, state, confidence` | `state`: `start` → `held` → `end`. `name` is a static check or `neutral`. Sent only for active players. Never dropped |
| `motion` | `player, name, confidence, count` | Phase P7 |
| `loudness` | `db, speaking` | Phase P5 (sent only when subscribed) |
| `echo_ready` | `path, duration` | Phase P5 |
| `keyword` | `word, lang, confidence` | Phase 2b |
| `status` | `fps{cam,pose,frames}, temp_c, errors[], camera` | Every 1 s |
| `no_player` | `seconds` | Every 0.5 s while there is no active player (from 1 s on) |
| `button` | `state`: `down` \| `up` | GPIO worker button edge (`gpio_button` in config.yaml). The game's InputRouter turns edges into short / 2 s / 5 s presses. Never dropped |
| `pong` | | Reply to `ping` |
| `error` | `text` | Bad message from the game, or an unavailable feature |

Static gesture names: `touch_nose touch_head touch_ear hands_up touch_tummy touch_shoulders touch_knees clap left_hand_up neutral`.

## Game → Vision

| `t` | Fields | Notes |
|---|---|---|
| `subscribe` | `frames, mask, loudness, motion[]` | Defaults: frames on, everything else off |
| `set_players` | `mode`: `single` \| `duo` | Duo: one active player per screen half |
| `set_camera` | `camera`: `wide` \| `noir` \| `imx500` \| `auto` | With one camera connected, that camera is used whatever is asked |
| `set_difficulty` | `difficulty`: `toddler` \| `kid` | Picks the static gesture tolerances (addition to the brief) |
| `mic_listen_start` | `purpose, max_s` (≤ 10) | Phase P5; returns `error` until then |
| `mic_listen_stop` | | Phase P5 |
| `ping` | | |
| `mock_expect` | `name` | Dev only. The mock server's synthetic child performs the gesture; the real service ignores it |
