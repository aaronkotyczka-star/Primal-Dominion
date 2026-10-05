"""Modular body parts (rigid meshes) attached to rig sockets.
Part frame: +Y = socket normal (outward), -Z = creature forward, +X = right.
Unit size: 1.0 == socket scale (Godot multiplies by socket scale * gene size)."""
import math
import os
import sys

import numpy as np

from sdfrig import Rig, v3, norm, R_KERATIN, R_TOOTH, R_SKIN, R_MEMBRANE, R_GLOW

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "parts")


def part(pid):
    r = Rig(pid, "part")
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    return r


def horn(r, base, direction, length, radius, curve, region=R_KERATIN, rings=8, segs=10):
    r.add_curved_cone(base, direction, length, radius, curve, "root", region, segs=segs, rings=rings)


def P_horns_brow():
    r = part("horns_brow")
    for s in (-1, 1):
        horn(r, v3(s * 0.38, 0, 0), v3(s * 0.15, 0.6, -1.0), 1.4, 0.2, v3(0, -0.25, 0))
    return r


def P_horn_nose():
    r = part("horn_nose")
    horn(r, v3(0, 0, 0), v3(0, 1.0, -0.4), 0.5, 0.12, v3(0, 0, -0.1))
    return r


def P_horns_short():
    r = part("horns_short")
    for s in (-1, 1):
        horn(r, v3(s * 0.12, 0, 0), v3(s * 1.0, 0.5, 0.0), 0.45, 0.13, v3(0, 0.15, 0))
    return r


def P_horns_demon():
    r = part("horns_demon")
    for s in (-1, 1):
        horn(r, v3(s * 0.15, 0, 0), v3(s * 0.5, 0.9, 0.5), 1.2, 0.13, v3(s * 0.3, -0.2, 0.6), rings=10)
    return r


def P_horns_ram():
    r = part("horns_ram")
    for s in (-1, 1):
        pts = []
        horn(r, v3(s * 0.15, 0, 0.05), v3(s * 0.6, 0.6, 0.6), 1.0, 0.16, v3(s * 0.2, -1.2, -0.6), rings=12)
    return r


def P_frill():
    r = part("frill")
    # shield: flattened disc tilted up/back with knobbed rim
    r.add("disc", "root", v3(0, 0.35, 0.25), v3(0, 0.9, 0.55), 0.55, 0.75, sx=1.0, sy=0.12, blend=0.1)
    r.add("neckpad", "root", v3(0, 0.0, 0.0), v3(0, 0.35, 0.25), 0.3, 0.45, sy=0.4, blend=0.15)
    d = norm(v3(0, 0.9, 0.55) - v3(0, 0.35, 0.25))
    for i in range(13):
        a = math.pi * (i / 12.0)
        c = v3(0, 0.9, 0.55) + v3(math.cos(a) * 0.72, 0, 0) + d * math.sin(a) * 0.62 * 0.6 + v3(0, math.sin(a) * 0.3, 0)
        r.add_cone(c, c + norm(c - v3(0, 0.5, 0.3)) * 0.18, 0.06, "root", R_KERATIN, segs=6)
    return r


def P_crest_dilo():
    r = part("crest_dilo")
    for s in (-1, 1):
        r.add(f"c{s}", "root", v3(s * 0.12, 0.05, -0.5), v3(s * 0.14, 0.15, 0.4), 0.18, 0.12, sx=0.12, sy=1.0, blend=0.05)
    return r


def P_frill_neck():
    """Dilophosaurus-style collapsible neck frill (fantasy)."""
    r = part("frill_neck")
    lead, trail, bw = [], [], []
    for i in range(11):
        a = math.pi * (i / 10.0)
        p0 = v3(math.cos(a) * 0.25, math.sin(a) * 0.15, 0)
        p1 = v3(math.cos(a) * 0.95, math.sin(a) * 0.75, 0.25)
        lead.append(p0)
        trail.append(p1)
        bw.append([("root", 1.0)])
    r.add_membrane(lead, bw, trail, bw, R_MEMBRANE, rows=4)
    return r


def P_crest_parasaur():
    r = part("crest_parasaur")
    r.add("tube", "root", v3(0, 0.0, -0.1), v3(0, 0.7, 1.4), 0.16, 0.12, sx=0.7, blend=0.05)
    return r


def P_crest_ptera():
    r = part("crest_ptera")
    r.add("blade", "root", v3(0, 0.0, -0.1), v3(0, 0.4, 1.2), 0.22, 0.05, sx=0.12, sy=1.0, blend=0.05)
    return r


