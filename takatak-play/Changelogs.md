# Changelog

## v0.3.0 — 2026-11-03 · Takatak Play runs on the Intel N150 mini PC

Takatak Play now runs on an Intel N150 mini PC (Ubuntu 24.04) with a normal USB webcam,
as well as on the Raspberry Pi. The Pi setups (`devrig`, `kit`) work exactly as before.

### New

- **N150 support.** A new `n150` hardware profile. Turn it on with
  `TAKATAK_PROFILE=n150 ./run.sh play`. Without it, everything behaves as on the Pi.
- **USB webcam.** The game can now use a plain USB camera (tested with an Arducam 16MP).
  It finds the camera by itself, skips the odd broken frame and comes back on its own
  if the cable is pulled out and plugged in again.
- **Body tracking on the Intel graphics chip.** The N150 has no AI accelerator, so body
  tracking now runs on its built-in graphics through OpenVINO. If the graphics driver
  isn't working, it falls back to the processor (slower) and says so on the status screen.
- **Point with your finger on "Choose a game".** The cursor now follows the tip of your
  index finger instead of your palm, so picking a game feels natural. If hand tracking
  isn't available, it falls back to the wrist like before.

### Fixed

- **Picture too dark.** We tuned the camera's brightness, gamma, colour and backlight
  settings for the room, so children in front of a bright window don't turn into dark
  shapes. One camera setting that made the picture almost black was removed.
- **Picture upside down.** On the N150 the camera picture is no longer flipped (the Pi rig
  mounts its camera upside down; the N150 doesn't).
- **Wrong temperature reading.** On a PC the service now reads the real CPU temperature
  instead of a board sensor, so overheat protection works properly.
- **Friendlier messages.** On the N150, error messages talk about the USB camera and the
  graphics driver instead of the Pi's AI HAT.

### How it performs on the N150

| | Result |
|---|---|
| Camera | about 27 frames per second |
| Body tracking | about 25 per second |
| Delay from camera to tracking | about 50 ms |
| Finger tracking | about 20 per second |

### Setting up an N150 (one time)

1. Install Intel's newer graphics driver (Ubuntu's own one doesn't know the N150 yet):
   `sudo add-apt-repository ppa:kobuk-team/intel-graphics`, then
   `sudo apt install libze-intel-gpu1 libze1 intel-opencl-icd clinfo`.
2. Install the Python packages:
   `.env/bin/pip install -r vision/requirements-pc.txt -r vision/requirements-hands.txt`.
3. Download the hand models: `vision/tools/fetch_hand_model.sh`.
4. Put the body-tracking model in `vision/models/openvino/` (it is not stored in git).
5. Check everything with `TAKATAK_PROFILE=n150 ./run.sh check`, then play.

### Still to do

- A script to download the body-tracking model, like the hand models.
