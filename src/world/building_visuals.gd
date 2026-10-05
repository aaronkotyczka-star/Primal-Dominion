class_name BuildingVisuals
extends RefCounted
## Procedural meshes for buildings and settlement props.

static var _m := {}


static func wood() -> Material:
	if not _m.has("wood"):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/textures/bark_albedo.png")
		m.normal_enabled = true
		m.normal_texture = load("res://assets/textures/bark_nrm.png")
		m.uv1_triplanar = true
		m.uv1_scale = Vector3(0.8, 0.8, 0.8)
		m.albedo_color = Color(0.95, 0.85, 0.75)
		m.roughness = 0.85
		_m["wood"] = m
	return _m["wood"]


static func stone() -> Material:
	if not _m.has("stone"):
		var rm := ShaderMaterial.new()
		rm.shader = load("res://shaders/rock.gdshader")
		rm.set_shader_parameter("albedo_arr", load("res://assets/textures/terrain_albedo_array.png"))
		rm.set_shader_parameter("normal_arr", load("res://assets/textures/terrain_nrm_array.png"))
		rm.set_shader_parameter("moss_amount", 0.15)
		_m["stone"] = rm
	return _m["stone"]


static func plain(key: String, col: Color, rough: float = 0.85, metal: float = 0.0, emis: float = 0.0) -> Material:
	if not _m.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = rough
		m.metallic = metal
		if emis > 0.0:
			m.emission_enabled = true
			m.emission = col
			m.emission_energy_multiplier = emis
		_m[key] = m
	return _m[key]


static func thatch() -> Material:
	return plain("thatch", Color(0.55, 0.45, 0.25), 0.95)


static func hide_m() -> Material:
	return plain("hide", Color(0.45, 0.33, 0.22), 0.8)


static func ghost(ok: bool) -> Material:
	var key := "ghost_ok" if ok else "ghost_bad"
	if not _m.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.3, 1.0, 0.4, 0.35) if ok else Color(1.0, 0.25, 0.2, 0.35)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = false
		_m[key] = m
	return _m[key]


static func box(p: Node3D, size: Vector3, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var bm := BoxMesh.new()
	bm.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi)
	return mi


static func cyl(p: Node3D, r1: float, r2: float, h: float, pos: Vector3, m: Material, rot: Vector3 = Vector3.ZERO, segs: int = 10) -> MeshInstance3D:
	var cm := CylinderMesh.new()
	cm.top_radius = r1
	cm.bottom_radius = r2
	cm.height = h
	cm.radial_segments = segs
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	p.add_child(mi)
	return mi


static func cone_roof(p: Node3D, r: float, h: float, y: float, m: Material) -> void:
	cyl(p, 0.05, r, h, Vector3(0, y + h * 0.5, 0), m, Vector3.ZERO, 12)


