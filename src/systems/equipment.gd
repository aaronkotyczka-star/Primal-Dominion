class_name Equipment
extends RefCounted
## Equip/unequip between inventory and equipment slots (keeps crafted data).

const SLOTS := {"weapon": "Waffe", "offhand": "Nebenhand", "head": "Kopf", "chest": "Brust", "legs": "Beine", "trinket": "Talisman"}


static func slot_for(id: String) -> String:
	var it := DB.item(id)
	if it.has("slot"):
		return it["slot"]
	if it.get("cat", "") in ["weapon", "tool"] and it.has("wtype"):
		return "weapon"
	return ""


static func equip_stack_index(idx: int) -> bool:
	var p := GameState.player()
	var inv: Array = p["inventory"]
	if idx < 0 or idx >= inv.size():
		return false
	var st: Dictionary = inv[idx]
	var slot := slot_for(st["id"])
	if slot == "":
		return false
	unequip(slot)
	var taken := Inventory.remove_at(inv, idx, 1)
	p["equipment"][slot] = taken["id"]
	if not p.has("equipment_data"):
		p["equipment_data"] = {}
	p["equipment_data"][slot] = taken
	EventBus.equipment_changed.emit()
	EventBus.inventory_changed.emit()
	return true


static func equip_from_inventory(id: String) -> bool:
	var inv: Array = GameState.player()["inventory"]
	# prefer best quality / crafted
	var best := -1
	var bq := -1.0
	for i in inv.size():
		if inv[i]["id"] == id and float(inv[i].get("q", 1.0)) > bq:
			bq = float(inv[i].get("q", 1.0))
			best = i
	return equip_stack_index(best)


static func unequip(slot: String) -> void:
	var p := GameState.player()
	var id: String = p["equipment"].get(slot, "")
	if id == "":
		return
	var ed: Dictionary = p.get("equipment_data", {})
	var st: Dictionary = ed.get(slot, {"id": id, "q": 1.0, "d": {}})
	if st.get("id", "") != id:
		st = {"id": id, "q": 1.0, "d": {}}
	Inventory.add(p["inventory"], id, 1, float(st.get("q", 1.0)), st.get("d", {}))
	p["equipment"][slot] = ""
	ed.erase(slot)
	EventBus.equipment_changed.emit()
	EventBus.inventory_changed.emit()


static func compare_text(st: Dictionary) -> String:
	## stat comparison against currently equipped item in the same slot
	var slot := slot_for(st["id"])
	if slot == "":
		return ""
	var new_s := Inventory.stats_of(st)
	var cur_id: String = GameState.player()["equipment"].get(slot, "")
	var cur_s := {}
	if cur_id != "":
		var ed: Dictionary = GameState.player().get("equipment_data", {})
		cur_s = Inventory.stats_of(ed.get(slot, {"id": cur_id, "q": 1.0, "d": {}}))
	var lines := []
	var names := {"dmg": "Schaden", "armor": "Rüstung", "torpor": "Betäubung", "speed": "Tempo", "reach": "Reichweite", "block": "Blocken", "spell_power": "Zauberkraft", "cold": "Kälteschutz"}
	for k in names:
		if new_s.has(k) or cur_s.has(k):
			var a := float(new_s.get(k, 0.0))
			var b := float(cur_s.get(k, 0.0))
			var diff := a - b
			var arrow := ""
			if absf(diff) > 0.01:
				arrow = "  [color=%s](%+.1f)[/color]" % ["#7fdc6a" if diff > 0 else "#e06050", diff]
			lines.append("%s: %.1f%s" % [names[k], a, arrow])
	return "\n".join(lines)
