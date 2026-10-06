class_name Fx
extends RefCounted
## Lightweight visual effects: floating text, hit sparks, element bursts, breath cones.

static var _mats := {}


static func _root(n: Node) -> Node:
	var w := n.get_tree().get_first_node_in_group("fx_root")
	return w if w else n.get_tree().current_scene


static func _unshaded(col: Color, additive: bool = true) -> StandardMaterial3D:
	var key := "%s_%s" % [col.to_html(), additive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = col
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	_mats[key] = m
	return m


static func element_color(elements: Array) -> Color:
	if elements.is_empty():
		return Color(1.0, 0.85, 0.6)
	var c := Color(0, 0, 0)
	for e in elements:
		var a: Array = DB.element(e).get("color", [1, 1, 1])
		c += Color(a[0], a[1], a[2])
	return c / float(elements.size())


static func float_text(target: Node, text: String, col: Color) -> void:
	if not is_instance_valid(target) or not target is Node3D:
		return
	var l := Label3D.new()
	l.text = text
	l.modulate = col
	l.outline_modulate = Color(0, 0, 0, 0.8)
	l.font_size = 48
	l.outline_size = 10
	l.pixel_size = 0.004
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = false
	var t3 := target as Node3D
	var h := 2.0
	if t3.has_method("get_body_height"):
		h = t3.get_body_height()
	_root(target).add_child(l)
	l.global_position = t3.global_position + Vector3(randf_range(-0.4, 0.4), h + 0.3, randf_range(-0.4, 0.4))
	l.scale = Vector3.ONE * clampf(h * 0.35, 0.8, 3.0)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "global_position", l.global_position + Vector3(0, 1.2, 0), 0.9)
	tw.tween_property(l, "modulate:a", 0.0, 0.9).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


static func burst(at: Vector3, col: Color, parent: Node, amount: int = 14, size: float = 0.12, speed: float = 3.0, life: float = 0.5) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = life
	p.explosiveness = 0.95
	p.direction = Vector3.UP
	p.spread = 180.0
	p.initial_velocity_min = speed * 0.5
	p.initial_velocity_max = speed
	p.gravity = Vector3(0, -6, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = _unshaded(col)
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, col)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	_root(parent).add_child(p)
	p.global_position = at
	p.emitting = true
	p.get_tree().create_timer(life + 0.5).timeout.connect(p.queue_free)


static func hit_spark(target: Node, elements: Array) -> void:
	if not is_instance_valid(target) or not target is Node3D:
		return
	var t3 := target as Node3D
	var h := 1.0
	if t3.has_method("get_body_height"):
		h = t3.get_body_height() * 0.6
	var col := element_color(elements) if not elements.is_empty() else Color(0.75, 0.08, 0.05)
	burst(t3.global_position + Vector3(0, h, 0), col, target, 10 if elements.is_empty() else 18, 0.1, 3.0)


static func heal_burst(target: Node) -> void:
	if target is Node3D:
		burst((target as Node3D).global_position + Vector3(0, 1.0, 0), Color(0.5, 1.0, 0.55), target, 24, 0.12, 1.5, 1.0)


static func shield_glow(target: Node) -> void:
	if target is Node3D:
		burst((target as Node3D).global_position + Vector3(0, 1.0, 0), Color(0.5, 0.75, 1.0), target, 30, 0.14, 1.2, 1.0)


static func cone_breath(actor: Node3D, origin: Vector3, dir: Vector3, rng: float, elements: Array) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 90
	p.lifetime = 0.7
	p.explosiveness = 0.3
	p.direction = Vector3(0, 0, -1)
	p.spread = 18.0
	p.initial_velocity_min = rng * 1.0
	p.initial_velocity_max = rng * 1.5
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 1.0
	p.scale_amount_max = 3.0
	var col := element_color(elements)
	var q := QuadMesh.new()
	q.size = Vector2(0.6, 0.6)
	q.material = _unshaded(col)
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, col * 1.5)
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	p.color_ramp = g
	_root(actor).add_child(p)
	p.global_position = origin
	p.look_at(origin + dir, Vector3.UP)
	p.emitting = true
	var light := OmniLight3D.new()
	light.light_color = col
	light.omni_range = rng
	light.light_energy = 2.0
	p.add_child(light)
	p.get_tree().create_timer(1.3).timeout.connect(p.queue_free)


static func glow_light(parent: Node3D, col: Color, rng: float, energy: float) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = col
	l.omni_range = rng
	l.light_energy = energy
	l.shadow_enabled = false
	parent.add_child(l)
	return l
