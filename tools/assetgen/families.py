"""Body family builders. Each returns a Rig with a shared bone layout per family,
so animation code and part sockets work across all species of a family."""
import math

import numpy as np

from sdfrig import Rig, v3, norm, R_EYE, R_TOOTH, R_KERATIN, R_MEMBRANE, R_FEATHER, R_TOP, R_BOTTOM, R_BOOTS, R_HAIR


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
# THEROPOD: bipedal predators and ornithopods
# =====================================================================================
def theropod(rid, H=1.0, torso_len=1.0, torso_r=0.3, chest_r=0.25, neck_len=0.6, neck_r=0.12, neck_angle=40,
             head_len=0.35, head_r=0.12, snout_r=0.06, head_pitch=-8, tail_len=1.6, tail_r=0.2, leg_r=0.12,
             arm_len=0.45, arm_r=0.05, width=None, teeth=True, n_teeth=8, sx_body=0.78, hand_claws=3,
             sickle=False, eye=1.0, beak=False, deep_snout=1.0, family="theropod"):
    r = Rig(rid, family)
    w = width if width is not None else torso_r * 0.62
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    P = v3(0, H, 0.05 * torso_len)
    S1 = v3(0, H * 1.04, -0.5 * torso_len)
    C = v3(0, H * 1.0, -torso_len)
    r.add("pelvis", "root", P, S1, torso_r * 0.92, torso_r * 1.06, sx=sx_body, blend=torso_r * 0.3)
    r.add("spine", "pelvis", S1, C, torso_r * 1.06, chest_r, sx=sx_body, blend=torso_r * 0.3)
    nd = _dirv(neck_angle)
    N1 = C + nd * neck_len * 0.5
    N2 = C + nd * neck_len
    r.add("neck1", "spine", C, N1, chest_r * 0.8, neck_r * 1.1, sx=0.85, blend=neck_r * 0.8)
    r.add("neck2", "neck1", N1, N2, neck_r * 1.1, neck_r, sx=0.85, blend=neck_r * 0.6)
    hd = _dirv(head_pitch)
    HB = N2 + hd * head_r * 0.2
    HT = HB + hd * head_len
    r.add("head", "neck2", HB, HT, head_r, snout_r, sx=0.72, sy=1.0 * deep_snout, blend=head_r * 0.45)
    jd = _dirv(head_pitch - 6)
    JB = HB + v3(0, -head_r * 0.55, head_r * 0.1)
    r.add("jaw", "head", JB, JB + jd * head_len * 0.88, head_r * 0.55, snout_r * 0.55, sx=0.75, sy=0.55, blend=head_r * 0.3)
    # tail: 6 segments with taper and slight droop
    prev = "pelvis"
    tp = P
    n_t = 6
    for i in range(n_t):
        t0 = i / n_t
        t1 = (i + 1) / n_t
        q = tp + v3(0, -tail_len * 0.04 * (1 if i < 2 else 0.3), tail_len / n_t)
        r0 = tail_r * (1 - t0) ** 1.1 + 0.015
        r1 = tail_r * (1 - t1) ** 1.1 + 0.012
        nm = f"tail{i + 1}"
        r.add(nm, prev, tp, q, r0, r1, sx=0.8, blend=r0 * 0.5)
        prev = nm
        tp = q
    r.chain("tail", [f"tail{i + 1}" for i in range(n_t)])
    # legs
    for s, sn in ((-1, "L"), (1, "R")):
        hip = v3(s * w, H * 0.96, 0.02 * torso_len)
        knee = v3(s * w * 1.08, H * 0.55, -0.2 * H)
        ankle = v3(s * w * 1.02, H * 0.17, 0.12 * H)
        toe = v3(s * w, H * 0.035, -0.04 * H)
        tip = v3(s * w, H * 0.02, -0.24 * H)
        r.add(f"thigh_{sn}", "pelvis", hip, knee, leg_r * 1.7, leg_r * 1.0, sx=0.75, blend=leg_r * 0.45)
        r.add(f"shin_{sn}", f"thigh_{sn}", knee, ankle, leg_r * 0.95, leg_r * 0.55, blend=leg_r * 0.4)
        r.add(f"meta_{sn}", f"shin_{sn}", ankle, toe, leg_r * 0.5, leg_r * 0.42, blend=leg_r * 0.25)
        r.add(f"toe_{sn}", f"meta_{sn}", toe, tip, leg_r * 0.42, leg_r * 0.18, sx=1.7, sy=0.55, blend=leg_r * 0.25)
        _claws(r, f"toe_{sn}", 3, leg_r * 0.5, leg_r * 0.35, curve_down=0.6)
        if sickle:
            tb = r.b(f"toe_{sn}")
            base = tb.head + v3(s * leg_r * 0.25, leg_r * 0.35, -leg_r * 0.1)
            r.add_curved_cone(base, v3(0, 0.7, -0.6), leg_r * 1.0, leg_r * 0.2, v3(0, -1.0, -0.3), f"toe_{sn}", R_KERATIN)
        r.chain(f"leg_{sn}", [f"thigh_{sn}", f"shin_{sn}", f"meta_{sn}", f"toe_{sn}"])
        # arms
        sh = C + v3(s * chest_r * 0.62, -chest_r * 0.35, -chest_r * 0.1)
        el = sh + v3(s * arm_len * 0.08, -arm_len * 0.38, -arm_len * 0.2)
        wr = el + v3(0, -arm_len * 0.1, -arm_len * 0.36)
        hn = wr + v3(0, -arm_len * 0.08, -arm_len * 0.18)
        r.add(f"uarm_{sn}", "spine", sh, el, arm_r * 1.3, arm_r * 0.9, blend=arm_r * 0.6)
        r.add(f"farm_{sn}", f"uarm_{sn}", el, wr, arm_r * 0.9, arm_r * 0.65, blend=arm_r * 0.4)
        r.add(f"hand_{sn}", f"farm_{sn}", wr, hn, arm_r * 0.6, arm_r * 0.3, sx=0.6, blend=arm_r * 0.3)
        if hand_claws:
            _claws(r, f"hand_{sn}", hand_claws, arm_r * 1.1, arm_r * 0.3, curve_down=0.8)
        r.chain(f"arm_{sn}", [f"uarm_{sn}", f"farm_{sn}", f"hand_{sn}"])
    r.chain("spine", ["pelvis", "spine"])
    r.chain("neck", ["neck1", "neck2", "head"])
    _head_details(r, "head", "jaw", teeth, eye_scale=eye, n_teeth=n_teeth)
    # sockets (used by parts)
    hb = r.b("head")
    hd_ = norm(hb.tail - hb.head)
    r.socket("head_top", "head", hb.head + hd_ * 0.25 * head_len + v3(0, head_r * 0.85, 0), (0, 1, 0), head_r * 2)
    r.socket("nose", "head", hb.head + hd_ * 0.8 * head_len + v3(0, snout_r * 0.9, 0), (0, 1, -0.3), head_r * 1.5)
    r.socket("brow_L", "head", hb.head + hd_ * 0.2 * head_len + v3(-head_r * 0.55, head_r * 0.7, 0), (-0.4, 1, -0.2), head_r * 1.5)
    r.socket("brow_R", "head", hb.head + hd_ * 0.2 * head_len + v3(head_r * 0.55, head_r * 0.7, 0), (0.4, 1, -0.2), head_r * 1.5)
    r.socket("neck_back", "neck1", (C + N1) * 0.5 + v3(0, neck_r * 1.0, 0), (0, 1, 0.3), neck_r * 2)
    r.socket("back", "pelvis", (P + S1) * 0.5 + v3(0, torso_r * 1.0, 0), (0, 1, 0), torso_r * 2)
    r.socket("back_front", "spine", (S1 + C) * 0.5 + v3(0, torso_r * 0.95, 0), (0, 1, 0), torso_r * 2)
    r.socket("shoulder_L", "spine", C + v3(-chest_r * 0.5, chest_r * 0.7, 0.1), (-1, 0.5, 0), chest_r * 2)
    r.socket("shoulder_R", "spine", C + v3(chest_r * 0.5, chest_r * 0.7, 0.1), (1, 0.5, 0), chest_r * 2)
    tl = r.b("tail6")
    r.socket("tail_tip", "tail6", tl.tail, (0, 0, 1), tail_r * 1.2)
    r.socket("tail_mid", "tail3", r.b("tail3").head + v3(0, tail_r * 0.6, 0), (0, 1, 0), tail_r * 1.5)
    r.socket("saddle", "pelvis", (P + S1) * 0.5 + v3(0, torso_r * 1.05, -0.1 * torso_len), (0, 1, 0), torso_r * 2)
    r.socket("mouth", "jaw", r.b("jaw").tail, (0, 0, -1), head_r)
    r.socket("maw", "head", hb.head + hd_ * 0.55 * head_len + v3(0, -head_r * 0.25, 0), (0, -1, -0.2), head_r * 1.2)
    r.meta.update(gait="biped", hip_height=H, length=float(torso_len + neck_len + head_len + tail_len))
    return r


