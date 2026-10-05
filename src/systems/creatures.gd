class_name Creatures
extends RefCounted
## Tamed creature records: creation, derived stats, leveling, bond, abilities.

const SIZE_UNITS := {"small": 0.5, "medium": 1.0, "large": 2.0, "huge": 4.0}
const PERSONALITIES := {
	"mutig": {"name": "Mutig", "desc": "+10% Schaden, flieht nie.", "dmg": 1.1, "flee": 0.0},
	"aengstlich": {"name": "Ängstlich", "desc": "+10% Tempo, zieht sich früh zurück.", "spd": 1.1, "flee": 0.35},
	"verspielt": {"name": "Verspielt", "desc": "+30% Bindungsgewinn.", "bond": 1.3},
	"stur": {"name": "Stur", "desc": "+10% Verteidigung, gehorcht manchmal verzögert.", "deff": 1.1, "disobey": 0.08},
	"loyal": {"name": "Loyal", "desc": "+50% Bindungsgewinn, bleibt nah.", "bond": 1.5},
	"gierig": {"name": "Gierig", "desc": "Frisst mehr, Futter wirkt stärker.", "hunger": 1.3, "food": 1.3},
	"wild": {"name": "Wild", "desc": "+15% Angriffstempo, schwerer zu lenken.", "atk_speed": 1.15, "disobey": 0.06},
	"ruhig": {"name": "Ruhig", "desc": "+25% Ausdauerregeneration.", "stam_regen": 1.25},
	"neugierig": {"name": "Neugierig", "desc": "+20% Erfahrung.", "xp": 1.2},
	"grausam": {"name": "Grausam", "desc": "Angriffe verursachen öfter Blutung.", "bleed": 0.2},
}
const LIKES := {"kampf": "Kämpfe", "schwimmen": "Schwimmen", "fliegen": "Fliegen", "ruhe": "Ruhe im Lager", "gesellschaft": "Gesellschaft anderer Tiere", "reiten": "Geritten werden", "jagd": "Jagen"}
const FEARS := {"feuer": "Feuer", "wasser": "Tiefes Wasser", "dunkel": "Dunkelheit", "gewitter": "Gewitter", "dämonen": "Dämonen", "raubtiere": "Große Raubtiere", "höhe": "Große Höhen"}


