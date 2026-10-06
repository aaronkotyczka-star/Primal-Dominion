class_name WinGeneLab
extends UIWindow
## Gene lab: pick parents, essences, auto or manual hybrid design, risk preview, results log, recipes, pedigree.

var a_uid := -1
var b_uid := -1
var essences: Array = []
var manual := false
var design := {}
var tab := "breed"
var left: VBoxContainer
var right: VBoxContainer
var rng := RandomNumberGenerator.new()


func _init() -> void:
	super._init("Genlabor", Vector2(1260, 740))
	window_id = "genelab"
	rng.randomize()
	var tabs := UIK.hbox(6)
	content.add_child(tabs)
	for t in [["Kreuzung", "breed"], ["Rezepte", "recipes"], ["Versuchsprotokoll", "log"], ["Stammbäume", "tree"]]:
		tabs.add_child(UIK.button(t[0], func():
			tab = t[1]
			refresh()))
	var cols := UIK.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var sc := UIK.scroll(Vector2(420, 600))
	cols.add_child(sc[0])
	left = sc[1]
	var sc2 := UIK.scroll(Vector2(780, 600))
	cols.add_child(sc2[0])
	right = sc2[1]


func _candidates() -> Array:
	return GameState.all_creatures().filter(func(c): return c["status"] in ["base", "party"] and float(c.get("growth", 1.0)) >= 0.99)


func refresh() -> void:
	if left == null:
		return
	UIK.clear(left)
	UIK.clear(right)
	match tab:
		"breed":
			_breed()
		"recipes":
			for r in GameState.state["hybrid"]["recipes"]:
				left.add_child(UIK.button("%s (%s × %s)" % [r["name"], r["a_name"], r["b_name"]], func():
					a_uid = int(r["a"])
					b_uid = int(r["b"])
					design = (r["design"] as Dictionary).duplicate(true)
					manual = not design.is_empty()
					essences = (r["essences"] as Array).duplicate()
					tab = "breed"
					refresh()))
			if GameState.state["hybrid"]["recipes"].is_empty():
				left.add_child(UIK.label("Noch keine gespeicherten Kreuzungsrezepte.", 15, UIK.DIM, true))
		"log":
			for e in GameState.state["hybrid"]["experiments"]:
				right.add_child(UIK.label("Tag %d: %s × %s → %s" % [e["day"], e["a"], e["b"], e["msg"]], 14, UIK.TEXT, true))
			if GameState.state["hybrid"]["experiments"].is_empty():
				right.add_child(UIK.label("Noch keine Versuche.", 15, UIK.DIM))
		"tree":
			for c in GameState.all_creatures():
				if int(c.get("generation", 0)) > 0:
					var txt := "%s (%s, Gen. %d) ← %s" % [c["name"], Creatures.display_species(c), c["generation"], " × ".join(c.get("parent_names", []))]
					for pid in c.get("parents", []):
						var pr := GameState.creature(pid)
						if not pr.is_empty() and not pr.get("parent_names", []).is_empty():
							txt += "\n      %s ← %s" % [pr["name"], " × ".join(pr["parent_names"])]
					right.add_child(UIK.label(txt, 14, UIK.TEXT, true))


func _pick(label: String, cur: int, cb: Callable) -> void:
	left.add_child(UIK.label(label, 17, UIK.GOLD))
	for c in _candidates():
		var b := UIK.button("%s – %s St.%d%s" % [c["name"], Creatures.display_species(c), c["level"], " ♂" if c["sex"] == "m" else " ♀"], func(): cb.call(int(c["uid"])))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if int(c["uid"]) == cur:
			b.add_theme_color_override("font_color", UIK.GOLD)
		left.add_child(b)


