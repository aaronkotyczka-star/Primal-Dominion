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
		return tex_mat(c, "metal_scratch", 0.85, 0.32)
	if id == "obsidian":
		return tex_mat(c, "stone_chip", 0.1, 0.08)
	if id == "crystal":
		return mat(c, 0.0, 0.1, true)
	if id in ["wood", "hardwood"]:
		return tex_mat(c * 1.3, "wood_grain", 0.0, 0.7, 6.0)
	if id in ["stone", "flint"]:
		return tex_mat(c * 1.25, "stone_chip", 0.0, 0.55, 5.0)
	if id in ["leather", "sinew"]:
		return tex_mat(c * 1.4, "leather", 0.0, 0.7, 8.0)
	if id in ["fiber", "silk"]:
		return tex_mat(c * 1.3, "thatch", 0.0, 0.9, 10.0)
	return mat(c)


## Material with a tiling detail texture (object-space triplanar, so it stays put on moving gear).
static func tex_mat(col: Color, tex: String, metallic: float, rough: float, scale: float = 4.0) -> StandardMaterial3D:
	var key := "t_%s_%s_%.2f_%.2f" % [col.to_html(), tex, metallic, rough]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.albedo_texture = load("res://assets/textures/%s.png" % tex)
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(scale, scale, scale)
	m.metallic = metallic
	m.roughness = rough
	_mats[key] = m
	return m