# =====================================================================================
# QUADRUPED: heavy dinos, mammals, crocodilians
# =====================================================================================
def quadruped(rid, Hh=1.0, Hs=0.9, torso_len=1.4, torso_r=0.4, chest_r=0.38, neck_len=0.5, neck_r=0.18, neck_angle=10,
              head_len=0.5, head_r=0.18, snout_r=0.1, head_pitch=-15, tail_len=1.5, tail_r=0.22, leg_r=0.12,
              fleg_r=None, width=None, teeth=False, n_teeth=6, sx_body=1.0, sy_body=0.95, mammal=False,
              sprawl=0.0, n_tail=5, feet="stump", eye=1.0, deep_snout=1.0, family="quadruped"):
    r = Rig(rid, family)
    fleg_r = fleg_r or leg_r
    w = width if width is not None else torso_r * 0.6
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    P = v3(0, Hh, 0.1 * torso_len)
    S1 = v3(0, (Hh + Hs) * 0.5 + torso_r * 0.15, -0.45 * torso_len)
    C = v3(0, Hs, -torso_len * 0.95)
    r.add("pelvis", "root", P, S1, torso_r * 0.9, torso_r * 1.05, sx=sx_body, sy=sy_body, blend=torso_r * 0.5)
    r.add("spine", "pelvis", S1, C, torso_r * 1.05, chest_r, sx=sx_body, sy=sy_body, blend=torso_r * 0.5)
    nd = _dirv(neck_angle)
    N1 = C + nd * neck_len * 0.5 + v3(0, 0, -chest_r * 0.3)
    N2 = C + nd * neck_len + v3(0, 0, -chest_r * 0.3)
    r.add("neck1", "spine", C, N1, chest_r * 0.75, neck_r * 1.1, sx=0.9, blend=neck_r * 0.8)
    r.add("neck2", "neck1", N1, N2, neck_r * 1.1, neck_r, sx=0.9, blend=neck_r * 0.6)
    hd = _dirv(head_pitch)
    HB = N2 + hd * head_r * 0.2
    HT = HB + hd * head_len
    r.add("head", "neck2", HB, HT, head_r, snout_r, sx=0.85, sy=deep_snout, blend=head_r * 0.45)
    jd = _dirv(head_pitch - 5)
    JB = HB + v3(0, -head_r * 0.5, head_r * 0.05)
    r.add("jaw", "head", JB, JB + jd * head_len * 0.82, head_r * 0.5, snout_r * 0.5, sx=0.8, sy=0.5, blend=head_r * 0.3)
    prev, tp = "pelvis", P
    for i in range(n_tail):
        t0, t1 = i / n_tail, (i + 1) / n_tail
        q = tp + v3(0, -tail_len * (0.07 if i < 2 else 0.02), tail_len / n_tail)
        r0 = tail_r * (1 - t0) ** 1.1 + 0.012
        r1 = tail_r * (1 - t1) ** 1.1 + 0.01
        nm = f"tail{i + 1}"
        r.add(nm, prev, tp, q, r0, r1, sx=0.85, blend=r0 * 0.5)
        prev, tp = nm, q
    r.chain("tail", [f"tail{i + 1}" for i in range(n_tail)])
    for s, sn in ((-1, "L"), (1, "R")):
        # hind leg
        sp = sprawl
        hip = v3(s * w, Hh * 0.92, 0.08 * torso_len)
        if mammal:
            knee = v3(s * (w + sp * Hh), Hh * 0.6, -0.12 * Hh)
            hock = v3(s * (w + sp * Hh), Hh * 0.28, 0.12 * Hh)
            paw = v3(s * (w + sp * Hh), Hh * 0.05, 0.02 * Hh)
        else:
            knee = v3(s * (w + sp * Hh * 0.8), Hh * 0.52, -0.06 * Hh)
            hock = v3(s * (w + sp * Hh), Hh * 0.16, 0.03 * Hh)
            paw = v3(s * (w + sp * Hh), Hh * 0.04, -0.02 * Hh)
        tip = paw + v3(0, -Hh * 0.02, -Hh * (0.14 if feet != "stump" else 0.09))
        r.add(f"thigh_{sn}", "pelvis", hip, knee, leg_r * 1.7, leg_r * 1.05, sx=0.85, blend=leg_r * 0.8)
        r.add(f"shin_{sn}", f"thigh_{sn}", knee, hock, leg_r * 1.0, leg_r * 0.75, blend=leg_r * 0.4)
        r.add(f"meta_{sn}", f"shin_{sn}", hock, paw, leg_r * 0.72, leg_r * 0.7, blend=leg_r * 0.3)
        r.add(f"toe_{sn}", f"meta_{sn}", paw, tip, leg_r * (0.75 if feet == "stump" else 0.55),
              leg_r * (0.6 if feet == "stump" else 0.35), sx=1.3, sy=0.55, blend=leg_r * 0.3)
        if feet == "paw":
            _claws(r, f"toe_{sn}", 4, leg_r * 0.35, leg_r * 0.22, curve_down=0.7)
        elif feet == "claw":
            _claws(r, f"toe_{sn}", 4, leg_r * 0.5, leg_r * 0.3, curve_down=0.6)
        else:
            _claws(r, f"toe_{sn}", 3, leg_r * 0.25, leg_r * 0.45, curve_down=0.4)
        r.chain(f"leg_{sn}", [f"thigh_{sn}", f"shin_{sn}", f"meta_{sn}", f"toe_{sn}"])
        # front leg
        fl = fleg_r
        sh = C + v3(s * w * 0.95, -chest_r * 0.25, 0.05 * torso_len)
        if mammal:
            el = v3(s * (w + sp * Hs), Hs * 0.55, sh[2] + 0.1 * Hs)
            wr = v3(s * (w + sp * Hs), Hs * 0.18, sh[2] + 0.02 * Hs)
        else:
            el = v3(s * (w * 1.05 + sp * Hs * 0.8), Hs * 0.5, sh[2] + 0.08 * Hs)
            wr = v3(s * (w + sp * Hs), Hs * 0.12, sh[2] - 0.02 * Hs)
        hn = v3(wr[0], Hs * 0.04, wr[2] - 0.04 * Hs)
        ht = hn + v3(0, -Hs * 0.02, -Hs * (0.1 if feet != "stump" else 0.07))
        r.add(f"uarm_{sn}", "spine", sh, el, fl * 1.5, fl * 1.0, sx=0.85, blend=fl * 0.7)
        r.add(f"farm_{sn}", f"uarm_{sn}", el, wr, fl * 0.95, fl * 0.75, blend=fl * 0.4)
        r.add(f"hand_{sn}", f"farm_{sn}", wr, hn, fl * 0.72, fl * 0.7, blend=fl * 0.3)
        r.add(f"fing_{sn}", f"hand_{sn}", hn, ht, fl * (0.72 if feet == "stump" else 0.5), fl * (0.6 if feet == "stump" else 0.32), sx=1.3, sy=0.55, blend=fl * 0.3)
        if feet == "paw":
            _claws(r, f"fing_{sn}", 4, fl * 0.35, fl * 0.22, curve_down=0.7)
        elif feet == "claw":
            _claws(r, f"fing_{sn}", 4, fl * 0.5, fl * 0.28, curve_down=0.6)
        else:
            _claws(r, f"fing_{sn}", 4, fl * 0.22, fl * 0.38, curve_down=0.4)
        r.chain(f"arm_{sn}", [f"uarm_{sn}", f"farm_{sn}", f"hand_{sn}", f"fing_{sn}"])
    r.chain("spine", ["pelvis", "spine"])
    r.chain("neck", ["neck1", "neck2", "head"])
    _head_details(r, "head", "jaw", teeth, eye_scale=eye, n_teeth=n_teeth, eye_t=0.22, eye_up=0.3)
    hb = r.b("head")
    hd_ = norm(hb.tail - hb.head)
    r.socket("head_top", "head", hb.head + hd_ * 0.2 * head_len + v3(0, head_r * 0.85, 0), (0, 1, 0), head_r * 2)
    r.socket("nose", "head", hb.head + hd_ * 0.78 * head_len + v3(0, snout_r * 0.9, 0), (0, 1, -0.4), head_r * 1.5)
    r.socket("brow_L", "head", hb.head + hd_ * 0.18 * head_len + v3(-head_r * 0.6, head_r * 0.7, 0), (-0.4, 1, -0.4), head_r * 1.5)
    r.socket("brow_R", "head", hb.head + hd_ * 0.18 * head_len + v3(head_r * 0.6, head_r * 0.7, 0), (0.4, 1, -0.4), head_r * 1.5)
    r.socket("frill", "head", hb.head + v3(0, head_r * 0.4, head_r * 0.2), (0, 0.6, 1), head_r * 2.4)
    r.socket("neck_back", "neck1", (C + N1) * 0.5 + v3(0, neck_r * 1.0, 0), (0, 1, 0.3), neck_r * 2)
    r.socket("back", "pelvis", (P + S1) * 0.5 + v3(0, torso_r * sy_body * 0.98, 0), (0, 1, 0), torso_r * 2)
    r.socket("back_front", "spine", (S1 + C) * 0.5 + v3(0, torso_r * sy_body * 0.95, 0), (0, 1, 0), torso_r * 2)
    r.socket("shoulder_L", "spine", C + v3(-chest_r * 0.6, chest_r * 0.7, 0.1), (-1, 0.5, 0), chest_r * 2)
    r.socket("shoulder_R", "spine", C + v3(chest_r * 0.6, chest_r * 0.7, 0.1), (1, 0.5, 0), chest_r * 2)
    tl = r.b(f"tail{n_tail}")
    r.socket("tail_tip", f"tail{n_tail}", tl.tail, (0, 0, 1), tail_r * 1.2)
    r.socket("tail_mid", f"tail{max(1, n_tail // 2)}", r.b(f"tail{max(1, n_tail // 2)}").head + v3(0, tail_r * 0.6, 0), (0, 1, 0), tail_r * 1.5)
    r.socket("saddle", "spine", S1 + v3(0, torso_r * sy_body * 1.0, 0), (0, 1, 0), torso_r * 2)
    r.socket("mouth", "jaw", r.b("jaw").tail, (0, 0, -1), head_r)
    r.socket("maw", "head", hb.head + hd_ * 0.45 * head_len + v3(0, -head_r * 0.2, 0), (0, -1, -0.2), head_r * 1.2)
    r.meta.update(gait="quad", hip_height=Hh, length=float(torso_len + neck_len + head_len + tail_len))
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
    r.add("head", "neck2", HB, HT, head_r, snout_r, sx=0.7, sy=1.1, blend=head_r * 0.5, region=0)
    JB = HB + v3(0, -head_r * 0.45, 0)
    r.add("jaw", "head", JB, JB + _dirv(head_pitch - 4) * head_len * 0.92, head_r * 0.5, snout_r * 0.6, sx=0.7, sy=0.5, blend=head_r * 0.3)
    if feathered:
        # hooked beak
        r.add_curved_cone(HT + v3(0, head_r * 0.15, head_r * 0.2), v3(0, 0.0, -1), head_len * 0.25, snout_r * 2.2, v3(0, -1.1, 0), "head", R_KERATIN)
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
    _head_details(r, "head", "jaw", teeth, eye_scale=1.1, n_teeth=10, eye_t=0.12 if not feathered else 0.3, eye_up=0.3)
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
    r = theropod(rid, H=H, torso_len=torso_len, torso_r=torso_r, chest_r=torso_r * 0.85, neck_len=neck_len,
                 neck_r=neck_r, neck_angle=45, head_len=head_len, head_r=head_r, snout_r=snout_r, tail_len=tail_len,
                 tail_r=tail_r, leg_r=leg_r, arm_len=0.0, arm_r=0.0, hand_claws=0, n_teeth=9, family="wyvern")
    # remove tiny arms geometry (set non-geo)
    for sn in ("L", "R"):
        for n in ("uarm", "farm", "hand"):
            r.b(f"{n}_{sn}").geo = False
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
def marine(rid, length=8.0, torso_r=0.7, neck_len=0.5, neck_r=0.35, head_len=1.2, head_r=0.35, snout_r=0.12,
           tail_len=3.5, tail_r=0.4, flipper=1.2, rear_flipper=1.0, fluke=1.0, teeth=True, sx=0.9, sy=0.9,
           n_tail=6, dorsal=0.0, family="marine"):
    r = Rig(rid, family)
    H = 0.0
    torso_len = length - head_len - tail_len - neck_len
    r.add("root", None, v3(0, 0, 0), v3(0, 0, 0), 0, 0, geo=False)
    P = v3(0, H, 0.0)
    S1 = v3(0, H, -0.5 * torso_len)
    C = v3(0, H, -torso_len)
    r.add("pelvis", "root", P, S1, torso_r * 0.85, torso_r, sx=sx, sy=sy, blend=torso_r * 0.5)
    r.add("spine", "pelvis", S1, C, torso_r, torso_r * 0.85, sx=sx, sy=sy, blend=torso_r * 0.5)
    N1 = C + v3(0, neck_len * 0.05, -neck_len * 0.5)
    N2 = C + v3(0, neck_len * 0.1, -neck_len)
    r.add("neck1", "spine", C, N1, torso_r * 0.75, neck_r * 1.05, sx=sx, blend=neck_r * 0.7)
    r.add("neck2", "neck1", N1, N2, neck_r * 1.05, neck_r, blend=neck_r * 0.6)
    HB = N2
    HT = HB + v3(0, -head_len * 0.03, -head_len)
    r.add("head", "neck2", HB, HT, head_r, snout_r, sx=0.8, sy=0.85, blend=head_r * 0.45)
    JB = HB + v3(0, -head_r * 0.45, 0.02)
    r.add("jaw", "head", JB, JB + v3(0, -head_len * 0.06, -head_len * 0.9), head_r * 0.5, snout_r * 0.55, sx=0.8, sy=0.45, blend=head_r * 0.3)
    prev, tp = "pelvis", P
    for i in range(n_tail):
        q = tp + v3(0, 0, tail_len / n_tail)
        r0 = tail_r * (1 - i / n_tail) ** 1.0 + 0.02
        r1 = tail_r * (1 - (i + 1) / n_tail) ** 1.0 + 0.015
        r.add(f"tail{i + 1}", prev, tp, q, r0, r1, sx=0.7, blend=r0 * 0.5)
        prev, tp = f"tail{i + 1}", q
    r.chain("tail", [f"tail{i + 1}" for i in range(n_tail)])
    if fluke > 0:
        TE = r.b(f"tail{n_tail}").tail
        # vertical tail fin (down-turned like mosasaur / shark-like)
        lead = [TE + v3(0, y, 0) for y in np.linspace(-fluke * 0.9, fluke * 0.5, 7)]
        trail = [p + v3(0, 0, fluke * 0.55 * (1 - abs((p[1] - TE[1]) / (fluke * 0.9)) * 0.5)) for p in lead]
        lead = [p + v3(0, 0, -fluke * 0.3 * (1 - abs(p[1] - TE[1]) / fluke)) for p in lead]
        bw = [[(f"tail{n_tail}", 1.0)]] * 7
        r.add_membrane(lead, bw, trail, bw, R_MEMBRANE, rows=3)
    if dorsal > 0:
        DB = r.b("spine").head + v3(0, torso_r * sy * 0.9, 0)
        lead = [DB + v3(0, 0, -dorsal * 0.3) + v3(0, h, h * 0.6) for h in np.linspace(0, dorsal, 5)]
        trail = [DB + v3(0, h * 0.95, dorsal * 0.6 + h * 0.2) for h in np.linspace(0, dorsal, 5)]
        bw = [[("spine", 1.0)]] * 5
        r.add_membrane(lead, bw, trail, bw, R_MEMBRANE, rows=3)
    for s, sn in ((-1, "L"), (1, "R")):
        # front flipper
        sh = C + v3(s * torso_r * 0.75, -torso_r * 0.35, 0.1)
        el = sh + v3(s * flipper * 0.4, -flipper * 0.1, flipper * 0.1)
        tip = el + v3(s * flipper * 0.6, -flipper * 0.05, flipper * 0.25)
        fr = torso_r * 0.22
        r.add(f"uarm_{sn}", "spine", sh, el, fr * 1.2, fr, sx=1.0, sy=0.4, blend=fr * 0.6)
        r.add(f"farm_{sn}", f"uarm_{sn}", el, tip, fr, fr * 0.3, sx=1.0, sy=0.35, blend=fr * 0.4)
        r.add(f"hand_{sn}", f"farm_{sn}", tip, tip + v3(s * 0.01, 0, 0.01), 0, 0, geo=False)
        r.chain(f"arm_{sn}", [f"uarm_{sn}", f"farm_{sn}", f"hand_{sn}"])
        hp = P + v3(s * torso_r * 0.7, -torso_r * 0.35, 0.1)
        kn = hp + v3(s * rear_flipper * 0.4, -rear_flipper * 0.1, rear_flipper * 0.15)
        tp2 = kn + v3(s * rear_flipper * 0.5, -rear_flipper * 0.05, rear_flipper * 0.3)
        rr = fr * 0.9
        r.add(f"thigh_{sn}", "pelvis", hp, kn, rr * 1.2, rr, sy=0.4, blend=rr * 0.6)
        r.add(f"shin_{sn}", f"thigh_{sn}", kn, tp2, rr, rr * 0.3, sy=0.35, blend=rr * 0.4)
        r.add(f"meta_{sn}", f"shin_{sn}", tp2, tp2 + v3(0, 0, 0.01), 0, 0, geo=False)
        r.add(f"toe_{sn}", f"meta_{sn}", tp2, tp2 + v3(0, 0, 0.02), 0, 0, geo=False)
        r.chain(f"leg_{sn}", [f"thigh_{sn}", f"shin_{sn}", f"meta_{sn}", f"toe_{sn}"])
    r.chain("spine", ["pelvis", "spine"])
    r.chain("neck", ["neck1", "neck2", "head"])
    _head_details(r, "head", "jaw", teeth, n_teeth=10, eye_t=0.2, eye_up=0.35)
    hb = r.b("head")
    r.socket("head_top", "head", hb.head + v3(0, head_r * 0.8, -head_len * 0.2), (0, 1, 0), head_r * 2)
    r.socket("brow_L", "head", hb.head + v3(-head_r * 0.5, head_r * 0.6, -head_len * 0.15), (-0.4, 1, 0), head_r * 1.5)
    r.socket("brow_R", "head", hb.head + v3(head_r * 0.5, head_r * 0.6, -head_len * 0.15), (0.4, 1, 0), head_r * 1.5)
    r.socket("nose", "head", hb.head + v3(0, snout_r * 1.2, -head_len * 0.75), (0, 1, 0), head_r)
    r.socket("back", "pelvis", (P + S1) * 0.5 + v3(0, torso_r * sy * 0.95, 0), (0, 1, 0), torso_r * 2)
    r.socket("back_front", "spine", (S1 + C) * 0.5 + v3(0, torso_r * sy * 0.95, 0), (0, 1, 0), torso_r * 2)
    r.socket("neck_back", "neck1", (C + N1) * 0.5 + v3(0, neck_r, 0), (0, 1, 0), neck_r * 2)
    r.socket("shoulder_L", "spine", C + v3(-torso_r * 0.5, torso_r * 0.7, 0.1), (-1, 0.5, 0), torso_r * 2)
    r.socket("shoulder_R", "spine", C + v3(torso_r * 0.5, torso_r * 0.7, 0.1), (1, 0.5, 0), torso_r * 2)
    r.socket("tail_tip", f"tail{n_tail}", r.b(f"tail{n_tail}").tail, (0, 0, 1), tail_r)
    r.socket("tail_mid", "tail3", r.b("tail3").head + v3(0, tail_r * 0.6, 0), (0, 1, 0), tail_r * 1.5)
    r.socket("saddle", "spine", S1 + v3(0, torso_r * sy * 1.0, 0), (0, 1, 0), torso_r * 2)
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
    # head: cranium blob + jaw
    r.add("head", "neck1", HD, HD + v3(0, hr * 1.6, 0), hr * 0.95, hr * 1.0, sx=0.9, sy=1.0, blend=hr * 0.3)
    r.blob("head", HD + v3(0, hr * 1.2, -hr * 0.05), (hr * 0.95, hr * 1.12, hr * 1.12), k=hr * 0.3)
    r.add("jaw", "head", HD + v3(0, hr * 0.55, -hr * 0.1), HD + v3(0, hr * 0.15, -hr * 0.65), hr * 0.62, hr * 0.38, sx=1.1, blend=hr * 0.35)
    # nose / brow
    nl = hr * 0.35 * nose
    r.blob("head", HD + v3(0, hr * 0.95, -hr * 1.0 - nl * 0.4), (hr * 0.13 * nose, hr * 0.25 * nose, nl), k=hr * 0.12)
    r.blob("head", HD + v3(0, hr * 1.32, -hr * 0.9), (hr * 0.75, hr * 0.13, hr * 0.2), k=hr * 0.15)
    for s, sn in ((-1, "L"), (1, "R")):
        r.add_sphere(HD + v3(s * hr * 0.36, hr * 1.17, -hr * 0.86), hr * 0.13, "head", R_EYE, segs=10, rings=7)
        if ears > 0:
            e0 = HD + v3(s * hr * 0.9, hr * 1.15, 0.0)
            r.blob("head", e0 + v3(s * hr * 0.35 * ears, hr * 0.25 * ears, hr * 0.15), (hr * 0.45 * ears, hr * 0.1, hr * 0.22), k=hr * 0.1)
        else:
            r.blob("head", HD + v3(s * hr * 0.92, hr * 1.12, 0.0), (hr * 0.12, hr * 0.25, hr * 0.17), k=hr * 0.08)
    if female:
        for s in (-1, 1):
            r.blob("chest", CH + v3(s * h * 0.05, h * 0.0, -h * 0.07), (h * 0.05, h * 0.05, h * 0.045), k=h * 0.03)
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
        if goblin or demon:
            _claws(r, f"hand_{sn}", 4, h * 0.03 * (1.8 if demon else 1.0), h * 0.011, curve_down=0.6)
        r.chain(f"arm_{sn}", [f"clav_{sn}", f"uarm_{sn}", f"farm_{sn}", f"hand_{sn}"])
        hip = P + v3(s * hipw * 0.85, -h * 0.03, 0)
        kn = v3(s * hipw * 0.75, h * 0.28, -0.01 * h)
        an = v3(s * hipw * 0.7, h * 0.045, 0.01 * h)
        toe = an + v3(0, -h * 0.03, -h * 0.1)
        r.add(f"thigh_{sn}", "pelvis", hip, kn, h * 0.062 * bw, h * 0.04 * bw, blend=h * 0.03)
        r.add(f"shin_{sn}", f"thigh_{sn}", kn, an, h * 0.042 * bw, h * 0.026 * bw, blend=h * 0.02)
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
    hair = not (goblin or demon)
    hd_y = HD[1]

    def region_fn(p, n, bn, cur):
        if cur != 0:
            return None
        if bn in ("pelvis", "spine", "chest") or bn.startswith(("clav", "uarm", "farm")):
            return R_BOTTOM if (bn == "pelvis" and p[1] < hipY + h * 0.02) else R_TOP
        if bn.startswith(("thigh", "shin")):
            return R_BOTTOM
        if bn.startswith(("meta", "toe")):
            return R_BOOTS
        if bn == "neck1":
            return None
        if hair and bn in ("head",):
            if p[1] > hd_y + hr * 1.42 and not (p[2] < -hr * 0.55 and p[1] < hd_y + hr * 1.75):
                return R_HAIR
            if p[2] > hr * 0.25 and p[1] > hd_y + hr * 0.75:
                return R_HAIR
        return None
    r.region_fn = region_fn
    r.meta.update(gait="human", hip_height=hipY, length=0.4 * h, height=h)
    return r
