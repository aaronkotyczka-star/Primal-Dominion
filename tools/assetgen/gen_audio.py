"""Procedural sound synthesis -> assets/audio (WAV one-shots, OGG loops/music). Deterministic."""
import os

import numpy as np
import soundfile as sf
from scipy import signal

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")
SR = 22050
rng = np.random.default_rng(2024)


def t_(d):
    return np.arange(int(d * SR)) / SR


def env(n, a=0.01, d=0.2, s=0.6, r=0.3, total=None):
    total = total or n / SR
    t = np.arange(n) / SR
    e = np.ones(n) * s
    e[t < a] = t[t < a] / max(a, 1e-4)
    m = (t >= a) & (t < a + d)
    e[m] = 1 - (1 - s) * (t[m] - a) / max(d, 1e-4)
    rel = t > total - r
    e[rel] *= np.clip((total - t[rel]) / max(r, 1e-4), 0, 1)
    return e


def noise(n):
    return rng.standard_normal(n)


def bp(x, lo, hi, order=2):
    b, a = signal.butter(order, [lo / (SR / 2), min(hi / (SR / 2), 0.99)], btype="band")
    return signal.lfilter(b, a, x)


def lp(x, f, order=2):
    b, a = signal.butter(order, min(f / (SR / 2), 0.99), btype="low")
    return signal.lfilter(b, a, x)


def hp(x, f, order=2):
    b, a = signal.butter(order, min(f / (SR / 2), 0.99), btype="high")
    return signal.lfilter(b, a, x)


def saw(freq_arr):
    ph = np.cumsum(freq_arr) / SR
    return 2 * (ph % 1.0) - 1


def sine(freq_arr):
    return np.sin(2 * np.pi * np.cumsum(freq_arr) / SR)


def norm(x, peak=0.9):
    m = np.max(np.abs(x)) + 1e-9
    return x / m * peak


def save(name, x, ogg=False):
    x = norm(x)
    path = os.path.join(OUT, name + (".ogg" if ogg else ".wav"))
    if ogg:
        sf.write(path, x.astype(np.float32), SR, format="OGG", subtype="VORBIS")
    else:
        sf.write(path, (x * 32767).astype(np.int16), SR, subtype="PCM_16")


def formant_voice(dur, f0_start, f0_end, formants, rough=0.4, breath=0.3, trem=0.0):
    n = int(dur * SR)
    tt = np.arange(n) / SR
    f0 = np.geomspace(f0_start, f0_end, n) * (1 + 0.03 * np.sin(2 * np.pi * 5.5 * tt))
    src = saw(f0) + rough * noise(n) * 0.5
    src = src * (1 + trem * np.sin(2 * np.pi * 22 * tt))
    out = np.zeros(n)
    for (fc, bw, g) in formants:
        out += bp(src, max(fc - bw, 30), fc + bw) * g
    out += bp(noise(n), 300, 3000) * breath
    return out


def roar(dur, f0a, f0b, deep=1.0, rough=0.6):
    x = formant_voice(dur, f0a, f0b, [(220 * deep, 120, 1.0), (520 * deep, 200, 0.7), (1100 * deep, 400, 0.4)], rough=rough, breath=0.5, trem=0.25)
    x += lp(noise(len(x)), 400 * deep) * 0.8
    return x * env(len(x), 0.08, 0.3, 0.8, dur * 0.45)


