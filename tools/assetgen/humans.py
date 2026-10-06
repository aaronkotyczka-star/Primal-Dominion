"""Humanoid bodies (humans, goblins, demons) with anatomical heads, fingered hands,
layered clothing (smooth hem masks + raised hems) and a hair cap rendered with shells.

Bone names/positions match the old humanoid layout so the procedural animator and the
part sockets keep working. Dimensions are written for a 1.8 m adult and scaled by s.
"""
import math

import numpy as np

from sdfrig import Rig, v3, norm, R_TOOTH, R_MOUTH
from families import _claws


def _seg_t(p, a, b):
    d = b - a
    L2 = max(float(d @ d), 1e-9)
    return np.clip((p - a) @ d / L2, 0.0, 1.0)


def _soft(x, w):
    """0..1 ramp across a hem line (x = signed distance in meters)."""
    return np.clip(0.5 + x / w, 0.0, 1.0)


def humanoid(rid, height=1.8, build=1.0, head_scale=1.0, ears=0.0, nose=1.0, goblin=False, demon=False,
             female=False, hair="short", family="humanoid"):
    r = Rig(rid, family)
    h = height
    s = h / 1.8
    bw = build
    fem = 1.0 if female else 0.0
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    hipY = h * 0.52
    P = v3(0, hipY, 0)
    SP = v3(0, h * 0.63, 0.0)
    CH = v3(0, h * 0.74, 0.0)
    NK = v3(0, h * 0.84, -0.005 * h)
    HD = v3(0, h * 0.875, -0.005 * h)
    hs = head_scale
    hipw = h * (0.105 if not female else 0.113) * bw
    # ------------------------------------------------------------------ trunk
    r.add("pelvis", "root", P + v3(0, -h * 0.01, 0), SP, 0.13 * s * bw, 0.115 * s * bw, sx=1.25 + 0.1 * fem, sy=0.78, blend=0.05 * s)
    r.add("spine", "pelvis", SP, CH, 0.112 * s * bw, 0.14 * s * bw, sx=1.22 - 0.1 * fem, sy=0.74, blend=0.06 * s)
    r.add("chest", "spine", CH, NK + v3(0, -h * 0.02, 0), 0.145 * s * bw, 0.07 * s * bw, sx=1.25 - 0.12 * fem, sy=0.72, blend=0.05 * s)
    r.add("neck1", "chest", NK + v3(0, -h * 0.025, 0.004 * s), HD + v3(0, 0.0, 0.006 * s), 0.054 * s * (1 - 0.1 * fem), 0.048 * s * (1 - 0.1 * fem), sy=0.95, blend=0.025 * s)
    # ribcage, abdomen, pelvis masses, glutes, shoulder girdle, back
    r.ell("chest", v3(0, h * 0.715, 0.004 * s), (0.152 * s * bw * (1 - 0.08 * fem), 0.165 * s, 0.112 * s * bw), k=0.04 * s)
    r.ell("spine", v3(0, h * 0.6, -0.012 * s), (0.135 * s * bw * (1 - 0.1 * fem), 0.11 * s, 0.098 * s * bw), k=0.05 * s)
    r.ell("pelvis", v3(0, hipY + 0.035 * s, 0.006 * s), ((0.148 + 0.02 * fem) * s * bw, 0.09 * s, 0.094 * s * bw), k=0.04 * s)
    for sd in (-1, 1):
        r.ell("pelvis", v3(sd * 0.058 * s, hipY - 0.035 * s, 0.05 * s), ((0.062 + 0.008 * fem) * s * bw, 0.074 * s, 0.05 * s), k=0.03 * s)
        # trapezius slope neck -> shoulder
        r.cap("chest", v3(sd * 0.03 * s, h * 0.825, 0.012 * s), v3(sd * 0.165 * s * bw, h * 0.792, 0.01 * s), 0.04 * s, 0.035 * s, up=(0, 1, 0), sy=0.55, k=0.03 * s)
        # scapulae
        r.ell("chest", v3(sd * 0.075 * s, h * 0.745, 0.075 * s), (0.06 * s, 0.075 * s, 0.03 * s), k=0.03 * s)
        if female:
            r.ell("chest", v3(sd * 0.062 * s, h * 0.71, -0.085 * s), (0.056 * s, 0.054 * s, 0.05 * s), k=0.03 * s)
        else:
            r.ell("chest", v3(sd * 0.062 * s, h * 0.73, -0.088 * s), (0.068 * s * bw, 0.05 * s, 0.03 * s), k=0.03 * s)
    # ------------------------------------------------------------------ head
    r.add("head", "neck1", HD, HD + v3(0, 0.18 * s * hs, 0), 0, 0, geo=False)
    r.add("jaw", "head", HD + v3(0, 0.062 * s * hs, -0.011 * s), HD + v3(0, 0.017 * s * hs, -0.073 * s * hs), 0, 0, geo=False)
    k = s * hs
    Hc = HD + v3(0, 0.129 * k, -0.006 * s)
    G = lambda x, y, z: Hc + v3(x * k, y * k, z * k)
    wide = 1.18 if (goblin or demon) else 1.0
    # Profile (rel. to Hc, forward = -z, 1.8 m adult): top +0.11, forehead -0.093, brow ridge -0.098 @ y 0,
    # cornea -0.082 @ -0.02, nose tip -0.116 @ -0.064, lips -0.098 @ -0.1, chin -0.094 @ -0.123, bottom -0.139
    r.ell("head", G(0, 0.02, 0.008), (0.073 * wide, 0.089, 0.098), k=0.02 * k)
    r.ell("head", G(0, 0.035, -0.045), (0.064 * wide, 0.055, 0.048), k=0.02 * k)
    for sd in (-1, 1):
        r.ell("head", G(sd * 0.084 * wide, 0.0, -0.038), (0.014, 0.028, 0.028), k=0.012 * k, sub=True)
    r.ell("head", G(0, 0.002, -0.08 + 0.003 * fem), (0.046 * wide, 0.012 * (1.5 if goblin or demon else 1.0) * (1 - 0.35 * fem), 0.016 * (1 - 0.3 * fem)), k=0.016 * k)
    for sd in (-1, 1):
        r.ell("head", G(sd * 0.032, -0.024, -0.064), (0.022, 0.02, 0.016), k=0.01 * k)
        r.ell("head", G(sd * 0.048, -0.036, -0.058), (0.024, 0.016, 0.024), k=0.012 * k)
        r.ell("head", G(sd * 0.036, -0.06, -0.066), (0.02, 0.022, 0.019), k=0.012 * k)
    nl = nose
    r.cap("head", G(0, -0.014, -0.086), G(0, -0.052 * nl, -0.1 - 0.012 * (nl - 1)), 0.0046, 0.0074 * nl, up=(0, 0, -1), sx=1.2, k=0.006 * k)
    r.ell("head", G(0, -0.06 * nl, -0.1 - 0.012 * (nl - 1)), (0.0105 * nl, 0.0098 * nl, 0.0105 * nl), k=0.005 * k)
    for sd in (-1, 1):
        r.ell("head", G(sd * 0.0122 * nl, -0.067, -0.092), (0.0078 * nl, 0.0072, 0.0078), k=0.004 * k)
        r.ell("head", G(sd * 0.0075 * nl, -0.0715, -0.096), (0.0032, 0.0021, 0.0034), k=0.0015 * k, sub=True)
        # cheek fat pad (avoid the gaunt look)
        r.ell("head", G(sd * 0.042, -0.07, -0.06), (0.022 * (1 - 0.25 * fem), 0.025 * (1 - 0.2 * fem), 0.022), k=0.016 * k)
    r.ell("head", G(0, -0.078, -0.066), (0.038 * wide, 0.03, 0.03), k=0.014 * k)
    r.ell("head", G(0, -0.084, -0.0915), (0.0105, 0.0075, 0.0052), k=0.004 * k)
    r.ell("head", G(0, -0.0925, -0.0912), (0.024 - 0.001 * fem, 0.0065 * (1 + 0.25 * fem), 0.0075 * (1 + 0.15 * fem)), k=0.0035 * k)
    r.ell("jaw", G(0, -0.1045, -0.0892), (0.0215 - 0.001 * fem, 0.0075 * (1 + 0.3 * fem), 0.0085 * (1 + 0.15 * fem)), k=0.0035 * k)
    r.cap("head", G(-0.0245, -0.0988, -0.0965), G(0.0245, -0.0988, -0.0965), 0.0012, 0.0012, up=(0, 1, 0), k=0.0018 * k, sub=True, region=R_MOUTH)
    for sd in (-1, 1):
        r.ell("head", G(sd * 0.026, -0.099, -0.086), (0.004, 0.004, 0.004), k=0.003 * k, sub=True)
    # mandible + chin (male jaw squarer)
    for sd in (-1, 1):
        r.ell_along("jaw", G(sd * (0.05 - 0.006 * fem) * wide, -0.062, -0.004), G(sd * (0.03 - 0.005 * fem), -0.12 + 0.004 * fem, -0.06), 0.014 * (1 - 0.25 * fem), 0.018 * (1 - 0.2 * fem), up=(0, 0, -1), k=0.03 * k)
        r.ell("head", G(sd * (0.055 - 0.006 * fem) * wide, -0.06, -0.025), (0.018 * (1 - 0.2 * fem), 0.03, 0.03), k=0.02 * k)
    r.ell("jaw", G(0, -0.112 + 0.004 * fem, -0.045), (0.04 * (1 - 0.18 * fem), 0.022, 0.04), k=0.02 * k)
    r.ell("jaw", G(0, -0.123, -0.078), (0.019 + 0.005 * (1 - fem), 0.016, 0.016), k=0.01 * k)
    r.ell("jaw", G(0, -0.112, -0.086), (0.012, 0.005, 0.004), k=0.004 * k, sub=True)
    # eyes: orbital soft tissue around the eyeball, almond-shaped lid opening, upper lid fold
    er = 0.0118 * k * (1.25 if goblin else 1.0) * (1 + 0.04 * fem)
    for sd in (-1, 1):
        ec = G(sd * 0.0315, -0.02, -0.0702)
        r.add_eye(ec, er, v3(sd * 0.06, -0.02, -1.0), "head")
        r.ell("head", ec + v3(0, 0.0005 * k, -0.0005 * k), (er * 1.32, er * 1.18, er * 1.12), k=0.004 * k)
        ax = (v3(1, sd * 0.12, 0), v3(-sd * 0.12, 1, 0), v3(0, 0, 1))
        r.ell("head", ec + v3(sd * 0.001 * k, 0.0006 * k, -0.011 * k), (0.0155 * k, 0.0046 * k, 0.012 * k), ax, k=0.0025 * k, sub=True)
        r.ell("head", ec + v3(0, 0.0105 * k, -0.0075 * k), (0.016 * k, 0.0042 * k, 0.008 * k), k=0.004 * k)
        # ears (between brow and nose base)
        if ears > 0:
            e0 = G(sd * 0.074, -0.03, 0.008)
            r.cap("head", e0, e0 + v3(sd * 0.07 * ears * k, 0.035 * ears * k, 0.03 * k), 0.022 * k, 0.004 * k, up=(sd, 0.3, 0), sx=1.0, sy=0.3, k=0.008 * k)
        else:
            ea = G(sd * 0.077, -0.035, 0.01)
            ax = (v3(1, 0, 0.3 * sd), v3(0, 1, 0.12), v3(-0.3 * sd, 0, 1))
            r.ell("head", ea, (0.008 * k, 0.03 * k, 0.019 * k), ax, k=0.005 * k)
            r.ell("head", ea + v3(sd * 0.0065 * k, 0.002 * k, -0.002 * k), (0.004 * k, 0.019 * k, 0.011 * k), ax, k=0.002 * k, sub=True)
            r.ell("head", ea + v3(sd * 0.003 * k, -0.01 * k, -0.006 * k), (0.004 * k, 0.006 * k, 0.005 * k), ax, k=0.002 * k, sub=True)
    # fine meshing for face and hands
    r.fine_boxes.append((Hc + v3(-0.1, -0.16, -0.13) * k, Hc + v3(0.1, 0.13, 0.12) * k, 0.0017 * k))
    # ------------------------------------------------------------------ hair
    hair_on = not (goblin or demon) and hair != "none"
    if hair_on:
        # hair = (cranium grown by the hair thickness) ∩ (volume above the hairline)
        th = 0.011 if hair == "short" else (0.007 if hair == "bun" else 0.016)
        r.ell("head", G(0, 0.02, 0.014), (0.073 * wide + th, 0.089 + th, 0.096 + th))
        if hair == "bun":
            # hair pulled back tight, gathered in a bun at the back of the head
            r.ell("head", G(0, 0.1, 0.038), (0.14, 0.13, 0.138))
            r.isect_end(2, "head", k=0.006 * k, fur=0.85)
            r.ell("head", G(0, 0.02, 0.008), (0.073 * wide + th * 0.8, 0.089 + th * 0.8, 0.098 + th * 0.8))
            r.ell("head", G(0, -0.01, 0.085), (0.1, 0.085, 0.07))
            r.isect_end(2, "head", k=0.01 * k, fur=0.85)
            r.ell("head", G(0, 0.03, 0.115), (0.037, 0.035, 0.03), k=0.012 * k, fur=0.7)
        elif hair == "short":
            r.ell("head", G(0, 0.1, 0.038), (0.14, 0.13, 0.138))
            r.isect_end(2, "head", k=0.006 * k, fur=1.0)
            # back and sides reach down to the nape
            r.ell("head", G(0, 0.02, 0.008), (0.073 * wide + th * 0.8, 0.089 + th * 0.8, 0.098 + th * 0.8))
            r.ell("head", G(0, -0.01, 0.085), (0.1, 0.085, 0.07))
            r.isect_end(2, "head", k=0.01 * k, fur=1.0)
        else:
            # chin-length bob: same high hairline as the short cut, plus side/back volumes that stay
            # beside/behind the face and a side-swept fringe above the brows
            r.ell("head", G(0, 0.1, 0.038), (0.14, 0.13, 0.138))
            r.isect_end(2, "head", k=0.006 * k, fur=1.0)
            r.ell("head", G(0, -0.035, 0.04), (0.09, 0.085, 0.082), k=0.025 * k, fur=1.0)
            for sd in (-1, 1):
                r.ell("head", G(sd * 0.084, -0.045, 0.012), (0.02, 0.07, 0.058), k=0.02 * k, fur=1.0)
            r.ell("head", G(0.018, 0.058, -0.078), (0.052, 0.018, 0.026), (v3(1, -0.3, 0), v3(0.3, 1, 0), v3(0, 0, 1)), k=0.012 * k, fur=1.0)
        if hair == "beard":
            # full short beard along the jaw, chin and upper lip
            for sd in (-1, 1):
                r.ell_along("jaw", G(sd * 0.056 * wide, -0.05, 0.0), G(sd * 0.033, -0.122, -0.062), 0.016, 0.021, up=(0, 0, -1), k=0.02 * k, fur=1.0)
                r.ell("head", G(sd * 0.05, -0.075, -0.05), (0.022, 0.03, 0.03), k=0.015 * k, fur=0.9)
            r.ell("jaw", G(0, -0.124, -0.072), (0.03, 0.025, 0.026), k=0.014 * k, fur=1.0)
            r.cap("head", G(-0.026, -0.087, -0.09), G(0.026, -0.087, -0.09), 0.0055, 0.0055, up=(0, 1, 0), sy=0.7, k=0.004 * k, fur=0.7)
        # eyebrows: short hair shells
        for sd in (-1, 1):
            r.cap("head", G(sd * 0.016, -0.001, -0.092), G(sd * 0.034, 0.003, -0.089), 0.0042, 0.004, up=(0, 1, 0), sy=0.55, k=0.003 * k, fur=0.2)
            r.cap("head", G(sd * 0.034, 0.003, -0.089), G(sd * 0.052, -0.002, -0.078), 0.004, 0.0028, up=(0, 1, 0), sy=0.55, k=0.003 * k, fur=0.2)
    if goblin or demon:
        for sd in (-1, 1):
            r.add_cone(G(sd * 0.024, -0.098, -0.086), G(sd * 0.026, -0.07 if demon else -0.078, -0.09), 0.006 * k, "jaw", R_TOOTH, segs=5)
    # ------------------------------------------------------------------ arms
    for sd, sn in ((-1, "L"), (1, "R")):
        # slight A-pose (gap to the torso) -- see animator arm_abduct
        sh = CH + v3(sd * h * 0.118 * bw, h * 0.045, 0.01)
        el = sh + v3(sd * h * 0.055 * bw, -h * 0.165, 0.01 * h)
        wr = el + v3(sd * h * 0.038 * bw, -h * 0.145, -0.02 * h)
        hn = wr + v3(sd * h * 0.018, -h * 0.083, -0.005 * h)
        fa = 1.0 - 0.15 * fem
        r.add(f"clav_{sn}", "chest", CH + v3(sd * h * 0.02, h * 0.04, 0), sh, 0.035 * s * bw, 0.04 * s * bw, blend=0.025 * s)
        r.add(f"uarm_{sn}", f"clav_{sn}", sh, el, 0.043 * s * bw * fa, 0.033 * s * bw * fa, blend=0.012 * s)
        r.add(f"farm_{sn}", f"uarm_{sn}", el, wr, 0.032 * s * bw * fa, 0.023 * s * bw * fa, sx=1.12, blend=0.012 * s)
        r.add(f"hand_{sn}", f"farm_{sn}", wr, hn, 0.0, 0.0, geo=False)
        # deltoid, biceps/triceps, forearm muscles
        r.ell(f"uarm_{sn}", sh + v3(sd * 0.008 * s, -0.03 * s, 0), (0.044 * s * bw * fa, 0.06 * s, 0.045 * s * bw * fa), k=0.025 * s)
        r.ell_along(f"uarm_{sn}", sh + (el - sh) * 0.25, sh + (el - sh) * 0.8, 0.038 * s * bw * fa, 0.04 * s * bw * fa, up=(0, 0, -1), k=0.014 * s)
        r.ell_along(f"farm_{sn}", el + (wr - el) * 0.05, el + (wr - el) * 0.6, 0.035 * s * bw * fa, 0.037 * s * bw * fa, up=(0, 0, -1), k=0.012 * s)
        _hand(r, f"hand_{sn}", wr, hn, sd, s * (1.0 - 0.1 * fem) * (1.15 if demon else 1.0), claws=(goblin or demon))
        lo_ = np.minimum(wr, hn) - 0.07 * s
        hi_ = np.maximum(wr, hn) + 0.07 * s
        r.fine_boxes.append((lo_, hi_, 0.0024 * s))
        if goblin or demon:
            _claws(r, f"hand_{sn}", 4, 0.03 * s * (1.8 if demon else 1.0), 0.011 * s, curve_down=0.6)
        r.chain(f"arm_{sn}", [f"clav_{sn}", f"uarm_{sn}", f"farm_{sn}", f"hand_{sn}"])
        # ------------------------------------------------------------------ legs
        hip = P + v3(sd * hipw * 0.85, -h * 0.03, 0)
        kn = v3(sd * hipw * 0.75, h * 0.28, -0.01 * h)
        an = v3(sd * hipw * 0.7, h * 0.045, 0.01 * h)
        toe = an + v3(0, -h * 0.03, -h * 0.1)
        r.add(f"thigh_{sn}", "pelvis", hip, kn, 0.078 * s * bw, 0.05 * s * bw, blend=0.03 * s)
        r.add(f"shin_{sn}", f"thigh_{sn}", kn, an, 0.05 * s * bw, 0.03 * s * bw, blend=0.02 * s)
        r.ell_along(f"thigh_{sn}", hip + v3(-sd * 0.004 * s, 0.0, -0.01 * s), kn + v3(0, 0.07 * s, -0.012 * s), 0.08 * s * bw, 0.079 * s * bw, up=(0, 0, -1), k=0.025 * s)
        r.ell_along(f"shin_{sn}", kn + v3(0, -0.04 * s, 0.014 * s), kn + (an - kn) * 0.55 + v3(0, 0, 0.014 * s), 0.043 * s * bw, 0.05 * s * bw, up=(0, 0, 1), k=0.015 * s)
        r.ell(f"shin_{sn}", kn + v3(0, 0.005 * s, -0.035 * s), (0.032 * s, 0.035 * s, 0.02 * s), k=0.012 * s)
        r.add(f"meta_{sn}", f"shin_{sn}", an, an + (toe - an) * 0.6, 0.0, 0.0, geo=False)
        r.add(f"toe_{sn}", f"meta_{sn}", an + (toe - an) * 0.6, toe, 0.0, 0.0, geo=False)
        _boot(r, f"meta_{sn}", f"toe_{sn}", an, toe, sd, s, bare=(goblin or demon))
        r.chain(f"leg_{sn}", [f"thigh_{sn}", f"shin_{sn}", f"meta_{sn}", f"toe_{sn}"])
    # ------------------------------------------------------------------ clothing hems (raised edges)
    clothed = not demon
    if clothed:
        waist_y = hipY + 0.085 * s
        # belt
        r.ell("pelvis", v3(0, waist_y, 0.004 * s), ((0.16 + 0.012 * fem) * s * bw, 0.022 * s, 0.112 * s * bw), k=0.004 * s)
        r.ell("pelvis", v3(0, waist_y, -0.112 * s * bw), (0.022 * s, 0.018 * s, 0.006 * s), k=0.003 * s)
        hem_y = hipY - 0.1 * s
        for sd, sn in ((-1, "L"), (1, "R")):
            # tunic hem around the upper thigh, sleeve cuff, boot top
            th_ = r.b(f"thigh_{sn}")
            tq = _seg_t(v3(th_.head[0], hem_y, th_.head[2]), th_.head, th_.tail)
            c = th_.head + (th_.tail - th_.head) * tq
            r.ell_along(f"thigh_{sn}", c - norm(th_.tail - th_.head) * 0.004 * s, c + norm(th_.tail - th_.head) * 0.004 * s,
                        0.083 * s * bw, 0.083 * s * bw, up=(0, 0, -1), k=0.003 * s)
            fb = r.b(f"farm_{sn}")
            c = fb.head + (fb.tail - fb.head) * 0.3
            dd = norm(fb.tail - fb.head)
            r.ell_along(f"farm_{sn}", c - dd * 0.004 * s, c + dd * 0.004 * s, 0.04 * s * bw, 0.042 * s * bw, up=(0, 0, -1), k=0.003 * s)
    r.chain("spine", ["pelvis", "spine", "chest"])
    r.chain("neck", ["neck1", "head"])
    # ------------------------------------------------------------------ sockets (unchanged names)
    r.socket("head_top", "head", HD + v3(0, 0.23 * k, 0), (0, 1, 0), 0.22 * k)
    r.socket("brow_L", "head", HD + v3(-0.06 * k, 0.195 * k, -0.06 * k), (-0.5, 1, -0.2), 0.18 * k)
    r.socket("brow_R", "head", HD + v3(0.06 * k, 0.195 * k, -0.06 * k), (0.5, 1, -0.2), 0.18 * k)
    for sn in ("L", "R"):
        hb = r.b(f"hand_{sn}")
        r.socket(f"hand_{sn}", f"hand_{sn}", hb.head * 0.4 + hb.tail * 0.6, (0, 0, -1), 1.0)
    r.socket("back", "chest", CH + v3(0, h * 0.03, h * 0.08), (0, 0, 1), h * 0.2)
    r.socket("back_front", "chest", CH + v3(0, h * 0.03, h * 0.08), (0, 0, 1), h * 0.2)
    r.socket("shoulder_L", "chest", CH + v3(-h * 0.08, h * 0.06, h * 0.06), (-0.3, 0.2, 1), h * 0.3)
    r.socket("shoulder_R", "chest", CH + v3(h * 0.08, h * 0.06, h * 0.06), (0.3, 0.2, 1), h * 0.3)
    r.socket("tail_tip", "pelvis", P + v3(0, 0, h * 0.08), (0, -0.3, 1), h * 0.3)
    r.socket("tail_mid", "pelvis", P + v3(0, 0, h * 0.08), (0, -0.3, 1), h * 0.3)
    r.socket("neck_back", "chest", NK + v3(0, 0, h * 0.04), (0, 0.5, 1), h * 0.1)
    r.socket("mouth", "jaw", r.b("jaw").tail, (0, 0, -1), 0.112 * k)
    r.socket("pauldron_L", "uarm_L", r.b("uarm_L").head + v3(0, h * 0.01, 0), (-1, 0.6, 0), h * 0.1)
    r.socket("pauldron_R", "uarm_R", r.b("uarm_R").head + v3(0, h * 0.01, 0), (1, 0.6, 0), h * 0.1)

    neck_line_y = NK[1] - 0.022 * s
    waist_y = hipY + 0.085 * s
    hem_y = hipY - 0.1 * s
    boot_y = h * 0.2

    def mask_fn(verts, nrm, bones, region, mask):
        if not clothed:
            return mask
        bones = np.asarray(bones)
        y = verts[:, 1]
        x = np.abs(verts[:, 0])
        z = verts[:, 2]
        top = np.zeros(len(verts))
        bot = np.zeros(len(verts))
        lea = np.zeros(len(verts))
        torso = np.isin(bones, ("pelvis", "spine", "chest", "clav_L", "clav_R", "uarm_L", "uarm_R", "neck1"))
        thigh = np.array([b.startswith("thigh") for b in bones])
        shin = np.array([b.startswith("shin") for b in bones])
        foot = np.array([b.startswith(("meta", "toe")) for b in bones])
        # tunic: torso + upper arms + forearm to the cuff, down to the hem; V-neck at the front
        vneck = (neck_line_y - 0.05 * s + np.clip(x, 0, 0.06 * s) * 1.4) - y
        vneck = np.where(z < 0, vneck, neck_line_y - y)
        t_tunic = np.minimum(_soft(vneck, 0.008 * s), _soft(y - hem_y, 0.008 * s))
        top = np.where(torso | thigh, t_tunic, top)
        for sn in ("L", "R"):
            fb = r.b(f"farm_{sn}")
            m = bones == f"farm_{sn}"
            tt = _seg_t(verts[m], fb.head, fb.tail)
            top[m] = _soft((0.3 - tt) * np.linalg.norm(fb.tail - fb.head), 0.008 * s)
        top = np.where(np.isin(bones, ("neck1",)), np.minimum(top, _soft(neck_line_y - y, 0.008 * s)), top)
        # trousers: legs below the tunic hem down to the boots, pelvis below the hem
        bot = np.where(thigh | shin | (bones == "pelvis"), 1.0 - top, 0.0)
        # belt (leather) and boots
        lea = np.maximum(lea, np.where(torso, _soft(0.024 * s - np.abs(y - waist_y), 0.004 * s), 0.0))
        lea = np.maximum(lea, np.where(shin | foot, _soft(boot_y - y, 0.008 * s), 0.0))
        lea = np.where(foot, 1.0, lea)
        bot = bot * (1.0 - lea)
        top = top * (1.0 - lea)
        mask[:, 1] = top
        mask[:, 2] = bot
        mask[:, 3] = lea
        # no hair shells on clothes
        mask[:, 0] = mask[:, 0] * (1.0 - np.maximum(np.maximum(top, bot), lea))
        return mask

    r.mask_fn = mask_fn
    if hair_on:
        crown = Hc + v3(0, 0.07 * k, 0.03 * k)
        r.meta["fur"] = dict(len=(0.028 if hair in ("bob", "beard") else 0.02) * k, density=1400.0, stiff=0.2 if hair == "bob" else 0.12,
                             comb=[0.0, -0.6, 0.4], crown=list(map(float, crown)), radial=1.0, hair=True, clump=0.6,
                             tip_light=0.15, shells=10)
    r.meta.update(gait="human", hip_height=hipY, length=0.4 * h, height=h,
                  arm_abduct=float(math.atan2(h * 0.055 * bw, h * 0.165)))
    return r


