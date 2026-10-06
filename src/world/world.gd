class_name World
extends Node3D
## Root of a running game: builds the archipelago, actors, POIs and connects systems.

signal loading_progress(text: String, frac: float)
signal ready_to_play()

var quality := 2
var terrain: Terrain
var sky: SkyWeather
var caves: Caves
var water: MeshInstance3D
var vegetation: Vegetation
var grass: GrassField
var buildings: BuildingSystem
var spawner: Spawner
var quests: Quests
var player: Player
var fx_root: Node3D
var actors: Node3D
var resource_nodes := {} # idx -> Node3D
var _disc_t := 0.0
var _region_id := ""
var _base_t := 0.0
var _respawn_t := 30.0
var _poi_t := 0.0
var poi_spawned := {}
var build_mode := false
var is_ready := false
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	add_to_group("world")
	rng.randomize()


func build_world(q: int) -> void:
	quality = q
	WorldData.ensure_loaded()
	loading_progress.emit("Gelände wird geformt …", 0.1)
	await get_tree().process_frame
	fx_root = Node3D.new()
	fx_root.name = "Fx"
	fx_root.add_to_group("fx_root")
	add_child(fx_root)
	actors = Node3D.new()
	actors.name = "Actors"
	add_child(actors)
	terrain = Terrain.new()
	terrain.name = "Terrain"
	add_child(terrain)
	terrain.build(q)
	loading_progress.emit("Himmel und Meer …", 0.3)
	await get_tree().process_frame
	sky = SkyWeather.new()
	sky.name = "SkyWeather"
	sky.add_to_group("sky_weather")
	add_child(sky)
	sky.setup(q)
	caves = Caves.new()
	add_child(caves)
	caves.setup(self)
	_build_water()
	loading_progress.emit("Wälder wachsen …", 0.45)
	await get_tree().process_frame
	vegetation = Vegetation.new()
	vegetation.name = "Vegetation"
	add_child(vegetation)
	vegetation.build(q, float(Settings.get_v("view_distance")))
	grass = GrassField.new()
	grass.name = "Grass"
	add_child(grass)
	grass.setup(q)
	loading_progress.emit("Rohstoffe und Ruinen …", 0.6)
	await get_tree().process_frame
	_build_resources()
	quests = Quests.new()
	quests.name = "Quests"
	add_child(quests)
	buildings = BuildingSystem.new()
	buildings.name = "Buildings"
	add_child(buildings)
	buildings.setup(self)
	loading_progress.emit("Siedlungen erwachen …", 0.7)
	await get_tree().process_frame
	_build_settlements()
	loading_progress.emit("Der Bestienbändiger erwacht …", 0.85)
	await get_tree().process_frame
	player = Player.new()
	player.name = "Player"
	actors.add_child(player)
	var pp: Array = GameState.player()["pos"]
	player.global_position = Vector3(pp[0], maxf(pp[1], WorldData.height_at(pp[0], pp[2]) + 0.3), pp[2])
	if GameState.player()["demon"].get("in_form", false):
		player.demon_form = true
		player.build_visual()
		player.recalc_stats()
	spawner = Spawner.new()
	spawner.name = "Spawner"
	add_child(spawner)
	spawner.setup(self, q)
	_spawn_party()
	_update_region(true)
	vegetation.update_colliders(player.global_position)
	EventBus.creature_born.connect(func(_u): pass)
	EventBus.player_died.connect(_on_player_died)
	quests.evaluate_all()
	is_ready = true
	loading_progress.emit("Bereit", 1.0)
	ready_to_play.emit()


func _build_water() -> void:
	water = MeshInstance3D.new()
	water.name = "Ocean"
	var pm := PlaneMesh.new()
	pm.size = Vector2(2600, 2600)
	pm.subdivide_width = 260
	pm.subdivide_depth = 260
	water.mesh = pm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	var n1 := NoiseTexture2D.new()
	n1.seamless = true
	n1.as_normal_map = true
	n1.bump_strength = 4.0
	n1.width = 512
	n1.height = 512
	var fn := FastNoiseLite.new()
	fn.frequency = 0.02
	fn.fractal_octaves = 4
	n1.noise = fn
	var n2 := NoiseTexture2D.new()
	n2.seamless = true
	n2.as_normal_map = true
	n2.bump_strength = 2.0
	n2.width = 512
	n2.height = 512
	var fn2 := FastNoiseLite.new()
	fn2.frequency = 0.05
	fn2.seed = 7
	n2.noise = fn2
	mat.set_shader_parameter("normal_a", n1)
	mat.set_shader_parameter("normal_b", n2)
	water.material_override = mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)


