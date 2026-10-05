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

**Built so far: milestones P0–P4, plus the core of the anganwadi demo build (D0, D1, D2, D4,
D8 on the dev rig).** See [Anganwadi demo build](#anganwadi-demo-build).

- **P0:** the Demo 1 code was moved into `vision/`. Its tests still pass and the pygame tool is now `debug_view.py`.
- **P1:** WebSocket service and protocol, plus a mock server with record and replay.
- **P2:** Godot skeleton: mirrored camera feed, reconnecting, a Devanagari test screen.
- **P3:** PlayerAvatar, a placeholder mascot, and AudioDirector.
- **P4:** Simon Says ported to Godot.

## Layout

```
vision/                     Python vision service (package takatak_vision)
  config.yaml               hardware profile + every vision threshold (camera, inference, tracker, gestures, server)
  models/hailo8|hailo10h/   HEF per accelerator (fetch_model.sh; docs/model_matrix.md)
  takatak_vision/
    main.py                 entry: hardware probe → camera → pose → analysis → WebSocket
    hardware.py             boot probe: accelerator, cameras, audio, network (hello.hardware)
    build.py                field | dev build flag (field = nothing records)
    button.py               optional GPIO worker button
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
  autoload/                 Settings, ContentDB, Centre, VisionClient, AudioDirector, Stats (usage
                            counters), InputRouter (worker buttons), GameManager, SessionDirector
  core/                     BaseGame, CameraLayer, PlayerAvatar, Mascot (placeholder), PraiseBurst, UiKit
  scenes/                   Main, Idle, Supervisor (menu), GamePicker (free play), DevaTest, StatusOverlay
  games/simon_says/         Simon Says
  games/bubble_pop/         Bubble Pop (fruit photos / numbers १–५)
  tests/                    SessionSmoke: headless session-flow test (./run.sh smoke)
content/
  script/lines.csv          every spoken line × mr/hi/en (DRAFT text: needs native review)
  games/simon_says.yaml     prompts, levels, timing
  games/bubble_pop.yaml     packs (local_fruits, numbers_1_5), speeds, sizes per difficulty
  packs/local_fruits/       CC0 / public-domain fruit photos (CREDITS.md)
  sessions/standard.yaml    the anganwadi session (steps, minutes, fallback game)
  curriculum/weeks.yaml     weekly themes mapped to Aadharshila (refs are TODO)
  centre_profile.yaml       per-centre defaults (language, week, caps, PIN …)
  ui/strings.yaml           worker/supervisor screen text (mr + en, DRAFT)
  session.yaml              presence/pause timing
  voice/raw/                studio recordings <line_id>_v<variant>_<lang>.wav (not in git)
tools/                      content_build.py, content_lint.py, tts_drafts.py, voice_pipeline.py,
                            make_field_build.py (field package)
docs/                       protocol.md, model_matrix.md, data_policy.md, field_test_log.md
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
3. Fetches `yolov8s_pose.hef` for the hardware profile (`vision/models/hailo8/` on the dev rig)
   and creates `/var/lib/takatak/usage` (usage counters) and `/run/takatak` (RAM temp files).
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
| `./run.sh vision` | Vision service on :8765 (`--profile kit`, `--camera noir`; `--video clip.mp4` needs `TAKATAK_BUILD=dev`) | P1 |
| `./run.sh game --deva-test` | Devanagari check on the TV; also speaks lines in each language | P2 |
| `./run.sh play` | Vision service and game together (the service stops when the game exits) | P2–P4 |
| `./run.sh play-mock` | Mock vision and game in a window (PC or Pi, no camera) | |
| `./run.sh content` | Draft voices → OGG (−18 LUFS) → build → lint | |
| `./run.sh test` | All Python tests (+ Godot smoke tests when `GODOT=` or `.godot-bin/godot` exists) | |
| `./run.sh smoke` | Headless Godot run of the whole session flow, driven like the remote | D1/D2 |
| `./run.sh field-build` | Package a field build into `dist/takatak-field` (`--with-godot`) | D8 |

`vision`, `game` and `play` run as a **field** build (no recording, no tester keys).
For development: `TAKATAK_BUILD=dev ./run.sh play`. `mock`, `play-mock`, `debug`,
`record` and `clip` default to dev.

**Worker buttons** (USB presenter remote, or one GPIO button): see
[Worker control](#worker-control).

**Dev keys** (dev builds only): `X` skip round · `L` language mode · `K` primary
language · `T` toddler/kid · `C` camera wide↔noir · `S` skeleton · `D` debug line ·
`F2` Devanagari test · `Ctrl+Q` quit. → also acts as "next" and ← as "repeat".

**Game args** go after `./run.sh game`: `--windowed`, `--screen=N`,
`--lang=mr|hi|en`, `--language-mode=all|all_three|single|rotate`,
`--difficulty=toddler|kid`, `--vision=ws://host:8765` (dev only), `--content=/path`,
`--usage-dir=/path`, `--free-play`, `--debug`, `--deva-test`.

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
to a dev-build game (`TAKATAK_BUILD=dev`; field builds stay on localhost).

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
   After 60 s away the session says goodbye (free play: back to the game picker).

Language modes (centre profile `language_mode`, or `L` in dev builds):

- `all` (centre profile `mr_first`): the prompt is spoken in Marathi but shown in all 3 scripts; the word is shown and spoken in all 3.
- `all_three` (`all_three`): prompts and words are spoken and shown in all 3.
- `single` (`single`): one language throughout (`primary_language`).
- `rotate` (dev only): the language changes every round.

## How Bubble Pop works

1. Two picker cards: **Fruit bubbles** (`local_fruits` photos) and **Number bubbles**
   (`numbers_1_5`, numerals with dots to count). Picking one asks **Easy / Medium / Hard**.
   In a session, weeks 2 and 4 play it at the centre's age group (3–4 → Easy, 5–6 → Medium).
2. The mascot asks for one item ("Pop number 1!"). A big copy of it sits under the prompt
   card, so children who can't read see what to pop.
3. Mixed in are **decoys** and, from Medium on, **bees** (red rim, crossed bee under the
   prompt): don't pop those. Decoys by level: Easy = only other packs (number round →
   fruit decoys, easy to tell apart) · Medium / Hard = other numbers *and* fruits.
