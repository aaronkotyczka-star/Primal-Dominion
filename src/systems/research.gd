class_name Research
extends RefCounted
## Research book: availability by source (start, quest, teacher, investigate, ruin), costs, completion.

static func source_met(id: String) -> bool:
	var r := DB.research(id)
	var src: String = r.get("source", "start")
	if src == "start":
		return true
	var known: Array = GameState.state["research"]["known_sources"]
	if id in known:
		return true
	if src.begins_with("quest:"):
		var q := src.substr(6)
		return GameState.state["quests"].has(q)
	if src.begins_with("investigate:"):
		var sp := src.substr(12)
		var lx: Dictionary = GameState.state["lexicon"].get(sp, {})
		return lx.get("investigated", false) or lx.get("tamed", false)
	if src.begins_with("ruin:"):
		return src.substr(5) in GameState.state["discovered"]
	return false


static func source_hint(id: String) -> String:
	var src: String = DB.research(id).get("source", "start")
	if src.begins_with("teacher:"):
		return "Lehrmeister: " + DB.npc(src.substr(8)).get("name", src)
	if src.begins_with("quest:"):
		return "Durch eine Quest"
	if src.begins_with("investigate:"):
		return "Untersuche einen %s" % DB.species(src.substr(12)).get("name", src)
	if src.begins_with("ruin:"):
		return "Finde einen besonderen Ort"
	return ""


static func status(id: String) -> String:
	## done, available, locked
	if GameState.has_research(id):
		return "done"
	var r := DB.research(id)
	for req in r.get("req", []):
		if not GameState.has_research(req):
			return "locked"
	if not source_met(id):
		return "locked"
	return "available"


static func can_research(id: String, at_table: bool) -> Dictionary:
	if status(id) != "available":
		return {"ok": false, "why": "Noch nicht verfügbar."}
	var r := DB.research(id)
	if not at_table:
		return {"ok": false, "why": "Forschung benötigt einen Forschungstisch."}
	var p := GameState.player()
	if int(p["research_points"]) < int(r["cost"]):
		return {"ok": false, "why": "%d Forschungspunkte nötig." % r["cost"]}
	for it in r.get("items", {}):
		if Inventory.count(p["inventory"], it) < int(r["items"][it]):
			return {"ok": false, "why": "Benötigt %d× %s." % [r["items"][it], DB.item_name(it)]}
	return {"ok": true}


static func complete(id: String, free: bool = false) -> void:
	if GameState.has_research(id):
		return
	var r := DB.research(id)
	var p := GameState.player()
	if not free:
		p["research_points"] = int(p["research_points"]) - int(r["cost"])
		for it in r.get("items", {}):
			Inventory.remove(p["inventory"], it, int(r["items"][it]))
	GameState.state["research"]["done"].append(id)
	EventBus.research_completed.emit(id)
	EventBus.notify.emit("Forschung abgeschlossen: " + r.get("name", id), "good")
	GameState.add_xp(20 + int(r.get("cost", 0)) * 4, "research")


static func unlock_source(id: String) -> void:
	var known: Array = GameState.state["research"]["known_sources"]
	if not id in known:
		known.append(id)


static func add_points(n: int) -> void:
	var p := GameState.player()
	var mult := 1.0 + 0.25 * GameState.skill_rank("craft_research")
	p["research_points"] = int(p["research_points"]) + int(round(n * mult))


static func building_unlocked(bid: String) -> bool:
	var b := DB.building(bid)
	var req = b.get("research", null)
	return req == null or GameState.has_research(req)


static func recipe_unlocked(rid: String) -> bool:
	var r := DB.recipe(rid)
	var req = r.get("research", null)
	return req == null or GameState.has_research(req)
