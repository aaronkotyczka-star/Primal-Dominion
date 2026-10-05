class_name Settlement
extends RefCounted
## Residents (skills, needs, loyalty, auto-jobs), expeditions and territory income.

const JOBS := {"sammeln": "Sammeln", "farm": "Feldarbeit", "handwerk": "Handwerk", "pflege": "Tierpflege", "wache": "Wache"}
const FIRST := ["Arn", "Bera", "Cato", "Dagny", "Eik", "Frida", "Gorm", "Hilde", "Ivo", "Jorun", "Kel", "Lysa", "Mads", "Nora", "Orm", "Pia"]
const GOB := ["Grik", "Zubba", "Nokk", "Ritta", "Snarg", "Mobbel", "Krix", "Tazz"]
const TERRITORIES := {
	"knochenebene": {"name": "Knochenebene", "poi": "knochenbrecher", "owner": "knochenbrecher", "yield": {"hide": 6, "large_bone": 2, "raw_meat": 6}},
	"moosfell": {"name": "Smaragddschungel", "poi": "moosfell", "owner": "moosfell", "yield": {"berries": 10, "herb_healing": 4, "fiber": 10}},
	"morgengrau": {"name": "Morgengrau-Küste", "poi": "morgengrau", "owner": "morgengrau", "yield": {"raw_fish": 8, "wood": 10, "salt": 2}},
	"narbenschlund": {"name": "Narbenschlund", "poi": "riss_narbenschlund", "owner": "daemonengoblins", "yield": {"demon_essence": 3, "rift_shard": 1}},
	"nordgrat": {"name": "Nordgrat", "poi": "adlerhorst", "owner": "", "yield": {"metal_ore": 6, "stone": 12, "flint": 4}},
	"fischerkap": {"name": "Fischerkap", "poi": "fischerkap", "owner": "eisenhand", "yield": {"metal_ingot": 2, "raw_fish": 6}},
	"aschenkamm": {"name": "Aschenkamm", "poi": "vulkan_krater", "owner": "", "yield": {"obsidian": 4, "sulfur": 4, "elemental_essence": 1}},
	"glutsand": {"name": "Glutsand", "poi": "oase", "owner": "", "yield": {"sulfur": 3, "salt": 4, "sand_glass": 0}},
}


static func capacity() -> int:
	var n := 0
	for b in GameState.state["buildings"]:
		n += int(DB.building(b["type"]).get("residents", 0))
	return n


static func residents() -> Array:
	return GameState.state["settlement"]["residents"]


static func recruit(origin: String) -> Dictionary:
	if residents().size() >= capacity():
		return {"ok": false, "why": "Keine freie Unterkunft (Wohnhütte bauen)."}
	var s: Dictionary = GameState.state["settlement"]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var goblin := origin in ["moosfell", "knochenbrecher"]
	var r := {"id": s["next_resident"], "name": (GOB if goblin else FIRST)[rng.randi() % (GOB if goblin else FIRST).size()],
		"race": "goblin" if goblin else "human", "origin": origin, "loyalty": 50.0, "hunger": 80.0, "job": "sammeln",
		"skills": {"sammeln": rng.randi_range(1, 4), "farm": rng.randi_range(1, 4), "handwerk": rng.randi_range(1, 4), "pflege": rng.randi_range(1, 4), "wache": rng.randi_range(1, 4)},
		"status": "home", "injured": 0.0}
	s["next_resident"] = int(s["next_resident"]) + 1
	residents().append(r)
	_auto_assign(r)
	return {"ok": true, "resident": r}


static func _auto_assign(r: Dictionary) -> void:
	var best := "sammeln"
	var bv := -1
	for k in r["skills"]:
		var v := int(r["skills"][k])
		if k == "farm" and not _has_building("farm_plot"):
			continue
		if v > bv:
			bv = v
			best = k
	r["job"] = best


static func _has_building(t: String) -> bool:
	for b in GameState.state["buildings"]:
		if b["type"] == t:
			return true
	return false