func _breed() -> void:
	_pick("Elterntier A", a_uid, func(u):
		a_uid = u
		design = {}
		refresh())
	_pick("Elterntier B", b_uid, func(u):
		b_uid = u
		design = {}
		refresh())
	left.add_child(UIK.label("Essenzen (optional)", 17, UIK.GOLD))
	var inv: Array = GameState.player()["inventory"]
	for st in inv:
		var it := DB.item(st["id"])
		if it.get("cat", "") == "essence" and (it.has("element") or it.has("monster") or st["id"] == "demon_essence"):
			var on: bool = st["id"] in essences
			left.add_child(UIK.button(("✔ " if on else "") + it["name"] + " ×%d" % st["n"], func():
				if on:
					essences.erase(st["id"])
				elif essences.size() < 3:
					essences.append(st["id"])
				refresh(), it.get("desc", "")))
	var a := GameState.creature(a_uid)
	var b := GameState.creature(b_uid)
	if a.is_empty() or b.is_empty():
		right.add_child(UIK.label("Wähle zwei Elterntiere (im Lager oder Gefolge, ausgewachsen).", 16, UIK.DIM, true))
		right.add_child(UIK.label("Grundregeln:\n• Gleiche Art: reine Zucht, geringes Risiko.\n• Gleiche Körperfamilie: Hybride (Genetik).\n• Verwandte Familien: Chimärenforschung.\n• Fremde Familien: Chimärenforschung + Fähigkeit „Chimärenkunde“.\n• Monsteressenzen: Monstergenetik – sichtbare Monster-Hybriden.\n• Bis zu 5 Elementbestandteile pro Genprofil.", 15, UIK.TEXT, true))
		return
	var an := Genetics.analyze(a, b, essences)
	var kind_name: String = {"pure": "Reine Zucht", "family": "Hybride (gleiche Körperfamilie)", "related": "Chimäre (verwandte Familien)", "cross": "Chimäre (fremde Familien)"}[an["kind"]]
	right.add_child(UIK.label("%s × %s" % [a["name"], b["name"]], 22, UIK.GOLD))
	right.add_child(UIK.label("Art der Kreuzung: " + kind_name + ("  +  Monsteressenz" if an.get("monster", false) else ""), 16))
	for r in an["reasons"]:
		right.add_child(UIK.label("✖ " + r, 15, UIK.RED, true))
	var cost := _cost(an)
	var cost_txt := []
	var cost_ok := true
	for k in cost:
		var have := Inventory.count(inv, k)
		cost_txt.append("%d× %s (%d)" % [cost[k], DB.item_name(k), have])
		if have < int(cost[k]):
			cost_ok = false
	right.add_child(UIK.label("Kosten: " + ", ".join(cost_txt), 15, UIK.TEXT if cost_ok else UIK.RED, true))
	# manual editor
	var can_manual = GameState.has_research("genetics_2") and an["kind"] != "pure"
	if can_manual:
		var mh := UIK.hbox(6)
		mh.add_child(UIK.button("Automatisch" + (" ✔" if not manual else ""), func():
			manual = false
			refresh()))
		mh.add_child(UIK.button("Manueller Editor" + (" ✔" if manual else ""), func():
			manual = true
			refresh()))
		right.add_child(mh)
	elif an["kind"] != "pure":
		right.add_child(UIK.label("Manueller Editor: Forschung „Vererbungslehre“ nötig.", 13, UIK.DIM))
	if manual and can_manual:
		_editor(a, b)
	var risk := float(an["risk"]) + Genetics.design_instability(design) * 0.5 if manual else float(an["risk"])
	right.add_child(UIK.sep())
	right.add_child(UIK.label("Risiko: %d%%" % int(risk * 100), 20, Color(1.0, 0.45, 0.35) if risk > 0.3 else (Color(1.0, 0.8, 0.4) if risk > 0.12 else UIK.GREEN)))
	var outs := Genetics.risk_outcomes(risk)
	for k in outs:
		right.add_child(UIK.label("  %s: %d%%" % [k, int(float(outs[k]) * 100)], 14, UIK.DIM))
	right.add_child(UIK.label("Vorschau der Erbanlagen:\n" + _preview_text(a, b), 14, UIK.TEXT, true))
	var bh := UIK.hbox(8)
	var start := UIK.button("Experiment starten", func(): _start(a, b, an, cost))
	start.disabled = not an["ok"] or not cost_ok
	bh.add_child(start)
	bh.add_child(UIK.button("Als Rezept speichern", func():
		GameState.state["hybrid"]["recipes"].append({"name": design.get("species_name", Genetics.hybrid_name(Genetics._base_species(a["genes"]), Genetics._base_species(b["genes"]))), "a": a_uid, "b": b_uid, "a_name": a["name"], "b_name": b["name"], "design": design.duplicate(true), "essences": essences.duplicate()})
		EventBus.notify.emit("Kreuzungsrezept gespeichert.", "good")))
	right.add_child(bh)


func _cost(an: Dictionary) -> Dictionary:
	var c := {}
	match an["kind"]:
		"pure":
			c = {"raw_meat": 4} if Creatures.species_def(GameState.creature(a_uid)).get("diet", "") != "herbivore" else {"veggies": 4}
		"family":
			c = {"crystal": 1, "elemental_essence": 2}
		_:
			c = {"crystal": 2, "elemental_essence": 3, "blood_crystal": 1}
	for e in essences:
		c[e] = int(c.get(e, 0)) + 1
	return c


