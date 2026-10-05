"""World generator: heightmap, splat maps, biome/region maps, vegetation instances, POIs, map image.
Archipelago 'Vor'Thal': core island Grünkrone + four satellite islands. Deterministic (seeded).
Coordinates: x east, z south (Godot -Z = north), meters, world spans [-1024, 1024]."""
import json
import math
import os
import struct

import numpy as np
from PIL import Image
from scipy import ndimage

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "world")
N = 1025
EXT = 1024.0
CELL = 2 * EXT / (N - 1)
SEA = 0.0

rng = np.random.default_rng(1337)

# ------------------------------------------------------------------ noise
_perm = np.random.default_rng(42).permutation(512)
_perm = np.concatenate([_perm, _perm]) % 256
_grad = np.array([[math.cos(a), math.sin(a)] for a in np.linspace(0, 2 * math.pi, 16, endpoint=False)])


def perlin(x, y):
    xi = np.floor(x).astype(int) & 255
    yi = np.floor(y).astype(int) & 255
    xf = x - np.floor(x)
    yf = y - np.floor(y)
    u = xf * xf * xf * (xf * (xf * 6 - 15) + 10)
    v = yf * yf * yf * (yf * (yf * 6 - 15) + 10)

    def g(ix, iy, dx, dy):
        h = _perm[_perm[ix] + iy] % 16
        return _grad[h, 0] * dx + _grad[h, 1] * dy

    n00 = g(xi, yi, xf, yf)
    n10 = g(xi + 1, yi, xf - 1, yf)
    n01 = g(xi, yi + 1, xf, yf - 1)
    n11 = g(xi + 1, yi + 1, xf - 1, yf - 1)
    x1 = n00 + u * (n10 - n00)
    x2 = n01 + u * (n11 - n01)
    return x1 + v * (x2 - x1)


def fbm(x, y, octaves=6, lac=2.0, gain=0.5, seed=0):
    tot = np.zeros_like(x)
    amp = 1.0
    f = 1.0
    norm_ = 0
    for o in range(octaves):
        tot += perlin(x * f + seed * 17.13 + o * 3.7, y * f + seed * 9.71 - o * 5.3) * amp
        norm_ += amp
        amp *= gain
        f *= lac
    return tot / norm_


def ridged(x, y, octaves=5, seed=0):
    tot = np.zeros_like(x)
    amp = 1.0
    f = 1.0
    w = 1.0
    norm_ = 0
    for o in range(octaves):
        n = 1.0 - np.abs(perlin(x * f + seed * 3.1 + o * 1.7, y * f - seed * 2.3 + o * 4.1))
        n = n * n * w
        w = np.clip(n * 2.0, 0, 1)
        tot += n * amp
        norm_ += amp
        amp *= 0.5
        f *= 2.0
    return tot / norm_


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ------------------------------------------------------------------ layout
ISLANDS = [
    # name, cx, cz, radius, base height, kind
    ("gruenkrone", 0.0, 0.0, 780.0, 34.0, "core"),
    ("aschenkamm", 720.0, -700.0, 240.0, 30.0, "volcano"),
    ("weisszahn", -730.0, -690.0, 270.0, 60.0, "snow"),
    ("glutsand", 710.0, 660.0, 270.0, 16.0, "desert"),
    ("narbe", -700.0, 690.0, 200.0, 22.0, "corrupted"),
]

