"""Body family builders. Each returns a Rig with a shared bone layout per family,
so animation code and part sockets work across all species of a family."""
import math

import numpy as np

from sdfrig import Rig, v3, norm, R_EYE, R_TOOTH, R_KERATIN, R_MEMBRANE, R_FEATHER, R_TOP, R_BOTTOM, R_BOOTS, R_HAIR, R_MOUTH


def _dirv(pitch_deg, yaw=0.0):
    """Forward (-Z) direction rotated up by pitch degrees."""
    p = math.radians(pitch_deg)
    return v3(0, math.sin(p), -math.cos(p))


def _head_details(r, head, jaw, teeth, eye_scale=1.0, n_teeth=7, eye_t=0.28, eye_up=0.35, beak=False):
    hb = r.b(head)
    A, B = hb.head, hb.tail
    L = np.linalg.norm(B - A)
    d = norm(B - A)
    side = norm(np.cross(d, v3(0, 1, 0)))
    up = norm(np.cross(side, d))
    rr = lambda t: hb.r0 + (hb.r1 - hb.r0) * t
    for s in (-1, 1):
        t = eye_t
        rad = rr(t)
        c = A + d * L * t + side * s * rad * hb.sx * 0.78 + up * rad * hb.sy * eye_up
        r.add_sphere(c, rad * 0.2 * eye_scale, head, R_EYE)
    if teeth and jaw:
        jb = r.b(jaw)
        for s in (-1, 1):
            for i in range(n_teeth):
                t = 0.3 + 0.65 * i / max(n_teeth - 1, 1)
                rad = rr(t)
                base = A + d * L * t + side * s * rad * hb.sx * 0.72 - up * rad * hb.sy * 0.55
                ln = rad * 0.38 * (1.2 - 0.5 * t)
                r.add_cone(base, base - up * ln + d * ln * 0.15, ln * 0.28, head, R_TOOTH, segs=5)
            JA, JB = jb.head, jb.tail
            JL = np.linalg.norm(JB - JA)
            jd = norm(JB - JA)
            for i in range(n_teeth - 1):
                t = 0.35 + 0.6 * i / max(n_teeth - 2, 1)
                rad = jb.r0 + (jb.r1 - jb.r0) * t
                base = JA + jd * JL * t + side * s * rad * jb.sx * 0.7 + up * rad * jb.sy * 0.6
                ln = rad * 0.5
                r.add_cone(base, base + up * ln + jd * ln * 0.1, ln * 0.3, jaw, R_TOOTH, segs=5)


def _claws(r, bone, n, length, spread, down=-0.6, curve_down=0.5, sideways=0.0):
    b = r.b(bone)
    d = norm(b.tail - b.head)
    side = norm(np.cross(d, v3(0, 1, 0))) if abs(d[1]) < 0.95 else v3(1, 0, 0)
    for i in range(n):
        o = (i - (n - 1) / 2) * spread
        base = b.tail + side * o
        dd = norm(d + side * o * 2.0 / max(length, 1e-3) * 0.15 + v3(0, down * 0.3, 0))
        r.add_curved_cone(base, dd, length, length * 0.22, v3(0, -curve_down, 0) + side * sideways, bone, R_KERATIN)


# =====================================================================================
# shared anatomy helpers
# =====================================================================================
def _basis(f):
    f = norm(np.asarray(f, float))
    s = norm(np.cross(f, v3(0, 1, 0))) if abs(f[1]) < 0.97 else v3(1, 0, 0)
    u = norm(np.cross(s, f))
    return f, s, u


def _rot_y(v, deg):
    a = math.radians(deg)
    c, sn = math.cos(a), math.sin(a)
    return v3(v[0] * c + v[2] * sn, v[1], -v[0] * sn + v[2] * c)


def build_skull(r, HB, f, L, hh, hw, sh, sw, *, teeth=True, n_teeth=10, tooth_len=0.1, eye=1.0, brow=0.0,
                beak=False, duck=False, gap=0.022, eye_t=0.2, eye_up=0.2, horn_boss=0.0, lower_teeth=True,
                jaw_depth=1.0, snout_drop=0.08, min_gap=0.0):
    """Archosaur skull: cranium, snout, cheeks, lower jaw with mouth gap, teeth, eye sockets, nostrils.
    HB: skull base (occiput), f: forward dir, L: length, hh/hw: height/half-width at back, sh/sw: snout tip height/half-width."""
    f, s, u = _basis(f)
    P = lambda a, b, c=0.0: HB + f * (a * L) + u * (b * hh) + s * (c * hw)
    ax = (s, u, f)
    # upper skull
    r.ell("head", P(0.2, 0.1), (hw * 0.95, hh * 0.46, L * 0.26), ax, k=hh * 0.12)
    r.ell("head", P(0.27, -0.06), (hw * 1.0, hh * 0.27, L * 0.2), ax, k=hh * 0.1)
    sx = max(sw / max(sh * 0.5, 1e-3), 0.3)
    if duck:
        r.cap("head", P(0.3, 0.08), P(0.86, -snout_drop), hh * 0.36, sh * 0.42, up=u, sx=max(sx, 1.0), k=hh * 0.15)
        r.ell("head", P(0.93, -snout_drop - 0.05), (sw * 1.25, sh * 0.32, L * 0.12), ax, k=hh * 0.08)
    else:
        r.cap("head", P(0.3, 0.1), P(0.97, -snout_drop), hh * 0.4, sh * 0.5, up=u, sx=sx, k=hh * 0.18)
    # lower jaw
    jd = jaw_depth
    r.cap("jaw", P(0.05, -0.3 * jd), P(0.95, -snout_drop - 0.3), hh * 0.27 * jd, sh * 0.3, up=u, sx=max(sw / max(sh * 0.3, 1e-3), 0.3) * 0.85, k=hh * 0.12)
    r.ell("jaw", P(0.16, -0.33 * jd), (hw * 0.78, hh * 0.22 * jd, L * 0.17), ax, k=hh * 0.08)
    # mouth gap (also separates jaw for animation)
    g = max(hh * gap, min_gap)
    if teeth:
        m0 = P(0.2, -0.2)
        m1 = P(1.05, -snout_drop - 0.2)
        r.cap("head", m0, m1, g, g, up=u, sx=(hw * 1.4) / g, sy=1.0, k=g * 0.5, sub=True, region=R_MOUTH)
    if beak:
        r.ell("head", P(0.97, -snout_drop - 0.12), (sw * 0.9, sh * 0.55, L * 0.1), ax, k=hh * 0.05, region=R_KERATIN)
        r.ell("jaw", P(0.95, -snout_drop - 0.34), (sw * 0.8, sh * 0.35, L * 0.09), ax, k=hh * 0.05, region=R_KERATIN)
    # eyes
    er = hh * 0.075 * eye
    for side in (-1, 1):
        c0 = P(eye_t, eye_up)
        hit = r.surface_hit(c0, s * side, hw * 3)
        if hit is None:
            continue
        r.ell("head", hit + s * side * er * 0.1, (er * 1.15, er * 0.95, er * 1.3), ax, k=er * 0.3, sub=True)
        r.add_eye(hit - s * side * er * 0.55, er, s * side + f * 0.35, "head")
        if brow > 0:
            r.ell("head", hit + u * er * 0.95 - s * side * er * 0.15 + f * er * 0.2, (er * 0.7 * brow, er * 0.5 * brow, er * 1.5 * brow), ax, k=er * 0.6)
        if horn_boss > 0:
            r.ell("head", hit + u * er * 1.3 - f * er * 1.6, (er * 0.6, er * 0.9 * horn_boss, er * 0.8), ax, k=er * 0.5)
        # nostril
        nh = r.surface_hit(P(0.88, -snout_drop * 0.5 + 0.05), s * side + u * 0.6, hw * 2)
        if nh is not None:
            r.ell("head", nh, (sh * 0.12, sh * 0.08, sh * 0.2), ax, k=sh * 0.05, sub=True)
    if teeth:
        for side in (-1, 1):
            for i in range(n_teeth):
                t = 0.32 + 0.6 * i / max(n_teeth - 1, 1)
                c = HB + f * (t * L) + u * (hh * (-0.2 + (-snout_drop) * (t - 0.2) / 0.85) + g * 1.4)
                hit = r.surface_hit(c, s * side, hw * 2)
                if hit is None:
                    continue
                tl = tooth_len * (1.15 - 0.55 * t) * (0.85 + 0.3 * ((i * 7) % 3) / 2)
                base = hit - s * side * tl * 0.22 + u * tl * 0.15
                r.add_curved_cone(base, -u + f * 0.12, tl, tl * 0.24, -f * 0.25 + s * side * 0.05, "head", R_TOOTH, segs=6, rings=3)
            if not lower_teeth:
                continue
            for i in range(n_teeth - 2):
                t = 0.38 + 0.52 * i / max(n_teeth - 3, 1)
                c = HB + f * (t * L) + u * (hh * (-0.2 + (-snout_drop) * (t - 0.2) / 0.85) - g * 1.4)
                hit = r.surface_hit(c, s * side, hw * 2)
                if hit is None:
                    continue
                tl = tooth_len * 0.75 * (1.1 - 0.5 * t)
                base = hit - s * side * tl * 0.22 - u * tl * 0.15
                r.add_curved_cone(base, u + f * 0.1, tl, tl * 0.24, -f * 0.2, "jaw", R_TOOTH, segs=6, rings=3)
    return f, s, u


def surface_socket(r, name, bone, inside, direction, max_d, scale, normal=None):
    hit = r.surface_hit(inside, direction, max_d)
    if hit is None:
        hit = np.asarray(inside, float) + norm(np.asarray(direction, float)) * max_d * 0.5
    r.socket(name, bone, hit, normal if normal is not None else direction, scale)


def _toe(r, bone, base, dirv, length, rad, claw, n_seg=2, droop=0.25):
    pts = [np.asarray(base, float)]
    d = norm(dirv)
    for i in range(n_seg):
        pts.append(pts[-1] + d * (length / n_seg) + v3(0, -length * droop * (i + 1) / n_seg / n_seg, 0))
    for i in range(n_seg):
        r0 = rad * (1 - 0.25 * i / n_seg)
        r1 = rad * (1 - 0.25 * (i + 1) / n_seg) * 0.85
        r.cap(bone, pts[i], pts[i + 1], r0, r1, sx=1.15, sy=0.8, k=rad * 0.35)
        r.ell(bone, pts[i + 1], (r1 * 1.15, r1 * 0.95, r1 * 1.1), k=rad * 0.2)
    if claw > 0:
        tip_d = norm(pts[-1] - pts[-2])
        r.add_curved_cone(pts[-1] - tip_d * rad * 0.3 + v3(0, rad * 0.15, 0), tip_d + v3(0, -0.25, 0), claw, rad * 0.75, v3(0, -0.6, 0), bone, R_KERATIN, segs=7, rings=4)
    return pts[-1]


