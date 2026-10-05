"""Core library: build skinned creature meshes from bone-driven SDF primitives.

Coordinate system (Godot): +Y up, -Z forward, +X right. Units: meters.
Output: <out>/<id>.json (metadata) + <id>.bin (vertex/index buffers).
"""
import json
import math
import struct

import numpy as np
import pyfqmr
from scipy import sparse
from skimage import measure

UP = np.array([0.0, 1.0, 0.0])

# Region ids written into CUSTOM0.w (used by creature shader)
R_SKIN, R_EYE, R_TOOTH, R_KERATIN, R_MEMBRANE, R_FEATHER, R_GLOW = 0, 1, 2, 3, 4, 5, 6
R_TOP, R_BOTTOM, R_BOOTS, R_HAIR = 7, 8, 9, 10


def v3(*a):
    return np.array(a, dtype=np.float64)


def norm(v):
    n = np.linalg.norm(v)
    return v / n if n > 1e-9 else v


class Bone:
    def __init__(self, name, parent, head, tail, r0, r1, sx=1.0, sy=1.0, blend=None, geo=True, region=R_SKIN):
        self.name = name
        self.parent = parent
        self.head = np.asarray(head, dtype=np.float64)
        self.tail = np.asarray(tail, dtype=np.float64)
        self.r0 = r0
        self.r1 = r1
        self.sx = sx
        self.sy = sy
        self.blend = blend if blend is not None else max(r0, r1) * 0.35
        self.geo = geo and (r0 > 0 or r1 > 0)
        self.region = region


