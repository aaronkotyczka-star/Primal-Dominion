class_name WinCrafting
extends UIWindow
## Crafting: suggestions, all recipes (search), modular weapon builder, saved designs. Uses nearby storage.

var station := "hand"
var tab := "suggest"
var search := ""
var list_box: VBoxContainer
var right: VBoxContainer
var mod_recipe := "m_spear"
var mod_choice := {}
var pool: Array = []
var stations: Array = []
var count := 1


func _init(st: String = "hand") -> void:
	super._init("Herstellen", Vector2(1150, 680))
	window_id = "crafting"
	station = st
	var tabs := UIK.hbox(6)
	content.add_child(tabs)
	for t in [["Vorschläge", "suggest"], ["Alle Rezepte", "all"], ["Modulare Waffen", "modular"], ["Entwürfe", "designs"]]:
		tabs.add_child(UIK.button(t[0], func():
			tab = t[1]
			refresh()))
	var le := LineEdit.new()
	le.placeholder_text = "Rezept suchen …"
	le.custom_minimum_size = Vector2(220, 0)
	le.text_changed.connect(func(t):
		search = t.to_lower()
		refresh())
	tabs.add_child(le)
	var cols := UIK.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var sc := UIK.scroll(Vector2(560, 520))
	cols.add_child(sc[0])
	list_box = sc[1]
	right = UIK.vbox(6)
	right.custom_minimum_size = Vector2(500, 0)
	cols.add_child(right)


func _gather() -> void:
	var pl := get_tree().get_first_node_in_group("player")
	var w := get_tree().get_first_node_in_group("world")
	if pl and w:
		pool = Crafting.pools(w.nearby_storages(pl.global_position, 20.0))
		stations = w.nearby_stations(pl.global_position, 7.0)
	else:
		pool = Crafting.pools([])
		stations = ["hand"]
	if station != "hand" and not station in stations:
		stations.append(station)


func refresh() -> void:
	if list_box == null or not is_inside_tree():
		return
	_gather()
	title_label.text = "Herstellen – Stationen: " + ", ".join(stations.map(func(s): return Crafting.STATION_NAMES.get(s, s)))
	UIK.clear(list_box)
	UIK.clear(right)
	match tab:
		"suggest":
			var sug := Crafting.suggestions(pool, stations)
			if sug.is_empty():
				list_box.add_child(UIK.label("Mit deinen Materialien (inkl. Lager in 20 m) ist gerade nichts herstellbar.", 15, UIK.DIM, true))
			for rid in sug:
				if search == "" or DB.recipe(rid)["name"].to_lower().contains(search):
					_recipe_row(rid)
		"all":
			var ids = DB.t("recipes").keys()
			ids.sort_custom(func(a, b): return DB.recipe(a)["name"] < DB.recipe(b)["name"])
			for rid in ids:
				var r := DB.recipe(rid)
				if r["kind"] != "fixed":
					continue
				if search != "" and not r["name"].to_lower().contains(search):
					continue
				_recipe_row(rid)
		"modular":
			_modular()
		"designs":
			for d in GameState.state["designs"]:
				list_box.add_child(UIK.button("%s (%s)" % [d["name"], DB.recipe(d["recipe"]).get("name", "")], func():
					tab = "modular"
					mod_recipe = d["recipe"]
					mod_choice = (d["choice"] as Dictionary).duplicate()
					refresh()))
			if GameState.state["designs"].is_empty():
				list_box.add_child(UIK.label("Noch keine Entwürfe gespeichert (im Modular-Tab „Entwurf speichern“).", 15, UIK.DIM, true))


func _recipe_row(rid: String) -> void:
	var r := DB.recipe(rid)
	var chk := Crafting.can_craft(rid, pool, stations)
	var row := UIK.hbox(6)
	row.add_child(UIK.item_badge(r["output"], 28))
	var b := UIK.button("%s%s" % [r["name"], (" ×%d" % r["count"]) if int(r.get("count", 1)) > 1 else ""], func(): _show_recipe(rid), chk.get("why", ""))
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not chk["ok"]:
		b.add_theme_color_override("font_color", UIK.DIM)
	row.add_child(b)
	list_box.add_child(row)