func _process(delta: float) -> void:
	if not is_ready or player == null:
		return
	GameState.advance_time(delta)
	var cam: Camera3D = player.rig.cam
	grass.update(cam.global_position)
	vegetation.update_colliders(player.global_position)
	water.global_position = Vector3(snappedf(cam.global_position.x, 20.0), 0.0, snappedf(cam.global_position.z, 20.0))
	Audio.night = 1.0 if sky.is_night() else 0.0
	var h := WorldData.height_at(player.global_position.x, player.global_position.z)
	Audio.near_sea = clampf(1.0 - absf(h) / 12.0, 0.0, 1.0) if h < 6.0 else 0.0
	_disc_t -= delta
	if _disc_t <= 0.0:
		_disc_t = 0.5
		_check_discovery()
		_update_region(false)
		_update_music()
	_base_t -= delta
	if _base_t <= 0.0:
		_base_t = 3.0
		_manage_base_creatures()
		_feed_party()
	_respawn_t -= delta
	if _respawn_t <= 0.0:
		_respawn_t = 30.0
		vegetation.process_respawns()
		_process_incubators()
		Settlement.tick(self, 30.0)
	_poi_t -= delta
	if _poi_t <= 0.0:
		_poi_t = 1.0
		_update_encounters()
	if buildings.is_placing():
		buildings.update_place(player, delta)


# ------------------------------------------------------------------ spawning helpers
func spawn_wild(species: String, level: int, pos: Vector3, variant: Dictionary = {}) -> Creature:
	var sp := DB.species(species)
	if sp.is_empty():
		return null
	var c := Creature.new()
	actors.add_child(c)
	var y := WorldData.height_at(pos.x, pos.z)
	if sp.get("family", "") in ["marine", "fish"]:
		y = clampf(rng.randf_range(y + 3.0, -3.0), y + 2.0, -2.0)
	c.global_position = Vector3(pos.x, y + 0.3, pos.z)
	c.rotation.y = rng.randf() * TAU
	c.setup_wild(species, level, {}, variant)
	c.ai.home = c.global_position
	if player and c.global_position.distance_to(player.global_position) < 60.0:
		GameState.lexicon_mark(species, "seen")
	return c


func spawn_companion(uid: int, pos: Vector3, yaw: float = 0.0) -> Creature:
	var rec := GameState.creature(uid)
	if rec.is_empty() or rec["status"] == "dead":
		return null
	for n in get_tree().get_nodes_in_group("companions"):
		if n.uid == uid:
			return n
	var c := Creature.new()
	actors.add_child(c)
	var y := WorldData.height_at(pos.x, pos.z)
	c.global_position = Vector3(pos.x, maxf(y, pos.y - 1.0) + 0.3, pos.z)
	c.rotation.y = yaw
	c.setup_tamed(rec)
	return c


func despawn_companion(uid: int) -> void:
	for n in get_tree().get_nodes_in_group("companions"):
		if n.uid == uid:
			n.queue_free()


func _spawn_party() -> void:
	var i := 0
	for uid in GameState.state["party"]:
		var rec := GameState.creature(uid)
		if rec.is_empty():
			continue
		var pos := player.global_position + Vector3(cos(i * 1.7) * 5.0, 0, sin(i * 1.7) * 5.0 + 3.0)
		spawn_companion(uid, pos)
		i += 1