class Rig:
    def __init__(self, rid, family):
        self.id = rid
        self.family = family
        self.bones = []
        self.index = {}
        self.extra = []  # explicit geometry: dict(pos, nrm, bones, weights, region, idx, surface, uv)
        self.sockets = {}
        self.chains = {}
        self.meta = {}
        self.blobs = []  # extra SDF-only blobs not tied to own bone: (bone_name, center, radii)
        self.region_fn = None

    def add(self, name, parent, head, tail, r0, r1, **kw):
        b = Bone(name, parent, head, tail, r0, r1, **kw)
        self.index[name] = len(self.bones)
        self.bones.append(b)
        return b

    def b(self, name):
        return self.bones[self.index[name]]

    def socket(self, name, bone, pos, normal=(0, 1, 0), scale=1.0):
        self.sockets[name] = {"bone": bone, "pos": list(map(float, pos)), "normal": list(map(float, norm(np.asarray(normal, float)))), "scale": float(scale)}

    def chain(self, name, bones):
        self.chains[name] = bones

    # ---------------------------------------------------------------- SDF
    def _seg_sdf(self, b, P):
        A, B = b.head, b.tail
        d = B - A
        L = np.linalg.norm(d)
        if L < 1e-6:
            dvec = v3(0, 0, -1)
            L = 1e-6
        else:
            dvec = d / L
        AP = P - A
        t = np.clip(AP @ dvec / L, 0.0, 1.0)
        C = A + np.outer(t * L, dvec)
        v = P - C
        side = np.cross(dvec, UP)
        if np.linalg.norm(side) < 1e-4:
            side = v3(1, 0, 0)
        side = norm(side)
        upv = norm(np.cross(side, dvec))
        vs = v @ side
        vu = v @ upv
        vd = v @ dvec
        r = b.r0 + (b.r1 - b.r0) * t
        q = np.sqrt((vs / b.sx) ** 2 + (vu / b.sy) ** 2 + vd ** 2)
        return (q - r) * min(b.sx, b.sy, 1.0)

    def _blob_sdf(self, center, radii, P):
        q = (P - center) / radii
        return (np.linalg.norm(q, axis=1) - 1.0) * radii.min()

    @staticmethod
    def smin(a, b, k):
        h = np.clip(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
        return b * (1 - h) + a * h - k * h * (1 - h)

    def eval_sdf(self, P, per_bone=False):
        total = None
        geo_idx = []
        dists = []
        for i, b in enumerate(self.bones):
            if not b.geo:
                continue
            d = self._seg_sdf(b, P)
            geo_idx.append(i)
            dists.append(d)
            total = d if total is None else self.smin(total, d, b.blend)
        for (bn, c, r, k) in self.blobs:
            d = self._blob_sdf(np.asarray(c), np.asarray(r, float), P)
            total = self.smin(total, d, k)
            geo_idx.append(self.index[bn])
            dists.append(d)
        if per_bone:
            return total, geo_idx, np.stack(dists, axis=1)
        return total

    def blob(self, bone, center, radii, k=0.05):
        self.blobs.append((bone, np.asarray(center, float), np.asarray(radii, float), k))

    # ------------------------------------------------------------ explicit parts
    def add_extra(self, pos, nrm, idx, bone_w, region, surface=0, uv=None):
        """bone_w: list per vertex of [(bone_name, w), ...]"""
        self.extra.append(dict(pos=np.asarray(pos, float), nrm=np.asarray(nrm, float), idx=np.asarray(idx, np.int64),
                               bw=bone_w, region=region, surface=surface,
                               uv=None if uv is None else np.asarray(uv, float)))

    def add_cone(self, base, tip, radius, bone, region, segs=8):
        base = np.asarray(base, float)
        tip = np.asarray(tip, float)
        ax = norm(tip - base)
        s = norm(np.cross(ax, UP)) if abs(ax[1]) < 0.95 else v3(1, 0, 0)
        u = np.cross(s, ax)
        pos, nrm, idx = [], [], []
        for i in range(segs):
            a = 2 * math.pi * i / segs
            dirv = s * math.cos(a) + u * math.sin(a)
            pos.append(base + dirv * radius)
            nrm.append(norm(dirv + ax * 0.3))
        pos.append(tip)
        nrm.append(ax)
        pos.append(base - ax * radius * 0.2)
        nrm.append(-ax)
        ti, bi = segs, segs + 1
        for i in range(segs):
            j = (i + 1) % segs
            idx += [i, j, ti]
            idx += [j, i, bi]
        self.add_extra(pos, nrm, idx, [[(bone, 1.0)]] * len(pos), region)

    def add_curved_cone(self, base, dir1, length, radius, curve, bone, region, segs=7, rings=5):
        """Cone curving towards `curve` vector (claws, horns)."""
        base = np.asarray(base, float)
        d = norm(np.asarray(dir1, float))
        c = np.asarray(curve, float)
        pts = []
        for i in range(rings + 1):
            t = i / rings
            pts.append(base + d * length * t + c * length * (t * t))
        pos, nrm, idx = [], [], []
        for i, p in enumerate(pts):
            t = i / rings
            if i < rings:
                ax = norm(pts[i + 1] - p)
            else:
                ax = norm(p - pts[i - 1])
            s = norm(np.cross(ax, UP)) if abs(ax[1]) < 0.95 else v3(1, 0, 0)
            u = np.cross(s, ax)
            r = radius * (1 - t) + 0.0005
            for k in range(segs):
                a = 2 * math.pi * k / segs
                dv = s * math.cos(a) + u * math.sin(a)
                pos.append(p + dv * r)
                nrm.append(dv)
        for i in range(rings):
            for k in range(segs):
                a = i * segs + k
                b_ = i * segs + (k + 1) % segs
                c_ = (i + 1) * segs + k
                d_ = (i + 1) * segs + (k + 1) % segs
                idx += [a, b_, c_, b_, d_, c_]
        self.add_extra(pos, nrm, idx, [[(bone, 1.0)]] * len(pos), region)

    def add_sphere(self, center, radius, bone, region, segs=10, rings=7):
        center = np.asarray(center, float)
        pos, nrm, idx = [], [], []
        for i in range(rings + 1):
            th = math.pi * i / rings
            for k in range(segs):
                ph = 2 * math.pi * k / segs
                n = v3(math.sin(th) * math.cos(ph), math.cos(th), math.sin(th) * math.sin(ph))
                pos.append(center + n * radius)
                nrm.append(n)
        for i in range(rings):
            for k in range(segs):
                a = i * segs + k
                b_ = i * segs + (k + 1) % segs
                c_ = (i + 1) * segs + k
                d_ = (i + 1) * segs + (k + 1) % segs
                idx += [a, c_, b_, b_, c_, d_]
        self.add_extra(pos, nrm, idx, [[(bone, 1.0)]] * len(pos), region)

    def add_membrane(self, lead_pts, lead_bones, trail_pts, trail_bones, region, rows=6, feather=False):
        """Grid surface between leading edge polyline and trailing edge polyline (same count).
        Written as two-sided geometry on surface 1 with UVs (u span, v chord)."""
        n = len(lead_pts)
        pos, nrm, idx, bw, uv = [], [], [], [], []
        for i in range(n):
            for j in range(rows + 1):
                v = j / rows
                p = lead_pts[i] * (1 - v) + trail_pts[i] * v
                pos.append(p)
                bw.append(_blend_bw(lead_bones[i], trail_bones[i], v))
                uv.append((i / (n - 1), v))
        pos = np.array(pos)
        # normals: computed later per face, here approximate
        for i in range(n - 1):
            for j in range(rows):
                a = i * (rows + 1) + j
                b_ = (i + 1) * (rows + 1) + j
                idx += [a, b_, a + 1, b_, b_ + 1, a + 1]
        idx = np.array(idx).reshape(-1, 3)
        nr = _vertex_normals(pos, idx)
        # double-sided: duplicate with flipped winding
        m = len(pos)
        pos2 = np.concatenate([pos, pos])
        nr2 = np.concatenate([nr, -nr])
        idx2 = np.concatenate([idx, idx[:, ::-1] + m]).reshape(-1)
        bw2 = bw + bw
        uv2 = uv + uv
        self.add_extra(pos2, nr2, idx2, bw2, region, surface=1, uv=uv2)

    # ------------------------------------------------------------- build
    def build(self, out_dir, voxel=None, target_tris=8000, smooth_iter=6):
        geo = [b for b in self.bones if b.geo]
        mins = np.min([np.minimum(b.head, b.tail) - max(b.r0, b.r1) * 1.3 for b in geo], axis=0)
        maxs = np.max([np.maximum(b.head, b.tail) + max(b.r0, b.r1) * 1.3 for b in geo], axis=0)
        for (_, c, r, _k) in self.blobs:
            mins = np.minimum(mins, c - r * 1.3)
            maxs = np.maximum(maxs, c + r * 1.3)
        ext = maxs - mins
        if voxel is None:
            voxel = max(ext) / 150.0
        mins -= voxel * 2
        maxs += voxel * 2
        shape = np.ceil((maxs - mins) / voxel).astype(int) + 1
        xs = mins[0] + np.arange(shape[0]) * voxel
        ys = mins[1] + np.arange(shape[1]) * voxel
        zs = mins[2] + np.arange(shape[2]) * voxel
        G = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), axis=-1).reshape(-1, 3)
        vol = self.eval_sdf(G).reshape(shape)
        verts, faces, _n, _v = measure.marching_cubes(vol, level=0.0, spacing=(voxel, voxel, voxel))
        verts += mins
        verts = _taubin(verts, faces, smooth_iter)
        simp = pyfqmr.Simplify()
        simp.setMesh(verts.astype(np.float64), faces.astype(np.int32))
        simp.simplify_mesh(target_count=target_tris, aggressiveness=5, preserve_border=True, verbose=False)
        verts, faces, _ = simp.getMesh()
        verts = np.asarray(verts, float)
        faces = np.asarray(faces, np.int64)
        # orient outward: check a face normal against SDF gradient
        fn = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
        cen = verts[faces].mean(axis=1)
        eps = voxel * 0.5
        g = self.eval_sdf(cen + norm_rows(fn) * eps) - self.eval_sdf(cen - norm_rows(fn) * eps)
        if np.mean(g > 0) < 0.5:
            faces = faces[:, ::-1]
        nrm = _vertex_normals(verts, faces)
        # skin weights
        _, geo_idx, D = self.eval_sdf(verts, per_bone=True)
        bones_arr, weights_arr = self._skin(verts, geo_idx, D)
        region = np.zeros(len(verts))
        # region from bones
        prim = np.array(geo_idx)[np.argmin(D, axis=1)]
        for i, b in enumerate(self.bones):
            if b.region != R_SKIN:
                region[prim == i] = b.region
        if self.region_fn is not None:
            for vi in range(len(verts)):
                rr = self.region_fn(verts[vi], nrm[vi], self.bones[prim[vi]].name, region[vi])
                if rr is not None:
                    region[vi] = rr
        surf0 = dict(pos=verts, nrm=nrm, idx=faces.reshape(-1), bones=bones_arr, weights=weights_arr, region=region, uv=np.zeros((len(verts), 2)))
        surf1 = dict(pos=np.zeros((0, 3)), nrm=np.zeros((0, 3)), idx=np.zeros(0, np.int64), bones=np.zeros((0, 4), np.int32), weights=np.zeros((0, 4)), region=np.zeros(0), uv=np.zeros((0, 2)))
        for e in self.extra:
            s = surf0 if e["surface"] == 0 else surf1
            off = len(s["pos"])
            bi = np.zeros((len(e["pos"]), 4), np.int32)
            bwv = np.zeros((len(e["pos"]), 4))
            for vi, lst in enumerate(e["bw"]):
                lst = sorted(lst, key=lambda x: -x[1])[:4]
                tot = sum(w for _, w in lst)
                for k, (bn, w) in enumerate(lst):
                    bi[vi, k] = self.index[bn]
                    bwv[vi, k] = w / tot
            s["pos"] = np.concatenate([s["pos"], e["pos"]])
            s["nrm"] = np.concatenate([s["nrm"], e["nrm"]])
            s["idx"] = np.concatenate([s["idx"], e["idx"] + off])
            s["bones"] = np.concatenate([s["bones"], bi])
            s["weights"] = np.concatenate([s["weights"], bwv])
            s["region"] = np.concatenate([s["region"], np.full(len(e["pos"]), e["region"])])
            s["uv"] = np.concatenate([s["uv"], e["uv"] if e["uv"] is not None else np.zeros((len(e["pos"]), 2))])
        self._write(out_dir, [surf0, surf1])
        return len(surf0["idx"]) // 3 + len(surf1["idx"]) // 3

    def _skin(self, verts, geo_idx, D):
        nb = len(self.bones)
        children = {i: [] for i in range(nb)}
        for i, b in enumerate(self.bones):
            if b.parent:
                children[self.index[b.parent]].append(i)
        geo_idx = np.array(geo_idx)
        col_of = {}
        for c, bi in enumerate(geo_idx):
            col_of.setdefault(bi, []).append(c)
        bones_out = np.zeros((len(verts), 4), np.int32)
        w_out = np.zeros((len(verts), 4))
        prim_col = np.argmin(D, axis=1)
        for vi in range(len(verts)):
            pb = geo_idx[prim_col[vi]]
            cand = {pb}
            b = self.bones[pb]
            if b.parent:
                cand.add(self.index[b.parent])
            cand.update(children[pb])
            dmin = D[vi, prim_col[vi]]
            ws = []
            for ci in cand:
                if ci not in col_of:
                    continue
                d = min(D[vi, c] for c in col_of[ci])
                sig = max(self.bones[ci].blend, 1e-3) * 0.9
                ws.append((ci, math.exp(-max(d - dmin, 0.0) / sig)))
            ws.sort(key=lambda x: -x[1])
            ws = ws[:4]
            tot = sum(w for _, w in ws)
            for k, (ci, w) in enumerate(ws):
                bones_out[vi, k] = ci
                w_out[vi, k] = w / tot
        return bones_out, w_out

    def _write(self, out_dir, surfaces):
        blob = bytearray()
        meta_s = []
        for s in surfaces:
            n = len(s["pos"])
            info = {"vertex_count": n, "index_count": int(len(s["idx"]))}
            if n == 0:
                meta_s.append(info)
                continue

            def put(key, arr, dtype):
                a = np.ascontiguousarray(arr, dtype=dtype).reshape(-1)
                info[key] = [len(blob), a.nbytes]
                blob.extend(a.tobytes())
                while len(blob) % 4:
                    blob.append(0)

            # rest normals for triplanar + belly factor
            custom0 = np.concatenate([s["pos"], s["region"][:, None]], axis=1)
            custom1 = np.concatenate([s["nrm"], np.zeros((n, 1))], axis=1)
            put("position", s["pos"], np.float32)
            put("normal", s["nrm"], np.float32)
            put("custom0", custom0, np.float32)
            put("custom1", custom1, np.float32)
            put("uv", s["uv"], np.float32)
            put("bones", s["bones"], np.int32)
            put("weights", s["weights"], np.float32)
            put("index", s["idx"], np.int32)
            meta_s.append(info)
        bones = []
        for b in self.bones:
            pi = self.index[b.parent] if b.parent else -1
            ph = self.bones[pi].head if pi >= 0 else np.zeros(3)
            bones.append({"name": b.name, "parent": pi, "rest": list(map(float, b.head - ph)),
                          "head": list(map(float, b.head)), "tail": list(map(float, b.tail)),
                          "r": float(max(b.r0, b.r1))})
        allp = np.concatenate([s["pos"] for s in surfaces if len(s["pos"])])
        meta = {"id": self.id, "family": self.family, "bones": bones, "surfaces": meta_s,
                "sockets": self.sockets, "chains": self.chains,
                "aabb": [list(map(float, allp.min(axis=0))), list(map(float, allp.max(axis=0)))]}
        meta.update(self.meta)
        with open(f"{out_dir}/{self.id}.bin", "wb") as f:
            f.write(bytes(blob))
        with open(f"{out_dir}/{self.id}.json", "w") as f:
            json.dump(meta, f, indent=1)


