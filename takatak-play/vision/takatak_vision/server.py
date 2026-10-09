"""WebSocket server (ws://127.0.0.1:8765). Survives game disconnects/reconnects.

Per client:
  - events (hello, gesture, status, no_player, button, pong, error) are queued and never dropped
  - pose messages and JPEG frames are latest-wins: a slow client just skips some
"""
import asyncio
import collections
import time

import websockets

from . import protocol as P


class Client:
    def __init__(self, ws):
        self.ws = ws
        self.sub = dict(P.SUBSCRIBE_DEFAULTS)
        self.events = collections.deque(maxlen=512)
        self.pose = None
        self.hands = None
        self.frame = None
        self.wake = asyncio.Event()

    def push(self, text):
        self.events.append(text)
        self.wake.set()

    def set_pose(self, text):
        self.pose = text
        self.wake.set()

    def set_hands(self, text):
        if self.sub.get("hands"):
            self.hands = text
            self.wake.set()

    def set_frame(self, data):
        if self.sub["frames"]:
            self.frame = data
            self.wake.set()

    async def writer(self):
        while True:
            await self.wake.wait()
            self.wake.clear()
            while self.events:
                await self.ws.send(self.events.popleft())
            if self.pose is not None:
                text, self.pose = self.pose, None
                await self.ws.send(text)
            if self.hands is not None:
                text, self.hands = self.hands, None
                await self.ws.send(text)
            if self.frame is not None:
                data, self.frame = self.frame, None
                await self.ws.send(data)


class VisionServer:
    def __init__(self, cfg, source):
        self.cfg = cfg["server"]
        self.source = source
        self.clients = set()
        self._last_no_player = 0.0
        self._loop = None

    # ---- connection ----
    async def handler(self, ws, *_):
        c = Client(ws)
        self.clients.add(c)
        print(f"[server] client connected ({len(self.clients)})")
        c.push(P.dumps(P.hello(self.source.camera_name, self.source.models, self.source.mic,
                               self.source.errors(), self.source.mirror,
                               getattr(self.source, "hardware", None))))
        self._update_frames_wanted()
        writer = asyncio.create_task(c.writer())
        try:
            async for raw in ws:
                if isinstance(raw, bytes):
                    continue
                try:
                    self.handle(c, P.parse_client(raw))
                except P.ProtocolError as e:
                    c.push(P.dumps(P.error(e)))
        except websockets.ConnectionClosed:
            pass
        finally:
            writer.cancel()
            self.clients.discard(c)
            self._update_frames_wanted()
            print(f"[server] client disconnected ({len(self.clients)})")

    def handle(self, c, m):
        t = m["t"]
        if t == "subscribe":
            c.sub = {k: m[k] for k in P.SUBSCRIBE_DEFAULTS}
            if not c.sub["frames"]:
                c.frame = None
            if not c.sub["hands"]:
                c.hands = None
            self._update_frames_wanted()
        elif t == "set_players":
            self.source.set_players(m["mode"])
        elif t == "set_camera":
            self.source.set_camera(m["camera"])
        elif t == "set_rotation" and hasattr(self.source, "set_rotation"):
            self.source.set_rotation(m["rotation"])
        elif t == "set_difficulty":
            self.source.set_difficulty(m["difficulty"])
        elif t == "mock_expect":
            self.source.mock_expect(m["name"])
        elif t == "ping":
            c.push(P.dumps(P.pong()))
        elif t in ("mic_listen_start", "mic_listen_stop"):
            c.push(P.dumps(P.error("microphone not available yet (Phase P5)")))

    def _broadcast(self, text):
        for c in self.clients:
            c.push(text)

    def button_threadsafe(self, state):
        """Called from the GPIO thread: forward a button edge to every game client."""
        if self._loop is not None:
            self._loop.call_soon_threadsafe(self._broadcast, P.dumps(P.button(state)))

    def _update_frames_wanted(self):
        self.source.set_frames_wanted(any(c.sub["frames"] for c in self.clients))
        if hasattr(self.source, "set_hands_wanted"):
            self.source.set_hands_wanted(any(c.sub.get("hands") for c in self.clients))

    # ---- pumps ----
    async def pump_results(self):
        seq = 0
        while True:
            seq, res = await asyncio.to_thread(self.source.results.wait_newer, seq, 0.25)
            if res is None or not self.clients:
                continue
            pose_txt = P.dumps(res.pose_msg)
            ev_txt = [P.dumps(e) for e in res.events]
            np_txt = None
            if res.no_player_s >= self.cfg["no_player_after_s"]:
                now = time.monotonic()
                if now - self._last_no_player >= self.cfg["no_player_every_s"]:
                    self._last_no_player = now
                    secs = res.no_player_s if res.no_player_s != float("inf") else 9999.0
                    np_txt = P.dumps(P.no_player(secs))
            for c in self.clients:
                for e in ev_txt:
                    c.push(e)
                if np_txt:
                    c.push(np_txt)
                c.set_pose(pose_txt)

    async def pump_frames(self):
        seq = 0
        while True:
            seq, item = await asyncio.to_thread(self.source.frames.wait_newer, seq, 0.25)
            if item is None or not self.clients:
                continue
            frame_id, jpg = item
            data = P.pack_binary(P.KIND_FRAME, frame_id, jpg)
            for c in self.clients:
                c.set_frame(data)

    async def pump_hands(self):
        slot = getattr(self.source, "hands_results", None)
        if slot is None:
            return
        seq = 0
        while True:
            seq, msg = await asyncio.to_thread(slot.wait_newer, seq, 0.25)
            if msg is None or not self.clients:
                continue
            text = P.dumps(msg)
            for c in self.clients:
                c.set_hands(text)

    async def pump_status(self):
        while True:
            await asyncio.sleep(self.cfg["status_every_s"])
            temp = self.source.tick()
            if self.clients:
                lat = self.source.perf.latencies() if hasattr(self.source.perf, "latencies") else None
                txt = P.dumps(P.status(self.source.perf.fps(), temp, self.source.errors(),
                                       self.source.camera_name, lat, getattr(self.source, "rotation", "normal"),
                                       getattr(self.source, "frame_size", None)))
                for c in self.clients:
                    c.push(txt)

    async def serve(self, stop_event=None, ready=None):
        host, port = self.cfg["host"], self.cfg["port"]
        self._loop = asyncio.get_running_loop()
        self.source.on_button = self.button_threadsafe
        async with websockets.serve(self.handler, host, port, max_size=2 ** 22,
                                    ping_interval=5, ping_timeout=10):
            print(f"[server] listening on ws://{host}:{port}")
            if ready is not None:
                ready.set()
            tasks = [asyncio.create_task(x()) for x in
                     (self.pump_results, self.pump_frames, self.pump_hands, self.pump_status)]
            try:
                if stop_event is None:
                    await asyncio.Future()
                else:
                    await stop_event.wait()
            finally:
                for t in tasks:
                    t.cancel()
