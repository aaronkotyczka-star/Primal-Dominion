class_name Dialogue
extends RefCounted
## Evaluates dialogue conditions and actions (tiny DSL from tools/data_src/story.py).

static func node(npc_id: String, node_id: String) -> Dictionary:
	return DB.get_entry("dialogues", npc_id).get(node_id, {})


static func options(npc_id: String, node_id: String) -> Array:
	var out := []
	for o in node(npc_id, node_id).get("options", []):
		if check(o.get("cond", "")):
			out.append(o)
	return out


static func check(cond: String) -> bool:
	if cond == "":
		return true
	for part in cond.split(";"):
		if not _check_one(part.strip_edges()):
			return false
	return true


static func _cmp(a: int, op: String, b: int) -> bool:
	match op:
		">=":
			return a >= b
		"<=":
			return a <= b
		"=":
			return a == b
		">":
			return a > b
		"<":
			return a < b
	return false


static func _split_op(s: String) -> Array:
	for op in [">=", "<=", "=", ">", "<"]:
		var i := s.find(op)
		if i >= 0:
			return [s.substr(0, i), op, s.substr(i + op.length())]
	return [s, "", ""]


static func _check_one(c: String) -> bool:
	var neg := c.begins_with("!")
	if neg:
		c = c.substr(1)
	var res := false
	var kind := c.get_slice(":", 0)
	var rest := c.substr(kind.length() + 1)
	match kind:
		"quest":
			var p := _split_op(rest)
			if p[1] == "":
				res = GameState.state["quests"].has(p[0])
			else:
				res = Quests.q(p[0]).get("state", "") == p[2]
		"stage":
			var p2 := _split_op(rest)
			res = Quests.is_active(p2[0]) and _cmp(Quests.stage(p2[0]), p2[1], int(p2[2]))
		"flag":
			var v = GameState.flag(rest, false)
			res = v != null and v != false and v != 0 and v != ""
		"rep":
			var p3 := _split_op(rest)
			res = _cmp(GameState.rep(p3[0]), p3[1], int(p3[2]))
		"item":
			var p4 := _split_op(rest)
			res = _cmp(Inventory.count(GameState.player()["inventory"], p4[0]), p4[1], int(p4[2]))
		"amber":
			res = GameState.amber() >= int(rest.trim_prefix(">=").trim_prefix("="))
		"research":
			res = GameState.has_research(rest)
		"demon_form":
			res = GameState.player()["demon"].get("in_form", false)
		"demon_unlocked":
			res = GameState.player()["demon"].get("unlocked", false)
		_:
			if c.begins_with("amber"):
				var p5 := _split_op(c)
				res = _cmp(GameState.amber(), p5[1], int(p5[2]))
	return not res if neg else res


## Runs actions; returns {"goto": node or "", "end": bool, "trade": bool, "teach": id}
static func run(npc_id: String, action: String) -> Dictionary:
	var out := {"goto": "", "end": false, "trade": false}
	if action == "":
		return out
	for part in action.split(";"):
		var a := part.strip_edges()
		var kind := a.get_slice(":", 0)
		var args := a.split(":")
		match kind:
			"start":
				Quests.start(args[1])
			"advance":
				if Quests.is_active(args[1]):
					Quests.advance(args[1])
			"complete":
				Quests.complete(args[1])
			"give":
				Inventory.add(GameState.player()["inventory"], args[1], int(args[2]))
				EventBus.notify.emit("Erhalten: %s× %s" % [args[2], DB.item_name(args[1])], "good")
				EventBus.inventory_changed.emit()
			"take":
				Inventory.remove(GameState.player()["inventory"], args[1], int(args[2]))
				EventBus.inventory_changed.emit()
			"amber":
				GameState.add_amber(int(args[1]))
			"rep":
				GameState.change_rep(args[1], int(args[2]))
			"flag":
				var kv := a.substr(5).split("=")
				GameState.set_flag(kv[0], kv[1] if kv.size() > 1 else true)
			"research":
				Research.unlock_source(args[1])
				Research.complete(args[1], true)
			"teach":
				_teach(npc_id, args[1])
			"path":
				GameState.add_path(args[1], int(args[2]))
			"xp":
				GameState.add_xp(int(args[1]))
			"respec":
				Skills.respec(false)
			"trade":
				out["trade"] = true
			"end":
				out["end"] = true
			"goto":
				out["goto"] = args[1]
	return out


static func _teach(npc_id: String, rid: String) -> void:
	if GameState.has_research(rid):
		EventBus.notify.emit("Das kennst du bereits.", "info")
		return
	var r := DB.research(rid)
	Research.unlock_source(rid)
	var cost := int(r.get("cost", 4)) * 10
	if GameState.amber() < cost:
		EventBus.notify.emit("Unterricht in „%s“ kostet %d Bernstein. Danach am Forschungstisch abschließen – oder hier sofort mit genug Bernstein." % [r.get("name", rid), cost], "warn")
		return
	GameState.add_amber(-cost)
	Research.complete(rid, true)


# ---------------------------------------------------------------- trading
static func price_buy(item_id: String, fid: String) -> int:
	var v := float(DB.item(item_id).get("value", 1))
	var rep := GameState.rep(fid)
	return maxi(1, int(round(v * 1.6 * (1.0 - clampf(rep, -50, 100) / 400.0))))


static func price_sell(item_id: String, fid: String) -> int:
	var v := float(DB.item(item_id).get("value", 1))
	var rep := GameState.rep(fid)
	return maxi(0, int(round(v * 0.45 * (1.0 + clampf(rep, -50, 100) / 400.0))))


static func buy(npc_id: String, item_id: String) -> bool:
	var fid: String = DB.npc(npc_id).get("faction", "")
	var price := price_buy(item_id, fid)
	if GameState.amber() < price:
		EventBus.notify.emit("Nicht genug Bernstein.", "warn")
		return false
	GameState.add_amber(-price)
	Inventory.add(GameState.player()["inventory"], item_id, 1)
	EventBus.inventory_changed.emit()
	Audio.play_ui("pickup")
	return true


static func sell(npc_id: String, idx: int) -> bool:
	var inv: Array = GameState.player()["inventory"]
	if idx < 0 or idx >= inv.size():
		return false
	var st: Dictionary = inv[idx]
	if DB.item(st["id"]).get("cat", "") == "quest":
		return false
	var fid: String = DB.npc(npc_id).get("faction", "")
	var price := price_sell(st["id"], fid)
	Inventory.remove_at(inv, idx, 1)
	GameState.add_amber(price)
	if fid != "":
		if randf() < 0.1:
			GameState.state["factions"][fid]["rep"] = mini(100, GameState.rep(fid) + 1)
	EventBus.inventory_changed.emit()
	Audio.play_ui("pickup")
	return true
