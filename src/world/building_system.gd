class_name BuildingSystem
extends Node3D
## Player buildings: spawning from state, placement preview/validation, station interaction.

var world: Node3D
var nodes := {} # building id -> Node3D
var placing := ""
var placing_template := ""
var ghost: Node3D
var ghost_rot := 0.0
var ghost_ok := false
var ghost_reason := ""
var ghost_pos := Vector3.ZERO


func setup(w: Node3D) -> void:
	world = w
	for b in GameState.state["buildings"]:
		_spawn(b)


func _spawn(b: Dictionary) -> Node3D:
	var kind: String = b["type"]
	var root := StaticBody3D.new()
	root.name = "B%d_%s" % [b["id"], kind]
	root.collision_layer = 8
	root.collision_mask = 0
	add_child(root)
	root.global_position = Vector3(b["pos"][0], b["pos"][1], b["pos"][2])
	root.rotation.y = float(b.get("rot", 0.0))
	var vis := BuildingVisuals.make(kind)
	root.add_child(vis)
	for sh in BuildingVisuals.collision_shapes(kind):
		var cs := CollisionShape3D.new()
		cs.shape = sh[0]
		cs.position = sh[1]
		root.add_child(cs)
	var bd := DB.building(kind)
	var size: Array = bd.get("size", [2, 2, 2])
	var it := Interactable.new()
	it.radius = maxf(2.5, maxf(float(size[0]), float(size[2])) * 0.6 + 1.0)
	it.prompt_fn = func(_p): return _prompt(b)
	it.on_interact = func(p): _use(b, p)
	it.position = Vector3(0, 0.8, 0)
	root.add_child(it)
	root.set_meta("building", b)
	nodes[int(b["id"])] = root
	if kind == "camp_totem":
		root.add_to_group("base_totems")
	return root


func _prompt(b: Dictionary) -> String:
	var bd := DB.building(b["type"])
	var name: String = bd.get("name", b["type"])
	if bd.has("storage"):
		return "E: %s öffnen" % name
	if bd.get("bed", false):
		return "E: Schlafen / Wiedereinstiegspunkt (%s)" % name
	if bd.has("station"):
		return "E: %s benutzen" % name
	if b["type"] == "camp_totem":
		return "E: Lager verwalten"
	if bd.get("pen_capacity", 0) > 0:
		return "E: %s – Kreaturen im Lager" % name
	return "E: %s (Abreißen mit gedrückter Ducken-Taste)" % name


func _use(b: Dictionary, p: Node) -> void:
	var bd := DB.building(b["type"])
	var ui := get_tree().get_first_node_in_group("ui")
	if Input.is_action_pressed("crouch") and b["type"] != "camp_totem":
		demolish(int(b["id"]))
		return
	if bd.has("storage"):
		if not b.has("data"):
			b["data"] = {}
		if not b["data"].has("storage"):
			b["data"]["storage"] = []
		ui.open_storage(b)
	elif bd.get("bed", false):
		GameState.player()["respawn"] = b["pos"]
		ui.open_sleep(b)
	elif bd.get("station", "") == "research":
		ui.open_research(true)
	elif bd.get("station", "") == "gene_lab":
		ui.open_genelab()
	elif bd.get("station", "") == "incubator":
		ui.open_incubator(b)
	elif bd.get("station", "") == "pact":
		ui.open_pact()
	elif bd.get("station", "") == "infirmary":
		_heal_base_creatures()
	elif bd.has("station"):
		ui.open_crafting(bd["station"])
	elif b["type"] == "camp_totem" or bd.get("pen_capacity", 0) > 0:
		ui.open_base()


func _heal_base_creatures() -> void:
	var n := 0
	for c in GameState.all_creatures():
		if c["status"] in ["base", "party"]:
			c["hp"] = Creatures.stats(c)["hp"]
			c["injuries"] = c["injuries"].filter(func(i): return i == "unheilbar")
			n += 1
	for node in get_tree().get_nodes_in_group("companions"):
		node.combatant.heal(node.combatant.max_hp)
	EventBus.notify.emit("Krankenstation: %d Kreaturen versorgt, Verletzungen behandelt." % n, "good")