4. **Score top right: +1 for the asked item, −1 for a wrong pop** (decoy or bee). The score
   can go below 0 (shown in red). A wrong pop also gives a light red flash over the
   screen. Each popped bubble shows "+1" / "−1" and its name. Big score at the end.
5. **Pop with one finger**: with hand tracking running, only a hand showing **POINT**
   (index finger up, others folded) pops, at its index fingertip. The tracked hands are
   drawn faintly (the pointing one in gold) and a gold cursor marks the fingertip.
   Without hand tracking it falls back to the arm pointer: the raised hand (the clearly
   higher one if both are up), tip estimated beyond the wrist, moving to pop.
   `pointer: finger | arm` in `bubble_pop.yaml`. 2 / 3 / 4 correct pops (Easy / Medium / Hard) win a round.
6. No luck for 14 s: hint. Bubbles slow down and drift to the hands. After a second
   timeout, a gentle move on.

| Level | Rounds | Pops to win | Bubbles on screen | Speed | Bees | Decoys |
|---|---|---|---|---|---|---|
| Easy | 6 | 2 | 5 | slow | none | other packs |
| Medium | 8 | 3 | 7 | medium | 12 % | all |
| Hard | 10 | 4 | 9 | fast | 20 % | all |

All of it is tunable in `content/games/bubble_pop.yaml` (`levels:`).

## Performance notes (Pi 5)

- Keypoints are smoothed once, in the vision service, with a One Euro filter (`smoothing`
  in `vision/config.yaml`): steady when still, almost no lag when moving. Bubble Pop's
  fingertip glides between poses with its velocity, so it moves every frame.
