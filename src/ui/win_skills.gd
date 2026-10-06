class_name WinSkills
extends UIWindow
## 12 skill trees, active loadout (4 slots), respec info, demon skills when unlocked.

var tree_id := "melee"
var left: VBoxContainer
var right: VBoxContainer


func _init() -> void:
	super._init("Fähigkeiten", Vector2(1150, 700))
	window_id = "skills"
	var cols := UIK.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	left = UIK.vbox(4)
	left.custom_minimum_size = Vector2(250, 0)
	cols.add_child(left)
	var sc := UIK.scroll(Vector2(840, 580))
	cols.add_child(sc[0])
	right = sc[1]


func refresh() -> void:
	if left == null:
		return
	UIK.clear(left)
	UIK.clear(right)
	var p := GameState.player()
	left.add_child(UIK.label("Punkte: %d" % p["skill_points"], 20, UIK.GOLD))
	for t in DB.t("skill_trees"):
		var b := UIK.button(DB.t("skill_trees")[t], func():
			tree_id = t
			refresh())
		if t == tree_id:
			b.add_theme_color_override("font_color", UIK.GOLD)
		left.add_child(b)
	if p["demon"].get("unlocked", false):
		var db := UIK.button("Dämonische Kräfte", func():
			tree_id = "demon"
			refresh())
		db.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
		left.add_child(db)
	left.add_child(UIK.sep())
	left.add_child(UIK.label("Neuverteilung: %d Bernstein bei Ilsa oder Trank des Vergessens." % Skills.respec_cost(), 13, UIK.DIM, true))
	# loadout
	right.add_child(UIK.label("Aktive Ausstattung (R / F / G / Z)", 18, UIK.GOLD))
	var lo: Array = p["loadout"]
	var known := Skills.known_actives()
	for i in 4:
		var row := UIK.hbox(4)
		row.add_child(UIK.label("Platz %d: %s" % [i + 1, DB.ability(lo[i]).get("name", "—") if lo[i] != "" else "—"], 15))
		for ab in known:
			row.add_child(UIK.button(DB.ability(ab).get("name", ab), func():
				Skills.set_loadout(i, ab)
				refresh(), DB.ability(ab).get("desc", "")))
		row.add_child(UIK.button("leeren", func():
			Skills.set_loadout(i, "")
			refresh()))
		right.add_child(row)
	right.add_child(UIK.sep())
	if tree_id == "demon":
		_demon()
		return
	right.add_child(UIK.label(DB.t("skill_trees")[tree_id], 22, UIK.GOLD))
	for id in DB.t("skills"):
		var sk := DB.skill(id)
		if sk["tree"] != tree_id:
			continue
		var rank := GameState.skill_rank(id)
		var row2 := UIK.hbox(8)
		var l := UIK.label("%s [%d/%d]%s – %s" % [sk["name"], rank, sk["max"], " (aktiv)" if sk["kind"] == "active" else "", sk["desc"]], 15, UIK.TEXT if rank > 0 else UIK.DIM, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row2.add_child(l)
		var chk := Skills.can_learn(id)
		var b2 := UIK.button("Lernen", func():
			Skills.learn(id)
			refresh(), chk.get("why", ""))
		b2.disabled = not chk["ok"]
		row2.add_child(b2)
		right.add_child(row2)


func _demon() -> void:
	var d: Dictionary = GameState.player()["demon"]
	right.add_child(UIK.label("Dämonenpfad – Stufe %d (%d EP) · Punkte: %d" % [d["level"], d["xp"], d["points"]], 20, Color(1.0, 0.45, 0.35)))
	right.add_child(UIK.label("Dämonen-EP erhältst du durch Kämpfe in Dämonengestalt. Aktive Kräfte belegen in Dämonengestalt automatisch die Tasten R/F/G/Z.", 13, UIK.DIM, true))
	for id in DB.t("demon_skills"):
		var sk: Dictionary = DB.get_entry("demon_skills", id)
		var rank := int(d["skills"].get(id, 0))
		var row := UIK.hbox(8)
		var l := UIK.label("%s [%d/%d] (ab Dämonenstufe %d) – %s" % [sk["name"], rank, sk["max"], sk["level"], sk["desc"]], 15, UIK.TEXT if rank > 0 else UIK.DIM, true)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		var b := UIK.button("Lernen", func():
			Skills.demon_learn(id)
			refresh())
		b.disabled = int(d["points"]) <= 0 or rank >= int(sk["max"]) or int(d["level"]) < int(sk["level"])
		row.add_child(b)
		right.add_child(row)
