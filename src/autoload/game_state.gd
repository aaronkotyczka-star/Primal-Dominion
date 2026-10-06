extends Node
## Authoritative, serializable game state (no scene references). Everything that is
## saved lives in `state`. Scene nodes read/write through this API.

const VERSION := 1
const HOUR_SECONDS := 90.0 # real seconds per in-game hour (36 min per day)

const DIFFICULTY := {
	"leicht": {"dmg_taken": 0.6, "dmg_dealt": 1.3, "hunger": 0.6, "taming": 1.5, "xp": 1.3, "drop_on_death": false, "player_permadeath": false, "creature_permadeath": true, "hunger_lethal": true},
	"normal": {"dmg_taken": 1.0, "dmg_dealt": 1.0, "hunger": 1.0, "taming": 1.0, "xp": 1.0, "drop_on_death": true, "player_permadeath": false, "creature_permadeath": true, "hunger_lethal": true},
	"schwer": {"dmg_taken": 1.35, "dmg_dealt": 0.9, "hunger": 1.3, "taming": 0.8, "xp": 0.9, "drop_on_death": true, "player_permadeath": false, "creature_permadeath": true, "hunger_lethal": true},
	"brutal": {"dmg_taken": 1.7, "dmg_dealt": 0.8, "hunger": 1.5, "taming": 0.6, "xp": 0.8, "drop_on_death": true, "player_permadeath": true, "creature_permadeath": true, "hunger_lethal": true},
}

const START_KITS := {
	"jaeger": {"name": "Jäger", "desc": "Bogen, Speer und Betäubungspfeile. Bonus auf Fernkampf und Jagd.",
		"items": [["bow_wood", 1], ["arrow_stone", 15], ["arrow_tranq", 6], ["spear_stone", 1], ["armor_hide_chest", 1], ["cooked_meat", 4]],
		"skills": {"ranged_aim": 1, "hunt_tracking": 1}, "equip": {"weapon": "spear_stone", "chest": "armor_hide_chest"}},
	"kaempfer": {"name": "Kämpfer", "desc": "Keule, Axt und Holzschild. Bonus auf Nahkampf und Verteidigung.",
		"items": [["club_wood", 1], ["axe_stone", 1], ["shield_wood", 1], ["armor_hide_chest", 1], ["armor_hide_legs", 1], ["cooked_meat", 4]],
		"skills": {"melee_power": 1, "def_block": 1}, "equip": {"weapon": "club_wood", "offhand": "shield_wood", "chest": "armor_hide_chest", "legs": "armor_hide_legs"}},
	"gelehrter": {"name": "Heilkundiger", "desc": "Stab, Heilkräuter und Forschungsnotizen. Bonus auf Heilung und Alchemie.",
		"items": [["staff_wood", 1], ["herb_healing", 8], ["bandage", 4], ["research_notes", 3], ["berries", 10]],
		"skills": {"heal_mend": 1, "surv_alchemy": 1}, "equip": {"weapon": "staff_wood"}, "research_points": 6},
	"bestienhueter": {"name": "Bestienhüter", "desc": "Startet mit einem kleinen Gefährten, Futter und Pfeife. Bonus auf Bestienführung und Zähmung.",
		"items": [["spear_stone", 1], ["raw_meat", 8], ["berries", 8], ["bola", 3], ["armor_hide_chest", 1]],
		"skills": {"beast_command": 1, "tame_trust": 1}, "equip": {"weapon": "spear_stone", "chest": "armor_hide_chest"}, "companion": "compy"},
}

var state: Dictionary = {}
var running := false
var _weather_hours := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	state = _blank_state()


