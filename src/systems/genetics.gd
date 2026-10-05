class_name Genetics
extends RefCounted
## Gene profiles, phenotypes, inheritance, hybridization and risk calculation.

const STAT_KEYS := ["hp", "atk", "deff", "spd", "stam"]
const STAT_NAMES := {"hp": "Leben", "atk": "Angriff", "deff": "Verteidigung", "spd": "Tempo", "stam": "Ausdauer"}
const RELATED := [["theropod", "ornithopod", "wyvern"], ["quadruped", "mammal", "crocodilian"],
	["pterosaur", "avian", "wyvern"], ["marine", "fish", "serpent"], ["arthropod"]]
const MUTATIONS := {
	"alpha": {"name": "Alpha", "good": true, "stats": {"hp": 1.25, "atk": 1.2, "deff": 1.1}, "scale": 1.18},
	"robust": {"name": "Robust", "good": true, "stats": {"hp": 1.12}},
	"kraftvoll": {"name": "Kraftvoll", "good": true, "stats": {"atk": 1.12}},
	"gepanzert": {"name": "Gepanzert", "good": true, "stats": {"deff": 1.15}},
	"flink": {"name": "Flink", "good": true, "stats": {"spd": 1.08}},
	"ausdauernd": {"name": "Ausdauernd", "good": true, "stats": {"stam": 1.15}},
	"riese": {"name": "Riesenwuchs", "good": true, "stats": {"hp": 1.08}, "scale": 1.14},
	"albino": {"name": "Albino", "good": true, "color": [0.88, 0.86, 0.82]},
	"melanistisch": {"name": "Melanistisch", "good": true, "color": [0.08, 0.07, 0.07]},
	"leuchtend": {"name": "Leuchtzeichnung", "good": true, "glow": 0.8},
	"elementar": {"name": "Elementarmutation", "good": true, "element": true},
	"korrumpiert": {"name": "Dämonisch korrumpiert", "good": true, "stats": {"atk": 1.15, "hp": 1.05}, "corruption": 0.85, "bond_mult": 0.75},
	"bruechig": {"name": "Brüchige Knochen", "good": false, "stats": {"deff": 0.8}, "cure": "creature_medicine"},
	"kurzatmig": {"name": "Kurzatmig", "good": false, "stats": {"stam": 0.75}, "cure": "training"},
	"lahm": {"name": "Lahm", "good": false, "stats": {"spd": 0.85}, "cure": "creature_medicine"},
	"jaehzornig": {"name": "Jähzornig", "good": false, "disobey": 0.15, "cure": "training"},
	"unfruchtbar": {"name": "Unfruchtbar", "good": false, "sterile": true, "cure": "purify_tonic"},
	"instabil": {"name": "Zellinstabilität", "good": false, "stats": {"hp": 0.85}, "cure": "gene_stabilizer"},
}
const ELEMENTS := ["fire", "water", "ice", "lightning", "earth", "wind", "nature", "poison", "light", "shadow", "blood"]
const NAMES_A := ["Asch", "Bor", "Dorn", "Grimm", "Krall", "Nebel", "Rost", "Schatt", "Splitt", "Zahn", "Funk", "Kies", "Moos", "Rab", "Brack", "Flint", "Glut", "Sturm", "Wirb", "Esch", "Fels", "Hag", "Jad", "Lanz", "Mor", "Narb", "Orm", "Pech", "Rauk", "Sumpf", "Teer", "Ur", "Wald", "Zorn", "Eis", "Horn", "Kno", "Lohe", "Skar", "Tos"]
const NAMES_B := ["a", "o", "ik", "ar", "ur", "en", "ka", "ra", "el", "is", "ox", "un", "ina", "ok", "ix", "ak", "ul"]


static func family_of(species: String) -> String:
	return DB.species(species).get("family", "theropod")