## Flat, double-edged blade with a centre ridge (knapped stone point, axe bit, sword).
## profile: [Vector2(half_width, y)] from base to tip; thick: ridge half-thickness at the base.
static func _blade(parent: Node3D, profile: Array, thick: float, pos: Vector3, rot: Vector3, m: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := profile.size()
	var y0: float = profile[0].y
	var y1: float = profile[n - 1].y
	for i in n - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		var ta := thick * (1.0 - 0.75 * (a.y - y0) / maxf(y1 - y0, 1e-4))
		var tb := thick * (1.0 - 0.75 * (b.y - y0) / maxf(y1 - y0, 1e-4))
		for side in [-1.0, 1.0]:
			for face in [-1.0, 1.0]:
				var ea := Vector3(side * a.x, a.y, 0)
				var eb := Vector3(side * b.x, b.y, 0)
				var ra := Vector3(0, a.y, face * ta)
				var rb := Vector3(0, b.y, face * tb)
				if side * face > 0:
					st.add_vertex(ea); st.add_vertex(eb); st.add_vertex(ra)
					st.add_vertex(ra); st.add_vertex(eb); st.add_vertex(rb)
				else:
					st.add_vertex(ea); st.add_vertex(ra); st.add_vertex(eb)
					st.add_vertex(ra); st.add_vertex(rb); st.add_vertex(eb)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


## Lashing: a few thin rings around a shaft.
static func _wrap(parent: Node3D, r: float, y: float, h: float, m: Material) -> void:
	var k := int(h / 0.018)
	for i in k:
		_cyl(parent, r, r, 0.012, Vector3(0, y - h * 0.5 + i * 0.018, 0), Vector3(0.12 * (1 if i % 2 == 0 else -1), 0, 0), m, 8)


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
	root.set_meta("wtype", wt)
	match wt:
		"spear":
			_cyl(root, 0.021, 0.025, 2.1, Vector3(0, 0.55, 0), Vector3.ZERO, shaft_mat)
			_blade(root, [Vector2(0.012, 0.0), Vector2(0.042, 0.07), Vector2(0.038, 0.16), Vector2(0.0, 0.3)], 0.012, Vector3(0, 1.57, 0), Vector3.ZERO, head_mat)
			_wrap(root, 0.026, 1.58, 0.1, bind_mat)
		"club":
			_cyl(root, 0.07, 0.028, 0.85, Vector3(0, 0.38, 0), Vector3.ZERO, shaft_mat, 10)
			var knob := SphereMesh.new()
			knob.radius = 0.085
			knob.height = 0.15
			var kmi := MeshInstance3D.new()
			kmi.mesh = knob
			kmi.material_override = shaft_mat
			kmi.position = Vector3(0, 0.8, 0)
			root.add_child(kmi)
			for k in 5:
				_cyl(root, 0.0, 0.018, 0.06, Vector3(cos(k * 1.26) * 0.075, 0.62 + k * 0.04, sin(k * 1.26) * 0.075), Vector3(0, -k * 1.26, -PI * 0.5), _mat_for("raptor_claw" if d.get("head", "") == "" else d["head"]), 4)
			_wrap(root, 0.034, 0.02, 0.12, bind_mat)
		"axe":
			_cyl(root, 0.022, 0.027, 0.8, Vector3(0, 0.3, 0), Vector3.ZERO, shaft_mat)
			# wedge-shaped bit pointing forward (-Z), lashed to the haft
			var bit := _blade(root, [Vector2(0.045, 0.0), Vector2(0.06, 0.08), Vector2(0.085, 0.16), Vector2(0.11, 0.2)], 0.02, Vector3(0, 0.62, -0.02), Vector3.ZERO, head_mat)
			bit.basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0)).scaled(Vector3.ONE * 1.5)
			_wrap(root, 0.032, 0.62, 0.09, bind_mat)
		"pick":
			_cyl(root, 0.022, 0.026, 0.8, Vector3(0, 0.3, 0), Vector3.ZERO, shaft_mat)
			var pf := _blade(root, [Vector2(0.035, 0.0), Vector2(0.03, 0.12), Vector2(0.0, 0.3)], 0.022, Vector3(0, 0.66, -0.01), Vector3.ZERO, head_mat)
			pf.basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, -1), Vector3(-1, 0, 0))
			var pb := _blade(root, [Vector2(0.035, 0.0), Vector2(0.025, 0.08), Vector2(0.0, 0.16)], 0.02, Vector3(0, 0.66, 0.01), Vector3.ZERO, head_mat)
			pb.basis = Basis(Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0))
			_wrap(root, 0.032, 0.66, 0.08, bind_mat)
		"sword":
			_blade(root, [Vector2(0.028, 0.0), Vector2(0.026, 0.55), Vector2(0.02, 0.72), Vector2(0.0, 0.82)], 0.006, Vector3(0, 0.13, 0), Vector3.ZERO, head_mat)
			_box(root, Vector3(0.2, 0.025, 0.035), Vector3(0, 0.12, 0), Vector3.ZERO, tex_mat(Color(0.55, 0.45, 0.3), "metal_scratch", 0.8, 0.4))
			_wrap(root, 0.019, 0.03, 0.17, _mat_for("leather"))
			var pom := SphereMesh.new()
			pom.radius = 0.025
			pom.height = 0.05
			var pmi := MeshInstance3D.new()
			pmi.mesh = pom
			pmi.material_override = tex_mat(Color(0.55, 0.45, 0.3), "metal_scratch", 0.8, 0.4)
			pmi.position = Vector3(0, -0.07, 0)
			root.add_child(pmi)
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
			var metal_sh: bool = stack["id"] == "shield_metal"
			var face := tex_mat(Color(1.0, 0.9, 0.8), "wood_planks", 0.0, 0.8, 2.0) if not metal_sh else tex_mat(Color(0.6, 0.6, 0.63), "metal_scratch", 0.85, 0.35)
			var rim := tex_mat(Color(0.5, 0.5, 0.52), "metal_scratch", 0.85, 0.4)
			_cyl(root, 0.32, 0.32, 0.035, Vector3(0, 0.15, -0.1), Vector3(PI * 0.5, 0, 0), face, 20)
			_cyl(root, 0.335, 0.335, 0.025, Vector3(0, 0.15, -0.1), Vector3(PI * 0.5, 0, 0), rim, 20)
			var boss := SphereMesh.new()
			boss.radius = 0.07
			boss.height = 0.07
			boss.is_hemisphere = true
			var bmi := MeshInstance3D.new()
			bmi.mesh = boss
			bmi.material_override = rim
			bmi.position = Vector3(0, 0.15, -0.12)
			bmi.rotation = Vector3(-PI * 0.5, 0, 0)
			root.add_child(bmi)
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
				_blade(root, [Vector2(0.01, 0.0), Vector2(0.032, 0.05), Vector2(0.0, 0.2)], 0.01, Vector3(0, 1.1, 0), Vector3.ZERO, head_mat)
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
