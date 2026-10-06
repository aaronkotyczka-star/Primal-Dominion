class_name FloraLibrary
extends RefCounted
## Loads static vegetation/rock meshes (assets/flora) and provides shared materials.

const DIR := "res://assets/flora/"
static var _meshes := {}
static var _mats := {}


static func mesh(id: String, lod: int) -> ArrayMesh:
	var key := "%s_lod%d" % [id, lod]
	if _meshes.has(key):
		return _meshes[key]
	var f := FileAccess.open(DIR + key + ".json", FileAccess.READ)
	if f == null:
		return null
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	var bf := FileAccess.open(DIR + key + ".bin", FileAccess.READ)
	var blob := bf.get_buffer(bf.get_length())
	var m := ArrayMesh.new()
	for s in meta["surfaces"]:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = _sl(blob, s["position"]).to_vector3_array()
		arr[Mesh.ARRAY_NORMAL] = _sl(blob, s["normal"]).to_vector3_array()
		arr[Mesh.ARRAY_TEX_UV] = _sl(blob, s["uv"]).to_vector2_array()
		arr[Mesh.ARRAY_COLOR] = _sl(blob, s["color"]).to_color_array()
		arr[Mesh.ARRAY_INDEX] = _sl(blob, s["index"]).to_int32_array()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, material(s["material"]))
	_meshes[key] = m
	return m


static func _sl(blob: PackedByteArray, r: Array) -> PackedByteArray:
	return blob.slice(int(r[0]), int(r[0]) + int(r[1]))


static func material(kind: String) -> Material:
	if _mats.has(kind):
		return _mats[kind]
	var m: Material
	match kind:
		"bark", "deadwood":
			var sm := StandardMaterial3D.new()
			sm.albedo_texture = load("res://assets/textures/bark_albedo.png")
			sm.normal_enabled = true
			sm.normal_texture = load("res://assets/textures/bark_nrm.png")
			sm.uv1_scale = Vector3(1.0, 0.5, 1.0)
			sm.roughness = 0.9
			sm.vertex_color_use_as_albedo = false
			if kind == "deadwood":
				sm.albedo_color = Color(0.55, 0.52, 0.5)
			# dither away branches right in front of the camera
			sm.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_DITHER
			sm.distance_fade_min_distance = 0.8
			sm.distance_fade_max_distance = 2.8
			m = sm
		"leaves", "moss":
			var fm := ShaderMaterial.new()
			fm.shader = load("res://shaders/foliage.gdshader")
			fm.set_shader_parameter("albedo_tex", load("res://assets/textures/leaves_atlas.png"))
			if kind == "moss":
				fm.set_shader_parameter("tint", Color(0.6, 0.65, 0.45))
			m = fm
		"rock", "crystal":
			var rm := ShaderMaterial.new()
			rm.shader = load("res://shaders/rock.gdshader")
			rm.set_shader_parameter("albedo_arr", load("res://assets/textures/terrain_albedo_array.jpg"))
			rm.set_shader_parameter("normal_arr", load("res://assets/textures/terrain_nrm_array.png"))
			if kind == "crystal":
				var cm := StandardMaterial3D.new()
				cm.albedo_color = Color(0.35, 0.05, 0.25)
				cm.emission_enabled = true
				cm.emission = Color(0.9, 0.15, 0.5)
				cm.emission_energy_multiplier = 2.0
				cm.roughness = 0.15
				cm.metallic = 0.3
				m = cm
			else:
				m = rm
		"cactus":
			var c := StandardMaterial3D.new()
			c.albedo_color = Color(0.25, 0.38, 0.2)
			c.roughness = 0.7
			m = c
		"berry":
			var b := StandardMaterial3D.new()
			b.albedo_color = Color(0.55, 0.05, 0.12)
			b.roughness = 0.3
			m = b
		_:
			m = StandardMaterial3D.new()
	_mats[kind] = m
	return m


static func ore_material(kind: String) -> Material:
	var key := "ore_" + kind
	if _mats.has(key):
		return _mats[key]
	var rm := ShaderMaterial.new()
	rm.shader = load("res://shaders/rock.gdshader")
	rm.set_shader_parameter("albedo_arr", load("res://assets/textures/terrain_albedo_array.jpg"))
	rm.set_shader_parameter("normal_arr", load("res://assets/textures/terrain_nrm_array.png"))
	rm.set_shader_parameter("moss_amount", 0.0)
	var cols := {"ore_metal": Color(0.75, 0.45, 0.25), "ore_obsidian": Color(0.05, 0.03, 0.08), "flint": Color(0.25, 0.25, 0.28),
		"crystal": Color(0.4, 0.75, 1.0), "rift_crystal": Color(0.9, 0.15, 0.5), "salt": Color(0.95, 0.95, 0.92),
		"clay": Color(0.6, 0.38, 0.25), "sulfur": Color(0.9, 0.85, 0.2)}
	rm.set_shader_parameter("vein_color", cols.get(kind, Color(0.7, 0.7, 0.7)))
	rm.set_shader_parameter("vein_amount", 0.9)
	rm.set_shader_parameter("emissive", 1.5 if kind in ["crystal", "rift_crystal"] else 0.0)
	if kind == "ore_obsidian":
		rm.set_shader_parameter("tint", Color(0.3, 0.3, 0.35))
	_mats[key] = rm
	return rm