static func compat(fa: String, fb: String) -> String:
	if fa == fb:
		return "family"
	for grp in RELATED:
		if fa in grp and fb in grp:
			return "related"
	return "cross"


static func _col(c: Array, rng: RandomNumberGenerator, var_amt: float = 0.06) -> Array:
	return [clampf(c[0] + rng.randf_range(-var_amt, var_amt), 0.0, 1.0), clampf(c[1] + rng.randf_range(-var_amt, var_amt), 0.0, 1.0), clampf(c[2] + rng.randf_range(-var_amt, var_amt), 0.0, 1.0)]


static func random_genes(species: String, rng: RandomNumberGenerator, variant: Dictionary = {}) -> Dictionary:
	var sp := DB.species(species)
	var g := {"species": species, "rig": sp.get("rig", species), "family": sp.get("family", "theropod"),
		"mix": {species: 1.0}, "stats_q": {}, "colors": {}, "pattern_type": 1, "pattern_scale": 1.0,
		"size": rng.randf_range(0.92, 1.08), "parts": (sp.get("parts", []) as Array).duplicate(true),
		"elements": (sp.get("elements", {}) as Dictionary).duplicate(), "mutations": [], "instability": 0.0,
		"generation": 0, "body": {}, "abilities_pool": (sp.get("abilities", []) as Array).duplicate()}
	for k in STAT_KEYS:
		g["stats_q"][k] = clampf(rng.randfn(0.5, 0.15), 0.05, 0.95)
	var pal: Array = sp.get("colors", [{}])
	var c: Dictionary = pal[rng.randi() % pal.size()]
	g["colors"] = {"main": _col(c.get("main", [0.4, 0.35, 0.3]), rng), "belly": _col(c.get("belly", [0.6, 0.55, 0.5]), rng), "pattern": _col(c.get("pattern", [0.2, 0.15, 0.1]), rng)}
	g["pattern_type"] = int(c.get("pt", 1))
	g["pattern_scale"] = rng.randf_range(0.8, 1.25)
	for part in ["neck", "tail", "head", "legs"]:
		g["body"][part] = rng.randf_range(0.95, 1.05)
	# rare variants
	var roll := rng.randf()
	if variant.get("alpha", false) or roll < 0.015:
		g["mutations"].append("alpha")
	elif roll < 0.03:
		g["mutations"].append(["albino", "melanistisch", "leuchtend"][rng.randi() % 3])
	elif roll < 0.05:
		_add_elemental(g, rng)
	if variant.get("corrupted", false):
		g["mutations"].append("korrumpiert")
		g["elements"]["shadow"] = maxf(float(g["elements"].get("shadow", 0.0)), 0.4)
	if variant.get("element", "") != "":
		g["elements"] = {variant["element"]: 0.8}
	return g


static func _add_elemental(g: Dictionary, rng: RandomNumberGenerator) -> void:
	if "elementar" in g["mutations"]:
		return
	g["mutations"].append("elementar")
	var e: String = ELEMENTS[rng.randi() % ELEMENTS.size()]
	if g["elements"].size() < 5:
		g["elements"][e] = maxf(float(g["elements"].get(e, 0.0)), 0.6)


static func display_species(g: Dictionary) -> String:
	if g.get("species", "") == "hybrid":
		return g.get("hybrid_name", "Hybride")
	return DB.species(g["species"]).get("name", g["species"])


static func random_name(rng: RandomNumberGenerator) -> String:
	return NAMES_A[rng.randi() % NAMES_A.size()] + NAMES_B[rng.randi() % NAMES_B.size()]


