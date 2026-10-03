# Takatak Play — Demo 1: Simon Says, Body Parts (trilingual)

A big-screen motion game for kids aged 2–7. A Raspberry Pi 5 drives a TV or
projector over HDMI. A camera faces the kids, pose estimation runs on the
Hailo-8 AI HAT, and the game speaks prompts in Marathi, Hindi and English
("नाकाला हात लाव!" / "अपनी नाक छुओ!" / "Touch your nose!"). When the child
does it, the screen celebrates.

This folder is independent of the Takatak web app (`../files`).

## Hardware

- Raspberry Pi 5 (8 GB) with active cooler.
- AI HAT+ 26 TOPS (Hailo-8).
- Camera Module 3 **Wide** on CAM0, for TV and lit rooms.
- Camera Module 3 **NoIR** on CAM1 with an 850 nm IR illuminator, for projector and dark rooms.
- TV or projector over HDMI. Audio also goes out over HDMI.

The code matches cameras by sensor name (`imx708_wide` vs `*_noir`), so port
order doesn't matter. `camera_index` in `config.yaml` is only a fallback.

**Mounting.** Put the camera 0.9–1.2 m high, directly above or below the
screen, and keep it out of the projector beam. The play zone is 1.5–3 m away:
mark it with tape as the "magic mat". For the knee prompts, the child must be
in frame from head to knees.

## Setup on the Pi

```bash
git clone <repo> && cd baby_play && git checkout feature/gameplay
cd takatak-play
./install.sh                 # options: --full-upgrade  --pcie-gen3  --skip-apt
sudo reboot                  # only needed after the first Hailo install
```

`install.sh` does the following:

1. Installs the system packages from **apt**: `hailo-all`, `python3-picamera2`,
   `python3-opencv`, `python3-pygame`, the Noto fonts, `libraqm0`, `espeak-ng`
   and `ffmpeg`. These can't go into a venv because the Hailo kernel driver,
   firmware and libcamera bindings are system-level. It does **not** run
   `full-upgrade` unless you ask.
2. Creates the **`.env` venv** (with `--system-site-packages`, so it sees
   picamera2 and Hailo) and pip-installs only `pyyaml` and `pytest` into it.
   Everything else Python-only stays in `.env`.
3. Fetches `models/yolov8s_pose.hef` for **Hailo-8**, not 8L
   (`tools/fetch_model.sh`). It checks `/usr/share/hailo-models` first, then
   downloads from the Hailo Model Zoo version that matches your HailoRT. To
   use a specific URL instead:
   `HEF_URL=https://… tools/fetch_model.sh`.
4. Generates placeholder voices and sound effects into `assets/audio_placeholder/`.
5. Runs a self-check (imports, raqm, camera list, `hailortcli identify`) and
   then the unit tests.

`--pcie-gen3` adds `dtparam=pciex1_gen=3` to `/boot/firmware/config.txt` (it
backs the file up first). It's recommended for the AI HAT.

**HDMI audio:** pick the HDMI output in the desktop's volume menu (or run
`raspi-config` → System → Audio).

## Running

All commands run inside `.env`. They work from the Pi desktop or over SSH; over
SSH, `run.sh` attaches to the TV's desktop session.

| Command | What it does | Milestone |
|---|---|---|
| `./run.sh check` | `hailortcli identify` and the camera list | M0 |
| `./run.sh debug` | Live mirrored feed with skeleton, keypoint indices, fps, every gesture check and the neutral flag | M1 / M3 |
| `./run.sh text` | Devanagari shaping and voice clips over HDMI; also writes `logs/text_check.png` | M2 |
| `./run.sh test` | `pytest`: gestures, post-processing, tracker, game flow | M3 |
| `./run.sh` | The game | M4+ |
| `./run.sh --camera noir --difficulty kid --rounds 5 --windowed` | The game with overrides | |

**Game keys:** `Space` skip · `S` skeleton · `L` language mode (all → single → rotate) ·
`C` switch camera (wide ↔ noir) · `D` fps/debug overlay · `Esc` quit.

**Debug keys:** `C` switch camera · `T` toggle toddler/kid tolerances · `I` keypoint indices · `Esc` quit.

## Layout

