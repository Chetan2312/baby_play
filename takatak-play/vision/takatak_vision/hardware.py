"""Boot-time hardware detection for the status screen (hello.hardware).

Every probe fails soft: a missing tool or device gives None / [] and a friendly
error string, never an exception. Nothing here touches the network.
"""
import glob
import os
import re
import subprocess

ACCELERATORS = {"HAILO8L": "hailo8l", "HAILO8": "hailo8", "HAILO10H": "hailo10h", "HAILO10": "hailo10h"}
ACCEL_NAMES = {"hailo8": "Hailo-8 (AI HAT+ 26 TOPS)", "hailo8l": "Hailo-8L (AI HAT+ 13 TOPS)",
               "hailo10h": "Hailo-10H (AI HAT+ 2)", "openvino": "OpenVINO (Intel GPU)"}


def parse_identify(text):
    """'Device Architecture: HAILO8' (hailortcli fw-control identify) → 'hailo8'."""
    m = re.search(r"Device Architecture:\s*(\w+)", text or "")
    if not m:
        return None
    arch = m.group(1).upper()
    for key in sorted(ACCELERATORS, key=len, reverse=True):
        if arch.startswith(key):
            return ACCELERATORS[key]
    return arch.lower()


def detect_accelerator(timeout=4.0):
    """→ (arch or None, present). Run before the pose engine opens the device."""
    present = bool(glob.glob("/dev/hailo*"))
    if not present:
        return None, False
    try:
        out = subprocess.run(["hailortcli", "fw-control", "identify"], capture_output=True,
                             text=True, timeout=timeout)
        return parse_identify(out.stdout + out.stderr), True
    except (OSError, subprocess.TimeoutExpired):
        return None, True


def detect_openvino(device="GPU"):
    """→ (arch, present, device name). present = OpenVINO lists the profile's device."""
    try:
        import openvino as ov
        core = ov.Core()
        if device not in core.available_devices:
            return "openvino", False, None
        return "openvino", True, str(core.get_property(device, "FULL_DEVICE_NAME"))
    except Exception:  # noqa: BLE001 - not installed / driver missing
        return None, False, None


def camera_kind(model):
    """Sensor model name → our camera label."""
    m = str(model).lower()
    if "imx500" in m:
        return "imx500"
    if "noir" in m:
        return "noir"
    return "wide"


def parse_v4l2_nodes(sys_v4l="/sys/class/video4linux"):
    """Capture cameras from sysfs: one name per device (index 0; index 1 is the metadata node)."""
    names = []
    for node in sorted(glob.glob(os.path.join(sys_v4l, "video*"))):
        try:
            with open(os.path.join(node, "index")) as f:
                if f.read().strip() != "0":
                    continue
            with open(os.path.join(node, "name")) as f:
                names.append(f.read().strip())
        except OSError:
            continue
    return names


def detect_cameras(backend="picamera2"):
    if backend == "v4l2":
        return parse_v4l2_nodes()
    try:
        from picamera2 import Picamera2
        infos = Picamera2.global_camera_info()
    except Exception:  # noqa: BLE001 - not a Pi / libcamera missing
        return []
    return [str(i.get("Model", "?")) for i in infos]


def parse_asound_cards(text):
    """/proc/asound/cards → card names ('ReSpeaker Lite', 'vc4-hdmi-0', …)."""
    names = []
    for line in (text or "").splitlines():
        m = re.match(r"\s*\d+\s+\[[^\]]*\]:\s*(.*?)\s+-\s+(.*)", line)
        if m:
            names.append(m.group(2).strip())
    return names


def detect_audio():
    try:
        with open("/proc/asound/cards", encoding="utf-8") as f:
            cards = parse_asound_cards(f.read())
    except OSError:
        cards = []
    mic = any(("respeaker" in c.lower() or "usb" in c.lower()) for c in cards)
    return cards, mic


def network_state(sys_net="/sys/class/net"):
    """'offline' when no interface except loopback is up. Reads sysfs only."""
    try:
        ifaces = os.listdir(sys_net)
    except OSError:
        return "unknown"
    for iface in ifaces:
        if iface == "lo":
            continue
        try:
            with open(os.path.join(sys_net, iface, "operstate")) as f:
                if f.read().strip() == "up":
                    return "online"
        except OSError:
            continue
    return "offline"


def profile_errors(profile, arch, present, cameras):
    """Friendly messages for a profile/hardware mismatch (shown on the TV status line)."""
    errs = []
    want = profile["accelerator"]
    if want == "openvino":
        if not present:
            errs.append(f"Intel GPU not found by OpenVINO (expected {profile.get('device', 'GPU')}): "
                        "pose runs slowly on the CPU. Check intel-opencl-icd: clinfo -l")
        if not cameras:
            errs.append("No USB camera found. Check the cable: v4l2-ctl --list-devices")
        return errs
    if not present:
        errs.append(f"AI accelerator not found (expected {ACCEL_NAMES.get(want, want)}). "
                    "Check the AI HAT ribbon cable.")
    elif arch and arch != want:
        errs.append(f"Profile '{profile['name']}' expects {ACCEL_NAMES.get(want, want)} but found "
                    f"{ACCEL_NAMES.get(arch, arch)}: set hardware.profile in vision/config.yaml.")
    kinds = [camera_kind(c) for c in cameras]
    if cameras and not any(k in profile["cameras"] for k in kinds):
        errs.append(f"Profile '{profile['name']}' expects camera {'/'.join(profile['cameras'])}, "
                    f"found {', '.join(cameras)}.")
    return errs


def probe(cfg):
    """Full boot probe → hello.hardware dict (+ 'errors' list)."""
    prof = cfg["profile"]
    device_name = None
    if prof["accelerator"] == "openvino":
        arch, present, device_name = detect_openvino(prof.get("device", "GPU"))
    else:
        arch, present = detect_accelerator()
    cameras = detect_cameras(prof.get("camera_backend", "picamera2"))
    cards, mic = detect_audio()
    info = {
        "profile": prof["name"],
        "accelerator": arch,
        "accelerator_expected": prof["accelerator"],
        "accelerator_present": present,
        "accelerator_device": device_name,
        "model": cfg["model"],
        "cameras": cameras,
        "audio": cards,
        "mic": mic,
        "network": network_state(),
    }
    info["errors"] = profile_errors(prof, arch, present, cameras)
    if prof.get("model_note"):
        info["model_note"] = prof["model_note"]
    return info


def format_boot_log(info):
    return (f"[boot] profile={info['profile']} accelerator={info['accelerator'] or '-'}"
            f" (expected {info['accelerator_expected']}) cameras={info['cameras'] or '-'}"
            f" mic={'yes' if info['mic'] else 'no'} audio={info['audio'] or '-'} network={info['network']}")