func _blank_state() -> Dictionary:
	return {
		"version": VERSION, "seed": 0, "slot": "", "created": "", "playtime": 0.0,
		"difficulty": "normal", "rules": DIFFICULTY["normal"].duplicate(),
		"time": {"day": 1, "hour": 8.0},
		"player": {
			"name": "Wanderer", "kit": "jaeger", "body": "human_m", "pos": [60.0, 15.0, 398.0], "yaw": 0.0,
			"hp": 100.0, "stamina": 100.0, "hunger": 85.0, "level": 1, "xp": 0, "skill_points": 1,
			"skills": {}, "loadout": ["heal_minor", "", "", ""], "hotbar": ["", "", "", "", "", ""],
			"equipment": {"weapon": "", "offhand": "", "head": "", "chest": "", "legs": "", "trinket": ""},
			"inventory": [], "amber": 15, "respawn": [], "dead": false, "buffs": [],
			"demon": {"unlocked": false, "level": 0, "xp": 0, "points": 0, "skills": {}, "in_form": false, "active_form": 0,
				"forms": [{"name": "Gestalt I", "horns": "horns_demon", "wings": false, "tail": true, "skin": [0.25, 0.08, 0.07], "glow": [1.0, 0.3, 0.05], "claws": true}],
				"hints": {}, "seen_by": {}},
			"research_points": 0, "camera_fp": false,
		},
		"creatures": {}, "next_uid": 1,
		"party": [], # uids following
		"crystal": [], # uids stored in portable crystal
		"buildings": [], "next_building": 1,
		"quests": {}, "flags": {},
		"factions": {"morgengrau": {"rep": 10}, "moosfell": {"rep": 0}, "knochenbrecher": {"rep": -30}, "daemonengoblins": {"rep": -80}, "eisenhand": {"rep": 0}},
		"research": {"done": [], "known_sources": []},
		"recipes_known": [], "designs": [], "lexicon": {}, "discovered": [],
		"world": {"harvested": {}, "killed_unique": [], "looted": [], "nests": {}, "rift_state": "open", "tarpit_rescue": false},
		"hybrid": {"experiments": [], "recipes": []},
		"settlement": {"residents": [], "next_resident": 1, "expeditions": [], "jobs": {}},
		"territories": {}, "campaign": {"armies": []},
		"stats": {"kills": 0, "tamed": 0, "crafted": 0, "deaths": 0, "hybrids": 0},
		"path": {"protector": 0, "conqueror": 0, "demon": 0},
		"endings": [],
	}


func new_game(opts: Dictionary) -> void:
	state = _blank_state()
	state["seed"] = _rng.randi()
	state["created"] = Time.get_datetime_string_from_system()
	var diff: String = opts.get("difficulty", "normal")
	state["difficulty"] = diff
	state["rules"] = DIFFICULTY.get(diff, DIFFICULTY["normal"]).duplicate()
	if opts.has("rules"):
		state["rules"].merge(opts["rules"], true)
	var p: Dictionary = state["player"]
	p["name"] = opts.get("name", "Wanderer")
	p["body"] = opts.get("body", "human_m")
	var kit_id: String = opts.get("kit", "jaeger")
	p["kit"] = kit_id
	var kit: Dictionary = START_KITS.get(kit_id, START_KITS["jaeger"])
	for it in kit["items"]:
		Inventory.add(p["inventory"], it[0], it[1])
	for sk in kit.get("skills", {}):
		p["skills"][sk] = kit["skills"][sk]
	for slot in kit.get("equip", {}):
		p["equipment"][slot] = kit["equip"][slot]
		Inventory.remove(p["inventory"], kit["equip"][slot], 1)
	p["research_points"] = kit.get("research_points", 0)
	# common starter items
	Inventory.add(p["inventory"], "torch", 1)
	Inventory.add(p["inventory"], "berries", 5)
	var sp := WorldData.poi_pos("start_beach") if WorldData.loaded else Vector3(60, 14, 398)
	p["pos"] = [sp.x, sp.y + 1.0, sp.z]
	p["respawn"] = [sp.x, sp.y + 1.0, sp.z]
	p["hotbar"][0] = p["equipment"]["weapon"]
	if kit.has("companion"):
		var uid := create_creature(kit["companion"], 3, {"name": "Krümel", "method": "start", "bond": 40})
		set_creature_status(uid, "party")
	state["quests"]["q1_gestrandet"] = {"state": "active", "stage": 0, "counters": {}}
	set_flag("tutorial_stage", 0)
	running = true


