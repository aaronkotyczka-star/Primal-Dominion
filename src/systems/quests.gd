class_name Quests
extends Node
## Quest progression. Lives as a child of the World; listens to EventBus and re-evaluates objectives.

var _eval_t := 0.0


func _ready() -> void:
	EventBus.inventory_changed.connect(_dirty)
	EventBus.crafted.connect(func(id, n): _count("craft", id, n))
	EventBus.built.connect(func(kind, _p): _count("build", kind, 1))
	EventBus.creature_tamed.connect(func(uid): _count("tame", GameState.creature(uid).get("species", ""), 1))
	EventBus.creature_killed.connect(_on_kill)
	EventBus.creature_born.connect(_on_born)
	EventBus.research_completed.connect(func(_r): _dirty())
	EventBus.location_discovered.connect(func(_p): _dirty())
	EventBus.game_loaded.connect(_dirty)


func _dirty() -> void:
	_eval_t = 0.05


func _process(delta: float) -> void:
	if _eval_t > 0.0:
		_eval_t -= delta
		if _eval_t <= 0.0:
			evaluate_all()


static func q(qid: String) -> Dictionary:
	return GameState.state["quests"].get(qid, {})


static func is_active(qid: String) -> bool:
	return q(qid).get("state", "") == "active"


static func stage(qid: String) -> int:
	return int(q(qid).get("stage", -1))


static func start(qid: String) -> void:
	if GameState.state["quests"].has(qid):
		return
	var qd := DB.quest(qid)
	if qd.is_empty():
		return
	GameState.state["quests"][qid] = {"state": "active", "stage": 0, "counters": {}}
	for r in qd.get("on_start_research", []):
		Research.complete(r, true)
	EventBus.notify.emit("Neue Quest: " + qd["name"], "quest")
	Audio.play_ui("ui_quest")
	EventBus.quest_updated.emit(qid)


static func current_stage_def(qid: String) -> Dictionary:
	var qd := DB.quest(qid)
	var s := stage(qid)
	var stages: Array = qd.get("stages", [])
	if s < 0 or s >= stages.size():
		return {}
	return stages[s]


func _count(kind: String, what: String, n: int) -> void:
	for qid in GameState.state["quests"]:
		if not is_active(qid):
			continue
		# remember crafts over the whole quest so a stage switch in between does not lose them
		if kind == "craft":
			var seen: Dictionary = GameState.state["quests"][qid].get("crafted", {})
			seen[what] = int(seen.get(what, 0)) + n
			GameState.state["quests"][qid]["crafted"] = seen
		var sd := current_stage_def(qid)
		var objs: Array = sd.get("obj", [])
		for i in objs.size():
			var o: Dictionary = objs[i]
			if o["type"] != kind:
				continue
			var keys: String = o.get("item", o.get("what", o.get("species", "any")))
			if keys == "any" or what in keys.split("|"):
				var c: Dictionary = GameState.state["quests"][qid]["counters"]
				c[str(i)] = int(c.get(str(i), 0)) + n
	_dirty()


func _on_kill(species: String, by_player: bool, pos: Vector3, data: Dictionary) -> void:
	if not by_player:
		return
	for qid in GameState.state["quests"]:
		if not is_active(qid):
			continue
		var objs: Array = current_stage_def(qid).get("obj", [])
		for i in objs.size():
			var o: Dictionary = objs[i]
			if o["type"] != "kill":
				continue
			var tag: String = o.get("tag", "")
			if tag != species and tag != data.get("tag", "") and tag != data.get("boss", ""):
				continue
			if o.has("at") and pos.distance_to(WorldData.poi_pos(o["at"])) > 90.0:
				continue
			var c: Dictionary = GameState.state["quests"][qid]["counters"]
			c[str(i)] = int(c.get(str(i), 0)) + 1
	_dirty()


func _on_born(uid: int) -> void:
	var c := GameState.creature(uid)
	_count("hatch", "any", 1)
	if c.get("species", "") == "hybrid":
		_count("hybrid", "any", 1)


static func objective_progress(qid: String, i: int, o: Dictionary) -> Array:
	## returns [current, needed]
	var need := int(o.get("n", 1))
	var c: Dictionary = GameState.state["quests"][qid]["counters"]
	match o["type"]:
		"have":
			return [mini(Inventory.count(GameState.player()["inventory"], o["item"]), need), need]
		"build":
			var cnt := 0
			for b in GameState.state["buildings"]:
				if b["type"] in String(o["what"]).split("|"):
					cnt += 1
			return [mini(cnt, need), need]
		"craft":
			var made := int(c.get(str(i), 0))
			var seen2: Dictionary = GameState.state["quests"][qid].get("crafted", {})
			var tot := 0
			for it in String(o["item"]).split("|"):
				tot += int(seen2.get(it, 0))
			return [mini(maxi(made, tot), need), need]
		"visit":
			return [1 if o["poi"] in GameState.state["discovered"] else 0, 1]
		"research":
			return [1 if GameState.has_research(o["id"]) else 0, 1]
		"flag":
			return [1 if GameState.flag(o["flag"], false) else 0, 1]
		"talk", "deliver":
			return [int(c.get(str(i), 0)), 1]
		"tame":
			var owned := 0
			for cr in GameState.all_creatures():
				if cr.get("status", "") != "dead" and (o["species"] == "any" or cr.get("species", "") == o["species"]):
					owned += 1
			return [mini(maxi(int(c.get(str(i), 0)), owned), need), need]
		"hybrid":
			var hy := 0
			for cr in GameState.all_creatures():
				if cr.get("status", "") != "dead" and cr.get("species", "") == "hybrid":
					hy += 1
			return [mini(maxi(int(c.get(str(i), 0)), hy), need), need]
		_:
			return [mini(int(c.get(str(i), 0)), need), need]


