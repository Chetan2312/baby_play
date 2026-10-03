# Takatak Play: Phase 2 (vision service + Godot client)

A big-screen motion game for kids aged 2–7. A Raspberry Pi 5 drives a TV or
projector over HDMI, and the cameras face the kids. The game speaks
Marathi, Hindi and English.

The system runs as two processes that talk over a local WebSocket (`ws://127.0.0.1:8765`):

| | What it does | Code |
|---|---|---|
| **Vision service** (Python, no UI) | Cameras, Hailo-8 pose, tracking, gestures → WebSocket | `vision/` |
| **Game client** (Godot 4, no AI) | Games, mascot, voice, text, effects | `game/` |

Either side runs without the other. Godot shows a "getting ready…" screen and
reconnects every 2 s. `mock_server.py` stands in for the camera on a PC.

**Built so far: milestones P0–P4.**

- **P0:** the Demo 1 code was moved into `vision/`. Its tests still pass and the pygame tool is now `debug_view.py`.
- **P1:** WebSocket service and protocol, plus a mock server with record and replay.
- **P2:** Godot skeleton: mirrored camera feed, reconnecting, a Devanagari test screen.
- **P3:** PlayerAvatar, a placeholder mascot, and AudioDirector.
- **P4:** Simon Says ported to Godot.

## Layout

```
vision/                     Python vision service (package takatak_vision)
  config.yaml               every vision threshold (camera, inference, tracker, gesture tolerances, server)
  takatak_vision/
    main.py                 entry: camera → pose → analysis → WebSocket
    protocol.py             message schemas: single source of truth (docs/protocol.md)
    server.py               websockets server; per-client latest-wins pose/frames, reliable events
    pipeline.py             hardware source (camera + Hailo + JPEG encoder + thermal throttle)
    mock.py                 mock source (synthetic child or recorded session)
    analysis.py             tracker + smoothing + gesture start/held/end events
    tracker.py              multi-person IDs, single/duo active players, keypoint smoothing
    gestures.py, poses.py   Demo 1 static gestures (unchanged) + synthetic test poses
    camera.py, pose.py, postprocess.py, encoder.py
  tools/                    debug_view.py, mock_server.py, record_session.py, record_clip.py, fetch_model.sh
  tests/                    pytest: gestures, decode, tracker, protocol, analysis, end-to-end WebSocket
game/                       Godot 4 project (open this folder in the editor; Compatibility renderer)
  autoload/                 Settings, ContentDB, VisionClient, AudioDirector, Stats, GameManager
  core/                     BaseGame, CameraLayer, PlayerAvatar, Mascot (placeholder), PraiseBurst, UiKit
  scenes/                   Main (builds the layers), Attract, Finish, DevaTest, StatusOverlay
  games/simon_says/         Simon Says
content/
  script/lines.csv          every spoken line × mr/hi/en (DRAFT text: needs native review)
  games/simon_says.yaml     prompts, levels, timing
  session.yaml              session flow timing
  voice/raw/                studio recordings <line_id>_v<variant>_<lang>.wav (not in git)
tools/                      content_build.py, content_lint.py, tts_drafts.py, voice_pipeline.py
docs/                       protocol.md, field_test_log.md
```

## Setup on the Pi

```bash
git pull && cd takatak-play
./install.sh --with-godot --pcie-gen3
sudo reboot            # only after the first Hailo install
```

`install.sh` does the following:

1. Installs the system packages from apt (`hailo-all`, `python3-picamera2`,
   `python3-simplejpeg`, Noto fonts, `espeak-ng`, `ffmpeg`). Hailo and libcamera
   can't be pip-installed.
2. Creates the Python venv in **`.env`** and pip-installs `websockets`, `pyyaml` and `pytest` into it.
3. Fetches the Hailo-8 `yolov8s_pose.hef`.
4. Downloads Godot `GODOT_VERSION` (default 4.4.1, linux arm64) into
   `.godot-bin/`. Use the same version as the Godot editor on your PC.
5. Generates draft voices (espeak-ng), converts them to OGG, builds the content
   JSON and lints it.
6. Runs a self-check, then the tests.

Optional flags: `--full-upgrade` and `--skip-apt`.

## Running

| Command | What it does | Milestone |
|---|---|---|
| `./run.sh check` | Hailo identify and the camera list | |
| `./run.sh debug` | pygame viewer of exactly what the game receives: mirrored JPEG, keypoints, gesture events, fps (`--mock` needs no hardware) | P0 |
| `./run.sh vision` | Vision service on :8765 (`--camera noir`, `--video clip.mp4`) | P1 |
| `./run.sh game --deva-test` | Devanagari check on the TV; also speaks lines in each language | P2 |
| `./run.sh play` | Vision service and game together (the service stops when the game exits) | P2–P4 |
| `./run.sh play-mock` | Mock vision and game in a window (PC or Pi, no camera) | |
| `./run.sh content` | Draft voices → OGG (−18 LUFS) → build → lint | |
| `./run.sh test` | All Python tests | |