# =====================================================================================
# THEROPOD: bipedal predators and ornithopods
# =====================================================================================
def theropod(rid, H=1.0, body_len=1.0, body_d=0.35, body_w=0.25, neck_len=0.6, neck_r=0.12, neck_rise=45,
             head_len=0.35, head_h=0.16, head_w=0.12, snout_h=0.07, snout_w=0.05, head_pitch=-8,
             tail_len=1.6, tail_r=0.2, leg_r=0.12, arm_len=0.45, arm_r=0.05, fingers=3, teeth=True,
             n_teeth=10, tooth_len=None, sickle=False, feathers=0.0, beak=False, duck=False, eye=1.0, brow=0.0,
             horn_boss=0.0, scutes=0.0, toe_len=0.24, quadish=False, family="theropod", detail=1.0, snout_drop=0.08,
             dome=0.0):
    r = Rig(rid, family)
    D, W, Lb = body_d, body_w, body_len
    tooth_len = tooth_len if tooth_len is not None else head_h * 0.16
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    P = v3(0, H + 0.2 * D, 0.2 * Lb)
    S1 = v3(0, H + 0.25 * D, -0.45 * Lb)
    C = v3(0, H + 0.12 * D, -0.98 * Lb)
    r.add("pelvis", "root", P, S1, D * 0.5, D * 0.55, sx=W / D, blend=D * 0.4)
    r.add("spine", "pelvis", S1, C, D * 0.55, D * 0.48, sx=W / D, blend=D * 0.4)
    # trunk masses
    r.ell("pelvis", v3(0, H + 0.18 * D, 0.02 * Lb), (W * 0.82, D * 0.78, Lb * 0.48), k=D * 0.35)
    r.ell("pelvis", v3(0, H - 0.25 * D, -0.3 * Lb), (W * 0.92, D * 0.82, Lb * 0.42), k=D * 0.4)
    r.ell("spine", v3(0, H - 0.12 * D, -0.62 * Lb), (W, D, Lb * 0.48), k=D * 0.35)
    r.ell("spine", v3(0, H - 0.05 * D, -0.95 * Lb), (W * 0.8, D * 0.82, Lb * 0.3), k=D * 0.35)
    # neck (S-curve)
    Nb = C + v3(0, 0.05 * D, -0.12 * Lb)
    N1 = Nb + _dirv(neck_rise) * neck_len * 0.55
    N2 = N1 + _dirv(neck_rise * 0.3) * neck_len * 0.45
    r.add("neck1", "spine", Nb, N1, D * 0.55, neck_r * 1.05, sx=0.78, blend=neck_r * 0.9)
    r.add("neck2", "neck1", N1, N2, neck_r * 1.05, neck_r * 0.95, sx=0.82, blend=neck_r * 0.6)
    r.ell_along("neck1", Nb + v3(0, -D * 0.45, 0.05 * Lb), N1 + v3(0, -neck_r * 0.45, 0), W * 0.62, neck_r * 1.05, up=(0, 0, -1), k=neck_r * 0.7, extra_len=1.05)
    # skull
    hd = _dirv(head_pitch)
    HB = N2 + hd * neck_r * 0.25 + v3(0, neck_r * 0.15, 0)
    r.add("head", "neck2", HB, HB + hd * head_len, 0, 0, geo=False, blend=head_h * 0.2)
    JB = HB + v3(0, -head_h * 0.3, 0) + hd * head_len * 0.05
    r.add("jaw", "head", JB, JB + _dirv(head_pitch - 4) * head_len * 0.9, 0, 0, geo=False, blend=head_h * 0.15)
    r.ell("head", HB - hd * head_h * 0.2 + v3(0, -head_h * 0.05, 0), (head_w * 0.75, head_h * 0.42, head_h * 0.45), k=head_h * 0.3)
    f, s_, u = build_skull(r, HB, hd, head_len, head_h, head_w, snout_h, snout_w, teeth=teeth, n_teeth=n_teeth,
                           tooth_len=tooth_len, eye=eye, brow=brow, beak=beak, duck=duck, horn_boss=horn_boss,
                           snout_drop=snout_drop, min_gap=(Lb + neck_len + head_len + tail_len) / 300 * 1.3)
    if dome > 0:
        dc = HB + f * head_len * 0.22 + u * head_h * 0.42
        r.ell("head", dc, (head_w * 1.0 * dome, head_h * 0.55 * dome, head_len * 0.3 * dome), (s_, u, f), k=head_h * 0.12)
        for i in range(10):
            a = 2 * math.pi * i / 10
            kn = dc - u * head_h * 0.18 * dome + s_ * math.cos(a) * head_w * 0.95 * dome + f * math.sin(a) * head_len * 0.28 * dome
            r.ell("head", kn, (head_h * 0.06, head_h * 0.06, head_h * 0.06), k=head_h * 0.04)
    # tail (laterally compressed, nearly horizontal)
    prev, tp = "pelvis", P + v3(0, 0, 0.05 * Lb)
    n_t = 6
    drops = [0.03, 0.0, -0.025, -0.035, -0.04, -0.04]
    for i in range(n_t):
        t0, t1 = i / n_t, (i + 1) / n_t
        q = tp + v3(0, tail_len * drops[i] * 0.6, tail_len / n_t)
        r0 = tail_r * (1 - t0) ** 1.25 + tail_r * 0.04
        r1 = tail_r * (1 - t1) ** 1.25 + tail_r * 0.03
        nm = f"tail{i + 1}"
        r.add(nm, prev, tp, q, r0, r1, sx=0.62, blend=r0 * 0.5)
        prev, tp = nm, q
    r.chain("tail", [f"tail{i + 1}" for i in range(n_t)])
    r.ell("tail1", v3(0, H + 0.02 * D, P[2] + tail_len * 0.1), (W * 0.55, tail_r * 0.85, tail_len * 0.15), k=tail_r * 0.35)
    # legs
    for sd, sn in ((-1, "L"), (1, "R")):
        J = v3(sd * W * 0.7, H, 0.0)
        K = v3(sd * W * 0.8, H * 0.53, -0.17 * H)
        A = v3(sd * W * 0.74, H * 0.17, 0.1 * H)
        T = v3(sd * W * 0.72, H * 0.05, -0.03 * H)
        tip = T + v3(0, -H * 0.03, -toe_len * H)
        r.add(f"thigh_{sn}", "pelvis", J, K, leg_r * 0.85, leg_r * 0.6, blend=leg_r * 0.5)
        r.add(f"shin_{sn}", f"thigh_{sn}", K, A, leg_r * 0.5, leg_r * 0.32, blend=leg_r * 0.4)
        r.add(f"meta_{sn}", f"shin_{sn}", A, T, leg_r * 0.3, leg_r * 0.26, sx=1.15, blend=leg_r * 0.2)
        r.add(f"toe_{sn}", f"meta_{sn}", T, tip, 0, 0, geo=False)
        r.ell_along(f"thigh_{sn}", J + v3(sd * leg_r * 0.1, leg_r * 0.8, 0.2 * leg_r), K + v3(0, 0, 0.1 * leg_r), leg_r * 0.95, leg_r * 1.4, up=(0, 0, -1), k=leg_r * 0.6, extra_len=1.2)
        r.ell_along(f"shin_{sn}", K + (A - K) * 0.05, K + (A - K) * 0.7, leg_r * 0.62, leg_r * 0.82, up=(0, 0, 1), k=leg_r * 0.4)
        r.ell(f"shin_{sn}", K, (leg_r * 0.5, leg_r * 0.45, leg_r * 0.5), k=leg_r * 0.3)
        r.ell(f"meta_{sn}", A, (leg_r * 0.36, leg_r * 0.34, leg_r * 0.38), k=leg_r * 0.15)
        tr = leg_r * 0.24
        fwd = v3(0, 0, -1)
        claw = leg_r * (0.75 if not quadish else 0.4)
        for ang, ln in ((-24, 0.8), (0, 1.0), (24, 0.82)):
            if sickle and ang * sd < 0:
                continue
            _toe(r, f"toe_{sn}", T + v3(sd * ang * 0.004 * H, 0, -tr * 0.5), _rot_y(fwd, -ang * sd), toe_len * H * ln, tr * (1.0 if ang == 0 else 0.88), claw * (1.0 if ang == 0 else 0.85))
        if sickle:
            base = T + v3(-sd * tr * 1.1, tr * 1.2, -tr * 0.4)
            mid = base + v3(-sd * tr * 0.3, tr * 0.8, -toe_len * H * 0.35)
            r.cap(f"toe_{sn}", base, mid, tr * 0.95, tr * 0.8, k=tr * 0.4)
            r.add_curved_cone(mid + v3(0, tr * 0.3, 0), v3(0, 0.9, -0.5), leg_r * 1.7, tr * 0.85, v3(0, -1.1, -0.45), f"toe_{sn}", R_KERATIN, segs=8, rings=6)
        # dewclaw
        hb = A + (T - A) * 0.65 + v3(-sd * tr * 0.6, 0, tr * 0.9)
        _toe(r, f"meta_{sn}", hb, v3(-sd * 0.3, -0.6, 0.7), toe_len * H * 0.3, tr * 0.6, claw * 0.45, n_seg=1, droop=0.0)
        r.chain(f"leg_{sn}", [f"thigh_{sn}", f"shin_{sn}", f"meta_{sn}", f"toe_{sn}"])
        # arms
        Sh = C + v3(sd * W * 0.62, -D * 0.38, 0.02 * Lb)
        El = Sh + v3(sd * arm_len * 0.12, -arm_len * 0.42, arm_len * 0.12)
        Wr = El + v3(-sd * arm_len * 0.02, -arm_len * 0.08, -arm_len * 0.42)
        Hn = Wr + v3(0, -arm_len * 0.05, -arm_len * 0.16)
        r.add(f"uarm_{sn}", "spine", Sh, El, arm_r * 1.25, arm_r * 0.9, blend=arm_r * 0.6)
        r.add(f"farm_{sn}", f"uarm_{sn}", El, Wr, arm_r * 0.85, arm_r * 0.62, blend=arm_r * 0.4)
        r.add(f"hand_{sn}", f"farm_{sn}", Wr, Hn, arm_r * 0.6, arm_r * 0.45, sx=0.7, blend=arm_r * 0.3)
        r.ell(f"uarm_{sn}", Sh + v3(0, arm_r * 0.3, 0), (arm_r * 1.4, arm_r * 1.5, arm_r * 1.6), k=arm_r * 0.8)
        hd_ = norm(Hn - Wr)
        for fi in range(fingers):
            o = (fi - (fingers - 1) / 2) * arm_r * 0.55
            fd = norm(hd_ + v3(sd * o * 0.8 / max(arm_len, 1e-3), -0.35, 0))
            _toe(r, f"hand_{sn}", Hn + v3(sd * o, 0, 0), fd, arm_len * (0.22 if fingers > 2 else 0.16), arm_r * 0.3, arm_r * (1.6 if sickle or fingers > 2 else 1.0), n_seg=2, droop=0.6)
        if feathers > 0:
            dn = norm(v3(0, -0.75, 0.65))
            for a, b, bn, dep in ((El, Wr, f"farm_{sn}", 0.22), (Wr, Hn + (Hn - Wr) * 0.3, f"hand_{sn}", 0.2)):
                off = dn * arm_len * dep * feathers * 0.55
                r.ell_along(bn, a + off, b + off, arm_r * 0.22, arm_len * dep * feathers * 0.75, up=dn, k=arm_r * 0.4, extra_len=1.1, region=R_FEATHER)
        r.chain(f"arm_{sn}", [f"uarm_{sn}", f"farm_{sn}", f"hand_{sn}"])
    if feathers > 0:
        for nm in ("tail4", "tail5", "tail6"):
            tb = r.b(nm)
            r.ell_along(nm, tb.head, tb.tail, tail_r * 1.3 * feathers, tail_r * 0.1, up=(0, 1, 0), k=tail_r * 0.15, extra_len=1.2, region=R_FEATHER)
    if scutes > 0:
        sc = D * 0.09 * scutes
        pts = []
        for i in range(14):
            t = i / 13
            pts.append((Nb + (C - Nb) * 0.0) * (1 - t) + (r.b("tail3").tail) * t)
        for i, ppt in enumerate(pts):
            bone = "neck1" if i < 2 else ("spine" if i < 6 else ("pelvis" if i < 9 else "tail2"))
            hit = r.surface_hit(ppt + v3(0, -D * 0.3, 0), v3(0, 1, 0), D * 2.5)
            if hit is not None:
                r.ell(bone, hit, (sc * 0.8, sc * 0.55, sc * 1.1), k=sc * 0.4)
    r.chain("spine", ["pelvis", "spine"])
    r.chain("neck", ["neck1", "neck2", "head"])
    if feathers > 0:
        feather_bones = {"pelvis", "spine", "neck1", "neck2", "tail1", "tail2", "tail3", "tail4", "tail5", "tail6", "uarm_L", "uarm_R", "farm_L", "farm_R", "thigh_L", "thigh_R"}

        def region_fn(p, n, bn, cur):
            if cur == 0 and bn in feather_bones:
                return R_FEATHER
            return None
        r.region_fn = region_fn
    r.ell("root", v3(0, -500.0, 0), (500.0, 500.0, 500.0), k=H * 0.01, sub=True)
    r.detail_amp = H * 0.0022 * detail
    r.detail_freq = 1.0 / max(H * 0.03, 0.003)
    # sockets on the actual surface
    sk = head_h * 1.3
    surface_socket(r, "head_top", "head", HB + f * head_len * 0.25, u, head_h * 2, sk)
    surface_socket(r, "nose", "head", HB + f * head_len * 0.8 + u * (-snout_drop * head_h), u, head_h * 2, sk * 0.75, normal=u - f * 0.3)
    for sd, nm in ((-1, "brow_L"), (1, "brow_R")):
        surface_socket(r, nm, "head", HB + f * head_len * 0.22 + u * head_h * 0.15, u + s_ * sd * 0.6, head_h * 2, sk * 0.75, normal=u * 1.0 + s_ * sd * 0.4 - f * 0.2)
    surface_socket(r, "neck_back", "neck1", (Nb + N1) * 0.5, v3(0, 1, 0.25), neck_r * 4, neck_r * 2)
    surface_socket(r, "back", "pelvis", v3(0, H, -0.1 * Lb), v3(0, 1, 0), D * 3, D * 2)
    surface_socket(r, "back_front", "spine", v3(0, H, -0.6 * Lb), v3(0, 1, 0), D * 3, D * 2)
    surface_socket(r, "saddle", "pelvis", v3(0, H, -0.35 * Lb), v3(0, 1, 0), D * 3, D * 2)
    for sd, nm in ((-1, "shoulder_L"), (1, "shoulder_R")):
        surface_socket(r, nm, "spine", v3(0, H, -0.9 * Lb), v3(sd, 0.6, 0), D * 3, D * 2)
    tl = r.b("tail6")
    r.socket("tail_tip", "tail6", tl.tail, (0, 0, 1), tail_r * 1.2)
    surface_socket(r, "tail_mid", "tail3", r.b("tail3").head, v3(0, 1, 0), tail_r * 3, tail_r * 1.5)
    r.socket("mouth", "jaw", r.b("jaw").tail, (0, 0, -1), head_h)
    r.socket("maw", "head", HB + f * head_len * 0.55 - u * head_h * 0.2, (0, -1, -0.2), head_h * 1.2)
    r.meta.update(gait="biped", hip_height=H, length=float(Lb + neck_len + head_len + tail_len))
    return r


