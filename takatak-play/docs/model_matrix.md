# Model matrix

HEF files are compiled for one accelerator. **A Hailo-8 HEF does not run on the Hailo-10H,
and the reverse is also true.** Each hardware profile (`hardware.profile` in
`vision/config.yaml`) loads models from its own folder:

| Profile | Board | Accelerator | Camera | Models folder |
|---|---|---|---|---|
| `devrig` | Pi 5 8 GB | AI HAT+ 26 TOPS (**Hailo-8**) | CM3 Wide (+ CM3 NoIR) | `vision/models/hailo8/` |
| `kit` | Pi 5 16 GB | AI HAT+ 2 (**Hailo-10H**) | Raspberry Pi AI Camera (IMX500) | `vision/models/hailo10h/` |

`vision/tools/fetch_model.sh` fills the folder (`PROFILE=kit` for the kit). The status
screen and the vision service's boot log show the profile, the expected accelerator and
the one actually found. A mismatch appears as an on-screen error, not a crash.

## Models needed for the demo

Status as of 2026-10-05. The kit hardware is **not in hand yet**, so nothing in the
Hailo-10H column has been tested. Fill in each cell once it is checked against the HailoRT
version installed on the kit (`hailortcli --version`) and the Hailo Model Zoo release for it.

| Model | Used for | Hailo-8 (devrig) | Hailo-10H (kit) | Notes |
|---|---|---|---|---|
| `yolov8s_pose` | Pose, every game | ✅ Model Zoo precompiled; running on the dev rig | ❓ Not checked yet: look for a precompiled hailo10h build | D0 needs ≥ 20 fps on the Hailo-10H |
| Segmentation (cutout) | Phase P6 cutout effect | not used yet | ❓ | Out of demo scope; thermal fallback disables it |
| `local_crops_v1` (custom detector) | `show_me_object` (D5) | ❓ compile with the Hailo DFC | ❓ compile with the Hailo DFC | Trained in-house, see `docs/data_policy.md` |
| Marathi KWS | `call_response` (D6) | — | — | Probably runs on the CPU, not the Hailo; decide in D6 |

Gaps to close (D0):

1. Check the Model Zoo for a precompiled `yolov8s_pose` for **hailo10h** that matches the
   kit's HailoRT. If none exists, compile one with the Dataflow Compiler. Record the source
   URL / zoo version and the HailoRT version here.
2. Measure pose fps on the kit (status screen, or `./run.sh debug`). Target ≥ 20 fps.
3. Check that `picamera2.devices.Hailo` (used by `pose.py`) supports the Hailo-10H on the
   installed stack. If it doesn't, `PoseEngine` needs a HailoRT path for that profile.

## Per-class accuracy (D5, custom object model)

Held-out set photographed in a **different room** from the training set. Demo threshold:
≥ 90 % top-1. Classes below the threshold are dropped from the demo.

| Class | Held-out images | Top-1 (Hailo-8) | Top-1 (Hailo-10H) | In demo? |
|---|---|---|---|---|
| (not trained yet) | | | | |

## IMX500 AI Camera: on-sensor inference (later)

The IMX500 can run a small network on the sensor itself. **For the demo it is a plain
camera feeding frames to the Hailo-10H** (one pipeline, same code as the dev rig). Moving a
model onto the sensor (for example person detection, to wake the system or pre-crop) is a
later optimisation. Before doing it, check:

- which networks the IMX500 packager can convert and their input size limits;
- whether loading on-sensor firmware changes the frame rate or the ISP output that
  `camera.py` relies on (`main` XBGR8888 + `lores` RGB888);
- that frames still never leave the device (privacy is unchanged: nothing is stored).

Until the kit arrives, the IMX500 path is limited to the camera matching in `camera.py`
(`imx500` in the sensor model name) and the `kit` profile. Both are untested.