static func _storage() -> Array:
	for b in GameState.state["buildings"]:
		if DB.building(b["type"]).has("storage"):
			if not b.has("data"):
				b["data"] = {}
			if not b["data"].has("storage"):
				b["data"]["storage"] = []
			return b["data"]["storage"]
	return []


static func tick(w: Node, dt: float) -> void:
	var hours := dt / GameState.HOUR_SECONDS
	var store := _storage()
	for r in residents():
		if r["status"] == "expedition":
			continue
		r["hunger"] = maxf(0.0, float(r["hunger"]) - hours * 4.0)
		if r["hunger"] < 40.0 and not store.is_empty():
			for f in ["cooked_meat", "cooked_fish", "jerky", "stew", "veggies", "berries", "raw_fish", "raw_meat"]:
				if Inventory.count(store, f) > 0:
					Inventory.remove(store, f, 1)
					r["hunger"] = 100.0
					break
		var happy := 1.0
		if r["hunger"] <= 0.0:
			happy = -2.0
		if _has_building("banner"):
			happy += 0.3
		r["loyalty"] = clampf(float(r["loyalty"]) + hours * happy, 0.0, 100.0)
		if float(r["loyalty"]) <= 0.0:
			residents().erase(r)
			EventBus.notify.emit("%s hat dein Lager verlassen (Hunger/Unzufriedenheit)." % r["name"], "danger")
			return
		if store.is_empty():
			continue
		var lvl := float(r["skills"].get(r["job"], 1))
		var eff := hours * lvl * (0.5 + float(r["loyalty"]) / 100.0)
		match r["job"]:
			"sammeln":
				_produce(store, {"wood": 2.0, "stone": 1.5, "fiber": 2.0, "berries": 1.0}, eff)
			"farm":
				var plots := 0
				for b in GameState.state["buildings"]:
					if b["type"] == "farm_plot":
						plots += 1
				_produce(store, {"veggies": 1.5 * plots, "berries": 1.0 * plots, "herb_healing": 0.5 * plots}, eff)
			"handwerk":
				for pair in [["raw_meat", "cooked_meat"], ["raw_fish", "cooked_fish"], ["hide", "leather"]]:
					if Inventory.count(store, pair[0]) > 0 and randf() < eff:
						Inventory.remove(store, pair[0], 1)
						Inventory.add(store, pair[1], 1)
			"pflege":
				for c in GameState.all_creatures():
					if c["status"] == "base":
						Creatures.add_bond(c, eff * 0.2)
						c["hunger"] = minf(100.0, float(c.get("hunger", 50)) + eff * 2.0)
			"wache":
				pass
	_expeditions()
	_territory_income(store)


static func _produce(store: Array, table: Dictionary, eff: float) -> void:
	for k in table:
		var amt: float = float(table[k]) * eff
		var n := int(amt) + (1 if randf() < fmod(amt, 1.0) else 0)
		if n > 0:
			Inventory.add(store, k, n)


static func defense_value() -> float:
	var v := 0.0
	for r in residents():
		if r["job"] == "wache" and r["status"] == "home":
			v += float(r["skills"]["wache"]) * 10.0
	for b in GameState.state["buildings"]:
		if DB.building(b["type"]).has("defense"):
			v += 40.0
	return v


