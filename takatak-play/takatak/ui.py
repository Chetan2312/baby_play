"""pygame drawing: mirrored camera feed, overlays, effects, game screens.

Coordinates from pose are in lores-frame pixels; Renderer.to_screen() maps
them onto the (cover-scaled, optionally mirrored) feed. Mirroring flips the
image and x-coordinates only. Keypoint L/R labels stay the person's own.
"""
import math
import random

import pygame

from . import gestures as G
from . import poses
from .game import State

WHITE = (255, 255, 255)
GOLD = (255, 205, 40)
SKY = (90, 200, 255)
PINK = (255, 110, 180)
GREEN = (120, 230, 120)
ORANGE = (255, 150, 60)
BG = (18, 22, 48)
LANG_COLORS = {"mr": (255, 225, 90), "hi": (140, 230, 255), "en": WHITE}
STAR_COLORS = [GOLD, PINK, SKY, GREEN, ORANGE, WHITE]


def open_display(dcfg):
    size = (dcfg["width"], dcfg["height"])
    if dcfg["fullscreen"]:
        for flags in (pygame.FULLSCREEN | pygame.SCALED, pygame.FULLSCREEN):
            try:
                screen = pygame.display.set_mode(size, flags, vsync=1)
                break
            except (pygame.error, TypeError):
                continue
        else:
            screen = pygame.display.set_mode(size, pygame.FULLSCREEN)
        pygame.mouse.set_visible(False)
    else:
        screen = pygame.display.set_mode(size)
    pygame.display.set_caption("Takatak Play")
    return screen


def star_points(cx, cy, r, rot=0.0, inner=0.45):
    pts = []
    for i in range(10):
        rr = r if i % 2 == 0 else r * inner
        a = rot + i * math.pi / 5 - math.pi / 2
        pts.append((cx + rr * math.cos(a), cy + rr * math.sin(a)))
    return pts


class Particles:
    def __init__(self):
        self.items = []

    def burst(self, x, y, n, scale, speed=900):
        for _ in range(n):
            a = random.uniform(0, 2 * math.pi)
            v = random.uniform(0.3, 1.0) * speed * scale
            self.items.append([x, y, math.cos(a) * v, math.sin(a) * v - 300 * scale,
                               random.uniform(1.2, 2.2), random.uniform(18, 40) * scale,
                               random.choice(STAR_COLORS), random.uniform(0, 6.28),
                               random.uniform(-4, 4)])

    def rain(self, w, n, scale):
        for _ in range(n):
            self.items.append([random.uniform(0, w), -40, random.uniform(-60, 60) * scale,
                               random.uniform(150, 400) * scale, 4.0,
                               random.uniform(14, 30) * scale, random.choice(STAR_COLORS),
                               random.uniform(0, 6.28), random.uniform(-3, 3)])

    def update(self, dt, gravity):
        alive = []
        for p in self.items:
            p[0] += p[2] * dt
            p[1] += p[3] * dt
            p[3] += gravity * dt
            p[4] -= dt
            p[7] += p[8] * dt
            if p[4] > 0:
                alive.append(p)
        self.items = alive

    def draw(self, surf):
        for x, y, _, _, life, size, color, rot, _ in self.items:
            r = size * min(1.0, life * 2)
            if r > 2:
                pygame.draw.polygon(surf, color, star_points(x, y, r, rot))


