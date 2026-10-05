"""Vision service entry point: python -m takatak_vision.main [--profile kit] [--camera noir] [--video clip.mp4]"""
import argparse
import asyncio
import signal
import socket
import subprocess
import sys
import traceback

from . import build, hardware
from .config import PROFILES, load_config
from .lifecycle import Shutdown
from .pipeline import HardwareSource
from .server import VisionServer


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="Takatak vision service (WebSocket, no UI)")
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--profile", choices=PROFILES, help="override hardware.profile")
    ap.add_argument("--camera", choices=["wide", "noir", "imx500", "auto"])
    ap.add_argument("--port", type=int)
    ap.add_argument("--host")
    ap.add_argument("--video", help="DEV ONLY: recorded clip instead of the camera")
    return ap.parse_args(argv)


async def run(server):
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        loop.add_signal_handler(sig, stop.set)
    await server.serve(stop)


def port_in_use(host, port):
    with socket.socket() as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        try:
            s.bind((host, port))
        except OSError:
            return True
    return False


def other_instances():
    """PIDs of other running vision services (they hold the camera + Hailo)."""
    try:
        out = subprocess.run(["pgrep", "-f", r"^[^ ]*python[^ ]* -m takatak_vision\.main"],
                             capture_output=True, text=True)
    except OSError:
        return []
    import os
    mine = {os.getpid(), os.getppid()}
    return [int(p) for p in out.stdout.split() if int(p) not in mine]


def main(argv=None):
    args = parse_args(argv)
    if args.video:
        build.require_dev("--video")
    cfg = load_config(args.config, args.profile)
    if args.camera:
        cfg["camera"] = args.camera
    if args.port:
        cfg["server"]["port"] = args.port
    if args.host:
        cfg["server"]["host"] = args.host
    if cfg["privacy"]["save_frames"]:
        print("WARNING: privacy.save_frames is true; the service never saves frames anyway.")
    # Check before touching the camera/Hailo: a leftover instance holds both.
    host, port = cfg["server"]["host"], cfg["server"]["port"]
    if port_in_use(host, port):
        pids = other_instances()
        print(f"ERROR: port {port} is already in use"
              + (f" by another vision service (pid {', '.join(map(str, pids))})." if pids else "."))
        print("It also holds the camera and the Hailo AI HAT. Stop it first:")
        print("    pkill -INT -f takatak_vision.main")
        sys.exit(1)
    shutdown = Shutdown()  # second Ctrl+C / stuck cleanup → hard exit
    hw = hardware.probe(cfg)   # before the pose engine opens the Hailo device
    print(f"[boot] build={build.current()} model={cfg['model']} camera={cfg['camera']}")
    print(hardware.format_boot_log(hw))
    for e in hw["errors"] + ([hw["model_note"]] if hw.get("model_note") else []):
        print(f"[boot] {e}")
    source = HardwareSource(cfg, args.video, hw)
    source.start()
    code = 0
    try:
        asyncio.run(run(VisionServer(cfg, source)))
    except Exception:  # noqa: BLE001 - show it: shutdown() hard-exits and would hide it
        traceback.print_exc()
        code = 1
    finally:
        print("[exit] stopping camera / Hailo…", flush=True)
        shutdown.shutdown(source.stop, code=code)


if __name__ == "__main__":
    main()
