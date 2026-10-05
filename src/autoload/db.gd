extends Node
## Read-only game data loaded from data/*.json (built from tools/data_src).

var tables := {}


func _ready() -> void:
	reload()


func reload() -> void:
	tables.clear()
	var d := DirAccess.open("res://data")
	if d == null:
		push_error("data/ fehlt")
		return
	for f in d.get_files():
		var fname := f.trim_suffix(".remap")
		if not fname.ends_with(".json"):
			continue
		var fa := FileAccess.open("res://data/" + fname, FileAccess.READ)
		if fa == null:
			continue
		var parsed = JSON.parse_string(fa.get_as_text())
		if parsed == null:
			push_error("JSON-Fehler in " + fname)
			continue
		tables[fname.get_basename()] = parsed


func t(table: String) -> Variant:
	return tables.get(table, {})


func get_entry(table: String, id: String) -> Dictionary:
	var tb = tables.get(table, {})
	if tb is Dictionary:
		return tb.get(id, {})
	return {}


func species(id: String) -> Dictionary:
	return get_entry("species", id)


func item(id: String) -> Dictionary:
	return get_entry("items", id)


func item_name(id: String) -> String:
	var it := item(id)
	return it.get("name", id)


func ability(id: String) -> Dictionary:
	return get_entry("abilities", id)


func part(id: String) -> Dictionary:
	return get_entry("parts", id)


func recipe(id: String) -> Dictionary:
	return get_entry("recipes", id)


func research(id: String) -> Dictionary:
	return get_entry("research", id)


func skill(id: String) -> Dictionary:
	return get_entry("skills", id)


func building(id: String) -> Dictionary:
	return get_entry("buildings", id)


func quest(id: String) -> Dictionary:
	return get_entry("quests", id)


func faction(id: String) -> Dictionary:
	return get_entry("factions", id)


func npc(id: String) -> Dictionary:
	return get_entry("npcs", id)


func element(id: String) -> Dictionary:
	return get_entry("elements", id)
