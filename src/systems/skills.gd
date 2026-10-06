class_name Skills
extends RefCounted
## Skill trees: learning, requirements, loadout (4 active slots), respec.

const LOADOUT_SIZE := 4


static func can_learn(id: String) -> Dictionary:
	var sk := DB.skill(id)
	var p := GameState.player()
	if sk.is_empty():
		return {"ok": false, "why": "Unbekannt"}
	var rank := GameState.skill_rank(id)
	if rank >= int(sk.get("max", 1)):
		return {"ok": false, "why": "Maximalrang erreicht."}
	if int(p["skill_points"]) <= 0:
		return {"ok": false, "why": "Keine Fähigkeitenpunkte."}
	if int(p["level"]) < int(sk.get("level", 1)):
		return {"ok": false, "why": "Benötigt Stufe %d." % sk["level"]}
	var req = sk.get("req", null)
	if req != null and GameState.skill_rank(req) <= 0:
		return {"ok": false, "why": "Benötigt „%s“." % DB.skill(req).get("name", req)}
	if sk.get("tree", "") == "elemental" and id == "elemental_affinity" and not GameState.flag("elemental_taught", false):
		return {"ok": false, "why": "Eine Lehrmeisterin muss dir die Elemente zeigen (Nixa)."}
	return {"ok": true}


static func learn(id: String) -> bool:
	var chk := can_learn(id)
	if not chk["ok"]:
		EventBus.notify.emit(chk["why"], "warn")
		return false
	var p := GameState.player()
	p["skills"][id] = GameState.skill_rank(id) + 1
	p["skill_points"] = int(p["skill_points"]) - 1
	var sk := DB.skill(id)
	if sk.get("kind", "") == "active":
		var lo: Array = p["loadout"]
		var free := lo.find("")
		if free >= 0:
			lo[free] = sk["ability"]
	EventBus.notify.emit("Gelernt: %s (Rang %d)" % [sk["name"], p["skills"][id]], "good")
	EventBus.hud_refresh.emit()
	return true


static func known_actives() -> Array:
	var out := ["heal_minor"]
	for id in GameState.player()["skills"]:
		var sk := DB.skill(id)
		if sk.get("kind", "") == "active":
			out.append(sk["ability"])
	return out


static func set_loadout(slot: int, ability: String) -> void:
	var lo: Array = GameState.player()["loadout"]
	if ability != "" and not ability in known_actives():
		return
	var existing := lo.find(ability)
	if existing >= 0 and ability != "":
		lo[existing] = ""
	lo[slot] = ability


static func respec_cost() -> int:
	return 40 + int(GameState.player()["level"]) * 15


static func respec(free: bool = false) -> bool:
	var p := GameState.player()
	if not free:
		var cost := respec_cost()
		if GameState.amber() < cost:
			EventBus.notify.emit("Neuverteilung kostet %d Bernstein." % cost, "warn")
			return false
		GameState.add_amber(-cost)
	var total := 0
	var kit: Dictionary = GameState.START_KITS.get(p["kit"], {})
	var kit_sk: Dictionary = kit.get("skills", {})
	for id in p["skills"]:
		total += int(p["skills"][id]) - int(kit_sk.get(id, 0))
	p["skills"] = kit_sk.duplicate()
	p["skill_points"] = int(p["skill_points"]) + total
	p["loadout"] = ["heal_minor", "", "", ""]
	EventBus.notify.emit("Fähigkeiten zurückgesetzt: %d Punkte frei." % total, "good")
	EventBus.hud_refresh.emit()
	return true


static func demon_learn(id: String) -> bool:
	var d: Dictionary = GameState.player()["demon"]
	var sk: Dictionary = DB.get_entry("demon_skills", id)
	if sk.is_empty() or int(d.get("points", 0)) <= 0:
		return false
	var rank := int(d["skills"].get(id, 0))
	if rank >= int(sk.get("max", 1)) or int(d.get("level", 0)) < int(sk.get("level", 1)):
		return false
	d["skills"][id] = rank + 1
	d["points"] = int(d["points"]) - 1
	EventBus.notify.emit("Dämonische Kraft erlernt: " + sk["name"], "good")
	return true
