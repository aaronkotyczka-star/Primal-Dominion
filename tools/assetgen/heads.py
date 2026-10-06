"""Species-specific skulls that need more anatomy than the generic builders:
canids (wolf/hellhound), felids (smilodon) and tyrannosaurid/dromaeosaurid theropods.
All measures are fractions of the head length L (occiput -> snout tip)."""
import math

import numpy as np

from sdfrig import v3, norm, R_EYE, R_TOOTH, R_KERATIN, R_MOUTH


def _basis(f):
    f = norm(np.asarray(f, float))
    s = norm(np.cross(f, v3(0, 1, 0))) if abs(f[1]) < 0.97 else v3(1, 0, 0)
    u = norm(np.cross(s, f))
    return f, s, u


def carnivore_head(r, HB, f, L, *, felid=False, ears=1.0, fang=0.0, eye=1.0):
    """Wolf-like (long muzzle, big upright ears) or cat-like (short muzzle, round head) skull."""
    f, s, u = _basis(f)
    P = lambda a, b, c=0.0: HB + f * (a * L) + u * (b * L) + s * (c * L)
    ax = (s, u, f)
    mz = 0.34 if felid else 0.5  # muzzle share of the head length
    m0 = 1.0 - mz
    # cranium (wide, rounded), sagittal brow, occipital
    r.ell("head", P(0.26, 0.04), ((0.23 if not felid else 0.27) * L, (0.2 if not felid else 0.23) * L, (0.27) * L), ax, k=0.05 * L)
    r.ell("head", P(m0 - 0.06, 0.1), ((0.15) * L, (0.085) * L, (0.12) * L), ax, k=0.05 * L)
    # zygomatic arches -> broad cheeks (cats: very broad)
    r.ell("head", P(m0 - 0.1, -0.06), ((0.26 if not felid else 0.31) * L, (0.12) * L, (0.15) * L), ax, k=0.05 * L)
    # muzzle: tapered, with a defined stop below the eyes; lips hang slightly
    r.cap("head", P(m0 - 0.04, -0.01), P(0.95, -0.06 if not felid else -0.04), (0.13 if not felid else 0.16) * L, (0.065 if not felid else 0.1) * L, up=u, sx=0.95, sy=0.85, k=0.04 * L)
    r.ell("head", P(0.98, -0.045), ((0.055 if not felid else 0.07) * L, (0.04) * L, (0.035) * L), ax, k=0.012 * L, region=R_KERATIN)
    for sd in (-1, 1):
        # upper lip flews and whisker pads
        r.ell("head", P(0.78 if not felid else 0.85, -0.12, sd * 0.065), ((0.05) * L, (0.06) * L, (0.14 if not felid else 0.08) * L), ax, k=0.03 * L)
        # nostrils
        r.ell("head", P(1.005, -0.04, sd * 0.022), ((0.012) * L, (0.009) * L, (0.012) * L), ax, k=0.004 * L, sub=True)
    # lower jaw, chin
    r.cap("jaw", P(0.32, -0.15), P(0.9 if not felid else 0.92, -0.17 if not felid else -0.15), (0.085 if not felid else 0.1) * L, (0.045 if not felid else 0.06) * L, up=u, sx=0.85, k=0.03 * L)
    r.ell("jaw", P(0.4, -0.2), ((0.16) * L, (0.07) * L, (0.13) * L), ax, k=0.04 * L)
    # mouth line
    r.cap("head", P(0.55, -0.135), P(1.0, -0.12), 0.006 * L / 0.3, 0.006 * L / 0.3, up=u, sx=12.0, sy=1.0, k=0.004 * L, sub=True, region=R_MOUTH)
    # eyes: forward-facing (cats more so), brow above
    er = 0.042 * L * eye
    for sd in (-1, 1):
        dirv = norm(f * (0.75 if felid else 0.55) + s * sd * (0.6 if felid else 0.8) + u * 0.05)
        c = P(m0 - 0.02, 0.08, sd * (0.13 if not felid else 0.14))
        hit = r.surface_hit(P(m0 - 0.05, 0.08, sd * 0.05), dirv, L)
        if hit is not None:
            c = hit
        r.ell("head", c + dirv * er * 0.2, (er * 1.15, er * 0.75, er * 1.1), (norm(np.cross(dirv, u)), u, dirv), k=er * 0.3, sub=True)
        r.add_eye(c - dirv * er * 0.55, er, dirv, "head")
        r.ell("head", c + u * er * 1.05 - dirv * er * 0.2, (er * 1.2, er * 0.35, er * 0.9), ax, k=er * 0.5)
        # ears
        if ears > 0:
            base = P(0.22, 0.17, sd * 0.13)
            if not felid:
                tip = base + u * 0.36 * L * ears + s * sd * 0.07 * L * ears - f * 0.04 * L
                r.cap("head", base, tip, 0.1 * L * ears, 0.02 * L, up=f, sx=1.0, sy=0.45, k=0.03 * L)
            else:
                c2 = base + u * 0.07 * L * ears + s * sd * 0.03 * L
                r.ell("head", c2, (0.075 * L * ears, 0.07 * L * ears, 0.025 * L), ax, k=0.02 * L)
                r.ell("head", c2 + f * 0.022 * L, (0.05 * L * ears, 0.045 * L * ears, 0.012 * L), ax, k=0.004 * L, sub=True)
    # teeth: canines (sabers for smilodon come from parts), incisors
    for sd in (-1, 1):
        cb = r.surface_hit(P(0.88, -0.1, sd * 0.02), s * sd - u * 0.3, L * 0.3)
        if cb is not None:
            ln = 0.09 * L * (1.0 + fang)
            r.add_curved_cone(cb - s * sd * 0.01 * L, -u + f * 0.12, ln, ln * 0.22, -f * 0.18, "head", R_TOOTH, segs=6, rings=4)
        jb = r.surface_hit(P(0.84, -0.17, sd * 0.02), s * sd + u * 0.3, L * 0.3)
        if jb is not None:
            ln = 0.06 * L
            r.add_curved_cone(jb - s * sd * 0.008 * L, u + f * 0.1, ln, ln * 0.24, -f * 0.15, "jaw", R_TOOTH, segs=6, rings=3)
    return f, s, u