# ------------------------------------------------------------------ time
func get_hour() -> float:
	return state["time"]["hour"]


func get_day() -> int:
	return state["time"]["day"]


func advance_time(real_delta: float) -> void:
	var hours := real_delta / HOUR_SECONDS
	add_hours(hours)


func add_hours(hours: float) -> void:
	var t: Dictionary = state["time"]
	t["hour"] += hours
	while t["hour"] >= 24.0:
		t["hour"] -= 24.0
		t["day"] += 1
	_weather_hours += hours


func skip_hours(hours: float) -> void:
	add_hours(hours)
	EventBus.time_skipped.emit(hours)


func consume_weather_hours() -> float:
	var h := _weather_hours
	_weather_hours = 0.0
	return h


func time_label() -> String:
	var h := get_hour()
	return "Tag %d, %02d:%02d" % [get_day(), int(h), int(fmod(h, 1.0) * 60.0)]


# ------------------------------------------------------------------ flags
func flag(k: String, default: Variant = null) -> Variant:
	return state["flags"].get(k, default)


func set_flag(k: String, v: Variant) -> void:
	state["flags"][k] = v


func rule(k: String) -> Variant:
	return state["rules"].get(k, DIFFICULTY["normal"].get(k))


# ------------------------------------------------------------------ player progression
func player() -> Dictionary:
	return state["player"]


func xp_for_level(lv: int) -> int:
	return int(80.0 * pow(lv, 1.55))


func add_xp(amount: float, _source: String = "") -> void:
	var p := player()
	p["xp"] += int(round(amount * float(rule("xp"))))
	while p["xp"] >= xp_for_level(p["level"]):
		p["xp"] -= xp_for_level(p["level"])
		p["level"] += 1
		p["skill_points"] += 1
		if p["level"] % 5 == 0:
			p["skill_points"] += 1
		EventBus.player_level_up.emit(p["level"])
		EventBus.notify.emit("Stufe %d erreicht! +Fähigkeitenpunkt" % p["level"], "good")
	var d: Dictionary = p["demon"]
	if _source == "kill" and d.get("unlocked", false) and d.get("in_form", false):
		add_demon_xp(amount * 1.5)


func demon_xp_for_level(lv: int) -> int:
	return 150 + lv * lv * 60


func add_demon_xp(amount: float) -> void:
	var d: Dictionary = player()["demon"]
	if not d.get("unlocked", false):
		return
	d["xp"] = int(d.get("xp", 0)) + int(round(amount * float(rule("xp"))))
	while int(d["xp"]) >= demon_xp_for_level(int(d["level"])) and int(d["level"]) < 30:
		d["xp"] = int(d["xp"]) - demon_xp_for_level(int(d["level"]))
		d["level"] = int(d["level"]) + 1
		d["points"] = int(d.get("points", 0)) + 1
		EventBus.notify.emit("Dämonenstufe %d erreicht! +Dämonenpunkt" % d["level"], "good")


func skill_rank(id: String) -> int:
	return int(player()["skills"].get(id, 0))


func has_research(id: String) -> bool:
	return id in state["research"]["done"]


func amber() -> int:
	return int(player()["amber"])


func add_amber(n: int) -> void:
	player()["amber"] = maxi(0, amber() + n)
	EventBus.inventory_changed.emit()


# ------------------------------------------------------------------ creatures
func create_creature(species: String, level: int, opts: Dictionary = {}) -> int:
	var uid: int = state["next_uid"]
	state["next_uid"] += 1
	var genes: Dictionary = opts.get("genes", Genetics.random_genes(species, _rng, opts.get("variant", {})))
	var rec := Creatures.make_record(uid, species, level, genes, opts)
	state["creatures"][str(uid)] = rec
	state["stats"]["tamed"] += 1
	lexicon_mark(genes.get("species", species), "tamed")
	return uid


func creature(uid: int) -> Dictionary:
	return state["creatures"].get(str(uid), {})


func all_creatures() -> Array:
	return state["creatures"].values()