# ---------------------------------------------------------------- phenotype
static func phenotype(g: Dictionary) -> Dictionary:
	var sp := DB.species(_base_species(g))
	var colors: Dictionary = g.get("colors", {})
	var main: Array = colors.get("main", [0.4, 0.35, 0.3])
	var belly: Array = colors.get("belly", [0.6, 0.55, 0.5])
	var patc: Array = colors.get("pattern", [0.2, 0.15, 0.1])
	var corruption := float(sp.get("corruption", 0.0))
	var glow := float(sp.get("glow", 0.0))
	var glow_color: Array = sp.get("glow_color", [1.0, 0.3, 0.05])
	var scale := float(g.get("size", 1.0))
	for m in g.get("mutations", []):
		var md: Dictionary = MUTATIONS.get(m, {})
		if md.has("color"):
			main = md["color"]
			belly = [main[0] * 1.1, main[1] * 1.1, main[2] * 1.1]
		if md.has("scale"):
			scale *= float(md["scale"])
		if md.has("glow"):
			glow = maxf(glow, float(md["glow"]))
		if md.has("corruption"):
			corruption = maxf(corruption, float(md["corruption"]))
			glow = maxf(glow, 0.6)
			glow_color = [1.0, 0.25, 0.08]
	var els: Dictionary = g.get("elements", {})
	if not els.is_empty() and ("elementar" in g.get("mutations", []) or els.size() >= 2):
		var best := ""
		var bv := 0.0
		for e in els:
			if els[e] > bv:
				bv = els[e]
				best = e
		var ed := DB.element(best)
		if not ed.is_empty():
			glow_color = ed["color"]
			glow = maxf(glow, 0.5 + bv * 0.5)
	return {"rig": g.get("rig", sp.get("rig", "raptor")), "scale": scale, "parts": expand_parts(g.get("parts", [])),
		"colors": {"color_main": main, "color_belly": belly, "color_pattern": patc},
		"pattern_type": g.get("pattern_type", 1), "pattern_scale": g.get("pattern_scale", 1.0),
		"corruption": corruption, "glow": glow, "glow_color": glow_color,
		"use_wrinkle": 1.0 if sp.get("tex", "") == "fur" else 0.0, "body": g.get("body", {})}


static func _base_species(g: Dictionary) -> String:
	if g.get("species", "") == "hybrid":
		return g.get("body_species", "raptor")
	return g.get("species", "raptor")


# ---------------------------------------------------------------- stats
static func base_stats(g: Dictionary) -> Dictionary:
	if g.has("base_stats"):
		return g["base_stats"]
	return DB.species(g["species"]).get("stats", {})


static func stat_multiplier(g: Dictionary, key: String) -> float:
	var q := float(g.get("stats_q", {}).get(key, 0.5))
	var m := 0.85 + 0.3 * q
	for mu in g.get("mutations", []):
		m *= float(MUTATIONS.get(mu, {}).get("stats", {}).get(key, 1.0))
	for p in g.get("parts", []):
		m *= float(DB.part(p["id"]).get("effects", {}).get(key, 1.0)) if _is_foreign(g, p) else 1.0
	return m


static func _is_foreign(g: Dictionary, p: Dictionary) -> bool:
	## native species parts are already baked into base stats
	if g.get("species", "") == "hybrid":
		return true
	for np in DB.species(g["species"]).get("parts", []):
		if np["id"] == p["id"] and np["socket"] == p["socket"]:
			return false
	return true


