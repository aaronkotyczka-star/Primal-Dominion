class_name GearFactory
extends RefCounted
## Procedural meshes for weapons, tools and armor pieces (visible equipment).

static var _mats := {}

const MAT_COLORS := {
	"wood": Color(0.42, 0.29, 0.17), "hardwood": Color(0.3, 0.18, 0.1), "stone": Color(0.45, 0.43, 0.4),
	"flint": Color(0.3, 0.3, 0.32), "bone": Color(0.82, 0.78, 0.66), "large_bone": Color(0.82, 0.78, 0.66),
	"obsidian": Color(0.05, 0.04, 0.06), "metal_ingot": Color(0.6, 0.6, 0.62), "crystal": Color(0.4, 0.7, 1.0),
	"horn": Color(0.25, 0.2, 0.15), "raptor_claw": Color(0.2, 0.17, 0.14), "trex_tooth": Color(0.9, 0.86, 0.72),
	"saber_fang": Color(0.9, 0.86, 0.72), "shark_tooth": Color(0.9, 0.9, 0.85), "fiber": Color(0.55, 0.5, 0.3),
	"sinew": Color(0.6, 0.45, 0.35), "silk": Color(0.9, 0.9, 0.85), "leather": Color(0.35, 0.22, 0.13),
}


static func mat(col: Color, metallic: float = 0.0, rough: float = 0.75, emissive: bool = false) -> StandardMaterial3D:
	var key := "%s_%.2f_%.2f_%s" % [col.to_html(), metallic, rough, emissive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.metallic = metallic
	m.roughness = rough
	if emissive:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.5
	_mats[key] = m
	return m


static func _mat_for(id: String) -> StandardMaterial3D:
	var c: Color = MAT_COLORS.get(id, Color(0.5, 0.5, 0.5))
	if id == "metal_ingot":
		return mat(c, 0.85, 0.35)
	if id == "obsidian":
		return mat(c, 0.1, 0.08)
	if id == "crystal":
		return mat(c, 0.0, 0.1, true)
	return mat(c)


static func _cyl(parent: Node3D, r1: float, r2: float, h: float, pos: Vector3, rot: Vector3, m: Material, segs: int = 8) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r2
	cm.height = h
	cm.radial_segments = segs
	cm.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, size: Vector3, pos: Vector3, rot: Vector3, m: Material) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## Weapon node in hand space: grip at origin, weapon pointing along +Y (up out of fist) / -Z forward.