class Renderer:
    def __init__(self, screen, text, dcfg):
        self.screen = screen
        self.text = text
        self.mirror = dcfg["mirror"]
        self.W, self.H = screen.get_size()
        self.u = self.H / 1080.0
        self._feed = None
        self._map = None   # (ox, oy, dw, dh, lores_w, lores_h)
        self._panels = {}

    # ---- camera feed -----------------------------------------------------
    def draw_feed(self, bundle):
        if bundle is None:
            self.screen.fill(BG)
            self._map = None
            return
        main = bundle.main
        h, w = main.shape[:2]
        src = pygame.image.frombuffer(main, (w, h), "RGBX")
        if self.mirror:
            src = pygame.transform.flip(src, True, False)
        s = max(self.W / w, self.H / h)
        dw, dh = int(w * s + 0.5), int(h * s + 0.5)
        if self._feed is None or self._feed.get_size() != (dw, dh):
            self._feed = pygame.Surface((dw, dh), 0, src)
        if (dw, dh) == (w, h):
            self._feed.blit(src, (0, 0))
        else:
            pygame.transform.scale(src, (dw, dh), self._feed)
        ox, oy = (self.W - dw) // 2, (self.H - dh) // 2
        self.screen.blit(self._feed, (ox, oy))
        lh, lw = bundle.lores.shape[:2]
        self._map = (ox, oy, dw, dh, lw, lh)

    def to_screen(self, x, y):
        ox, oy, dw, dh, lw, lh = self._map
        sx = x * dw / lw
        if self.mirror:
            sx = dw - sx
        return int(ox + sx), int(oy + y * dh / lh)

    def bbox_to_screen(self, b):
        x1, y1 = self.to_screen(b[0], b[1])
        x2, y2 = self.to_screen(b[2], b[3])
        return pygame.Rect(min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1))

    # ---- overlays --------------------------------------------------------
    def panel(self, rect, alpha=150, color=(0, 0, 0)):
        rect = pygame.Rect(rect)
        key = (rect.size, alpha, color)
        surf = self._panels.get(key)
        if surf is None:
            surf = pygame.Surface(rect.size, pygame.SRCALPHA)
            pygame.draw.rect(surf, color + (alpha,), surf.get_rect(),
                             border_radius=int(28 * self.u))
            self._panels[key] = surf
        self.screen.blit(surf, rect.topleft)

    def draw_skeleton(self, kp, min_conf, labels=False):
        if self._map is None:
            return
        u = self.u
        for a, b in G.SKELETON:
            if kp[a, 2] >= min_conf and kp[b, 2] >= min_conf:
                color = SKY if a in G.LEFT_SIDE and b in G.LEFT_SIDE else (
                    ORANGE if a not in G.LEFT_SIDE and b not in G.LEFT_SIDE else WHITE)
                pygame.draw.line(self.screen, color, self.to_screen(*kp[a, :2]),
                                 self.to_screen(*kp[b, :2]), max(2, int(6 * u)))
        for i in range(17):
            if kp[i, 2] >= min_conf:
                p = self.to_screen(*kp[i, :2])
                pygame.draw.circle(self.screen, GOLD, p, max(3, int(9 * u)))
                if labels:
                    self.screen.blit(self.text.render(f"{i}", 26 * u), (p[0] + 8, p[1] - 14))

    def draw_glow(self, bbox, t):
        if self._map is None:
            return
        r = self.bbox_to_screen(bbox).inflate(int(40 * self.u), int(40 * self.u))
        pulse = 0.5 + 0.5 * math.sin(t * 4)
        for i, c in enumerate([(255, 240, 150), (255, 210, 80), (255, 170, 40)]):
            w = max(2, int((10 - i * 3 + pulse * 4) * self.u))
            pygame.draw.rect(self.screen, c, r.inflate(i * 14, i * 14), w,
                             border_radius=int(40 * self.u))

    def text_lines(self, lines, center_y, gap=10, panel_alpha=150, max_w=None):
        """lines: [(text, size, color, lang)] stacked, centred horizontally."""
        surfs = [self.text.render(t, s, c, lang=lang) for t, s, c, lang in lines]
        if not surfs:
            return
        gap = int(gap * self.u)
        total_h = sum(s.get_height() for s in surfs) + gap * (len(surfs) - 1)
        width = max(s.get_width() for s in surfs)
        if panel_alpha:
            pad = int(30 * self.u)
            rect = pygame.Rect(0, 0, min(self.W - 20, width + 2 * pad), total_h + 2 * pad)
            rect.center = (self.W // 2, center_y)
            self.panel(rect, panel_alpha)
        y = center_y - total_h // 2
        for s in surfs:
            self.screen.blit(s, (self.W // 2 - s.get_width() // 2, y))
            y += s.get_height() + gap

    def progress_ring(self, center, radius, frac, color=GOLD):
        n = 48
        r = max(4, int(10 * self.u))
        for i in range(n):
            a = -math.pi / 2 + 2 * math.pi * i / n
            p = (center[0] + radius * math.cos(a), center[1] + radius * math.sin(a))
            on = i < frac * n
            pygame.draw.circle(self.screen, color if on else (80, 80, 110), p, r if on else r // 2)

    def trophy(self, cx, cy, s):
        cup = [(cx - 110 * s, cy - 120 * s), (cx + 110 * s, cy - 120 * s),
               (cx + 85 * s, cy + 10 * s), (cx + 30 * s, cy + 50 * s),
               (cx - 30 * s, cy + 50 * s), (cx - 85 * s, cy + 10 * s)]
        for side in (-1, 1):
            pygame.draw.circle(self.screen, GOLD, (cx + side * 120 * s, cy - 60 * s),
                               int(50 * s), int(16 * s))
        pygame.draw.polygon(self.screen, GOLD, cup)
        pygame.draw.rect(self.screen, GOLD, (cx - 18 * s, cy + 45 * s, 36 * s, 60 * s))
        pygame.draw.rect(self.screen, (200, 140, 20), (cx - 80 * s, cy + 100 * s, 160 * s, 40 * s),
                         border_radius=int(10 * s))
        pygame.draw.polygon(self.screen, WHITE, star_points(cx, cy - 50 * s, 45 * s))

    def stick_figure(self, kp, rect, highlight=()):
        """Draw a pose (lores-like pixel coords) scaled into rect, mirrored like the feed."""
        xs, ys = kp[:, 0], kp[:, 1]
        x0, x1, y0, y1 = xs.min() - 40, xs.max() + 40, ys.min() - 50, ys.max() + 20
        s = min(rect.w / (x1 - x0), rect.h / (y1 - y0))
        cx = rect.centerx

        def P(i):
            x = (kp[i, 0] - (x0 + x1) / 2) * s
            if self.mirror:
                x = -x
            return int(cx + x), int(rect.y + (kp[i, 1] - y0) * s)

        lw = max(4, int(14 * s))
        for a, b in G.SKELETON:
            if a in G.FACE or b in G.FACE:
                continue
            pygame.draw.line(self.screen, WHITE, P(a), P(b), lw)
        pygame.draw.line(self.screen, WHITE, P(G.NOSE),
                         ((P(G.L_SHOULDER)[0] + P(G.R_SHOULDER)[0]) // 2, P(G.L_SHOULDER)[1]), lw)
        pygame.draw.circle(self.screen, WHITE, P(G.NOSE), int(34 * s))
        for i in highlight:
            pygame.draw.circle(self.screen, GOLD, P(i), int(22 * s))

    def messages(self, msgs):
        y = self.H - int(20 * self.u)
        for m in reversed(msgs):
            s = self.text.render(m, 30 * self.u, (255, 230, 200))
            y -= s.get_height() + int(12 * self.u)
            self.panel((int(16 * self.u), y - 8, s.get_width() + 24, s.get_height() + 16), 200, (90, 30, 0))
            self.screen.blit(s, (int(28 * self.u), y))

    def corner_text(self, txt, size=26):
        s = self.text.render(txt, size * self.u, WHITE)
        self.panel((10, 10, s.get_width() + 20, s.get_height() + 12), 170)
        self.screen.blit(s, (20, 16))


class GameView:
    def __init__(self, renderer, lines):
        self.r = renderer
        self.lines = lines
        self.fx = Particles()
        self._last_state = None

    def _line(self, key, langs, size, n=None):
        out = []
        for i, lang in enumerate(langs):
            t = self.lines[key]["text"][lang]
            if n is not None:
                t = t.format(n=n)
            out.append((t, size * (1.0 if i == 0 else 0.8), LANG_COLORS.get(lang, WHITE), lang))
        return out

    def render(self, game, player, now, dt):
        r, u = self.r, self.r.u
        W, H = r.W, r.H
        st = game.state
        entered = st != self._last_state
        self._last_state = st
        langs_all = game.g["languages"]

        if player is not None and st != State.ATTRACT:
            r.draw_glow(player.bbox, now)
        if st == State.FINISH:
            r.panel((0, 0, W, H), 90)
        # effects under the text so words stay readable
        self.fx.update(dt, 900 * u)
        self.fx.draw(r.screen)

        if st in (State.ATTRACT, State.PAUSED):
            pulse = 0.5 + 0.5 * math.sin(now * 3)
            mat = pygame.Rect(0, 0, int(W * 0.45), int(H * 0.12))
            mat.center = (W // 2, int(H * 0.88))
            pygame.draw.ellipse(r.screen, (255, int(150 + 80 * pulse), 60), mat, max(4, int(12 * u)))
            for i in range(3):
                x = W // 2 + int((i - 1) * 140 * u)
                y = int(H * 0.72 + 25 * u * math.sin(now * 4 + i))
                pygame.draw.polygon(r.screen, GOLD, star_points(x, y, 34 * u, now))
            r.text_lines(self._line("come_back", langs_all, 78 * u), int(H * 0.25))

        elif st == State.GREETING:
            if entered:
                self.fx.burst(W // 2, H // 3, 40, u, 700)
            r.text_lines(self._line("greeting", langs_all, 100 * u), int(H * 0.3))

        elif st in (State.ROUND_INTRO, State.LISTENING, State.HINT):
            langs = game.languages_for_round()
            lines = [(game.prompt["text"][lg], (86 if i == 0 else 66) * u,
                      LANG_COLORS.get(lg, WHITE), lg) for i, lg in enumerate(langs)]
            r.text_lines(lines, int(H * (0.08 + 0.055 * len(lines))))
            ring_c = (W - int(130 * u), int(130 * u))
            r.panel((ring_c[0] - int(100 * u), ring_c[1] - int(100 * u), int(200 * u), int(200 * u)), 120)
            r.progress_ring(ring_c, int(80 * u), game.hold_fraction if game.armed else 0.0)
            self._round_dots(game)
            if st == State.HINT:
                self._hint(game, now)

        elif st == State.CELEBRATE:
            if entered:
                self.fx.burst(W // 2, int(H * 0.45), 90, u)
                if player is not None and r._map is not None:
                    self.fx.burst(*r.bbox_to_screen(player.bbox).center, 40, u, 600)
            if game.last_word:
                lines = [(game.last_word[lg], (150 if i == 0 else 120) * u,
                          LANG_COLORS.get(lg, WHITE), lg) for i, lg in enumerate(langs_all)]
                r.text_lines(lines, int(H * 0.45), gap=6, panel_alpha=110)
            self._round_dots(game)

        elif st == State.FINISH:
            if entered:
                self.fx.rain(W, 120, u)
            if random.random() < 0.3:
                self.fx.rain(W, 2, u)
            r.trophy(W // 2, int(H * 0.34), 1.3 * u)
            r.text_lines(self._line("finish", langs_all, 84 * u, n=game.successes), int(H * 0.75))

    def _round_dots(self, game):
        r, u = self.r, self.r.u
        n = game.g["rounds"]
        sp = int(46 * u)
        x0 = int(40 * u)
        y = r.H - int(50 * u)
        for i in range(n):
            x = x0 + i * sp
            if i < len(game.round_results):
                if game.round_results[i] == "success":
                    pygame.draw.polygon(r.screen, GOLD, star_points(x, y, 20 * u))
                else:
                    pygame.draw.circle(r.screen, (200, 200, 220), (x, y), int(9 * u))
            elif i == game.round_idx - 1:
                pygame.draw.circle(r.screen, WHITE, (x, y), int(14 * u), max(2, int(4 * u)))
            else:
                pygame.draw.circle(r.screen, (120, 120, 150), (x, y), int(7 * u))

    def _hint(self, game, now):
        r, u = self.r, self.r.u
        check = game.prompt["check"]
        rect = pygame.Rect(0, 0, int(360 * u), int(520 * u))
        rect.bottomright = (r.W - int(30 * u), r.H - int(100 * u))
        r.panel(rect, 170, (30, 40, 90))
        phase = 0.5 - 0.5 * math.cos(now * 2.2)
        kp = poses.NEUTRAL + (poses.TARGETS[check] - poses.NEUTRAL) * phase
        fig = pygame.Rect(rect.x + int(20 * u), rect.y + int(70 * u),
                          rect.w - int(40 * u), rect.h - int(90 * u))
        r.stick_figure(kp, fig,
                       poses.highlight_indices(check) if phase > 0.7 else ())
        lang = game.languages_for_round()[0]
        s = r.text.render(self.lines["hint"]["text"][lang], 40 * u, GOLD, lang=lang)
        r.screen.blit(s, (rect.centerx - s.get_width() // 2, rect.y + int(10 * u)))
