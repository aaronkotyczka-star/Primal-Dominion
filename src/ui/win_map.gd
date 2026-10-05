class_name WinMap
extends UIWindow
## World map with discovered locations, player, base, companions, quest target and territories.

var map_rect: TextureRect
var overlay: Control


func _init() -> void:
	super._init("Karte des Vor'Thal-Archipels", Vector2(980, 900))
	window_id = "map"
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(800, 800)
	content.add_child(holder)
	map_rect = TextureRect.new()
	map_rect.texture = load("res://assets/world/map.png")
	map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	map_rect.stretch_mode = TextureRect.STRETCH_SCALE
	map_rect.size = Vector2(800, 800)
	holder.add_child(map_rect)
	overlay = Control.new()
	overlay.size = Vector2(800, 800)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(overlay)
	overlay.draw.connect(_draw_overlay)
	content.add_child(UIK.label("● Du   ◆ Lager   ■ entdeckter Ort   ▲ Quest-Ziel   ○ Gefährte   Gebiete in Grün gehören dir", 14, UIK.DIM))


func _to_map(x: float, z: float) -> Vector2:
	var e := WorldData.extent
	return Vector2((x + e) / (2.0 * e) * 800.0, (z + e) / (2.0 * e) * 800.0)


func refresh() -> void:
	if overlay:
		overlay.queue_redraw()


func _draw_overlay() -> void:
	var font := UIK.get_theme().default_font
	var carto := GameState.skill_rank("exp_cartography") > 0 or GameState.has_research("cartography")
	for id in WorldData.info["pois"]:
		var p: Dictionary = WorldData.info["pois"][id]
		var disc: bool = id in GameState.state["discovered"]
		if not disc and not carto:
			continue
		var mp := _to_map(p["x"], p["z"])
		overlay.draw_rect(Rect2(mp - Vector2(4, 4), Vector2(8, 8)), Color(0.95, 0.85, 0.5) if disc else Color(0.6, 0.6, 0.6, 0.6))
		overlay.draw_string(font, mp + Vector2(7, 4), p["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.95, 0.85))
	for tid in Settlement.TERRITORIES:
		if Settlement.territory_owner(tid) == "player":
			var pp := WorldData.poi_pos(Settlement.TERRITORIES[tid]["poi"])
			overlay.draw_circle(_to_map(pp.x, pp.z), 26.0, Color(0.3, 0.9, 0.3, 0.25))
	var w := overlay.get_tree().get_first_node_in_group("world") as World
	if w == null:
		return
	var bc := w.buildings.base_center()
	if bc != Vector3.INF:
		var bm := _to_map(bc.x, bc.z)
		overlay.draw_colored_polygon(PackedVector2Array([bm + Vector2(0, -8), bm + Vector2(8, 0), bm + Vector2(0, 8), bm + Vector2(-8, 0)]), Color(0.4, 0.8, 1.0))
		overlay.draw_string(font, bm + Vector2(10, 4), "Lager", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.9, 1.0))
	for c in w.get_tree().get_nodes_in_group("companions"):
		overlay.draw_arc(_to_map(c.global_position.x, c.global_position.z), 4.0, 0, TAU, 12, Color(0.5, 1.0, 0.6), 2.0)
	for qid in Quests.tracked():
		for o in Quests.current_stage_def(qid).get("obj", []):
			var key: String = o.get("poi", o.get("at", ""))
			if key == "" and o.has("npc"):
				key = DB.npc(o["npc"]).get("poi", "")
			if key != "":
				var q := WorldData.poi_pos(key)
				var qm := _to_map(q.x, q.z)
				overlay.draw_colored_polygon(PackedVector2Array([qm + Vector2(0, -10), qm + Vector2(8, 6), qm + Vector2(-8, 6)]), Color(1.0, 0.75, 0.2))
	var pp2 := w.player.global_position
	var pm := _to_map(pp2.x, pp2.z)
	overlay.draw_circle(pm, 6.0, Color(1.0, 0.3, 0.25))
	var f := Vector2(-sin(w.player.rig.yaw), -cos(w.player.rig.yaw))
	overlay.draw_line(pm, pm + f * 16.0, Color(1.0, 0.3, 0.25), 2.0)
	var bag = GameState.player().get("death_bag", [])
	if not bag.is_empty():
		overlay.draw_string(font, _to_map(bag[0], bag[2]), "✝", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(1, 0.8, 0.3))