static func make_weapon(stack: Dictionary) -> Node3D:
	var root := Node3D.new()
	if stack.is_empty():
		return root
	var it := DB.item(stack["id"])
	var d: Dictionary = stack.get("d", {})
	var head_mat := _mat_for(d.get("head", _default_head(stack["id"])))
	var shaft_mat := _mat_for(d.get("shaft", "wood"))
	var bind_mat := _mat_for(d.get("binding", "fiber"))
	var wt: String = it.get("wtype", "")
	match wt:
		"spear":
			_cyl(root, 0.022, 0.025, 2.1, Vector3(0, 0.55, 0), Vector3.ZERO, shaft_mat)
			_cyl(root, 0.0, 0.045, 0.28, Vector3(0, 1.73, 0), Vector3.ZERO, head_mat, 4)
			_cyl(root, 0.03, 0.03, 0.12, Vector3(0, 1.55, 0), Vector3.ZERO, bind_mat)
		"club":
			_cyl(root, 0.075, 0.03, 0.85, Vector3(0, 0.38, 0), Vector3.ZERO, shaft_mat)
			_cyl(root, 0.035, 0.035, 0.12, Vector3(0, 0.02, 0), Vector3.ZERO, bind_mat)
		"axe":
			_cyl(root, 0.022, 0.026, 0.8, Vector3(0, 0.3, 0), Vector3.ZERO, shaft_mat)
			_box(root, Vector3(0.05, 0.16, 0.2), Vector3(0, 0.62, -0.1), Vector3.ZERO, head_mat)
			_cyl(root, 0.03, 0.03, 0.08, Vector3(0, 0.62, 0), Vector3.ZERO, bind_mat)
		"pick":
			_cyl(root, 0.022, 0.026, 0.8, Vector3(0, 0.3, 0), Vector3.ZERO, shaft_mat)
			_cyl(root, 0.0, 0.04, 0.4, Vector3(0, 0.66, -0.18), Vector3(PI * 0.5, 0, 0), head_mat, 5)
			_cyl(root, 0.0, 0.04, 0.25, Vector3(0, 0.66, 0.12), Vector3(-PI * 0.5, 0, 0), head_mat, 5)
		"sword":
			_box(root, Vector3(0.05, 0.85, 0.012), Vector3(0, 0.55, 0), Vector3.ZERO, head_mat)
			_box(root, Vector3(0.2, 0.03, 0.04), Vector3(0, 0.12, 0), Vector3.ZERO, mat(Color(0.3, 0.25, 0.2), 0.5, 0.5))
			_cyl(root, 0.018, 0.018, 0.18, Vector3(0, 0.02, 0), Vector3.ZERO, bind_mat)
		"bow":
			for i in 7:
				var a := (i - 3) / 3.0
				var seg := _cyl(root, 0.016, 0.02, 0.24, Vector3(0, a * 0.62, -absf(a) * absf(a) * 0.16 + 0.08), Vector3(-a * 0.55, 0, 0), shaft_mat)
			_cyl(root, 0.003, 0.003, 1.3, Vector3(0, 0, 0.18), Vector3.ZERO, mat(Color(0.85, 0.85, 0.8)))
		"crossbow":
			_box(root, Vector3(0.06, 0.06, 0.7), Vector3(0, 0.05, -0.2), Vector3.ZERO, shaft_mat)
			_box(root, Vector3(0.7, 0.03, 0.04), Vector3(0, 0.08, -0.5), Vector3.ZERO, mat(Color(0.55, 0.55, 0.57), 0.8, 0.4))
		"gun":
			_cyl(root, 0.025, 0.03, 0.9, Vector3(0, 0.08, -0.4), Vector3(PI * 0.5, 0, 0), mat(Color(0.35, 0.35, 0.37), 0.9, 0.35))
			_box(root, Vector3(0.06, 0.12, 0.45), Vector3(0, 0.0, 0.15), Vector3(0.25, 0, 0), shaft_mat)
			if stack["id"] == "runenbuechse":
				_cyl(root, 0.04, 0.04, 0.12, Vector3(0, 0.1, -0.2), Vector3(PI * 0.5, 0, 0), mat(Color(0.3, 0.6, 1.0), 0, 0.1, true))
		"staff":
			_cyl(root, 0.022, 0.03, 1.8, Vector3(0, 0.45, 0), Vector3.ZERO, shaft_mat)
			if stack["id"] == "staff_crystal" or d.get("focus", "") == "crystal":
				var sm := SphereMesh.new()
				sm.radius = 0.08
				sm.height = 0.2
				var mi := MeshInstance3D.new()
				mi.mesh = sm
				mi.material_override = mat(Color(0.4, 0.7, 1.0), 0, 0.1, true)
				mi.position = Vector3(0, 1.42, 0)
				root.add_child(mi)
				Fx.glow_light(mi, Color(0.4, 0.7, 1.0), 4.0, 0.8)
		"shield":
			var sm2 := _cyl(root, 0.32, 0.32, 0.04, Vector3(0, 0.15, -0.1), Vector3(PI * 0.5, 0, 0), mat(Color(0.4, 0.28, 0.16)) if stack["id"] != "shield_metal" else mat(Color(0.55, 0.55, 0.57), 0.8, 0.4), 16)
		"torch":
			_cyl(root, 0.03, 0.025, 0.6, Vector3(0, 0.22, 0), Vector3.ZERO, shaft_mat)
			var flame := Node3D.new()
			flame.position = Vector3(0, 0.6, 0)
			root.add_child(flame)
			_flame(flame, 0.6)
		"throw":
			if stack["id"] == "bola":
				for k in 3:
					var sm3 := SphereMesh.new()
					sm3.radius = 0.04
					sm3.height = 0.08
					var mi3 := MeshInstance3D.new()
					mi3.mesh = sm3
					mi3.material_override = mat(Color(0.4, 0.38, 0.35))
					mi3.position = Vector3(cos(k * 2.1) * 0.12, 0.1, sin(k * 2.1) * 0.12)
					root.add_child(mi3)
			elif stack["id"] == "javelin":
				_cyl(root, 0.018, 0.02, 1.4, Vector3(0, 0.4, 0), Vector3.ZERO, shaft_mat)
				_cyl(root, 0.0, 0.035, 0.2, Vector3(0, 1.2, 0), Vector3.ZERO, head_mat, 4)
			else:
				var sm4 := SphereMesh.new()
				sm4.radius = 0.1
				sm4.height = 0.2
				var mi4 := MeshInstance3D.new()
				mi4.mesh = sm4
				mi4.material_override = mat(Color(0.5, 0.35, 0.25))
				root.add_child(mi4)
		"blowpipe":
			_cyl(root, 0.015, 0.015, 0.9, Vector3(0, 0.3, 0), Vector3.ZERO, shaft_mat)
	return root


static func _default_head(id: String) -> String:
	if id.ends_with("_metal"):
		return "metal_ingot"
	if id.ends_with("_stone"):
		return "flint"
	return "stone"


static func _flame(parent: Node3D, size: float) -> void:
	var p := CPUParticles3D.new()
	p.amount = 24
	p.lifetime = 0.6
	p.direction = Vector3.UP
	p.spread = 15.0
	p.initial_velocity_min = 0.6 * size
	p.initial_velocity_max = 1.2 * size
	p.gravity = Vector3(0, 1.5, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.2
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.18) * size
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	q.material = m
	p.mesh = q
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.7, 0.25, 0.9))
	g.set_color(1, Color(0.8, 0.15, 0.02, 0.0))
	p.color_ramp = g
	parent.add_child(p)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.6, 0.3)
	l.omni_range = 9.0 * size + 3.0
	l.light_energy = 1.6
	l.shadow_enabled = true
	parent.add_child(l)
	l.set_meta("flicker", true)


static func make_flame(parent: Node3D, size: float) -> void:
	_flame(parent, size)


static func armor_colors(equipment: Dictionary) -> Dictionary:
	var out := {}
	var chest: String = equipment.get("chest", "")
	var legs: String = equipment.get("legs", "")
	var head: String = equipment.get("head", "")
	if chest != "":
		var c: Array = DB.item(chest).get("color", [0.4, 0.3, 0.2])
		out["top_color"] = c
	else:
		out["top_color"] = [0.5, 0.45, 0.38]
	if legs != "":
		out["bottom_color"] = DB.item(legs).get("color", [0.3, 0.25, 0.2])
	else:
		out["bottom_color"] = [0.32, 0.28, 0.22]
	if head != "":
		out["hair_color"] = DB.item(head).get("color", [0.3, 0.25, 0.2])
	return out