**Game keys:** `Space` skip/start · `L` language mode (all/single/rotate) ·
`K` primary language · `T` toddler/kid · `C` camera wide↔noir · `S` skeleton ·
`D` debug line · `F2` Devanagari test · `Esc` quit.

**Game args** go after `./run.sh game`: `--windowed`, `--screen=N`,
`--lang=mr|hi|en`, `--language-mode=all|single|rotate`,
`--difficulty=toddler|kid`, `--vision=ws://host:8765`, `--content=/path`,
`--debug`, `--deva-test`.

### PC development (no Pi)

1. Install the Godot 4 editor (same version as the Pi) and Python 3.11+ with
   `pip install websockets pyyaml numpy pillow`.
2. Start the mock: `python vision/tools/mock_server.py`. The synthetic child
   does whatever Simon Says expects (the game sends `mock_expect`). Type
   `away` to test pause/callback, or `touch_nose`, `neutral` and so on.
   `--auto` cycles poses by itself, `--react 20` makes the child too slow so
   you can test hints, and `--replay logs/sessions/x.jsonl` replays a recorded
   Pi session.
3. Run `python tools/content_build.py`, then open `game/` in Godot and press
   Play (add `--windowed` under Project → Run args, or just use the editor's
   windowed run).

To point a PC game at the real Pi: run `./run.sh vision` on the Pi with
`host: 0.0.0.0` in `vision/config.yaml`, then pass `--vision=ws://<pi>:8765`
to the game.

## How Simon Says works now

1. The vision service evaluates every static gesture for the active player each
   frame. It sends `start` after 2 frames, `held` after 6, and `end` after a
   miss (all set in `vision/config.yaml`). It also sends `neutral` (hands down).
   `set_difficulty` picks the toddler or kid tolerances.
2. The Godot game says the prompt and arms after `intro_arm_s`. Arming also
   needs a neutral pose (or `rearm_gap_s`), so the previous pose can't trigger
   the next prompt. Success comes when the target gesture is `held`. The
   progress ring fills between `start` and `held`.
3. Success brings praise (never repeating the last 3), a star burst, and the
   word in 3 scripts, spoken in the configured languages.
4. On timeout the mascot comes forward and demonstrates, gives a hint, and
   repeats the prompt. A second timeout gets an encouragement line and a gentle
   move on. Nothing on screen or in audio signals failure.
5. If the child leaves for 3 s, the game pauses and the mascot calls them back.
   After 60 s away it returns to attract.

Language modes (`L`):

- `all`: the prompt is spoken in the primary language but shown in all 3 scripts; the word is shown and spoken in all 3.
- `single`: one language throughout.
- `rotate`: the language changes every round.

## Voice

- Every line lives in `content/script/lines.csv`. The Marathi and Hindi drafts **must be reviewed by native speakers**. `content_lint.py` warns that praise (15) and encourage (8) are below the brief's 25 and 15.
- Studio recordings go in `content/voice/raw/<line_id>_v<variant>_<lang>.wav` and automatically take precedence over drafts. Run `./run.sh content` after adding them.
- PC drafts with Indic Parler-TTS: `python tools/tts_drafts.py --engine parler` (needs a GPU).
- If Rhubarb is on PATH, lipsync JSON is generated. The placeholder mascot moves its mouth from the voice bus level either way.
- `content_lint.py --release` fails if any draft voice would ship.

## Privacy

- Everything runs on the device.
- The service never stores frames.
- `record_session.py` saves keypoints only, unless you pass `--with-frames --i-have-consent`.
- Stats (`user://stats/`) hold outcomes only.
- `content/names/` (the child's name clip) and `content/voice/raw/` are gitignored.

## Not built yet

P5 onward:

- Mic, VAD and parrot echo (P5).
- Segmentation cutout and shaders (P6).
- Motion detectors (P7).
- Rhubarb-driven lip sync and real voice recordings (P8).
- Jungle Adventure (P9).
- Parent panel, kiosk and systemd units in `deploy/` (P10).
- The other games (P11).

The mascot is a code-drawn placeholder with the final API (`play`, `demo`, `look_at_point`).

## Troubleshooting

| Symptom | Fix |
|---|---|
| Godot stuck on "Getting ready…" | Is `./run.sh vision` (or `mock`) running? Check `--vision=` |
| "Content not found" | `./run.sh content` (or `python tools/content_build.py`) |
| GDScript error on first run | Report the error from the Godot output. The scripts avoid `class_name`, so no editor import should be needed |
| Devanagari broken in Godot | `sudo apt install fonts-noto-core`; check with `./run.sh game --deva-test` |
| Model / Hailo / camera errors | Shown at the bottom of the game screen and in `./run.sh debug`; see `vision/tools/fetch_model.sh` |
| Hot Pi | `D` shows `temp_c`; above 80 °C the frame rate drops to 15 fps automatically |
