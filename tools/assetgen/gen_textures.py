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


def terrain():
    n = 1024
    # grass: dense blade noise + clumps
    base = tile_noise(n, 8, 100, 6)
    fine = tile_noise(n, 128, 101, 2)
    clump = tile_noise(n, 16, 102, 4)
    g = np.stack([0.20 + 0.10 * clump + 0.08 * fine, 0.26 + 0.12 * base + 0.08 * fine, 0.09 + 0.05 * clump], -1)
    g *= (0.75 + 0.35 * fine[..., None])
    hgt = fine * 0.6 + clump * 0.4
    write_set("grass", g, hgt, 0.85 + 0.1 * fine, 3.0)
    # dirt / forest floor
    peb_f1, peb_f2, peb_id = voronoi(n, 48, 110)
    peb = np.clip(1 - peb_f1 * 1.6, 0, 1)
    soil = tile_noise(n, 16, 111, 6)
    leaves = tile_noise(n, 48, 112, 3)
    col = np.stack([0.24 + 0.08 * soil, 0.18 + 0.06 * soil, 0.12 + 0.04 * soil], -1)
    col = col * (0.8 + 0.3 * leaves[..., None])
    col = np.where((peb > 0.35)[..., None] & (peb_id > 0.6)[..., None], col * 0.6 + np.array([0.18, 0.17, 0.15]) * (0.6 + peb[..., None] * 0.5), col)
    hgt = soil * 0.5 + np.where(peb_id > 0.6, peb, 0) * 0.5
    write_set("dirt", col, hgt, 0.9 - peb * 0.2, 4.0)
    # rock: layered strata + cracks
    r1, r2, rid = voronoi(n, 10, 120)
    crack = np.clip((r2 - r1) * 6, 0, 1)
    st = tile_noise(n, 4, 121, 7)
    lay = np.sin((np.mgrid[0:n, 0:n][0] / n * 18 + st * 6) * np.pi) * 0.5 + 0.5
    hgt = crack ** 0.4 * 0.5 + st * 0.35 + lay * 0.15
    col = np.stack([0.36 + 0.12 * st, 0.34 + 0.11 * st, 0.31 + 0.1 * st], -1) * (0.7 + 0.4 * hgt[..., None])
    col *= (0.85 + 0.2 * rid[..., None])
    write_set("rock", col, hgt, 0.75 + 0.2 * (1 - crack), 6.0)
    # sand
    s1 = tile_noise(n, 64, 130, 3)
    dunes = np.sin((np.mgrid[0:n, 0:n][1] / n * 24 + tile_noise(n, 4, 131, 3) * 8) * np.pi) * 0.5 + 0.5
    col = np.stack([0.72 + 0.06 * s1, 0.63 + 0.05 * s1, 0.46 + 0.05 * s1], -1) * (0.9 + 0.1 * dunes[..., None])
    write_set("sand", col, dunes * 0.4 + s1 * 0.6, 0.9 + 0.05 * s1, 2.0)
    # mud / swamp
    m1 = tile_noise(n, 12, 140, 6)
    m2 = tile_noise(n, 48, 141, 3)
    col = np.stack([0.16 + 0.05 * m1, 0.14 + 0.05 * m1, 0.09 + 0.03 * m1], -1) * (0.8 + 0.3 * m2[..., None])
    write_set("mud", col, m1 * 0.7 + m2 * 0.3, 0.35 + 0.4 * m2, 2.5)
    # snow
    sn = tile_noise(n, 16, 150, 6)
    col = np.stack([0.86 + 0.06 * sn, 0.88 + 0.06 * sn, 0.92 + 0.05 * sn], -1)
    write_set("snow", col, sn, 0.6 + 0.2 * sn, 2.0)
    # ash / volcanic
    a1 = tile_noise(n, 20, 160, 6)
    v1, v2, vid = voronoi(n, 14, 161)
    cr = np.clip((v2 - v1) * 8, 0, 1)
    col = np.stack([0.13 + 0.05 * a1, 0.12 + 0.04 * a1, 0.12 + 0.04 * a1], -1) * (0.6 + 0.4 * cr[..., None])
    write_set("ash", col, a1 * 0.6 + cr * 0.4, 0.85, 4.0)
    # corrupted ground (demonic): dark, veined
    c1 = tile_noise(n, 10, 170, 6)
    veins = 1 - np.abs(tile_noise(n, 6, 171, 5) * 2 - 1)
    veins = np.clip((veins - 0.85) * 8, 0, 1)
    col = np.stack([0.12 + 0.06 * c1 + 0.35 * veins, 0.07 + 0.03 * c1, 0.08 + 0.04 * c1 + 0.05 * veins], -1)
    write_set("corrupt", col, c1 * 0.7 + (1 - veins) * 0.3, 0.6, 3.0, emission=veins)