- For a snappier pointer try `camera_opts.framerate: 50` and watch the fps in
  `./run.sh debug` (the Pi must keep up with pose decoding at that rate).
- **Hand tracking:** 21 points per hand (all five fingers), MediaPipe Hand Landmarker on
  the CPU. The camera captures 1920×1080 (`camera_opts.main_size`); hands are cut out
  around the pose wrists; the game still gets 960×540 (`transport_size`). It runs only
  while a game subscribes (Bubble Pop), so other games cost nothing. Setup once (internet):
  `.env/bin/pip install -r vision/requirements-hands.txt` and
  `vision/tools/fetch_hand_model.sh`. Without them, Bubble Pop uses the arm pointer.
  `./run.sh handprobe` shows the tracking live (stop the vision service first).

- Camera JPEG decoding runs on a worker thread, not the game's main thread.
- Bubble looks are drawn once into textures (one draw per bubble per frame).
- Celebration stars reuse one shape (no per-frame allocations), max 450 particles.

## Voice

- Every line lives in `content/script/lines.csv`. The Marathi and Hindi drafts **must be reviewed by native speakers**. `content_lint.py` warns that praise (15) and encourage (8) are below the brief's 25 and 15.
- Studio recordings go in `content/voice/raw/<line_id>_v<variant>_<lang>.wav` and automatically take precedence over drafts. Run `./run.sh content` after adding them.
- PC drafts with Indic Parler-TTS: `python tools/tts_drafts.py --engine parler` (needs a GPU).
- If Rhubarb is on PATH, lipsync JSON is generated. The placeholder mascot moves its mouth from the voice bus level either way.
- `content_lint.py --release` fails if any draft voice would ship.

## Anganwadi demo build

Built on top of Phase 2 for the CSR demo. **Done (dev rig):** D0 hardware profiles, D1
session orchestrator, D2 worker control + supervisor menu, D4 weekly themes + centre
profile, D8 privacy hardening + anonymous counts. The `kit` profile (AI HAT+ 2 / Hailo-10H,
IMX500 AI Camera) exists as config but is **untested until the kit arrives**
(`docs/model_matrix.md`).

### Session (D1)

One press of start runs `content/sessions/standard.yaml`: greet → Simon Says warm-up →
this week's theme → talk-back → cool-down → goodbye → idle "see you tomorrow" screen.
The session ends by itself. Step minutes scale to the centre's `session_minutes`.
A step whose game isn't built yet plays `fallback_game` (Simon Says). `content_lint`
lists these steps. Daily cap: `max_sessions_per_day` (2) and `max_minutes_per_day` (40).
When the cap is reached, start shows the mascot resting. The supervisor can lift the cap
for today. Each game opens with a 2.5 s title card (mr / hi / en) so everyone knows
what's starting.

### Start screen: Choose a game

The kit starts on **"Choose a game"** (centre profile `landing: picker`, the default).
Cards: **Today's session** (the fixed session above, daily cap applies), then one card per
built game. **Raise a hand onto a card and hold it there**: a gold ring fills around its
picture (1.5 s) and it starts. Only a raised hand counts (wrist above elbow), and moving
away drains the ring, so a child standing in front of a card doesn't pick it. (The pose
model has no finger points, so a fist/grab gesture isn't possible.) Single button:
press = next card, hold 2 s = start. After a game (or B during one) it comes back here;
after a session it shows "see you tomorrow" for 5 s, then comes back.
`landing: session` (supervisor menu → Start screen) gives the fixed-session idle screen
for the field instead. Free-play games count rounds and movement minutes, not sessions.
Planned: a "children choose" step inside the session.

While the button is held, a ring at the bottom of the screen fills: ▶ (release = next),
■ after 2 s (release = stop / OK), ☰ at 5 s (supervisor menu).

### Worker control

One button is enough. The **single button** can be the Space bar, a screen tap, a mouse
click, or the GPIO button when one is fitted. All four behave the same.