func _editor(a: Dictionary, b: Dictionary) -> void:
	var ga: Dictionary = a["genes"]
	var gb: Dictionary = b["genes"]
	right.add_child(UIK.label("Manueller Editor", 18, UIK.GOLD))
	var row := UIK.hbox(4)
	row.add_child(UIK.label("Grundkörper:", 14))
	for src in [["a", a], ["b", b]]:
		row.add_child(UIK.button(("● " if design.get("body", "a") == src[0] else "○ ") + Creatures.display_species(src[1]), func():
			design["body"] = src[0]
			design.erase("parts")
			refresh()))
	right.add_child(row)
	for k in Genetics.STAT_KEYS:
		var r2 := UIK.hbox(4)
		r2.add_child(UIK.label("%s:" % Genetics.STAT_NAMES[k], 14))
		var cur: String = design.get("stats", {}).get(k, "")
		for src2 in [["a", "%s %d%%" % [a["name"], int(ga["stats_q"][k] * 100)]], ["b", "%s %d%%" % [b["name"], int(gb["stats_q"][k] * 100)]], ["", "Zufall/Bestes"]]:
			r2.add_child(UIK.button(("● " if cur == src2[0] else "○ ") + src2[1], func():
				if not design.has("stats"):
					design["stats"] = {}
				design["stats"][k] = src2[0]
				refresh()))
		right.add_child(r2)
	var rc := UIK.hbox(4)
	rc.add_child(UIK.label("Färbung:", 14))
	for src3 in [["a", a["name"]], ["b", b["name"]]]:
		rc.add_child(UIK.button(("● " if design.get("colors", "a") == src3[0] else "○ ") + src3[1], func():
			design["colors"] = src3[0]
			refresh()))
	rc.add_child(UIK.label("Muster:", 14))
	for pt in [[0, "keins"], [1, "Streifen"], [2, "Flecken"], [3, "Bänder"], [4, "Marmor"]]:
		rc.add_child(UIK.button(("● " if int(design.get("pattern_type", ga.get("pattern_type", 1))) == pt[0] else "○ ") + pt[1], func():
			design["pattern_type"] = pt[0]
			refresh()))
	right.add_child(rc)
	# parts
	var body_g: Dictionary = ga if design.get("body", "a") == "a" else gb
	var fam: String = body_g["family"]
	var rig: String = body_g["rig"]
	var pool := []
	for p in (ga.get("parts", []) as Array) + (gb.get("parts", []) as Array):
		if not p["id"] in pool:
			pool.append(p["id"])
	for pid in DB.t("parts"):
		var pd := DB.part(pid)
		if pd.get("monster", false) and not essences.any(func(e): return DB.item(e).has("monster") or e == "demon_essence"):
			continue
		if pd.has("research") and not GameState.has_research(pd["research"]):
			continue
		if pid in ["wing_membrane", "wing_feather"] and not pid in pool:
			pool.append(pid)
	if not design.has("parts"):
		var init := []
		for p in body_g.get("parts", []):
			init.append(p)
		design["parts"] = init
	right.add_child(UIK.label("Körperteile (nur zur Körperfamilie passende werden befestigt):", 14, UIK.DIM))
	var pf := HFlowContainer.new()
	for pid in pool:
		var pd2 := DB.part(pid)
		var on := (design["parts"] as Array).any(func(p): return p["id"] == pid)
		var fits: bool = fam in pd2.get("families", [])
		var bt := UIK.button(("✔ " if on else "") + pd2.get("name", pid) + ("" if fits else " (passt nicht)"), func():
			if on:
				design["parts"] = (design["parts"] as Array).filter(func(p): return p["id"] != pid)
			else:
				var placed := Genetics.place_part(fam, rig, pid, design["parts"])
				if placed.is_empty():
					EventBus.notify.emit("Kein freier, passender Befestigungspunkt.", "warn")
				else:
					design["parts"].append(placed)
			refresh(), "Instabilität +%d%%" % int(float(pd2.get("instability", 0.05)) * 100))
		bt.disabled = not fits
		pf.add_child(bt)
	right.add_child(pf)
	# elements
	var els_pool := {}
	for g in [ga, gb]:
		for e in g.get("elements", {}):
			els_pool[e] = maxf(float(els_pool.get(e, 0.0)), float(g["elements"][e]))
	for es in essences:
		if DB.item(es).has("element"):
			els_pool[DB.item(es)["element"]] = 0.4
	if not els_pool.is_empty():
		if not design.has("elements"):
			design["elements"] = els_pool.duplicate()
		var ef := HFlowContainer.new()
		ef.add_child(UIK.label("Elemente (max. 5):", 14))
		for e in els_pool:
			var on3: bool = (design["elements"] as Dictionary).has(e)
			ef.add_child(UIK.button(("✔ " if on3 else "") + DB.element(e).get("name", e), func():
				if on3:
					design["elements"].erase(e)
				elif design["elements"].size() < 5:
					design["elements"][e] = els_pool[e]
				refresh()))
		right.add_child(ef)
	var nr := UIK.hbox(4)
	nr.add_child(UIK.label("Artname:", 14))
	var le := LineEdit.new()
	le.text = design.get("species_name", Genetics.hybrid_name(Genetics._base_species(ga if design.get("body", "a") == "a" else gb), Genetics._base_species(gb if design.get("body", "a") == "a" else ga)))
	le.custom_minimum_size = Vector2(200, 0)
	le.text_changed.connect(func(t): design["species_name"] = t)
	nr.add_child(le)
	right.add_child(nr)
	right.add_child(UIK.label("Design-Instabilität: +%d%%" % int(Genetics.design_instability(design) * 100), 14, Color(1.0, 0.75, 0.4)))


