"""Painted item icons (128 px PNG with alpha) for every item in data/items.json -> assets/icons/<id>.png.
Each item maps to a drawn shape (weapon, food, material ...) with gradient shading, outline,
highlight and a soft drop shadow. Rendered at 4x and downsampled for smooth edges."""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")
OUT = os.path.join(ROOT, "assets", "icons")
S = 512  # working size
O = 128  # output size

ELEM = {"fire": (0.95, 0.42, 0.1), "water": (0.2, 0.5, 0.95), "ice": (0.6, 0.85, 1.0), "lightning": (0.95, 0.9, 0.3),
        "earth": (0.6, 0.45, 0.25), "wind": (0.7, 0.95, 0.8), "nature": (0.35, 0.8, 0.3), "poison": (0.55, 0.85, 0.2),
        "light": (1.0, 0.95, 0.7), "shadow": (0.45, 0.25, 0.6), "blood": (0.8, 0.08, 0.12)}


def C(c, k=1.0):
    return tuple(int(max(0, min(255, v * 255 * k))) for v in c[:3])


class Icon:
    def __init__(self):
        self.img = Image.new("RGBA", (S, S), (0, 0, 0, 0))

    def mask(self):
        m = Image.new("L", (S, S), 0)
        return m, ImageDraw.Draw(m)

    def paint(self, m, c1, c2=None, angle=-50, outline=0.35, hi=0.25, tex=0.0):
        """Fill mask m with a light->dark gradient, outline and a rim highlight."""
        c2 = c2 if c2 is not None else tuple(v * 0.55 for v in c1)
        a = math.radians(angle)
        yy, xx = np.mgrid[0:S, 0:S] / S
        box = m.getbbox()
        if box is None:
            return
        x0, y0, x1, y1 = [v / S for v in box]
        t = ((xx - x0) / max(x1 - x0, 1e-3) * math.cos(a) + (yy - y0) / max(y1 - y0, 1e-3) * -math.sin(a))
        t = (t - t.min()) / max(t.max() - t.min(), 1e-6)
        t = 1.0 - t
        col = np.array(c1)[None, None, :] * (1 - t[..., None]) + np.array(c2)[None, None, :] * t[..., None]
        if tex > 0:
            rng = np.random.default_rng(int(sum(c1) * 1000))
            nz = rng.random((S // 8, S // 8))
            nz = np.array(Image.fromarray((nz * 255).astype(np.uint8)).resize((S, S), Image.BICUBIC)) / 255.0
            col *= (1 - tex * 0.5 + tex * nz)[..., None]
        rgb = Image.fromarray(np.clip(col * 255, 0, 255).astype(np.uint8), "RGB")
        # inner highlight along the upper-left rim
        er = m.filter(ImageFilter.MinFilter(9))
        shifted = Image.new("L", (S, S), 0)
        shifted.paste(m, (10, 10))
        rim = np.clip(np.asarray(m, float) - np.asarray(shifted, float), 0, 255) / 255.0 * (np.asarray(er, float) / 255.0)
        rgbf = np.asarray(rgb, float) / 255.0
        rgbf = rgbf + rim[..., None] * hi
        rgb = Image.fromarray(np.clip(rgbf * 255, 0, 255).astype(np.uint8), "RGB")
        layer = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        layer.paste(rgb, (0, 0), m)
        if outline > 0:
            ol = m.filter(ImageFilter.MaxFilter(11))
            ocol = tuple(int(v * 255 * outline) for v in c2)
            o_layer = Image.new("RGBA", (S, S), ocol + (255,))
            base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
            base.paste(o_layer, (0, 0), ol)
            self.img = Image.alpha_composite(self.img, base)
        self.img = Image.alpha_composite(self.img, layer)

    def glow(self, color, cx=0.5, cy=0.5, r=0.45, strength=0.9):
        yy, xx = np.mgrid[0:S, 0:S] / S
        d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2) / r
        a = np.clip(1 - d, 0, 1) ** 2 * strength
        g = np.zeros((S, S, 4))
        g[..., :3] = color
        g[..., 3] = a
        self.img = Image.alpha_composite(Image.fromarray((g * 255).astype(np.uint8), "RGBA"), self.img)

    def line(self, pts, w, c, rel=True):
        d = ImageDraw.Draw(self.img)
        d.line([(x * S, y * S) for x, y in pts] if rel else pts, fill=C(c) + (255,), width=int(w * S), joint="curve")

    def finish(self, path):
        # soft drop shadow
        a = self.img.split()[3]
        sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        sha = a.filter(ImageFilter.GaussianBlur(10)).point(lambda v: int(v * 0.55))
        sh.putalpha(sha)
        out = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        out.paste(sh, (10, 14), sh)
        out = Image.alpha_composite(out, self.img)
        out.resize((O, O), Image.LANCZOS).save(path)


def P(pts):
    return [(x * S, y * S) for x, y in pts]


def poly(ic, pts, c1, c2=None, **kw):
    m, d = ic.mask()
    d.polygon(P(pts), fill=255)
    ic.paint(m, c1, c2, **kw)


def ellipse(ic, box, c1, c2=None, **kw):
    m, d = ic.mask()
    d.ellipse([v * S for v in box], fill=255)
    ic.paint(m, c1, c2, **kw)


def thick(ic, pts, w, c1, c2=None, **kw):
    m, d = ic.mask()
    d.line(P(pts), fill=255, width=int(w * S), joint="curve")
    for x, y in (pts[0], pts[-1]):
        d.ellipse([(x - w / 2) * S, (y - w / 2) * S, (x + w / 2) * S, (y + w / 2) * S], fill=255)
    ic.paint(m, c1, c2, **kw)


def blob(ic, cx, cy, r, c1, seed=0, n=9, jag=0.18, c2=None, **kw):
    rng = np.random.default_rng(seed)
    pts = []
    for i in range(n):
        a = i / n * math.tau
        rr = r * (1 - jag + 2 * jag * rng.random())
        pts.append((cx + math.cos(a) * rr, cy + math.sin(a) * rr * 0.85))
    poly(ic, pts, c1, c2, **kw)


WOOD = (0.55, 0.38, 0.22)
STONE = (0.62, 0.6, 0.56)
METAL = (0.75, 0.77, 0.8)
BONE = (0.92, 0.88, 0.78)
LEATHER = (0.55, 0.36, 0.2)


# ------------------------------------------------------------------ shapes
def s_log(ic, c=WOOD):
    thick(ic, [(0.18, 0.66), (0.78, 0.34)], 0.26, c, tex=0.3)
    ellipse(ic, (0.66, 0.2, 0.92, 0.48), (0.85, 0.7, 0.48), (0.6, 0.45, 0.28))
    ic.line([(0.79, 0.34)], 0.0, (0, 0, 0))
    ellipse(ic, (0.74, 0.28, 0.84, 0.4), (0.7, 0.55, 0.35), outline=0.0)


def s_rock(ic, c=STONE, seed=1):
    blob(ic, 0.5, 0.56, 0.32, c, seed, n=8, jag=0.22, tex=0.4)


def s_ingot(ic, c=METAL):
    poly(ic, [(0.18, 0.62), (0.32, 0.4), (0.82, 0.4), (0.86, 0.62), (0.7, 0.74), (0.14, 0.74)], c, tex=0.1)


def s_crystal(ic, c=(0.5, 0.8, 1.0)):
    ic.glow(c, 0.5, 0.55, 0.42, 0.5)
    for dx, h, w in ((-0.14, 0.42, 0.11), (0.14, 0.36, 0.1), (0.0, 0.55, 0.13)):
        x = 0.5 + dx
        poly(ic, [(x - w, 0.8), (x - w, 0.8 - h * 0.7), (x, 0.8 - h), (x + w, 0.8 - h * 0.7), (x + w, 0.8)], c, angle=-20, hi=0.5)


def s_pile(ic, c):
    poly(ic, [(0.15, 0.78), (0.3, 0.5), (0.5, 0.36), (0.7, 0.5), (0.86, 0.78)], c, tex=0.6)


def s_bundle(ic, c=(0.75, 0.68, 0.4)):
    for i in range(7):
        x = 0.3 + i * 0.065
        thick(ic, [(x, 0.18), (x + 0.05, 0.82)], 0.045, c, outline=0.3)
    thick(ic, [(0.26, 0.52), (0.78, 0.5)], 0.06, (0.5, 0.35, 0.2))


def s_hide(ic, c=(0.62, 0.45, 0.32), fur=False):
    pts = [(0.2, 0.2), (0.35, 0.28), (0.5, 0.18), (0.65, 0.28), (0.8, 0.2), (0.76, 0.5), (0.84, 0.82), (0.62, 0.72),
           (0.5, 0.84), (0.38, 0.72), (0.16, 0.82), (0.24, 0.5)]
    poly(ic, pts, c, tex=0.7 if fur else 0.3)


def s_bone(ic, c=BONE, big=False):
    w = 0.12 if big else 0.09
    thick(ic, [(0.26, 0.7), (0.74, 0.3)], w, c)
    for x, y in ((0.22, 0.7), (0.28, 0.76), (0.72, 0.24), (0.78, 0.3)):
        ellipse(ic, (x - w * 0.8, y - w * 0.8, x + w * 0.8, y + w * 0.8), c)


def s_feather(ic, c=(0.85, 0.82, 0.75)):
    poly(ic, [(0.3, 0.82), (0.36, 0.55), (0.52, 0.28), (0.72, 0.14), (0.66, 0.36), (0.5, 0.6)], c, hi=0.3)
    ic.line([(0.28, 0.86), (0.7, 0.16)], 0.012, (0.5, 0.45, 0.4))


def s_scales(ic, c):
    for j in range(3):
        for i in range(3 - (j % 2)):
            x = 0.3 + i * 0.2 + (j % 2) * 0.1
            y = 0.3 + j * 0.18
            poly(ic, [(x - 0.1, y), (x, y - 0.06), (x + 0.1, y), (x + 0.08, y + 0.12), (x, y + 0.17), (x - 0.08, y + 0.12)], c, hi=0.35)


def s_claw(ic, c=(0.25, 0.22, 0.2), tooth=False):
    if tooth:
        poly(ic, [(0.38, 0.2), (0.62, 0.2), (0.58, 0.45), (0.5, 0.86), (0.42, 0.45)], c, angle=0, hi=0.4)
    else:
        poly(ic, [(0.3, 0.3), (0.5, 0.2), (0.7, 0.32), (0.78, 0.55), (0.72, 0.84), (0.62, 0.55), (0.42, 0.4)], c, hi=0.4)


def s_berries(ic, c=(0.62, 0.1, 0.18)):
    thick(ic, [(0.5, 0.18), (0.5, 0.36)], 0.025, (0.3, 0.45, 0.2))
    poly(ic, [(0.5, 0.25), (0.7, 0.18), (0.62, 0.32)], (0.3, 0.6, 0.25))
    for x, y in ((0.4, 0.5), (0.58, 0.48), (0.48, 0.66), (0.66, 0.66), (0.32, 0.68), (0.5, 0.82)):
        ellipse(ic, (x - 0.1, y - 0.1, x + 0.1, y + 0.1), c, hi=0.5)


def s_root(ic, c=(0.75, 0.55, 0.35)):
    poly(ic, [(0.35, 0.3), (0.6, 0.28), (0.7, 0.5), (0.58, 0.78), (0.48, 0.86), (0.36, 0.7)], c, tex=0.4)
    for x in (0.42, 0.5, 0.58):
        thick(ic, [(x, 0.3), (x - 0.04, 0.12)], 0.03, (0.35, 0.6, 0.25))


def s_flower(ic, c=(0.85, 0.35, 0.65)):
    thick(ic, [(0.5, 0.86), (0.5, 0.45)], 0.03, (0.3, 0.55, 0.25))
    for i in range(6):
        a = i / 6 * math.tau
        ellipse(ic, (0.5 + math.cos(a) * 0.14 - 0.1, 0.38 + math.sin(a) * 0.14 - 0.1, 0.5 + math.cos(a) * 0.14 + 0.1, 0.38 + math.sin(a) * 0.14 + 0.1), c)
    ellipse(ic, (0.43, 0.31, 0.57, 0.45), (0.95, 0.8, 0.3))


def s_herb(ic, c=(0.35, 0.7, 0.3)):
    thick(ic, [(0.5, 0.86), (0.5, 0.3)], 0.025, (0.3, 0.5, 0.2))
    for i, (y, sd) in enumerate(((0.35, -1), (0.45, 1), (0.55, -1), (0.65, 1), (0.28, 1))):
        poly(ic, [(0.5, y), (0.5 + sd * 0.15, y - 0.12), (0.5 + sd * 0.3, y - 0.06), (0.5 + sd * 0.15, y + 0.04)], c)


def s_mushroom(ic, c=(0.8, 0.3, 0.2)):
    poly(ic, [(0.42, 0.85), (0.44, 0.5), (0.56, 0.5), (0.58, 0.85)], (0.92, 0.88, 0.8))
    m, d = ic.mask()
    d.chord([0.18 * S, 0.22 * S, 0.82 * S, 0.78 * S], 180, 360, fill=255)
    ic.paint(m, c)
    for x, y in ((0.35, 0.38), (0.55, 0.32), (0.66, 0.44)):
        ellipse(ic, (x - 0.035, y - 0.035, x + 0.035, y + 0.035), (0.95, 0.92, 0.85), outline=0)


def s_meat(ic, cooked=False, prime=False):
    c = (0.55, 0.28, 0.15) if cooked else ((0.8, 0.22, 0.25) if not prime else (0.85, 0.3, 0.35))
    s_bone(ic, BONE)
    blob(ic, 0.45, 0.55, 0.26, c, 5, n=10, jag=0.12, tex=0.3)
    if prime:
        for i in range(4):
            ic.line([(0.32 + i * 0.07, 0.42), (0.38 + i * 0.07, 0.7)], 0.012, (0.95, 0.85, 0.85))


def s_fish(ic, cooked=False, prime=False):
    c = (0.65, 0.5, 0.3) if cooked else ((0.55, 0.65, 0.75) if not prime else (0.85, 0.55, 0.45))
    poly(ic, [(0.14, 0.5), (0.3, 0.36), (0.58, 0.34), (0.74, 0.46), (0.88, 0.32), (0.86, 0.68), (0.74, 0.56), (0.58, 0.66), (0.3, 0.64)], c, hi=0.4)
    ellipse(ic, (0.24, 0.44, 0.3, 0.5), (0.1, 0.1, 0.1), outline=0)


def s_jerky(ic):
    for i, y in enumerate((0.3, 0.48, 0.66)):
        poly(ic, [(0.18, y), (0.8, y - 0.06), (0.84, y + 0.06), (0.22, y + 0.11)], (0.5, 0.25, 0.15), tex=0.5)


def s_bowl(ic, c=(0.55, 0.32, 0.18)):
    ellipse(ic, (0.2, 0.36, 0.8, 0.52), c, tex=0.3)
    m, d = ic.mask()
    d.chord([0.16 * S, 0.2 * S, 0.84 * S, 0.84 * S], 0, 180, fill=255)
    ic.paint(m, WOOD)


def s_bottle(ic, c):
    ic.glow(c, 0.5, 0.6, 0.38, 0.35)
    ellipse(ic, (0.24, 0.38, 0.76, 0.88), c, hi=0.6)
    poly(ic, [(0.43, 0.42), (0.43, 0.2), (0.57, 0.2), (0.57, 0.42)], (0.85, 0.9, 0.95), hi=0.5)
    poly(ic, [(0.41, 0.2), (0.41, 0.12), (0.59, 0.12), (0.59, 0.2)], (0.6, 0.42, 0.25))


def s_jar(ic, c):
    poly(ic, [(0.28, 0.32), (0.72, 0.32), (0.76, 0.82), (0.24, 0.82)], c, tex=0.2)
    poly(ic, [(0.26, 0.24), (0.74, 0.24), (0.74, 0.34), (0.26, 0.34)], (0.5, 0.35, 0.2))


def s_bandage(ic):
    ellipse(ic, (0.22, 0.3, 0.68, 0.76), (0.95, 0.93, 0.88))
    ellipse(ic, (0.38, 0.46, 0.52, 0.6), (0.75, 0.72, 0.65), outline=0)
    poly(ic, [(0.6, 0.6), (0.86, 0.66), (0.84, 0.76), (0.56, 0.72)], (0.95, 0.93, 0.88))


def s_tablet(ic):
    poly(ic, [(0.24, 0.16), (0.76, 0.2), (0.8, 0.86), (0.2, 0.82)], STONE, tex=0.5)
    for i in range(5):
        ic.line([(0.32, 0.3 + i * 0.1), (0.68, 0.32 + i * 0.1)], 0.015, (0.35, 0.33, 0.3))


def s_page(ic, c=(0.92, 0.86, 0.7), lines=True):
    poly(ic, [(0.24, 0.14), (0.76, 0.16), (0.78, 0.86), (0.22, 0.84)], c, tex=0.3)
    if lines:
        for i in range(6):
            ic.line([(0.32, 0.28 + i * 0.09), (0.7, 0.29 + i * 0.09)], 0.01, (0.35, 0.28, 0.2))


def s_map(ic):
    s_page(ic, (0.88, 0.8, 0.6), lines=False)
    ic.line([(0.3, 0.7), (0.42, 0.5), (0.55, 0.58), (0.68, 0.3)], 0.014, (0.6, 0.2, 0.15))
    ic.line([(0.62, 0.26), (0.74, 0.36)], 0.02, (0.7, 0.1, 0.1))
    ic.line([(0.74, 0.26), (0.62, 0.36)], 0.02, (0.7, 0.1, 0.1))


def s_key(ic):
    ellipse(ic, (0.18, 0.2, 0.44, 0.46), (0.85, 0.7, 0.3))
    ellipse(ic, (0.25, 0.27, 0.37, 0.39), (0.0, 0.0, 0.0), outline=0)
    thick(ic, [(0.38, 0.4), (0.8, 0.8)], 0.07, (0.85, 0.7, 0.3))
    thick(ic, [(0.66, 0.66), (0.58, 0.76)], 0.06, (0.85, 0.7, 0.3))


def s_totem(ic):
    poly(ic, [(0.36, 0.86), (0.36, 0.2), (0.64, 0.2), (0.64, 0.86)], (0.4, 0.5, 0.3), tex=0.5)
    ellipse(ic, (0.4, 0.3, 0.48, 0.38), (0.9, 0.8, 0.2), outline=0)
    ellipse(ic, (0.52, 0.3, 0.6, 0.38), (0.9, 0.8, 0.2), outline=0)
    poly(ic, [(0.42, 0.5), (0.58, 0.5), (0.54, 0.6), (0.46, 0.6)], (0.25, 0.15, 0.1))


def s_orb(ic, c):
    ic.glow(c, 0.5, 0.5, 0.48, 1.0)
    ellipse(ic, (0.26, 0.26, 0.74, 0.74), c, tuple(v * 0.4 for v in c), hi=0.7)
    ellipse(ic, (0.36, 0.32, 0.48, 0.42), (1, 1, 1), outline=0, hi=0)


def s_shard(ic, c):
    ic.glow(c, 0.5, 0.5, 0.45, 0.7)
    poly(ic, [(0.5, 0.12), (0.66, 0.4), (0.6, 0.88), (0.38, 0.6), (0.4, 0.34)], c, angle=-20, hi=0.6)


def s_heart(ic, c=(0.55, 0.05, 0.1)):
    ic.glow((0.9, 0.2, 0.1), 0.5, 0.52, 0.45, 0.6)
    m, d = ic.mask()
    d.ellipse([0.2 * S, 0.24 * S, 0.52 * S, 0.56 * S], fill=255)
    d.ellipse([0.48 * S, 0.24 * S, 0.8 * S, 0.56 * S], fill=255)
    d.polygon(P([(0.22, 0.46), (0.78, 0.46), (0.5, 0.86)]), fill=255)
    ic.paint(m, c, hi=0.4)


# weapons ---------------------------------------------------------------
def s_spear(ic, head=STONE, shaft=WOOD):
    thick(ic, [(0.18, 0.86), (0.7, 0.3)], 0.045, shaft)
    poly(ic, [(0.66, 0.34), (0.74, 0.18), (0.88, 0.12), (0.82, 0.26), (0.72, 0.36)], head, hi=0.4)
    thick(ic, [(0.62, 0.36), (0.7, 0.32)], 0.06, (0.6, 0.5, 0.3))


def s_club(ic):
    thick(ic, [(0.22, 0.84), (0.5, 0.5)], 0.06, WOOD)
    poly(ic, [(0.44, 0.52), (0.56, 0.24), (0.72, 0.16), (0.84, 0.28), (0.76, 0.46), (0.52, 0.6)], (0.5, 0.35, 0.2), tex=0.4)


def s_axe(ic, head=STONE):
    thick(ic, [(0.26, 0.86), (0.62, 0.2)], 0.05, WOOD)
    poly(ic, [(0.5, 0.26), (0.72, 0.18), (0.86, 0.3), (0.84, 0.48), (0.66, 0.42), (0.52, 0.42)], head, hi=0.5)


def s_pick(ic, head=STONE):
    thick(ic, [(0.3, 0.86), (0.56, 0.24)], 0.05, WOOD)
    poly(ic, [(0.22, 0.34), (0.5, 0.2), (0.86, 0.3), (0.88, 0.36), (0.52, 0.3), (0.26, 0.42)], head, hi=0.4)


def s_sword(ic):
    poly(ic, [(0.5, 0.08), (0.56, 0.18), (0.56, 0.64), (0.44, 0.64), (0.44, 0.18)], METAL, angle=-10, hi=0.6)
    thick(ic, [(0.32, 0.66), (0.68, 0.66)], 0.05, (0.7, 0.55, 0.25))
    thick(ic, [(0.5, 0.68), (0.5, 0.84)], 0.05, LEATHER)
    ellipse(ic, (0.45, 0.84, 0.55, 0.94), (0.7, 0.55, 0.25))


def s_bow(ic, c=WOOD):
    m, d = ic.mask()
    d.arc([0.15 * S, 0.1 * S, 0.75 * S, 0.9 * S], -80, 80, fill=255, width=int(0.06 * S))
    ic.paint(m, c)
    ic.line([(0.5, 0.12), (0.5, 0.88)], 0.008, (0.9, 0.9, 0.85))


def s_crossbow(ic):
    thick(ic, [(0.5, 0.88), (0.5, 0.26)], 0.08, WOOD)
    m, d = ic.mask()
    d.arc([0.14 * S, 0.18 * S, 0.86 * S, 0.6 * S], 200, 340, fill=255, width=int(0.05 * S))
    ic.paint(m, METAL)
    ic.line([(0.18, 0.32), (0.5, 0.46), (0.82, 0.32)], 0.008, (0.9, 0.9, 0.85))


def s_tube(ic, c=(0.45, 0.55, 0.3), wide=0.05):
    thick(ic, [(0.18, 0.82), (0.82, 0.18)], wide, c)


def s_staff(ic, gem=None):
    thick(ic, [(0.3, 0.9), (0.66, 0.2)], 0.045, WOOD)
    if gem is not None:
        s_orb_small(ic, gem, 0.68, 0.17, 0.09)
    else:
        m, d = ic.mask()
        d.arc([0.56 * S, 0.06 * S, 0.8 * S, 0.3 * S], 150, 400, fill=255, width=int(0.045 * S))
        ic.paint(m, WOOD)


def s_orb_small(ic, c, x, y, r):
    ic.glow(c, x, y, r * 2.4, 0.8)
    ellipse(ic, (x - r, y - r, x + r, y + r), c, hi=0.6)


def s_gun(ic, rune=False):
    thick(ic, [(0.14, 0.4), (0.72, 0.4)], 0.07, (0.3, 0.3, 0.32))
    poly(ic, [(0.6, 0.4), (0.86, 0.46), (0.88, 0.7), (0.74, 0.72), (0.66, 0.52)], WOOD)
    if rune:
        s_orb_small(ic, (0.4, 0.8, 1.0), 0.42, 0.4, 0.05)


def s_shield(ic, c=WOOD, rim=METAL):
    ellipse(ic, (0.16, 0.14, 0.84, 0.86), rim)
    ellipse(ic, (0.22, 0.2, 0.78, 0.8), c, tex=0.3)
    ellipse(ic, (0.42, 0.42, 0.58, 0.58), METAL)


def s_torch(ic):
    ic.glow((1.0, 0.6, 0.2), 0.6, 0.28, 0.32, 0.9)
    thick(ic, [(0.3, 0.88), (0.58, 0.36)], 0.06, WOOD)
    poly(ic, [(0.5, 0.36), (0.58, 0.12), (0.62, 0.24), (0.72, 0.16), (0.7, 0.36), (0.6, 0.44)], (1.0, 0.7, 0.2), (0.9, 0.3, 0.05), hi=0.6)


def s_bola(ic):
    ic.line([(0.5, 0.3), (0.28, 0.72)], 0.012, (0.75, 0.68, 0.4))
    ic.line([(0.5, 0.3), (0.74, 0.7)], 0.012, (0.75, 0.68, 0.4))
    for x, y in ((0.5, 0.26), (0.26, 0.74), (0.76, 0.72)):
        ellipse(ic, (x - 0.1, y - 0.1, x + 0.1, y + 0.1), STONE, tex=0.4)


def s_bomb(ic):
    ic.glow((1, 0.5, 0.1), 0.55, 0.22, 0.2, 0.7)
    ellipse(ic, (0.24, 0.32, 0.76, 0.84), (0.6, 0.38, 0.25), tex=0.3)
    thick(ic, [(0.5, 0.32), (0.56, 0.18)], 0.03, (0.75, 0.68, 0.4))


def s_arrow(ic, head=STONE, fletch=(0.85, 0.82, 0.75), tip_glow=None, short=False):
    a, b = ((0.24, 0.76), (0.72, 0.28)) if not short else ((0.3, 0.7), (0.66, 0.34))
    thick(ic, [a, b], 0.03, WOOD)
    poly(ic, [(b[0] - 0.04, b[1] + 0.04), (b[0] + 0.03, b[1] - 0.11), (b[0] + 0.11, b[1] - 0.03)], head, hi=0.5)
    poly(ic, [(a[0], a[1]), (a[0] - 0.08, a[1] + 0.02), (a[0] + 0.06, a[1] - 0.1), (a[0] + 0.1, a[1] - 0.08)], fletch)
    if tip_glow:
        ic.glow(tip_glow, b[0] + 0.04, b[1] - 0.04, 0.16, 0.9)


def s_balls(ic):
    for x, y in ((0.38, 0.6), (0.62, 0.6), (0.5, 0.4)):
        ellipse(ic, (x - 0.12, y - 0.12, x + 0.12, y + 0.12), (0.45, 0.45, 0.48), hi=0.6)


# armor -----------------------------------------------------------------
def s_helmet(ic, c, cap=False):
    m, d = ic.mask()
    d.chord([0.2 * S, 0.2 * S, 0.8 * S, 0.9 * S], 180, 360, fill=255)
    if not cap:
        d.rectangle([0.2 * S, 0.54 * S, 0.32 * S, 0.74 * S], fill=255)
        d.rectangle([0.68 * S, 0.54 * S, 0.8 * S, 0.74 * S], fill=255)
    ic.paint(m, c, tex=0.2 if cap else 0.05)
    if not cap:
        thick(ic, [(0.5, 0.3), (0.5, 0.62)], 0.05, tuple(v * 0.8 for v in c))


def s_vest(ic, c, fur=False):
    poly(ic, [(0.3, 0.16), (0.42, 0.22), (0.5, 0.34), (0.58, 0.22), (0.7, 0.16), (0.86, 0.3), (0.76, 0.46), (0.74, 0.86),
              (0.26, 0.86), (0.24, 0.46), (0.14, 0.3)], c, tex=0.6 if fur else 0.2)
    if fur:
        thick(ic, [(0.3, 0.18), (0.5, 0.36), (0.7, 0.18)], 0.08, tuple(min(1, v * 1.4) for v in c))


def s_pants(ic, c):
    poly(ic, [(0.28, 0.16), (0.72, 0.16), (0.76, 0.88), (0.56, 0.88), (0.5, 0.42), (0.44, 0.88), (0.24, 0.88)], c, tex=0.25)
    thick(ic, [(0.28, 0.2), (0.72, 0.2)], 0.05, LEATHER)


def s_amulet(ic, c):
    m, d = ic.mask()
    d.arc([0.22 * S, 0.08 * S, 0.78 * S, 0.62 * S], 0, 180, fill=255, width=int(0.02 * S))
    ic.paint(m, (0.6, 0.45, 0.3), outline=0)
    s_orb_small(ic, c, 0.5, 0.66, 0.11)


def s_rune(ic, c):
    ic.glow(c, 0.5, 0.5, 0.45, 0.5)
    blob(ic, 0.5, 0.52, 0.32, (0.45, 0.44, 0.42), 3, n=7, jag=0.12, tex=0.4)
    ic.line([(0.42, 0.32), (0.58, 0.5), (0.42, 0.56), (0.58, 0.74)], 0.03, c)


def s_saddle(ic, c=LEATHER, size=1.0):
    poly(ic, [(0.18, 0.5), (0.3, 0.38), (0.5, 0.44), (0.7, 0.32), (0.84, 0.42), (0.8, 0.62), (0.5, 0.66), (0.22, 0.66)], c, tex=0.3)
    thick(ic, [(0.48, 0.66), (0.46, 0.86)], 0.035, (0.4, 0.28, 0.16))
    ellipse(ic, (0.4, 0.82, 0.52, 0.92), METAL)


def s_egg(ic):
    ellipse(ic, (0.28, 0.16, 0.72, 0.86), (0.9, 0.86, 0.72), hi=0.5)
    for x, y in ((0.4, 0.4), (0.58, 0.55), (0.45, 0.68), (0.6, 0.32)):
        ellipse(ic, (x - 0.03, y - 0.03, x + 0.03, y + 0.03), (0.55, 0.45, 0.3), outline=0)


def s_trap(ic, kind):
    if kind == "trap_bear":
        m, d = ic.mask()
        d.arc([0.15 * S, 0.25 * S, 0.85 * S, 0.85 * S], 180, 360, fill=255, width=int(0.06 * S))
        ic.paint(m, METAL)
        for i in range(7):
            x = 0.22 + i * 0.093
            poly(ic, [(x - 0.03, 0.58), (x, 0.42), (x + 0.03, 0.58)], METAL)
        thick(ic, [(0.15, 0.6), (0.85, 0.6)], 0.05, (0.4, 0.4, 0.42))
    elif kind == "trap_net":
        for i in range(6):
            ic.line([(0.2 + i * 0.12, 0.15), (0.2 + i * 0.12, 0.85)], 0.012, (0.75, 0.68, 0.4))
            ic.line([(0.15, 0.2 + i * 0.12), (0.85, 0.2 + i * 0.12)], 0.012, (0.75, 0.68, 0.4))
    else:
        poly(ic, [(0.12, 0.84), (0.88, 0.84), (0.8, 0.7), (0.2, 0.7)], (0.4, 0.3, 0.2))
        for i in range(5):
            x = 0.24 + i * 0.13
            poly(ic, [(x - 0.04, 0.72), (x, 0.3), (x + 0.04, 0.72)], WOOD)


def s_soul(ic):
    s_crystal(ic, (0.75, 0.55, 1.0))


def draw(iid, it):
    ic = Icon()
    cat = it.get("cat", "")
    el = it.get("element", "")
    col = it.get("color")
    n = iid
    if cat == "rune" and el:
        s_rune(ic, ELEM[el])
    elif cat == "essence" and el:
        s_orb(ic, ELEM[el])
    elif n in ("demon_essence",):
        s_orb(ic, (0.85, 0.15, 0.1))
    elif n == "elemental_essence":
        s_orb(ic, (0.4, 0.85, 0.95))
    elif n in ("rift_shard",):
        s_shard(ic, (0.9, 0.25, 0.6))
    elif n == "shadow_shard":
        s_shard(ic, (0.45, 0.25, 0.65))
    elif n == "blood_crystal":
        s_shard(ic, (0.8, 0.08, 0.15))
    elif n == "demon_heart":
        s_heart(ic)
    elif n.startswith("essence_"):
        s_orb(ic, {"essence_hellhound": (1.0, 0.35, 0.1), "essence_shadowstalker": (0.5, 0.2, 0.7),
                   "essence_bonewyrm": (0.9, 0.85, 0.7), "essence_riftspider": (0.9, 0.2, 0.6)}.get(n, (0.8, 0.4, 0.9)))
    elif n in ("wood", "hardwood"):
        s_log(ic, WOOD if n == "wood" else (0.42, 0.26, 0.14))
    elif n in ("stone", "flint", "metal_ore", "obsidian", "sulfur", "salt", "clay", "charcoal"):
        c = {"stone": STONE, "flint": (0.45, 0.45, 0.5), "metal_ore": (0.55, 0.42, 0.35), "obsidian": (0.15, 0.12, 0.2),
             "sulfur": (0.9, 0.82, 0.25), "salt": (0.95, 0.95, 0.92), "clay": (0.7, 0.45, 0.3), "charcoal": (0.2, 0.2, 0.2)}[n]
        if n in ("salt", "sulfur"):
            s_pile(ic, c)
        else:
            s_rock(ic, c, seed=len(n))
            if n == "metal_ore":
                for x, y in ((0.42, 0.5), (0.58, 0.6), (0.5, 0.42)):
                    ellipse(ic, (x - 0.04, y - 0.04, x + 0.04, y + 0.04), (0.85, 0.6, 0.35), outline=0)
    elif n in ("cement", "gunpowder"):
        s_pile(ic, (0.75, 0.73, 0.68) if n == "cement" else (0.2, 0.2, 0.22))
    elif n in ("fiber", "thatch", "sinew", "silk"):
        s_bundle(ic, {"fiber": (0.6, 0.7, 0.35), "thatch": (0.8, 0.68, 0.38), "sinew": (0.85, 0.7, 0.6), "silk": (0.95, 0.95, 0.98)}[n])
    elif n in ("hide", "leather", "pelt", "sail_membrane"):
        s_hide(ic, {"hide": (0.75, 0.55, 0.42), "leather": (0.5, 0.32, 0.18), "pelt": (0.45, 0.36, 0.28), "sail_membrane": (0.65, 0.5, 0.45)}[n], fur=(n == "pelt"))
    elif n in ("bone", "large_bone", "charred_bone"):
        s_bone(ic, BONE if n != "charred_bone" else (0.25, 0.22, 0.2), big=(n == "large_bone"))
    elif n == "feather":
        s_feather(ic)
    elif n in ("scales", "keratin_plate", "chitin", "wyvern_scale"):
        s_scales(ic, {"scales": (0.45, 0.55, 0.4), "keratin_plate": (0.6, 0.5, 0.35), "chitin": (0.2, 0.17, 0.15), "wyvern_scale": (0.65, 0.18, 0.12)}[n])
    elif n in ("horn", "raptor_claw", "saber_fang", "ivory"):
        s_claw(ic, {"horn": (0.35, 0.3, 0.25), "raptor_claw": (0.22, 0.2, 0.18), "saber_fang": BONE, "ivory": (0.95, 0.92, 0.85)}[n], tooth=(n == "saber_fang"))
    elif n in ("trex_tooth", "shark_tooth"):
        s_claw(ic, BONE, tooth=True)
    elif n == "metal_ingot":
        s_ingot(ic)
    elif n in ("crystal",):
        s_crystal(ic)
    elif n == "soul_crystal":
        s_soul(ic)
    elif n == "venom_gland":
        blob(ic, 0.5, 0.55, 0.26, (0.55, 0.75, 0.3), 2, jag=0.08, hi=0.5)
    elif n in ("berries", "narcoberry"):
        s_berries(ic, (0.62, 0.1, 0.18) if n == "berries" else (0.25, 0.2, 0.55))
    elif n == "veggies":
        s_root(ic)
    elif n == "rare_flower":
        s_flower(ic)
    elif n == "herb_healing":
        s_herb(ic)
    elif n == "mushroom":
        s_mushroom(ic)
    elif "meat" in n or n == "cooked_prime":
        s_meat(ic, cooked=n.startswith("cooked"), prime="prime" in n)
    elif "fish" in n:
        s_fish(ic, cooked=n.startswith("cooked"), prime="prime" in n)
    elif n == "jerky":
        s_jerky(ic)
    elif n == "stew":
        s_bowl(ic)
    elif n == "kibble":
        s_bowl(ic, (0.6, 0.5, 0.3))
    elif n == "wyvern_milk":
        s_jar(ic, (0.95, 0.85, 0.6))
    elif n == "bandage":
        s_bandage(ic)
    elif n in ("healing_salve", "repel_musk"):
        s_jar(ic, (0.4, 0.65, 0.35) if n == "healing_salve" else (0.5, 0.35, 0.25))
    elif n in ("healing_potion", "stamina_tonic", "narcotic", "antidote", "creature_medicine", "purify_tonic", "gene_stabilizer", "forget_potion"):
        s_bottle(ic, {"healing_potion": (0.85, 0.15, 0.15), "stamina_tonic": (0.95, 0.75, 0.2), "narcotic": (0.45, 0.3, 0.7),
                      "antidote": (0.35, 0.8, 0.4), "creature_medicine": (0.3, 0.6, 0.9), "purify_tonic": (0.9, 0.95, 1.0),
                      "gene_stabilizer": (0.3, 0.9, 0.7), "forget_potion": (0.6, 0.6, 0.65)}[n])
    elif n == "research_notes":
        s_page(ic)
    elif n == "ancient_tablet":
        s_tablet(ic)
    elif n.startswith("journal_page"):
        s_page(ic, (0.9, 0.82, 0.62))
    elif n == "map_fragment":
        s_map(ic)
    elif n == "ward_key":
        s_key(ic)
    elif n == "grukk_totem":
        s_totem(ic)
    elif n == "spear_stone":
        s_spear(ic)
    elif n == "javelin":
        s_spear(ic, METAL)
    elif n == "club_wood":
        s_club(ic)
    elif n == "axe_stone":
        s_axe(ic)
    elif n == "pick_stone":
        s_pick(ic)
    elif n == "sword_metal":
        s_sword(ic)
    elif n in ("bow_wood", "bow_composite"):
        s_bow(ic, WOOD if n == "bow_wood" else (0.35, 0.22, 0.15))
    elif n == "crossbow":
        s_crossbow(ic)
    elif n == "blowpipe":
        s_tube(ic)
    elif n in ("staff_wood", "staff_crystal"):
        s_staff(ic, None if n == "staff_wood" else (0.5, 0.8, 1.0))
    elif n in ("donnerrohr", "runenbuechse"):
        s_gun(ic, rune=(n == "runenbuechse"))
    elif n in ("shield_wood", "shield_metal"):
        s_shield(ic, WOOD if n == "shield_wood" else METAL, METAL if n == "shield_wood" else (0.6, 0.5, 0.3))
    elif n == "torch":
        s_torch(ic)
    elif n == "bola":
        s_bola(ic)
    elif n == "firebomb":
        s_bomb(ic)
    elif n.startswith("arrow_") or n.startswith("bolt_") or n == "dart_tranq":
        head = METAL if "metal" in n else STONE
        glow = (1.0, 0.5, 0.1) if "fire" in n else ((0.6, 0.4, 0.9) if "tranq" in n else None)
        s_arrow(ic, head, tip_glow=glow, short=n.startswith("bolt") or n.startswith("dart"))
    elif n == "shot_iron":
        s_balls(ic)
    elif n == "rune_charge":
        s_orb(ic, (0.4, 0.8, 1.0))
    elif cat == "armor":
        c = tuple(col) if col else (0.5, 0.4, 0.3)
        slot = it.get("slot", "")
        if slot == "head":
            s_helmet(ic, c, cap="hide" in n)
        elif slot == "legs":
            s_pants(ic, c)
        elif slot == "trinket":
            s_amulet(ic, (0.9, 0.85, 0.7) if "beast" in n else (0.9, 0.25, 0.6))
        else:
            s_vest(ic, c, fur="fur" in n)
    elif n in ("binding_rune", "pact_sigil"):
        s_rune(ic, (0.9, 0.75, 0.3) if n == "binding_rune" else (0.85, 0.2, 0.25))
    elif cat == "saddle":
        s_saddle(ic, {"saddle_small": LEATHER, "saddle_large": (0.45, 0.3, 0.18), "saddle_huge": (0.35, 0.25, 0.15),
                      "saddle_flyer": (0.55, 0.42, 0.3), "saddle_sea": (0.3, 0.4, 0.45)}[n])
    elif n == "egg":
        s_egg(ic)
    elif cat == "trap":
        s_trap(ic, n)
    else:
        s_rock(ic, (0.6, 0.6, 0.6))
        print("fallback icon:", n)
    ic.finish(os.path.join(OUT, iid + ".png"))


def main():
    os.makedirs(OUT, exist_ok=True)
    items = json.load(open(os.path.join(ROOT, "data", "items.json")))
    ids = sys.argv[1:] or list(items.keys())
    for iid in ids:
        draw(iid, items[iid])
    print(len(ids), "icons")


if __name__ == "__main__":
    main()
