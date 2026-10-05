class_name Crafting
extends RefCounted
## Fixed and modular crafting. Pulls materials from the player inventory and nearby storage.

const STATION_NAMES := {"hand": "Hand", "campfire": "Lagerfeuer", "workbench": "Werkbank", "forge": "Schmiede",
	"alchemy": "Alchemietisch", "kitchen": "Kochstelle"}


static func pools(storages: Array) -> Array:
	var out := [GameState.player()["inventory"]]
	for s in storages:
		out.append(s)
	return out


static func missing(rid: String, pool: Array, count: int = 1) -> Dictionary:
	var r := DB.recipe(rid)
	var out := {}
	for it in r.get("inputs", {}):
		var need := int(r["inputs"][it]) * count
		var have := Inventory.pooled_count(pool, it)
		if have < need:
			out[it] = need - have
	return out


static func can_craft(rid: String, pool: Array, stations: Array, count: int = 1) -> Dictionary:
	var r := DB.recipe(rid)
	if r.is_empty():
		return {"ok": false, "why": "Unbekanntes Rezept."}
	if not Research.recipe_unlocked(rid):
		return {"ok": false, "why": "Forschung „%s“ nötig." % DB.research(r["research"]).get("name", r["research"])}
	var st: String = r.get("station", "hand")
	if st != "hand" and not st in stations:
		return {"ok": false, "why": "Benötigt: %s." % STATION_NAMES.get(st, st)}
	if r["kind"] == "fixed":
		var m := missing(rid, pool, count)
		if not m.is_empty():
			var parts := []
			for k in m:
				parts.append("%d× %s" % [m[k], DB.item_name(k)])
			return {"ok": false, "why": "Fehlt: " + ", ".join(parts)}
	return {"ok": true}


static func craft_fixed(rid: String, pool: Array, stations: Array, count: int = 1) -> bool:
	var chk := can_craft(rid, pool, stations, count)
	if not chk["ok"]:
		EventBus.notify.emit(chk["why"], "warn")
		return false
	var r := DB.recipe(rid)
	var save := 0.1 * GameState.skill_rank("craft_efficiency")
	for it in r["inputs"]:
		var n := int(r["inputs"][it]) * count
		if randf() < save:
			n = int(n * 0.5)
		Inventory.pooled_remove(pool, it, n)
	var out_id: String = r["output"]
	var out_n := int(r.get("count", 1)) * count
	if DB.item(out_id).get("cat", "") in ["consumable"] and GameState.skill_rank("surv_alchemy") >= 2:
		out_n += count
	var q := 1.0
	if DB.item(out_id).get("cat", "") in ["weapon", "armor", "tool", "saddle"]:
		q = roll_quality(1.0)
		for i in count:
			Inventory.add(GameState.player()["inventory"], out_id, 1, q)
	else:
		Inventory.add(GameState.player()["inventory"], out_id, out_n, q)
	GameState.state["stats"]["crafted"] += count
	GameState.add_xp(float(r.get("xp", 4)) * count, "craft")
	EventBus.crafted.emit(out_id, out_n)
	EventBus.inventory_changed.emit()
	Audio.play_ui("craft")
	return true


static func roll_quality(tier_bonus: float) -> float:
	return clampf((1.0 + 0.08 * GameState.skill_rank("craft_quality")) * tier_bonus * randf_range(0.93, 1.1), 0.7, 2.0)


static func modular_options(rid: String, pool: Array) -> Dictionary:
	## slot -> list of material item ids available in sufficient amount
	var r := DB.recipe(rid)
	var out := {}
	for slot in r.get("slots", {}):
		var sd: Dictionary = r["slots"][slot]
		var opts := []
		for id in DB.t("items"):
			var it: Dictionary = DB.item(id)
			if it.has("mat") and sd["tag"] in it["mat"].get("tags", []):
				if Inventory.pooled_count(pool, id) >= int(sd["n"]):
					opts.append(id)
		if sd.get("optional", false):
			opts.push_front("")
		out[slot] = opts
	# runes (optional)
	var runes := [""]
	for id in DB.t("items"):
		if DB.item(id).get("cat", "") == "rune" and Inventory.pooled_count(pool, id) > 0:
			runes.append(id)
	out["rune"] = runes
	return out