func _preview_text(a: Dictionary, b: Dictionary) -> String:
	var lines := []
	var ins := GameState.skill_rank("gen_insight")
	for k in Genetics.STAT_KEYS:
		var qa := float(a["genes"]["stats_q"][k])
		var qb := float(b["genes"]["stats_q"][k])
		if ins >= 2:
			var ctrl := 0.15 * GameState.skill_rank("gen_control") + (0.15 if GameState.has_research("genetics_2") else 0.0)
			lines.append("%s: %d%% oder %d%% (besseres zu %d%%)" % [Genetics.STAT_NAMES[k], int(qa * 100), int(qb * 100), int((0.5 + ctrl * 0.6) * 100)])
		else:
			lines.append("%s: zwischen %d%% und %d%%" % [Genetics.STAT_NAMES[k], int(minf(qa, qb) * 100), int(maxf(qa, qb) * 100)])
	return "\n".join(lines)


func _start(a: Dictionary, b: Dictionary, an: Dictionary, cost: Dictionary) -> void:
	var inv: Array = GameState.player()["inventory"]
	for k in cost:
		Inventory.remove(inv, k, int(cost[k]))
	var res := Genetics.make_offspring(a, b, rng, design if manual else {}, essences)
	var log := {"day": GameState.get_day(), "a": a["name"], "b": b["name"], "msg": res["message"], "result": res["result"]}
	GameState.state["hybrid"]["experiments"].push_front(log)
	essences = []
	var w := get_tree().get_first_node_in_group("world")
	match res["result"]:
		"loss":
			ui.show_text("Fehlschlag", res["message"])
		"breakout":
			ui.show_text("Ausbruch!", res["message"])
			if w:
				var sp: String = res["genes"].get("body_species", res["genes"].get("species", "raptor"))
				var c: Creature = w.spawn_wild(sp, maxi(int(a["level"]), int(b["level"])) + 3, w.player.global_position + w.player.get_forward() * 6.0, {})
				if c:
					c.rec["genes"] = res["genes"]
					c.combatant.add_buff("wut", {"dmg": 1.3, "speed": 1.2, "dur": 120.0})
					c.ai.target = w.player
					c.ai._go("chase", 60.0)
		_:
			var genes: Dictionary = res["genes"]
			var nm: String = genes.get("hybrid_name", DB.species(genes.get("species", "")).get("name", "")) + "-Ei"
			Inventory.add(inv, "egg", 1, 1.0, {"name": nm, "genes": genes, "species": genes.get("species", "hybrid"), "parents": [a_uid, b_uid],
				"parent_names": [a["name"], b["name"]], "dud": res["result"] == "no_egg", "hybrid_label": genes.get("hybrid_name", "")})
			ui.show_text("Ergebnis", res["message"] + "\n\nDas Ei liegt in deinem Inventar. Lege es in eine Brutstätte.")
			GameState.add_xp(60, "hybrid")
			Research.add_points(1)
	EventBus.inventory_changed.emit()
	refresh()
