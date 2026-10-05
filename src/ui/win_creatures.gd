class_name WinCreatures
extends UIWindow
## Tamed creatures: filter/search/sort/favorites, details, abilities, element slots, commands & management.

var filter := "party"
var search := ""
var sort_by := "level"
var selected_uid := -1
var list_box: VBoxContainer
var detail: VBoxContainer


func _init(uid: int = -1) -> void:
	super._init("Kreaturen", Vector2(1200, 720))
	window_id = "creatures"
	selected_uid = uid
	if uid >= 0:
		filter = "all"
	var top := UIK.hbox(6)
	content.add_child(top)
	for f in [["Gefolge", "party"], ["Seelenkristall", "crystal"], ["Lager", "base"], ["Favoriten", "fav"], ["Alle", "all"], ["Verstorben", "dead"]]:
		top.add_child(UIK.button(f[0], func():
			filter = f[1]
			refresh()))
	var le := LineEdit.new()
	le.placeholder_text = "Name/Art suchen …"
	le.custom_minimum_size = Vector2(180, 0)
	le.text_changed.connect(func(t):
		search = t.to_lower()
		refresh())
	top.add_child(le)
	for s in [["Stufe", "level"], ["Name", "name"], ["Art", "species"], ["Bindung", "bond"]]:
		top.add_child(UIK.button("↕" + s[0], func():
			sort_by = s[1]
			refresh()))
	var cols := UIK.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var sc := UIK.scroll(Vector2(380, 560))
	cols.add_child(sc[0])
	list_box = sc[1]
	var sc2 := UIK.scroll(Vector2(760, 560))
	cols.add_child(sc2[0])
	detail = sc2[1]


func refresh() -> void:
	if list_box == null:
		return
	UIK.clear(list_box)
	var cap := "Gefolge %d/%d · Kristall %.1f/%.1f · Lager %.1f/%.1f" % [GameState.state["party"].size(), GameState.party_limit(), GameState.crystal_used(), GameState.crystal_capacity(), GameState.base_used(), GameState.base_capacity()]
	list_box.add_child(UIK.label(cap, 13, UIK.DIM, true))
	var all := GameState.all_creatures().filter(func(c):
		if filter == "fav":
			return c.get("favorite", false) and c["status"] != "dead"
		if filter == "all":
			return c["status"] != "dead"
		return c["status"] == filter)
	if search != "":
		all = all.filter(func(c): return c["name"].to_lower().contains(search) or Creatures.display_species(c).to_lower().contains(search))
	match sort_by:
		"level":
			all.sort_custom(func(a, b): return int(a["level"]) > int(b["level"]))
		"name":
			all.sort_custom(func(a, b): return a["name"] < b["name"])
		"species":
			all.sort_custom(func(a, b): return Creatures.display_species(a) < Creatures.display_species(b))
		"bond":
			all.sort_custom(func(a, b): return float(a["bond"]) > float(b["bond"]))
	for c in all:
		var txt := "%s%s – %s St. %d (%s)" % ["★ " if c.get("favorite", false) else "", c["name"], Creatures.display_species(c), c["level"], Creatures.status_label(c["status"])]
		var b := UIK.button(txt, func():
			selected_uid = int(c["uid"])
			refresh())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		if int(c["uid"]) == selected_uid:
			b.add_theme_color_override("font_color", UIK.GOLD)
		list_box.add_child(b)
	if all.is_empty():
		list_box.add_child(UIK.label("Keine Kreaturen in dieser Ansicht.", 15, UIK.DIM))
	_detail()


