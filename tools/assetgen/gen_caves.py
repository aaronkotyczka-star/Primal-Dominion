"""Walkable cave interiors: chambers (flat-floored ellipsoids) joined by tunnels, carved from rock
with layered noise. Output: assets/flora/cave_<id>_lod0.(json|bin) (rendered from inside) and
assets/world/cave_<id>.json with named spots (entry, exit, crystals, loot, spawns) in local space."""
import json
import math
import os

import numpy as np
import pyfqmr
from skimage import measure

from gen_flora import MB
from sdfrig import _taubin, _vertex_normals

WORLD = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "world")

CAVES = {
    "wurzelhoehle": dict(
        seed=5,
        chambers=[((0, 0, -4), (4.5, 4.0, 5.0)), ((0, 1.5, -24), (12, 7, 10)), ((19, -1.5, -42), (14, 8, 12)),
                  ((-9, -3.5, -60), (11, 9, 10)), ((14, -5, -70), (8, 6, 8))],
        tunnels=[(0, 1, 3.6), (1, 2, 4.0), (2, 3, 4.2), (2, 4, 3.4)],
        crystals=[(3, 4), (4, 3), (2, 2)], loot=[(3, "rift_shard", 2), (4, "metal_ore", 6), (2, "crystal", 4), (1, "mushroom", 5)],
        spawns=[(2, "spider", 2), (3, "spider", 2), (4, "titanoboa", 1)],
    ),
    "weisszahn_hoehle": dict(
        seed=9,
        chambers=[((0, 0, -4), (4.5, 4.0, 5.0)), ((-4, 2, -22), (10, 6, 9)), ((-20, 0, -38), (13, 9, 11)),
                  ((0, -2, -52), (12, 7, 10)), ((-26, -3, -60), (9, 7, 8))],
        tunnels=[(0, 1, 3.6), (1, 2, 3.8), (2, 3, 4.0), (2, 4, 3.4)],
        crystals=[(2, 2), (3, 3), (4, 2)], loot=[(4, "saber_fang", 2), (3, "pelt", 4), (2, "ancient_tablet", 1), (4, "ivory", 2)],
        spawns=[(2, "direwolf", 3), (3, "direwolf", 2), (4, "smilodon", 1)],
    ),
}


def _vnoise(P, seed):
    rng = np.random.default_rng(seed)
    perm = rng.random(4096)

    def h(i):
        k = (i[..., 0] * 73856093 ^ i[..., 1] * 19349663 ^ i[..., 2] * 83492791) & 4095
        return perm[k]
    i = np.floor(P).astype(np.int64)
    f = P - i
    f = f * f * (3 - 2 * f)
    out = 0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (f[..., 0] if dx else 1 - f[..., 0]) * (f[..., 1] if dy else 1 - f[..., 1]) * (f[..., 2] if dz else 1 - f[..., 2])
                out = out + w * h(i + np.array([dx, dy, dz]))
    return out