# ---------------------------------------------------------------- breeding / hybridization
static func analyze(a: Dictionary, b: Dictionary, essences: Array = []) -> Dictionary:
	## a, b = creature records. Returns feasibility & risk breakdown.
	var ga: Dictionary = a["genes"]
	var gb: Dictionary = b["genes"]
	var fa: String = ga.get("family", "")
	var fb: String = gb.get("family", "")
	var kind := "pure" if _base_species(ga) == _base_species(gb) and ga["species"] != "hybrid" and gb["species"] != "hybrid" else compat(fa, fb)
	var out := {"kind": kind, "ok": true, "reasons": [], "risk": 0.0}
	if a["uid"] == b["uid"]:
		out["ok"] = false
		out["reasons"].append("Zwei verschiedene Elterntiere nötig.")
	for g in [ga, gb]:
		if "unfruchtbar" in g.get("mutations", []):
			out["ok"] = false
			out["reasons"].append("Ein Elterntier ist unfruchtbar.")
	if kind == "family" and not GameState.has_research("genetics_1"):
		out["ok"] = false
		out["reasons"].append("Forschung „Genetik“ fehlt.")
	if kind == "related" and not GameState.has_research("chimera"):
		out["ok"] = false
		out["reasons"].append("Forschung „Chimärenforschung“ nötig (verwandte Körperfamilien).")
	if kind == "cross":
		if not GameState.has_research("chimera") or GameState.skill_rank("gen_chimera") < 1:
			out["ok"] = false
			out["reasons"].append("Fremde Körperfamilien: Chimärenforschung + Fähigkeit „Chimärenkunde“ nötig.")
	var monster := false
	for e in essences:
		if DB.item(e).has("monster") or e == "demon_essence":
			monster = true
	if monster and not GameState.has_research("monster_genes"):
		out["ok"] = false
		out["reasons"].append("Forschung „Monstergenetik“ nötig für Monsteressenzen.")
	var risk = {"pure": 0.03, "family": 0.12, "related": 0.24, "cross": 0.38}[kind]
	risk += (float(ga.get("instability", 0.0)) + float(gb.get("instability", 0.0))) * 0.5
	risk += 0.15 if monster else 0.0
	risk += 0.03 * essences.size()
	risk *= 1.0 - 0.15 * GameState.skill_rank("gen_stability")
	if kind in ["related", "cross"]:
		risk *= 1.0 - 0.2 * GameState.skill_rank("gen_chimera")
	out["risk"] = clampf(risk, 0.01, 0.9)
	out["monster"] = monster
	out["outcomes"] = risk_outcomes(out["risk"])
	return out


static func risk_outcomes(risk: float) -> Dictionary:
	var breakout := 0.0 if risk < 0.3 else (risk - 0.3) * 0.5
	return {"Erfolg": 1.0 - risk, "Materialverlust": risk * 0.4, "Ei entwickelt sich nicht": risk * 0.25,
		"Behandelbarer Erbdefekt": risk * 0.35 - breakout, "Aggressiver Ausbruch": breakout,
		"Überraschungserfolg (Mutation)": 0.04 + 0.03 * GameState.skill_rank("gen_mutation")}


static func design_instability(design: Dictionary) -> float:
	## extra instability from manual design choices
	var inst := 0.0
	for p in design.get("parts", []):
		inst += float(DB.part(p["id"]).get("instability", 0.05))
	var n_el: int = (design.get("elements", {}) as Dictionary).size()
	inst += maxf(0.0, n_el - 2) * 0.06
	return inst