func demolish(id: int) -> void:
	var arr: Array = GameState.state["buildings"]
	for i in arr.size():
		if int(arr[i]["id"]) == id:
			var b: Dictionary = arr[i]
			var bd := DB.building(b["type"])
			for item in bd.get("cost", {}):
				Inventory.add(GameState.player()["inventory"], item, int(ceil(int(bd["cost"][item]) * 0.5)))
			for st in b.get("data", {}).get("storage", []):
				Inventory.add(GameState.player()["inventory"], st["id"], int(st["n"]), float(st.get("q", 1.0)), st.get("d", {}))
			arr.remove_at(i)
			if nodes.has(id):
				nodes[id].queue_free()
				nodes.erase(id)
			EventBus.notify.emit("%s abgerissen (50%% Material zurück)." % bd.get("name", b["type"]), "info")
			EventBus.inventory_changed.emit()
			return


# ------------------------------------------------------------------ placement
func begin_place(kind: String, template: String = "") -> void:
	cancel_place()
	placing = kind
	placing_template = template
	ghost = Node3D.new()
	add_child(ghost)
	var pieces := _pieces()
	for pc in pieces:
		var v := BuildingVisuals.make(pc[0])
		v.position = Vector3(pc[1], pc[2], pc[3])
		v.rotation.y = deg_to_rad(pc[4])
		ghost.add_child(v)
	_set_ghost_mat(true)


func _pieces() -> Array:
	if placing_template != "":
		return DB.get_entry("templates", placing_template).get("pieces", [])
	return [[placing, 0, 0, 0, 0]]


func _set_ghost_mat(ok: bool) -> void:
	for n in ghost.find_children("*", "MeshInstance3D", true, false):
		(n as MeshInstance3D).material_override = BuildingVisuals.ghost(ok)
	for n in ghost.find_children("*", "Light3D", true, false):
		n.visible = false
	for n in ghost.find_children("*", "CPUParticles3D", true, false):
		n.emitting = false


func cancel_place() -> void:
	placing = ""
	placing_template = ""
	if ghost:
		ghost.queue_free()
		ghost = null


func is_placing() -> bool:
	return placing != "" or placing_template != ""


func total_cost() -> Dictionary:
	var cost := {}
	for pc in _pieces():
		var bd := DB.building(pc[0])
		for it in bd.get("cost", {}):
			cost[it] = int(cost.get(it, 0)) + int(bd["cost"][it])
	return cost


func update_place(player: Player, delta: float) -> void:
	if ghost == null:
		return
	var ray := player.rig.aim_ray(25.0, [player.get_rid()])
	var p: Vector3 = ray["point"]
	var max_d := 18.0
	var flat := Vector3(p.x - player.global_position.x, 0, p.z - player.global_position.z)
	if flat.length() > max_d:
		p = player.global_position + flat.normalized() * max_d
	var bd := DB.building(placing if placing != "" else "foundation")
	var snap := float(bd.get("snap", 0.0)) if placing_template == "" else 0.0
	if snap > 0.0:
		p.x = round(p.x / snap) * snap
		p.z = round(p.z / snap) * snap
	if Input.is_action_just_pressed("rotate_build"):
		ghost_rot += PI * 0.5 if snap > 0.0 else PI * 0.125
	p.y = WorldData.height_at(p.x, p.z)
	# stack on foundations
	if ray["hit"] and ray["hit"].get("collider") is StaticBody3D and ray["hit"]["collider"].has_meta("building"):
		var hb: Dictionary = ray["hit"]["collider"].get_meta("building")
		if hb["type"] == "foundation":
			p.y = float(hb["pos"][1]) + 0.25
	ghost_pos = p
	ghost.global_position = p
	ghost.rotation.y = ghost_rot
	var chk := validate(p)
	ghost_ok = chk["ok"]
	ghost_reason = chk.get("why", "")
	_set_ghost_mat(ghost_ok)