func summon_from_crystal(uid: int) -> bool:
	var rec := GameState.creature(uid)
	if rec.is_empty() or rec["status"] != "crystal":
		return false
	if GameState.state["party"].size() >= GameState.party_limit():
		EventBus.notify.emit("Gefolge ist voll (%d). Bestienführung erhöht das Limit." % GameState.party_limit(), "warn")
		return false
	GameState.set_creature_status(uid, "party")
	var pos := player.global_position + player.get_forward() * 4.0
	var c := spawn_companion(uid, pos, player.rotation.y)
	Fx.burst(pos + Vector3.UP, Color(0.5, 0.75, 1.0), self, 40, 0.2, 3.0, 0.8)
	Audio.play_at("spell_cast", pos)
	return c != null


func store_in_crystal(uid: int) -> bool:
	var rec := GameState.creature(uid)
	if Inventory.count(GameState.player()["inventory"], "soul_crystal") <= 0:
		EventBus.notify.emit("Du besitzt keinen Seelenkristall.", "warn")
		return false
	if GameState.crystal_used() + Creatures.size_units(rec) > GameState.crystal_capacity():
		EventBus.notify.emit("Seelenkristall voll (%.1f/%.1f). Große Tiere brauchen mehr Platz." % [GameState.crystal_used(), GameState.crystal_capacity()], "warn")
		return false
	for n in get_tree().get_nodes_in_group("companions"):
		if n.uid == uid:
			if n.global_position.distance_to(player.global_position) > 40.0:
				EventBus.notify.emit("%s ist zu weit entfernt für den Kristall." % rec["name"], "warn")
				return false
			rec["hp"] = n.combatant.hp
			Fx.burst(n.global_position + Vector3.UP, Color(0.5, 0.75, 1.0), self, 40, 0.2, 3.0, 0.8)
			n.queue_free()
	GameState.set_creature_status(uid, "crystal")
	return true


func send_to_base(uid: int) -> bool:
	if not GameState.has_base():
		EventBus.notify.emit("Du hast noch kein Lager (Lagerstein bauen).", "warn")
		return false
	var rec := GameState.creature(uid)
	if GameState.base_used() + Creatures.size_units(rec) > GameState.base_capacity():
		EventBus.notify.emit("Lager voll (%.1f/%.1f). Baue mehr Gehege." % [GameState.base_used(), GameState.base_capacity()], "warn")
		return false
	if rec["status"] == "party":
		var near_base := player.global_position.distance_to(buildings.base_center()) < 120.0
		var in_crystal_ok := Inventory.count(GameState.player()["inventory"], "soul_crystal") > 0
		if not near_base and not in_crystal_ok:
			EventBus.notify.emit("Bringe die Kreatur zum Lager oder nutze einen Seelenkristall.", "warn")
			return false
		despawn_companion(uid)
	GameState.set_creature_status(uid, "base")
	return true


func take_from_base(uid: int) -> bool:
	if player.global_position.distance_to(buildings.base_center()) > 120.0:
		EventBus.notify.emit("Du musst im Lager sein.", "warn")
		return false
	if GameState.state["party"].size() >= GameState.party_limit():
		EventBus.notify.emit("Gefolge ist voll.", "warn")
		return false
	GameState.set_creature_status(uid, "party")
	despawn_companion(uid)
	spawn_companion(uid, player.global_position + player.get_forward() * 4.0)
	return true


func base_center() -> Vector3:
	var b := buildings.pen_center()
	return b if b != Vector3.INF else player.global_position


func _manage_base_creatures() -> void:
	var bc := buildings.base_center()
	if bc == Vector3.INF:
		return
	var near := player.global_position.distance_to(bc) < 180.0
	var present := {}
	for n in get_tree().get_nodes_in_group("companions"):
		present[n.uid] = n
	for c in GameState.all_creatures():
		var uid := int(c["uid"])
		if c["status"] == "base":
			if near and not present.has(uid):
				var pc := buildings.pen_center()
				spawn_companion(uid, pc + Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)))
			elif not near and present.has(uid):
				present[uid].queue_free()
	# base creatures eat from storage & heal slowly
	for c in GameState.all_creatures():
		if c["status"] == "base":
			c["hunger"] = maxf(0.0, float(c.get("hunger", 80)) - 0.08)
			if c["hunger"] < 50.0:
				if _feed_from_storage(c):
					c["hunger"] = 90.0
			if c["hunger"] <= 0.0:
				c["hp"] = maxf(1.0, float(c["hp"]) - 2.0)
			else:
				c["hp"] = minf(Creatures.stats(c)["hp"], float(c["hp"]) + 5.0)