def _hand(r, bone, wr, hn, sd, s, claws=False):
    """Palm, four slightly curled fingers and an opposed thumb (relaxed grip)."""
    d = norm(hn - wr)
    inward = v3(-sd, 0, 0)
    palm_n = norm(inward - d * (inward @ d))  # palm faces the body
    side = None
    L = np.linalg.norm(hn - wr)
    pc = wr + d * L * 0.42
    r.ell_along(bone, wr + d * L * 0.05, wr + d * L * 0.62, 0.039 * s, 0.014 * s, up=palm_n, k=0.008 * s)
    knuckle = wr + d * L * 0.6
    fwd = v3(0, 0, -1)
    for i, (off, ln) in enumerate(((0.024, 0.075), (0.008, 0.08), (-0.009, 0.076), (-0.025, 0.062))):
        base = knuckle + norm(fwd - d * (fwd @ d)) * off * s
        # three phalanges curling towards the palm
        a = base
        dirv = d
        r0 = 0.0085 * s
        for j, frac in enumerate((0.45, 0.32, 0.23)):
            seg = ln * s * frac
            b = a + dirv * seg
            r.cap(bone, a, b, r0, r0 * 0.9, k=0.003 * s)
            a = b
            dirv = norm(dirv * math.cos(0.32) + (-palm_n) * -math.sin(0.32))
            r0 *= 0.9
    # thumb from the wrist side, opposed
    tb = wr + d * L * 0.18 + norm(fwd - d * (fwd @ d)) * 0.028 * s
    tdir = norm(d * 0.6 + norm(fwd - d * (fwd @ d)) * 0.25 + palm_n * 0.5)
    a = tb
    r0 = 0.0105 * s
    for frac in (0.45, 0.32, 0.23):
        b = a + tdir * 0.068 * s * frac
        r.cap(bone, a, b, r0, r0 * 0.9, k=0.004 * s)
        a = b
        tdir = norm(tdir + d * 0.25)
        r0 *= 0.9
    _ = (pc, side, claws)


