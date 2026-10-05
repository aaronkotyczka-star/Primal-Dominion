"""Generates tileable PBR-ish textures (albedo/normal/roughness packs) into assets/textures.
All procedural: Voronoi cells, fBm noise, domain warping. Deterministic (fixed seeds)."""
import os

import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "textures")


def tile_noise(n, freq, seed, octaves=5, gain=0.5):
    """Periodic fBm value noise via random lattice + cosine interpolation (tileable)."""
    rng = np.random.default_rng(seed)
    out = np.zeros((n, n))
    amp = 1.0
    tot = 0
    f = freq
    for _ in range(octaves):
        g = rng.random((f, f))
        x = np.linspace(0, f, n, endpoint=False)
        xi = np.floor(x).astype(int)
        xf = x - xi
        xf = xf * xf * (3 - 2 * xf)
        x0 = xi % f
        x1 = (xi + 1) % f
        a = g[np.ix_(x0, x0)]
        b = g[np.ix_(x0, x1)]
        c = g[np.ix_(x1, x0)]
        d = g[np.ix_(x1, x1)]
        ty = xf[:, None]
        tx = xf[None, :]
        v = (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty
        out += v * amp
        tot += amp
        amp *= gain
        f *= 2
    return out / tot


def voronoi(n, cells, seed, jitter=0.9):
    from scipy.spatial import cKDTree
    rng = np.random.default_rng(seed)
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells), indexing="ij"), -1) + 0.5 +
           (rng.random((cells, cells, 2)) - 0.5) * jitter) / cells
    flat = pts.reshape(-1, 2) % 1.0
    rnd = rng.random(len(flat))
    tree = cKDTree(flat, boxsize=1.0)
    ys, xs = np.mgrid[0:n, 0:n] / n
    q = np.stack([ys.reshape(-1), xs.reshape(-1)], -1)
    d, i = tree.query(q, k=2)
    f1 = d[:, 0].reshape(n, n)
    f2 = d[:, 1].reshape(n, n)
    cid = rnd[i[:, 0]].reshape(n, n)
    return f1 * cells, f2 * cells, cid


