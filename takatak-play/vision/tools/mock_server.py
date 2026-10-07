#!/usr/bin/env python3
"""Mock vision server for Godot development without a Pi (or without a camera).

  python tools/mock_server.py                 # synthetic child; does what the game expects
  python tools/mock_server.py --auto          # child cycles through poses on its own
  python tools/mock_server.py --replay logs/sessions/x.jsonl   # replay a recorded session

Type into this terminal while it runs (synthetic mode):
  touch_nose | touch_head | touch_ear | hands_up | touch_tummy | touch_shoulders |
  touch_knees | clap | left_hand_up | neutral | away | back
  press | hold <seconds>     (GPIO worker button: hold 2 = stop, hold 5 = supervisor menu)
  left | right | middle      (step to that side of the screen: Ninja Dash lanes)
"""
import argparse
import asyncio
import os
import signal
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from takatak_vision.config import load_config  # noqa: E402
from takatak_vision.lifecycle import Shutdown  # noqa: E402
from takatak_vision.mock import MockPerformer, MockSource  # noqa: E402
from takatak_vision.server import VisionServer  # noqa: E402


def press_button(source, seconds):
    if source.on_button is None:
        return False
    source.on_button("down")
    time.sleep(seconds)
    source.on_button("up")
    return True


def stdin_commands(performer, source):
    for line in sys.stdin:
        cmd = line.strip()
        if not cmd:
            continue
        parts = cmd.split()
        if parts[0] in ("press", "hold"):
            try:
                secs = 0.2 if parts[0] == "press" else float(parts[1])
            except (IndexError, ValueError):
                print("[mock] usage: hold <seconds>", flush=True)
                continue
            ok = press_button(source, secs)
        else:
            ok = performer.command(cmd)
        print(f"[mock] {'ok' if ok else 'unknown command'}: {cmd}", flush=True)


async def run(server):
    stop = asyncio.Event()
    loop = asyncio.get_running_loop()
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        loop.add_signal_handler(sig, stop.set)
    await server.serve(stop)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int)
    ap.add_argument("--auto", action="store_true")
    ap.add_argument("--replay")
    ap.add_argument("--react", type=float, default=1.2, help="seconds before the child reacts")
    ap.add_argument("--hold", type=float, default=2.0, help="seconds the child holds a pose")
    args = ap.parse_args()
    cfg = load_config()
    cfg["server"]["host"] = args.host
    if args.port:
        cfg["server"]["port"] = args.port
    shutdown = Shutdown()
    performer = MockPerformer(args.react, args.hold, args.auto)
    source = MockSource(cfg, performer, args.replay)
    source.start()
    if not args.replay and sys.stdin.isatty():
        threading.Thread(target=stdin_commands, args=(performer, source), daemon=True).start()
        print(__doc__.split("Type into")[1].strip().replace("this terminal while it runs (synthetic mode):",
                                                            "Commands:"))
    try:
        asyncio.run(run(VisionServer(cfg, source)))
    finally:
        shutdown.shutdown(source.stop)


if __name__ == "__main__":
    main()