# =====================================================================================
# QUADRUPED: heavy dinos, mammals, crocodilians
# =====================================================================================
def build_mammal_head(r, HB, f, L, hh, hw, *, muzzle=0.5, muzzle_r=0.3, ears=1.0, ear_shape="pointed", teeth=True,
                      fang=0.0, eye=1.0, trunk=0.0, dome=0.0):
    f, s, u = _basis(f)
    P = lambda a, b, c=0.0: HB + f * (a * L) + u * (b * hh) + s * (c * hw)
    ax = (s, u, f)
    m0 = 1.0 - muzzle
    # cranium (rounded, high forehead) + cheekbones
    r.ell("head", P(m0 * 0.55, 0.12 + dome * 0.2), (hw * 0.95, hh * (0.48 + dome * 0.3), L * m0 * 0.55), ax, k=hh * 0.15)
    r.ell("head", P(m0 * 0.75, -0.06), (hw * 1.05, hh * 0.3, L * 0.16), ax, k=hh * 0.12)
    # tapering muzzle with a stop below the eyes
    r.cap("head", P(m0 - 0.02, -0.02), P(0.97, -0.1), hh * muzzle_r * 1.05, hh * muzzle_r * 0.62, up=u, sx=0.78, k=hh * 0.12)
    r.ell("head", P(0.99, -0.06), (hw * 0.26, hh * 0.15, L * 0.05), ax, k=hh * 0.04, region=R_KERATIN)
    # lower jaw tucked under the muzzle
    r.cap("jaw", P(m0 * 0.6, -0.28), P(0.92, -0.3), hh * 0.18, hh * muzzle_r * 0.4, up=u, sx=0.85, k=hh * 0.1)
    er = hh * 0.085 * eye
    for side in (-1, 1):
        dirv = norm(s * side * 0.8 + f * 0.6)
        hit = r.surface_hit(P(m0 * 0.85, 0.16), dirv, hw * 3)
        if hit is not None:
            r.ell("head", hit + dirv * er * 0.1, (er * 1.1, er * 0.9, er * 1.25), ax, k=er * 0.3, sub=True)
            r.add_eye(hit - dirv * er * 0.5, er, dirv, "head")
            r.ell("head", hit + u * er * 1.0 - dirv * er * 0.2, (er * 0.8, er * 0.45, er * 1.4), ax, k=er * 0.6)
        if ears > 0:
            base = P(m0 * 0.3, 0.46 + dome * 0.15, side * 0.6)
            if ear_shape == "pointed":
                tip = base + u * hh * 0.5 * ears + s * side * hw * 0.3 * ears + f * L * 0.02
                r.cap("head", base, tip, hh * 0.16 * ears, hh * 0.02, up=f, sx=1.0, sy=0.32, k=hh * 0.06)
            elif ear_shape == "round":
                r.ell("head", base + u * hh * 0.1 * ears, (hh * 0.15 * ears, hh * 0.13 * ears, hh * 0.05), ax, k=hh * 0.05)
            else:  # big flap (mammoth)
                c = P(0.15, 0.0, side * 0.95) + s * side * hh * 0.1
                r.ell("head", c, (hh * 0.06, hh * 0.42 * ears, L * 0.26 * ears), (s, u, f), k=hh * 0.08)
        if teeth and fang > 0:
            fb = r.surface_hit(P(0.88, -0.22), s * side, hw * 2)
            if fb is not None:
                r.add_curved_cone(fb - s * side * hh * 0.03 + u * hh * 0.03, -u + f * 0.15, hh * 0.22 * fang, hh * 0.05 * fang, -f * 0.2, "head", R_TOOTH, segs=6, rings=4)
    if trunk > 0:
        prev = P(0.98, -0.1)
        d = norm(f * 0.4 - u)
        rad = hh * 0.2
        for i in range(7):
            t = i / 6
            d = norm(d + f * (0.12 if t > 0.6 else -0.05))
            nxt = prev + d * L * 0.28 * trunk
            r.cap("head", prev, nxt, rad * (1 - 0.45 * t), rad * (1 - 0.45 * (t + 1 / 6)), k=rad * 0.3)
            prev = nxt
    return f, s, u


def _foot(r, bone, base, fwd, kind, rad, sd):
    """Feet: elephant (pad + nails), paw (4 toes + claws), croc (splayed toes), hoof."""
    fwd = norm(fwd)
    if kind == "elephant":
        r.cap(bone, base + v3(0, rad * 0.9, 0), base - v3(0, rad * 0.3, 0), rad * 0.62, rad * 0.72, up=(0, 0, -1), k=rad * 0.3)
        for i in range(4):
            a = (i - 1.5) * 24
            d = _rot_y(fwd, -a * sd)
            c = base + d * rad * 0.66 + v3(0, rad * 0.02, 0)
            r.ell(bone, c, (rad * 0.17, rad * 0.16, rad * 0.14), k=rad * 0.05, region=R_KERATIN)
    elif kind == "paw":
        r.ell(bone, base + v3(0, rad * 0.1, 0), (rad * 0.85, rad * 0.55, rad * 0.95), k=rad * 0.3)
        for i in range(4):
            a = (i - 1.5) * 16
            d = _rot_y(fwd, -a * sd)
            _toe(r, bone, base + d * rad * 0.55 + v3(0, -rad * 0.05, 0), d, rad * 0.7, rad * 0.28, rad * 0.45, n_seg=1, droop=0.3)
    elif kind == "croc":
        r.ell(bone, base, (rad * 0.9, rad * 0.45, rad * 0.9), k=rad * 0.3)
        for i in range(4):
            a = (i - 1.5) * 26 - 10
            d = _rot_y(fwd, -a * sd)
            _toe(r, bone, base + d * rad * 0.5, d, rad * 1.3, rad * 0.22, rad * 0.4, n_seg=2, droop=0.15)
    else:  # hoof
        r.ell(bone, base + v3(0, rad * 0.2, 0), (rad * 0.75, rad * 0.75, rad * 0.8), k=rad * 0.3, region=R_KERATIN)


