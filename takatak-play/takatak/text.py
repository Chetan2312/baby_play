"""Text → pygame Surface via Pillow + libraqm.

pygame's own font renderer does not shape Devanagari (matras and conjuncts
break), so all text goes through Pillow with the RAQM layout engine and Noto
fonts. Rendered surfaces are cached.
"""
import os

import pygame
from PIL import Image, ImageDraw, ImageFont, features

from .config import path as project_path

_RAQM = getattr(getattr(ImageFont, "Layout", None), "RAQM", getattr(ImageFont, "LAYOUT_RAQM", None))


def is_devanagari(text):
    return any("ऀ" <= ch <= "ॿ" for ch in text)


def _first_existing(paths):
    for p in paths:
        full = project_path(p)
        if os.path.exists(full):
            return full
    return None


class TextRenderer:
    def __init__(self, font_cfg):
        self.raqm = bool(features.check("raqm")) and _RAQM is not None
        self.warning = None if self.raqm else (
            "libraqm missing: Devanagari will render broken (sudo apt install libraqm0)")
        self.paths = {
            "deva": _first_existing(font_cfg["devanagari"]),
            "latin": _first_existing(font_cfg["latin"]),
        }
        if not self.paths["deva"]:
            self.warning = "Noto Sans Devanagari not found (sudo apt install fonts-noto-core)"
        self._fonts = {}
        self._cache = {}

    def _font(self, script, size):
        key = (script, size)
        if key not in self._fonts:
            p = self.paths[script] or self.paths["latin"]
            if p is None:
                f = ImageFont.load_default()
            elif self.raqm:
                f = ImageFont.truetype(p, size, layout_engine=_RAQM)
            else:
                f = ImageFont.truetype(p, size)
            self._fonts[key] = f
        return self._fonts[key]

    def render(self, text, size, color=(255, 255, 255), stroke=None,
               stroke_color=(20, 20, 40), lang=None):
        size = max(8, int(size))
        stroke = max(2, size // 14) if stroke is None else stroke
        key = (text, size, color, stroke, stroke_color, lang)
        surf = self._cache.get(key)
        if surf is not None:
            return surf
        script = "deva" if is_devanagari(text) else "latin"
        font = self._font(script, size)
        kw = {}
        if self.raqm and lang in ("hi", "mr"):
            kw["language"] = lang
        x0, y0, x1, y1 = font.getbbox(text, stroke_width=stroke, **kw)
        img = Image.new("RGBA", (max(1, x1 - x0), max(1, y1 - y0)), (0, 0, 0, 0))
        ImageDraw.Draw(img).text((-x0, -y0), text, font=font, fill=color + (255,),
                                 stroke_width=stroke, stroke_fill=stroke_color + (255,), **kw)
        surf = pygame.image.fromstring(img.tobytes(), img.size, "RGBA")
        if pygame.display.get_init() and pygame.display.get_surface() is not None:
            surf = surf.convert_alpha()
        if len(self._cache) > 512:
            self._cache.clear()
        self._cache[key] = surf
        return surf

    def save_png(self, text, size, out_path, lang=None):
        """Render to a PNG (headless check of shaping)."""
        script = "deva" if is_devanagari(text) else "latin"
        font = self._font(script, size)
        kw = {"language": lang} if self.raqm and lang in ("hi", "mr") else {}
        x0, y0, x1, y1 = font.getbbox(text, **kw)
        img = Image.new("RGB", (x1 - x0 + 20, y1 - y0 + 20), (255, 255, 255))
        ImageDraw.Draw(img).text((10 - x0, 10 - y0), text, font=font, fill=(0, 0, 0), **kw)
        img.save(out_path)