func _feed_from_storage(c: Dictionary) -> bool:
	var sp := Creatures.species_def(c)
	var foods: Array = sp.get("food", []) + ["kibble"]
	for b in GameState.state["buildings"]:
		var st: Array = b.get("data", {}).get("storage", [])
		for f in foods:
			if Inventory.count(st, f) > 0:
				Inventory.remove(st, f, 1)
				Creatures.add_bond(c, 0.3)
				return true
	return false


func _feed_party() -> void:
	var inv: Array = GameState.player()["inventory"]
	for n in get_tree().get_nodes_in_group("companions"):
		if n.rec.get("status", "") != "party":
			continue
		var c: Dictionary = n.rec
		var pers: Dictionary = Creatures.PERSONALITIES.get(c.get("personality", ""), {})
		c["hunger"] = maxf(0.0, float(c.get("hunger", 80)) - 0.12 * float(pers.get("hunger", 1.0)))
		if c["hunger"] < 35.0:
			var fed := false
			for f in Creatures.species_def(c).get("food", []) + ["kibble"]:
				if Inventory.count(inv, f) > 0:
					Inventory.remove(inv, f, 1)
					c["hunger"] = minf(100.0, float(c["hunger"]) + 40.0 * float(pers.get("food", 1.0)))
					if f in c.get("likes", []) or f == "kibble":
						Creatures.add_bond(c, 1.0)
					fed = true
					EventBus.inventory_changed.emit()
					break
			if not fed and c["hunger"] < 15.0 and int(Time.get_ticks_msec() / 3000) % 20 == 0:
				EventBus.notify.emit("%s hungert! Gib ihm passendes Futter (%s)." % [c["name"], DB.item_name(Creatures.species_def(c).get("food", ["raw_meat"])[0])], "danger")
		if c["hunger"] <= 0.0:
			n.combatant.take_hit({"amount": n.combatant.max_hp * 0.01, "true_damage": true, "unavoidable": true})


func _process_incubators() -> void:
	for b in GameState.state["buildings"]:
		if b["type"] != "incubator":
			continue
		var d: Dictionary = b.get("data", {})
		if not d.has("egg"):
			continue
		var egg: Dictionary = d["egg"]
		var now := GameState.get_day() * 24.0 + GameState.get_hour()
		if now >= float(egg["ready_at"]):
			d.erase("egg")
			if egg.get("dud", false):
				EventBus.notify.emit("Das Ei in der Brutstätte hat sich nicht entwickelt.", "warn")
				continue
			hatch_egg(egg, Vector3(b["pos"][0], b["pos"][1], b["pos"][2]))


func hatch_egg(egg: Dictionary, pos: Vector3) -> int:
	var genes: Dictionary = egg["genes"]
	var species: String = genes.get("species", "raptor")
	var imprint := 0.15 * GameState.skill_rank("tame_imprint")
	if imprint > 0.0:
		for k in genes["stats_q"]:
			genes["stats_q"][k] = minf(0.99, float(genes["stats_q"][k]) + imprint * 0.3)
	var uid := GameState.create_creature(species if species != "hybrid" else "hybrid", 1, {"genes": genes, "method": "egg", "bond": 50.0 + imprint * 100.0,
		"parents": egg.get("parents", []), "parent_names": egg.get("parent_names", []), "growth": 0.35})
	var rec := GameState.creature(uid)
	if species == "hybrid":
		GameState.state["stats"]["hybrids"] += 1
		rec["name"] = egg.get("name", rec["name"])
	GameState.set_creature_status(uid, "base" if GameState.has_base() else "party")
	EventBus.creature_born.emit(uid)
	EventBus.notify.emit("Geschlüpft: %s (%s)! Es wächst mit der Zeit heran." % [rec["name"], Creatures.display_species(rec)], "good")
	Audio.play_ui("ui_quest")
	if egg.get("breakout", false):
		rec["genes"]["mutations"].append("jaehzornig")
		rec["bond"] = 5.0
		EventBus.notify.emit("Das Geschöpf ist aggressiv und kaum zu kontrollieren!", "danger")
	return uid