| Action | Presenter remote | Single button (Space / tap / click / GPIO) | In a session | In menus |
|---|---|---|---|---|
| next | Page Down | short press | start / next step | move down (PIN: digit +1) |
| prev | Page Up | | repeat the prompt | move up (PIN: digit −1) |
| select | F5 / Shift+F5 / Enter | | start / next step | OK |
| back | B / . / Esc | | stop (goodbye line) | back / close |
| long | | hold 2 s | stop | OK |
| supervisor | hold B 5 s, or tap B 5× | hold 5 s | open the menu (PIN) | |

GPIO: set `gpio_button.enabled: true` and `pin` in `vision/config.yaml` (button to GND).
Supervisor PIN: `supervisor_pin` in `content/centre_profile.yaml` (default `1234`:
change it per centre). Menu: week, language mode, main language, age group, session
length, children at a time*, AI-literacy games*, lift today's limit, usage counts, export
usage to USB, privacy screen, system status, choose a game (free play). First item:
Start screen (Choose a game / fixed session). (*stored only; those features
are not built yet.)

### Weeks and centre profile (D4)

`content/curriculum/weeks.yaml` has weeks 1–5 (demo default: week 3, farm animals).
**`aadharshila_ref` stays TODO until someone fills it from the actual Aadharshila
document.** `content/centre_profile.yaml` holds the per-centre defaults. Changes made in
the supervisor menu are saved on the device (`user://centre_profile.json`).
Every Marathi/Hindi line, week title and UI string is marked `reviewed: false`.
`python tools/content_lint.py --list-unreviewed` lists them, and `--release` fails until
a native speaker has reviewed them.

### Clock (RTC)

Daily caps and usage dates need the right date offline. Fit the Pi 5 RTC battery, cold-boot
with no network and check `timedatectl`. If the clock reads earlier than 2026, the app
still works: counters go to `date-unknown.json`, the cap counts since boot, and the status
screen says "date unknown".

## Privacy

- Everything runs on the device. No network clients other than the localhost vision socket.
- The service never stores frames, masks, audio or keypoints.
- Field builds (`TAKATAK_BUILD=field`, the default) refuse `record_session.py`,
  `record_clip.py` and `--video`. Field packages leave them out entirely and pin the build.
  The child-name clip feature is off.
- Usage counters (`/var/lib/takatak/usage/YYYY-MM.json`) hold counts only, nothing per child.
- Voice temp files (P5) go to `/run/takatak` (RAM).
- `tools/tests/test_privacy.py` builds a field package and checks all of the above.
  Details: `docs/data_policy.md`.
- `content/names/` and `content/voice/raw/` are gitignored.

## Not built yet

Demo build: D3 group play (slots/turns), D5 local-object model, D6 Marathi KWS,
D7 AI-literacy games, D9 USB pack loader / CEC / thermal soak, D10 demo mode and
picture cards, D11 dry run. Also the games the curriculum names:
catch_mango, animal_parade, call_response, story_calm, shape_match_lite, show_me_object.

Phase 2, P5 onward:

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
| Godot stuck on "Getting ready…" | Is `./run.sh vision` (or `mock`) running? Check `--vision=` (dev builds only) |
| Remote does nothing / keys ignored | Field build: only the worker buttons work. `TAKATAK_BUILD=dev` for tester keys |
| "Profile 'devrig' expects Hailo-8 but found …" | Set `hardware.profile` in `vision/config.yaml` to match the hardware |
| "Content not found" | `./run.sh content` (or `python tools/content_build.py`) |
| GDScript error on first run | Report the error from the Godot output. The scripts avoid `class_name`, so no editor import should be needed |
| Devanagari broken in Godot | `sudo apt install fonts-noto-core`; check with `./run.sh game --deva-test` |
| Model / Hailo / camera errors | Shown at the bottom of the game screen and in `./run.sh debug`; see `vision/tools/fetch_model.sh` |
| Hot Pi | `D` shows `temp_c`; above 80 °C the frame rate drops to 15 fps automatically |