static func make_record(uid: int, species: String, level: int, genes: Dictionary, opts: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(uid * 7919 + level)
	var sp := DB.species(genes.get("body_species", species) if genes.get("species", "") == "hybrid" else species)
	var pers_keys := PERSONALITIES.keys()
	var likes := LIKES.keys()
	var fears := FEARS.keys()
	var foods: Array = sp.get("food", ["raw_meat"])
	var rec := {
		"uid": uid, "species": genes.get("species", species), "name": opts.get("name", Genetics.random_name(rng)),
		"level": level, "xp": 0, "sex": "m" if rng.randf() < 0.5 else "w", "genes": genes,
		"hp": -1.0, "stamina": -1.0, "hunger": 80.0, "bond": float(opts.get("bond", 20.0)),
		"personality": opts.get("personality", pers_keys[rng.randi() % pers_keys.size()]),
		"likes": [likes[rng.randi() % likes.size()], foods[rng.randi() % foods.size()]],
		"fears": [fears[rng.randi() % fears.size()]],
		"abilities": [], "element_slots": [[], [], []], "status": opts.get("status", "base"),
		"pos": [], "injuries": [], "generation": genes.get("generation", 0), "parents": opts.get("parents", []),
		"parent_names": opts.get("parent_names", []), "favorite": false, "born_day": GameState.get_day(),
		"tamed_method": opts.get("method", "unknown"), "saddle": false, "trained": {}, "kills": 0, "growth": float(opts.get("growth", 1.0)),
		"notes": "", "aggression": "defensive",
	}
	# equip default abilities up to slot limit
	var pool: Array = genes.get("abilities_pool", sp.get("abilities", []))
	for ab in pool:
		if rec["abilities"].size() < ability_slots(rec):
			rec["abilities"].append(ab)
	# element slots: strongest element goes to slot 1
	var els: Dictionary = genes.get("elements", {})
	if not els.is_empty():
		var best := ""
		var bv := -1.0
		for e in els:
			if els[e] > bv:
				bv = els[e]
				best = e
		rec["element_slots"][0] = [best]
	var st := stats(rec)
	rec["hp"] = st["hp"]
	rec["stamina"] = st["stam"]
	return rec


static func species_def(rec: Dictionary) -> Dictionary:
	var g: Dictionary = rec["genes"]
	if g.get("species", "") == "hybrid":
		return DB.species(g.get("body_species", "raptor"))
	return DB.species(g["species"])


static func display_species(rec: Dictionary) -> String:
	return Genetics.display_species(rec["genes"])


static func size_units(rec: Dictionary) -> float:
	return SIZE_UNITS.get(species_def(rec).get("size", "medium"), 1.0)


static func ability_slots(rec: Dictionary) -> int:
	var lv := int(rec.get("level", 1))
	var n := 1
	if lv >= 5:
		n = 2
	if lv >= 15:
		n = 3
	if lv >= 30 or (lv >= 20 and float(rec.get("bond", 0)) >= 80.0):
		n = 4
	return n


static func stats(rec: Dictionary) -> Dictionary:
	var g: Dictionary = rec["genes"]
	var base: Dictionary = Genetics.base_stats(g)
	var lv := float(rec.get("level", 1))
	var pers: Dictionary = PERSONALITIES.get(rec.get("personality", ""), {})
	var bond_bonus := 1.0 + clampf(float(rec.get("bond", 0)) / 100.0, 0.0, 1.0) * 0.1
	var tr: Dictionary = rec.get("trained", {})
	var growth := clampf(float(rec.get("growth", 1.0)), 0.25, 1.0)
	var out := {}
	out["hp"] = float(base.get("hp", 100)) * (1.0 + 0.06 * (lv - 1)) * Genetics.stat_multiplier(g, "hp") * (1.0 + 0.02 * float(tr.get("hp", 0))) * growth
	out["atk"] = float(base.get("atk", 10)) * (1.0 + 0.045 * (lv - 1)) * Genetics.stat_multiplier(g, "atk") * float(pers.get("dmg", 1.0)) * bond_bonus * (1.0 + 0.02 * float(tr.get("atk", 0))) * lerpf(0.4, 1.0, growth)
	out["deff"] = float(base.get("deff", 5)) * (1.0 + 0.02 * (lv - 1)) * Genetics.stat_multiplier(g, "deff") * float(pers.get("deff", 1.0)) * (1.0 + 0.02 * float(tr.get("deff", 0)))
	out["spd"] = float(base.get("spd", 6)) * Genetics.stat_multiplier(g, "spd") * float(pers.get("spd", 1.0)) * (1.0 + 0.01 * float(tr.get("spd", 0)))
	out["walk"] = float(base.get("walk", 2.5))
	out["stam"] = float(base.get("stam", 200)) * (1.0 + 0.03 * (lv - 1)) * Genetics.stat_multiplier(g, "stam") * (1.0 + 0.02 * float(tr.get("stam", 0)))
	out["carry"] = float(base.get("carry", 100)) * (1.0 + 0.02 * (lv - 1))
	out["swim"] = float(base.get("swim", 0.0)) * Genetics.stat_multiplier(g, "spd")
	out["fly"] = float(base.get("fly", 0.0)) * Genetics.stat_multiplier(g, "spd")
	for inj in rec.get("injuries", []):
		match inj:
			"bein_verletzt":
				out["spd"] *= 0.75
			"schwer_verletzt":
				out["hp"] *= 0.7
				out["atk"] *= 0.8
	return out


static func xp_needed(lv: int) -> int:
	return int(60.0 * pow(lv, 1.45))


static func add_xp(rec: Dictionary, amount: float) -> bool:
	var pers: Dictionary = PERSONALITIES.get(rec.get("personality", ""), {})
	rec["xp"] = int(rec["xp"]) + int(amount * float(pers.get("xp", 1.0)))
	var leveled := false
	while rec["xp"] >= xp_needed(rec["level"]) and rec["level"] < 60:
		rec["xp"] -= xp_needed(rec["level"])
		rec["level"] += 1
		leveled = true
		var slots := ability_slots(rec)
		var pool: Array = rec["genes"].get("abilities_pool", [])
		for ab in pool:
			if rec["abilities"].size() < slots and not ab in rec["abilities"]:
				rec["abilities"].append(ab)
	if leveled:
		EventBus.notify.emit("%s erreicht Stufe %d!" % [rec["name"], rec["level"]], "good")
	return leveled


static func add_bond(rec: Dictionary, amount: float) -> void:
	var pers: Dictionary = PERSONALITIES.get(rec.get("personality", ""), {})
	var mult := float(pers.get("bond", 1.0)) * (1.0 + 0.25 * GameState.skill_rank("tame_bond"))
	for m in rec["genes"].get("mutations", []):
		mult *= float(Genetics.MUTATIONS.get(m, {}).get("bond_mult", 1.0))
	if amount < 0:
		mult = 1.0
	rec["bond"] = clampf(float(rec["bond"]) + amount * mult, 0.0, 100.0)


static func bond_label(b: float) -> String:
	if b >= 90:
		return "Seelenverwandt"
	if b >= 70:
		return "Treu"
	if b >= 45:
		return "Vertraut"
	if b >= 20:
		return "Zögerlich"
	return "Misstrauisch"


static func obey_chance(rec: Dictionary) -> float:
	var c := 0.75 + float(rec.get("bond", 0)) / 400.0
	c -= float(PERSONALITIES.get(rec.get("personality", ""), {}).get("disobey", 0.0))
	for m in rec["genes"].get("mutations", []):
		c -= float(Genetics.MUTATIONS.get(m, {}).get("disobey", 0.0))
	return clampf(c, 0.4, 1.0)


static func can_ride(rec: Dictionary) -> Dictionary:
	var sp := species_def(rec)
	if not sp.get("rideable", false):
		return {"ok": false, "why": "Diese Art ist nicht reitbar."}
	if float(rec.get("growth", 1.0)) < 0.99:
		return {"ok": false, "why": "Noch nicht ausgewachsen."}
	if int(rec["level"]) < int(sp.get("min_ride_level", 0)):
		return {"ok": false, "why": "Erst ab Stufe %d reitbar." % sp["min_ride_level"]}
	if not rec.get("saddle", false):
		return {"ok": false, "why": "Kein Sattel angelegt (%s nötig)." % DB.item_name(saddle_for(rec))}
	return {"ok": true}


static func saddle_for(rec: Dictionary) -> String:
	var sp := species_def(rec)
	match sp.get("mount", "ground"):
		"fly":
			return "saddle_flyer"
		"swim":
			return "saddle_sea"
	match sp.get("size", "medium"):
		"large":
			return "saddle_large"
		"huge":
			return "saddle_huge"
	return "saddle_small"


static func element_slot_ok(rec: Dictionary, slot: Array) -> Dictionary:
	var n := slot.size()
	if n == 0:
		return {"ok": true}
	if n > 5:
		return {"ok": false, "why": "Höchstens 5 Bestandteile."}
	var mix: Dictionary = DB.t("mixture").get(str(n), {})
	var req = mix.get("research", null)
	if req != null and not GameState.has_research(req):
		return {"ok": false, "why": "Mischung aus %d Elementen benötigt Forschung „%s“." % [n, DB.research(req).get("name", req)]}
	var els: Dictionary = rec["genes"].get("elements", {})
	for e in slot:
		if not els.has(e):
			return {"ok": false, "why": "Element %s ist nicht im Genprofil." % DB.element(e).get("name", e)}
	if n >= 1 and not GameState.has_research("element_theory") and n > 0 and rec["element_slots"].find(slot) != 0:
		return {"ok": false, "why": "Weitere Elementplätze benötigen „Elementlehre“."}
	return {"ok": true}


static func status_label(s: String) -> String:
	return {"party": "Gefolge", "crystal": "Seelenkristall", "base": "Lager", "dead": "Verstorben", "egg": "Ei", "expedition": "Expedition", "wild": "Wild"}.get(s, s)