POIS = {
    "start_beach": dict(x=60, z=398, kind="spawn", name="Treibgutstrand", flatten=22),
    "morgengrau": dict(x=-130, z=390, kind="village", faction="morgengrau", name="Morgengrau", flatten=46),
    "moosfell": dict(x=340, z=120, kind="village", faction="moosfell", name="Moosfell-Dorf", flatten=50),
    "knochenbrecher": dict(x=-390, z=150, kind="camp", faction="knochenbrecher", name="Knochenbrecher-Lager", flatten=48),
    "alte_warte": dict(x=-210, z=40, kind="ruin", name="Alte Warte", flatten=22),
    "schrein": dict(x=385, z=-300, kind="shrine", name="Schrein des Gehörnten", flatten=16),
    "riss_narbenschlund": dict(x=-300, z=-270, kind="rift", name="Narbenschlund", flatten=40),
    "adlerhorst": dict(x=20, z=-430, kind="plateau", name="Adlerhorst"),
    "wurzelhoehle": dict(x=-170, z=-290, kind="cave", name="Wurzelhöhlen"),
    "versunkener_tempel": dict(x=330, z=780, kind="underwater_ruin", name="Versunkener Tempel"),
    "raptor_nest_1": dict(x=-40, z=110, kind="nest", species="raptor", name="Raptorennest"),
    "raptor_nest_2": dict(x=230, z=260, kind="nest", species="raptor", name="Raptorennest"),
    "dilo_nest": dict(x=420, z=-40, kind="nest", species="dilophosaurus", name="Dilophosaurus-Gelege"),
    "teergrube": dict(x=250, z=-180, kind="tarpit", name="Teergrube", flatten=14),
    "wyvern_nest": dict(x=700, z=-760, kind="nest", species="wyvern", name="Wyvernhorst"),
    "vulkan_krater": dict(x=720, z=-700, kind="volcano", name="Aschenkamm-Krater"),
    "weisszahn_hoehle": dict(x=-700, z=-620, kind="cave", name="Eisgrotte"),
    "oase": dict(x=680, z=620, kind="oasis", name="Glutsand-Oase", flatten=40),
    "narbe_zitadelle": dict(x=-700, z=700, kind="citadel", name="Zitadelle der Narbe", flatten=46),
    "fischerkap": dict(x=520, z=430, kind="camp", faction="morgengrau", name="Fischerkap", flatten=24),
    "wolfsschlucht": dict(x=-300, z=-60, kind="den", species="direwolf", name="Wolfsschlucht"),
}