static func make_offspring(a: Dictionary, b: Dictionary, rng: RandomNumberGenerator, design: Dictionary = {}, essences: Array = []) -> Dictionary:
	## Returns {genes, result, message}. result: success, surprise, loss, no_egg, defect, breakout
	var an := analyze(a, b, essences)
	var ga: Dictionary = a["genes"]
	var gb: Dictionary = b["genes"]
	var control := 0.15 * GameState.skill_rank("gen_control") + (0.15 if GameState.has_research("genetics_2") else 0.0)
	var g := {}
	var kind: String = an["kind"]
	var body_from: Dictionary = ga if design.get("body", "a") == "a" else gb
	var other: Dictionary = gb if body_from == ga else ga
	g["rig"] = body_from["rig"]
	g["family"] = body_from["family"]
	g["generation"] = maxi(int(ga.get("generation", 0)), int(gb.get("generation", 0))) + 1
	# mix fractions
	var mix := {}
	for k in ga["mix"]:
		mix[k] = float(mix.get(k, 0.0)) + float(ga["mix"][k]) * 0.5
	for k in gb["mix"]:
		mix[k] = float(mix.get(k, 0.0)) + float(gb["mix"][k]) * 0.5
	g["mix"] = mix
	if kind == "pure":
		g["species"] = ga["species"]
	else:
		g["species"] = "hybrid"
		g["body_species"] = _base_species(body_from)
		g["hybrid_name"] = design.get("species_name", hybrid_name(_base_species(body_from), _base_species(other)))
		# blended base stats with hybrid vigor
		var sa := base_stats(ga)
		var sb := base_stats(gb)
		var bs := {}
		for k in sa:
			if sb.has(k) and (sa[k] is float or sa[k] is int):
				bs[k] = lerpf(float(sa[k]), float(sb[k]), 0.4) * (1.08 if k in ["hp", "atk", "deff", "stam"] else 1.0)
			else:
				bs[k] = sa[k]
		# locomotion follows the body
		for k in ["spd", "walk", "swim", "fly", "carry"]:
			if sa.has(k) or sb.has(k):
				bs[k] = float(base_stats(body_from).get(k, bs.get(k, 0.0)))
		g["base_stats"] = bs
	# stat genes: pick parent per stat, control biases to better, small drift
	g["stats_q"] = {}
	for k in STAT_KEYS:
		var qa := float(ga["stats_q"].get(k, 0.5))
		var qb := float(gb["stats_q"].get(k, 0.5))
		var src: String = design.get("stats", {}).get(k, "")
		var v: float
		if src == "a":
			v = qa if rng.randf() < 0.55 + control else qb
		elif src == "b":
			v = qb if rng.randf() < 0.55 + control else qa
		else:
			var better := maxf(qa, qb)
			var worse := minf(qa, qb)
			v = better if rng.randf() < 0.5 + control * 0.6 else worse
		g["stats_q"][k] = clampf(v + rng.randfn(0.0, 0.04), 0.02, 0.99)
	# colors
	var cs: String = design.get("colors", "")
	if cs == "":
		cs = "a" if rng.randf() < 0.5 else "b"
	var csrc: Dictionary = ga if cs == "a" else gb
	g["colors"] = (csrc["colors"] as Dictionary).duplicate(true)
	if design.has("color_override"):
		g["colors"]["main"] = design["color_override"]
	g["pattern_type"] = design.get("pattern_type", (ga if rng.randf() < 0.5 else gb).get("pattern_type", 1))
	g["pattern_scale"] = lerpf(float(ga.get("pattern_scale", 1.0)), float(gb.get("pattern_scale", 1.0)), rng.randf())
	g["size"] = clampf(lerpf(float(ga.get("size", 1.0)), float(gb.get("size", 1.0)), rng.randf()) + rng.randfn(0.0, 0.02), 0.85, 1.15)
	g["body"] = {}
	for part in ["neck", "tail", "head", "legs"]:
		g["body"][part] = clampf(lerpf(float(ga.get("body", {}).get(part, 1.0)), float(gb.get("body", {}).get(part, 1.0)), rng.randf()) + rng.randfn(0, 0.015), 0.85, 1.15)
	# parts
	var parts: Array = []
	if design.has("parts"):
		parts = (design["parts"] as Array).duplicate(true)
	else:
		var pool: Array = (ga.get("parts", []) as Array) + (gb.get("parts", []) as Array)
		for p in pool:
			if rng.randf() < 0.5 + control * 0.3:
				var placed := place_part(g["family"], g["rig"], p["id"], parts)
				if not placed.is_empty():
					parts.append(placed)
	g["parts"] = parts
	# elements
	var els := {}
	if design.has("elements"):
		els = (design["elements"] as Dictionary).duplicate()
	else:
		for src2 in [ga, gb]:
			for e in src2.get("elements", {}):
				if rng.randf() < 0.6 + control * 0.3:
					els[e] = maxf(float(els.get(e, 0.0)), float(src2["elements"][e]) * rng.randf_range(0.8, 1.05))
	for ess in essences:
		var it := DB.item(ess)
		if it.has("element"):
			els[it["element"]] = minf(1.0, float(els.get(it["element"], 0.0)) + 0.35)
	while els.size() > 5:
		var weakest := ""
		var wv := 9.0
		for e in els:
			if els[e] < wv:
				wv = els[e]
				weakest = e
		els.erase(weakest)
	g["elements"] = els
	# abilities pool
	var pool2: Array = []
	for src3 in [ga, gb]:
		for ab in src3.get("abilities_pool", []):
			if not ab in pool2:
				pool2.append(ab)
	for p in parts:
		for ab in DB.part(p["id"]).get("abilities", []):
			if not ab in pool2:
				pool2.append(ab)
	if not els.is_empty() and not "breath" in pool2 and g["family"] in ["wyvern", "theropod", "quadruped", "mammal"]:
		pool2.append("breath")
	g["abilities_pool"] = pool2
	# inherited mutations (good ones 35%, bad ones 50%)
	g["mutations"] = []
	for src4 in [ga, gb]:
		for m in src4.get("mutations", []):
			if m == "alpha":
				continue
			var good: bool = MUTATIONS.get(m, {}).get("good", true)
			if rng.randf() < (0.35 if good else 0.5) and not m in g["mutations"]:
				g["mutations"].append(m)
	# monster essence -> visible monster traits
	if an.get("monster", false):
		if not "korrumpiert" in g["mutations"]:
			g["mutations"].append("korrumpiert")
		var mon := ""
		for e in essences:
			if DB.item(e).has("monster"):
				mon = DB.item(e)["monster"]
		var mp := place_part(g["family"], g["rig"], "bone_spikes", g["parts"])
		if not mp.is_empty():
			g["parts"].append(mp)
		var hp := place_part(g["family"], g["rig"], "horns_demon", g["parts"])
		if not hp.is_empty() and design.get("allow_horns", true):
			g["parts"].append(hp)
		els["shadow"] = maxf(float(els.get("shadow", 0.0)), 0.5)
		if mon != "":
			for ab in DB.species(mon).get("abilities", []):
				if not ab in g["abilities_pool"]:
					g["abilities_pool"].append(ab)
	var inst := (float(ga.get("instability", 0.0)) + float(gb.get("instability", 0.0))) * 0.5
	inst += {"pure": 0.0, "family": 0.08, "related": 0.16, "cross": 0.26}[kind]
	inst += design_instability({"parts": g["parts"].filter(func(p): return _is_foreign(g, p)) if g["species"] != "hybrid" else g["parts"], "elements": els})
	inst *= 1.0 - 0.15 * GameState.skill_rank("gen_stability")
	g["instability"] = clampf(inst, 0.0, 1.0)
	# roll outcome
	var risk: float = an["risk"] + design_instability(design) * 0.5
	var result := "success"
	var msg := ""
	var r := rng.randf()
	var surprise := 0.04 + 0.03 * GameState.skill_rank("gen_mutation")
	if r < risk:
		var o := rng.randf()
		var breakout_p := 0.0 if risk < 0.3 else (risk - 0.3) * 1.2
		if o < breakout_p:
			result = "breakout"
			msg = "Das Experiment gerät außer Kontrolle – die Kreatur bricht aggressiv aus!"
		elif o < 0.45:
			result = "loss"
			msg = "Fehlschlag: Die Materialien sind verbraucht, es entsteht kein Ei."
		elif o < 0.7:
			result = "no_egg"
			msg = "Ein Ei entsteht, doch es wird sich nicht entwickeln."
		else:
			result = "defect"
			var bad := ["bruechig", "kurzatmig", "lahm", "jaehzornig", "instabil"]
			g["mutations"].append(bad[rng.randi() % bad.size()])
			msg = "Erfolg mit Erbdefekt: %s (behandelbar)." % MUTATIONS[g["mutations"][-1]]["name"]
	elif rng.randf() < surprise:
		result = "surprise"
		var goods := ["robust", "kraftvoll", "gepanzert", "flink", "ausdauernd", "leuchtend", "riese"]
		var pick: String = goods[rng.randi() % goods.size()]
		if not pick in g["mutations"]:
			g["mutations"].append(pick)
		if rng.randf() < 0.35:
			_add_elemental(g, rng)
		msg = "Überraschungserfolg! Positive Mutation: %s." % MUTATIONS[pick]["name"]
	else:
		msg = "Erfolg! Ein gesundes Ei ist entstanden."
	return {"genes": g, "result": result, "message": msg, "risk": risk, "kind": kind}


