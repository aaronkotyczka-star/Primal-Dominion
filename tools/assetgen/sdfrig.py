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
R_MOUTH = 11


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
        self.blobs = []  # legacy axis-aligned blobs: (bone_name, center, radii, k)
        self.prims = []  # dict(kind, bone, k, sub, region, ...)
        self.region_fn = None
        # smooth per-vertex material masks (CUSTOM2): r = fur/hair/feather length, g/b/a = cloth masks
        self.mask_fn = None
        self.fine_boxes = []  # [(lo xyz, hi xyz, voxel)] regions meshed at a finer resolution
        self.fur_bones = {}  # bone name -> fur coverage (blended with skin weights, so borders are soft)
        self.detail_amp = 0.0
        self.detail_freq = 1.0
        self.ao_scale = None

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

    def _prim_sdf(self, pr, P):
        if pr["kind"] == "isect":
            return np.max([self._prim_sdf(c, P) for c in pr["parts"]], axis=0)
        if pr["kind"] == "ell":
            q = (P - pr["c"]) @ pr["R"].T
            r = pr["r"]
            k0 = np.linalg.norm(q / r, axis=1)
            k1 = np.linalg.norm(q / (r * r), axis=1)
            return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
        # tapered capsule with elliptical cross-section
        A, B = pr["a"], pr["b"]
        d = B - A
        L = max(np.linalg.norm(d), 1e-6)
        dvec = d / L
        AP = P - A
        t = np.clip(AP @ dvec / L, 0.0, 1.0)
        v = AP - np.outer(t * L, dvec)
        up = pr["up"] - dvec * (pr["up"] @ dvec)
        if np.linalg.norm(up) < 1e-4:
            up = v3(0, 0, 1) if abs(dvec[1]) > 0.9 else UP
            up = up - dvec * (up @ dvec)
        up = norm(up)
        side = np.cross(dvec, up)
        rad = pr["r0"] + (pr["r1"] - pr["r0"]) * t
        q = np.sqrt(((v @ side) / pr["sx"]) ** 2 + ((v @ up) / pr["sy"]) ** 2 + (v @ dvec) ** 2)
        return (q - rad) * min(pr["sx"], pr["sy"], 1.0)

    def eval_sdf(self, P, per_bone=False, detail=True):
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
            total = d if total is None else self.smin(total, d, k)
            geo_idx.append(self.index[bn])
            dists.append(d)
        for pr in self.prims:
            if pr["sub"]:
                continue
            d = self._prim_sdf(pr, P)
            total = d if total is None else self.smin(total, d, pr["k"])
            geo_idx.append(self.index[pr["bone"]])
            dists.append(d)
        for pr in self.prims:
            if not pr["sub"]:
                continue
            d = self._prim_sdf(pr, P)
            total = -self.smin(-total, d, pr["k"])
        if detail and self.detail_amp > 0.0:
            total = total + self.detail_amp * (_vnoise(P * self.detail_freq) - 0.5 + 0.5 * (_vnoise(P * self.detail_freq * 2.7 + 5.0) - 0.5))
        if per_bone:
            return total, geo_idx, np.stack(dists, axis=1)
        return total

    # oriented ellipsoid. axes: rows = local x (side), y (up), z (length) unit vectors
    def ell(self, bone, center, radii, axes=None, k=0.05, sub=False, region=None, fur=None):
        R = np.eye(3) if axes is None else np.array([norm(np.asarray(a, float)) for a in axes])
        self.prims.append(dict(kind="ell", bone=bone, c=np.asarray(center, float), r=np.asarray(radii, float), R=R, k=k, sub=sub, region=region, fur=fur))

    def ell_along(self, bone, a, b, rad_side, rad_up, up=(0, 1, 0), k=0.05, extra_len=1.0, sub=False, region=None, fur=None):
        """Ellipsoid spanning segment a-b (length axis), cross radii rad_side/rad_up."""
        a = np.asarray(a, float)
        b = np.asarray(b, float)
        z = norm(b - a)
        u = np.asarray(up, float)
        u = norm(u - z * (u @ z)) if np.linalg.norm(u - z * (u @ z)) > 1e-4 else norm(np.cross(z, v3(1, 0, 0)))
        x = np.cross(u, z)
        L = np.linalg.norm(b - a) * 0.5 * extra_len
        self.ell(bone, (a + b) * 0.5, (rad_side, rad_up, L), (x, u, z), k=k, sub=sub, region=region, fur=fur)

    def cap(self, bone, a, b, r0, r1, up=(0, 1, 0), sx=1.0, sy=1.0, k=0.05, sub=False, region=None, fur=None):
        self.prims.append(dict(kind="cap", bone=bone, a=np.asarray(a, float), b=np.asarray(b, float), r0=r0, r1=r1,
                               up=np.asarray(up, float), sx=sx, sy=sy, k=k, sub=sub, region=region, fur=fur))

    def isect_end(self, n_parts, bone, k=0.05, region=None, sub=False, fur=None):
        """Replace the last n_parts prims by their intersection (e.g. hair = offset cranium ∩ hairline volume)."""
        parts = self.prims[-n_parts:]
        del self.prims[-n_parts:]
        self.prims.append(dict(kind="isect", parts=parts, bone=bone, k=k, sub=sub, region=region, fur=fur))

    def surface_hit(self, origin, direction, max_dist, steps=48):
        """March from an interior point outward; returns first surface point (or None)."""
        o = np.asarray(origin, float)
        dvec = norm(np.asarray(direction, float))
        ts = np.linspace(0, max_dist, steps)
        pts = o[None, :] + ts[:, None] * dvec[None, :]
        d = self.eval_sdf(pts, detail=False)
        idx = np.where((d[:-1] < 0) & (d[1:] >= 0))[0]
        if len(idx) == 0:
            return None
        i = idx[0]
        lo, hi = ts[i], ts[i + 1]
        for _ in range(12):
            mid = (lo + hi) * 0.5
            if self.eval_sdf((o + dvec * mid)[None, :], detail=False)[0] < 0:
                lo = mid
            else:
                hi = mid
        return o + dvec * (lo + hi) * 0.5

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

    def add_eye(self, center, radius, axis, bone, segs=14, rings=10):
        """Sphere with its pole along `axis`; uv.y = polar angle / pi (0 at pupil), uv.x = azimuth / 2pi."""
        center = np.asarray(center, float)
        ax = norm(np.asarray(axis, float))
        s = norm(np.cross(ax, UP)) if abs(ax[1]) < 0.95 else v3(1, 0, 0)
        u = np.cross(s, ax)
        pos, nrm, idx, uv = [], [], [], []
        for i in range(rings + 1):
            th = math.pi * i / rings
            for k in range(segs + 1):
                ph = 2 * math.pi * k / segs
                n = ax * math.cos(th) + (s * math.cos(ph) + u * math.sin(ph)) * math.sin(th)
                pos.append(center + n * radius)
                nrm.append(n)
                uv.append((k / segs, i / rings))
        w = segs + 1
        for i in range(rings):
            for k in range(segs):
                a = i * w + k
                idx += [a, a + w, a + 1, a + 1, a + w, a + w + 1]
        self.add_extra(pos, nrm, idx, [[(bone, 1.0)]] * len(pos), R_EYE, uv=uv)

    def add_membrane(self, lead_pts, lead_bones, trail_pts, trail_bones, region, rows=6, feather=False, uspan=(0.0, 1.0)):
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
                uv.append((uspan[0] + (uspan[1] - uspan[0]) * i / (n - 1), v))
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
    def _bounds(self):
        geo = [b for b in self.bones if b.geo]
        lo = [np.minimum(b.head, b.tail) - max(b.r0, b.r1) * 1.3 for b in geo]
        hi = [np.maximum(b.head, b.tail) + max(b.r0, b.r1) * 1.3 for b in geo]
        for (_, c, r, _k) in self.blobs:
            lo.append(c - r * 1.3)
            hi.append(c + r * 1.3)
        for pr in self.prims:
            if pr["sub"]:
                continue
            if pr["kind"] == "isect":
                pr0 = pr["parts"][0]
                rr = np.max(pr0["r"]) * 1.3 if pr0["kind"] == "ell" else max(pr0["r0"], pr0["r1"]) * 1.3
                c0 = pr0["c"] if pr0["kind"] == "ell" else (pr0["a"] + pr0["b"]) * 0.5
                lo.append(c0 - rr)
                hi.append(c0 + rr)
            elif pr["kind"] == "ell":
                rr = np.max(pr["r"]) * 1.3
                lo.append(pr["c"] - rr)
                hi.append(pr["c"] + rr)
            else:
                rr = max(pr["r0"], pr["r1"]) * max(pr["sx"], pr["sy"], 1.0) * 1.3
                lo.append(np.minimum(pr["a"], pr["b"]) - rr)
                hi.append(np.maximum(pr["a"], pr["b"]) + rr)
        return np.min(lo, axis=0), np.max(hi, axis=0)

    def build(self, out_dir, voxel=None, target_tris=8000, smooth_iter=6, res=150):
        mins, maxs = self._bounds()
        ext = maxs - mins
        if voxel is None:
            voxel = max(ext) / res
        mins -= voxel * 3
        maxs += voxel * 3
        f = 3
        # per-axis coordinates; finer spacing inside self.fine_boxes (faces, hands) with a graded transition
        axes = []
        for ax in range(3):
            ranges = [(bx[0][ax], bx[1][ax], bx[2]) for bx in self.fine_boxes]
            c = _axis_coords(mins[ax], maxs[ax], voxel, ranges)
            n = len(c)
            m = int(np.ceil((n - 1) / f)) * f + 1  # so that coarse samples are every f-th fine sample
            while len(c) < m:
                c = np.append(c, c[-1] + voxel)
            axes.append(c)
        xs, ys, zs = axes
        shape = (len(xs), len(ys), len(zs))
        if res > 200 or self.fine_boxes:
            # narrow band: coarse pass, exact evaluation only near the surface
            cx, cy, cz = xs[::f], ys[::f], zs[::f]
            CG = np.stack(np.meshgrid(cx, cy, cz, indexing="ij"), axis=-1).reshape(-1, 3)
            cvol = self.eval_sdf(CG).reshape(len(cx), len(cy), len(cz)).astype(np.float32)
            del CG
            from scipy.ndimage import zoom
            vol = zoom(cvol, (f, f, f), order=1, grid_mode=False)
            vol = vol[:shape[0], :shape[1], :shape[2]]
            if vol.shape != shape:
                vol = np.pad(vol, [(0, shape[i] - vol.shape[i]) for i in range(3)], mode="edge")
            # coarse cells are up to f*voxel wide (graded areas are finer, so this is conservative)
            band = np.abs(vol) < voxel * f * 2.2
            ii, jj, kk = np.nonzero(band)
            CH = 2_000_000
            out = np.empty(len(ii), np.float32)
            for c0 in range(0, len(ii), CH):
                G = np.stack([xs[ii[c0:c0 + CH]], ys[jj[c0:c0 + CH]], zs[kk[c0:c0 + CH]]], axis=1)
                out[c0:c0 + CH] = self.eval_sdf(G)
            vol[ii, jj, kk] = out
            del band, ii, jj, kk, out
        else:
            G = np.stack(np.meshgrid(xs, ys, zs, indexing="ij"), axis=-1).reshape(-1, 3)
            vol = self.eval_sdf(G).reshape(shape)
        verts, faces, _n, _v = measure.marching_cubes(vol, level=0.0)
        del vol
        verts = np.stack([np.interp(verts[:, i], np.arange(len(axes[i])), axes[i]) for i in range(3)], axis=1)
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
        for pr in self.prims:
            if pr["region"] is None:
                continue
            dd = self._prim_sdf(pr, verts)
            if pr["sub"]:
                hit = np.abs(dd) < voxel * 2.0
                if pr["kind"] == "cap":
                    hit &= np.abs(nrm @ norm(pr["up"])) > 0.55
            else:
                hit = dd < voxel
            region[hit] = pr["region"]
        ao = self._bake_ao(verts, nrm, max(ext))
        mask = np.zeros((len(verts), 4))
        if self.fur_bones:
            fb = np.array([self.fur_bones.get(b.name, 0.0) for b in self.bones])
            mask[:, 0] = np.sum(fb[bones_arr] * weights_arr, axis=1)
        for pr in self.prims:
            if pr.get("fur") is None:
                continue
            dd = self._prim_sdf(pr, verts)
            w = np.clip(1.0 - dd / (voxel * 2.5), 0.0, 1.0)
            mask[:, 0] = np.maximum(mask[:, 0], w * pr["fur"]) if pr["fur"] > 0 else mask[:, 0] * (1.0 - w)
        if self.mask_fn is not None:
            mask = self.mask_fn(verts, nrm, [self.bones[i].name for i in prim], region, mask)
        # no fur on eyes, teeth, claws/horns, mouth, membranes
        mask[~np.isin(region, (R_SKIN, R_FEATHER, R_HAIR)), 0] = 0.0
        surf0 = dict(pos=verts, nrm=nrm, idx=faces.reshape(-1), bones=bones_arr, weights=weights_arr, region=region, uv=np.zeros((len(verts), 2)), ao=ao, mask=mask)
        surf1 = dict(pos=np.zeros((0, 3)), nrm=np.zeros((0, 3)), idx=np.zeros(0, np.int64), bones=np.zeros((0, 4), np.int32), weights=np.zeros((0, 4)), region=np.zeros(0), uv=np.zeros((0, 2)), ao=np.zeros(0), mask=np.zeros((0, 4)))
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
            s["ao"] = np.concatenate([s["ao"], self._bake_ao(e["pos"], e["nrm"], max(ext), extra=True)])
            s["mask"] = np.concatenate([s["mask"], np.zeros((len(e["pos"]), 4))])
        if "saddle" in self.sockets:
            self.meta["saddle_half_width"] = self._saddle_half_width()
        self._write(out_dir, [surf0, surf1])
        return len(surf0["idx"]) // 3 + len(surf1["idx"]) // 3

    def _saddle_half_width(self):
        """Widest half-width of the body below the saddle (riders spread their legs around it)."""
        sp = np.asarray(self.sockets["saddle"]["pos"], float)
        top = sp - UP * 0.01
        bottom = self.surface_hit(top, -UP, 20.0)
        depth = float(np.linalg.norm(top - bottom)) if bottom is not None else 1.0
        best = 0.0
        for f in (0.1, 0.25, 0.4, 0.55):
            c = top - UP * depth * f
            for sd in (-1.0, 1.0):
                hit = self.surface_hit(c, v3(sd, 0, 0), depth * 3 + 2.0)
                if hit is not None:
                    best = max(best, abs(hit[0] - c[0]))
        return float(best)

    def _bake_ao(self, pos, nrm, size, extra=False):
        """Ambient occlusion from the SDF (0 = open, 1 = fully occluded). Stored as 1-ao in CUSTOM1.w."""
        if len(pos) == 0:
            return np.zeros(0)
        step = (self.ao_scale or size * 0.012)
        occ = np.zeros(len(pos))
        start = 1.5 if extra else 1.0
        for i in range(1, 6):
            h = step * (i + start)
            d = self.eval_sdf(pos + nrm * h, detail=False)
            occ += np.maximum(h - d, 0.0) / h * (0.5 ** (i - 1))
        return np.clip(1.0 - occ * 0.45, 0.0, 1.0)

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
            custom1 = np.concatenate([s["nrm"], (1.0 - s["ao"])[:, None] if "ao" in s else np.zeros((n, 1))], axis=1)
            put("position", s["pos"], np.float32)
            put("normal", s["nrm"], np.float32)
            put("custom0", custom0, np.float32)
            put("custom1", custom1, np.float32)
            put("custom2", s["mask"] if "mask" in s else np.zeros((n, 4)), np.float32)
            put("uv", s["uv"], np.float32)
            put("bones", s["bones"], np.int32)
            put("weights", s["weights"], np.float32)
            put("index", godot_winding(s["pos"], s["nrm"], s["idx"]), np.int32)
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


