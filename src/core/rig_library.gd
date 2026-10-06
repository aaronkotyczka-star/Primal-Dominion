class_name RigLibrary
extends RefCounted
## Loads generated creature rigs (assets/creatures/<id>.json + .bin) and builds
## shared ArrayMeshes plus per-instance Skeleton3D/Skin.

const DIR := "res://assets/creatures/"
const PART_DIR := "res://assets/parts/"

static var _meta_cache := {}
static var _mesh_cache := {}
static var _skin_shader: Shader
static var _membrane_shader: Shader
static var _skin_tex: Texture2D
static var _wrinkle_tex: Texture2D
static var _cloth_tex: Texture2D
static var _leather_tex: Texture2D
static var _strand_tex: Texture2D
static var _fur_shader: Shader


static func load_meta(rig_id: String) -> Dictionary:
	if _meta_cache.has(rig_id):
		return _meta_cache[rig_id]
	var f := FileAccess.open(DIR + rig_id + ".json", FileAccess.READ)
	if f == null:
		push_error("Rig fehlt: " + rig_id)
		return {}
	var m: Dictionary = JSON.parse_string(f.get_as_text())
	_meta_cache[rig_id] = m
	return m


static func get_mesh(rig_id: String) -> ArrayMesh:
	if _mesh_cache.has(rig_id):
		return _mesh_cache[rig_id]
	var mesh := _build_mesh(DIR, rig_id, load_meta(rig_id), false)
	_mesh_cache[rig_id] = mesh
	return mesh


static func get_part_mesh(part_id: String, mirrored: bool = false) -> ArrayMesh:
	var key := "part:" + part_id + (":m" if mirrored else "")
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	if mirrored:
		var src := get_part_mesh(part_id, false)
		if src == null:
			return null
		var mm := ArrayMesh.new()
		for si in src.get_surface_count():
			var arr := src.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			for i in v.size():
				v[i].x = -v[i].x
				n[i].x = -n[i].x
			arr[Mesh.ARRAY_VERTEX] = v
			arr[Mesh.ARRAY_NORMAL] = n
			var c0: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM0]
			var c1: PackedFloat32Array = arr[Mesh.ARRAY_CUSTOM1]
			for i in range(0, c0.size(), 4):
				c0[i] = -c0[i]
				c1[i] = -c1[i]
			arr[Mesh.ARRAY_CUSTOM0] = c0
			arr[Mesh.ARRAY_CUSTOM1] = c1
			var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			for i in range(0, idx.size(), 3):
				var t := idx[i + 1]
				idx[i + 1] = idx[i + 2]
				idx[i + 2] = t
			arr[Mesh.ARRAY_INDEX] = idx
			mm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT))
		_mesh_cache[key] = mm
		return mm
	var f := FileAccess.open(PART_DIR + part_id + ".json", FileAccess.READ)
	if f == null:
		push_error("Teil fehlt: " + part_id)
		return null
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	var mesh := _build_mesh(PART_DIR, part_id, meta, true)
	_mesh_cache[key] = mesh
	return mesh


static func _build_mesh(dir: String, id: String, meta: Dictionary, rigid: bool) -> ArrayMesh:
	var f := FileAccess.open(dir + id + ".bin", FileAccess.READ)
	var blob := f.get_buffer(f.get_length())
	var mesh := ArrayMesh.new()
	var fmt := Mesh.ARRAY_FORMAT_VERTEX | Mesh.ARRAY_FORMAT_NORMAL | Mesh.ARRAY_FORMAT_TEX_UV \
		| Mesh.ARRAY_FORMAT_INDEX \
		| Mesh.ARRAY_FORMAT_CUSTOM0 | Mesh.ARRAY_FORMAT_CUSTOM1 | Mesh.ARRAY_FORMAT_CUSTOM2 \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)
	for s in meta["surfaces"]:
		if int(s["vertex_count"]) == 0:
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = _slice(blob, s["position"]).to_vector3_array()
		arr[Mesh.ARRAY_NORMAL] = _slice(blob, s["normal"]).to_vector3_array()
		arr[Mesh.ARRAY_TEX_UV] = _slice(blob, s["uv"]).to_vector2_array()
		arr[Mesh.ARRAY_CUSTOM0] = _slice(blob, s["custom0"]).to_float32_array()
		arr[Mesh.ARRAY_CUSTOM1] = _slice(blob, s["custom1"]).to_float32_array()
		if s.has("custom2"):
			arr[Mesh.ARRAY_CUSTOM2] = _slice(blob, s["custom2"]).to_float32_array()
		else:
			var z := PackedFloat32Array()
			z.resize(int(s["vertex_count"]) * 4)
			arr[Mesh.ARRAY_CUSTOM2] = z
		if not rigid:
			arr[Mesh.ARRAY_BONES] = _slice(blob, s["bones"]).to_int32_array()
			arr[Mesh.ARRAY_WEIGHTS] = _slice(blob, s["weights"]).to_float32_array()
		arr[Mesh.ARRAY_INDEX] = _slice(blob, s["index"]).to_int32_array()
		var sf := fmt
		if not rigid:
			sf |= Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, sf)
	return mesh


