class_name WinInventory
extends UIWindow
## Inventory: search, sort, filter, equip, use, hotbar assignment, comparisons, drop.

var search := ""
var filter := ""
var selected := -1
var list_box: VBoxContainer
var detail: VBoxContainer
var equip_box: VBoxContainer
var weight_label: Label


func _init() -> void:
	super._init("Inventar", Vector2(1180, 700))
	window_id = "inventory"
	var cols := UIK.hbox(12)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	equip_box = UIK.vbox(4)
	equip_box.custom_minimum_size = Vector2(260, 0)
	cols.add_child(equip_box)
	var mid := UIK.vbox(6)
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(mid)
	var tools := UIK.hbox(6)
	mid.add_child(tools)
	var le := LineEdit.new()
	le.placeholder_text = "Suchen …"
	le.custom_minimum_size = Vector2(200, 0)
	le.text_changed.connect(func(t):
		search = t.to_lower()
		refresh())
	tools.add_child(le)
	for s in [["Kategorie", "cat"], ["Name", "name"], ["Gewicht", "weight"], ["Wert", "value"]]:
		tools.add_child(UIK.button(s[0], func():
			Inventory.sort(GameState.player()["inventory"], s[1])
			selected = -1
			refresh(), "Sortieren"))
	var ft := UIK.hbox(4)
	mid.add_child(ft)
	for f in [["Alle", ""], ["Waffen", "weapon"], ["Rüstung", "armor"], ["Nahrung", "food"], ["Verbrauch", "consumable"], ["Munition", "ammo"], ["Material", "material"], ["Essenzen", "essence"]]:
		ft.add_child(UIK.button(f[0], func():
			filter = f[1]
			refresh()))
	var sc := UIK.scroll(Vector2(480, 470))
	mid.add_child(sc[0])
	list_box = sc[1]
	weight_label = UIK.label("", 14, UIK.DIM)
	mid.add_child(weight_label)
	detail = UIK.vbox(6)
	detail.custom_minimum_size = Vector2(330, 0)
	cols.add_child(detail)


func refresh() -> void:
	if list_box == null:
		return
	var p := GameState.player()
	var inv: Array = p["inventory"]
	UIK.clear(list_box)
	for i in inv.size():
		var st: Dictionary = inv[i]
		var it := DB.item(st["id"])
		if filter != "" and it.get("cat", "") != filter:
			continue
		var nm := Inventory.display_name(st)
		if search != "" and not nm.to_lower().contains(search):
			continue
		var row := UIK.hbox(6)
		row.add_child(UIK.item_badge(st["id"], 30))
		var b := UIK.button("%s  ×%d" % [nm, st["n"]], func():
			selected = i
			refresh(), UIK.item_tooltip(st))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", Inventory.quality_color(float(st.get("q", 1.0))) if it.get("cat", "") in ["weapon", "armor", "tool"] else UIK.TEXT)
		if i == selected:
			b.add_theme_color_override("font_color", UIK.GOLD)
		row.add_child(b)
		list_box.add_child(row)
	weight_label.text = "Gewicht: %.1f / %.0f kg   ·   %d Bernstein   ·   Forschungspunkte: %d" % [Inventory.weight(inv), _cap(), GameState.amber(), int(p["research_points"])]
	_equip_panel()
	_detail_panel()


func _cap() -> float:
	var pl := get_tree().get_first_node_in_group("player") if is_inside_tree() else null
	return pl.carry_capacity() if pl else 60.0