# ------------------------------------------------------------------ resources & harvesting
func _build_resources() -> void:
	var res: Array = WorldData.info["resources"]
	var meshes := {"rock": FloraLibrary.mesh("rock_small", 0)}
	for i in res.size():
		var r: Dictionary = res[i]
		var key := "res_%d" % i
		var harvested: Dictionary = GameState.state["world"]["harvested"]
		var node := StaticBody3D.new()
		node.collision_layer = 64
		add_child(node)
		node.global_position = Vector3(r["x"], r["y"] - 0.2, r["z"])
		var t: String = r["type"]
		if t in ["herb_patch", "mushroom"]:
			var mi := MeshInstance3D.new()
			mi.mesh = FloraLibrary.mesh("fern" if t == "herb_patch" else "berry_bush", 0)
			mi.scale = Vector3.ONE * (0.7 if t == "herb_patch" else 0.4)
			node.add_child(mi)
			if t == "mushroom":
				for k in 5:
					var cm := CylinderMesh.new()
					cm.top_radius = 0.0
					cm.bottom_radius = 0.12
					cm.height = 0.12
					var m2 := MeshInstance3D.new()
					m2.mesh = cm
					m2.material_override = BuildingVisuals.plain("shroom", Color(0.75, 0.55, 0.35))
					m2.position = Vector3(cos(k) * 0.4, 0.18, sin(k * 1.3) * 0.4)
					node.add_child(m2)
		else:
			var mi2 := MeshInstance3D.new()
			mi2.mesh = meshes["rock"]
			mi2.material_override = FloraLibrary.ore_material(t)
			mi2.scale = Vector3.ONE * 1.3
			node.add_child(mi2)
			var cs := CollisionShape3D.new()
			var sh := SphereShape3D.new()
			sh.radius = 0.9
			cs.shape = sh
			cs.position = Vector3(0, 0.4, 0)
			node.add_child(cs)
			if t in ["crystal", "rift_crystal"]:
				Fx.glow_light(node, Color(0.4, 0.7, 1.0) if t == "crystal" else Color(0.9, 0.15, 0.5), 5.0, 0.8).position = Vector3(0, 1, 0)
		node.set_meta("res", i)
		resource_nodes[i] = node
		if harvested.has(key) and not vegetation._respawned(harvested[key]):
			node.visible = false
			node.collision_layer = 0
		var it := Interactable.new()
		it.radius = 2.8
		it.prompt_fn = func(_p): return "E: %s sammeln" % _res_name(t) if node.visible else ""
		it.condition = func(_p): return node.visible
		it.on_interact = func(p): harvest_resource(i, p.combat.weapon_stats() if p.has_method("get_reach") else {}, true)
		node.add_child(it)


func _res_name(t: String) -> String:
	return {"ore_metal": "Metallerz", "ore_obsidian": "Obsidian", "flint": "Feuerstein", "crystal": "Kristall", "rift_crystal": "Risskristall",
		"salt": "Salz", "clay": "Lehm", "sulfur": "Schwefel", "herb_patch": "Heilkräuter", "mushroom": "Pilze"}.get(t, t)