static func place_part(family: String, rig: String, part_id: String, existing: Array) -> Dictionary:
	var pd := DB.part(part_id)
	if pd.is_empty():
		return {}
	if not family in pd.get("families", []):
		return {}
	var meta := RigLibrary.load_meta(rig)
	var used := {}
	for e in existing:
		used[e["socket"]] = true
	if pd.get("pair", false):
		if used.has("shoulder_L") or used.has("shoulder_R"):
			return {}
		if not meta["sockets"].has("shoulder_L"):
			return {}
		return {"id": part_id, "socket": "shoulder_L", "size": pd.get("size", 1.0), "pair": true}
	for s in pd.get("sockets", []):
		if meta["sockets"].has(s) and not used.has(s):
			return {"id": part_id, "socket": s, "size": pd.get("size", 1.0)}
	return {}


static func expand_parts(parts: Array) -> Array:
	## pair parts (wings) become two attachments
	var out := []
	for p in parts:
		if p.get("pair", false):
			out.append({"id": p["id"], "socket": "shoulder_L", "size": p.get("size", 1.0), "mirror": true, "align": "body"})
			out.append({"id": p["id"], "socket": "shoulder_R", "size": p.get("size", 1.0), "align": "body"})
		else:
			out.append(p)
	return out


static func hybrid_name(sa: String, sb: String) -> String:
	var na: String = DB.species(sa).get("name", sa)
	var nb: String = DB.species(sb).get("name", sb)
	var a := na.substr(0, maxi(3, int(na.length() * 0.5)))
	var b := nb.substr(int(nb.length() * 0.5))
	return (a + b).capitalize().replace(" ", "")