static func make(kind: String) -> Node3D:
	var n := Node3D.new()
	var bd := DB.building(kind)
	var size: Array = bd.get("size", [2, 2, 2])
	var sx := float(size[0])
	var sy := float(size[1])
	var sz := float(size[2])
	match kind:
		"camp_totem":
			cyl(n, 0.28, 0.35, 2.6, Vector3(0, 1.3, 0), wood())
			box(n, Vector3(1.3, 0.12, 0.25), Vector3(0, 2.2, 0), wood())
			var sk := SphereMesh.new()
			sk.radius = 0.25
			sk.height = 0.4
			var mi := MeshInstance3D.new()
			mi.mesh = sk
			mi.material_override = plain("bone", Color(0.85, 0.82, 0.72), 0.6)
			mi.position = Vector3(0, 2.65, 0)
			n.add_child(mi)
			for k in 6:
				var a := k * TAU / 6.0
				box(n, Vector3(0.35, 0.25, 0.3), Vector3(cos(a) * 0.9, 0.12, sin(a) * 0.9), stone(), Vector3(0, a, 0))
		"campfire":
			for k in 8:
				var a := k * TAU / 8.0
				box(n, Vector3(0.3, 0.22, 0.25), Vector3(cos(a) * 0.65, 0.11, sin(a) * 0.65), stone(), Vector3(0, a, 0))
			for k in 4:
				cyl(n, 0.06, 0.07, 0.9, Vector3(0, 0.18, 0), wood(), Vector3(PI * 0.42, k * PI * 0.5, 0))
			var f := Node3D.new()
			f.position = Vector3(0, 0.35, 0)
			n.add_child(f)
			GearFactory.make_flame(f, 1.6)
		"bedroll", "bed":
			if kind == "bed":
				box(n, Vector3(sx, 0.4, sz), Vector3(0, 0.2, 0), wood())
				box(n, Vector3(sx * 0.9, 0.15, sz * 0.92), Vector3(0, 0.47, 0), plain("pelt", Color(0.45, 0.36, 0.28), 1.0))
			else:
				box(n, Vector3(sx, 0.12, sz), Vector3(0, 0.06, 0), plain("pelt", Color(0.45, 0.36, 0.28), 1.0))
				cyl(n, 0.15, 0.15, sx * 0.9, Vector3(0, 0.15, -sz * 0.42), hide_m(), Vector3(0, 0, PI * 0.5))
		"storage_box", "storage_large":
			box(n, Vector3(sx, sy * 0.85, sz), Vector3(0, sy * 0.425, 0), wood())
			box(n, Vector3(sx * 1.04, sy * 0.15, sz * 1.04), Vector3(0, sy * 0.92, 0), wood())
			box(n, Vector3(sx * 1.05, 0.06, 0.06), Vector3(0, sy * 0.5, sz * 0.52), plain("iron", Color(0.3, 0.3, 0.32), 0.5, 0.7))
		"workbench", "research_table", "alchemy_table":
			box(n, Vector3(sx, 0.12, sz), Vector3(0, sy * 0.85, 0), wood())
			for x in [-1, 1]:
				for z in [-1, 1]:
					box(n, Vector3(0.12, sy * 0.85, 0.12), Vector3(x * (sx * 0.5 - 0.1), sy * 0.42, z * (sz * 0.5 - 0.1)), wood())
			if kind == "workbench":
				box(n, Vector3(0.5, 0.08, 0.2), Vector3(-0.4, sy * 0.95, 0), plain("iron", Color(0.3, 0.3, 0.32), 0.5, 0.7))
				box(n, Vector3(0.3, 0.3, 0.3), Vector3(0.6, sy * 1.06, 0.1), stone())
			elif kind == "research_table":
				box(n, Vector3(0.6, 0.02, 0.45), Vector3(0, sy * 0.92, 0), plain("paper", Color(0.85, 0.8, 0.65), 0.9))
				var skull := SphereMesh.new()
				skull.radius = 0.15
				skull.height = 0.25
				var mi2 := MeshInstance3D.new()
				mi2.mesh = skull
				mi2.material_override = plain("bone", Color(0.85, 0.82, 0.72), 0.6)
				mi2.position = Vector3(0.65, sy * 1.0, 0)
				n.add_child(mi2)
			else:
				for k in 4:
					cyl(n, 0.06, 0.06, 0.22, Vector3(-0.6 + k * 0.35, sy * 1.0, 0), plain("glass%d" % k, Color.from_hsv(k * 0.2, 0.7, 0.8), 0.1, 0.0, 1.2))
		"forge":
			box(n, Vector3(sx, sy * 0.45, sz), Vector3(0, sy * 0.225, 0), stone())
			cyl(n, 0.4, 0.55, sy, Vector3(sx * 0.3, sy * 0.95, -sz * 0.25), stone())
			box(n, Vector3(0.6, 0.25, 0.4), Vector3(-sx * 0.25, sy * 0.55, sz * 0.2), plain("iron", Color(0.3, 0.3, 0.32), 0.5, 0.7))
			var ember := box(n, Vector3(0.8, 0.1, 0.6), Vector3(0, sy * 0.47, 0), plain("ember", Color(1.0, 0.35, 0.05), 0.5, 0.0, 3.0))
			Fx.glow_light(n, Color(1.0, 0.45, 0.15), 6.0, 2.0).position = Vector3(0, sy * 0.7, 0)
		"kitchen":
			box(n, Vector3(sx, sy * 0.5, sz), Vector3(0, sy * 0.25, 0), stone())
			cyl(n, 0.35, 0.45, 0.4, Vector3(0, sy * 0.7, 0), plain("iron", Color(0.25, 0.25, 0.27), 0.5, 0.7))
			var f2 := Node3D.new()
			f2.position = Vector3(0, sy * 0.52, sz * 0.3)
			n.add_child(f2)
			GearFactory.make_flame(f2, 0.8)
		"gene_lab":
			box(n, Vector3(sx, 0.2, sz), Vector3(0, 0.1, 0), stone())
			for k in 3:
				var tube := cyl(n, 0.32, 0.32, 1.6, Vector3(-0.9 + k * 0.9, 1.0, -0.4), plain("vat%d" % k, Color(0.25, 0.8, 0.55, 1.0), 0.05, 0.0, 0.6))
			box(n, Vector3(sx, 0.1, sz * 0.4), Vector3(0, 1.9, -0.4), wood())
			box(n, Vector3(1.2, 0.9, 0.6), Vector3(0, 0.55, 0.7), wood())
			Fx.glow_light(n, Color(0.3, 1.0, 0.6), 5.0, 1.0).position = Vector3(0, 1.2, 0)
		"incubator":
			cyl(n, sx * 0.5, sx * 0.55, 0.5, Vector3(0, 0.25, 0), stone(), Vector3.ZERO, 14)
			cyl(n, sx * 0.42, sx * 0.42, 0.1, Vector3(0, 0.5, 0), plain("straw", Color(0.65, 0.55, 0.3), 1.0), Vector3.ZERO, 14)
			Fx.glow_light(n, Color(1.0, 0.6, 0.3), 3.0, 0.6).position = Vector3(0, 0.8, 0)
		"infirmary", "hut":
			for k in 8:
				var a := k * TAU / 8.0
				cyl(n, 0.1, 0.12, sy * 0.6, Vector3(cos(a) * sx * 0.45, sy * 0.3, sin(a) * sz * 0.45), wood())
			cyl(n, sx * 0.47, sx * 0.47, sy * 0.55, Vector3(0, sy * 0.3, 0), hide_m() if kind == "infirmary" else thatch(), Vector3.ZERO, 12)
			cone_roof(n, sx * 0.62, sy * 0.5, sy * 0.55, thatch())
		"pen", "pen_large":
			var posts := int(sx / 2.0)
			for side in 4:
				for i in posts + 1:
					var t := (float(i) / posts - 0.5) * sx
					var pos := Vector3(t, 0, -sz * 0.5) if side == 0 else (Vector3(t, 0, sz * 0.5) if side == 1 else (Vector3(-sx * 0.5, 0, t) if side == 2 else Vector3(sx * 0.5, 0, t)))
					if side == 1 and absf(t) < 1.5:
						continue
					cyl(n, 0.12, 0.14, sy, pos + Vector3(0, sy * 0.5, 0), wood())
				var rail := Vector3(sx, 0.12, 0.12) if side < 2 else Vector3(0.12, 0.12, sz)
				var c := Vector3(0, 0, (-1 if side == 0 else 1) * sz * 0.5) if side < 2 else Vector3((-1 if side == 2 else 1) * sx * 0.5, 0, 0)
				for h in [0.45, 0.85]:
					box(n, rail, c + Vector3(0, sy * h, 0), wood())
		"water_pen":
			for side in 4:
				var rail2 := Vector3(sx, 1.2, 0.5) if side < 2 else Vector3(0.5, 1.2, sz)
				var c2 := Vector3(0, 0, (-1 if side == 0 else 1) * sz * 0.5) if side < 2 else Vector3((-1 if side == 2 else 1) * sx * 0.5, 0, 0)
				box(n, rail2, c2 + Vector3(0, 0.3, 0), stone())
		"flight_platform":
			for x in [-1, 1]:
				for z in [-1, 1]:
					cyl(n, 0.25, 0.3, sy, Vector3(x * sx * 0.4, sy * 0.5, z * sz * 0.4), wood())
			box(n, Vector3(sx, 0.3, sz), Vector3(0, sy, 0), wood())
		"farm_plot":
			box(n, Vector3(sx, 0.3, sz), Vector3(0, 0.1, 0), plain("soil", Color(0.25, 0.17, 0.1), 1.0))
			for k in 9:
				var plant := cyl(n, 0.0, 0.18, 0.5, Vector3(-1.0 + (k % 3), 0.45, -1.0 + (k / 3)), plain("crop", Color(0.3, 0.55, 0.2), 0.9), Vector3.ZERO, 5)
		"watchtower":
			for x in [-1, 1]:
				for z in [-1, 1]:
					cyl(n, 0.15, 0.2, sy, Vector3(x * sx * 0.35, sy * 0.5, z * sz * 0.35), wood())
			box(n, Vector3(sx, 0.2, sz), Vector3(0, sy * 0.8, 0), wood())
			box(n, Vector3(sx, 0.9, 0.12), Vector3(0, sy * 0.8 + 0.5, sz * 0.5), wood())
			box(n, Vector3(sx, 0.9, 0.12), Vector3(0, sy * 0.8 + 0.5, -sz * 0.5), wood())
			cone_roof(n, sx * 0.8, 1.5, sy, thatch())
		"palisade", "palisade_gate", "spike_wall":
			var nlogs := int(sx / 0.35)
			for i in nlogs:
				var x := -sx * 0.5 + (i + 0.5) * sx / nlogs
				if kind == "palisade_gate" and absf(x) < 1.0:
					continue
				var hh := sy * randf_range(0.92, 1.05) if kind != "spike_wall" else sy
				var rot := Vector3(0.0 if kind != "spike_wall" else -0.5, 0, 0)
				cyl(n, 0.0 if kind == "spike_wall" else 0.14, 0.17, hh, Vector3(x, hh * 0.5, 0), wood(), rot, 6)
			if kind == "palisade_gate":
				box(n, Vector3(2.0, 0.2, 0.2), Vector3(0, sy, 0), wood())
		"stone_wall":
			box(n, Vector3(sx, sy, sz), Vector3(0, sy * 0.5, 0), stone())
		"torch_post":
			cyl(n, 0.06, 0.08, sy, Vector3(0, sy * 0.5, 0), wood())
			var f3 := Node3D.new()
			f3.position = Vector3(0, sy, 0)
			n.add_child(f3)
			GearFactory.make_flame(f3, 0.7)
		"banner":
			cyl(n, 0.06, 0.08, sy, Vector3(0, sy * 0.5, 0), wood())
			box(n, Vector3(0.05, 1.6, 1.0), Vector3(0, sy - 1.0, 0.55), plain("banner", Color(0.5, 0.1, 0.08), 0.9))
		"rift_altar":
			box(n, Vector3(sx, 0.8, sz), Vector3(0, 0.4, 0), stone())
			for k in 4:
				var a2 := k * TAU / 4.0 + PI / 4.0
				cyl(n, 0.0, 0.25, 1.8, Vector3(cos(a2) * sx * 0.45, 1.5, sin(a2) * sz * 0.45), plain("rift_crystal", Color(0.9, 0.15, 0.5), 0.2, 0.2, 2.5), Vector3.ZERO, 5)
			Fx.glow_light(n, Color(0.9, 0.15, 0.4), 6.0, 1.5).position = Vector3(0, 1.4, 0)
		"foundation":
			box(n, Vector3(sx, sy, sz), Vector3(0, sy * 0.5 - 0.25, 0), wood())
		"wall", "wall_window", "doorway":
			if kind == "wall":
				box(n, Vector3(sx, sy, sz), Vector3(0, sy * 0.5, 0), wood())
			elif kind == "wall_window":
				box(n, Vector3(sx, 1.0, sz), Vector3(0, 0.5, 0), wood())
				box(n, Vector3(sx, 0.8, sz), Vector3(0, sy - 0.4, 0), wood())
				box(n, Vector3(1.2, 1.2, sz), Vector3(-sx * 0.35, 1.6, 0), wood())
				box(n, Vector3(1.2, 1.2, sz), Vector3(sx * 0.35, 1.6, 0), wood())
			else:
				box(n, Vector3(1.4, sy, sz), Vector3(-sx * 0.5 + 0.7, sy * 0.5, 0), wood())
				box(n, Vector3(1.4, sy, sz), Vector3(sx * 0.5 - 0.7, sy * 0.5, 0), wood())
				box(n, Vector3(1.2, 0.6, sz), Vector3(0, sy - 0.3, 0), wood())
		"roof":
			box(n, Vector3(sx + 0.4, sy, sz + 0.4), Vector3(0, 0, 0), thatch())
		"stairs":
			for k in 6:
				box(n, Vector3(sx, 0.2, sz / 6.0), Vector3(0, (k + 1) * sy / 6.0 - 0.1, sz * 0.5 - (k + 0.5) * sz / 6.0), wood())
		_:
			box(n, Vector3(sx, sy, sz), Vector3(0, sy * 0.5, 0), wood())
	return n