def P_dome():
    r = part("dome")
    r.blob("root", v3(0, 0.0, 0.05), (0.62, 0.55, 0.68), k=0.05)
    r.add("x", "root", v3(0, -0.2, 0), v3(0, -0.2, 0.01), 0.3, 0.3, blend=0.1)
    for i in range(10):
        a = math.pi * 2 * i / 10
        c = v3(math.cos(a) * 0.55, -0.05, 0.1 + math.sin(a) * 0.55)
        r.add_cone(c, c + norm(c) * 0.15 + v3(0, 0.05, 0), 0.06, "root", R_KERATIN, segs=6)
    return r


def P_plates():
    """Row of 3 alternating stegosaur plates (unit length 1 along z)."""
    r = part("plates")
    for i, (z, sd, h) in enumerate([(-0.45, -1, 0.72), (0.0, 1, 1.0), (0.45, -1, 0.82)]):
        base = v3(sd * 0.05, -0.08, z)
        lean = v3(sd * 0.06, 0, 0.12) * h
        c = base + v3(0, h * 0.42, 0) + lean * 0.4
        r.ell("root", c, (0.045 * h + 0.012, h * 0.42, h * 0.3), k=0.03)
        r.cap("root", c, base + v3(0, h * 1.02, 0) + lean, h * 0.22, 0.012, up=(1, 0, 0), sx=0.22, sy=1.0, k=0.04)
        r.cap("root", base + v3(0, -0.02, 0), c, h * 0.12, h * 0.2, up=(1, 0, 0), sx=0.4, sy=1.0, k=0.04)
    r.meta["voxel"] = 0.012
    return r


def P_spikes_back():
    r = part("spikes_back")
    for i in range(5):
        z = -0.5 + i * 0.25
        horn(r, v3(0, -0.05, z), v3(0, 1.0, 0.35), 0.55 - abs(i - 2) * 0.08, 0.07, v3(0, 0, 0.15), rings=5, segs=7)
    return r


def P_thagomizer():
    r = part("thagomizer")
    for s in (-1, 1):
        for k, z in enumerate((-0.2, 0.25)):
            horn(r, v3(s * 0.1, 0.05, z), v3(s * 1.0, 0.55, 0.25 + k * 0.2), 0.9, 0.09, v3(0, 0.0, 0.2), rings=6, segs=8)
    return r


def P_club():
    r = part("club")
    r.blob("root", v3(0, 0, 0.35), (0.5, 0.32, 0.45), k=0.05)
    for s in (-1, 1):
        r.blob("root", v3(s * 0.32, 0, 0.35), (0.3, 0.26, 0.32), k=0.1)
    r.add("x", "root", v3(0, 0, -0.2), v3(0, 0, 0.1), 0.15, 0.25, blend=0.1)
    return r


def P_armor():
    """Osteoderm shell for the back: row of bony scutes + edge spikes (unit = torso diameter)."""
    r = part("armor")
    cy, rr, sxx, syy = -0.34, 0.62, 1.35, 0.58
    r.add("shell", "root", v3(0, cy, 0.62), v3(0, cy, -0.62), rr, rr * 0.92, sx=sxx, sy=syy, blend=0.1)
    for i in range(7):
        z = -0.6 + i * 0.2
        for k in range(-3, 4):
            x = k * 0.21
            ex = rr * sxx
            y = cy + rr * syy * math.sqrt(max(0.0, 1 - (x / ex) ** 2))
            nrm = norm(v3(x / (ex * ex), (y - cy) / (rr * syy) ** 2, 0))
            horn(r, v3(x, y - 0.02, z), nrm, 0.13, 0.085, v3(0, 0, 0), rings=3, segs=6)
        for s in (-1, 1):
            c = v3(s * rr * sxx * 0.97, cy - 0.05, z)
            horn(r, c, v3(s * 1.0, 0.15, 0.1), 0.28, 0.08, v3(0, 0, 0.1), rings=4, segs=6)
    return r


def P_sail():
    r = part("sail")
    # spines + membrane, unit length ~ 2 (spans back), height 1.3
    lead, trail, bw = [], [], []
    n = 12
    for i in range(n):
        t = i / (n - 1)
        z = -1.0 + 2.0 * t
        h = 0.15 + 1.25 * math.sin(t * math.pi) ** 0.8
        lead.append(v3(0, -0.05, z))
        trail.append(v3(0, h, z + 0.08))
        bw.append([("root", 1.0)])
        r.add(f"s{i}", "root", v3(0, -0.05, z), v3(0, h + 0.03, z + 0.08), 0.04, 0.012, blend=0.01, region=R_KERATIN)
    r.add_membrane(lead, bw, trail, bw, R_MEMBRANE, rows=5)
    return r