func set_creature_status(uid: int, status: String) -> void:
	var c := creature(uid)
	if c.is_empty():
		return
	c["status"] = status
	state["party"].erase(uid)
	state["crystal"].erase(uid)
	if status == "party":
		state["party"].append(uid)
	elif status == "crystal":
		state["crystal"].append(uid)
	EventBus.party_changed.emit()


func party_limit() -> int:
	return 2 + skill_rank("beast_command") + skill_rank("beast_pack")


func crystal_capacity() -> float:
	var cap := 3.0
	if has_research("crystal_2"):
		cap += 2.0
	if has_research("crystal_3"):
		cap += 3.0
	return cap


func crystal_used() -> float:
	var u := 0.0
	for uid in state["crystal"]:
		u += Creatures.size_units(creature(uid))
	return u


func base_capacity() -> float:
	var cap := 5.0 if has_base() else 0.0
	for b in state["buildings"]:
		var bd := DB.building(b["type"])
		cap += float(bd.get("pen_capacity", 0.0))
	return cap


func base_used() -> float:
	var u := 0.0
	for c in all_creatures():
		if c["status"] == "base":
			u += Creatures.size_units(c)
	return u


func has_base() -> bool:
	for b in state["buildings"]:
		if b["type"] == "camp_totem":
			return true
	return false


func kill_creature(uid: int, cause: String) -> void:
	var c := creature(uid)
	if c.is_empty():
		return
	if rule("creature_permadeath"):
		c["status"] = "dead"
		c["death_cause"] = cause
		c["death_day"] = get_day()
	else:
		c["status"] = "crystal" if crystal_used() + Creatures.size_units(c) <= crystal_capacity() else "base"
		c["hp"] = 1.0
		c["injuries"].append("schwer_verletzt")
	state["party"].erase(uid)
	state["crystal"].erase(uid)
	EventBus.creature_died.emit(uid)
	EventBus.party_changed.emit()


# ------------------------------------------------------------------ lexicon / discovery
func lexicon_mark(species: String, what: String) -> void:
	var lx: Dictionary = state["lexicon"]
	if not lx.has(species):
		lx[species] = {"seen": false, "killed": 0, "investigated": false, "tamed": false}
	var e: Dictionary = lx[species]
	var first := false
	match what:
		"seen":
			first = not e["seen"]
			e["seen"] = true
		"killed":
			e["killed"] += 1
		"investigated":
			first = not e["investigated"]
			e["investigated"] = true
		"tamed":
			e["tamed"] = true
	if first:
		EventBus.lexicon_updated.emit(species)


func discover(poi_id: String) -> bool:
	if poi_id in state["discovered"]:
		return false
	state["discovered"].append(poi_id)
	EventBus.location_discovered.emit(poi_id)
	return true


# ------------------------------------------------------------------ factions
func rep(fid: String) -> int:
	return int(state["factions"].get(fid, {"rep": 0})["rep"])


func change_rep(fid: String, delta: int, reason: String = "") -> void:
	if not state["factions"].has(fid):
		state["factions"][fid] = {"rep": 0}
	var f: Dictionary = state["factions"][fid]
	f["rep"] = clampi(int(f["rep"]) + delta, -100, 100)
	EventBus.faction_changed.emit(fid, f["rep"])
	var fname: String = DB.faction(fid).get("name", fid)
	if delta != 0:
		EventBus.notify.emit("%s: Ansehen %+d%s" % [fname, delta, (" (" + reason + ")") if reason != "" else ""], "info" if delta > 0 else "warn")


func add_path(path: String, amount: int) -> void:
	state["path"][path] = int(state["path"].get(path, 0)) + amount


# ------------------------------------------------------------------ serialization helpers
func to_save() -> Dictionary:
	return state.duplicate(true)


func from_save(d: Dictionary) -> void:
	var blank := _blank_state()
	# forward-compatible merge: keep new keys from blank state
	for k in blank:
		if not d.has(k):
			d[k] = blank[k]
	for k in blank["player"]:
		if not d["player"].has(k):
			d["player"][k] = blank["player"][k]
	state = d
	running = true
