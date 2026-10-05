class_name Inventory
extends RefCounted
## Inventory helpers operating on plain arrays of stacks: {id, n, q, d}
## q = quality (1.0 = normal), d = custom data (crafted stats, genes, names).

const SORT_ORDER := ["weapon", "armor", "ammo", "tool", "saddle", "consumable", "food", "essence", "rune", "material", "trap", "special", "quest"]


static func _stackable(st: Dictionary, id: String, q: float, d: Dictionary) -> bool:
	return st["id"] == id and absf(float(st.get("q", 1.0)) - q) < 0.001 and (st.get("d", {}) as Dictionary).is_empty() and d.is_empty()


static func add(inv: Array, id: String, n: int = 1, q: float = 1.0, d: Dictionary = {}) -> int:
	if n <= 0:
		return 0
	var it := DB.item(id)
	var max_stack: int = int(it.get("stack", 50))
	var left := n
	if d.is_empty():
		for st in inv:
			if _stackable(st, id, q, d) and st["n"] < max_stack:
				var take := mini(left, max_stack - int(st["n"]))
				st["n"] += take
				left -= take
				if left <= 0:
					break
	while left > 0:
		var take := mini(left, max_stack)
		inv.append({"id": id, "n": take, "q": q, "d": d.duplicate(true)})
		left -= take
	return n


static func count(inv: Array, id: String) -> int:
	var c := 0
	for st in inv:
		if st["id"] == id:
			c += int(st["n"])
	return c


static func remove(inv: Array, id: String, n: int = 1) -> int:
	var left := n
	for i in range(inv.size() - 1, -1, -1):
		var st: Dictionary = inv[i]
		if st["id"] != id:
			continue
		var take := mini(left, int(st["n"]))
		st["n"] -= take
		left -= take
		if st["n"] <= 0:
			inv.remove_at(i)
		if left <= 0:
			break
	return n - left


static func remove_at(inv: Array, idx: int, n: int = 1) -> Dictionary:
	if idx < 0 or idx >= inv.size():
		return {}
	var st: Dictionary = inv[idx]
	var out := st.duplicate(true)
	out["n"] = mini(n, int(st["n"]))
	st["n"] -= out["n"]
	if st["n"] <= 0:
		inv.remove_at(idx)
	return out


static func weight(inv: Array) -> float:
	var w := 0.0
	for st in inv:
		w += float(DB.item(st["id"]).get("weight", 0.5)) * int(st["n"])
	return w


static func sort(inv: Array, mode: String = "cat") -> void:
	inv.sort_custom(func(a, b): return _less(a, b, mode))


static func _less(a: Dictionary, b: Dictionary, mode: String) -> bool:
	var ia := DB.item(a["id"])
	var ib := DB.item(b["id"])
	if mode == "name":
		return str(ia.get("name", a["id"])) < str(ib.get("name", b["id"]))
	if mode == "weight":
		return float(ia.get("weight", 0)) * a["n"] > float(ib.get("weight", 0)) * b["n"]
	if mode == "value":
		return float(ia.get("value", 0)) > float(ib.get("value", 0))
	var ca := SORT_ORDER.find(ia.get("cat", "special"))
	var cb := SORT_ORDER.find(ib.get("cat", "special"))
	if ca != cb:
		return ca < cb
	return str(ia.get("name", a["id"])) < str(ib.get("name", b["id"]))


static func display_name(st: Dictionary) -> String:
	var d: Dictionary = st.get("d", {})
	if d.has("name"):
		return d["name"]
	return DB.item_name(st["id"])


static func quality_label(q: float) -> String:
	if q >= 1.6:
		return "Meisterhaft"
	if q >= 1.35:
		return "Hervorragend"
	if q >= 1.15:
		return "Gut"
	if q >= 0.95:
		return "Gewöhnlich"
	return "Grob"


static func quality_color(q: float) -> Color:
	if q >= 1.6:
		return Color(1.0, 0.6, 0.15)
	if q >= 1.35:
		return Color(0.7, 0.45, 1.0)
	if q >= 1.15:
		return Color(0.35, 0.65, 1.0)
	if q >= 0.95:
		return Color(0.9, 0.9, 0.88)
	return Color(0.6, 0.6, 0.58)


## Weapon/armor stats of a stack, combining base template and crafted data
static func stats_of(st: Dictionary) -> Dictionary:
	var base: Dictionary = DB.item(st["id"]).get("stats", {}).duplicate()
	var d: Dictionary = st.get("d", {})
	if d.has("stats"):
		base.merge(d["stats"], true)
	var q := float(st.get("q", 1.0))
	for k in ["dmg", "armor", "torpor", "block", "spell_power"]:
		if base.has(k) and not d.has("stats"):
			base[k] = float(base[k]) * q
	return base


## Gather stacks from player inventory + nearby storages for crafting
static func pooled_count(inventories: Array, id: String) -> int:
	var c := 0
	for inv in inventories:
		c += count(inv, id)
	return c


static func pooled_remove(inventories: Array, id: String, n: int) -> void:
	var left := n
	for inv in inventories:
		if left <= 0:
			break
		left -= remove(inv, id, left)