def P_tusks():
    r = part("tusks")
    for s in (-1, 1):
        horn(r, v3(s * 0.22, 0, 0), v3(s * 0.3, -0.6, -0.6), 2.2, 0.13, v3(s * 0.4, 0.9, -0.3), region=R_TOOTH, rings=12)
    return r


def P_fangs():
    r = part("fangs")
    for s in (-1, 1):
        horn(r, v3(s * 0.25, 0, 0), v3(0, -1.0, -0.1), 1.1, 0.12, v3(0, 0.0, 0.25), region=R_TOOTH, rings=6)
    return r


def _wing(pid, feather):
    r = part(pid)
    # single wing extending to +X; mirrored in engine with negative scale
    lead = [v3(x, 0.08 * math.sin(x * 1.5), -0.05 * x) for x in np.linspace(0, 2.2, 12)]
    trail = []
    for i, p in enumerate(lead):
        u = i / 11
        chord = 0.95 * (1 - u) ** 0.5 + 0.08 if feather else 0.9 * math.sin((1 - u) * math.pi * 0.5) + 0.05
        trail.append(p + v3(0, -0.02, chord))
    bw = [[("root", 1.0)]] * len(lead)
    r.add_membrane(lead, bw, trail, bw, 5 if feather else R_MEMBRANE, rows=5)
    r.add("bone", "root", v3(0, 0, 0), v3(2.2, 0.08 * math.sin(3.3), -0.11), 0.07, 0.015, blend=0.02)
    return r


def P_wing_membrane():
    return _wing("wing_membrane", False)


def P_wing_feather():
    return _wing("wing_feather", True)


def P_saddle():
    r = part("saddle")
    r.add("seat", "root", v3(0, 0.02, 0.35), v3(0, 0.02, -0.35), 0.38, 0.38, sx=1.0, sy=0.18, blend=0.05)
    r.add("pommel", "root", v3(0, 0.05, -0.35), v3(0, 0.22, -0.4), 0.09, 0.07, blend=0.04)
    r.add("cantle", "root", v3(0, 0.05, 0.38), v3(0, 0.18, 0.42), 0.18, 0.12, sx=1.6, sy=0.5, blend=0.04)
    for s in (-1, 1):
        r.add(f"flap{s}", "root", v3(s * 0.33, -0.02, 0.0), v3(s * 0.45, -0.35, 0.0), 0.2, 0.18, sx=0.15, sy=1.0, blend=0.04)
    return r


def P_bone_spikes():
    """Demonic bone growths for corrupted/monster hybrids."""
    r = part("bone_spikes")
    rng = np.random.default_rng(7)
    for i in range(9):
        z = -0.6 + i * 0.15
        s = 1 if i % 2 else -1
        horn(r, v3(s * 0.12 * rng.random(), -0.05, z), v3(s * 0.4, 1.0, 0.5), 0.5 + rng.random() * 0.4, 0.07,
             v3(0, -0.2, 0.4), region=R_TOOTH, rings=5, segs=6)
    return r


def P_tail_demon():
    r = part("tail_demon")
    pts = [v3(0, 0, 0), v3(0, -0.6, 0.5), v3(0, -0.9, 1.3), v3(0, -0.85, 2.1), v3(0, -0.6, 2.8)]
    for i in range(4):
        r.add(f"t{i}", "root", pts[i], pts[i + 1], 0.16 * (1 - i * 0.22), 0.16 * (1 - (i + 1) * 0.22), blend=0.05)
    horn(r, pts[4], v3(0, 0.2, 1.0), 0.4, 0.1, v3(0, 0.3, 0), rings=4)
    return r


def P_eye_glow():
    r = part("eye_glow")
    r.add_sphere(v3(0, 0, 0), 0.1, "root", R_GLOW, segs=8, rings=6)
    return r


PARTS = {k[2:]: v for k, v in globals().items() if k.startswith("P_")}


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    ids = sys.argv[1:] or list(PARTS.keys())
    for pid in ids:
        rig = PARTS[pid]()
        if not any(b.geo for b in rig.bones) and not rig.blobs and not rig.prims:
            # explicit-only parts: add a tiny hidden blob so marching cubes has a surface
            rig.add("hidden", "root", v3(0, -0.01, 0), v3(0, -0.01, 0.001), 0.02, 0.02, blend=0.01)
        vox = rig.meta.pop("voxel", 0.025)
        tris = rig.build(OUT, voxel=vox, target_tris=3000, smooth_iter=3)
        print(pid, tris)