static func modular_preview(rid: String, choice: Dictionary) -> Dictionary:
	var r := DB.recipe(rid)
	var base: Dictionary = DB.item(r["base"])
	var stats: Dictionary = base.get("stats", {}).duplicate()
	var weights := {"head": 0.6, "shaft": 0.25, "binding": 0.15, "focus": 0.5}
	var mult := 0.0
	var wsum := 0.0
	var tier := 0.0
	var n := 0
	for slot in r["slots"]:
		var mid: String = choice.get(slot, "")
		if mid == "":
			continue
		var mat: Dictionary = DB.item(mid).get("mat", {})
		var w: float = weights.get(slot, 0.2)
		mult += float(mat.get("dmg", 1.0)) * w
		wsum += w
		tier += float(mat.get("tier", 1))
		n += 1
	mult = mult / maxf(wsum, 0.01) if wsum > 0 else 1.0
	stats["dmg"] = float(stats.get("dmg", 10.0)) * mult
	if stats.has("torpor") and float(stats["torpor"]) > 0:
		stats["torpor"] = float(stats["torpor"]) * mult
	if stats.has("spell_power") and choice.get("focus", "") == "crystal":
		stats["spell_power"] = 1.4
		stats["bolt"] = 18.0
	if r["base"] in ["axe_stone", "pick_stone"]:
		for k in ["harvest_wood", "harvest_stone", "harvest_ore"]:
			if stats.has(k):
				stats[k] = float(stats[k]) * lerpf(1.0, mult, 0.7)
	var head: String = choice.get("head", choice.get("shaft", ""))
	var label: String = DB.item_name(head) if head != "" else ""
	var name: String = "%s-%s" % [label, r["name"]] if label != "" else r["name"]
	var rune: String = choice.get("rune", "")
	if rune != "":
		name = DB.element(DB.item(rune).get("element", "")).get("name", "") + " " + name
	return {"stats": stats, "name": name, "tier_bonus": 1.0 + 0.05 * maxf(0.0, tier / maxf(n, 1) - 1.0)}


static func craft_modular(rid: String, choice: Dictionary, pool: Array, stations: Array) -> bool:
	var chk := can_craft(rid, pool, stations)
	if not chk["ok"]:
		EventBus.notify.emit(chk["why"], "warn")
		return false
	var r := DB.recipe(rid)
	for slot in r["slots"]:
		var sd: Dictionary = r["slots"][slot]
		var mid: String = choice.get(slot, "")
		if mid == "":
			if not sd.get("optional", false):
				EventBus.notify.emit("Material für „%s“ fehlt." % slot, "warn")
				return false
			continue
		if Inventory.pooled_count(pool, mid) < int(sd["n"]):
			EventBus.notify.emit("Nicht genug %s." % DB.item_name(mid), "warn")
			return false
	var rune: String = choice.get("rune", "")
	if rune != "" and Inventory.pooled_count(pool, rune) < 1:
		return false
	var prev := modular_preview(rid, choice)
	for slot in r["slots"]:
		var mid2: String = choice.get(slot, "")
		if mid2 != "":
			Inventory.pooled_remove(pool, mid2, int(r["slots"][slot]["n"]))
	if rune != "":
		Inventory.pooled_remove(pool, rune, 1)
	var q := roll_quality(prev["tier_bonus"])
	var stats: Dictionary = prev["stats"]
	for k in ["dmg", "torpor"]:
		if stats.has(k):
			stats[k] = float(stats[k]) * q
	if rune != "":
		stats["element"] = DB.item(rune).get("element", "")
	var d := {"name": prev["name"], "stats": stats, "head": choice.get("head", ""), "shaft": choice.get("shaft", ""), "binding": choice.get("binding", ""), "focus": choice.get("focus", "")}
	if rune != "":
		d["rune"] = rune
	Inventory.add(GameState.player()["inventory"], r["base"], 1, q, d)
	GameState.state["stats"]["crafted"] += 1
	GameState.add_xp(float(r.get("xp", 8)), "craft")
	EventBus.crafted.emit(r["base"], 1)
	EventBus.inventory_changed.emit()
	Audio.play_ui("craft")
	EventBus.notify.emit("Hergestellt: %s (%s)" % [prev["name"], Inventory.quality_label(q)], "good")
	return true


static func save_design(name: String, rid: String, choice: Dictionary) -> void:
	GameState.state["designs"].append({"name": name, "recipe": rid, "choice": choice.duplicate()})
	EventBus.notify.emit("Entwurf gespeichert: " + name, "info")


static func suggestions(pool: Array, stations: Array) -> Array:
	## craftable recipes right now, most useful first
	var out := []
	for rid in DB.t("recipes"):
		var r := DB.recipe(rid)
		if r["kind"] != "fixed":
			continue
		if can_craft(rid, pool, stations)["ok"]:
			var have := Inventory.pooled_count(pool, r["output"])
			out.append({"id": rid, "score": -have + (5 if DB.item(r["output"]).get("cat", "") in ["weapon", "armor", "saddle"] else 0)})
	out.sort_custom(func(a, b): return a["score"] > b["score"])
	return out.map(func(x): return x["id"])
