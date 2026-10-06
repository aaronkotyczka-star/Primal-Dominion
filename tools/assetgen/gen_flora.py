"""Procedural vegetation & rock meshes (static) -> assets/flora/<id>_lod<k>.json/.bin
Surfaces carry a material tag: bark, leaves, rock, cactus, crystal, berry.
Vertex color: r = wind sway weight, g = AO, b = random per-part, a = unused."""
import json
import math
import os
import sys

import numpy as np
import pyfqmr
from skimage import measure

from sdfrig import _taubin, _vertex_normals, godot_winding

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "flora")


class MB:
    def __init__(self):
        self.s = {}

    def surf(self, mat):
        if mat not in self.s:
            self.s[mat] = dict(p=[], n=[], uv=[], c=[], i=[])
        return self.s[mat]

    def add(self, mat, P, Nn, UV, C, I):
        s = self.surf(mat)
        off = len(s["p"])
        s["p"] += [list(map(float, x)) for x in P]
        s["n"] += [list(map(float, x)) for x in Nn]
        s["uv"] += [list(map(float, x)) for x in UV]
        s["c"] += [list(map(float, x)) for x in C]
        s["i"] += [int(x) + off for x in I]

    def write(self, name):
        blob = bytearray()
        meta = {"surfaces": []}
        for mat, s in self.s.items():
            info = {"material": mat, "vertex_count": len(s["p"]), "index_count": len(s["i"])}

            def put(k, arr, dt):
                a = np.ascontiguousarray(np.asarray(arr, dt)).reshape(-1)
                info[k] = [len(blob), a.nbytes]
                blob.extend(a.tobytes())

            put("position", s["p"], np.float32)
            put("normal", s["n"], np.float32)
            put("uv", s["uv"], np.float32)
            put("color", s["c"], np.float32)
            put("index", godot_winding(s["p"], s["n"], s["i"]), np.int32)
            meta["surfaces"].append(info)
        allp = np.concatenate([np.asarray(s["p"]) for s in self.s.values()])
        meta["aabb"] = [allp.min(0).tolist(), allp.max(0).tolist()]
        with open(os.path.join(OUT, name + ".bin"), "wb") as f:
            f.write(bytes(blob))
        with open(os.path.join(OUT, name + ".json"), "w") as f:
            json.dump(meta, f)
        return sum(len(s["i"]) // 3 for s in self.s.values())


def frame(d):
    d = d / np.linalg.norm(d)
    up = np.array([0, 1.0, 0]) if abs(d[1]) < 0.95 else np.array([1.0, 0, 0])
    s = np.cross(d, up)
    s /= np.linalg.norm(s)
    u = np.cross(s, d)
    return s, u


def tube(mb, pts, radii, segs, mat="bark", sway0=0.0, sway1=0.0, vscale=1.0):
    P, Nn, UV, C, I = [], [], [], [], []
    n = len(pts)
    vacc = 0.0
    for i, p in enumerate(pts):
        d = pts[min(i + 1, n - 1)] - pts[max(i - 1, 0)]
        s, u = frame(d)
        if i > 0:
            vacc += np.linalg.norm(pts[i] - pts[i - 1])
        for k in range(segs + 1):
            a = 2 * math.pi * k / segs
            dv = s * math.cos(a) + u * math.sin(a)
            P.append(p + dv * radii[i])
            Nn.append(dv)
            UV.append((k / segs * max(1, round(radii[0] * 6)), vacc * vscale))
            t = i / (n - 1)
            C.append((sway0 + (sway1 - sway0) * t, 0.6 + 0.4 * t, 0.5, 1))
    for i in range(n - 1):
        for k in range(segs):
            a = i * (segs + 1) + k
            b = a + segs + 1
            I += [a, b, a + 1, a + 1, b, b + 1]
    mb.add(mat, P, Nn, UV, C, I)


def card(mb, center, normal, up, w, h, atlas_q, sway, rnd, mat="leaves", bend=0.0, crown_c=None, crown_r=1.0):
    """Leaf card quad (double sided via material). atlas_q: 0..3 quadrant."""
    nrm = normal / np.linalg.norm(normal)
    upv = up - nrm * np.dot(up, nrm)
    upv /= np.linalg.norm(upv) + 1e-9
    side = np.cross(upv, nrm)
    qx, qy = (atlas_q % 2) * 0.5, (atlas_q // 2) * 0.5
    P, Nn, UV, C = [], [], [], []
    for j, (sx, sy) in enumerate([(-1, -1), (1, -1), (1, 1), (-1, 1)]):
        p = center + side * sx * w * 0.5 + upv * sy * h * 0.5 + nrm * bend * (sy + 1) * 0.5 * h
        P.append(p)
        UV.append((qx + (sx * 0.5 + 0.5) * 0.5, qy + (1 - (sy * 0.5 + 0.5)) * 0.5))
        if crown_c is not None:
            # rounded crown shading: normal points away from the crown centre, inner leaves darker
            off = p - crown_c
            dn = np.linalg.norm(off) + 1e-6
            Nn.append(off / dn * 0.85 + np.array([0, 0.15, 0]))
            C.append((sway, 0.45 + 0.55 * min(dn / crown_r, 1.0) ** 1.5, rnd, 0))
        else:
            # normals bent outward for soft shading
            Nn.append(nrm * 0.6 + upv * 0.4)
            C.append((sway, 0.7 + 0.3 * (sy * 0.5 + 0.5), rnd, 1))
    mb.add(mat, P, Nn, UV, C, [0, 1, 2, 0, 2, 3])


def crown(mb, rng, center, radius, count, card_size, atlas_q, sway=1.0, squash=0.8, mat="leaves", crown_c=None, crown_r=None):
    for _ in range(count):
        d = rng.normal(size=3)
        d /= np.linalg.norm(d)
        d[1] *= squash
        r = radius * (0.55 + 0.45 * rng.random() ** 0.5)
        c = center + d * r
        nrm = d + rng.normal(size=3) * 0.3
        up = np.array([0, 1.0, 0]) + rng.normal(size=3) * 0.4
        sz = card_size * rng.uniform(0.75, 1.25)
        card(mb, c, nrm, up, sz, sz, atlas_q, sway, rng.random(), mat, crown_c=crown_c if crown_c is not None else center,
             crown_r=crown_r or radius)


def branch_curve(start, direction, length, droop, segs):
    pts = []
    for i in range(segs + 1):
        t = i / segs
        p = start + direction * length * t + np.array([0, -droop * t * t * length, 0])
        pts.append(p)
    return pts


# ------------------------------------------------------------------ species
def tree_broad(lod, seed=1, H=11.0, crown_r=2.4, nb0=7, spread=1.0, lean=0.25, trunk_r=0.45):
    """Deciduous tree: buttressed trunk, main limbs, twigs, and many leaf clusters at the twig
    ends (gaps between clusters), shaded as one rounded crown."""
    rng = np.random.default_rng(seed)
    mb = MB()
    ph = rng.random() * 6
    trunk = [np.array([math.sin(t * 2 + ph) * lean * t, t * H * 0.58, math.cos(t * 3 + ph) * lean * 0.8 * t]) for t in np.linspace(0, 1, 7)]
    tube(mb, trunk, np.linspace(trunk_r, trunk_r * 0.6, 7), 12 if lod == 0 else 6, sway1=0.1, vscale=0.6)
    for k in range(6 if lod == 0 else 0):
        a = k / 6 * math.tau + ph
        d = np.array([math.cos(a), -0.4, math.sin(a)])
        tube(mb, [np.array([0, 0.9, 0]), np.array([0, 0.9, 0]) + d * 1.3 * trunk_r / 0.45], [trunk_r * 0.5, 0.05], 5)
    top = trunk[-1]
    ccen = top + np.array([0, crown_r * 0.55, 0])
    CR = crown_r * 1.9
    clusters = []
    nb = nb0 if lod == 0 else max(3, nb0 - 3)
    for k in range(nb):
        a = k / nb * math.tau + rng.random() * 0.6
        d = np.array([math.cos(a) * spread, rng.uniform(0.45, 0.95), math.sin(a) * spread])
        d /= np.linalg.norm(d)
        st = top - np.array([0, rng.uniform(0, 2.0), 0])
        L = rng.uniform(2.4, 3.6) * crown_r / 2.4
        pts = branch_curve(st, d, L, 0.12, 4)
        tube(mb, pts, np.linspace(trunk_r * 0.42, 0.05, 5), 7 if lod == 0 else 4, sway0=0.1, sway1=0.4)
        clusters.append(pts[-1])
        if lod == 0:
            for q in range(3):
                base = pts[1 + q]
                d2 = d + rng.normal(size=3) * 0.6
                d2[1] = abs(d2[1]) * 0.6 + 0.2
                d2 /= np.linalg.norm(d2)
                tw = branch_curve(base, d2, L * rng.uniform(0.35, 0.55), 0.1, 2)
                tube(mb, tw, [0.07, 0.04, 0.015], 4, sway0=0.3, sway1=0.6)
                clusters.append(tw[-1])
    clusters.append(top + np.array([0, crown_r * 1.0, 0]))
    for c in clusters:
        if lod == 0:
            crown(mb, rng, c, crown_r * 0.62, 30, 1.25, 0, sway=0.8, squash=0.7, crown_c=ccen, crown_r=CR)
        else:
            crown(mb, rng, c, crown_r * 0.9, 9, 3.4, 0, sway=0.8, crown_c=ccen, crown_r=CR)
    return mb


def tree_conifer(lod, seed=2, H=16.0, width=4.2, tiers0=11):
    """Spruce/fir: whorls of drooping branches, each carrying needle fronds along its length
    (two crossed cards per segment), so the crown reads as layered, sagging boughs."""
    rng = np.random.default_rng(seed)
    mb = MB()
    trunk = [np.array([math.sin(t * 5 + seed) * 0.06, t * H, math.cos(t * 4 + seed) * 0.06]) for t in np.linspace(0, 1, 8)]
    tube(mb, trunk, np.linspace(0.42 * H / 16, 0.03, 8), 10 if lod == 0 else 5, sway1=0.25, vscale=0.5)
    tiers = tiers0 if lod == 0 else max(5, tiers0 // 2)
    up = np.array([0, 1.0, 0])
    for k in range(tiers):
        t = 0.14 + 0.84 * k / (tiers - 1)
        y = t * H + rng.uniform(-0.2, 0.2)
        rad = (1 - t) ** 0.85 * width + 0.4
        nb = (7 if lod == 0 else 5) if t < 0.85 else 4
        for j in range(nb):
            a = j / nb * math.tau + k * 0.9 + rng.uniform(-0.3, 0.3)
            d = np.array([math.cos(a), rng.uniform(0.0, 0.25), math.sin(a)])
            d /= np.linalg.norm(d)
            L = rad * rng.uniform(0.85, 1.1)
            pts = branch_curve(np.array([0, y, 0]), d, L, 0.45 + 0.2 * (1 - t), 3)
            if lod == 0:
                tube(mb, pts, [0.07 * width / 4.2, 0.05, 0.03, 0.012], 4, sway0=0.2, sway1=0.6)
            segs = [(pts[0], pts[1]), (pts[1], pts[2]), (pts[2], pts[3])] if lod == 0 else [(pts[0] + (pts[3] - pts[0]) * 0.15, pts[3])]
            for q, (p0, p1) in enumerate(segs):
                dirv = p1 - p0
                ln = np.linalg.norm(dirv)
                side = np.cross(dirv / ln, up)
                side /= np.linalg.norm(side) + 1e-9
                nrm = np.cross(side, dirv / ln)
                wq = (0.95 - 0.18 * q) * min(L * 0.75, 2.2) if lod == 0 else min(L * 0.9, 2.8)
                sw = 0.35 + 0.65 * (q + 1) / len(segs)
                mid = (p0 + p1) * 0.5 + np.array([0, -0.05 * wq, 0])
                card(mb, mid, nrm + side * 0.55, dirv, wq, ln * 1.35, 1, sw, rng.random(), bend=0.12)
                card(mb, mid, nrm - side * 0.55, dirv, wq, ln * 1.35, 1, sw, rng.random(), bend=0.12)
    # leader
    card(mb, np.array([0, H * 0.985, 0]), np.array([1.0, 0, 0]), up, 0.7, H * 0.08, 1, 1.0, 0.5)
    card(mb, np.array([0, H * 0.985, 0]), np.array([0, 0, 1.0]), up, 0.7, H * 0.08, 1, 1.0, 0.5)
    return mb


def tree_palm(lod, seed=3):
    rng = np.random.default_rng(seed)
    mb = MB()
    H = 9.0
    trunk = [np.array([t * t * 2.2, t * H, 0]) for t in np.linspace(0, 1, 9)]
    tube(mb, trunk, np.linspace(0.3, 0.2, 9), 8 if lod == 0 else 5, sway1=0.35, vscale=2.5)
    top = trunk[-1]
    nf = 9 if lod == 0 else 6
    for k in range(nf):
        a = k / nf * math.tau
        d = np.array([math.cos(a), 0.35, math.sin(a)])
        pts = branch_curve(top, d / np.linalg.norm(d), 4.2, 0.55, 5)
        for i in range(len(pts) - 1):
            mid = (pts[i] + pts[i + 1]) / 2
            dirv = pts[i + 1] - pts[i]
            nrm = np.cross(dirv, np.cross(np.array([0, 1.0, 0]), dirv))
            card(mb, mid, nrm, dirv, 1.6 - i * 0.2, np.linalg.norm(dirv) * 1.05, 3, 0.6 + i * 0.1, rng.random())
    return mb


def tree_jungle(lod, seed=4):
    rng = np.random.default_rng(seed)
    mb = MB()
    H = 22.0
    trunk = [np.array([math.sin(t * 4) * 0.4, t * H, math.cos(t * 3) * 0.3]) for t in np.linspace(0, 1, 8)]
    tube(mb, trunk, np.linspace(0.9, 0.45, 8), 12 if lod == 0 else 6, sway1=0.08)
    for k in range(6 if lod == 0 else 3):
        a = k / 6 * math.tau + 0.3
        d = np.array([math.cos(a), 0.0, math.sin(a)])
        tube(mb, [np.array([0, 3.5, 0]) + d * 0.4, np.array([0, 1.2, 0]) + d * 1.6, d * 2.6 + np.array([0, -0.3, 0])],
             [0.35, 0.25, 0.1], 6)
    top = trunk[-1]
    for k in range(7 if lod == 0 else 4):
        a = k / 7 * math.tau + rng.random()
        d = np.array([math.cos(a), rng.uniform(0.2, 0.5), math.sin(a)])
        pts = branch_curve(top - np.array([0, rng.uniform(0, 4), 0]), d / np.linalg.norm(d), rng.uniform(5, 8), 0.1, 4)
        tube(mb, pts, np.linspace(0.3, 0.08, 5), 6 if lod == 0 else 4, sway0=0.05, sway1=0.3)
        crown(mb, rng, pts[-1] + np.array([0, 0.5, 0]), 3.6, 45 if lod == 0 else 8, 3.0 if lod == 0 else 5.5, 2, sway=0.5, squash=0.45)
    # hanging vines
    if lod == 0:
        for k in range(10):
            a = rng.random() * math.tau
            r = rng.uniform(2, 7)
            c = top + np.array([math.cos(a) * r, -rng.uniform(2, 6), math.sin(a) * r])
            card(mb, c, np.array([math.cos(a), 0, math.sin(a)]), np.array([0, 1.0, 0]), 0.6, rng.uniform(4, 8), 3, 0.7, rng.random())
    return mb


def tree_swamp(lod, seed=5):
    rng = np.random.default_rng(seed)
    mb = MB()
    H = 10.0
    trunk = [np.array([math.sin(t * 5) * 0.5, 1.5 + t * H, math.cos(t * 4) * 0.4]) for t in np.linspace(0, 1, 6)]
    tube(mb, trunk, np.linspace(0.5, 0.2, 6), 9 if lod == 0 else 5, sway1=0.1)
    for k in range(7 if lod == 0 else 4):
        a = k / 7 * math.tau
        d = np.array([math.cos(a), 0, math.sin(a)])
        tube(mb, [np.array([0, 2.3, 0]), d * 1.2 + np.array([0, 1.8, 0]), d * 2.4 + np.array([0, -0.4, 0])], [0.18, 0.14, 0.08], 5)
    top = trunk[-1]
    for k in range(4 if lod == 0 else 2):
        a = k / 4 * math.tau
        d = np.array([math.cos(a), 0.3, math.sin(a)])
        pts = branch_curve(top, d / np.linalg.norm(d), 3.5, 0.4, 3)
        tube(mb, pts, np.linspace(0.14, 0.04, 4), 5, sway0=0.1, sway1=0.4)
        crown(mb, rng, pts[-1], 1.8, 18 if lod == 0 else 5, 2.0 if lod == 0 else 3.2, 0, sway=0.6, squash=0.6)
        if lod == 0:
            for q in range(4):  # hanging moss
                c = pts[-1] + rng.normal(size=3) * 1.0 + np.array([0, -1.5, 0])
                card(mb, c, rng.normal(size=3), np.array([0, 1.0, 0]), 0.5, 2.8, 3, 0.9, rng.random(), mat="moss")
    return mb


def tree_dead(lod, seed=6):
    rng = np.random.default_rng(seed)
    mb = MB()
    H = 8.0
    trunk = [np.array([math.sin(t * 3) * 0.6, t * H, 0]) for t in np.linspace(0, 1, 6)]
    tube(mb, trunk, np.linspace(0.38, 0.06, 6), 7 if lod == 0 else 5, mat="deadwood")
    for k in range(6 if lod == 0 else 3):
        st = trunk[2 + k % 3]
        a = rng.random() * math.tau
        d = np.array([math.cos(a), rng.uniform(0.3, 0.9), math.sin(a)])
        pts = branch_curve(st, d / np.linalg.norm(d), rng.uniform(1.5, 3.5), -0.1, 3)
        tube(mb, pts, np.linspace(0.12, 0.02, 4), 4, mat="deadwood")
    return mb


def bush(lod, seed=7, berries=False):
    rng = np.random.default_rng(seed)
    mb = MB()
    for k in range(4):
        a = k / 4 * math.tau
        tube(mb, branch_curve(np.zeros(3), np.array([math.cos(a) * 0.5, 1, math.sin(a) * 0.5]) / 1.12, 1.0, 0, 2),
             [0.06, 0.04, 0.02], 4, sway1=0.3)
    crown(mb, rng, np.array([0, 0.9, 0]), 1.0, 26 if lod == 0 else 8, 1.0 if lod == 0 else 1.6, 0, sway=0.6, squash=0.7)
    if berries:
        for k in range(30 if lod == 0 else 10):
            d = rng.normal(size=3)
            d /= np.linalg.norm(d)
            d[1] = abs(d[1]) * 0.7
            c = np.array([0, 0.9, 0]) + d * 1.0
            sphere(mb, c, 0.06, "berry")
    return mb


def sphere(mb, c, r, mat, segs=6, rings=4):
    P, Nn, UV, C, I = [], [], [], [], []
    for i in range(rings + 1):
        th = math.pi * i / rings
        for k in range(segs):
            ph = 2 * math.pi * k / segs
            n = np.array([math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph)])
            P.append(c + n * r)
            Nn.append(n)
            UV.append((k / segs, i / rings))
            C.append((0.5, 1, 0.5, 1))
    for i in range(rings):
        for k in range(segs):
            a = i * segs + k
            b = i * segs + (k + 1) % segs
            c2 = (i + 1) * segs + k
            d = (i + 1) * segs + (k + 1) % segs
            I += [a, c2, b, b, c2, d]
    mb.add(mat, P, Nn, UV, C, I)


def fern(lod, seed=8):
    rng = np.random.default_rng(seed)
    mb = MB()
    n = 9 if lod == 0 else 5
    for k in range(n):
        a = k / n * math.tau + rng.random() * 0.4
        d = np.array([math.cos(a), 0.9, math.sin(a)])
        d /= np.linalg.norm(d)
        pts = branch_curve(np.zeros(3), d, 1.3, 0.7, 3)
        for i in range(len(pts) - 1):
            mid = (pts[i] + pts[i + 1]) / 2
            dirv = pts[i + 1] - pts[i]
            nrm = np.cross(dirv, np.cross(np.array([0, 1.0, 0]), dirv))
            card(mb, mid, nrm, dirv, 0.55 - i * 0.1, np.linalg.norm(dirv) * 1.1, 2, 0.4 + i * 0.25, rng.random())
    return mb


def reed(lod, seed=9):
    rng = np.random.default_rng(seed)
    mb = MB()
    for k in range(10 if lod == 0 else 5):
        a = rng.random() * math.tau
        c = np.array([math.cos(a), 0, math.sin(a)]) * rng.uniform(0, 0.6)
        h = rng.uniform(1.2, 2.2)
        card(mb, c + np.array([0, h * 0.5, 0]), np.array([math.cos(a + 1.5), 0, math.sin(a + 1.5)]), np.array([0, 1.0, 0]),
             0.35, h, 3, 0.8, rng.random())
    return mb


def cactus(lod, seed=10):
    mb = MB()
    tube(mb, [np.array([0, t, 0]) for t in np.linspace(0, 4, 6)], [0.35] * 5 + [0.2], 10 if lod == 0 else 6, mat="cactus")
    for s in (-1, 1):
        tube(mb, [np.array([0, 1.6 + s * 0.3, 0]), np.array([s * 0.9, 1.8 + s * 0.3, 0]), np.array([s * 0.95, 3.0 + s * 0.2, 0])],
             [0.22, 0.22, 0.16], 8 if lod == 0 else 5, mat="cactus")
    return mb


def rock(lod, seed=11, size=1.0, flat=0.7, crystal=False):
    """Noisy SDF rock via marching cubes: faceted (plane cuts), layered strata, cracks, fine grain."""
    rng = np.random.default_rng(seed)
    res = 72 if lod == 0 else 20
    g = np.linspace(-1.4, 1.4, res)
    X, Y, Z = np.meshgrid(g, g, g, indexing="ij")
    d = np.sqrt(X ** 2 + (Y / flat) ** 2 + Z ** 2) - 1.0
    for _ in range(11):
        n = rng.normal(size=3)
        n /= np.linalg.norm(n)
        off = rng.uniform(0.55, 0.95)
        d = np.maximum(d, (X * n[0] + Y * n[1] / flat + Z * n[2]) - off)
    tilt = rng.normal(size=3) * 0.25 + np.array([0, 1.0, 0])
    tilt /= np.linalg.norm(tilt)
    hgt = X * tilt[0] + Y * tilt[1] + Z * tilt[2]
    # strata: stepped ledges
    d += (np.abs(np.sin(hgt * 9.0 + rng.random() * 6)) ** 6) * 0.035 * (lod == 0)
    for o in range(5 if lod == 0 else 2):
        f = 2.3 * 2.1 ** o
        ph = rng.random(3) * 10
        d += (np.sin(X * f + ph[0]) * np.sin(Y * f * 1.3 + ph[1]) * np.sin(Z * f * 0.9 + ph[2])) * 0.085 / (o + 1) ** 1.3
    v, fa, _, _ = measure.marching_cubes(d, 0.0, spacing=(g[1] - g[0],) * 3)
    v -= 1.4
    v = _taubin(v, fa, 2)
    s_ = pyfqmr.Simplify()
    s_.setMesh(v, fa.astype(np.int32))
    s_.simplify_mesh(target_count=2600 if lod == 0 else 300, aggressiveness=5, verbose=False)
    v, fa, _ = s_.getMesh()
    v = np.asarray(v) * size
    v[:, 1] += size * flat * 0.55
    fa = np.asarray(fa)[:, ::-1]
    nr = _vertex_normals(v, fa)
    if np.mean(np.sum(nr * (v - v.mean(0)), axis=1)) < 0:
        fa = fa[:, ::-1]
        nr = -nr
    mb = MB()
    mb.add("crystal" if crystal else "rock", v, nr, v[:, [0, 2]] * 0.3, [(0, 1, 0.5, 1)] * len(v), fa.reshape(-1))
    return mb


def log(lod, seed=31):
    rng = np.random.default_rng(seed)
    mb = MB()
    L = rng.uniform(6.0, 9.0)
    pts = [np.array([0.0, 0.42, -L * 0.5 + L * t]) + np.array([math.sin(t * 3) * 0.2, 0, 0]) for t in np.linspace(0, 1, 6)]
    tube(mb, pts, np.linspace(0.45, 0.32, 6), 10 if lod == 0 else 6, mat="deadwood")
    for k in range(4 if lod == 0 else 2):
        st = pts[1 + k]
        d = np.array([rng.choice([-1, 1]) * 0.8, rng.uniform(0.1, 0.6), rng.uniform(-0.3, 0.3)])
        tube(mb, branch_curve(st, d / np.linalg.norm(d), rng.uniform(0.8, 1.6), 0.0, 2), [0.12, 0.07, 0.02], 4, mat="deadwood")
    if lod == 0:
        for k in range(10):
            c = pts[rng.integers(0, 6)] + np.array([rng.uniform(-0.3, 0.3), 0.35, 0])
            card(mb, c, np.array([0, 1.0, 0]), np.array([1.0, 0, 0]), 0.9, 0.6, 2, 0.0, rng.random())
    return mb


def stump(lod, seed=32):
    rng = np.random.default_rng(seed)
    mb = MB()
    tube(mb, [np.array([0, -0.2, 0]), np.array([0, 0.5, 0]), np.array([0.05, 0.9, 0])], [0.55, 0.48, 0.44], 10 if lod == 0 else 6, mat="deadwood")
    for k in range(5 if lod == 0 else 3):
        a = k / 5 * math.tau + rng.random()
        d = np.array([math.cos(a), -0.45, math.sin(a)])
        tube(mb, [np.array([0, 0.4, 0]), np.array([0, 0.4, 0]) + d * 1.0], [0.25, 0.05], 5, mat="deadwood")
    return mb


def crystal(lod, seed=12):
    rng = np.random.default_rng(seed)
    mb = MB()
    for k in range(5):
        a = rng.random() * math.tau
        tilt = np.array([math.cos(a) * 0.4, 1, math.sin(a) * 0.4])
        L = rng.uniform(1.0, 2.6)
        base = np.array([math.cos(a), 0, math.sin(a)]) * rng.uniform(0, 0.5)
        tube(mb, [base, base + tilt / np.linalg.norm(tilt) * L * 0.8, base + tilt / np.linalg.norm(tilt) * L],
             [0.25, 0.25, 0.01], 6, mat="crystal")
    return mb


TYPES = {
    "tree_conifer": tree_conifer, "tree_broad": tree_broad, "tree_palm": tree_palm, "tree_jungle": tree_jungle,
    "tree_swamp": tree_swamp, "tree_dead": tree_dead, "bush": bush, "fern": fern,
    "rock_small": lambda lod: rock(lod, 11, 0.8, 0.6), "rock_large": lambda lod: rock(lod, 13, 4.0, 0.7),
    "cactus": cactus, "berry_bush": lambda lod: bush(lod, 21, True), "reed": reed, "crystal_corrupt": crystal,
    "boulder": lambda lod: rock(lod, 17, 9.0, 0.6),
    "tree_broad_b": lambda lod: tree_broad(lod, 41, H=8.5, crown_r=3.3, nb0=9, spread=1.5, lean=0.4, trunk_r=0.62),
    "tree_broad_c": lambda lod: tree_broad(lod, 42, H=14.0, crown_r=1.8, nb0=6, spread=0.6, lean=0.15, trunk_r=0.3),
    "tree_conifer_b": lambda lod: tree_conifer(lod, 43, H=23.0, width=4.8, tiers0=14),
    "tree_conifer_c": lambda lod: tree_conifer(lod, 44, H=8.0, width=2.6, tiers0=8),
    "rock_medium": lambda lod: rock(lod, 45, 1.9, 0.65),
    "rock_small_b": lambda lod: rock(lod, 46, 0.6, 0.45),
    "rock_spire": lambda lod: rock(lod, 47, 3.2, 2.4),
    "log": log, "stump": stump,
}

if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    ids = sys.argv[1:] or list(TYPES.keys())
    for t in ids:
        for lod in (0, 1):
            n = TYPES[t](lod).write(f"{t}_lod{lod}")
            print(t, lod, n)