def build(cid, spec):
    ch = [(np.array(c, float), np.array(r, float)) for c, r in spec["chambers"]]
    lo = np.min([c - r for c, r in ch], axis=0) - 6
    hi = np.max([c + r for c, r in ch], axis=0) + 6
    vox = 0.5
    xs, ys, zs = [np.arange(lo[i], hi[i], vox) for i in range(3)]
    G = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), -1)
    E = np.full(G.shape[:3], 1e3)
    k = 2.5

    def smin(a, b):
        hh = np.clip(0.5 + 0.5 * (b - a) / k, 0, 1)
        return b * (1 - hh) + a * hh - k * hh * (1 - hh)
    for c, r in ch:
        q = (G - c) / r
        d = (np.linalg.norm(q, axis=-1) - 1.0) * r.min()
        d = np.maximum(d, (c[1] - r[1] * 0.55) - G[..., 1])  # flat floor
        E = smin(E, d)
    for a, b, rad in spec["tunnels"]:
        A, B = ch[a][0], ch[b][0]
        A = A + np.array([0, -ch[a][1][1] * 0.55 + rad * 0.6, 0])
        B = B + np.array([0, -ch[b][1][1] * 0.55 + rad * 0.6, 0])
        dvec = B - A
        L2 = dvec @ dvec
        t = np.clip(((G - A) @ dvec) / L2, 0, 1)
        C = A + t[..., None] * dvec
        v = G - C
        d = np.sqrt(v[..., 0] ** 2 + (v[..., 1] * 1.15) ** 2 + v[..., 2] ** 2) - rad
        floor = C[..., 1] - rad * 0.6
        d = np.maximum(d, floor - G[..., 1])
        E = smin(E, d)
    # rock relief: large lumps, ledges, fine grain (walls and ceiling more than the floor)
    seed = spec["seed"]
    n = (_vnoise(G * 0.12, seed) - 0.5) * 3.0 + (_vnoise(G * 0.35, seed + 1) - 0.5) * 1.1 + (_vnoise(G * 1.1, seed + 2) - 0.5) * 0.35
    E = E + n
    # stalactites hanging from the ceiling
    rng = np.random.default_rng(seed)
    for c, r in ch[1:]:
        for _ in range(9):
            x = c[0] + rng.uniform(-0.7, 0.7) * r[0]
            z = c[2] + rng.uniform(-0.7, 0.7) * r[2]
            top = c[1] + r[1] * 0.85
            L = rng.uniform(1.5, 3.5)
            dxz = np.sqrt((G[..., 0] - x) ** 2 + (G[..., 2] - z) ** 2)
            tt = np.clip((top - G[..., 1]) / L, 0, 1)
            d = dxz - 0.7 * (1 - tt)
            d = np.where((G[..., 1] < top + 2) & (G[..., 1] > top - L), d, 1e3)
            E = np.maximum(E, -d)
    v, f, _n, _ = measure.marching_cubes(E, 0.0, spacing=(vox, vox, vox))
    v += lo
    v = _taubin(v, f, 3)
    s = pyfqmr.Simplify()
    s.setMesh(v, f.astype(np.int32))
    s.simplify_mesh(target_count=70000, aggressiveness=5, verbose=False)
    v, f, _ = s.getMesh()
    v = np.asarray(v)
    f = np.asarray(f)
    nr = _vertex_normals(v, f)
    # normals must point into the open space (E < 0): compare with the SDF gradient
    from scipy.ndimage import map_coordinates
    idx = ((v - lo) / vox).T
    gx = map_coordinates(np.gradient(E, axis=0), idx, order=1)
    gy = map_coordinates(np.gradient(E, axis=1), idx, order=1)
    gz = map_coordinates(np.gradient(E, axis=2), idx, order=1)
    grad = np.stack([gx, gy, gz], 1)
    if np.mean(np.sum(nr * grad, axis=1)) > 0:
        f = f[:, ::-1]
        nr = -nr
    mb = MB()
    up = np.clip(nr[:, 1], 0, 1)
    mb.add("rock", v, nr, v[:, [0, 2]] * 0.3, [(0, 1, up_i, 1) for up_i in up], f.reshape(-1))
    tris = mb.write(f"cave_{cid}_lod0")
    # spots: floor height under a point = first free voxel above solid ground
    def floor_at(x, z, y_hint):
        ix = int((x - lo[0]) / vox)
        iz = int((z - lo[2]) / vox)
        col = E[ix, :, iz]
        j0 = int((y_hint - lo[1]) / vox)
        for j in range(max(j0, 1), 0, -1):
            if col[j] < 0 <= col[j - 1]:
                return lo[1] + j * vox
        for j in range(max(j0, 1), len(col) - 1):
            if col[j] < 0 <= col[j - 1]:
                return lo[1] + j * vox
        return y_hint

    def spot(ci, rad=0.55):
        c, r = ch[ci]
        for _ in range(40):
            x = c[0] + rng.uniform(-rad, rad) * r[0]
            z = c[2] + rng.uniform(-rad, rad) * r[2]
            y = floor_at(x, z, c[1])
            if abs(y - (c[1] - r[1] * 0.55)) < 2.5:
                return [float(x), float(y), float(z)]
        return [float(c[0]), float(c[1] - r[1] * 0.55), float(c[2])]
    entry_c, entry_r = ch[0]
    meta = {
        "entry": [0.0, float(floor_at(0, -2, 0)) + 0.2, -2.0],
        "exit": [0.0, float(floor_at(0, -1, 0)), -1.0],
        "crystals": [spot(ci) for ci, n_ in spec["crystals"] for _ in range(n_)],
        "loot": [{"pos": spot(ci, 0.4), "item": it, "n": n_} for ci, it, n_ in spec["loot"]],
        "spawns": [{"pos": spot(ci, 0.35), "species": sp, "n": n_} for ci, sp, n_ in spec["spawns"]],
        "lights": [spot(ci, 0.2) for ci in range(1, len(ch))],
        "bounds": [lo.tolist(), hi.tolist()],
    }
    with open(os.path.join(WORLD, f"cave_{cid}.json"), "w") as fh:
        json.dump(meta, fh, indent=1)
    return tris


if __name__ == "__main__":
    for cid, spec in CAVES.items():
        print(cid, build(cid, spec))