def _blend_bw(a, b, t):
    out = {}
    for n, w in a:
        out[n] = out.get(n, 0) + w * (1 - t)
    for n, w in b:
        out[n] = out.get(n, 0) + w * t
    return [(n, w) for n, w in out.items() if w > 1e-4]


def norm_rows(a):
    n = np.linalg.norm(a, axis=1, keepdims=True)
    n[n < 1e-12] = 1
    return a / n


def _vertex_normals(verts, faces):
    faces = np.asarray(faces).reshape(-1, 3)
    fn = np.cross(verts[faces[:, 1]] - verts[faces[:, 0]], verts[faces[:, 2]] - verts[faces[:, 0]])
    vn = np.zeros_like(verts)
    for k in range(3):
        np.add.at(vn, faces[:, k], fn)
    return norm_rows(vn)


def _taubin(verts, faces, iters, lam=0.5, mu=-0.53):
    if iters <= 0:
        return verts
    n = len(verts)
    e = np.concatenate([faces[:, [0, 1]], faces[:, [1, 2]], faces[:, [2, 0]]])
    e = np.concatenate([e, e[:, ::-1]])
    A = sparse.coo_matrix((np.ones(len(e)), (e[:, 0], e[:, 1])), shape=(n, n)).tocsr()
    A.data[:] = 1.0
    deg = np.asarray(A.sum(axis=1)).reshape(-1)
    deg[deg == 0] = 1
    Dinv = sparse.diags(1.0 / deg)
    L = Dinv @ A
    v = verts.copy()
    for _ in range(iters):
        v = v + lam * (L @ v - v)
        v = v + mu * (L @ v - v)
    return v