static func describe(g: Dictionary, insight: int = 3) -> String:
	var lines := []
	lines.append("Art: " + display_species(g) + ("  (Generation %d)" % g.get("generation", 0)))
	if g.get("species", "") == "hybrid":
		var parts := []
		for k in g["mix"]:
			parts.append("%s %d%%" % [DB.species(k).get("name", k), int(round(float(g["mix"][k]) * 100))])
		lines.append("Erbanteile: " + ", ".join(parts))
	if insight >= 1:
		var st := []
		for k in STAT_KEYS:
			st.append("%s %d%%" % [STAT_NAMES[k], int(float(g["stats_q"].get(k, 0.5)) * 100)])
		lines.append("Gene: " + ", ".join(st))
	var els := []
	for e in g.get("elements", {}):
		els.append("%s %d%%" % [DB.element(e).get("name", e), int(float(g["elements"][e]) * 100)])
	if not els.is_empty():
		lines.append("Elemente: " + ", ".join(els))
	var muts := []
	for m in g.get("mutations", []):
		if insight >= 3 or MUTATIONS.get(m, {}).get("good", true):
			muts.append(MUTATIONS.get(m, {}).get("name", m))
	if not muts.is_empty():
		lines.append("Mutationen: " + ", ".join(muts))
	var pts := []
	for p in g.get("parts", []):
		pts.append(DB.part(p["id"]).get("name", p["id"]))
	if not pts.is_empty():
		lines.append("Merkmale: " + ", ".join(pts))
	lines.append("Instabilität: %d%%" % int(float(g.get("instability", 0.0)) * 100))
	return "\n".join(lines)