func harvest_resource(i: int, tool: Dictionary, by_hand: bool) -> void:
	var r: Dictionary = WorldData.info["resources"][i]
	var t: String = r["type"]
	var node: Node3D = resource_nodes[i]
	if not node.visible:
		return
	var yields := {"ore_metal": [["metal_ore", 2], ["stone", 1]], "ore_obsidian": [["obsidian", 2]], "flint": [["flint", 3]],
		"crystal": [["crystal", 2]], "rift_crystal": [["rift_shard", 1], ["demon_essence", 1]], "salt": [["salt", 3]],
		"clay": [["clay", 3]], "sulfur": [["sulfur", 3]], "herb_patch": [["herb_healing", 2], ["fiber", 1]], "mushroom": [["mushroom", 2]]}
	var hand_ok := t in ["herb_patch", "mushroom", "salt", "clay"]
	var power := 1.0
	if not hand_ok:
		power = float(tool.get("harvest_ore", tool.get("harvest_stone", 0.0)))
		if power <= 0.0:
			EventBus.notify.emit("Du brauchst eine Spitzhacke für %s." % _res_name(t), "warn")
			return
	var inv: Array = GameState.player()["inventory"]
	var got := []
	for y in yields.get(t, []):
		var n := maxi(1, int(round(y[1] * power * (1.0 + 0.25 * GameState.skill_rank("surv_forage")))))
		Inventory.add(inv, y[0], n)
		got.append("%d× %s" % [n, DB.item_name(y[0])])
	if t == "rift_crystal":
		player.combatant.take_hit({"amount": 8.0, "elements": ["shadow"], "true_damage": true, "unavoidable": true})
		GameState.player()["demon"]["hints"]["crystal"] = true
	node.visible = false
	node.collision_layer = 0
	GameState.state["world"]["harvested"]["res_%d" % i] = {"respawn": GameState.get_day() + GameState.get_hour() / 24.0 + 3.0}
	Audio.play_at("mine" if not hand_ok else "pickup", node.global_position)
	EventBus.notify.emit("Gesammelt: " + ", ".join(got), "info")
	EventBus.item_picked.emit(t, 1)
	EventBus.inventory_changed.emit()
	player.play_action("gather", 0.7)


func harvest_hit(p: Node3D, origin: Vector3, fwd: Vector3, reach: float, tool: Dictionary) -> void:
	# resource nodes first
	for i in resource_nodes:
		var n: Node3D = resource_nodes[i]
		if n.visible and n.global_position.distance_to(origin) < reach + 1.2:
			harvest_resource(i, tool, false)
			return
	var idx := vegetation.nearest(origin, fwd, reach)
	if idx < 0:
		return
	var got := vegetation.harvest(idx, tool, false)
	_give(got)


func hand_gather(p: Node3D) -> bool:
	var idx := vegetation.nearest(p.global_position, p.get_forward(), 2.5, true)
	if idx < 0:
		return false
	var got := vegetation.harvest(idx, {}, true)
	if got.is_empty():
		return false
	player.play_action("gather", 0.6)
	_give(got)
	return true


func _give(got: Array) -> void:
	if got.is_empty():
		return
	var inv: Array = GameState.player()["inventory"]
	var names := []
	for g in got:
		Inventory.add(inv, g[0], int(g[1]))
		names.append("+%d %s" % [g[1], DB.item_name(g[0])])
	EventBus.notify.emit(", ".join(names), "info")
	EventBus.inventory_changed.emit()


func drop_loot(pos: Vector3, items: Array) -> void:
	var real := []
	for it in items:
		if it[0] == "amber_coin":
			GameState.add_amber(int(it[1]))
			EventBus.notify.emit("+%d Bernstein" % it[1], "good")
		else:
			real.append(it)
	if real.is_empty():
		return
	var bag := Node3D.new()
	fx_root.add_child(bag)
	bag.global_position = Vector3(pos.x, WorldData.height_at(pos.x, pos.z) + 0.2, pos.z)
	BuildingVisuals.box(bag, Vector3(0.5, 0.35, 0.4), Vector3(0, 0.17, 0), BuildingVisuals.hide_m())
	var it := Interactable.new()
	it.prompt = "E: Beute aufheben"
	it.radius = 2.5
	bag.add_child(it)
	it.on_interact = func(_p):
		_give(real)
		bag.queue_free()


func place_trap(id: String, pos: Vector3) -> void:
	var trap := Area3D.new()
	trap.collision_layer = 0
	trap.collision_mask = 4
	fx_root.add_child(trap)
	trap.global_position = pos
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.2
	cs.shape = sh
	trap.add_child(cs)
	BuildingVisuals.cyl(trap, 0.6, 0.65, 0.12, Vector3(0, 0.06, 0), BuildingVisuals.plain("trapm", Color(0.35, 0.3, 0.25), 0.7, 0.3))
	var stats: Dictionary = DB.item(id).get("stats", {})
	var used := [false]
	trap.body_entered.connect(func(b):
		if used[0] or not b is Creature or not b.wild:
			return
		used[0] = true
		var hold := float(stats.get("hold", 5.0)) * (1.0 + 0.25 * GameState.skill_rank("hunt_traps"))
		if b.body_h > 3.0 and id != "trap_spike":
			hold *= 0.3
		b.combatant.apply_status("entangled", hold, player)
		AbilityRunner.apply_hit(player, b, {"amount": float(stats.get("dmg", 0)), "torpor": float(stats.get("torpor", 0)), "from_player": true})
		EventBus.notify.emit("Falle ausgelöst: %s gefangen!" % b.sp.get("name", ""), "good")
		Audio.play_at("block", trap.global_position)
		trap.get_tree().create_timer(hold).timeout.connect(trap.queue_free))
	EventBus.notify.emit("%s aufgestellt." % DB.item_name(id), "info")


