"""Prüft, ob angesetzte Körperteile (Hörner, Platten, Zähne …) im Körper versinken oder schweben.
Aufruf: python3 tools/check_parts.py"""
import json, sys, numpy as np
import os
os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'assetgen'))
sys.path.insert(0, '.')
from gen_creatures import SPECIES
sp = json.load(open('../../data/species.json'))
def load_part(pid):
    m = json.load(open(f'../../assets/parts/{pid}.json')); b = open(f'../../assets/parts/{pid}.bin','rb').read()
    pts = []
    for s in m['surfaces']:
        if s['vertex_count'] == 0: continue
        o, n = s['position']; pts.append(np.frombuffer(b[o:o+n], dtype=np.float32).reshape(-1, 3))
    return np.concatenate(pts).astype(float)
def basis(n):
    n = n / np.linalg.norm(n); F = np.array([0, 0, -1.0])
    if abs(n @ F) < 0.98:
        x = np.cross(F, n); x /= np.linalg.norm(x); z = np.cross(x, n); z /= np.linalg.norm(z)
        return np.stack([x, n, z], 1)
    return np.eye(3)
for sid, d in sp.items():
    parts = d.get('parts', [])
    if not parts: continue
    rig = SPECIES[d['rig']]()
    meta = json.load(open(f"../../assets/creatures/{d['rig']}.json"))
    for p in parts:
        so = meta['sockets'].get(p['socket'])
        if so is None: print(sid, p['id'], 'SOCKET FEHLT'); continue
        v = load_part(p['id']) * so['scale'] * p.get('size', 1.0)
        w = v @ basis(np.array(so['normal'])).T + np.array(so['pos'])
        sdf = rig.eval_sdf(w, detail=False)
        L = np.linalg.norm(v, axis=1).max()
        deep = (sdf < -0.15 * L).mean()
        float_ = sdf.min() > 0.02 * L
        print(f"{sid:20s} {p['id']:14s} tief_im_koerper={deep:5.1%} schwebt={float_}")