def tyrant_skull(r, HB, f, L, hh, hw, *, n_teeth=12, tooth_len=0.12, eye=1.0, boss=0.6, lips=True):
    """Tyrannosaurid skull: deep, box-like snout, broad back of the skull (forward-facing eyes),
    rugose nasals, brow horns, massive lower jaw, lip-covered teeth with tips showing."""
    f, s, u = _basis(f)
    P = lambda a, b, c=0.0: HB + f * (a * L) + u * (b * hh) + s * (c * hw)
    ax = (s, u, f)
    # back of the skull: wide (temporal region), deep
    r.ell("head", P(0.16, 0.12), (hw * 1.0, hh * 0.46, L * 0.2), ax, k=hh * 0.1)
    r.ell("head", P(0.24, -0.08), (hw * 1.05, hh * 0.32, L * 0.2), ax, k=hh * 0.1)
    # snout: deep and narrow-ish, slightly convex top line, square front
    r.cap("head", P(0.3, 0.12), P(0.92, 0.0), hh * 0.36, hh * 0.27, up=u, sx=(hw * 0.62) / (hh * 0.36), sy=1.0, k=hh * 0.1)
    r.ell("head", P(0.94, -0.06), (hw * 0.45, hh * 0.3, L * 0.07), ax, k=hh * 0.08)
    # rugose nasal ridge (bumps)
    for i in range(7):
        t = 0.45 + i * 0.07
        r.ell("head", P(t, 0.34 - (t - 0.45) * 0.4), (hw * 0.12, hh * 0.05, L * 0.03), ax, k=hh * 0.04)
    # antorbital fenestra depression and maxillary fenestra (shallow)
    for sd in (-1, 1):
        r.ell("head", P(0.55, 0.05, sd * 0.62), (hw * 0.12, hh * 0.15, L * 0.12), ax, k=hh * 0.05, sub=True)
    # lower jaw: deep at the back (surangular), straight lower edge, mouth line with lips
    r.cap("jaw", P(0.1, -0.3), P(0.92, -0.32), hh * 0.27, hh * 0.18, up=u, sx=(hw * 0.75) / (hh * 0.27), k=hh * 0.1)
    r.ell("jaw", P(0.2, -0.4), (hw * 0.85, hh * 0.24, L * 0.16), ax, k=hh * 0.08)
    g = hh * 0.025
    r.cap("head", P(0.2, -0.17), P(1.02, -0.2), g, g, up=u, sx=(hw * 1.4) / g, sy=1.0, k=g * 0.5, sub=True, region=R_MOUTH)
    # eyes: forward-facing, under a brow horn (lacrimal / postorbital bosses)
    er = hh * 0.07 * eye
    for sd in (-1, 1):
        c0 = P(0.25, 0.22)
        dirv = norm(s * sd + f * 0.55)
        hit = r.surface_hit(c0, dirv, hw * 3)
        if hit is None:
            continue
        r.ell("head", hit + dirv * er * 0.15, (er * 1.15, er * 0.85, er * 1.25), ax, k=er * 0.3, sub=True)
        r.add_eye(hit - dirv * er * 0.55, er, dirv, "head")
        r.ell("head", hit + u * er * 1.0 + f * er * 0.6, (er * 0.9, er * 0.6, er * 1.8), ax, k=er * 0.6)
        if boss > 0:
            r.ell("head", hit + u * er * 1.6 + f * er * 2.0 - dirv * er * 0.3, (er * 0.7 * boss, er * 1.0 * boss, er * 0.9 * boss), ax, k=er * 0.5)
        # nostril near the snout tip, high
        nh = r.surface_hit(P(0.9, 0.12), s * sd + u * 0.5, hw * 2)
        if nh is not None:
            r.ell("head", nh, (hh * 0.05, hh * 0.035, hh * 0.08), ax, k=hh * 0.02, sub=True)
    # teeth: thick, banana-shaped, mostly behind lips (only the tips show below the upper lip line)
    for sd in (-1, 1):
        for i in range(n_teeth):
            t = 0.3 + 0.66 * i / max(n_teeth - 1, 1)
            hit = r.surface_hit(P(t, -0.17 + 0.03 * t), s * sd, hw * 2)
            if hit is None:
                continue
            tl = tooth_len * (1.25 - 0.5 * abs(t - 0.55) * 1.6) * (0.85 + 0.3 * ((i * 7) % 3) / 2)
            base = hit - s * sd * tl * (0.32 if lips else 0.22) + u * tl * (0.45 if lips else 0.15)
            r.add_curved_cone(base, -u + f * 0.1, tl, tl * 0.28, -f * 0.22 + s * sd * 0.04, "head", R_TOOTH, segs=6, rings=3)
        for i in range(n_teeth - 2):
            t = 0.36 + 0.56 * i / max(n_teeth - 3, 1)
            hit = r.surface_hit(P(t, -0.24), s * sd, hw * 2)
            if hit is None:
                continue
            tl = tooth_len * 0.8 * (1.1 - 0.5 * t)
            base = hit - s * sd * tl * (0.32 if lips else 0.22) - u * tl * (0.4 if lips else 0.15)
            r.add_curved_cone(base, u + f * 0.08, tl, tl * 0.26, -f * 0.18, "jaw", R_TOOTH, segs=6, rings=3)
    return f, s, u
