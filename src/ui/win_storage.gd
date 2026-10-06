class_name WinStorage
extends UIWindow
## Transfer items between inventory and a storage building.

var b: Dictionary
var left: VBoxContainer
var right: VBoxContainer


func _init(bld: Dictionary = {}) -> void:
	super._init(DB.building(bld.get("type", "storage_box")).get("name", "Lager"), Vector2(1000, 640))
	window_id = "storage"
	b = bld
	var hb := UIK.hbox(6)
	content.add_child(hb)
	hb.add_child(UIK.button("Alles einlagern (außer Ausrüstung/Quest)", func():
		var inv: Array = GameState.player()["inventory"]
		var st: Array = b["data"]["storage"]
		for i in range(inv.size() - 1, -1, -1):
			var s: Dictionary = inv[i]
			if DB.item(s["id"]).get("cat", "") in ["material", "food", "essence"] and st.size() < _cap():
				Inventory.add(st, s["id"], int(s["n"]), float(s.get("q", 1.0)), s.get("d", {}))
				inv.remove_at(i)
		EventBus.inventory_changed.emit()
		refresh()))
	hb.add_child(UIK.button("Sortieren", func():
		Inventory.sort(b["data"]["storage"])
		refresh()))
	var cols := UIK.hbox(16)
	content.add_child(cols)
	var sc := UIK.scroll(Vector2(460, 500))
	cols.add_child(sc[0])
	left = sc[1]
	var sc2 := UIK.scroll(Vector2(460, 500))
	cols.add_child(sc2[0])
	right = sc2[1]


func _cap() -> int:
	return int(DB.building(b["type"]).get("storage", 30))


func refresh() -> void:
	if left == null:
		return
	UIK.clear(left)
	UIK.clear(right)
	var inv: Array = GameState.player()["inventory"]
	var st: Array = b["data"]["storage"]
	left.add_child(UIK.label("Inventar (Klick: einlagern, Shift-Klick: ganzer Stapel)", 15, UIK.GOLD))
	for i in inv.size():
		var s: Dictionary = inv[i]
		left.add_child(UIK.button("%s ×%d" % [Inventory.display_name(s), s["n"]], func():
			if st.size() >= _cap() and Inventory.count(st, s["id"]) == 0:
				EventBus.notify.emit("Lager voll.", "warn")
				return
			var n := int(s["n"]) if Input.is_key_pressed(KEY_SHIFT) else 1
			var taken := Inventory.remove_at(inv, i, n)
			Inventory.add(st, taken["id"], int(taken["n"]), float(taken.get("q", 1.0)), taken.get("d", {}))
			EventBus.inventory_changed.emit()
			refresh()))
	right.add_child(UIK.label("Lager %d/%d Plätze" % [st.size(), _cap()], 15, UIK.GOLD))
	for i in st.size():
		var s2: Dictionary = st[i]
		right.add_child(UIK.button("%s ×%d" % [Inventory.display_name(s2), s2["n"]], func():
			var n2 := int(s2["n"]) if Input.is_key_pressed(KEY_SHIFT) else 1
			var taken2 := Inventory.remove_at(st, i, n2)
			Inventory.add(inv, taken2["id"], int(taken2["n"]), float(taken2.get("q", 1.0)), taken2.get("d", {}))
			EventBus.inventory_changed.emit()
			refresh()))