# ---------------------------------------------------------------- expeditions
static func start_expedition(region_id: String, resident_ids: Array, creature_uids: Array, hours: float) -> Dictionary:
	var reg := {}
	for r in WorldData.info["regions"]:
		if r["id"] == region_id:
			reg = r
	if reg.is_empty():
		return {"ok": false, "why": "Unbekannte Region."}
	if not reg.get("water", false) and not _region_known(reg):
		return {"ok": false, "why": "Region noch nicht erkundet."}
	if resident_ids.is_empty() and creature_uids.is_empty():
		return {"ok": false, "why": "Mindestens ein Bewohner oder eine Kreatur."}
	var power := 0.0
	for rid in resident_ids:
		for r in residents():
			if int(r["id"]) == int(rid):
				r["status"] = "expedition"
				power += 10.0 + float(r["skills"]["wache"]) * 3.0 + float(r["skills"]["sammeln"]) * 3.0
	for uid in creature_uids:
		var c := GameState.creature(uid)
		if c.is_empty() or c["status"] != "base":
			continue
		c["status"] = "expedition"
		var st := Creatures.stats(c)
		power += float(st["atk"]) * 0.6 + float(st["hp"]) * 0.02
	var now := GameState.get_day() * 24.0 + GameState.get_hour()
	var danger := float(reg["levels"][1]) * 6.0
	GameState.state["settlement"]["expeditions"].append({"region": region_id, "name": reg["name"], "residents": resident_ids, "creatures": creature_uids,
		"power": power, "danger": danger, "return_at": now + hours, "hours": hours})
	return {"ok": true}


static func _region_known(reg: Dictionary) -> bool:
	for id in GameState.state["discovered"]:
		var p := WorldData.poi(id)
		if Vector2(p["x"] - reg["x"], p["z"] - reg["z"]).length() < float(reg["r"]):
			return true
	return false


static func _expeditions() -> void:
	var now := GameState.get_day() * 24.0 + GameState.get_hour()
	var exps: Array = GameState.state["settlement"]["expeditions"]
	for e in exps.duplicate():
		if now < float(e["return_at"]):
			continue
		exps.erase(e)
		var ratio := float(e["power"]) / maxf(1.0, float(e["danger"]))
		var store := _storage()
		var loot := {}
		var reg := {}
		for r in WorldData.info["regions"]:
			if r["id"] == e["region"]:
				reg = r
		for sp in reg.get("spawns", {}):
			for l in DB.species(sp).get("loot", []):
				if randf() < 0.5:
					loot[l[0]] = int(loot.get(l[0], 0)) + int(ceil(float(l[2]) * clampf(ratio, 0.3, 2.0) * float(e["hours"]) / 6.0))
		for k in loot:
			Inventory.add(store, k, loot[k])
		var injured := []
		for uid in e["creatures"]:
			var c := GameState.creature(uid)
			if c.is_empty():
				continue
			c["status"] = "base"
			Creatures.add_xp(c, 40.0 * float(e["hours"]))
			if randf() > clampf(ratio, 0.2, 0.95):
				c["injuries"].append("bein_verletzt")
				injured.append(c["name"])
		for rid in e["residents"]:
			for r in residents():
				if int(r["id"]) == int(rid):
					r["status"] = "home"
					r["skills"]["sammeln"] = mini(10, int(r["skills"]["sammeln"]) + (1 if randf() < 0.3 else 0))
		var txt := "Expedition aus %s zurück: %s" % [e["name"], ", ".join(loot.keys().map(func(k): return "%d× %s" % [loot[k], DB.item_name(k)]))]
		if not injured.is_empty():
			txt += ". Verletzt: " + ", ".join(injured)
		EventBus.notify.emit(txt, "good" if injured.is_empty() else "warn")


# ---------------------------------------------------------------- territories
static func territory_owner(tid: String) -> String:
	var t: Dictionary = GameState.state["territories"].get(tid, {})
	if t.has("owner"):
		return t["owner"]
	return TERRITORIES.get(tid, {}).get("owner", "")


static func claim(tid: String, how: String) -> void:
	GameState.state["territories"][tid] = {"owner": "player", "since": GameState.get_day(), "how": how, "last_income": GameState.get_day()}
	EventBus.notify.emit("Gebiet gewonnen: %s (%s)." % [TERRITORIES[tid]["name"], how], "quest")