def write_set(name, albedo, height, rough, nstrength, emission=None):
    n = albedo.shape[0]
    a = u8(albedo)
    # albedo + height in alpha (for height-blending between layers)
    save(f"t_{name}_albedo.png", np.concatenate([a, u8(height)[..., None]], -1))
    nm = normal_from_height(height, nstrength)
    r = u8(rough if np.ndim(rough) else np.full((n, n), rough))
    e = u8(emission) if emission is not None else np.zeros((n, n), np.uint8)
    # normal xy + roughness + emission mask packed
    save(f"t_{name}_nrm.png", np.stack([nm[..., 0], nm[..., 1], r, e if emission is not None else np.full((n, n), 0, np.uint8)], -1))


def bark_and_leaves():
    n = 512
    # bark: vertical fibrous
    ys, xs = np.mgrid[0:n, 0:n] / n
    f = tile_noise(n, 8, 200, 6)
    fib = np.sin((xs * 40 + f * 6) * np.pi * 2) * 0.5 + 0.5
    cr = tile_noise(n, 24, 201, 3)
    h = fib * 0.5 + cr * 0.3 + f * 0.2
    col = np.stack([0.26 + 0.1 * h, 0.2 + 0.07 * h, 0.15 + 0.05 * h], -1) * (0.7 + 0.3 * cr[..., None])
    save("bark_albedo.png", u8(col))
    save("bark_nrm.png", np.concatenate([normal_from_height(h, 5.0), np.full((n, n, 1), 230, np.uint8)], -1)[..., :3])
    # leaf atlas: 2x2 leaf cluster cards (alpha)
    rng = np.random.default_rng(210)
    n2 = 1024
    img = np.zeros((n2, n2, 4))
    for qi in range(4):
        ox, oy = (qi % 2) * 512, (qi // 2) * 512
        kind = qi
        for _ in range(140 if kind != 3 else 60):
            cx, cy = rng.uniform(60, 452, 2)
            ang = rng.uniform(0, np.pi * 2)
            if kind == 0:  # broadleaf
                L, W = rng.uniform(40, 70), rng.uniform(16, 26)
            elif kind == 1:  # needles cluster
                L, W = rng.uniform(50, 80), rng.uniform(3, 5)
            elif kind == 2:  # small jungle leaves
                L, W = rng.uniform(55, 95), rng.uniform(22, 36)
            else:  # fern frond-ish/grass blade
                L, W = rng.uniform(120, 200), rng.uniform(6, 10)
            R = int(L + W + 2)
            x0, x1 = int(max(cx - R, 0)), int(min(cx + R, 512))
            y0, y1 = int(max(cy - R, 0)), int(min(cy + R, 512))
            y, x = np.mgrid[y0:y1, x0:x1]
            dx, dy = x - cx, y - cy
            u = dx * np.cos(ang) + dy * np.sin(ang)
            v = -dx * np.sin(ang) + dy * np.cos(ang)
            t = u / L
            inside = (t > 0) & (t < 1) & (np.abs(v) < W * np.sin(np.clip(t, 0, 1) * np.pi) ** 0.7)
            shade = rng.uniform(0.75, 1.15)
            hue = np.array([0.16, 0.3, 0.07]) if kind != 1 else np.array([0.1, 0.2, 0.08])
            if kind == 2:
                hue = np.array([0.12, 0.32, 0.08])
            vein = np.exp(-(v / (W * 0.08 + 0.5)) ** 2) * 0.15
            col = hue[None, None, :] * shade * (0.8 + 0.4 * t)[..., None] + vein[..., None]
            sub = img[oy + y0:oy + y1, ox + x0:ox + x1]
            m = inside
            sub[m, :3] = col[m]
            sub[m, 3] = 1.0
    save("leaves_atlas.png", u8(img))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    import sys
    which = sys.argv[1:] or ["creature_skin", "terrain", "bark_and_leaves"]
    for w in which:
        globals()[w]()
    print("textures done")