def _boot(r, meta_bone, toe_bone, an, toe, sd, s, bare=False):
    f = norm(v3(toe[0] - an[0], 0, toe[2] - an[2]))
    # heel, arch, ball, toe cap, sole
    r.ell(meta_bone, an + v3(0, -0.03 * s, 0.022 * s), (0.034 * s, 0.035 * s, 0.04 * s), k=0.012 * s)
    r.cap(meta_bone, an + v3(0, -0.035 * s, 0.02 * s), toe + v3(0, -0.012 * s, 0) - f * 0.02 * s, 0.036 * s, 0.038 * s, up=(0, 1, 0), sx=1.1, sy=0.75, k=0.012 * s)
    r.ell(toe_bone, toe + v3(0, -0.012 * s, 0.01 * s), (0.04 * s, 0.026 * s, 0.045 * s), k=0.01 * s)
    if not bare:
        # sole slab and the boot shaft cuff
        r.cap(toe_bone, an + v3(0, -0.068 * s, 0.03 * s), toe + v3(0, -0.032 * s, -0.012 * s), 0.038 * s, 0.042 * s, up=(0, 1, 0), sx=1.15, sy=0.3, k=0.004 * s)
        r.ell_along(meta_bone, an + v3(0, 0.27 * s - 0.004 * s, 0), an + v3(0, 0.27 * s + 0.004 * s, 0), 0.048 * s, 0.05 * s, up=(0, 0, -1), k=0.003 * s)