static func collision_shapes(kind: String) -> Array:
	## returns [[Shape3D, Vector3 pos]] for the building body
	var bd := DB.building(kind)
	var size: Array = bd.get("size", [2, 2, 2])
	var sx := float(size[0])
	var sy := float(size[1])
	var sz := float(size[2])
	var out := []
	match kind:
		"pen", "pen_large", "water_pen":
			for side in 4:
				var b := BoxShape3D.new()
				b.size = Vector3(sx, sy, 0.4) if side < 2 else Vector3(0.4, sy, sz)
				var c := Vector3(0, sy * 0.5, (-1 if side == 0 else 1) * sz * 0.5) if side < 2 else Vector3((-1 if side == 2 else 1) * sx * 0.5, sy * 0.5, 0)
				if side == 1:
					# leave a gate gap
					var b1 := BoxShape3D.new()
					b1.size = Vector3(sx * 0.5 - 1.5, sy, 0.4)
					out.append([b1, Vector3(-sx * 0.25 - 0.75, sy * 0.5, sz * 0.5)])
					out.append([b1, Vector3(sx * 0.25 + 0.75, sy * 0.5, sz * 0.5)])
					continue
				out.append([b, c])
		"palisade_gate", "doorway":
			var b2 := BoxShape3D.new()
			b2.size = Vector3(sx * 0.5 - 1.0, sy, sz)
			out.append([b2, Vector3(-sx * 0.25 - 0.5, sy * 0.5, 0)])
			out.append([b2, Vector3(sx * 0.25 + 0.5, sy * 0.5, 0)])
		"bedroll", "farm_plot", "campfire":
			pass
		"foundation":
			var b3 := BoxShape3D.new()
			b3.size = Vector3(sx, sy, sz)
			out.append([b3, Vector3(0, sy * 0.5 - 0.25, 0)])
		"roof":
			var b4 := BoxShape3D.new()
			b4.size = Vector3(sx, sy, sz)
			out.append([b4, Vector3.ZERO])
		_:
			var b5 := BoxShape3D.new()
			b5.size = Vector3(sx, sy, sz)
			out.append([b5, Vector3(0, sy * 0.5, 0)])
	return out