def main():
    os.makedirs(OUT, exist_ok=True)
    # ---------------- UI
    save("ui_click", sine(np.full(int(0.05 * SR), 1300.0)) * env(int(0.05 * SR), 0.002, 0.02, 0.3, 0.02))
    save("ui_open", sine(np.geomspace(500, 900, int(0.15 * SR))) * env(int(0.15 * SR), 0.005, 0.05, 0.5, 0.08))
    save("ui_error", saw(np.full(int(0.2 * SR), 140.0)) * env(int(0.2 * SR), 0.005, 0.05, 0.6, 0.1) * 0.5)
    n = int(1.2 * SR)
    tt = t_(1.2)
    q = sum(sine(np.full(n, f)) * np.exp(-tt * 2.5) * np.clip((tt - d) * 30, 0, 1) for f, d in [(523, 0), (659, 0.12), (784, 0.24), (1047, 0.36)])
    save("ui_quest", q)
    save("ui_levelup", q + 0.5 * sine(np.geomspace(300, 1200, n)) * np.exp(-tt * 3))
    # ---------------- foley
    for i in range(4):
        n = int(0.18 * SR)
        x = lp(noise(n), 900 + i * 150) * env(n, 0.003, 0.05, 0.2, 0.1)
        save(f"footstep_{i}", x)
    for i in range(3):
        n = int(0.6 * SR)
        x = lp(noise(n), 160) * env(n, 0.005, 0.2, 0.3, 0.35) * 2 + sine(np.geomspace(70, 35, n)) * np.exp(-t_(0.6) * 7)
        save(f"footstep_heavy_{i}", x)
    for i in range(3):
        n = int(0.25 * SR)
        x = bp(noise(n), 400 + 300 * i, 3500) * np.sin(np.linspace(0, np.pi, n)) ** 2
        save(f"swing_{i}", x)
    for i in range(3):
        n = int(0.22 * SR)
        x = lp(noise(n), 1200) * env(n, 0.002, 0.04, 0.2, 0.15) + sine(np.geomspace(180, 80, n)) * np.exp(-t_(0.22) * 20) * 0.8
        save(f"hit_flesh_{i}", x)
    n = int(0.3 * SR)
    save("block", bp(noise(n), 300, 1800) * np.exp(-t_(0.3) * 18) + sine(np.full(n, 220)) * np.exp(-t_(0.3) * 14) * 0.6)
    save("parry", sum(sine(np.full(n, f)) for f in (1800, 2650, 3900)) * np.exp(-t_(0.3) * 9))
    save("bow_shot", bp(noise(int(0.25 * SR)), 200, 1200) * np.exp(-t_(0.25) * 25) + sine(np.geomspace(300, 120, int(0.25 * SR))) * np.exp(-t_(0.25) * 30))
    save("arrow_hit", lp(noise(int(0.12 * SR)), 2500) * np.exp(-t_(0.12) * 40))
    n = int(1.2 * SR)
    save("gun_shot", lp(noise(n), 3000) * np.exp(-t_(1.2) * 9) + sine(np.geomspace(120, 40, n)) * np.exp(-t_(1.2) * 6))
    n = int(2.0 * SR)
    save("explosion", lp(noise(n), 600) * np.exp(-t_(2.0) * 2.5) * 1.5 + sine(np.geomspace(80, 25, n)) * np.exp(-t_(2.0) * 3))
    n = int(0.9 * SR)
    sp = sine(np.geomspace(300, 1200, n)) * 0.4 + bp(noise(n), 2000, 6000) * 0.4
    save("spell_cast", sp * env(n, 0.05, 0.2, 0.6, 0.4))
    hl = sum(sine(np.full(n, f) * (1 + 0.01 * np.sin(2 * np.pi * 6 * t_(0.9)))) for f in (523, 659, 784)) * 0.3
    save("spell_heal", hl * env(n, 0.1, 0.2, 0.7, 0.4))
    for i in range(3):
        n = int(0.35 * SR)
        x = bp(noise(n), 500, 2500) * np.exp(-t_(0.35) * 14) + sine(np.full(n, 160 + i * 20)) * np.exp(-t_(0.35) * 20)
        save(f"chop_{i}", x)
    for i in range(3):
        n = int(0.3 * SR)
        x = hp(noise(n), 1500) * np.exp(-t_(0.3) * 25) + sum(sine(np.full(n, f)) for f in (900 + i * 100, 2300)) * np.exp(-t_(0.3) * 18) * 0.5
        save(f"mine_{i}", x)
    n = int(0.25 * SR)
    save("pickup", sine(np.geomspace(600, 1100, n)) * env(n, 0.005, 0.05, 0.4, 0.15) * 0.6)
    n = int(0.8 * SR)
    save("craft", sum(lp(noise(n), 2000) * np.exp(-((t_(0.8) - d) * 30) ** 2) for d in (0.1, 0.35, 0.6)))
    save("build", sum(lp(noise(n), 900) * np.exp(-((t_(0.8) - d) * 20) ** 2) for d in (0.1, 0.4)) + sine(np.geomspace(120, 60, n)) * np.exp(-t_(0.8) * 5))
    n = int(0.6 * SR)
    save("eat", sum(bp(noise(n), 300, 2000) * np.exp(-((t_(0.6) - d) * 25) ** 2) for d in (0.1, 0.3, 0.5)))
    n = int(0.7 * SR)
    save("splash", bp(noise(n), 300, 4000) * env(n, 0.01, 0.1, 0.4, 0.5))
    # ---------------- creature voices
    save("roar_big_0", roar(2.6, 90, 55, 0.7, 0.7))
    save("roar_big_1", roar(2.2, 110, 60, 0.75, 0.8))
    save("roar_mid_0", roar(1.6, 170, 110, 1.0))
    save("roar_mid_1", roar(1.4, 200, 120, 1.05))
    save("roar_dragon", roar(2.5, 140, 70, 0.85, 0.9) + bp(noise(int(2.5 * SR)), 1500, 5000) * 0.3 * env(int(2.5 * SR), 0.1, 0.4, 0.6, 1.2))
    save("roar_water", lp(roar(2.4, 80, 45, 0.6), 700))
    save("roar_demon", roar(2.5, 85, 45, 0.6, 1.0) + formant_voice(2.5, 300, 160, [(900, 300, 0.6)], rough=1.0) * 0.4)
    for i in range(2):
        d = 0.9
        n = int(d * SR)
        f = np.concatenate([np.geomspace(900 + i * 200, 2400, n // 3), np.geomspace(2400, 1200, n - n // 3)])
        x = sine(f + 300 * sine(np.full(n, 47.0))) * env(n, 0.02, 0.2, 0.7, 0.3) + hp(noise(n), 2000) * 0.2 * env(n, 0.02, 0.2, 0.6, 0.3)
        save(f"screech_{i}", x)
    n = int(1.0 * SR)
    save("screech_demon", sine(np.geomspace(1400, 500, n) + 600 * sine(np.full(n, 31.0))) * env(n, 0.02, 0.3, 0.7, 0.4) + roar(1.0, 200, 90) * 0.4)
    save("hiss", hp(noise(int(1.0 * SR)), 2500) * env(int(1.0 * SR), 0.1, 0.2, 0.7, 0.4))
    save("hiss_deep", bp(noise(int(1.4 * SR)), 400, 3000) * env(int(1.4 * SR), 0.15, 0.2, 0.7, 0.5) + lp(noise(int(1.4 * SR)), 200) * 0.3)
    save("hiss_demon", hp(noise(int(1.2 * SR)), 1800) * env(int(1.2 * SR), 0.1, 0.2, 0.7, 0.4) + roar(1.2, 120, 70) * 0.25)
    for i in range(2):
        n = int(0.3 * SR)
        save(f"chirp_{i}", sine(np.geomspace(1800 + i * 300, 2600, n)) * env(n, 0.01, 0.05, 0.6, 0.15))
    n = int(1.8 * SR)
    save("bellow", formant_voice(1.8, 95, 80, [(300, 100, 1.0), (700, 200, 0.5)], rough=0.2, breath=0.15) * env(n, 0.15, 0.3, 0.8, 0.6))
    n = int(2.8 * SR)
    save("bellow_deep", formant_voice(2.8, 45, 38, [(180, 80, 1.0), (450, 150, 0.6)], rough=0.2, breath=0.15) * env(n, 0.3, 0.3, 0.8, 1.0))
    for i in range(2):
        n = int(0.5 * SR)
        save(f"grunt_{i}", formant_voice(0.5, 120 + i * 30, 90, [(350, 120, 1.0), (900, 250, 0.4)], rough=0.6) * env(n, 0.02, 0.1, 0.6, 0.25))
    n = int(2.4 * SR)
    f = np.concatenate([np.geomspace(380, 620, n // 3), np.full(n // 3, 620.0), np.geomspace(620, 420, n - 2 * (n // 3))])
    save("howl", (sine(f) + 0.3 * sine(f * 2) + 0.15 * sine(f * 3)) * env(n, 0.2, 0.3, 0.8, 0.8))
    n = int(1.0 * SR)
    save("growl", formant_voice(1.0, 80, 70, [(250, 100, 1.0), (600, 200, 0.5)], rough=1.2, trem=0.5) * env(n, 0.05, 0.2, 0.7, 0.3))
    save("growl_demon", formant_voice(1.2, 60, 50, [(200, 80, 1.0), (520, 200, 0.6)], rough=1.5, trem=0.7) * env(int(1.2 * SR), 0.05, 0.2, 0.7, 0.4))
    n = int(1.8 * SR)
    save("trumpet", (saw(np.geomspace(260, 420, n)) * 0.6 + formant_voice(1.8, 260, 420, [(900, 300, 1.0)], rough=0.3)) * env(n, 0.05, 0.3, 0.8, 0.5))
    n = int(0.7 * SR)
    save("caw", formant_voice(0.7, 600, 450, [(1200, 400, 1.0), (2500, 500, 0.5)], rough=0.8) * env(n, 0.01, 0.1, 0.6, 0.3))
    n = int(1.1 * SR)
    save("eagle", sine(np.geomspace(2200, 1500, n) * (1 + 0.04 * np.sin(2 * np.pi * 30 * t_(1.1)))) * env(n, 0.02, 0.2, 0.6, 0.5))
    n = int(3.0 * SR)
    save("whale", sine(np.geomspace(300, 180, n) * (1 + 0.05 * np.sin(2 * np.pi * 0.7 * t_(3.0)))) * env(n, 0.5, 0.5, 0.8, 1.0))
    n = int(0.4 * SR)
    save("click", sum(hp(noise(n), 3000) * np.exp(-((t_(0.4) - d) * 150) ** 2) for d in np.linspace(0.02, 0.35, 8)))
    n = int(2.2 * SR)
    save("horn_call", (sine(np.full(n, 140.0)) + 0.5 * sine(np.full(n, 280.0)) + 0.25 * saw(np.full(n, 140.0))) * env(n, 0.3, 0.3, 0.8, 0.8))
    n = int(0.6 * SR)
    save("hurt_beast_0", formant_voice(0.6, 300, 200, [(700, 200, 1.0)], rough=0.8) * env(n, 0.01, 0.1, 0.6, 0.3))
    save("hurt_beast_1", formant_voice(0.5, 380, 240, [(900, 300, 1.0)], rough=0.8) * env(int(0.5 * SR), 0.01, 0.1, 0.6, 0.25))
    n = int(1.6 * SR)
    save("death_beast", formant_voice(1.6, 200, 70, [(500, 200, 1.0), (1000, 300, 0.4)], rough=0.6) * env(n, 0.02, 0.4, 0.6, 1.0))
    for i in range(2):
        n = int(0.3 * SR)
        save(f"bite_{i}", lp(noise(n), 2500) * np.exp(-t_(0.3) * 25) + bp(noise(n), 100, 400) * np.exp(-t_(0.3) * 15))
    n = int(1.4 * SR)
    save("breath", bp(noise(n), 200, 3000) * env(n, 0.1, 0.2, 0.8, 0.5) + lp(noise(n), 150) * 0.5)
    n = int(4.0 * SR)
    th = lp(noise(n), 300) * np.exp(-t_(4.0) * 1.2) * (1 + 0.5 * np.sin(2 * np.pi * 3 * t_(4.0))) + hp(noise(n), 1500) * np.exp(-t_(4.0) * 12) * 0.6
    save("thunder", th)
    # ---------------- ambience loops (OGG, seamless via crossfade)
    def loopify(x, fade=1.0):
        f = int(fade * SR)
        a = x[:f] * np.linspace(0, 1, f)
        b = x[-f:] * np.linspace(1, 0, f)
        y = x[f:-f].copy()
        y[:f] += 0
        return np.concatenate([a + b, y])

    L = 20.0
    n = int(L * SR)
    wind = lp(noise(n), 500) * (0.6 + 0.4 * np.sin(2 * np.pi * 0.07 * t_(L)) ** 2) + bp(noise(n), 800, 1600) * 0.15 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.13 * t_(L)))
    save("amb_wind", loopify(wind), ogg=True)
    rain = hp(noise(n), 900) * 0.6 + lp(noise(n), 300) * 0.3
    drops = np.zeros(n)
    for k in rng.integers(0, n - 200, 2500):
        drops[k:k + 120] += np.exp(-np.arange(120) / 15.0) * rng.uniform(0.1, 0.5)
    rain += bp(drops, 1500, 6000) * 0.8
    save("amb_rain", loopify(rain), ogg=True)
    day = lp(noise(n), 300) * 0.15
    for k in rng.integers(0, n - SR, 70):
        dd = rng.uniform(0.08, 0.3)
        m = int(dd * SR)
        f0 = rng.uniform(2000, 4500)
        day[k:k + m] += sine(np.linspace(f0, f0 * rng.uniform(0.8, 1.3), m)) * np.sin(np.linspace(0, np.pi, m)) * rng.uniform(0.1, 0.35)
    insects = bp(noise(n), 5000, 7000) * 0.08 * (0.5 + 0.5 * np.sin(2 * np.pi * 0.2 * t_(L)))
    save("amb_day", loopify(day + insects), ogg=True)
    night = lp(noise(n), 200) * 0.1
    cr = (np.sin(2 * np.pi * 4500 * t_(L)) * (np.sin(2 * np.pi * 28 * t_(L)) > 0.6) * (np.sin(2 * np.pi * 0.9 * t_(L)) > 0)) * 0.2
    for k in rng.integers(0, n - 2 * SR, 6):
        m = int(1.5 * SR)
        night[k:k + m] += sine(np.full(m, rng.uniform(350, 500))) * np.sin(np.linspace(0, np.pi, m)) ** 3 * 0.2
    save("amb_night", loopify(night + cr), ogg=True)
    sea = lp(noise(n), 700) * (0.4 + 0.6 * np.sin(2 * np.pi * 0.12 * t_(L)) ** 4) + hp(noise(n), 2500) * 0.1 * np.sin(2 * np.pi * 0.12 * t_(L)) ** 8
    save("amb_sea", loopify(sea), ogg=True)
    demon = sum(sine(np.full(n, f) * (1 + 0.01 * np.sin(2 * np.pi * 0.1 * t_(L) + f))) for f in (41, 61.7, 82.4)) * 0.3
    demon += lp(noise(n), 120) * 0.5 + formant_voice(L, 70, 65, [(300, 100, 0.2)], rough=0.3, breath=0.05) * 0.3
    save("amb_demon", loopify(demon), ogg=True)
    # ---------------- music (slow modal pads, dark)
    def pad(chords, beat=6.0, oct_=1.0, bright=1500, pulse=0.0, drums=0.0, L_=None):
        L2 = L_ or beat * len(chords)
        n2 = int(L2 * SR)
        tt2 = t_(L2)
        y = np.zeros(n2)
        for ci, ch in enumerate(chords):
            s0 = int(ci * beat * SR)
            m = int(beat * SR * 1.3)
            seg = np.zeros(min(m, n2 - s0))
            ts = np.arange(len(seg)) / SR
            for note in ch:
                f = 440 * 2 ** ((note - 69) / 12) * oct_
                for det in (-0.004, 0.0, 0.005):
                    seg += saw(np.full(len(seg), f * (1 + det))) * 0.12
            seg = lp(seg, bright)
            e = np.sin(np.clip(ts / (beat * 1.3), 0, 1) * np.pi)
            y[s0:s0 + len(seg)] += seg * e
        if pulse > 0:
            y *= 1 - pulse * 0.5 * (1 - np.cos(2 * np.pi * (60 / 76) * tt2))
        if drums > 0:
            for k in np.arange(0, L2, 60 / 92):
                s0 = int(k * SR)
                m = int(0.5 * SR)
                if s0 + m < n2:
                    y[s0:s0 + m] += sine(np.geomspace(110, 40, m)) * np.exp(-np.arange(m) / SR * 9) * drums
        return y

    Am = [57, 60, 64]; F = [53, 57, 60]; C = [48, 52, 55]; G = [55, 59, 62]; Dm = [50, 53, 57]; E = [52, 56, 59]
    save("music_explore", loopify(pad([Am, F, C, G, Am, Dm, E, Am], 6.0), 2.0), ogg=True)
    save("music_night", loopify(pad([Dm, Am, Dm, [46, 50, 53], Dm, Am, E, Am], 7.0, 0.5, 900), 2.0), ogg=True)
    save("music_combat", loopify(pad([Am, Am, F, E, Am, Am, Dm, E], 2.6, 1.0, 2400, pulse=0.6, drums=0.9), 1.0), ogg=True)
    save("music_demon", loopify(pad([[45, 48, 51], [44, 47, 50], [45, 48, 51], [41, 44, 47]], 8.0, 0.5, 700), 2.0) + 0, ogg=True)
    save("music_boss", loopify(pad([[45, 48, 52], [46, 49, 53], [45, 48, 52], [43, 46, 50]], 3.0, 0.5, 2000, pulse=0.8, drums=1.2) , 1.0), ogg=True)
    save("music_menu", loopify(pad([Am, F, Dm, E], 8.0, 0.5, 1100), 2.0), ogg=True)
    print("audio done:", len(os.listdir(OUT)))


if __name__ == "__main__":
    main()