static func claim_options(tid: String) -> Array:
	## ways to gain a territory: alliance (rep), trade (amber), conquest (army power)
	var t: Dictionary = TERRITORIES[tid]
	var fid: String = t["owner"]
	var out := []
	if fid != "" and GameState.rep(fid) >= 60:
		out.append({"how": "Bündnis", "cost": 0, "ok": true})
	elif fid != "":
		out.append({"how": "Bündnis", "cost": 0, "ok": false, "why": "Ansehen ≥ 60 nötig"})
	out.append({"how": "Handelsabkommen", "cost": 300, "ok": GameState.amber() >= 300 and (fid == "" or GameState.rep(fid) >= 20), "why": "300 Bernstein, Ansehen ≥ 20"})
	out.append({"how": "Eroberung", "cost": 0, "ok": true, "why": "Feldzug auf der taktischen Karte"})
	return out


static func _territory_income(store: Array) -> void:
	if store.is_empty():
		return
	for tid in GameState.state["territories"]:
		var t: Dictionary = GameState.state["territories"][tid]
		if t.get("owner", "") != "player":
			continue
		var last := int(t.get("last_income", t.get("since", 0)))
		if GameState.get_day() > last:
			t["last_income"] = GameState.get_day()
			for k in TERRITORIES.get(tid, {}).get("yield", {}):
				var n := int(TERRITORIES[tid]["yield"][k])
				if n > 0:
					Inventory.add(store, k, n)
			EventBus.notify.emit("Abgaben aus %s eingetroffen." % TERRITORIES.get(tid, {}).get("name", tid), "good")
			# recapture threat when taken by force from a hostile faction
			if t.get("how", "") == "erobert" and randf() < 0.15:
				var prev: String = TERRITORIES[tid]["owner"]
				if prev != "" and GameState.rep(prev) < 0:
					if defense_value() < 30.0:
						t["owner"] = prev
						EventBus.notify.emit("%s wurde von %s zurückerobert! Stärke deine Wachen." % [TERRITORIES[tid]["name"], DB.faction(prev).get("name", prev)], "danger")
					else:
						EventBus.notify.emit("Ein Rückeroberungsversuch auf %s wurde von deinen Wachen abgewehrt." % TERRITORIES[tid]["name"], "good")


# ---------------------------------------------------------------- campaign battle (auto-resolve with optional join)
static func army_power(uids: Array) -> float:
	var p := 0.0
	for uid in uids:
		var c := GameState.creature(uid)
		if c.is_empty() or c["status"] == "dead":
			continue
		var st := Creatures.stats(c)
		p += float(st["atk"]) * 1.0 + float(st["hp"]) * 0.03 + float(st["deff"]) * 0.5
	return p


static func defender_power(tid: String) -> float:
	var base := {"knochenbrecher": 220.0, "moosfell": 150.0, "morgengrau": 180.0, "daemonengoblins": 420.0, "eisenhand": 380.0, "": 160.0}
	return float(base.get(TERRITORIES[tid]["owner"], 200.0))


static func resolve_campaign(tid: String, uids: Array) -> Dictionary:
	var ap := army_power(uids) + defense_value() * 0.5
	var dp := defender_power(tid)
	var ratio := ap / maxf(1.0, dp)
	var win := randf() < clampf(0.15 + (ratio - 0.6) * 0.6, 0.05, 0.95)
	var lost := []
	for uid in uids:
		var c := GameState.creature(uid)
		if c.is_empty():
			continue
		if randf() < clampf(0.35 - ratio * 0.2, 0.02, 0.5):
			if randf() < 0.25:
				GameState.kill_creature(uid, "Gefallen im Feldzug um " + TERRITORIES[tid]["name"])
				lost.append(c["name"] + " (gefallen)")
			else:
				c["injuries"].append("schwer_verletzt")
				lost.append(c["name"] + " (verletzt)")
		Creatures.add_xp(c, 200.0)
	var owner: String = TERRITORIES[tid]["owner"]
	if win:
		claim(tid, "erobert")
		if owner != "":
			GameState.change_rep(owner, -35, "Gebiet erobert")
		GameState.add_path("conqueror", 2)
	return {"win": win, "ratio": ratio, "losses": lost}
