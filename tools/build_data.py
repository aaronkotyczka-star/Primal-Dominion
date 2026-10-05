"""Builds data/*.json from tools/data_src/*.py (source of truth for game data)."""
import json, os, sys, importlib.util
ROOT = os.path.join(os.path.dirname(__file__), "..")
SRC = os.path.join(os.path.dirname(__file__), "data_src")

def load(name):
    spec = importlib.util.spec_from_file_location(name, os.path.join(SRC, name + ".py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m

def dump(name, obj):
    with open(os.path.join(ROOT, "data", name + ".json"), "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False, indent=1)

if __name__ == "__main__":
    for f in sorted(os.listdir(SRC)):
        if not f.endswith(".py"):
            continue
        m = load(f[:-3])
        exports = getattr(m, "EXPORT", None)
        if exports is None:
            exports = {k.lower(): getattr(m, k) for k in dir(m) if k.isupper() and isinstance(getattr(m, k), (dict, list)) and k not in ("EL_DE", "ELEMENTS_LIST", "ALL", "LAND")}
        for k, v in exports.items():
            dump(k, v)
            print("wrote", k)