static func objective_text(qid: String, i: int, o: Dictionary) -> String:
	var pr := objective_progress(qid, i, o)
	var label := ""
	match o["type"]:
		"have":
			label = "%s" % DB.item_name(o["item"])
		"build":
			label = "Baue: " + " / ".join(Array(String(o["what"]).split("|")).map(func(b): return DB.building(b).get("name", b)))
		"craft":
			label = "Stelle her: " + " / ".join(Array(String(o["item"]).split("|")).map(func(b): return DB.item_name(b)))
		"kill":
			var tag: String = o["tag"]
			label = "Besiege: " + DB.species(tag).get("name", DB.npc(tag).get("name", tag.capitalize()))
		"tame":
			label = "Zähme: " + ("beliebige Kreatur" if o["species"] == "any" else DB.species(o["species"]).get("name", o["species"]))
		"visit":
			label = "Erreiche: " + WorldData.poi(o["poi"]).get("name", o["poi"])
		"talk":
			label = "Sprich mit " + DB.npc(o["npc"]).get("name", o["npc"])
		"deliver":
			label = "Übergib %d× %s an %s" % [o["n"], DB.item_name(o["item"]), DB.npc(o["npc"]).get("name", o["npc"])]
		"research":
			label = "Erforsche: " + DB.research(o["id"]).get("name", o["id"])
		"hybrid":
			label = "Erschaffe einen Hybriden"
		"hatch":
			label = "Brüte ein Ei aus"
		"flag":
			label = "Aufgabe erfüllen"
	return "%s (%d/%d)" % [label, pr[0], pr[1]] if pr[1] > 1 or o["type"] in ["have", "kill"] else ("✔ " if pr[0] >= pr[1] else "• ") + label


func evaluate_all() -> void:
	var changed := true
	var guard := 0
	while changed and guard < 20:
		changed = false
		guard += 1
		for qid in GameState.state["quests"].keys():
			if not is_active(qid):
				continue
			var sd := current_stage_def(qid)
			if sd.is_empty():
				continue
			var done := true
			var objs: Array = sd.get("obj", [])
			for i in objs.size():
				var o: Dictionary = objs[i]
				if o["type"] in ["talk", "deliver"]:
					done = false
					continue
				var pr := objective_progress(qid, i, o)
				if pr[0] < pr[1]:
					done = false
			if done and not objs.is_empty():
				advance(qid)
				changed = true


static func advance(qid: String) -> void:
	if not is_active(qid):
		return
	var st: Dictionary = GameState.state["quests"][qid]
	var qd := DB.quest(qid)
	st["stage"] = int(st["stage"]) + 1
	st["counters"] = {}
	if int(st["stage"]) >= qd["stages"].size():
		complete(qid)
	else:
		EventBus.notify.emit("%s: %s" % [qd["name"], qd["stages"][st["stage"]]["text"]], "quest")
		Audio.play_ui("ui_open")
		EventBus.quest_updated.emit(qid)


static func complete(qid: String) -> void:
	var st: Dictionary = GameState.state["quests"][qid]
	st["state"] = "done"
	var qd := DB.quest(qid)
	var rw: Dictionary = qd.get("rewards", {})
	var lines := []
	if rw.has("xp"):
		GameState.add_xp(rw["xp"], "quest")
		lines.append("%d EP" % rw["xp"])
	if rw.has("amber"):
		GameState.add_amber(int(rw["amber"]))
		lines.append("%d Bernstein" % rw["amber"])
	for it in rw.get("items", []):
		Inventory.add(GameState.player()["inventory"], it[0], int(it[1]))
		lines.append("%d× %s" % [it[1], DB.item_name(it[0])])
	for r in rw.get("research", []):
		Research.unlock_source(r)
		Research.complete(r, true)
	if rw.has("research_points"):
		Research.add_points(int(rw["research_points"]))
		lines.append("%d Forschungspunkte" % rw["research_points"])
	if rw.has("skill_points"):
		GameState.player()["skill_points"] += int(rw["skill_points"])
		lines.append("%d Fähigkeitenpunkt" % rw["skill_points"])
	for r2 in rw.get("rep", []):
		GameState.change_rep(r2[0], int(r2[1]))
	for f in rw.get("flags", []):
		GameState.set_flag(f, true)
	EventBus.notify.emit("Quest abgeschlossen: %s%s" % [qd["name"], (" – " + ", ".join(lines)) if not lines.is_empty() else ""], "quest")
	Audio.play_ui("ui_levelup")
	EventBus.quest_completed.emit(qid)
	EventBus.inventory_changed.emit()
	for nq in qd.get("next", []):
		start(nq)


static func tracked() -> Array:
	## active quests, main first
	var out := []
	for qid in GameState.state["quests"]:
		if is_active(qid):
			out.append(qid)
	out.sort_custom(func(a, b): return int(DB.quest(a).get("main", false)) > int(DB.quest(b).get("main", false)))
	return out
