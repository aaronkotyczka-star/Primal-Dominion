class_name Caves
extends Node3D
## Walkable cave interiors. Each cave mesh (tools/assetgen/gen_caves.py) is placed high above the
## open sea outside the island map; entering/leaving teleports the player (and nearby companions)
## between the cave mouth and the cave entry. Content: crystals with light, loot, cave creatures.

const ORIGINS := {"wurzelhoehle": Vector3(1750.0, 620.0, 1750.0), "weisszahn_hoehle": Vector3(-1750.0, 620.0, 1750.0)}
const NAMES := {"wurzelhoehle": "Wurzelhöhlen", "weisszahn_hoehle": "Eisgrotte"}

var world: Node3D
var active := ""
var _built := {}
var _mouth := Vector3.ZERO
var _spawned: Array = []


func setup(w: Node3D) -> void:
	world = w
	name = "Caves"


static func meta(id: String) -> Dictionary:
	var f := FileAccess.open("res://assets/world/cave_%s.json" % id, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else {}


func origin(id: String) -> Vector3:
	return ORIGINS[id]


func enter(id: String, mouth: Vector3) -> void:
	if not ORIGINS.has(id):
		return
	_build(id)
	active = id
	_mouth = mouth
	var m := meta(id)
	var e: Array = m["entry"]
	var target: Vector3 = origin(id) + Vector3(e[0], e[1], e[2])
	_move_party(target)
	if world.get("sky"):
		world.sky.in_cave = true
	_spawn_creatures(id, m)
	EventBus.notify.emit("Du betrittst: %s." % NAMES[id], "region")
	EventBus.notify.emit("%s – Fackel oder Licht empfohlen." % NAMES[id], "info")


func leave() -> void:
	if active == "":
		return
	_move_party(_mouth)
	if world.get("sky"):
		world.sky.in_cave = false
	for c in _spawned:
		if is_instance_valid(c) and not c.is_in_group("companions"):
			c.queue_free()
	_spawned.clear()
	active = ""
	EventBus.notify.emit("Du verlässt die Höhle.", "info")


func _physics_process(_delta: float) -> void:
	# safety net: never lose the player through a crack in the cave mesh
	if active != "" and world and world.player and world.player.global_position.y < origin(active).y - 40.0:
		var e: Array = meta(active)["entry"]
		world.player.global_position = origin(active) + Vector3(e[0], e[1] + 0.5, e[2])
		world.player.velocity = Vector3.ZERO


## Position to store in a save while inside a cave: the mouth (caves are rebuilt on demand).
func save_position(p: Vector3) -> Vector3:
	return _mouth if active != "" else p


func _move_party(target: Vector3) -> void:
	var pl: Node3D = world.player
	var from := pl.global_position
	pl.global_position = target
	if pl is CharacterBody3D:
		(pl as CharacterBody3D).velocity = Vector3.ZERO
	var i := 0
	for c in get_tree().get_nodes_in_group("companions"):
		if c.global_position.distance_to(from) < 40.0 and c.rec.get("order", "follow") == "follow":
			i += 1
			var a := i * 1.3
			c.global_position = target + Vector3(cos(a) * 2.5, 0.4, sin(a) * 2.5 + 2.0)
			c.velocity = Vector3.ZERO


func _build(id: String) -> void:
	if _built.has(id):
		return
	var root := Node3D.new()
	root.name = "Cave_" + id
	add_child(root)
	root.global_position = origin(id)
	_built[id] = root
	var mesh := FloraLibrary.mesh("cave_" + id, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var rm := ShaderMaterial.new()
	rm.shader = load("res://shaders/rock.gdshader")
	rm.set_shader_parameter("albedo_arr", load("res://assets/textures/terrain_albedo_array.jpg"))
	rm.set_shader_parameter("normal_arr", load("res://assets/textures/terrain_nrm_array.png"))
	if id == "weisszahn_hoehle":
		rm.set_shader_parameter("moss_layer", 5.0)
		rm.set_shader_parameter("moss_amount", 0.7)
		rm.set_shader_parameter("tint", Color(0.82, 0.88, 0.98))
	else:
		rm.set_shader_parameter("moss_layer", 1.0)
		rm.set_shader_parameter("moss_amount", 0.8)
		rm.set_shader_parameter("tint", Color(0.78, 0.72, 0.66))
	mi.material_override = rm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	cs.shape = mesh.create_trimesh_shape()
	body.add_child(cs)
	root.add_child(body)
	var m := meta(id)
	var ice := id == "weisszahn_hoehle"
	var crystal_col := Color(0.4, 0.75, 1.0) if ice else Color(0.85, 0.3, 0.75)
	var cm := StandardMaterial3D.new()
	cm.albedo_color = crystal_col.darkened(0.5)
	cm.emission_enabled = true
	cm.emission = crystal_col
	cm.emission_energy_multiplier = 2.2
	cm.roughness = 0.15
	cm.metallic = 0.2
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	for p in m["crystals"]:
		var cr := MeshInstance3D.new()
		cr.mesh = FloraLibrary.mesh("crystal_corrupt", 0)
		cr.material_override = cm
		root.add_child(cr)
		cr.position = Vector3(p[0], p[1] - 0.1, p[2])
		cr.rotation.y = rng.randf() * TAU
		cr.scale = Vector3.ONE * rng.randf_range(0.5, 1.0)
		var l := OmniLight3D.new()
		l.light_color = crystal_col
		l.omni_range = 14.0
		l.light_energy = 3.0
		l.shadow_enabled = false
		l.position = cr.position + Vector3(0, 1.4, 0)
		root.add_child(l)
	for p in m["lights"]:
		# glowing fungus (root cave) / ice glow: soft fill so chambers are never pitch black
		var l := OmniLight3D.new()
		l.light_color = Color(0.55, 0.85, 0.6) if not ice else Color(0.6, 0.8, 1.0)
		l.omni_range = 22.0
		l.light_energy = 1.3
		l.position = Vector3(p[0], p[1] + 3.0, p[2])
		root.add_child(l)
		if not ice:
			for k in 6:
				var mu := MeshInstance3D.new()
				var sm := SphereMesh.new()
				sm.radius = rng.randf_range(0.08, 0.18)
				sm.height = sm.radius
				sm.is_hemisphere = true
				mu.mesh = sm
				var mm := StandardMaterial3D.new()
				mm.albedo_color = Color(0.3, 0.6, 0.4)
				mm.emission_enabled = true
				mm.emission = Color(0.4, 1.0, 0.6)
				mm.emission_energy_multiplier = 1.5
				mu.material_override = mm
				root.add_child(mu)
				mu.position = Vector3(p[0] + rng.randf_range(-2, 2), p[1] + 0.02, p[2] + rng.randf_range(-2, 2))
	var i := 0
	for lt in m["loot"]:
		var lp: Array = lt["pos"]
		Settlements.pickup(world, origin(id) + Vector3(lp[0], lp[1], lp[2]), lt["item"], int(lt["n"]), "cave_%s_%d" % [id, i], "", false)
		i += 1
	var ex: Array = m["exit"]
	var it := Interactable.new()
	it.prompt = "E: Höhle verlassen"
	it.radius = 3.0
	it.position = Vector3(ex[0], ex[1] + 1.0, ex[2])
	root.add_child(it)
	it.on_interact = func(_p): leave()
	var exit_light := OmniLight3D.new()
	exit_light.light_color = Color(1.0, 0.92, 0.75)
	exit_light.omni_range = 10.0
	exit_light.light_energy = 1.4
	exit_light.position = it.position + Vector3(0, 1.5, 1.0)
	root.add_child(exit_light)


func _spawn_creatures(id: String, m: Dictionary) -> void:
	var reg := WorldData.region_at(_mouth.x, _mouth.z)
	var lv: Array = reg.get("levels", [5, 12]) if not reg.is_empty() else [5, 12]
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for s in m["spawns"]:
		var sp: Array = s["pos"]
		for k in int(s["n"]):
			var p: Vector3 = origin(id) + Vector3(sp[0] + rng.randf_range(-2.5, 2.5), sp[1], sp[2] + rng.randf_range(-2.5, 2.5))
			var c: Creature = world.spawn_wild(s["species"], rng.randi_range(int(lv[0]), int(lv[1]) + 2), p)
			if c:
				c.global_position = p + Vector3(0, 0.6, 0)
				c.ai.home = c.global_position
				_spawned.append(c)