func validate(p: Vector3) -> Dictionary:
	var cost := total_cost()
	var pool := Crafting.pools(world.nearby_storages(p, 25.0))
	for it in cost:
		if Inventory.pooled_count(pool, it) < int(cost[it]):
			return {"ok": false, "why": "Fehlt: %d× %s" % [int(cost[it]) - Inventory.pooled_count(pool, it), DB.item_name(it)]}
	if world.is_no_build(p):
		return {"ok": false, "why": "Hier kann nicht gebaut werden (Siedlung oder wichtiger Ort)."}
	var kinds := _pieces().map(func(x): return x[0])
	var water_ok := "water_pen" in kinds
	var h := WorldData.height_at(p.x, p.z)
	if h < 0.2 and not water_ok:
		return {"ok": false, "why": "Nicht im Wasser bauen."}
	if water_ok and h > 1.5:
		return {"ok": false, "why": "Wassergehege muss an der Küste stehen."}
	if WorldData.normal_at(p.x, p.z).y < 0.82 and not ("foundation" in kinds):
		return {"ok": false, "why": "Zu steil."}
	if "camp_totem" in kinds and GameState.has_base():
		return {"ok": false, "why": "Du besitzt bereits einen Lagerstein (abreißen, um umzuziehen)."}
	# overlap with other buildings (rough footprint test)
	for pc in _pieces():
		var bdp := DB.building(pc[0])
		var sz: Array = bdp.get("size", [2, 2, 2])
		var r1: float = maxf(float(sz[0]), float(sz[2])) * 0.45
		var pp := p + Vector3(pc[1], 0, pc[3]).rotated(Vector3.UP, ghost_rot)
		if float(bdp.get("snap", 0)) > 0.0:
			continue
		for b in GameState.state["buildings"]:
			var bdb := DB.building(b["type"])
			if float(bdb.get("snap", 0)) > 0.0 or bdb.get("cat", "") == "structure":
				continue
			var sz2: Array = bdb.get("size", [2, 2, 2])
			var r2: float = maxf(float(sz2[0]), float(sz2[2])) * 0.45
			if Vector2(pp.x - b["pos"][0], pp.z - b["pos"][2]).length() < (r1 + r2) * 0.75:
				return {"ok": false, "why": "Kollision mit %s." % bdb.get("name", b["type"])}
	for pc in _pieces():
		if not Research.building_unlocked(pc[0]):
			return {"ok": false, "why": "Forschung „%s“ nötig." % DB.research(DB.building(pc[0])["research"]).get("name", "")}
	return {"ok": true}


func confirm_place() -> bool:
	if ghost == null or not ghost_ok:
		if ghost_reason != "":
			EventBus.notify.emit(ghost_reason, "warn")
		return false
	var pool := Crafting.pools(world.nearby_storages(ghost_pos, 25.0))
	var cost := total_cost()
	for it in cost:
		Inventory.pooled_remove(pool, it, int(cost[it]))
	for pc in _pieces():
		var off := Vector3(pc[1], pc[2], pc[3]).rotated(Vector3.UP, ghost_rot)
		var pos := ghost_pos + off
		if float(pc[2]) == 0.0:
			pos.y = WorldData.height_at(pos.x, pos.z) if not (pc[0] in ["wall", "wall_window", "doorway", "roof"]) else ghost_pos.y + float(pc[2])
		var b := {"id": GameState.state["next_building"], "type": pc[0], "pos": [pos.x, pos.y, pos.z], "rot": ghost_rot + deg_to_rad(pc[4]), "hp": float(DB.building(pc[0]).get("hp", 500)), "data": {}}
		GameState.state["next_building"] += 1
		GameState.state["buildings"].append(b)
		_spawn(b)
		if pc[0] == "camp_totem":
			GameState.player()["respawn"] = [pos.x, pos.y + 1.0, pos.z + 2.0]
			EventBus.notify.emit("Lager gegründet! Kreaturen im Lager werden hier untergebracht.", "good")
		EventBus.built.emit(pc[0], pos)
	Audio.play_at("build", ghost_pos)
	GameState.add_xp(5, "build")
	EventBus.inventory_changed.emit()
	if not Input.is_action_pressed("sprint"):
		cancel_place()
	return true


func base_center() -> Vector3:
	for b in GameState.state["buildings"]:
		if b["type"] == "camp_totem":
			return Vector3(b["pos"][0], b["pos"][1], b["pos"][2])
	return Vector3.INF


func pen_center() -> Vector3:
	for b in GameState.state["buildings"]:
		if b["type"] in ["pen", "pen_large"]:
			return Vector3(b["pos"][0], b["pos"][1], b["pos"][2])
	return base_center()