func nearby_storages(pos: Vector3, r: float = 20.0) -> Array:
	var out := []
	for b in GameState.state["buildings"]:
		if DB.building(b["type"]).has("storage") and Vector2(b["pos"][0] - pos.x, b["pos"][2] - pos.z).length() < r:
			if not b.has("data"):
				b["data"] = {}
			if not b["data"].has("storage"):
				b["data"]["storage"] = []
			out.append(b["data"]["storage"])
	return out


func nearby_stations(pos: Vector3, r: float = 7.0) -> Array:
	var out := ["hand"]
	for b in GameState.state["buildings"]:
		var st: String = DB.building(b["type"]).get("station", "")
		if st != "" and Vector2(b["pos"][0] - pos.x, b["pos"][2] - pos.z).length() < r:
			out.append(st)
	for s in get_tree().get_nodes_in_group("village_stations"):
		if Vector2(s.global_position.x - pos.x, s.global_position.z - pos.z).length() < r:
			out.append(s.get_meta("station"))
	return out


func is_no_build(p: Vector3) -> bool:
	for id in WorldData.info["pois"]:
		var poi: Dictionary = WorldData.info["pois"][id]
		var r := float(poi.get("flatten", 25)) + 15.0
		if poi["kind"] in ["village", "camp", "rift", "shrine", "ruin", "citadel", "nest", "tarpit"]:
			if Vector2(p.x - poi["x"], p.z - poi["z"]).length() < r:
				return true
	return false


func is_no_spawn(p: Vector3) -> bool:
	for id in WorldData.info["pois"]:
		var poi: Dictionary = WorldData.info["pois"][id]
		if poi["kind"] in ["village", "camp"] and Vector2(p.x - poi["x"], p.z - poi["z"]).length() < float(poi.get("flatten", 30)) + 60.0:
			return true
	var bc := buildings.base_center()
	if bc != Vector3.INF and bc.distance_to(p) < 70.0:
		return true
	return false


func is_safe_place(p: Vector3) -> bool:
	for b in GameState.state["buildings"]:
		var bd := DB.building(b["type"])
		var bp := Vector3(b["pos"][0], b["pos"][1], b["pos"][2])
		if bd.get("safe_save", false) or bd.get("bed", false):
			if bp.distance_to(p) < (float(bd.get("base_radius", 12.0))):
				return true
	for id in ["morgengrau", "moosfell", "fischerkap"]:
		var poi := WorldData.poi(id)
		if Vector2(p.x - poi["x"], p.z - poi["z"]).length() < 50.0:
			return true
	if id_near("knochenbrecher", p, 50.0) and GameState.rep("knochenbrecher") >= 20:
		return true
	return false


func id_near(poi_id: String, p: Vector3, r: float) -> bool:
	var poi := WorldData.poi(poi_id)
	return not poi.is_empty() and Vector2(p.x - poi["x"], p.z - poi["z"]).length() < r


# ------------------------------------------------------------------ discovery & regions
func _check_discovery() -> void:
	var pp := player.global_position
	for id in WorldData.info["pois"]:
		var poi: Dictionary = WorldData.info["pois"][id]
		var r := maxf(40.0, float(poi.get("flatten", 30)) + 15.0)
		if Vector3(poi["x"], poi.get("y", pp.y), poi["z"]).distance_to(pp) < r:
			if GameState.discover(id):
				EventBus.notify.emit("Entdeckt: " + poi["name"], "quest")
				GameState.add_xp(25, "discover")
				Audio.play_ui("ui_quest")
				if poi["kind"] in ["ruin", "underwater_ruin"]:
					Research.add_points(2)
	# lexicon: see creatures nearby
	for c in get_tree().get_nodes_in_group("creatures"):
		if c.wild and c.global_position.distance_to(pp) < 50.0:
			GameState.lexicon_mark(c.species_id, "seen")