func _show_recipe(rid: String) -> void:
	UIK.clear(right)
	var r := DB.recipe(rid)
	right.add_child(UIK.label(r["name"], 22, UIK.GOLD))
	right.add_child(UIK.label("Station: " + Crafting.STATION_NAMES.get(r["station"], r["station"]), 15, UIK.DIM))
	for it in r["inputs"]:
		var have := Inventory.pooled_count(pool, it)
		var need := int(r["inputs"][it]) * count
		right.add_child(UIK.label("%s: %d / %d" % [DB.item_name(it), have, need], 15, UIK.GREEN if have >= need else UIK.RED))
	right.add_child(UIK.rich(UIK.item_tooltip({"id": r["output"], "q": 1.0, "d": {}})))
	var chk := Crafting.can_craft(rid, pool, stations, count)
	if not chk["ok"]:
		right.add_child(UIK.label(chk["why"], 15, UIK.RED, true))
	var cnt := UIK.hbox(4)
	cnt.add_child(UIK.label("Anzahl:", 14))
	for n in [1, 5, 10]:
		cnt.add_child(UIK.button(str(n), func():
			count = n
			_show_recipe(rid)))
	right.add_child(cnt)
	right.add_child(UIK.button("Herstellen ×%d" % count, func():
		if Crafting.craft_fixed(rid, pool, stations, count):
			refresh()
			_show_recipe(rid)))


func _modular() -> void:
	for rid in DB.t("recipes"):
		var r := DB.recipe(rid)
		if r["kind"] != "modular":
			continue
		var ok := Research.recipe_unlocked(rid)
		var b := UIK.button(r["name"] + ("" if ok else " (Forschung nötig)"), func():
			mod_recipe = rid
			mod_choice = {}
			refresh())
		if rid == mod_recipe:
			b.add_theme_color_override("font_color", UIK.GOLD)
		list_box.add_child(b)
	var r2 := DB.recipe(mod_recipe)
	right.add_child(UIK.label("Modular: " + r2["name"], 22, UIK.GOLD))
	right.add_child(UIK.label("Station: " + Crafting.STATION_NAMES.get(r2["station"], r2["station"]), 14, UIK.DIM))
	var opts := Crafting.modular_options(mod_recipe, pool)
	var names := {"head": "Kopf/Klinge", "shaft": "Schaft", "binding": "Bindung", "focus": "Fokus", "rune": "Rune (optional)"}
	for slot in opts:
		var h := UIK.hbox(6)
		var need := int(r2["slots"].get(slot, {}).get("n", 1))
		h.add_child(UIK.label("%s (%d):" % [names.get(slot, slot), need], 15))
		var ob := OptionButton.new()
		ob.custom_minimum_size = Vector2(240, 0)
		var list: Array = opts[slot]
		for i in list.size():
			var mid: String = list[i]
			ob.add_item(DB.item_name(mid) if mid != "" else "—", i)
		if not mod_choice.has(slot) and not list.is_empty():
			mod_choice[slot] = list[0]
		var cur := list.find(mod_choice.get(slot, ""))
		if cur >= 0:
			ob.select(cur)
		ob.item_selected.connect(func(idx):
			mod_choice[slot] = list[idx]
			refresh())
		h.add_child(ob)
		if list.is_empty() or (list.size() == 1 and list[0] == "" and not r2["slots"].get(slot, {}).get("optional", true)):
			h.add_child(UIK.label("kein Material", 13, UIK.RED))
		right.add_child(h)
	var prev := Crafting.modular_preview(mod_recipe, mod_choice)
	right.add_child(UIK.sep())
	right.add_child(UIK.label("Vorschau: " + prev["name"], 17, UIK.TEXT))
	var st: Dictionary = prev["stats"]
	var lines := []
	for k in [["dmg", "Schaden"], ["torpor", "Betäubung"], ["reach", "Reichweite"], ["speed", "Tempo"], ["harvest_wood", "Holzertrag"], ["harvest_stone", "Steinertrag"], ["spell_power", "Zauberkraft"]]:
		if st.has(k[0]) and float(st[k[0]]) > 0.0:
			lines.append("%s: %.1f" % [k[1], float(st[k[0]])])
	right.add_child(UIK.label("\n".join(lines) + "\n(Qualität ±10%% je nach Handwerkskönnen: +%d%%)" % (8 * GameState.skill_rank("craft_quality")), 14, UIK.DIM, true))
	var chk := Crafting.can_craft(mod_recipe, pool, stations)
	if not chk["ok"]:
		right.add_child(UIK.label(chk["why"], 14, UIK.RED, true))
	var bh := UIK.hbox(6)
	bh.add_child(UIK.button("Herstellen", func():
		if Crafting.craft_modular(mod_recipe, mod_choice, pool, stations):
			refresh()))
	bh.add_child(UIK.button("Entwurf speichern", func(): Crafting.save_design(prev["name"], mod_recipe, mod_choice)))
	right.add_child(bh)