func _detail() -> void:
	UIK.clear(detail)
	var c := GameState.creature(selected_uid)
	if c.is_empty():
		detail.add_child(UIK.label("Wähle eine Kreatur.", 16, UIK.DIM))
		return
	var w := get_tree().get_first_node_in_group("world") as World
	var node: Creature = null
	for n in get_tree().get_nodes_in_group("companions"):
		if n.uid == selected_uid:
			node = n
	var head := UIK.hbox(8)
	var le := LineEdit.new()
	le.text = c["name"]
	le.custom_minimum_size = Vector2(220, 0)
	le.text_submitted.connect(func(t):
		c["name"] = t.strip_edges() if t.strip_edges() != "" else c["name"]
		refresh())
	head.add_child(le)
	head.add_child(UIK.button("Umbenennen", func():
		c["name"] = le.text.strip_edges() if le.text.strip_edges() != "" else c["name"]
		refresh()))
	head.add_child(UIK.button("★ Favorit" if not c.get("favorite", false) else "☆ Kein Favorit", func():
		c["favorite"] = not c.get("favorite", false)
		refresh()))
	detail.add_child(head)
	var st := Creatures.stats(c)
	var sp := Creatures.species_def(c)
	detail.add_child(UIK.label("%s · Stufe %d (%d/%d EP) · %s · %s" % [Creatures.display_species(c), c["level"], c["xp"], Creatures.xp_needed(c["level"]), "männlich" if c["sex"] == "m" else "weiblich", Creatures.status_label(c["status"])], 16, UIK.TEXT, true))
	if c["status"] == "dead":
		detail.add_child(UIK.label("✝ %s (Tag %d). Gefallene Gefährten kehren nicht zurück." % [c.get("death_cause", ""), c.get("death_day", 0)], 15, UIK.RED, true))
	var hp_now := float(node.combatant.hp) if node else float(c["hp"])
	detail.add_child(UIK.label("Leben %d/%d · Angriff %d · Verteidigung %d · Tempo %.1f m/s · Ausdauer %d · Traglast %d kg" % [hp_now, st["hp"], st["atk"], st["deff"], st["spd"], st["stam"], st["carry"]], 15, UIK.TEXT, true))
	if float(st.get("fly", 0)) > 0:
		detail.add_child(UIK.label("Flug: %.1f m/s" % st["fly"], 14, UIK.BLUE))
	if float(st.get("swim", 0)) > 0:
		detail.add_child(UIK.label("Schwimmen: %.1f m/s" % st["swim"], 14, UIK.BLUE))
	var pers: Dictionary = Creatures.PERSONALITIES.get(c["personality"], {})
	detail.add_child(UIK.label("Bindung: %s (%d) · Persönlichkeit: %s – %s · Hunger %d%%" % [Creatures.bond_label(float(c["bond"])), int(c["bond"]), pers.get("name", ""), pers.get("desc", ""), int(c.get("hunger", 80))], 14, UIK.TEXT, true))
	var likes := Array(c.get("likes", [])).map(func(l): return Creatures.LIKES.get(l, DB.item_name(l)))
	var fears := Array(c.get("fears", [])).map(func(f): return Creatures.FEARS.get(f, f))
	detail.add_child(UIK.label("Mag: %s · Fürchtet: %s" % [", ".join(likes), ", ".join(fears)], 14, UIK.DIM, true))
	if not c.get("injuries", []).is_empty():
		detail.add_child(UIK.label("Verletzungen: " + ", ".join(c["injuries"]) + " (Tiermedizin / Krankenstation)", 14, UIK.RED, true))
	if not c.get("parent_names", []).is_empty():
		detail.add_child(UIK.label("Eltern: " + " × ".join(c["parent_names"]) + " · Generation %d" % c.get("generation", 0), 14, UIK.DIM))
	detail.add_child(UIK.sep())
	detail.add_child(UIK.label("Gene", 18, UIK.GOLD))
	detail.add_child(UIK.label(Genetics.describe(c["genes"], 1 + GameState.skill_rank("gen_insight")), 14, UIK.TEXT, true))
	# abilities
	detail.add_child(UIK.sep())
	var slots := Creatures.ability_slots(c)
	detail.add_child(UIK.label("Fähigkeiten (%d/%d Plätze)" % [c["abilities"].size(), slots], 18, UIK.GOLD))
	var pool: Array = c["genes"].get("abilities_pool", [])
	var ab_row := HFlowContainer.new()
	for ab in pool:
		var on: bool = ab in c["abilities"]
		var ad := DB.ability(ab)
		var b := UIK.button(("✔ " if on else "") + ad.get("name", ab), func():
			if on:
				c["abilities"].erase(ab)
			elif c["abilities"].size() < slots:
				c["abilities"].append(ab)
			else:
				EventBus.notify.emit("Alle Fähigkeitsplätze belegt (mehr ab Stufe 5/15/30).", "warn")
			refresh(), ad.get("desc", ""))
		ab_row.add_child(b)
	detail.add_child(ab_row)
	# element slots
	var els: Dictionary = c["genes"].get("elements", {})
	if not els.is_empty():
		detail.add_child(UIK.sep())
		detail.add_child(UIK.label("Elementplätze (3) – Klick fügt Element hinzu/entfernt es", 18, UIK.GOLD))
		for si in 3:
			var slot: Array = c["element_slots"][si]
			var row := UIK.hbox(4)
			row.add_child(UIK.label("Platz %d:" % (si + 1), 14, UIK.DIM))
			for e in els:
				var on2: bool = e in slot
				row.add_child(UIK.button(("● " if on2 else "○ ") + DB.element(e).get("name", e), func():
					var trial: Array = slot.duplicate()
					if on2:
						trial.erase(e)
					else:
						trial.append(e)
					var ok := Creatures.element_slot_ok(c, trial)
					if ok["ok"] or trial.size() < slot.size():
						c["element_slots"][si] = trial
					else:
						EventBus.notify.emit(ok["why"], "warn")
					refresh()))
			if slot.size() > 1:
				var mix: Dictionary = DB.t("mixture").get(str(slot.size()), {})
				row.add_child(UIK.label("Mischung: Wirkung %d%%, Ausdauer ×%.2f" % [int(float(mix.get("potency", 1)) * 100), float(mix.get("stamina", 1))], 13, Color(0.9, 0.7, 0.4)))
			detail.add_child(row)
	# management
	detail.add_child(UIK.sep())
	var acts := HFlowContainer.new()
	detail.add_child(acts)
	if c["status"] == "dead":
		return
	match c["status"]:
		"crystal":
			acts.add_child(UIK.button("Beschwören", func():
				if w.summon_from_crystal(selected_uid):
					refresh()))
			acts.add_child(UIK.button("Ins Lager schicken", func():
				if w.send_to_base(selected_uid):
					refresh()))
		"party":
			acts.add_child(UIK.button("In Seelenkristall", func():
				if w.store_in_crystal(selected_uid):
					refresh()))
			acts.add_child(UIK.button("Ins Lager schicken", func():
				if w.send_to_base(selected_uid):
					refresh()))
		"base":
			acts.add_child(UIK.button("Ins Gefolge holen", func():
				if w.take_from_base(selected_uid):
					refresh()))
			acts.add_child(UIK.button("Trainieren (1 Std., Futter)", func(): _train(c)))
	var inv: Array = GameState.player()["inventory"]
	var saddle := Creatures.saddle_for(c)
	if Creatures.species_def(c).get("rideable", false) and not c.get("saddle", false):
		acts.add_child(UIK.button("Sattel anlegen (%s)" % DB.item_name(saddle), func():
			if Inventory.count(inv, saddle) > 0:
				Inventory.remove(inv, saddle, 1)
				c["saddle"] = true
				if node:
					node.refresh_from_record()
				EventBus.notify.emit("Sattel angelegt.", "good")
			else:
				EventBus.notify.emit("Du brauchst: " + DB.item_name(saddle), "warn")
			refresh()))
	acts.add_child(UIK.button("Füttern", func():
		var fed := false
		for f in Creatures.species_def(c).get("food", []) + ["kibble"]:
			if Inventory.count(inv, f) > 0:
				Inventory.remove(inv, f, 1)
				c["hunger"] = minf(100.0, float(c.get("hunger", 50)) + 40.0)
				Creatures.add_bond(c, 2.0 if f in c.get("likes", []) or f == "kibble" else 0.5)
				EventBus.notify.emit("%s frisst %s." % [c["name"], DB.item_name(f)], "info")
				fed = true
				break
		if not fed:
			EventBus.notify.emit("Kein passendes Futter.", "warn")
		refresh()))
	acts.add_child(UIK.button("Streicheln", func():
		Creatures.add_bond(c, 1.5)
		EventBus.notify.emit("%s genießt die Zuwendung." % c["name"], "info")
		refresh()))
	for med in [["creature_medicine", "Tiermedizin geben"], ["purify_tonic", "Reinigungstrank"], ["gene_stabilizer", "Genstabilisator"]]:
		if Inventory.count(inv, med[0]) > 0:
			acts.add_child(UIK.button(med[1], func(): _medicine(c, med[0], node)))
	var aggr: String = c.get("aggression", "defensive")
	acts.add_child(UIK.button("Haltung: %s" % {"passive": "Passiv", "defensive": "Verteidigend", "aggressive": "Aggressiv"}[aggr], func():
		c["aggression"] = {"passive": "defensive", "defensive": "aggressive", "aggressive": "passive"}[aggr]
		refresh()))
	acts.add_child(UIK.button("Freilassen", func():
		ui.show_choice("Freilassen?", "%s wird in die Wildnis entlassen. Dies kann nicht rückgängig gemacht werden." % c["name"], [
			{"text": "Ja, freilassen", "cb": func():
				if node:
					node.queue_free()
				GameState.state["creatures"].erase(str(selected_uid))
				GameState.state["party"].erase(selected_uid)
				GameState.state["crystal"].erase(selected_uid)
				selected_uid = -1
				refresh()},
			{"text": "Abbrechen", "cb": func(): pass}])))