func _equip_panel() -> void:
	UIK.clear(equip_box)
	equip_box.add_child(UIK.label("Ausrüstung", 20, UIK.GOLD))
	var p := GameState.player()
	for slot in Equipment.SLOTS:
		var id: String = p["equipment"].get(slot, "")
		var row := UIK.hbox(4)
		var l := UIK.label("%s:" % Equipment.SLOTS[slot], 14, UIK.DIM)
		l.custom_minimum_size = Vector2(80, 0)
		row.add_child(l)
		var ed: Dictionary = p.get("equipment_data", {})
		var nm := Inventory.display_name(ed.get(slot, {"id": id})) if id != "" else "—"
		var b := UIK.button(nm, func():
			if id != "":
				Equipment.unequip(slot)
				refresh(), "Klicken zum Ablegen")
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)
		equip_box.add_child(row)
	equip_box.add_child(UIK.sep())
	var pl := get_tree().get_first_node_in_group("player")
	if pl:
		equip_box.add_child(UIK.label("Leben: %d / %d" % [pl.combatant.hp, pl.combatant.max_hp], 14))
		equip_box.add_child(UIK.label("Rüstung: %.0f (−%d%% Schaden)" % [pl.combatant.armor, int(pl.combatant.armor / (pl.combatant.armor + 50.0) * 100)], 14))
		equip_box.add_child(UIK.label("Angriff: %.0f" % pl.combat.attack_value(), 14))
	equip_box.add_child(UIK.sep())
	equip_box.add_child(UIK.label("Schnellleiste (1–6)", 16, UIK.GOLD))
	for i in 6:
		var id2: String = p["hotbar"][i]
		var r2 := UIK.hbox(4)
		r2.add_child(UIK.label("%d:" % (i + 1), 14, UIK.DIM))
		var b2 := UIK.button(DB.item_name(id2) if id2 != "" else "—", func():
			p["hotbar"][i] = ""
			refresh(), "Klicken zum Leeren")
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r2.add_child(b2)
		equip_box.add_child(r2)
	equip_box.add_child(UIK.button("Herstellen öffnen (U)", func(): ui.open_crafting("hand")))


func _detail_panel() -> void:
	UIK.clear(detail)
	var inv: Array = GameState.player()["inventory"]
	if selected < 0 or selected >= inv.size():
		detail.add_child(UIK.label("Wähle einen Gegenstand.", 15, UIK.DIM, true))
		return
	var st: Dictionary = inv[selected]
	var it := DB.item(st["id"])
	detail.add_child(UIK.label(Inventory.display_name(st), 20, UIK.GOLD, true))
	detail.add_child(UIK.rich(UIK.item_tooltip(st).replace(Inventory.display_name(st) + "\n", "")))
	var cmp := Equipment.compare_text(st)
	if cmp != "":
		detail.add_child(UIK.label("Vergleich mit Ausgerüstetem:", 14, UIK.DIM))
		detail.add_child(UIK.rich(cmp))
	var acts := UIK.vbox(4)
	detail.add_child(acts)
	var cat: String = it.get("cat", "")
	var pl := get_tree().get_first_node_in_group("player")
	if Equipment.slot_for(st["id"]) != "":
		acts.add_child(UIK.button("Ausrüsten", func():
			Equipment.equip_stack_index(selected)
			selected = -1
			refresh()))
	if cat in ["food", "consumable"] and (it.has("food") or it.has("heal") or it.has("buff") or it.has("research") or it.has("cure") or it.get("respec", false)):
		acts.add_child(UIK.button("Benutzen / Essen", func():
			if pl:
				pl.eat(st["id"])
			refresh()))
	if it.get("read", false):
		acts.add_child(UIK.button("Lesen", func(): ui.show_text(it["name"], DB.t("texts").get(st["id"], ""))))
	var hb := UIK.hbox(2)
	hb.add_child(UIK.label("Schnellleiste:", 13, UIK.DIM))
	for i in 6:
		hb.add_child(UIK.button(str(i + 1), func():
			GameState.player()["hotbar"][i] = st["id"]
			refresh()))
	acts.add_child(hb)
	if cat != "quest":
		acts.add_child(UIK.button("1 Stück wegwerfen", func():
			Inventory.remove_at(inv, selected, 1)
			if selected >= inv.size():
				selected = -1
			EventBus.inventory_changed.emit()
			refresh()))
