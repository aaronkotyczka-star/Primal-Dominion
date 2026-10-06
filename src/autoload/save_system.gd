extends Node
## Save slots (binary Variant serialization of GameState.state) + small JSON metadata for listings.

const DIR := "user://saves/"
const SLOTS := ["auto", "quick", "slot1", "slot2", "slot3", "slot4", "slot5"]
const SLOT_NAMES := {"auto": "Automatisch", "quick": "Schnellspeicher", "slot1": "Platz 1", "slot2": "Platz 2", "slot3": "Platz 3", "slot4": "Platz 4", "slot5": "Platz 5"}

var autosave_interval := 300.0
var _auto_t := 0.0
var pending_load := ""


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	process_mode = Node.PROCESS_MODE_PAUSABLE


func _process(delta: float) -> void:
	if not GameState.running:
		return
	GameState.state["playtime"] = float(GameState.state.get("playtime", 0.0)) + delta
	_auto_t += delta
	if _auto_t >= autosave_interval:
		_auto_t = 0.0
		var pl := get_tree().get_first_node_in_group("player")
		if pl and not pl.dead and pl.combatant.in_combat_t <= 0.0:
			save_slot("auto")


func path(slot: String) -> String:
	return DIR + slot + ".sav"


func save_slot(slot: String) -> bool:
	if GameState.state["player"].get("dead", false):
		return false
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("before_save"):
		world.before_save()
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		EventBus.notify.emit("Speichern fehlgeschlagen!", "danger")
		return false
	GameState.state["slot"] = slot
	f.store_var(GameState.to_save(), false)
	f.close()
	var meta := {"slot": slot, "name": GameState.player()["name"], "level": GameState.player()["level"],
		"day": GameState.get_day(), "time": Time.get_datetime_string_from_system(false, true),
		"playtime": GameState.state.get("playtime", 0.0), "difficulty": GameState.state["difficulty"],
		"quest": _main_quest_name(), "version": GameState.VERSION}
	var mf := FileAccess.open(DIR + slot + ".json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(meta))
	mf.close()
	EventBus.game_saved.emit(slot)
	if slot != "auto":
		EventBus.notify.emit("Gespeichert (%s)." % SLOT_NAMES.get(slot, slot), "good")
	return true


func _main_quest_name() -> String:
	for qid in Quests.tracked():
		if DB.quest(qid).get("main", false):
			return DB.quest(qid)["name"]
	return ""


func slot_info(slot: String) -> Dictionary:
	var f := FileAccess.open(DIR + slot + ".json", FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	return d if d is Dictionary else {}


func has_slot(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


func load_slot(slot: String) -> bool:
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return false
	var d = f.get_var(false)
	if not d is Dictionary:
		EventBus.notify.emit("Spielstand beschädigt.", "danger")
		return false
	GameState.from_save(d)
	return true


func delete_slot(slot: String) -> void:
	DirAccess.remove_absolute(path(slot))
	DirAccess.remove_absolute(DIR + slot + ".json")


func can_manual_save() -> Dictionary:
	## manual saving only at safe places: own camp, campfire, villages, beds
	var pl := get_tree().get_first_node_in_group("player")
	if pl == null:
		return {"ok": false, "why": "Kein Spiel aktiv."}
	if pl.combatant.in_combat_t > 0.0:
		return {"ok": false, "why": "Nicht im Kampf speichern."}
	var world := get_tree().get_first_node_in_group("world")
	if world and world.has_method("is_safe_place") and world.is_safe_place(pl.global_position):
		return {"ok": true}
	return {"ok": false, "why": "Manuelles Speichern nur an sicheren Orten (Lager, Lagerfeuer, Siedlungen)."}