```
config.yaml               every threshold and tunable
main.py                   entry point and wiring (3 threads: camera → inference → UI)
takatak/
  camera.py               Picamera2 dual stream: main 1280x720 XBGR → display; lores 640x360 → inference
  pose.py                 Hailo inference thread, letterbox 640x360 → 640x640
  postprocess.py          YOLOv8-pose decode + NMS (pure numpy; outputs matched by shape)
  player.py               active player (largest/center), sticky tracking, EMA, face-keypoint memory
  gestures.py             pure gesture checks normalised by shoulder width
  poses.py                synthetic poses (test fixtures and the HINT stick figure)
  game.py                 state machine (no pygame, unit-tested)
  ui.py                   pygame drawing: mirrored feed, glow, banners, stars, ring, trophy
  text.py                 Pillow + raqm text → pygame surfaces (correct Devanagari)
  audio.py                voice queue (mr → hi → en) and sfx; recorded clips win over placeholders
  stats.py                session JSON (prompt ids and outcomes only)
  perf.py                 cam/inf/ui fps and latency → logs/perf.log every 5 s
content/prompts.yaml      trilingual prompts (DRAFT text: needs native review)
content/lines.yaml        greeting, come-back, hint, next, finish
tools/                    pose_debug, text_audio_check, make_placeholder_audio, fetch_model.sh, record_test_clip
tests/                    pytest suites (run on any machine, no hardware needed)
```

## Game flow

```
ATTRACT ─(person 1 s)→ GREETING → ROUND_INTRO ─(1 s)→ LISTENING ─(hold 6 frames)→ CELEBRATE → next round
                                                     LISTENING ─(8 s silence)→ HINT (stick figure + replay) → LISTENING → move on gently
nobody for 3 s → PAUSED ("Come to the magic mat!") → resumes the same prompt | 60 s → ATTRACT
after N rounds → FINISH (trophy, "You did 8!") → ATTRACT
```

- There is no failure language and no red: a timeout gives a gentle hint, then the game moves on.
- The prompt timer only runs while no voice clip is playing, so the three languages don't eat into it.
- The next check is armed only after a neutral pose (hands down) or after `rearm_gap_s`, so the previous pose can't trigger the next prompt.
- When a hand covers the face, the face keypoints are held for 0.5 s. This stops the nose/ear checks from dropping out at the moment of success.

## Tuning

- Each difficulty has its own tolerances in `config.yaml → gestures.toddler / kid`. They are in units of shoulder width.
- Use `./run.sh debug` with `T` to watch the scores live against both sets.
- To build a dev-only clip set for offline tuning:
  `./run.sh record --i-have-consent --seconds 20`, then
  `./run.sh debug --video logs/clips/<file>.mp4`.
- Swap in real voices by dropping `assets/audio/<lang>/<id>.wav` files (ids
  come from `prompts.yaml` and `lines.yaml`). They take priority over the
  placeholders. SFX go in `assets/sfx/{success,try_again,start}.wav`.

## Privacy

- Everything runs on the device. The game makes no network calls.
- The game **never** saves frames. `privacy.save_frames` stays `false`.
- `logs/stats/*.json` holds only timestamps, prompt ids, outcomes, time-to-success and the language mode.
- `tools/record_test_clip.py` is dev-only. It requires `--i-have-consent`,
  prints a warning, and writes to the gitignored `logs/clips/`.

## Troubleshooting

| Symptom | Fix |
|---|---|
| On-screen "Model not found" | `tools/fetch_model.sh`, or copy a Hailo-8 `yolov8s_pose.hef` to `models/` |
| "Hailo could not load the model" | Run `hailortcli fw-control identify`; check the HEF is for Hailo-8 (`hailortcli parse-hef`) and matches your HailoRT version |
| "HEF outputs don't look like yolov8 pose" | You have a different model or an NMS-on-chip build: use the Model Zoo `yolov8s_pose` |
| "'noir' camera not found" | Run `rpicam-hello --list-cameras`; check the ribbon cable |
| Devanagari looks broken (detached matras) | `sudo apt install libraqm0`; `./run.sh text` should show `raqm=OK` |
| No sound | Select HDMI as the output device; check `./run.sh text` |
| Window doesn't appear over SSH | Log in to the desktop on the TV first; `run.sh` attaches to it |
| Low fps | Use `D` to see cam/inf/ui fps; try `--pcie-gen3`; lower `camera_opts.main_size` |

See [docs/field_test_log.md](docs/field_test_log.md) for the per-session field-test template (M5–M7).