def godot_winding(pos, nrm, idx):
    """Godot treats CLOCKWISE triangles as front faces. Flip every triangle whose
    counter-clockwise normal agrees with its vertex normals (= would be culled from outside)."""
    pos = np.asarray(pos, float)
    nrm = np.asarray(nrm, float)
    t = np.asarray(idx, np.int64).reshape(-1, 3).copy()
    if len(t) == 0:
        return t.reshape(-1)
    fn = np.cross(pos[t[:, 1]] - pos[t[:, 0]], pos[t[:, 2]] - pos[t[:, 0]])
    vn = nrm[t].sum(axis=1)
    ccw = (fn * vn).sum(axis=1) > 0
    t[ccw] = t[ccw][:, ::-1]
    return t.reshape(-1)


def _axis_coords(lo, hi, base, ranges, grow=0.25):
    """Sample positions from lo to hi: `base` spacing, finer inside ranges [(a, b, spacing)].
    Outside a range the spacing grows linearly with the distance (slope `grow`), so cells stay well shaped."""
    def spacing(t):
        sp = base
        for a, b, v in ranges:
            d = max(a - t, t - b, 0.0)
            sp = min(sp, v + grow * d)
        return sp
    out = [lo]
    t = lo
    while t < hi:
        t = t + spacing(t)
        out.append(t)
    return np.array(out)


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


def _hash3(i):
    h = (i[..., 0] * 73856093) ^ (i[..., 1] * 19349663) ^ (i[..., 2] * 83492791)
    h = (h ^ (h >> 13)) * 1274126177
    return ((h ^ (h >> 16)) & 0xFFFF) / 65535.0


def _vnoise(P):
    """Smooth value noise in [0,1]."""
    fl = np.floor(P)
    f = P - fl
    i = fl.astype(np.int64)
    u = f * f * (3 - 2 * f)
    res = 0.0
    for dx in (0, 1):
        for dy in (0, 1):
            for dz in (0, 1):
                w = (u[:, 0] if dx else 1 - u[:, 0]) * (u[:, 1] if dy else 1 - u[:, 1]) * (u[:, 2] if dz else 1 - u[:, 2])
                res = res + w * _hash3(i + np.array([dx, dy, dz]))
    return res