func _train(c: Dictionary) -> void:
	var inv: Array = GameState.player()["inventory"]
	var store := Settlement._storage()
	var food := ""
	for f in Creatures.species_def(c).get("food", []) + ["kibble"]:
		if Inventory.count(inv, f) > 0 or Inventory.count(store, f) > 0:
			food = f
			break
	if food == "":
		EventBus.notify.emit("Training benötigt Futter (im Inventar oder Lager).", "warn")
		return
	if Inventory.count(inv, food) > 0:
		Inventory.remove(inv, food, 1)
	else:
		Inventory.remove(store, food, 1)
	var keys := ["hp", "atk", "deff", "spd", "stam"]
	var k: String = keys[randi() % keys.size()]
	c["trained"][k] = int(c["trained"].get(k, 0)) + 1
	Creatures.add_xp(c, 80.0)
	Creatures.add_bond(c, 1.0)
	GameState.skip_hours(1.0)
	# training can cure behavioural/breathing defects
	for m in ["kurzatmig", "jaehzornig"]:
		if m in c["genes"]["mutations"] and randf() < 0.25:
			c["genes"]["mutations"].erase(m)
			EventBus.notify.emit("%s hat den Erbdefekt „%s“ überwunden!" % [c["name"], Genetics.MUTATIONS[m]["name"]], "good")
	EventBus.notify.emit("%s trainiert: %s +2%%." % [c["name"], Genetics.STAT_NAMES[k]], "good")
	refresh()