func _update_region(force: bool) -> void:
	var pp := player.global_position
	var reg := WorldData.region_at(pp.x, pp.z)
	var rid: String = reg.get("id", "")
	if rid != _region_id or force:
		_region_id = rid
		if rid != "":
			EventBus.region_entered.emit(rid)
			if not force:
				EventBus.notify.emit("— %s —  (Stufe %d–%d)" % [reg["name"], reg["levels"][0], reg["levels"][1]], "region")
		var kind := "core"
		for isl in WorldData.info["islands"]:
			if Vector2(pp.x - isl["x"], pp.z - isl["z"]).length() < float(isl["r"]) * 1.1:
				kind = isl["kind"]
		if kind != sky.region_kind:
			sky.region_kind = kind
			sky._pick_target()


func _update_music() -> void:
	var combat := false
	var boss := false
	for c in get_tree().get_nodes_in_group("creatures"):
		if c.wild and c.ai.target == player and c.ai.state in ["chase", "attack"] and c.global_position.distance_to(player.global_position) < 40.0:
			combat = true
			if c.is_boss:
				boss = true
	for n in get_tree().get_nodes_in_group("npcs"):
		if n.target == player and n.global_position.distance_to(player.global_position) < 30.0:
			combat = true
	var biome := WorldData.biome_at(player.global_position.x, player.global_position.z)
	if boss:
		Audio.set_music("boss")
	elif combat:
		Audio.set_music("combat")
	elif biome == 10 or sky.weather == "demon_storm" or player.demon_form:
		Audio.set_music("demon")
	elif sky.is_night():
		Audio.set_music("night")
	else:
		Audio.set_music("explore")


func _on_player_died() -> void:
	var p := GameState.player()
	if GameState.rule("player_permadeath"):
		p["dead"] = true
		SaveSystem.delete_slot(GameState.state.get("slot", "auto"))
		SaveSystem.delete_slot("auto")
		return
	if GameState.rule("drop_on_death"):
		var bag = p["inventory"].duplicate(true)
		p["inventory"] = []
		var pos := player.global_position
		var node := Node3D.new()
		fx_root.add_child(node)
		node.global_position = Vector3(pos.x, maxf(WorldData.height_at(pos.x, pos.z), 0.0) + 0.3, pos.z)
		BuildingVisuals.box(node, Vector3(0.6, 0.45, 0.5), Vector3(0, 0.22, 0), BuildingVisuals.hide_m())
		Fx.glow_light(node, Color(1.0, 0.8, 0.3), 6.0, 1.5).position = Vector3(0, 1, 0)
		var it := Interactable.new()
		it.prompt = "E: Deine verlorene Ausrüstung aufnehmen"
		it.radius = 3.0
		node.add_child(it)
		it.on_interact = func(_pl):
			for st in bag:
				Inventory.add(GameState.player()["inventory"], st["id"], int(st["n"]), float(st.get("q", 1.0)), st.get("d", {}))
			EventBus.inventory_changed.emit()
			EventBus.notify.emit("Ausrüstung zurückgeholt.", "good")
			node.queue_free()
		p["death_bag"] = [pos.x, pos.y, pos.z]
	EventBus.inventory_changed.emit()


func before_save() -> void:
	if player:
		var pp := caves.save_position(player.global_position) if caves else player.global_position
		GameState.player()["pos"] = [pp.x, pp.y, pp.z]
	for n in get_tree().get_nodes_in_group("companions"):
		var cp: Vector3 = caves.save_position(n.global_position) if caves and caves.active != "" else n.global_position
		n.rec["pos"] = [cp.x, cp.y, cp.z]
		n.rec["hp"] = n.combatant.hp


# ------------------------------------------------------------------ settlements, POIs, encounters
func _build_settlements() -> void:
	Settlements.build(self)


func _update_encounters() -> void:
	Encounters.update(self)