static func _slice(blob: PackedByteArray, rng: Array) -> PackedByteArray:
	var off := int(rng[0])
	return blob.slice(off, off + int(rng[1]))


## Builds Skeleton3D + MeshInstance3D under `parent`. Returns {skeleton, mesh_instance, materials}.
static func instantiate(rig_id: String, parent: Node3D) -> Dictionary:
	var meta := load_meta(rig_id)
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	parent.add_child(skel)
	var bones: Array = meta["bones"]
	for i in bones.size():
		var b: Dictionary = bones[i]
		skel.add_bone(b["name"])
	for i in bones.size():
		var b: Dictionary = bones[i]
		if int(b["parent"]) >= 0:
			skel.set_bone_parent(i, int(b["parent"]))
		var r: Array = b["rest"]
		var t := Transform3D(Basis(), Vector3(r[0], r[1], r[2]))
		skel.set_bone_rest(i, t)
	skel.reset_bone_poses()
	var skin := Skin.new()
	for i in bones.size():
		var h: Array = bones[i]["head"]
		skin.add_named_bind(bones[i]["name"], Transform3D(Basis(), -Vector3(h[0], h[1], h[2])))
	var mi := MeshInstance3D.new()
	mi.name = "Body"
	mi.mesh = get_mesh(rig_id)
	mi.skin = skin
	skel.add_child(mi)
	mi.skeleton = NodePath("..")
	var mats := []
	var body_mat := ShaderMaterial.new()
	body_mat.shader = _get_skin_shader()
	body_mat.set_shader_parameter("skin_tex", _skin_tex)
	body_mat.set_shader_parameter("wrinkle_tex", _wrinkle_tex)
	body_mat.set_shader_parameter("cloth_tex", _cloth_tex)
	body_mat.set_shader_parameter("leather_tex", _leather_tex)
	mi.set_surface_override_material(0, body_mat)
	mats.append(body_mat)
	if mi.mesh.get_surface_count() > 1:
		var mem := ShaderMaterial.new()
		mem.shader = _membrane_shader
		mi.set_surface_override_material(1, mem)
		mats.append(mem)
	var fur_mats := _add_fur(meta, skel, skin, mi.mesh, body_mat)
	return {"skeleton": skel, "mesh_instance": mi, "materials": mats, "fur_materials": fur_mats, "meta": meta}


## Shell fur/hair: a second instance of the skinned body drawn N times with growing offsets.
## Only drawn up close (visibility range); further away the body's coat colour carries the look.
static func _add_fur(meta: Dictionary, skel: Skeleton3D, skin: Skin, mesh: Mesh, body_mat: ShaderMaterial) -> Array:
	var fur: Dictionary = meta.get("fur", {})
	if fur.is_empty() or fur_shells() <= 0:
		return []
	var n: int = mini(int(fur.get("shells", 12)), fur_shells())
	var fmi := MeshInstance3D.new()
	fmi.name = "Fur"
	fmi.mesh = mesh
	fmi.skin = skin
	skel.add_child(fmi)
	fmi.skeleton = NodePath("..")
	fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var aabb: Array = meta["aabb"]
	var size := Vector3(aabb[1][0] - aabb[0][0], aabb[1][1] - aabb[0][1], aabb[1][2] - aabb[0][2]).length()
	fmi.visibility_range_end = clampf(size * 12.0, 18.0, 70.0)
	fmi.visibility_range_end_margin = 4.0
	fmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	var mats := []
	var first: ShaderMaterial = null
	var prev: ShaderMaterial = null
	for i in n:
		var m := ShaderMaterial.new()
		m.shader = _fur_shader
		m.set_shader_parameter("shell", (float(i) + 1.0) / float(n))
		m.set_shader_parameter("strand_tex", _strand_tex)
		m.set_shader_parameter("fur_len", float(fur.get("len", 0.03)))
		m.set_shader_parameter("strand_density", float(fur.get("density", 300.0)))
		m.set_shader_parameter("fur_stiff", float(fur.get("stiff", 0.5)))
		var c: Array = fur.get("comb", [0.0, -0.45, 1.0])
		m.set_shader_parameter("comb", Vector3(c[0], c[1], c[2]))
		var cr: Array = fur.get("crown", [0.0, 0.0, 0.0])
		m.set_shader_parameter("crown", Vector3(cr[0], cr[1], cr[2]))
		m.set_shader_parameter("comb_radial", float(fur.get("radial", 0.0)))
		m.set_shader_parameter("use_hair_color", 1.0 if fur.get("hair", false) else 0.0)
		m.set_shader_parameter("clumping", float(fur.get("clump", 0.3)))
		m.set_shader_parameter("tip_light", float(fur.get("tip_light", 0.25)))
		m.render_priority = i
		if prev == null:
			first = m
		else:
			prev.next_pass = m
		prev = m
		mats.append(m)
	fmi.material_override = first
	body_mat.set_shader_parameter("fur_len", float(fur.get("len", 0.03)))
	return mats