# =====================================================================================
# QUADRUPED: heavy dinos, mammals, crocodilians
# =====================================================================================
def quadruped(rid, Hh=1.0, Hs=0.9, body_len=1.4, body_d=0.4, body_w=0.35, neck_len=0.5, neck_r=0.18, neck_angle=10,
              head_len=0.5, head_h=0.3, head_w=0.18, snout_h=0.15, snout_w=0.1, head_pitch=-15, tail_len=1.5,
              tail_r=0.22, leg_r=0.12, fleg_r=None, style="reptile", teeth=False, n_teeth=8, tooth_len=None,
              beak=False, feet="elephant", ffeet=None, sprawl=0.0, n_tail=5, eye=1.0, brow=0.0, horn_boss=0.0,
              frill=0.0, scutes=0.0, osteo=0.0, ears=0.0, ear_shape="pointed", trunk=0.0, hump=0.0, fang=0.0,
              muzzle=0.5, muzzle_r=0.3, dome=0.0, snout_drop=0.08, family="quadruped", detail=1.0, tail_sx=0.75,
              tail_droop=0.04, spikes=0.0):
    r = Rig(rid, family)
    fleg_r = fleg_r or leg_r
    ffeet = ffeet or feet
    D, W, Lb = body_d, body_w, body_len
    mammal = style in ("canid", "felid", "proboscid")
    tooth_len = tooth_len if tooth_len is not None else head_h * 0.12
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    Hm = (Hh + Hs) * 0.5
    P = v3(0, Hh + 0.1 * D, 0.12 * Lb)
    S1 = v3(0, Hm + 0.2 * D, -0.5 * Lb)
    C = v3(0, Hs + 0.1 * D, -0.95 * Lb)
    r.add("pelvis", "root", P, S1, D * 0.5, D * 0.55, sx=W / D, blend=D * 0.4)
    r.add("spine", "pelvis", S1, C, D * 0.55, D * 0.5, sx=W / D, blend=D * 0.4)
    r.ell("pelvis", v3(0, Hh - 0.05 * D, 0.0), (W * 0.88, D * 0.8, Lb * 0.36), k=D * 0.35)
    r.ell("spine", v3(0, Hm - 0.15 * D, -0.5 * Lb), (W, D * (0.8 if style in ("canid", "felid") else 1.0), Lb * 0.48), k=D * 0.35)
    if style in ("canid", "felid"):
        r.ell("spine", v3(0, Hs - 0.35 * D, -0.7 * Lb), (W * 0.9, D * 0.85, Lb * 0.32), k=D * 0.4)
    else:
        r.ell("pelvis", v3(0, Hm - 0.35 * D, -0.38 * Lb), (W * 0.95, D * 0.78, Lb * 0.38), k=D * 0.4)
    r.ell("spine", v3(0, Hs - 0.08 * D, -0.9 * Lb), (W * 0.88, D * 0.85, Lb * 0.28), k=D * 0.35)
    if hump > 0:
        r.ell("spine", v3(0, Hs + 0.6 * D, -0.82 * Lb), (W * 0.6, D * 0.5 * hump, Lb * 0.3), k=D * 0.4)
    # neck
    Nb = C + v3(0, 0.05 * D, -0.1 * Lb)
    N1 = Nb + _dirv(neck_angle) * neck_len * 0.5
    N2 = N1 + _dirv(neck_angle * 0.6) * neck_len * 0.5
    r.add("neck1", "spine", Nb, N1, D * 0.55, neck_r * 1.1, sx=0.85, blend=neck_r * 0.8)
    r.add("neck2", "neck1", N1, N2, neck_r * 1.1, neck_r, sx=0.88, blend=neck_r * 0.6)
    r.ell_along("neck1", Nb + v3(0, -D * 0.4, 0.05 * Lb), N1 + v3(0, -neck_r * 0.4, 0), W * 0.6, neck_r * 1.0, up=(0, 0, -1), k=neck_r * 0.6)
    hd = _dirv(head_pitch)
    HB = N2 + hd * neck_r * 0.2
    r.add("head", "neck2", HB, HB + hd * head_len, 0, 0, geo=False)
    JB = HB + v3(0, -head_h * 0.3, 0) + hd * head_len * 0.1
    r.add("jaw", "head", JB, JB + _dirv(head_pitch - 4) * head_len * 0.85, 0, 0, geo=False)
    r.ell("head", HB - hd * head_h * 0.15, (head_w * 0.7, head_h * 0.42, head_h * 0.4), k=head_h * 0.3)
    if mammal:
        f, s_, u = build_mammal_head(r, HB, hd, head_len, head_h, head_w, muzzle=muzzle, muzzle_r=muzzle_r, ears=ears,
                                     ear_shape=ear_shape, teeth=teeth, fang=fang, eye=eye, trunk=trunk, dome=dome)
    else:
        f, s_, u = build_skull(r, HB, hd, head_len, head_h, head_w, snout_h, snout_w, teeth=teeth, n_teeth=n_teeth,
                               tooth_len=tooth_len, eye=eye, brow=brow, beak=beak, horn_boss=horn_boss,
                               snout_drop=snout_drop, eye_up=0.35 if style == "croc" else 0.2,
                               eye_t=0.12 if style == "croc" else 0.2, min_gap=(Lb + neck_len + head_len + tail_len) / 300 * 1.3)
    if frill > 0:
        n = norm(f * 0.45 + u * 0.85)
        pu = norm(np.cross(n, s_))
        if pu @ u < 0 or pu @ f > 0.3:
            pu = -pu
        fc = HB + u * head_h * 0.3 - f * head_len * 0.05 + pu * head_h * 0.95 * frill
        r.ell("head", fc, (head_w * 1.9 * frill, head_h * 1.25 * frill, head_len * 0.05), (s_, pu, n), k=head_h * 0.2)
        for i in range(13):
            a = math.pi * (i / 12)
            rim = fc + (s_ * math.cos(a) * head_w * 1.85 * frill + pu * math.sin(a) * head_h * 1.2 * frill)
            rr = head_h * 0.09 * frill
            r.ell("head", rim, (rr, rr, rr * 0.7), (s_, pu, n), k=rr * 0.6, region=R_KERATIN if i % 2 == 0 else None)
    # tail
    prev, tp = "pelvis", P + v3(0, -0.02 * D, 0.06 * Lb)
    for i in range(n_tail):
        t0, t1 = i / n_tail, (i + 1) / n_tail
        q = tp + v3(0, -tail_len * tail_droop * (1.6 if i < 2 else 0.8), tail_len / n_tail)
        r0 = tail_r * (1 - t0) ** 1.15 + tail_r * 0.05
        r1 = tail_r * (1 - t1) ** 1.15 + tail_r * 0.04
        nm = f"tail{i + 1}"
        r.add(nm, prev, tp, q, r0, r1, sx=tail_sx, blend=r0 * 0.5)
        prev, tp = nm, q
    r.chain("tail", [f"tail{i + 1}" for i in range(n_tail)])
    # legs
    for sd, sn in ((-1, "L"), (1, "R")):
        spr = sprawl * Hh
        J = v3(sd * W * 0.72, Hh, 0.02 * Lb)
        if mammal and style != "proboscid":
            K = v3(sd * W * 0.72, Hh * 0.62, -0.12 * Hh)
            A = v3(sd * W * 0.68, Hh * 0.3, 0.16 * Hh)
            T = v3(sd * W * 0.66, Hh * 0.06, 0.05 * Hh)
        else:
            K = v3(sd * (W * 0.78 + spr * 0.7), Hh * 0.52, -0.07 * Hh)
            A = v3(sd * (W * 0.76 + spr), Hh * 0.17, 0.03 * Hh)
            T = v3(sd * (W * 0.76 + spr * 1.1), Hh * 0.06 if spr == 0 else leg_r * 0.4, -0.01 * Hh)
        tip = T + v3(0, -T[1] * 0.4, -leg_r * 1.2)
        r.add(f"thigh_{sn}", "pelvis", J, K, leg_r * 0.85, leg_r * 0.7, blend=leg_r * 0.5)
        r.add(f"shin_{sn}", f"thigh_{sn}", K, A, leg_r * 0.62, leg_r * 0.5, blend=leg_r * 0.4)
        r.add(f"meta_{sn}", f"shin_{sn}", A, T, leg_r * 0.55, leg_r * (0.58 if feet == "elephant" else 0.45), blend=leg_r * 0.3)
        r.add(f"toe_{sn}", f"meta_{sn}", T, tip, 0, 0, geo=False)
        r.ell_along(f"thigh_{sn}", J + v3(0, leg_r * 0.7, 0.25 * leg_r), K, leg_r * 1.0, leg_r * 1.45, up=(0, 0, -1), k=leg_r * 0.6, extra_len=1.2)
        r.ell_along(f"shin_{sn}", K, K + (A - K) * 0.7, leg_r * 0.65, leg_r * 0.8, up=(0, 0, 1), k=leg_r * 0.4)
        _foot(r, f"toe_{sn}", T + v3(0, -T[1] * 0.3, 0), v3(sd * sprawl * 0.5, 0, -1), feet, leg_r * 0.75 if feet != "elephant" else leg_r * 0.85, sd)
        r.chain(f"leg_{sn}", [f"thigh_{sn}", f"shin_{sn}", f"meta_{sn}", f"toe_{sn}"])
        fl = fleg_r
        fspr = sprawl * Hs
        Sh = C + v3(sd * W * 0.66, -D * 0.4, 0.06 * Lb)
        if mammal and style != "proboscid":
            El = v3(sd * W * 0.66, Hs * 0.58, Sh[2] + 0.1 * Hs)
            Wr = v3(sd * W * 0.62, Hs * 0.2, Sh[2] + 0.02 * Hs)
            Hn = v3(sd * W * 0.62, Hs * 0.05, Sh[2] - 0.03 * Hs)
        else:
            El = v3(sd * (W * 0.74 + fspr * 0.8), Hs * 0.5, Sh[2] + 0.08 * Hs)
            Wr = v3(sd * (W * 0.72 + fspr), Hs * 0.15, Sh[2] + 0.01 * Hs)
            Hn = v3(sd * (W * 0.72 + fspr * 1.1), Hs * 0.05 if fspr == 0 else fl * 0.4, Sh[2] - 0.03 * Hs)
        ht = Hn + v3(0, -Hn[1] * 0.4, -fl * 1.1)
        r.add(f"uarm_{sn}", "spine", Sh, El, fl * 0.85, fl * 0.7, blend=fl * 0.5)
        r.add(f"farm_{sn}", f"uarm_{sn}", El, Wr, fl * 0.62, fl * 0.5, blend=fl * 0.4)
        r.add(f"hand_{sn}", f"farm_{sn}", Wr, Hn, fl * 0.55, fl * (0.58 if ffeet == "elephant" else 0.45), blend=fl * 0.3)
        r.add(f"fing_{sn}", f"hand_{sn}", Hn, ht, 0, 0, geo=False)
        r.ell_along(f"uarm_{sn}", Sh + v3(0, D * 0.35, 0.1 * fl), El, fl * 0.95, fl * 1.3, up=(0, 0, -1), k=fl * 0.6, extra_len=1.15)
        r.ell_along(f"farm_{sn}", El, El + (Wr - El) * 0.65, fl * 0.62, fl * 0.72, up=(0, 0, 1), k=fl * 0.35)
        _foot(r, f"fing_{sn}", Hn + v3(0, -Hn[1] * 0.3, 0), v3(sd * sprawl * 0.5, 0, -1), ffeet, fl * 0.72 if ffeet != "elephant" else fl * 0.85, sd)
        r.chain(f"arm_{sn}", [f"uarm_{sn}", f"farm_{sn}", f"hand_{sn}", f"fing_{sn}"])
    r.chain("spine", ["pelvis", "spine"])
    r.chain("neck", ["neck1", "neck2", "head"])
    # armor / scutes / osteoderms
    if osteo > 0:
        for i in range(9):
            for j in range(-3, 4):
                t = i / 8
                z = 0.25 * Lb - t * 1.15 * Lb
                inside = v3(j * W * 0.22, (Hh * (1 - t) + Hs * t) - 0.2 * D, z)
                dirv = norm(v3(j * 0.35, 1.0, 0))
                hit = r.surface_hit(inside, dirv, D * 3)
                if hit is None:
                    continue
                o = D * 0.12 * osteo * (1.2 if abs(j) == 3 else 1.0)
                r.ell("spine" if t > 0.45 else "pelvis", hit - dirv * o * 0.2, (o, o * 0.55, o * 1.15), k=o * 0.3)
        for i in range(7):
            t = i / 6
            z = 0.2 * Lb - t * 1.1 * Lb
            for sd in (-1, 1):
                hit = r.surface_hit(v3(0, (Hh * (1 - t) + Hs * t) - 0.2 * D, z), v3(sd, 0.15, 0), W * 3)
                if hit is not None:
                    r.add_curved_cone(hit - v3(sd * D * 0.05, 0, 0), v3(sd, 0.1, 0.25), D * 0.32 * osteo, D * 0.09 * osteo, v3(0, 0, 0.2), "spine" if t > 0.45 else "pelvis", R_KERATIN, segs=7, rings=3)
    if scutes > 0:
        bones_line = ["spine", "spine", "pelvis", "pelvis"] + [f"tail{i + 1}" for i in range(n_tail)]
        pts = [C, (C + S1) * 0.5, S1, P] + [r.b(f"tail{i + 1}").tail for i in range(n_tail)]
        for bi, (a, b) in enumerate(zip(pts[:-1], pts[1:])):
            for k in range(3):
                q = a + (b - a) * (k / 3)
                for sd in ((-1, 1) if style == "croc" else (0,)):
                    hit = r.surface_hit(q + v3(sd * W * 0.12, -D * 0.3, 0), v3(sd * 0.25, 1, 0), D * 3)
                    if hit is None:
                        continue
                    sc_ = D * 0.08 * scutes * (1.0 - 0.5 * bi / len(pts))
                    r.ell(bones_line[min(bi, len(bones_line) - 1)], hit, (sc_ * 0.8, sc_ * 0.7, sc_ * 1.2), k=sc_ * 0.3)
    r.ell("root", v3(0, -500.0, 0), (500.0, 500.0, 500.0), k=Hh * 0.01, sub=True)
    r.detail_amp = (Hh * 0.0022 if not mammal else Hh * 0.001) * detail
    r.detail_freq = 1.0 / max(Hh * 0.03, 0.003)
    # sockets
    sk = head_h * 1.3
    surface_socket(r, "head_top", "head", HB + f * head_len * 0.2, u, head_h * 2, sk)
    surface_socket(r, "nose", "head", HB + f * head_len * 0.8, u, head_h * 2, sk * 0.75, normal=u - f * 0.4)
    for sd, nm in ((-1, "brow_L"), (1, "brow_R")):
        surface_socket(r, nm, "head", HB + f * head_len * 0.22 + u * head_h * 0.15, u + s_ * sd * 0.6, head_h * 2, sk * 0.75, normal=u + s_ * sd * 0.4 - f * 0.4)
    r.socket("frill", "head", HB + u * head_h * 0.4 + f * head_len * 0.05, (0, 0.6, 1), head_h * 2.4)
    surface_socket(r, "neck_back", "neck1", (Nb + N1) * 0.5, v3(0, 1, 0.3), neck_r * 4, neck_r * 2)
    surface_socket(r, "back", "pelvis", v3(0, Hh, -0.15 * Lb), v3(0, 1, 0), D * 3, D * 2)
    surface_socket(r, "back_front", "spine", v3(0, Hm, -0.6 * Lb), v3(0, 1, 0), D * 3, D * 2)
    surface_socket(r, "saddle", "spine", v3(0, Hm, -0.45 * Lb), v3(0, 1, 0), D * 3, D * 2)
    for sd, nm in ((-1, "shoulder_L"), (1, "shoulder_R")):
        surface_socket(r, nm, "spine", v3(0, Hs, -0.85 * Lb), v3(sd, 0.6, 0), D * 3, D * 2)
    tl = r.b(f"tail{n_tail}")
    r.socket("tail_tip", f"tail{n_tail}", tl.tail, (0, 0, 1), tail_r * 1.2)
    mid = max(1, n_tail // 2)
    surface_socket(r, "tail_mid", f"tail{mid}", r.b(f"tail{mid}").head, v3(0, 1, 0), tail_r * 3, tail_r * 1.5)
    r.socket("mouth", "jaw", r.b("jaw").tail, (0, 0, -1), head_h)
    r.socket("maw", "head", HB + f * head_len * 0.6 - u * head_h * 0.2, (0, -1, -0.2), head_h * 1.2)
    r.meta.update(gait="quad", hip_height=Hh, length=float(Lb + neck_len + head_len + tail_len))
    return r


# =====================================================================================
# FLYERS: pterosaur (membrane), avian (feathered)
# =====================================================================================
def flyer(rid, H=0.6, torso_len=0.6, torso_r=0.18, neck_len=0.5, neck_r=0.06, neck_angle=35, head_len=0.6,
          head_r=0.08, snout_r=0.015, head_pitch=-5, wing_span=6.0, tail_len=0.2, tail_r=0.05, leg_r=0.04,
          feathered=False, teeth=False, family="flyer"):
    r = Rig(rid, family)
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    P = v3(0, H, 0.1 * torso_len)
    S1 = v3(0, H * 1.08, -0.5 * torso_len)
    C = v3(0, H * 1.12, -torso_len)
    r.add("pelvis", "root", P, S1, torso_r * 0.75, torso_r * 1.0, sx=0.95, blend=torso_r * 0.5)
    r.add("spine", "pelvis", S1, C, torso_r * 1.0, torso_r * 0.9, sx=1.0, blend=torso_r * 0.5)
    nd = _dirv(neck_angle)
    N1 = C + nd * neck_len * 0.5
    N2 = C + nd * neck_len
    r.add("neck1", "spine", C, N1, torso_r * 0.6, neck_r * 1.1, blend=neck_r)
    r.add("neck2", "neck1", N1, N2, neck_r * 1.1, neck_r, blend=neck_r * 0.6)
    hd = _dirv(head_pitch)
    HB = N2 + hd * head_r * 0.2
    HT = HB + hd * head_len
    r.add("head", "neck2", HB, HT, 0, 0, geo=False)
    JB = HB + v3(0, -head_r * 0.45, 0)
    r.add("jaw", "head", JB, JB + _dirv(head_pitch - 4) * head_len * 0.92, 0, 0, geo=False)
    r.ell("spine", (S1 + C) * 0.5 + v3(0, -torso_r * 0.15, 0), (torso_r * 0.95, torso_r * 1.05, torso_len * 0.55), k=torso_r * 0.4)
    if feathered:
        r.ell("spine", C + v3(0, -torso_r * 0.55, 0.15 * torso_len), (torso_r * 0.6, torso_r * 0.75, torso_len * 0.4), k=torso_r * 0.4)
        f_, s_, u_ = build_skull(r, HB, hd, head_len, head_r * 1.9, head_r * 0.95, snout_r * 3.0, snout_r * 1.4, teeth=False,
                                 beak=True, eye=1.6, eye_t=0.3, eye_up=0.25, snout_drop=0.12)
        r.add_curved_cone(HT + u_ * snout_r * 0.8 - f_ * head_len * 0.12, f_, head_len * 0.22, snout_r * 1.6, -u_ * 1.1, "head", R_KERATIN, segs=8, rings=5)
    else:
        f_, s_, u_ = build_skull(r, HB, hd, head_len, head_r * 2.0, head_r * 0.85, snout_r * 2.2, snout_r * 1.1, teeth=teeth,
                                 beak=False, eye=1.4, eye_t=0.14, eye_up=0.25, snout_drop=0.02, min_gap=head_len * 0.015)
    prev, tp = "pelvis", P
    n_t = 3
    for i in range(n_t):
        q = tp + v3(0, -tail_len * 0.1, tail_len / n_t)
        r0 = tail_r * (1 - i / n_t) + 0.01
        r1 = tail_r * (1 - (i + 1) / n_t) + 0.008
        r.add(f"tail{i + 1}", prev, tp, q, r0, r1, blend=r0 * 0.5)
        prev, tp = f"tail{i + 1}", q
    r.chain("tail", [f"tail{i + 1}" for i in range(n_t)])
    half = wing_span * 0.5
    for s, sn in ((-1, "L"), (1, "R")):
        hip = v3(s * torso_r * 0.45, H * 0.95, 0.05 * torso_len)
        knee = hip + v3(s * 0.02, -H * 0.42, -H * 0.12)
        ank = knee + v3(0, -H * 0.4, H * 0.12)
        toe = ank + v3(0, -H * 0.1, -H * 0.15)
        r.add(f"thigh_{sn}", "pelvis", hip, knee, leg_r * 1.6, leg_r, blend=leg_r * 0.8)
        r.add(f"shin_{sn}", f"thigh_{sn}", knee, ank, leg_r, leg_r * 0.6, blend=leg_r * 0.4)
        r.add(f"meta_{sn}", f"shin_{sn}", ank, toe, leg_r * 0.6, leg_r * 0.4, blend=leg_r * 0.3, sx=1.6, sy=0.6)
        r.add(f"toe_{sn}", f"meta_{sn}", toe, toe + v3(0, 0, -H * 0.1), 0, 0, geo=False)
        _claws(r, f"meta_{sn}", 3, leg_r * 0.9, leg_r * 0.5, curve_down=0.8)
        r.chain(f"leg_{sn}", [f"thigh_{sn}", f"shin_{sn}", f"meta_{sn}", f"toe_{sn}"])
        # wing chain: humerus, radius, metacarpal, finger
        sh = C + v3(s * torso_r * 0.7, torso_r * 0.35, 0.05)
        el = sh + v3(s * half * 0.2, half * 0.02, 0.05 * half)
        wr = el + v3(s * half * 0.28, 0.0, -0.06 * half)
        mc = wr + v3(s * half * 0.14, 0.0, 0.0)
        tipp = mc + v3(s * half * 0.38, -half * 0.01, 0.18 * half)
        wr_r = torso_r * 0.28
        r.add(f"wing1_{sn}", "spine", sh, el, wr_r * 1.4, wr_r * 0.9, sy=0.6 if feathered else 0.8, blend=wr_r * 0.6)
        r.add(f"wing2_{sn}", f"wing1_{sn}", el, wr, wr_r * 0.8, wr_r * 0.55, sy=0.6 if feathered else 0.8, blend=wr_r * 0.4)
        r.add(f"wing3_{sn}", f"wing2_{sn}", wr, mc, wr_r * 0.5, wr_r * 0.4, sy=0.6, blend=wr_r * 0.3)
        r.add(f"wing4_{sn}", f"wing3_{sn}", mc, tipp, wr_r * 0.35 if not feathered else wr_r * 0.4, 0.008, sy=0.6, blend=wr_r * 0.2)
        if not feathered:
            _claws(r, f"wing3_{sn}", 3, wr_r * 0.9, wr_r * 0.4, curve_down=0.8)
        r.chain(f"wing_{sn}", [f"wing1_{sn}", f"wing2_{sn}", f"wing3_{sn}", f"wing4_{sn}"])
        # membrane / feather surface
        lead = []
        lb = []
        segs = [(sh, el, f"wing1_{sn}"), (el, wr, f"wing2_{sn}"), (wr, mc, f"wing3_{sn}"), (mc, tipp, f"wing4_{sn}")]
        per = [3, 4, 2, 5]
        for (a, b, bn), n in zip(segs, per):
            for k in range(n):
                t = k / n
                lead.append(a * (1 - t) + b * t)
                lb.append([(bn, 1.0)])
        lead.append(tipp)
        lb.append([(f"wing4_{sn}", 1.0)])
        # trailing edge: from hip/thigh (pterosaur) or body (bird) out to wing tip
        nlead = len(lead)
        trail = []
        tb = []
        body_anchor = (hip + v3(0, 0, 0.0)) if not feathered else (P + v3(s * torso_r * 0.6, torso_r * 0.3, 0.0))
        for i in range(nlead):
            u = i / (nlead - 1)
            L = lead[i]
            if feathered:
                chord = half * (0.32 * (1 - u) ** 0.6 + 0.08) * (1.0 - 0.5 * u ** 3)
                tpt = L + v3(0, -0.01 * half, chord)
            else:
                base_tr = body_anchor * (1 - u) + tipp * u
                bow = math.sin(u * math.pi) * half * 0.1
                tpt = base_tr + v3(-s * bow * 0.3, 0, -bow) * 0.0 + v3(0, 0, half * 0.05 * math.sin(u * math.pi))
                tpt = tpt + (L - tpt) * 0.15 * math.sin(u * math.pi)
            trail.append(tpt)
            if u < 0.25:
                tb.append([("pelvis" if not feathered else "spine", 1.0)])
            else:
                tb.append(lb[i])
        r.add_membrane(lead, lb, trail, tb, R_FEATHER if feathered else R_MEMBRANE, rows=5, feather=feathered)
    if feathered:
        # tail fan
        TT = r.b("tail3").tail
        lead = [TT + v3(x, 0, 0) for x in np.linspace(-tail_len * 0.9, tail_len * 0.9, 7)]
        trail = [p + v3(0, -0.02, tail_len * 1.8 - abs(p[0] - TT[0]) * 0.6) for p in lead]
        bw = [[("tail3", 1.0)]] * 7
        r.add_membrane(lead, bw, trail, bw, R_FEATHER, rows=3)
    r.chain("spine", ["pelvis", "spine"])
    r.chain("neck", ["neck1", "neck2", "head"])
    if feathered:
        fb = {"pelvis", "spine", "neck1", "neck2", "tail1", "tail2", "tail3", "thigh_L", "thigh_R"}
        r.region_fn = lambda p, n, bn, cur: R_FEATHER if (cur == 0 and bn in fb) else None
    hb = r.b("head")
    hd_ = norm(hb.tail - hb.head)
    r.socket("head_top", "head", hb.head + v3(0, head_r * 0.9, 0.02), (0, 1, 0.5), head_r * 3)
    r.socket("brow_L", "head", hb.head + v3(-head_r * 0.5, head_r * 0.7, 0), (-0.4, 1, 0.3), head_r * 2)
    r.socket("brow_R", "head", hb.head + v3(head_r * 0.5, head_r * 0.7, 0), (0.4, 1, 0.3), head_r * 2)
    r.socket("nose", "head", hb.head + hd_ * 0.6 * head_len + v3(0, snout_r * 2, 0), (0, 1, 0), head_r * 1.5)
    r.socket("back", "pelvis", (P + S1) * 0.5 + v3(0, torso_r * 0.9, 0), (0, 1, 0), torso_r * 2)
    r.socket("back_front", "spine", (S1 + C) * 0.5 + v3(0, torso_r * 0.9, 0), (0, 1, 0), torso_r * 2)
    r.socket("neck_back", "neck1", (C + N1) * 0.5 + v3(0, neck_r * 1.0, 0), (0, 1, 0.3), neck_r * 2)
    r.socket("shoulder_L", "spine", C + v3(-torso_r * 0.5, torso_r * 0.7, 0.1), (-1, 0.5, 0), torso_r * 2)
    r.socket("shoulder_R", "spine", C + v3(torso_r * 0.5, torso_r * 0.7, 0.1), (1, 0.5, 0), torso_r * 2)
    r.socket("tail_tip", "tail3", r.b("tail3").tail, (0, 0, 1), tail_r * 1.5)
    r.socket("tail_mid", "tail2", r.b("tail2").head + v3(0, tail_r, 0), (0, 1, 0), tail_r * 1.5)
    r.socket("saddle", "spine", S1 + v3(0, torso_r * 1.0, 0), (0, 1, 0), torso_r * 2)
    r.socket("mouth", "jaw", r.b("jaw").tail, (0, 0, -1), head_r)
    r.meta.update(gait="flyer", hip_height=H, length=float(torso_len + neck_len + head_len + tail_len), wing_span=wing_span)
    return r


# =====================================================================================
# WYVERN: biped hind legs + membrane wings (forelimbs) + long neck & tail
# =====================================================================================
def wyvern(rid, H=1.7, torso_len=2.0, torso_r=0.55, neck_len=1.8, neck_r=0.22, head_len=0.9, head_r=0.25,
           snout_r=0.11, tail_len=4.0, tail_r=0.3, leg_r=0.2, wing_span=12.0):
    r = theropod(rid, H=H, body_len=torso_len, body_d=torso_r, body_w=torso_r * 0.8, neck_len=neck_len,
                 neck_r=neck_r, neck_rise=45, head_len=head_len, head_h=head_r * 2.0, head_w=head_r * 1.0,
                 snout_h=snout_r * 1.8, snout_w=snout_r * 0.9, tail_len=tail_len, tail_r=tail_r, leg_r=leg_r,
                 arm_len=0.3, arm_r=0.05, fingers=0, n_teeth=11, tooth_len=head_r * 0.25, brow=1.0, scutes=0.8,
                 family="wyvern")
    # remove the theropod arms (wings replace them)
    arm_bones = {f"{n}_{sn}" for n in ("uarm", "farm", "hand") for sn in ("L", "R")}
    for sn in ("L", "R"):
        for n in ("uarm", "farm", "hand"):
            r.b(f"{n}_{sn}").geo = False
    r.prims = [p for p in r.prims if p["bone"] not in arm_bones]
    C = r.b("spine").tail
    half = wing_span * 0.5
    for s, sn in ((-1, "L"), (1, "R")):
        sh = C + v3(s * torso_r * 0.6, torso_r * 0.55, 0.15)
        el = sh + v3(s * half * 0.22, half * 0.06, 0.1 * half)
        wr = el + v3(s * half * 0.25, -half * 0.02, -0.08 * half)
        mc = wr + v3(s * half * 0.12, 0.0, 0.02 * half)
        tipp = mc + v3(s * half * 0.4, -half * 0.06, 0.25 * half)
        wr_r = torso_r * 0.3
        r.add(f"wing1_{sn}", "spine", sh, el, wr_r * 1.3, wr_r * 0.85, sy=0.8, blend=wr_r * 0.6)
        r.add(f"wing2_{sn}", f"wing1_{sn}", el, wr, wr_r * 0.8, wr_r * 0.55, sy=0.8, blend=wr_r * 0.4)
        r.add(f"wing3_{sn}", f"wing2_{sn}", wr, mc, wr_r * 0.5, wr_r * 0.4, blend=wr_r * 0.3)
        r.add(f"wing4_{sn}", f"wing3_{sn}", mc, tipp, wr_r * 0.35, 0.01, blend=wr_r * 0.2)
        _claws(r, f"wing3_{sn}", 2, wr_r * 0.9, wr_r * 0.5, curve_down=0.8)
        r.chain(f"wing_{sn}", [f"wing1_{sn}", f"wing2_{sn}", f"wing3_{sn}", f"wing4_{sn}"])
        lead, lb = [], []
        segs = [(sh, el, f"wing1_{sn}"), (el, wr, f"wing2_{sn}"), (wr, mc, f"wing3_{sn}"), (mc, tipp, f"wing4_{sn}")]
        for (a, b, bn), n in zip(segs, [3, 4, 2, 5]):
            for k in range(n):
                t = k / n
                lead.append(a * (1 - t) + b * t)
                lb.append([(bn, 1.0)])
        lead.append(tipp)
        lb.append([(f"wing4_{sn}", 1.0)])
        anchor = r.b("pelvis").head + v3(s * torso_r * 0.7, torso_r * 0.3, 0.2)
        trail, tb = [], []
        nl = len(lead)
        for i in range(nl):
            u = i / (nl - 1)
            base_tr = anchor * (1 - u) + tipp * u
            tpt = base_tr + v3(0, 0, half * 0.08 * math.sin(u * math.pi))
            tpt = tpt + (lead[i] - tpt) * 0.12 * math.sin(u * math.pi)
            trail.append(tpt)
            tb.append([("pelvis", 1.0)] if u < 0.2 else lb[i])
        r.add_membrane(lead, lb, trail, tb, R_MEMBRANE, rows=6)
    r.meta.update(gait="wyvern", wing_span=wing_span)
    return r


# =====================================================================================
# MARINE: marine reptiles with flippers
# =====================================================================================
def _fin(r, bone, base, tip, width, thick, up, k=None, region=None):
    """Flattened tapered paddle from base to tip; `up` is the fin's thin axis normal."""
    base = np.asarray(base, float)
    tip = np.asarray(tip, float)
    k = k if k is not None else thick * 0.8
    mid = base + (tip - base) * 0.4
    r.ell_along(bone, base, mid + (tip - base) * 0.15, thick, width, up=np.cross(norm(tip - base), norm(up)), k=k, region=region)
    r.cap(bone, mid, tip, width * 0.8, width * 0.12, up=np.cross(norm(tip - base), norm(up)), sx=thick / (width * 0.8), sy=1.0, k=k, region=region)


def marine(rid, length=8.0, torso_r=0.7, neck_len=0.5, neck_r=0.35, head_len=1.2, head_r=0.35, snout_r=0.12,
           tail_len=3.5, tail_r=0.4, flipper=1.2, rear_flipper=1.0, fluke=1.0, teeth=True, sx=0.9, sy=0.9,
           n_tail=6, dorsal=0.0, family="marine", style="reptile", eye=1.0):
    r = Rig(rid, family)
    H = 0.0
    torso_len = length - head_len - tail_len - neck_len
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    P = v3(0, H, 0.0)
    S1 = v3(0, H, -0.5 * torso_len)
    C = v3(0, H, -torso_len)
    r.add("pelvis", "root", P, S1, torso_r * 0.7, torso_r * 0.85, sx=sx, sy=sy, blend=torso_r * 0.5)
    r.add("spine", "pelvis", S1, C, torso_r * 0.85, torso_r * 0.75, sx=sx, sy=sy, blend=torso_r * 0.5)
    r.ell("spine", v3(0, 0, -0.5 * torso_len), (torso_r * sx, torso_r * sy, torso_len * 0.62), k=torso_r * 0.4)
    r.ell("spine", v3(0, -torso_r * 0.25 * sy, -0.55 * torso_len), (torso_r * sx * 0.9, torso_r * sy * 0.85, torso_len * 0.45), k=torso_r * 0.4)
    N1 = C + v3(0, neck_len * 0.05, -neck_len * 0.5)
    N2 = C + v3(0, neck_len * 0.1, -neck_len)
    r.add("neck1", "spine", C, N1, torso_r * 0.7, neck_r * 1.05, sx=sx, blend=neck_r * 0.7)
    r.add("neck2", "neck1", N1, N2, neck_r * 1.05, neck_r, blend=neck_r * 0.6)
    HB = N2
    hdir = norm(v3(0, -0.03, -1))
    r.add("head", "neck2", HB, HB + hdir * head_len, 0, 0, geo=False)
    JB = HB + v3(0, -head_r * 0.45, 0.02)
    r.add("jaw", "head", JB, JB + v3(0, -head_len * 0.06, -head_len * 0.9), 0, 0, geo=False)
    mg = length / 260 * 1.3
    if style == "shark":
        f, s_, u = _basis(hdir)
        r.ell("head", HB + f * head_len * 0.35, (head_r * 1.0, head_r * 1.0, head_len * 0.55), (s_, u, f), k=head_r * 0.4)
        r.ell("head", HB + f * head_len * 0.78 + u * head_r * 0.15, (head_r * 0.62, head_r * 0.55, head_len * 0.3), (s_, u, f), k=head_r * 0.35)
        r.cap("jaw", HB + f * head_len * 0.15 - u * head_r * 0.55, HB + f * head_len * 0.68 - u * head_r * 0.6, head_r * 0.42, head_r * 0.3, up=u, sx=1.6, k=head_r * 0.25)
        g = max(head_r * 0.06, mg)
        m0 = HB + f * head_len * 0.15 - u * head_r * 0.28
        m1 = HB + f * head_len * 0.75 - u * head_r * 0.35
        r.cap("head", m0, m1, g, g, up=u, sx=(head_r * 1.3) / g, k=g * 0.5, sub=True, region=R_MOUTH)
        for side in (-1, 1):
            for i in range(9):
                t = 0.2 + 0.55 * i / 8
                c = HB + f * head_len * t - u * head_r * (0.26 + 0.1 * t) + u * g * 1.3
                hit = r.surface_hit(c, s_ * side, head_r * 2.5)
                if hit is not None:
                    tl = head_r * 0.16 * (1.1 - 0.3 * t)
                    r.add_cone(hit - s_ * side * tl * 0.3 + u * tl * 0.1, hit - s_ * side * tl * 0.3 - u * tl, tl * 0.45, "head", R_TOOTH, segs=4)
            for gi in range(5):
                gc = HB + f * head_len * (0.02 - gi * 0.07) - u * head_r * 0.1
                hit = r.surface_hit(gc, s_ * side, head_r * 3)
                if hit is not None:
                    r.ell("head", hit, (head_r * 0.08, head_r * 0.42, head_r * 0.025), (s_, u, f), k=head_r * 0.03, sub=True)
            er = head_r * 0.07 * eye
            hit = r.surface_hit(HB + f * head_len * 0.5 + u * head_r * 0.3, s_ * side, head_r * 3)
            if hit is not None:
                r.add_eye(hit - s_ * side * er * 0.4, er, s_ * side, "head")
    else:
        f, s_, u = build_skull(r, HB, hdir, head_len, head_r * 1.8, head_r * 0.95, snout_r * 1.8, snout_r,
                               teeth=teeth, n_teeth=14, tooth_len=head_r * 0.16, eye=eye * 0.9, eye_up=0.3,
                               snout_drop=0.03, min_gap=mg)
    prev, tp = "pelvis", P
    for i in range(n_tail):
        q = tp + v3(0, 0, tail_len / n_tail)
        r0 = tail_r * (1 - i / n_tail) ** 1.0 + 0.02
        r1 = tail_r * (1 - (i + 1) / n_tail) ** 1.0 + 0.015
        r.add(f"tail{i + 1}", prev, tp, q, r0, r1, sx=0.62, blend=r0 * 0.5)
        prev, tp = f"tail{i + 1}", q
    r.chain("tail", [f"tail{i + 1}" for i in range(n_tail)])
    TE = r.b(f"tail{n_tail}").tail
    tb = f"tail{n_tail}"
    if fluke > 0:
        if style == "shark":
            _fin(r, tb, TE - v3(0, 0, fluke * 0.2), TE + v3(0, fluke * 1.0, fluke * 0.75), fluke * 0.22, fluke * 0.035, v3(1, 0, 0))
            _fin(r, tb, TE - v3(0, 0, fluke * 0.15), TE + v3(0, -fluke * 0.75, fluke * 0.45), fluke * 0.18, fluke * 0.035, v3(1, 0, 0))
        else:
            _fin(r, tb, TE - v3(0, 0, fluke * 0.2), TE + v3(0, -fluke * 0.9, fluke * 0.55), fluke * 0.22, fluke * 0.035, v3(1, 0, 0))
            _fin(r, tb, TE - v3(0, 0, fluke * 0.1), TE + v3(0, fluke * 0.45, fluke * 0.45), fluke * 0.15, fluke * 0.03, v3(1, 0, 0))
    if dorsal > 0:
        DB = v3(0, torso_r * sy * 0.8, -0.45 * torso_len)
        _fin(r, "spine", DB, DB + v3(0, dorsal, dorsal * 0.55), dorsal * 0.35, dorsal * 0.05, v3(1, 0, 0))
    for sd, sn in ((-1, "L"), (1, "R")):
        sh = C + v3(sd * torso_r * 0.7, -torso_r * 0.4, 0.1)
        el = sh + v3(sd * flipper * 0.4, -flipper * 0.1, flipper * 0.1)
        tip = el + v3(sd * flipper * 0.6, -flipper * 0.05, flipper * 0.25)
        fr = torso_r * 0.22
        r.add(f"uarm_{sn}", "spine", sh, el, 0, 0, geo=False)
        r.add(f"farm_{sn}", f"uarm_{sn}", el, tip, 0, 0, geo=False)
        r.add(f"hand_{sn}", f"farm_{sn}", tip, tip + v3(sd * 0.01, 0, 0.01), 0, 0, geo=False)
        _fin(r, f"uarm_{sn}", sh, el + (el - sh) * 0.1, flipper * 0.22, fr * 0.35, v3(0, 1, 0))
        _fin(r, f"farm_{sn}", el, tip, flipper * 0.2, fr * 0.28, v3(0, 1, 0))
        r.chain(f"arm_{sn}", [f"uarm_{sn}", f"farm_{sn}", f"hand_{sn}"])
        hp = P + v3(sd * torso_r * 0.6, -torso_r * 0.4, 0.1)
        kn = hp + v3(sd * rear_flipper * 0.4, -rear_flipper * 0.1, rear_flipper * 0.15)
        tp2 = kn + v3(sd * rear_flipper * 0.5, -rear_flipper * 0.05, rear_flipper * 0.3)
        r.add(f"thigh_{sn}", "pelvis", hp, kn, 0, 0, geo=False)
        r.add(f"shin_{sn}", f"thigh_{sn}", kn, tp2, 0, 0, geo=False)
        r.add(f"meta_{sn}", f"shin_{sn}", tp2, tp2 + v3(0, 0, 0.01), 0, 0, geo=False)
        r.add(f"toe_{sn}", f"meta_{sn}", tp2, tp2 + v3(0, 0, 0.02), 0, 0, geo=False)
        if rear_flipper > 0.05:
            _fin(r, f"thigh_{sn}", hp, kn + (kn - hp) * 0.1, rear_flipper * 0.2, fr * 0.3, v3(0, 1, 0))
            _fin(r, f"shin_{sn}", kn, tp2, rear_flipper * 0.18, fr * 0.25, v3(0, 1, 0))
        r.chain(f"leg_{sn}", [f"thigh_{sn}", f"shin_{sn}", f"meta_{sn}", f"toe_{sn}"])
    r.chain("spine", ["pelvis", "spine"])
    r.chain("neck", ["neck1", "neck2", "head"])
    r.detail_amp = length * 0.0006
    r.detail_freq = 1.0 / max(length * 0.008, 0.003)
    sk = head_r * 2
    surface_socket(r, "head_top", "head", HB + f * head_len * 0.2, u, head_r * 3, sk)
    for sd, nm in ((-1, "brow_L"), (1, "brow_R")):
        surface_socket(r, nm, "head", HB + f * head_len * 0.2, u + s_ * sd * 0.6, head_r * 3, head_r * 1.5)
    surface_socket(r, "nose", "head", HB + f * head_len * 0.75, u, head_r * 3, head_r)
    surface_socket(r, "back", "pelvis", (P + S1) * 0.5, v3(0, 1, 0), torso_r * 3, torso_r * 2)
    surface_socket(r, "back_front", "spine", (S1 + C) * 0.5, v3(0, 1, 0), torso_r * 3, torso_r * 2)
    surface_socket(r, "neck_back", "neck1", (C + N1) * 0.5, v3(0, 1, 0), neck_r * 4, neck_r * 2)
    for sd, nm in ((-1, "shoulder_L"), (1, "shoulder_R")):
        surface_socket(r, nm, "spine", C, v3(sd, 0.6, 0), torso_r * 3, torso_r * 2)
    r.socket("tail_tip", f"tail{n_tail}", TE, (0, 0, 1), tail_r)
    surface_socket(r, "tail_mid", "tail3", r.b("tail3").head, v3(0, 1, 0), tail_r * 3, tail_r * 1.5)
    surface_socket(r, "saddle", "spine", S1, v3(0, 1, 0), torso_r * 3, torso_r * 2)
    r.socket("mouth", "jaw", r.b("jaw").tail, (0, 0, -1), head_r)
    r.meta.update(gait="swim", hip_height=0.0, length=float(length))
    return r


# =====================================================================================
# SERPENT
# =====================================================================================
def serpent(rid, length=12.0, r_body=0.35, head_len=0.7, head_r=0.3, n_seg=16, family="serpent"):
    r = Rig(rid, family)
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    seg = (length - head_len) / n_seg
    # body from head (front, -z) to tail (+z); chain root at front so head drives
    z0 = -length * 0.35
    prev = "root"
    names = []
    for i in range(n_seg):
        t0 = i / n_seg
        t1 = (i + 1) / n_seg
        prof = lambda t: r_body * (0.75 + 0.35 * math.sin(min(t * 1.4, 1) * math.pi * 0.9)) * (1 - t ** 3 * 0.92)
        a = v3(0, prof(t0) * 0.9, z0 + i * seg)
        b = v3(0, prof(t1) * 0.9, z0 + (i + 1) * seg)
        nm = f"seg{i + 1}"
        r.add(nm, prev, a, b, prof(t0), prof(t1), sx=1.0, sy=0.85, blend=prof(t0) * 0.5)
        names.append(nm)
        prev = nm
    HB = r.b("seg1").head
    r.add("neck1", "seg1", HB, HB + v3(0, 0, -0.01), 0, 0, geo=False)
    r.add("head", "neck1", HB, HB + v3(0, 0.02, -head_len), head_r, head_r * 0.45, sx=1.2, sy=0.65, blend=head_r * 0.5)
    JB = HB + v3(0, -head_r * 0.3, 0)
    r.add("jaw", "head", JB, JB + v3(0, -0.02, -head_len * 0.9), head_r * 0.6, head_r * 0.3, sx=1.15, sy=0.35, blend=head_r * 0.3)
    r.chain("body", names)
    r.chain("neck", ["neck1", "head"])
    _head_details(r, "head", "jaw", True, n_teeth=6, eye_t=0.35, eye_up=0.55)
    r.socket("head_top", "head", HB + v3(0, head_r * 0.6, -head_len * 0.3), (0, 1, 0), head_r * 2)
    r.socket("brow_L", "head", HB + v3(-head_r * 0.6, head_r * 0.5, -head_len * 0.3), (-0.4, 1, 0), head_r * 1.5)
    r.socket("brow_R", "head", HB + v3(head_r * 0.6, head_r * 0.5, -head_len * 0.3), (0.4, 1, 0), head_r * 1.5)
    r.socket("back", names[n_seg // 3], r.b(names[n_seg // 3]).head + v3(0, r_body, 0), (0, 1, 0), r_body * 2)
    r.socket("back_front", names[n_seg // 6], r.b(names[n_seg // 6]).head + v3(0, r_body, 0), (0, 1, 0), r_body * 2)
    r.socket("neck_back", "seg2", r.b("seg2").head + v3(0, r_body * 0.9, 0), (0, 1, 0), r_body * 2)
    r.socket("tail_tip", names[-1], r.b(names[-1]).tail, (0, 0, 1), r_body)
    r.socket("tail_mid", names[n_seg * 2 // 3], r.b(names[n_seg * 2 // 3]).head + v3(0, r_body * 0.7, 0), (0, 1, 0), r_body * 1.5)
    r.socket("saddle", names[n_seg // 4], r.b(names[n_seg // 4]).head + v3(0, r_body * 1.0, 0), (0, 1, 0), r_body * 2)
    r.socket("mouth", "jaw", r.b("jaw").tail, (0, 0, -1), head_r)
    r.meta.update(gait="serpent", hip_height=r_body, length=float(length))
    return r


# =====================================================================================
# ARTHROPOD: giant spider
# =====================================================================================
def arthropod(rid, size=1.0, family="arthropod"):
    r = Rig(rid, family)
    s_ = size
    H = 0.55 * s_
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    C = v3(0, H, 0)
    r.add("pelvis", "root", C, C + v3(0, 0.05 * s_, 0.5 * s_), 0.0, 0.0, geo=False)
    r.add("abdomen", "pelvis", C + v3(0, 0.05 * s_, 0.25 * s_), C + v3(0, 0.15 * s_, 0.9 * s_), 0.35 * s_, 0.25 * s_, sx=1.0, sy=0.85, blend=0.08 * s_)
    r.add("spine", "pelvis", C, C + v3(0, 0.02 * s_, -0.35 * s_), 0.24 * s_, 0.2 * s_, sx=1.0, sy=0.7, blend=0.1 * s_)
    r.add("neck1", "spine", C + v3(0, 0.02 * s_, -0.35 * s_), C + v3(0, 0.0, -0.4 * s_), 0, 0, geo=False)
    r.add("head", "neck1", C + v3(0, 0.0, -0.38 * s_), C + v3(0, -0.02 * s_, -0.55 * s_), 0.13 * s_, 0.1 * s_, sy=0.8, blend=0.06 * s_)
    r.add("jaw", "head", C + v3(0, -0.06 * s_, -0.5 * s_), C + v3(0, -0.12 * s_, -0.6 * s_), 0.0, 0.0, geo=False)
    for sd, sn in ((-1, "L"), (1, "R")):
        _ = r.add_curved_cone(C + v3(sd * 0.05 * s_, -0.05 * s_, -0.52 * s_), v3(0, -1, -0.3), 0.14 * s_, 0.035 * s_, v3(0, 0, 0.8), "head", R_KERATIN)
    for i in range(4):
        z = -0.25 * s_ + i * 0.15 * s_
        spread = [-0.9, -0.3, 0.3, 0.9][i]
        for sd, sn in ((-1, "L"), (1, "R")):
            base = C + v3(sd * 0.18 * s_, -0.02 * s_, z * 0.6)
            out = norm(v3(sd * 1.0, 0, spread * 0.8))
            knee = base + out * 0.45 * s_ + v3(0, 0.35 * s_, 0)
            foot = base + out * 1.05 * s_ + v3(0, -H, 0)
            mid = knee + (foot - knee) * 0.55 + v3(0, 0.05 * s_, 0)
            lr = 0.045 * s_
            nm = f"l{i}_{sn}"
            r.add(f"{nm}a", "spine" if i < 2 else "pelvis", base, knee, lr * 1.3, lr, blend=lr * 0.5)
            r.add(f"{nm}b", f"{nm}a", knee, mid, lr, lr * 0.7, blend=lr * 0.4)
            r.add(f"{nm}c", f"{nm}b", mid, foot, lr * 0.7, lr * 0.25, blend=lr * 0.3)
            r.chain(f"spider_{i}_{sn}", [f"{nm}a", f"{nm}b", f"{nm}c"])
    for k in range(4):
        hb = r.b("head").head
        r.add_sphere(hb + v3((k - 1.5) * 0.04 * s_, 0.09 * s_, -0.1 * s_ - abs(k - 1.5) * 0.01 * s_), 0.022 * s_, "head", R_EYE, segs=8, rings=6)
    r.chain("spine", ["pelvis", "spine"])
    r.chain("neck", ["neck1", "head"])
    r.socket("head_top", "head", r.b("head").head + v3(0, 0.12 * s_, 0), (0, 1, 0), 0.2 * s_)
    r.socket("brow_L", "head", r.b("head").head + v3(-0.08 * s_, 0.1 * s_, 0), (-0.4, 1, 0), 0.15 * s_)
    r.socket("brow_R", "head", r.b("head").head + v3(0.08 * s_, 0.1 * s_, 0), (0.4, 1, 0), 0.15 * s_)
    r.socket("back", "abdomen", r.b("abdomen").head + v3(0, 0.3 * s_, 0.2 * s_), (0, 1, 0.3), 0.5 * s_)
    r.socket("back_front", "spine", C + v3(0, 0.18 * s_, -0.1 * s_), (0, 1, 0), 0.4 * s_)
    r.socket("neck_back", "spine", C + v3(0, 0.15 * s_, -0.25 * s_), (0, 1, 0), 0.3 * s_)
    r.socket("tail_tip", "abdomen", r.b("abdomen").tail, (0, 0, 1), 0.3 * s_)
    r.socket("tail_mid", "abdomen", r.b("abdomen").head + v3(0, 0.3 * s_, 0.35 * s_), (0, 1, 0), 0.3 * s_)
    r.socket("shoulder_L", "spine", C + v3(-0.15 * s_, 0.12 * s_, -0.1 * s_), (-1, 0.5, 0), 0.4 * s_)
    r.socket("shoulder_R", "spine", C + v3(0.15 * s_, 0.12 * s_, -0.1 * s_), (1, 0.5, 0), 0.4 * s_)
    r.socket("saddle", "spine", C + v3(0, 0.2 * s_, 0.05 * s_), (0, 1, 0), 0.4 * s_)
    r.socket("mouth", "head", r.b("head").tail, (0, 0, -1), 0.1 * s_)
    r.meta.update(gait="spider", hip_height=H, length=float(1.6 * s_))
    return r


# =====================================================================================
# HUMANOID: human, goblin, demon
# =====================================================================================
def humanoid(rid, height=1.8, build=1.0, head_scale=1.0, ears=0.0, nose=1.0, goblin=False, demon=False, female=False,
             family="humanoid"):
    r = Rig(rid, family)
    h = height
    bw = build
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    hipY = h * 0.52
    P = v3(0, hipY, 0)
    SP = v3(0, h * 0.63, 0.0)
    CH = v3(0, h * 0.74, 0.0)
    NK = v3(0, h * 0.84, -0.005 * h)
    HD = v3(0, h * 0.875, -0.005 * h)
    hr = h * 0.062 * head_scale
    hipw = h * (0.105 if not female else 0.115) * bw
    r.add("pelvis", "root", P + v3(0, -h * 0.01, 0), SP, h * 0.085 * bw, h * 0.075 * bw, sx=1.35, sy=1.0, blend=h * 0.04)
    r.add("spine", "pelvis", SP, CH, h * 0.075 * bw, h * 0.09 * bw, sx=1.4 if not female else 1.3, sy=0.95, blend=h * 0.05)
    r.add("chest", "spine", CH, NK + v3(0, -h * 0.02, 0), h * 0.095 * bw, h * 0.06 * bw, sx=1.45 if not female else 1.25, sy=0.95, blend=h * 0.04)
    r.add("neck1", "chest", NK + v3(0, -h * 0.02, 0), HD, h * 0.032 * bw, h * 0.03 * bw, blend=h * 0.02)
    # head: cranium, face, jaw, features (all smooth SDF prims)
    r.add("head", "neck1", HD, HD + v3(0, hr * 1.6, 0), 0, 0, geo=False)
    r.add("jaw", "head", HD + v3(0, hr * 0.55, -hr * 0.1), HD + v3(0, hr * 0.15, -hr * 0.65), 0, 0, geo=False)
    Hc = HD + v3(0, hr * 1.15, -hr * 0.05)
    F = v3(0, 0, -1)
    r.ell("head", Hc + v3(0, hr * 0.12, hr * 0.06), (hr * 0.86, hr * 1.0, hr * 1.06), k=hr * 0.2)
    r.ell("head", Hc + v3(0, -hr * 0.22, -hr * 0.42), (hr * 0.7, hr * 0.78, hr * 0.62), k=hr * 0.25)
    r.ell("jaw", Hc + v3(0, -hr * 0.7, -hr * 0.5), (hr * 0.52 * (1.15 if goblin or demon else 1.0), hr * 0.34, hr * 0.42), k=hr * 0.2)
    r.ell("jaw", Hc + v3(0, -hr * 0.9, -hr * 0.78), (hr * 0.22, hr * 0.17, hr * 0.17), k=hr * 0.12)
    r.ell("head", Hc + v3(0, hr * 0.22, -hr * 0.86), (hr * 0.62, hr * 0.13 * (1.6 if demon or goblin else 1.0), hr * 0.18), k=hr * 0.12)
    nl = nose
    r.cap("head", Hc + v3(0, hr * 0.18, -hr * 0.93), Hc + v3(0, -hr * 0.22 * nl, -hr * (1.0 + 0.2 * nl)), hr * 0.07, hr * 0.1 * nl, up=(0, 0, -1), sx=1.2, k=hr * 0.07)
    r.ell("head", Hc + v3(0, -hr * 0.27 * nl, -hr * (1.02 + 0.17 * nl)), (hr * 0.17 * nl, hr * 0.1 * nl, hr * 0.11 * nl), k=hr * 0.06)
    lip_z = -hr * 0.97
    r.ell("head", Hc + v3(0, -hr * 0.47, lip_z), (hr * 0.3, hr * 0.065, hr * 0.1), k=hr * 0.06)
    r.ell("jaw", Hc + v3(0, -hr * 0.58, lip_z + hr * 0.03), (hr * 0.28, hr * 0.07, hr * 0.1), k=hr * 0.06)
    r.cap("head", Hc + v3(-hr * 0.26, -hr * 0.52, lip_z - hr * 0.05), Hc + v3(hr * 0.26, -hr * 0.52, lip_z - hr * 0.05), hr * 0.012, hr * 0.012, up=(0, 1, 0), sx=1.0, sy=1.0, k=hr * 0.015, sub=True, region=R_MOUTH)
    er = hr * 0.12
    for sd, sn in ((-1, "L"), (1, "R")):
        r.ell("head", Hc + v3(sd * hr * 0.5, -hr * 0.3, -hr * 0.62), (hr * 0.22, hr * 0.18, hr * 0.25), k=hr * 0.15)
        ec = Hc + v3(sd * hr * 0.33, hr * 0.03, -hr * 0.72)
        r.ell("head", ec + v3(0, 0, -er * 0.75), (er * 1.15, er * 0.8, er * 0.7), k=er * 0.5, sub=True)
        r.add_eye(ec + v3(0, 0, -er * 0.15), er * 0.92, v3(sd * 0.12, 0.0, -1.0), "head")
        r.ell("head", ec + v3(0, -er * 0.75, -er * 0.25), (er * 1.0, er * 0.22, er * 0.5), k=er * 0.2)
        r.ell("head", ec + v3(0, er * 0.75, -er * 0.35), (er * 1.15, er * 0.32, er * 0.6), k=er * 0.25)
        if ears > 0:
            e0 = Hc + v3(sd * hr * 0.82, hr * 0.0, hr * 0.12)
            r.cap("head", e0, e0 + v3(sd * hr * 0.8 * ears, hr * 0.35 * ears, hr * 0.35), hr * 0.22, hr * 0.03, up=(sd, 0.3, 0), sx=1.0, sy=0.3, k=hr * 0.08)
        else:
            r.ell("head", Hc + v3(sd * hr * 0.86, hr * 0.0, hr * 0.12), (hr * 0.1, hr * 0.26, hr * 0.17), k=hr * 0.07)
    hair = not (goblin or demon)
    if hair:
        r.ell("head", Hc + v3(0, hr * 0.28, hr * 0.12), (hr * 0.93, hr * 0.9, hr * 1.06), k=hr * 0.06, region=R_HAIR)
        if female:
            r.ell("head", Hc + v3(0, -hr * 0.55, hr * 0.62), (hr * 0.85, hr * 1.25, hr * 0.42), k=hr * 0.2, region=R_HAIR)
        else:
            r.ell("head", Hc + v3(0, -hr * 0.15, hr * 0.55), (hr * 0.8, hr * 0.6, hr * 0.42), k=hr * 0.15, region=R_HAIR)
    if female:
        for s_ in (-1, 1):
            r.ell("chest", CH + v3(s_ * h * 0.05, h * 0.0, -h * 0.07), (h * 0.05, h * 0.05, h * 0.045), k=h * 0.03)
    # musculature & clothing details
    r.ell("chest", CH + v3(0, h * 0.0, -h * 0.045), (h * 0.12 * bw, h * 0.06, h * 0.05), k=h * 0.03)
    r.ell("neck1", NK + v3(0, -h * 0.005, -h * 0.005), (h * 0.042 * bw, h * 0.02, h * 0.04), k=h * 0.02, region=R_TOP)
    r.ell("pelvis", P + v3(0, h * 0.035, 0), (h * 0.125 * bw, h * 0.022, h * 0.088 * bw), k=h * 0.008, region=R_BOOTS)
    r.ell("pelvis", P + v3(0, -h * 0.03, h * 0.05), (h * 0.1 * bw, h * 0.06, h * 0.05), k=h * 0.03)
    # arms
    for s, sn in ((-1, "L"), (1, "R")):
        sh = CH + v3(s * h * 0.115 * bw, h * 0.045, 0.01)
        el = sh + v3(s * h * 0.03, -h * 0.17, 0.01 * h)
        wr = el + v3(s * h * 0.012, -h * 0.15, -0.02 * h)
        hn = wr + v3(0, -h * 0.085, -0.005 * h)
        r.add(f"clav_{sn}", "chest", CH + v3(s * h * 0.02, h * 0.04, 0), sh, h * 0.035 * bw, h * 0.04 * bw, blend=h * 0.03)
        r.add(f"uarm_{sn}", f"clav_{sn}", sh, el, h * 0.042 * bw, h * 0.032 * bw, blend=h * 0.02)
        r.add(f"farm_{sn}", f"uarm_{sn}", el, wr, h * 0.032 * bw, h * 0.022 * bw, sx=1.1, blend=h * 0.015)
        r.add(f"hand_{sn}", f"farm_{sn}", wr, hn, h * 0.024 * bw, h * 0.02 * bw, sx=1.4, sy=0.6, blend=h * 0.01)
        r.ell(f"uarm_{sn}", sh + v3(s * h * 0.01, -h * 0.01, 0), (h * 0.05 * bw, h * 0.05, h * 0.048 * bw), k=h * 0.02)
        r.ell_along(f"farm_{sn}", el, el + (wr - el) * 0.6, h * 0.033 * bw, h * 0.036 * bw, up=(0, 0, -1), k=h * 0.012)
        r.cap(f"hand_{sn}", wr + v3(-s * h * 0.012, -h * 0.01, -h * 0.012), wr + v3(-s * h * 0.022, -h * 0.05, -h * 0.025), h * 0.011, h * 0.008, k=h * 0.008)
        if goblin or demon:
            _claws(r, f"hand_{sn}", 4, h * 0.03 * (1.8 if demon else 1.0), h * 0.011, curve_down=0.6)
        r.chain(f"arm_{sn}", [f"clav_{sn}", f"uarm_{sn}", f"farm_{sn}", f"hand_{sn}"])
        hip = P + v3(s * hipw * 0.85, -h * 0.03, 0)
        kn = v3(s * hipw * 0.75, h * 0.28, -0.01 * h)
        an = v3(s * hipw * 0.7, h * 0.045, 0.01 * h)
        toe = an + v3(0, -h * 0.03, -h * 0.1)
        r.add(f"thigh_{sn}", "pelvis", hip, kn, h * 0.062 * bw, h * 0.04 * bw, blend=h * 0.03)
        r.add(f"shin_{sn}", f"thigh_{sn}", kn, an, h * 0.042 * bw, h * 0.026 * bw, blend=h * 0.02)
        r.ell_along(f"shin_{sn}", kn + v3(0, -h * 0.02, h * 0.01), kn + (an - kn) * 0.55 + v3(0, 0, h * 0.012), h * 0.04 * bw, h * 0.045 * bw, up=(0, 0, 1), k=h * 0.015)
        r.ell(f"shin_{sn}", an + (kn - an) * 0.42, (h * 0.04 * bw, h * 0.018, h * 0.042 * bw), k=h * 0.006, region=R_BOOTS)
        r.add(f"meta_{sn}", f"shin_{sn}", an, an + (toe - an) * 0.6, h * 0.03, h * 0.032, sx=1.1, sy=0.7, blend=h * 0.015)
        r.add(f"toe_{sn}", f"meta_{sn}", an + (toe - an) * 0.6, toe, h * 0.03, h * 0.025, sx=1.2, sy=0.6, blend=h * 0.01)
        r.chain(f"leg_{sn}", [f"thigh_{sn}", f"shin_{sn}", f"meta_{sn}", f"toe_{sn}"])
    if goblin or demon:
        for s in (-1, 1):
            r.add_cone(HD + v3(s * hr * 0.3, hr * 0.3, -hr * 0.62), HD + v3(s * hr * 0.32, hr * (0.6 if demon else 0.5), -hr * 0.66), hr * 0.06, "jaw", R_TOOTH, segs=5)
    r.chain("spine", ["pelvis", "spine", "chest"])
    r.chain("neck", ["neck1", "head"])
    r.socket("head_top", "head", HD + v3(0, hr * 2.1, 0), (0, 1, 0), hr * 2)
    r.socket("brow_L", "head", HD + v3(-hr * 0.55, hr * 1.75, -hr * 0.55), (-0.5, 1, -0.2), hr * 1.6)
    r.socket("brow_R", "head", HD + v3(hr * 0.55, hr * 1.75, -hr * 0.55), (0.5, 1, -0.2), hr * 1.6)
    r.socket("hand_R", "hand_R", r.b("hand_R").head * 0.4 + r.b("hand_R").tail * 0.6, (0, 0, -1), 1.0)
    r.socket("hand_L", "hand_L", r.b("hand_L").head * 0.4 + r.b("hand_L").tail * 0.6, (0, 0, -1), 1.0)
    r.socket("back", "chest", CH + v3(0, h * 0.03, h * 0.08), (0, 0, 1), h * 0.2)
    r.socket("back_front", "chest", CH + v3(0, h * 0.03, h * 0.08), (0, 0, 1), h * 0.2)
    r.socket("shoulder_L", "chest", CH + v3(-h * 0.08, h * 0.06, h * 0.06), (-0.3, 0.2, 1), h * 0.3)
    r.socket("shoulder_R", "chest", CH + v3(h * 0.08, h * 0.06, h * 0.06), (0.3, 0.2, 1), h * 0.3)
    r.socket("tail_tip", "pelvis", P + v3(0, 0, h * 0.08), (0, -0.3, 1), h * 0.3)
    r.socket("tail_mid", "pelvis", P + v3(0, 0, h * 0.08), (0, -0.3, 1), h * 0.3)
    r.socket("neck_back", "chest", NK + v3(0, 0, h * 0.04), (0, 0.5, 1), h * 0.1)
    r.socket("mouth", "jaw", r.b("jaw").tail, (0, 0, -1), hr)
    r.socket("pauldron_L", "uarm_L", r.b("uarm_L").head + v3(0, h * 0.01, 0), (-1, 0.6, 0), h * 0.1)
    r.socket("pauldron_R", "uarm_R", r.b("uarm_R").head + v3(0, h * 0.01, 0), (1, 0.6, 0), h * 0.1)
    hd_y = HD[1]

    def region_fn(p, n, bn, cur):
        if cur != 0:
            return None
        if bn in ("pelvis", "spine", "chest") or bn.startswith(("clav", "uarm", "farm")):
            return R_BOTTOM if (bn == "pelvis" and p[1] < hipY + h * 0.02) else R_TOP
        if bn.startswith(("thigh", "shin")):
            return R_BOTTOM
        if bn.startswith(("meta", "toe")) or (bn.startswith("shin") and p[1] < h * 0.17):
            return R_BOOTS
        if bn == "neck1":
            return None
        return None
    r.region_fn = region_fn
    r.meta.update(gait="human", hip_height=hipY, length=0.4 * h, height=h)
    return r