func _medicine(c: Dictionary, item: String, node: Creature) -> void:
	var inv: Array = GameState.player()["inventory"]
	Inventory.remove(inv, item, 1)
	match item:
		"creature_medicine":
			c["injuries"] = []
			c["hp"] = Creatures.stats(c)["hp"]
			if node:
				node.combatant.heal(node.combatant.max_hp)
			for m in ["bruechig", "lahm"]:
				if m in c["genes"]["mutations"] and randf() < 0.35:
					c["genes"]["mutations"].erase(m)
					EventBus.notify.emit("Defekt geheilt: " + Genetics.MUTATIONS[m]["name"], "good")
		"purify_tonic":
			var bad := Array(c["genes"]["mutations"]).filter(func(m): return not Genetics.MUTATIONS.get(m, {}).get("good", true))
			if not bad.is_empty():
				c["genes"]["mutations"].erase(bad[0])
				EventBus.notify.emit("Reinigung: „%s“ entfernt." % Genetics.MUTATIONS[bad[0]]["name"], "good")
			else:
				EventBus.notify.emit("Keine negativen Erbmerkmale vorhanden.", "info")
		"gene_stabilizer":
			c["genes"]["instability"] = maxf(0.0, float(c["genes"].get("instability", 0.0)) - 0.2)
			c["genes"]["mutations"].erase("instabil")
			EventBus.notify.emit("Instabilität gesenkt.", "good")
	EventBus.inventory_changed.emit()
	if node:
		node.refresh_from_record()
	refresh()