def normal_from_height(h, strength):
    gx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * strength
    gy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * strength
    nz = np.ones_like(h)
    n = np.stack([-gx, gy, nz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    return ((n * 0.5 + 0.5) * 255).astype(np.uint8)


def save(name, arr):
    Image.fromarray(arr).save(os.path.join(OUT, name), optimize=True)


def u8(a):
    return (np.clip(a, 0, 1) * 255).astype(np.uint8)


def creature_skin():
    n = 512
    f1, f2, cid = voronoi(n, 22, 3)
    edge = np.clip((f2 - f1) * 2.2, 0, 1)
    dome = np.clip(1 - f1 * 1.1, 0, 1) ** 0.6
    fine = tile_noise(n, 32, 5, 3)
    wr = tile_noise(n, 8, 9, 4)
    h = edge ** 0.5 * 0.65 + dome * 0.25 + fine * 0.1 + wr * 0.1
    # R: height, G: cell id variation, B: crease/fine noise
    save("skin_scales.png", np.stack([u8(h), u8(cid), u8(fine), np.full((n, n), 255, np.uint8)], -1))
    # coarse wrinkles for mammals / heavy skin
    w1 = tile_noise(n, 6, 21, 6)
    w2 = tile_noise(n, 12, 22, 5)
    ridges = 1 - np.abs(w1 * 2 - 1)
    h2 = ridges ** 3 * 0.7 + w2 * 0.3
    fur = tile_noise(n, 64, 30, 2)
    save("skin_wrinkle.png", np.stack([u8(h2), u8(w2), u8(fur), np.full((n, n), 255, np.uint8)], -1))


# ---------------------------------------------------------------------------------------------
# terrain materials (tileable). Albedo is painted at TN (2048) for detail, normal/rough/height at
# TN/2. Stamps (blades, leaves, pebbles, twigs) wrap around the edges so the tiles stay seamless.
TN = 2048


def warp_field(f, n, seed, amount, freq=6):
    """Domain-warp a tileable field (wraps around)."""
    from scipy.ndimage import map_coordinates
    wx = (tile_noise(n, freq, seed, 4) - 0.5) * amount
    wy = (tile_noise(n, freq, seed + 1, 4) - 0.5) * amount
    ys, xs = np.mgrid[0:n, 0:n].astype(float)
    return map_coordinates(f, [(ys + wy) % n, (xs + wx) % n], order=1, mode="wrap")


def up(f, n):
    """Upsample a tileable field to n (bilinear, wrapping)."""
    from scipy.ndimage import zoom
    k = n // f.shape[0]
    return zoom(np.pad(f, 1, mode="wrap"), k, order=1)[k:k + n, k:k + n]


class Painter:
    """Paints tapered strokes / ellipses onto a wrapping canvas (color + height)."""

    def __init__(self, n, base_rgb, base_h):
        self.n = n
        self.c = base_rgb.copy()
        self.h = base_h.copy()

    def _patch(self, cx, cy, r):
        r = int(r) + 2
        ys = np.arange(int(cy) - r, int(cy) + r + 1)
        xs = np.arange(int(cx) - r, int(cx) + r + 1)
        Y, X = np.meshgrid(ys, xs, indexing="ij")
        return Y, X, Y % self.n, X % self.n

    def stroke(self, cx, cy, ang, length, width, col, hgt, taper=1.0, curve=0.0):
        Y, X, yi, xi = self._patch(cx, cy, length + width)
        dx, dy = X - cx, Y - cy
        u = dx * np.cos(ang) + dy * np.sin(ang)
        v = -dx * np.sin(ang) + dy * np.cos(ang)
        t = u / length
        v = v - curve * length * t * t
        w = width * (1.0 - t * taper * 0.9)
        m = (t >= 0) & (t <= 1) & (np.abs(v) <= w)
        if not m.any():
            return
        prof = np.clip(1 - (np.abs(v) / np.maximum(w, 1e-3)) ** 2, 0, 1)
        shade = 0.82 + 0.25 * prof + 0.12 * t
        cc = np.asarray(col)[None, None, :] * shade[..., None]
        self.c[yi[m], xi[m]] = cc[m]
        hh = hgt * (0.6 + 0.4 * prof) * (1.0 - 0.3 * t)
        self.h[yi[m], xi[m]] = np.maximum(self.h[yi[m], xi[m]], hh[m])

    def blob(self, cx, cy, rx, ry, ang, col, hgt, edge=0.25, dome=True):
        Y, X, yi, xi = self._patch(cx, cy, max(rx, ry))
        dx, dy = X - cx, Y - cy
        u = (dx * np.cos(ang) + dy * np.sin(ang)) / rx
        v = (-dx * np.sin(ang) + dy * np.cos(ang)) / ry
        d = u * u + v * v
        m = d <= 1
        if not m.any():
            return
        prof = np.sqrt(np.clip(1 - d, 0, 1)) if dome else np.ones_like(d)
        cc = np.asarray(col)[None, None, :] * (1 - edge + edge * prof)[..., None]
        self.c[yi[m], xi[m]] = cc[m]
        self.h[yi[m], xi[m]] = np.maximum(self.h[yi[m], xi[m]], (hgt * prof)[m])


def _pebbles(P, rng, count, rmin, rmax, cols, hgt):
    n = P.n
    for _ in range(count):
        r = rng.uniform(rmin, rmax)
        col = np.asarray(cols[rng.integers(len(cols))]) * rng.uniform(0.75, 1.15)
        P.blob(rng.uniform(0, n), rng.uniform(0, n), r, r * rng.uniform(0.6, 0.95), rng.uniform(0, np.pi), col, hgt * rng.uniform(0.7, 1.0), edge=0.45)


def terrain():
    n = TN
    rng = np.random.default_rng(4242)
    yy, xx = np.mgrid[0:n, 0:n] / n

    # ---------------- grass: soil, layered blades (dark → light), clover, dry straw, rare flowers
    soil = tile_noise(n, 16, 300, 6)
    base = np.stack([0.17 + 0.05 * soil, 0.15 + 0.04 * soil, 0.08 + 0.03 * soil], -1)
    P = Painter(n, base, soil * 0.15)
    patch = up(tile_noise(n // 8, 6, 301, 4), n)
    for layer, cnt, lum in ((0, 26000, 0.65), (1, 26000, 0.85), (2, 22000, 1.0)):
        for _ in range(cnt):
            cx, cy = rng.uniform(0, n, 2)
            pv = patch[int(cy) % n, int(cx) % n]
            g = rng.uniform(0.0, 1.0)
            if rng.random() < 0.06 + 0.08 * pv:
                col = np.array([0.52, 0.47, 0.25]) * rng.uniform(0.8, 1.1)
            else:
                col = np.array([0.18 + 0.12 * g + 0.08 * pv, 0.32 + 0.16 * g + 0.04 * pv, 0.08 + 0.06 * g]) * lum
            P.stroke(cx, cy, rng.uniform(0, 2 * np.pi), rng.uniform(16, 42), rng.uniform(1.3, 2.6), col, 0.45 + 0.2 * layer,
                     taper=1.0, curve=rng.uniform(-0.15, 0.15))
    for _ in range(260):  # clover patches
        cx, cy = rng.uniform(0, n, 2)
        for _ in range(rng.integers(5, 14)):
            ox, oy = rng.normal(0, 14, 2)
            for k in range(3):
                a = k * 2.1 + rng.uniform(0, 0.4)
                P.blob(cx + ox + np.cos(a) * 4.5, cy + oy + np.sin(a) * 4.5, 4.5, 3.6, a, np.array([0.16, 0.36, 0.11]) * rng.uniform(0.85, 1.1), 0.95)
    for _ in range(140):  # tiny flowers
        col = [np.array([0.92, 0.9, 0.82]), np.array([0.95, 0.82, 0.25]), np.array([0.7, 0.55, 0.85])][rng.integers(3)]
        P.blob(rng.uniform(0, n), rng.uniform(0, n), 3.2, 3.2, 0, col, 1.0, edge=0.2)
    write_set("grass", P.c, P.h, 0.86 - 0.08 * P.h, 3.0)

    # ---------------- forest floor: soil, moss, fallen leaves, twigs, pebbles
    soil = warp_field(tile_noise(n, 12, 310, 6), n, 311, 60)
    moss = np.clip((tile_noise(n, 6, 312, 5) - 0.55) * 4, 0, 1)
    fine = tile_noise(n, 128, 313, 2)
    base = np.stack([0.22 + 0.07 * soil, 0.16 + 0.05 * soil, 0.1 + 0.04 * soil], -1) * (0.85 + 0.25 * fine[..., None])
    base = base * (1 - moss[..., None] * 0.7) + np.array([0.17, 0.27, 0.09]) * (0.8 + 0.3 * fine[..., None]) * moss[..., None] * 0.7
    P = Painter(n, base, soil * 0.25 + moss * 0.2)
    leaf_cols = [np.array([0.45, 0.28, 0.12]), np.array([0.55, 0.36, 0.14]), np.array([0.36, 0.22, 0.1]), np.array([0.62, 0.48, 0.2]), np.array([0.3, 0.26, 0.12])]
    for _ in range(2600):
        cx, cy = rng.uniform(0, n, 2)
        if moss[int(cy) % n, int(cx) % n] > 0.6 and rng.random() < 0.7:
            continue
        a = rng.uniform(0, np.pi)
        L = rng.uniform(9, 20)
        col = (leaf_cols[rng.integers(len(leaf_cols))] * 0.75 + base[int(cy) % n, int(cx) % n] * 0.25) * rng.uniform(0.7, 1.0)
        P.blob(cx, cy, L, L * rng.uniform(0.38, 0.55), a, col, 0.55, edge=0.35)
        P.stroke(cx - np.cos(a) * L, cy - np.sin(a) * L, a, L * 2, 0.8, col * 0.6, 0.6)
    for _ in range(700):  # twigs
        P.stroke(rng.uniform(0, n), rng.uniform(0, n), rng.uniform(0, 2 * np.pi), rng.uniform(40, 140), rng.uniform(1.5, 3.2),
                 np.array([0.24, 0.17, 0.11]) * rng.uniform(0.7, 1.1), 0.75, taper=0.5, curve=rng.uniform(-0.08, 0.08))
    _pebbles(P, rng, 450, 3, 10, [(0.3, 0.28, 0.25), (0.26, 0.24, 0.21), (0.36, 0.33, 0.29)], 0.8)
    write_set("dirt", P.c, P.h, 0.92 - 0.1 * P.h, 3.5)

    # ---------------- rock: warped strata, crack network, grain, lichen
    st = warp_field(tile_noise(n, 4, 320, 7), n, 321, 220, freq=4)
    lay = np.sin((yy * 14 + st * 6) * np.pi) * 0.5 + 0.5
    lay = lay * 0.6 + 0.4 * (np.sin((yy * 37 + st * 11) * np.pi) * 0.5 + 0.5)
    r1, r2, rid = voronoi(n // 2, 5, 322, jitter=1.0)
    crack = up(np.clip((r2 - r1) * 1.6, 0, 1), n)
    crack = warp_field(crack, n, 323, 90, freq=6)
    crack = 0.55 + 0.45 * crack
    fine_cr = np.clip((1 - np.abs(tile_noise(n, 12, 324, 5) * 2 - 1) - 0.93) * 14, 0, 1)
    fine_cr *= np.clip((tile_noise(n, 6, 328, 3) - 0.45) * 4, 0, 1)
    grain = tile_noise(n, 256, 325, 2)
    mgrain = tile_noise(n, 96, 329, 2)
    speck = (rng.random((n, n)) > 0.985).astype(float)
    from scipy.ndimage import gaussian_filter
    dspeck = gaussian_filter((np.random.default_rng(331).random((n, n)) > 0.993).astype(float), 0.9, mode="wrap")
    dspeck = np.clip(dspeck * 5, 0, 1)
    hgt = st * 0.45 + lay * 0.18 + crack ** 0.6 * 0.3 - fine_cr * 0.1 + grain * 0.07 + mgrain * 0.05
    tone = 0.34 + 0.12 * st + 0.08 * lay
    warm = tile_noise(n, 5, 332, 4)
    col = np.stack([tone * (0.98 + 0.1 * warm), tone * 0.97, tone * (0.97 - 0.08 * warm)], -1)
    col *= (0.7 + 0.4 * crack[..., None]) * (1 - 0.25 * fine_cr[..., None]) * (0.86 + 0.2 * grain[..., None]) * (0.92 + 0.12 * mgrain[..., None])
    col = col * (1 - 0.35 * dspeck[..., None])
    col = col * (1 - 0.25 * speck[..., None]) + 0.25 * speck[..., None] * np.array([0.75, 0.73, 0.7])
    lich = np.clip((tile_noise(n, 10, 326, 5) - 0.64) * 5, 0, 1) * (0.5 + 0.5 * crack)
    lich2 = np.clip((tile_noise(n, 14, 327, 5) - 0.72) * 6, 0, 1)
    col = col * (1 - lich[..., None] * 0.55) + np.array([0.46, 0.5, 0.37]) * lich[..., None] * 0.55
    col = col * (1 - lich2[..., None] * 0.45) + np.array([0.66, 0.5, 0.24]) * lich2[..., None] * 0.45
    write_set("rock", col, hgt, 0.8 + 0.12 * (1 - crack) - 0.1 * speck, 5.0)

    # ---------------- sand: grains, wind ripples, pebbles and shell bits
    gr = tile_noise(n, 512, 330, 1)
    ripple_w = tile_noise(n, 4, 331, 4)
    rip = np.sin((xx * 46 + ripple_w * 7 + yy * 4) * np.pi * 2) * 0.5 + 0.5
    rip = rip ** 1.6
    big = tile_noise(n, 6, 332, 5)
    col = np.stack([0.74 + 0.07 * big, 0.65 + 0.06 * big, 0.48 + 0.05 * big], -1) * (0.88 + 0.12 * rip[..., None]) * (0.9 + 0.18 * gr[..., None])
    P = Painter(n, col, rip * 0.35 + big * 0.3 + gr * 0.1)
    _pebbles(P, rng, 260, 3, 8, [(0.55, 0.5, 0.42), (0.44, 0.4, 0.36), (0.85, 0.82, 0.76)], 0.8)
    write_set("sand", P.c, P.h, 0.9 + 0.05 * gr, 2.5)

    # ---------------- mud: wet low areas (glossy), dry cracked plates higher up
    m1 = warp_field(tile_noise(n, 8, 340, 6), n, 341, 80)
    wet = np.clip((0.48 - m1) * 5, 0, 1)
    c1, c2, _ = voronoi(n // 2, 12, 342)
    cracks = warp_field(up(np.clip(1 - (c2 - c1) * 9, 0, 1), n), n, 344, 70, freq=8) * (1 - wet) * 0.6
    fine = tile_noise(n, 96, 343, 3)
    col = np.stack([0.23 + 0.06 * m1, 0.19 + 0.05 * m1, 0.12 + 0.03 * m1], -1) * (0.85 + 0.2 * fine[..., None])
    col = col * (1 - 0.45 * wet[..., None]) * (1 - 0.4 * cracks[..., None])
    hgt = m1 * 0.6 - cracks * 0.25 + fine * 0.1
    write_set("mud", col, hgt, np.clip(0.75 - 0.6 * wet + 0.1 * fine, 0.08, 1), 3.0)

    # ---------------- snow: soft drifts, blue hollows, sparkles
    sn = warp_field(tile_noise(n, 6, 350, 6), n, 351, 120)
    drift = np.sin((xx * 9 + sn * 5) * np.pi) * 0.5 + 0.5
    sastr = np.sin((xx * 31 + yy * 7 + tile_noise(n, 8, 353, 4) * 6) * np.pi) * 0.5 + 0.5
    drift = drift * 0.6 + sastr ** 3 * 0.4
    fine = tile_noise(n, 64, 352, 3)
    sparkle = (rng.random((n, n)) > 0.994).astype(float)
    hgt = sn * 0.6 + drift * 0.25 + fine * 0.15
    col = np.stack([0.8 + 0.12 * hgt, 0.84 + 0.1 * hgt, 0.94 + 0.04 * hgt], -1)
    col = col * (1 - 0.18 * (1 - hgt[..., None])) + sparkle[..., None] * 0.15
    write_set("snow", col, hgt, np.clip(0.55 + 0.25 * fine - 0.4 * sparkle, 0.05, 1), 2.0)

    # ---------------- ash / volcanic: porous pumice, cinders, cracks
    a1 = warp_field(tile_noise(n, 10, 360, 6), n, 361, 60)
    v1, v2, vid = voronoi(n // 2, 16, 362)
    cr = up(np.clip(1 - (v2 - v1) * 6, 0, 1), n)
    pores = np.clip((tile_noise(n, 160, 363, 2) - 0.62) * 6, 0, 1)
    col = np.stack([0.15 + 0.05 * a1, 0.14 + 0.045 * a1, 0.14 + 0.04 * a1], -1) * (1 - 0.5 * pores[..., None]) * (1 - 0.35 * cr[..., None])
    P = Painter(n, col, a1 * 0.6 - cr * 0.2 - pores * 0.1)
    _pebbles(P, rng, 1400, 3, 10, [(0.1, 0.09, 0.09), (0.2, 0.18, 0.17), (0.28, 0.16, 0.12)], 0.8)
    write_set("ash", P.c, P.h, 0.9, 4.0)

    # ---------------- corrupted ground: blackened soil, branching glowing veins, crystal shards
    c1 = warp_field(tile_noise(n, 8, 370, 6), n, 371, 90)
    veins = 1 - np.abs(warp_field(tile_noise(n, 5, 372, 5), n, 373, 140) * 2 - 1)
    veins = np.clip((veins - 0.95) * 18, 0, 1)
    v2_ = 1 - np.abs(tile_noise(n, 12, 374, 4) * 2 - 1)
    veins = np.maximum(veins, np.clip((v2_ - 0.965) * 22, 0, 1) * 0.6)
    col = np.stack([0.11 + 0.06 * c1, 0.06 + 0.03 * c1, 0.08 + 0.04 * c1], -1)
    col = col * (1 - veins[..., None]) + np.array([0.95, 0.28, 0.08]) * veins[..., None]
    P = Painter(n, col, c1 * 0.6 + (1 - veins) * 0.2)
    for _ in range(500):
        a = rng.uniform(0, 2 * np.pi)
        P.stroke(rng.uniform(0, n), rng.uniform(0, n), a, rng.uniform(10, 26), rng.uniform(2, 4), np.array([0.3, 0.06, 0.2]) * rng.uniform(0.8, 1.3), 1.0, taper=1.0)
    write_set("corrupt", P.c, P.h, 0.55 + 0.2 * (1 - veins), 3.0)


def write_set(name, albedo, height, rough, nstrength):
    """Albedo RGB at full res (JPG later); normal xy + roughness + height (alpha) at half res."""
    n = albedo.shape[0]
    Image.fromarray(u8(albedo)).save(os.path.join(OUT, f"t_{name}_albedo.png"))
    from scipy.ndimage import zoom
    h = height if np.ndim(height) else np.full((n, n), height)
    r = rough if np.ndim(rough) else np.full((n, n), rough)
    hs = zoom(h, 0.5, order=1)
    rs = zoom(r, 0.5, order=1)
    hs = (hs - hs.min()) / max(hs.max() - hs.min(), 1e-6)
    nm = normal_from_height(hs, nstrength)
    save(f"t_{name}_nrm.png", np.stack([nm[..., 0], nm[..., 1], u8(rs), u8(hs)], -1))


def _stretched_voronoi(n, count, seed, sy):
    """Voronoi with cells elongated along y (distances in y scaled by sy < 1). Wraps."""
    from scipy.spatial import cKDTree
    rng = np.random.default_rng(seed)
    pts = rng.random((count, 2))
    box = np.array([sy, 1.0])
    tree = cKDTree(pts * box, boxsize=box)
    ys, xs = np.mgrid[0:n, 0:n] / n
    q = np.stack([ys.reshape(-1) * sy, xs.reshape(-1)], -1)
    d, i = tree.query(q, k=2)
    return d[:, 0].reshape(n, n) * np.sqrt(count), d[:, 1].reshape(n, n) * np.sqrt(count), rng.random(count)[i[:, 0]].reshape(n, n)


def bark_and_leaves():
    n = 1024
    ys, xs = np.mgrid[0:n, 0:n] / n
    # bark: elongated plates separated by deep fissures, fibrous ridges, lichen
    f1, f2, cid = _stretched_voronoi(n, 70, 205, 0.28)
    f1 = warp_field(f1, n, 206, 18)
    f2 = warp_field(f2, n, 206, 18)
    edge = f2 - f1
    fw = 0.28 + 0.25 * tile_noise(n, 12, 209, 3)
    fiss = 1.0 - np.clip(edge / fw, 0, 1) ** 0.7
    fn = tile_noise(n, 8, 200, 6)
    fib = np.sin((xs * 90 + fn * 9 + cid * 3) * np.pi * 2) * 0.5 + 0.5
    grain = tile_noise(n, 64, 203, 3)
    plate = np.clip(edge / 0.5, 0, 1) ** 0.5
    hcrack = np.clip(1 - np.abs(np.sin((ys * 34 + tile_noise(n, 16, 210, 3) * 4 + cid * 7) * np.pi)) / 0.06, 0, 1) * (tile_noise(n, 24, 211, 2) > 0.55)
    h = plate * 0.5 + fib * 0.22 * plate + grain * 0.2 + fn * 0.15 - fiss * 0.45 - hcrack * 0.15 * plate
    base = np.array([0.30, 0.24, 0.18])
    col = base[None, None, :] * (0.75 + 0.35 * cid[..., None]) * (0.6 + 0.6 * h[..., None])
    col = col * (1 - 0.4 * hcrack[..., None])
    col = col * (1 - 0.55 * fiss[..., None]) + np.array([0.06, 0.045, 0.035]) * 0.55 * fiss[..., None]
    gray = tile_noise(n, 10, 207, 4)
    col = col * (1 - 0.3 * gray[..., None]) + np.array([0.33, 0.31, 0.28]) * 0.3 * gray[..., None]
    lic = np.clip((tile_noise(n, 16, 208, 5) - 0.6) * 6, 0, 1) * plate
    lic_c = np.array([0.42, 0.47, 0.33]) * (0.85 + 0.3 * grain[..., None])
    col = col * (1 - lic[..., None] * 0.8) + lic_c * lic[..., None] * 0.8
    h = h + lic * 0.05
    save("bark_albedo.png", u8(col))
    save("bark_nrm.png", normal_from_height(h, 9.0))
    # leaf atlas: 2x2 quadrants (broadleaf, needles, jungle leaves, grass/fern blades) with alpha
    rng = np.random.default_rng(210)
    n2 = 2048
    Q = n2 // 2
    S = Q / 512.0
    img = np.zeros((n2, n2, 4))

    def put(ox, oy, x0, x1, y0, y1, m, col):
        sub = img[oy + y0:oy + y1, ox + x0:ox + x1]
        sub[m, :3] = col[m]
        sub[m, 3] = 1.0

    def twig(ox, oy, cx, cy, ang, L, W, col):
        R = int(L + W + 2)
        x0, x1 = int(max(cx - R, 0)), int(min(cx + R, Q))
        y0, y1 = int(max(cy - R, 0)), int(min(cy + R, Q))
        y, x = np.mgrid[y0:y1, x0:x1]
        dx, dy = x - cx, y - cy
        u = dx * np.cos(ang) + dy * np.sin(ang)
        v = -dx * np.sin(ang) + dy * np.cos(ang)
        t = u / L
        w = W * (1 - 0.6 * t)
        m = (t > 0) & (t < 1) & (np.abs(v) < w)
        prof = np.clip(1 - (v / np.maximum(w, 1e-3)) ** 2, 0, 1)
        c = np.asarray(col)[None, None, :] * (0.65 + 0.45 * prof)[..., None]
        put(ox, oy, x0, x1, y0, y1, m, c)

    for qi in range(4):
        ox, oy = (qi % 2) * Q, (qi // 2) * Q
        kind = qi
        if kind in (0, 2):
            for _ in range(6):
                twig(ox, oy, rng.uniform(80, 432) * S, rng.uniform(80, 432) * S, rng.uniform(0, np.pi * 2),
                     rng.uniform(120, 220) * S, rng.uniform(2.5, 4) * S, (0.2, 0.14, 0.09))
        cnt = {0: 150, 1: 85, 2: 110, 3: 60}[kind]
        for _ in range(cnt):
            cx, cy = rng.uniform(60, 452, 2) * S
            ang = rng.uniform(0, np.pi * 2)
            if kind == 1:  # needle sprig: twig + needles along it
                L = rng.uniform(70, 110) * S
                twig(ox, oy, cx, cy, ang, L, 2.2 * S, (0.22, 0.15, 0.1))
                for k in range(int(L / (3.2 * S))):
                    tt = k * 3.2 * S
                    px, py = cx + np.cos(ang) * tt, cy + np.sin(ang) * tt
                    for sd in (-1, 1):
                        a2 = ang + sd * rng.uniform(0.6, 1.0)
                        nl = rng.uniform(18, 28) * S * (1 - 0.4 * tt / L)
                        twig(ox, oy, px, py, a2, nl, 2.0 * S,
                             np.array([0.09, 0.2, 0.09]) * rng.uniform(0.8, 1.25) + np.array([0.0, 0.02, 0.01]) * (tt / L))
                continue
            if kind == 0:
                L, W = rng.uniform(40, 70) * S, rng.uniform(16, 26) * S
            elif kind == 2:
                L, W = rng.uniform(55, 95) * S, rng.uniform(22, 36) * S
            else:
                L, W = rng.uniform(120, 200) * S, rng.uniform(6, 10) * S
            R = int(L + W + 2)
            x0, x1 = int(max(cx - R, 0)), int(min(cx + R, Q))
            y0, y1 = int(max(cy - R, 0)), int(min(cy + R, Q))
            y, x = np.mgrid[y0:y1, x0:x1]
            dx, dy = x - cx, y - cy
            u = dx * np.cos(ang) + dy * np.sin(ang)
            v = -dx * np.sin(ang) + dy * np.cos(ang)
            t = u / L
            tc = np.clip(t, 0, 1)
            if kind == 3:
                halfw = W * (1 - tc) ** 0.8 * np.clip(tc * 8, 0, 1)
            else:
                halfw = W * np.sin(tc * np.pi) ** 0.7
                if kind == 0:  # serrated edge
                    halfw = halfw * (1 - 0.08 * (np.sin(t * 38) * 0.5 + 0.5))
            inside = (t > 0) & (t < 1) & (np.abs(v) < halfw)
            shade = rng.uniform(0.72, 1.18)
            if kind == 0:
                hue = np.array([0.16, 0.3, 0.07]) * (np.array([1.25, 1.0, 0.8]) if rng.random() < 0.15 else 1.0)
            elif kind == 2:
                hue = np.array([0.1, 0.31, 0.08])
            else:
                hue = np.array([0.18, 0.34, 0.08]) * rng.uniform(0.85, 1.1)
            vn = np.abs(v) / np.maximum(halfw, 1e-3)
            mid = np.exp(-(v / (W * 0.05 + 0.6)) ** 2)
            side = 0.0
            if kind != 3:
                side = np.exp(-((np.abs(v) * 0.7 - (u - L * 0.1) + 1000) % (L * 0.14) - L * 0.07) ** 2 / (L * 0.012) ** 2) * (vn < 0.9)
            col = hue[None, None, :] * shade * (0.78 + 0.35 * tc)[..., None] * (1.0 - 0.25 * vn ** 3)[..., None]
            if kind == 3:
                col = col * (1 - 0.12 * mid)[..., None]
            else:
                col = col + np.array([0.05, 0.07, 0.02]) * (mid + 0.5 * side)[..., None]
            put(ox, oy, x0, x1, y0, y1, inside, col)
    save("leaves_atlas.png", u8(img))


def build_strips():
    layers = ["grass", "dirt", "rock", "sand", "mud", "snow", "ash", "corrupt"]
    ims = [Image.open(os.path.join(OUT, f"t_{l}_albedo.png")).convert("RGB") for l in layers]
    w, h = ims[0].size
    strip = Image.new("RGB", (w, h * len(ims)))
    for i, im in enumerate(ims):
        strip.paste(im, (0, i * h))
    strip.save(os.path.join(OUT, "terrain_albedo_array.jpg"), quality=90, subsampling=0)
    ims = [Image.open(os.path.join(OUT, f"t_{l}_nrm.png")).convert("RGBA") for l in layers]
    w, h = ims[0].size
    strip = Image.new("RGBA", (w, h * len(ims)))
    for i, im in enumerate(ims):
        strip.paste(im, (0, i * h))
    strip.save(os.path.join(OUT, "terrain_nrm_array.png"), optimize=True)
    for l in layers:
        for kind in ["albedo", "nrm"]:
            os.remove(os.path.join(OUT, f"t_{l}_{kind}.png"))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    import sys
    which = sys.argv[1:] or ["creature_skin", "terrain", "bark_and_leaves", "build_strips"]
    for w in which:
        globals()[w]()
    print("textures done")