static func fur_shells() -> int:
	var tree := Engine.get_main_loop() as SceneTree
	var st = tree.root.get_node_or_null("Settings") if tree != null else null
	if st == null:
		return 12
	return [0, 8, 12, 16][clampi(int(st.data.get("quality", 2)), 0, 3)]


static func _get_skin_shader() -> Shader:
	if _skin_shader == null:
		_skin_shader = load("res://shaders/creature.gdshader")
		_membrane_shader = load("res://shaders/membrane.gdshader")
		_skin_tex = load("res://assets/textures/skin_scales.png")
		_wrinkle_tex = load("res://assets/textures/skin_wrinkle.png")
		_cloth_tex = load("res://assets/textures/cloth.png")
		_leather_tex = load("res://assets/textures/leather.png")
		_strand_tex = load("res://assets/textures/fur_strands.png")
		_fur_shader = load("res://shaders/fur.gdshader")
	return _skin_shader


static func socket_transform(meta: Dictionary, socket: String) -> Dictionary:
	## Returns {bone, local: Transform3D relative to bone head, scale}
	var s: Dictionary = meta["sockets"].get(socket, {})
	if s.is_empty():
		return {}
	var bone_name: String = s["bone"]
	var head := Vector3.ZERO
	for b in meta["bones"]:
		if b["name"] == bone_name:
			head = Vector3(b["head"][0], b["head"][1], b["head"][2])
			break
	var p := Vector3(s["pos"][0], s["pos"][1], s["pos"][2]) - head
	var n := Vector3(s["normal"][0], s["normal"][1], s["normal"][2]).normalized()
	var basis := Basis()
	if absf(n.dot(Vector3.FORWARD)) < 0.98:
		var x := Vector3.FORWARD.cross(n).normalized()
		var z := x.cross(n).normalized()
		basis = Basis(x, n, z)
	return {"bone": bone_name, "local": Transform3D(basis, p), "scale": float(s["scale"])}


## Attaches a rigid part mesh to a socket. Returns the BoneAttachment3D (or null).
## The part shares the creature's materials so colors/corruption match.
static func attach_part(inst: Dictionary, part_id: String, socket: String, size: float = 1.0, mirror_x: bool = false) -> Node3D:
	var meta: Dictionary = inst["meta"]
	var st := socket_transform(meta, socket)
	if st.is_empty():
		return null
	var skel: Skeleton3D = inst["skeleton"]
	var att := BoneAttachment3D.new()
	att.name = "Part_%s_%s" % [part_id, socket]
	att.bone_name = st["bone"]
	skel.add_child(att)
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	att.add_child(pivot)
	pivot.transform = st["local"]
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = get_part_mesh(part_id, mirror_x)
	if mi.mesh == null:
		att.queue_free()
		return null
	var sc: float = st["scale"] * size
	mi.scale = Vector3(sc, sc, sc)
	pivot.add_child(mi)
	var mats: Array = inst["materials"]
	mi.set_surface_override_material(0, mats[0])
	if mi.mesh.get_surface_count() > 1:
		if mats.size() > 1:
			mi.set_surface_override_material(1, mats[1])
		else:
			var mem := ShaderMaterial.new()
			mem.shader = _membrane_shader
			mats.append(mem)
			mi.set_surface_override_material(1, mem)
	return att