def build():
    os.makedirs(OUT, exist_ok=True)
    lin = np.linspace(-EXT, EXT, N)
    X, Z = np.meshgrid(lin, lin, indexing="xy")  # rows = z, cols = x
    H = np.full((N, N), -70.0)
    island_id = np.full((N, N), -1, int)
    land = np.zeros((N, N))
    warp_x = fbm(X / 300.0, Z / 300.0, 4, seed=1) * 120
    warp_z = fbm(X / 300.0, Z / 300.0, 4, seed=2) * 120
    for i, (name, cx, cz, r, base, kind) in enumerate(ISLANDS):
        dx = X + warp_x * (r / 640) - cx
        dz = Z + warp_z * (r / 640) - cz
        d = np.sqrt(dx * dx + dz * dz)
        ang = np.arctan2(dz, dx)
        rr = r * (1.0 + 0.18 * np.sin(ang * 3 + i) + 0.1 * np.sin(ang * 7 + i * 2.1))
        m = 1.0 - smoothstep(rr * 0.55, rr * 1.0, d)
        h = -70 + (base + 70) * m
        upd = m > land
        land = np.maximum(land, m)
        island_id[upd & (m > 0.02)] = i
        H = np.maximum(H, h)
    # base relief
    hills = fbm(X / 260.0, Z / 260.0, 6, seed=5)
    detail = fbm(X / 60.0, Z / 60.0, 4, seed=6)
    calm = np.zeros((N, N))
    for key, rad in (("start_beach", 260), ("morgengrau", 230), ("moosfell", 180), ("knochenbrecher", 160), ("fischerkap", 120)):
        p0 = POIS[key]
        calm = np.maximum(calm, 1 - smoothstep(rad * 0.6, rad, np.sqrt((X - p0["x"]) ** 2 + (Z - p0["z"]) ** 2)))
    H += land * (hills * (26 + 10 * (1 - calm)) + detail * (4 + 1.5 * (1 - calm)))
    # ---- core island features: warped Voronoi biome seeds
    core = island_id == 0
    seeds = [(2, -420, 200), (2, -330, 400), (2, 120, 420), (2, -40, 20),
             (3, -170, 160), (3, -260, -60), (3, -10, 260), (3, -90, -120), (3, 110, 140),
             (4, 340, 150), (4, 470, 320), (4, 210, 20), (4, 300, 380),
             (5, 360, -250), (5, 230, -140), (5, 470, -120),
             (6, 10, -430), (6, -130, -330), (6, 170, -410), (6, -20, -280), (6, -520, 20), (6, 560, 80),
             (6, 120, -230),
             (10, -310, -270), (10, -430, -140)]
    wx = X + fbm(X / 160.0, Z / 160.0, 4, seed=11) * 90
    wz = Z + fbm(X / 160.0, Z / 160.0, 4, seed=12) * 90
    best = np.full((N, N), 1e9)
    core_b = np.zeros((N, N), np.uint8)
    for bid, sx, sz in seeds:
        d = (wx - sx) ** 2 + (wz - sz) ** 2
        upd = d < best
        best = np.where(upd, d, best)
        core_b = np.where(upd, bid, core_b)
    core_b = np.where(core, core_b, 0)
    def bmask(b, sigma):
        return ndimage.gaussian_filter((core_b == b).astype(float), sigma)
    mmask = bmask(6, 18)
    smask = bmask(5, 14)
    gmask = bmask(2, 14)
    rid = ridged(X / 170.0, Z / 170.0, 6, seed=9)
    H += mmask * (rid * 210 + 30)
    H += gmask * 4.0
    fmask = bmask(3, 14)
    outcrop = np.clip(ridged(X / 90.0, Z / 90.0, 5, seed=14) - 0.55, 0, None) * 2.2
    H += (gmask + fmask) * outcrop * 38 * (1 - calm)
    # plateau Adlerhorst: flat top with cliff walls
    px, pz = POIS["adlerhorst"]["x"], POIS["adlerhorst"]["z"]
    pd = np.sqrt((X - px) ** 2 + (Z - pz) ** 2)
    pl = 1 - smoothstep(55, 68, pd)
    H = H * (1 - pl) + np.maximum(H, 205 + detail * 2) * pl
    # swamp lowland
    H = H * (1 - smask * 0.9) + smask * 0.9 * (1.0 + detail * 1.8 + hills * 1.2)
    # corrupted crater (rift)
    rx, rz = POIS["riss_narbenschlund"]["x"], POIS["riss_narbenschlund"]["z"]
    rd = np.sqrt((X - rx) ** 2 + (Z - rz) ** 2)
    crater = (1 - smoothstep(30, 120, rd)) * core
    rim = np.exp(-((rd - 110) / 28) ** 2) * core
    H = H - crater * 26 + rim * 18
    # forest lake (west-central)
    ld = np.sqrt(((X + 60) / 1.4) ** 2 + ((Z - 200) / 1.0) ** 2)
    lake = (1 - smoothstep(25, 70, ld)) * core
    H = H * (1 - lake) + lake * (-4 + detail * 1.0)
    # ---- satellites
    vx, vz = 720, -700
    vd = np.sqrt((X - vx) ** 2 + (Z - vz) ** 2)
    volcano = (island_id == 1)
    cone = np.clip(1 - vd / 230, 0, 1) ** 1.6 * 280
    craterv = (1 - smoothstep(18, 55, vd)) * 70
    H = np.where(volcano, np.maximum(H, H * 0.3 + cone - craterv + ridged(X / 60, Z / 60, 4, seed=21) * 14 * (cone > 20)), H)
    snowi = island_id == 2
    H = np.where(snowi, H + ridged(X / 140, Z / 140, 6, seed=31) * 260 * land, H)
    deserti = island_id == 3
    dunes = np.abs(np.sin((X * 0.6 + Z * 0.8) / 23 + fbm(X / 90, Z / 90, 3, seed=41) * 5)) * 9
    mesa = (smoothstep(0.25, 0.3, fbm(X / 120, Z / 120, 4, seed=43)) * 32)
    H = np.where(deserti, H * 0.5 + (dunes + mesa) * land + 6 * land, H)
    narbe = island_id == 4
    H = np.where(narbe, H + ridged(X / 70, Z / 70, 5, seed=51) * 40 * land, H)
    # flatten POIs
    for key, p in POIS.items():
        if "flatten" not in p:
            continue
        r = p["flatten"]
        d = np.sqrt((X - p["x"]) ** 2 + (Z - p["z"]) ** 2)
        w = 1 - smoothstep(r * 0.6, r, d)
        sel = d < r * 0.5
        target = float(np.median(H[sel])) if sel.any() else 5.0
        if p.get("kind") in ("village", "camp") and target < 3.0:
            target = 3.0
        p["y"] = target
        H = H * (1 - w) + target * w
    # beaches: compress near sea level to make sandy shelves
    shore = (H > -3) & (H < 4)
    H = np.where(shore, H * 0.7 + 0.3 * np.clip(H, -1, 2), H)
    H = ndimage.gaussian_filter(H, 0.7)
    # underwater temple area: plateau at -28
    tx, tz = POIS["versunkener_tempel"]["x"], POIS["versunkener_tempel"]["z"]
    td = np.sqrt((X - tx) ** 2 + (Z - tz) ** 2)
    tw = 1 - smoothstep(40, 70, td)
    H = H * (1 - tw) + (-28) * tw
    POIS["versunkener_tempel"]["y"] = -28
    # world border: deep
    border = smoothstep(EXT * 0.9, EXT, np.maximum(np.abs(X), np.abs(Z)))
    H = H * (1 - border) + (-90) * border
    for key, p in POIS.items():
        if "y" not in p:
            p["y"] = float(sample(H, p["x"], p["z"]))

    # ------------------------------------------------------------------ biomes
    slope = slope_deg(H)
    B = np.zeros((N, N), np.uint8)
    # ids: 0 sea,1 coast,2 grass,3 forest,4 jungle,5 swamp,6 mountain,7 snow,8 volcano,9 desert,10 corrupted
    fnoise = fbm(X / 150, Z / 150, 4, seed=61)
    B[:] = 0
    landm = H > -0.5
    B[landm] = 2
    B[landm & core] = core_b[landm & core]
    corr = core & ((1 - smoothstep(120, 240, rd)) > 0.3)
    B[landm & corr] = 10
    B[landm & (island_id == 1)] = 8
    B[landm & (island_id == 2)] = 7
    B[landm & (island_id == 3)] = 9
    B[landm & (island_id == 4)] = 10
    B[landm & (H < 2.2) & ~((B == 5) | (B == 10))] = 1
    B[landm & (H > 165) & (island_id == 0)] = 6
    B[landm & (H > 140) & (island_id == 2)] = 7
    # oasis greenery
    ox, oz = POIS["oase"]["x"], POIS["oase"]["z"]
    B[landm & (np.sqrt((X - ox) ** 2 + (Z - oz) ** 2) < 55)] = 2
    # ------------------------------------------------------------------ splats (8 layers)
    # 0 grass,1 dirt,2 rock,3 sand,4 mud,5 snow,6 ash,7 corrupt
    W = np.zeros((N, N, 8))
    n1 = fbm(X / 40, Z / 40, 4, seed=71) * 0.5 + 0.5
    n2 = fbm(X / 18, Z / 18, 3, seed=72) * 0.5 + 0.5
    W[..., 0] += (B == 2) * (0.75 + 0.25 * n1)
    W[..., 1] += (B == 2) * (0.25 * (1 - n1)) + (B == 3) * (0.6 + 0.3 * n2) + (B == 4) * 0.35
    W[..., 0] += (B == 3) * (0.4 * n1) + (B == 4) * (0.65 * n2 + 0.2)
    W[..., 4] += (B == 5) * (0.7 + 0.3 * n1) + (B == 4) * 0.15 * (1 - n2)
    W[..., 0] += (B == 5) * 0.35 * n2
    W[..., 3] += (B == 1) * 1.0 + (B == 9) * (0.85 + 0.15 * n1) + (B == 0) * 1.0
    W[..., 2] += (B == 6) * (0.7 + 0.3 * n2) + (B == 9) * 0.15
    W[..., 1] += (B == 6) * 0.3 * n1
    W[..., 5] += (B == 7) * (0.8 + 0.2 * n1)
    W[..., 2] += (B == 7) * 0.2
    W[..., 6] += (B == 8) * (0.7 + 0.3 * n1)
    W[..., 2] += (B == 8) * 0.3
    W[..., 7] += (B == 10) * (0.7 + 0.3 * n2)
    W[..., 6] += (B == 10) * 0.3 * n1
    # slopes -> rock
    rockw = smoothstep(30, 42, slope)
    W = W * (1 - rockw[..., None])
    W[..., 2] += rockw
    # underwater -> sand/mud by depth
    deep = H < -0.5
    W[deep] = 0
    W[deep, 3] = 1.0
    W[deep & (H < -20), 3] = 0.4
    W[deep & (H < -20), 2] = 0.6
    W /= np.maximum(W.sum(-1, keepdims=True), 1e-5)
    s0 = (W[..., 0:4] * 255).astype(np.uint8)
    s1 = (W[..., 4:8] * 255).astype(np.uint8)
    Image.fromarray(s0[:-1, :-1], "RGBA").save(os.path.join(OUT, "splat0.png"))
    Image.fromarray(s1[:-1, :-1], "RGBA").save(os.path.join(OUT, "splat1.png"))
    Image.fromarray(B[:-1:2, :-1:2]).save(os.path.join(OUT, "biome.png"))
    H.astype(np.float32).tofile(os.path.join(OUT, "height.f32"))
    # ------------------------------------------------------------------ vegetation
    veg = vegetation(H, B, slope, X, Z)
    with open(os.path.join(OUT, "veg.bin"), "wb") as f:
        f.write(np.asarray(veg, np.float32).tobytes())
    # ------------------------------------------------------------------ resources (harvestable special nodes)
    res = resources(H, B, slope)
    # ------------------------------------------------------------------ map image
    map_image(H, B)
    regions = REGIONS
    meta = dict(size=N, extent=EXT, cell=CELL, sea_level=SEA, pois=POIS, islands=[dict(name=n, x=cx, z=cz, r=r, kind=k) for (n, cx, cz, r, b, k) in ISLANDS],
                biome_names=["Meer", "Küste", "Grasland", "Wald", "Dschungel", "Sumpf", "Gebirge", "Schneegebirge", "Vulkan", "Wüste", "Verderbnis"],
                vegetation_types=VEG_TYPES, resources=res, regions=regions)
    with open(os.path.join(OUT, "world.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)
    print("height range", H.min(), H.max(), "veg", len(veg), "res", len(res))


def sample(H, x, z):
    fx = (x + EXT) / CELL
    fz = (z + EXT) / CELL
    ix = int(np.clip(fx, 0, N - 2))
    iz = int(np.clip(fz, 0, N - 2))
    tx = fx - ix
    tz = fz - iz
    a = H[iz, ix] * (1 - tx) + H[iz, ix + 1] * tx
    b = H[iz + 1, ix] * (1 - tx) + H[iz + 1, ix + 1] * tx
    return a * (1 - tz) + b * tz


def slope_deg(H):
    gz, gx = np.gradient(H, CELL)
    return np.degrees(np.arctan(np.sqrt(gx * gx + gz * gz)))


VEG_TYPES = ["tree_conifer", "tree_broad", "tree_palm", "tree_jungle", "tree_swamp", "tree_dead", "bush",
             "fern", "rock_small", "rock_large", "cactus", "berry_bush", "reed", "crystal_corrupt",
             "tree_broad_b", "tree_broad_c", "tree_conifer_b", "tree_conifer_c", "rock_medium", "rock_small_b",
             "rock_spire", "boulder", "log", "stump"]

# density per biome per type (instances per 100x100 m)
DENS = {
    2: dict(tree_broad=16, tree_broad_b=11, tree_broad_c=8, tree_conifer_c=4, bush=55, rock_small=14, rock_small_b=12, rock_medium=5,
            rock_large=1.6, boulder=0.35, berry_bush=6, fern=10, log=1.5, stump=2.5),
    3: dict(tree_conifer=100, tree_conifer_b=45, tree_conifer_c=40, tree_broad=60, tree_broad_b=25, tree_broad_c=30,
            bush=80, fern=150, rock_small=14, rock_small_b=10, rock_medium=6, rock_large=2.2, boulder=0.4,
            berry_bush=9, log=9, stump=8),
    4: dict(tree_jungle=70, tree_palm=30, tree_broad_b=10, fern=230, bush=90, rock_small=8, rock_medium=4,
            berry_bush=10, log=7, stump=3),
    5: dict(tree_swamp=60, tree_dead=12, reed=200, bush=30, fern=60, log=10, stump=8, rock_small_b=6),
    1: dict(tree_palm=18, rock_small=10, rock_small_b=10, rock_medium=3, reed=10, log=1.2),
    6: dict(tree_conifer=18, tree_conifer_c=14, rock_small=40, rock_small_b=30, rock_medium=16, rock_large=8,
            rock_spire=2.0, boulder=1.4, bush=10, stump=2),
    7: dict(tree_conifer=16, tree_conifer_b=6, rock_small=18, rock_medium=8, rock_large=5, rock_spire=1.5, boulder=1.0),
    8: dict(tree_dead=10, rock_small=22, rock_medium=10, rock_large=7, rock_spire=2.5, boulder=1.2),
    9: dict(cactus=10, rock_small=14, rock_medium=6, rock_large=3.5, rock_spire=1.8, boulder=0.8, tree_palm=0.8),
    10: dict(tree_dead=28, crystal_corrupt=10, rock_small=16, rock_medium=6, rock_large=3, rock_spire=1.5, stump=4),
}


def vegetation(H, B, slope, X, Z):
    out = []
    vrng = np.random.default_rng(777)
    area = (2 * EXT) ** 2
    clump = fbm(X / 70, Z / 70, 3, seed=88) * 0.5 + 0.5
    for bid, types in DENS.items():
        mask = (B == bid)
        frac = mask.mean()
        for tname, dens in types.items():
            tid = VEG_TYPES.index(tname)
            count = int(dens * area * frac / 10000.0)
            if count <= 0:
                continue
            cz_, cx_ = np.nonzero(mask)
            pick = vrng.integers(0, len(cx_), int(count * 6) + 1)
            xs = -EXT + (cx_[pick] + vrng.random(len(pick))) * CELL
            zs = -EXT + (cz_[pick] + vrng.random(len(pick))) * CELL
            ix = np.clip(((xs + EXT) / CELL).astype(int), 0, N - 1)
            iz = np.clip(((zs + EXT) / CELL).astype(int), 0, N - 1)
            ok = (B[iz, ix] == bid) & (slope[iz, ix] < (28 if tname.startswith("tree") or tname in ("log", "stump") else 46)) & (H[iz, ix] > 0.4)
            if tname == "reed":
                ok = (B[iz, ix] == bid) & (H[iz, ix] > -0.6) & (H[iz, ix] < 1.6)
            if tname.startswith("tree") or tname in ("fern", "bush", "log", "stump"):
                ok &= vrng.random(len(xs)) < (0.2 + 0.8 * clump[iz, ix])
            if tname.startswith("rock") or tname == "boulder":
                ok &= vrng.random(len(xs)) < (0.35 + 0.65 * (1 - clump[iz, ix]))
            # keep villages / pois clear
            for p in POIS.values():
                r = p.get("flatten", 0)
                if r:
                    ok &= (xs - p["x"]) ** 2 + (zs - p["z"]) ** 2 > (r * 0.9) ** 2
            xs, zs = xs[ok][:count], zs[ok][:count]
            for x, z in zip(xs, zs):
                y = sample(H, x, z)
                sc = vrng.uniform(0.75, 1.3)
                if tname == "tree_jungle":
                    sc = vrng.uniform(0.9, 1.6)
                out.append((tid, x, y, z, vrng.uniform(0, math.tau), sc))
    return out


def resources(H, B, slope):
    rr = np.random.default_rng(999)
    out = []
    spec = [("ore_metal", (6, 7, 8), 160), ("ore_obsidian", (8,), 40), ("flint", (2, 3, 6), 80),
            ("crystal", (7, 6), 40), ("rift_crystal", (10,), 30), ("salt", (1, 9), 30), ("clay", (5, 1), 40),
            ("sulfur", (8, 9), 30), ("herb_patch", (3, 4, 5), 120), ("mushroom", (3, 5), 80)]
    for name, biomes, count in spec:
        n = 0
        tries = 0
        while n < count and tries < count * 200:
            tries += 1
            x, z = rr.uniform(-EXT * 0.95, EXT * 0.95, 2)
            ix = int((x + EXT) / CELL)
            iz = int((z + EXT) / CELL)
            if B[iz, ix] not in biomes or H[iz, ix] < 0.5:
                continue
            out.append(dict(type=name, x=round(float(x), 2), y=round(float(sample(H, x, z)), 2), z=round(float(z), 2)))
            n += 1
    return out


REGIONS = [
    dict(id="suedstrand", name="Treibgutstrand", x=60, z=380, r=170, levels=[1, 4],
         spawns=dict(compy=3, gallimimus=3, parasaurolophus=1, ichthyosaurus=1)),
    dict(id="morgengrauwald", name="Morgengrauwald", x=-150, z=230, r=220, levels=[2, 8],
         spawns=dict(raptor=3, parasaurolophus=3, compy=2, direwolf=1, pachycephalosaurus=1)),
    dict(id="knochenebene", name="Knochenebene", x=-400, z=200, r=240, levels=[5, 14],
         spawns=dict(triceratops=3, gallimimus=3, carnotaurus=1, pachycephalosaurus=2, stegosaurus=1)),
    dict(id="westwald", name="Flüsterwald", x=-250, z=-60, r=200, levels=[6, 14],
         spawns=dict(direwolf=2, raptor=2, atrociraptor=2, stegosaurus=1, smilodon=1)),
    dict(id="dschungel", name="Smaragddschungel", x=360, z=150, r=230, levels=[6, 16],
         spawns=dict(dilophosaurus=3, raptor=2, atrociraptor=2, parasaurolophus=2, titanoboa=1, compy=2)),
    dict(id="sumpf", name="Moorkessel", x=340, z=-260, r=220, levels=[10, 22],
         spawns=dict(sarcosuchus=2, spinosaurus=1, dilophosaurus=2, stegosaurus=1, titanoboa=1)),
    dict(id="nordgrat", name="Nordgrat", x=0, z=-420, r=260, levels=[12, 26],
         spawns=dict(argentavis=2, pteranodon=3, ankylosaurus=2, smilodon=1, trex=1)),
    dict(id="narbenschlund", name="Narbenschlund", x=-300, z=-270, r=200, levels=[14, 28],
         spawns=dict(hellhound=3, shadowstalker=1, riftspider=1)),
    dict(id="aschenkamm", name="Aschenkamm", x=720, z=-700, r=280, levels=[22, 40],
         spawns=dict(wyvern=2, carnotaurus=2, ankylosaurus=1, hellhound=1)),
    dict(id="weisszahn", name="Weißzahn-Gebirge", x=-730, z=-690, r=300, levels=[18, 36],
         spawns=dict(mammoth=3, direwolf=3, smilodon=2, argentavis=1)),
    dict(id="glutsand", name="Glutsand", x=710, z=660, r=300, levels=[16, 32],
         spawns=dict(ankylosaurus=2, carnotaurus=2, brontosaurus=2, gallimimus=2, titanoboa=1)),
    dict(id="narbe", name="Die Narbe", x=-700, z=690, r=230, levels=[30, 45],
         spawns=dict(bonewyrm=1, riftspider=2, shadowstalker=2, hellhound=2)),
    dict(id="kuestenmeer", name="Küstenmeer", x=0, z=0, r=900, levels=[3, 20], water=True,
         spawns=dict(ichthyosaurus=3, plesiosaurus=1, megalodon=1)),
    dict(id="tiefsee", name="Tiefsee", x=0, z=0, r=1400, levels=[20, 45], water=True, deep=True,
         spawns=dict(mosasaurus=1, megalodon=2)),
]


def map_image(H, B):
    cols = np.array([[30, 52, 70], [190, 175, 130], [96, 120, 62], [52, 82, 44], [40, 92, 46], [70, 76, 46],
                     [120, 112, 100], [225, 230, 236], [70, 52, 48], [205, 170, 110], [92, 30, 40]], float)
    img = cols[B]
    deep = np.clip(-H / 70, 0, 1)
    sea = H < 0
    img[sea] = np.array([48, 80, 98]) * (1 - deep[sea, None]) + np.array([14, 26, 40]) * deep[sea, None]
    gz, gx = np.gradient(H, CELL)
    shade = np.clip(0.75 + (-gx * 0.6 - gz * 0.6) * 0.7, 0.45, 1.3)
    img[~sea] *= shade[~sea, None]
    # contour lines
    cont = (np.abs((H % 40) - 20) > 19.2) & (~sea)
    img[cont] *= 0.8
    # parchment tint
    img = img * 0.82 + np.array([60, 48, 30]) * 0.18
    im = Image.fromarray(np.clip(img[:-1, :-1], 0, 255).astype(np.uint8))
    im.save(os.path.join(OUT, "map.png"))


if __name__ == "__main__":
    build()
