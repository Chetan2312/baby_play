"""Voice clips + sound effects over pygame.mixer (HDMI audio in Demo 1).

Lookup order for a voice clip: assets/audio/<lang>/<id>.wav (real recording)
→ assets/audio_placeholder/<lang>/<id>.wav (espeak-ng). SFX: assets/sfx/<name>.wav
→ assets/audio_placeholder/sfx/<name>.wav. A missing file is skipped, never fatal.
"""
import os
from collections import deque

import pygame

from .config import path as project_path


class AudioPlayer:
    def __init__(self, cfg):
        self.acfg = cfg["audio"]
        self.paths = cfg["paths"]
        self.gap_s = self.acfg["language_gap_s"]
        self.error = None
        self.enabled = False
        self._sounds = {}
        self._missing = set()
        self.queue = deque()
        self._playing = False
        self._gap_until = 0.0
        try:
            if not pygame.mixer.get_init():
                pygame.mixer.init(self.acfg["frequency"], -16, 2, self.acfg["buffer"])
            pygame.mixer.set_num_channels(8)
            self.voice = pygame.mixer.Channel(0)
            self.fx = pygame.mixer.Channel(1)
            self.voice.set_volume(self.acfg["voice_volume"])
            self.fx.set_volume(self.acfg["sfx_volume"])
            self.enabled = True
        except pygame.error as e:
            self.error = f"Audio disabled: {e}"

    def _load(self, candidates):
        for c in candidates:
            p = project_path(c)
            if p in self._sounds:
                return self._sounds[p]
            if os.path.exists(p):
                try:
                    snd = pygame.mixer.Sound(p)
                except pygame.error as e:
                    print(f"[audio] cannot load {p}: {e}")
                    continue
                self._sounds[p] = snd
                return snd
        key = candidates[0]
        if key not in self._missing:
            self._missing.add(key)
            print(f"[audio] missing clip: {key} (run tools/make_placeholder_audio.py)")
        return None

    def voice_clip(self, lang, clip_id):
        return self._load([os.path.join(self.paths["audio"], lang, f"{clip_id}.wav"),
                           os.path.join(self.paths["audio_placeholder"], lang, f"{clip_id}.wav")])

    def say(self, clips, langs, interrupt=False):
        """Speak each clip in each language, e.g. prompt in mr, hi, en."""
        if not self.enabled:
            return
        if interrupt:
            self.queue.clear()
            self.voice.stop()
            self._playing = False
        for lang in langs:
            for clip_id in clips:
                self.queue.append((lang, clip_id))

    def sfx(self, name):
        if not self.enabled:
            return
        snd = self._load([os.path.join(self.paths["sfx"], f"{name}.wav"),
                          os.path.join(self.paths["audio_placeholder"], "sfx", f"{name}.wav")])
        if snd:
            self.fx.play(snd)

    def handle(self, events):
        for e in events:
            if e.kind == "say":
                self.say(e.clips, e.langs, e.interrupt)
            elif e.kind == "sfx":
                for c in e.clips:
                    self.sfx(c)

    def update(self, now):
        if not self.enabled:
            return
        if self._playing and not self.voice.get_busy():
            self._playing = False
            self._gap_until = now + self.gap_s
        while not self._playing and self.queue and now >= self._gap_until:
            lang, clip_id = self.queue.popleft()
            snd = self.voice_clip(lang, clip_id)
            if snd:
                self.voice.play(snd)
                self._playing = True

    @property
    def busy(self):
        return self.enabled and (self._playing or bool(self.queue))

    def stop(self):
        if self.enabled:
            self.queue.clear()
            pygame.mixer.stop()
