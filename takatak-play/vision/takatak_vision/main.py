"""Vision service entry point: python -m takatak_vision.main [--camera noir] [--video clip.mp4]"""
import argparse
import asyncio
import signal

from .config import load_config
from .lifecycle import Shutdown
from .pipeline import HardwareSource
from .server import VisionServer


def parse_args(argv=None):
    ap = argparse.ArgumentParser(description="Takatak vision service (WebSocket, no UI)")
    ap.add_argument("--config", default="config.yaml")
    ap.add_argument("--camera", choices=["wide", "noir", "auto"])
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


def main(argv=None):
    args = parse_args(argv)
    cfg = load_config(args.config)
    if args.camera:
        cfg["camera"] = args.camera
    if args.port:
        cfg["server"]["port"] = args.port
    if args.host:
        cfg["server"]["host"] = args.host
    if cfg["privacy"]["save_frames"]:
        print("WARNING: privacy.save_frames is true; the service never saves frames anyway.")
    shutdown = Shutdown()  # second Ctrl+C / stuck cleanup → hard exit
    source = HardwareSource(cfg, args.video)
    source.start()
    try:
        asyncio.run(run(VisionServer(cfg, source)))
    finally:
        print("[exit] stopping camera / Hailo…", flush=True)
        shutdown.shutdown(source.stop)


if __name__ == "__main__":
    main()
