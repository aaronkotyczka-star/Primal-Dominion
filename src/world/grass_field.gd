class_name GrassField
extends Node3D
## Dense grass around the camera, density from the grass splat layer. Rebuilt in cells as the camera moves.

const CELL := 12.0
var radius_cells := 4
var density := 26 # per cell side sqrt
var splat: Image
var cells := {} # key -> MultiMeshInstance3D
var mesh: ArrayMesh
var _center := Vector2i(99999, 99999)
var _queue: Array = []
var enabled := true


func setup(quality: int) -> void:
	enabled = quality >= 1
	radius_cells = 3 if quality <= 1 else (4 if quality == 2 else 6)
	density = 16 if quality <= 1 else (24 if quality == 2 else 32)
	var t: Texture2D = load("res://assets/world/splat0.png")
	splat = t.get_image()
	if splat.is_compressed():
		splat.decompress()
	mesh = _make_mesh()


func _make_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in 3:
		var a := k * PI / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.45
		var h := 0.75
		var corners := [-d, d, d + Vector3(0, h, 0), -d + Vector3(0, h, 0)]
		var uvs := [Vector2(0.5, 1.0), Vector2(1.0, 1.0), Vector2(1.0, 0.5), Vector2(0.5, 0.5)]
		var sways := [0.0, 0.0, 1.0, 1.0]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(Color(sways[idx], 0.55 + 0.45 * sways[idx], randf(), 1))
			st.set_uv(uvs[idx])
			st.set_normal(Vector3.UP)
			st.add_vertex(corners[idx])
	var m := st.commit()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/foliage.gdshader")
	mat.set_shader_parameter("albedo_tex", load("res://assets/textures/leaves_atlas.png"))
	mat.set_shader_parameter("tint", Color(0.85, 0.95, 0.7))
	mat.set_shader_parameter("wind_strength", 0.18)
	mat.set_shader_parameter("alpha_cut", 0.5)
	mat.set_shader_parameter("fade_end", CELL * (radius_cells + 0.5))
	m.surface_set_material(0, mat)
	return m


func _grass_weight(x: float, z: float) -> float:
	var w := splat.get_width()
	var px := clampi(int((x + WorldData.extent) / (2.0 * WorldData.extent) * w), 0, w - 1)
	var pz := clampi(int((z + WorldData.extent) / (2.0 * WorldData.extent) * w), 0, w - 1)
	return splat.get_pixel(px, pz).r


func update(cam_pos: Vector3) -> void:
	if not enabled:
		return
	var c := Vector2i(int(floor(cam_pos.x / CELL)), int(floor(cam_pos.z / CELL)))
	if c != _center:
		_center = c
		var want := {}
		for dz in range(-radius_cells, radius_cells + 1):
			for dx in range(-radius_cells, radius_cells + 1):
				if dx * dx + dz * dz > radius_cells * radius_cells + 1:
					continue
				want[Vector2i(c.x + dx, c.y + dz)] = true
		for k in cells.keys():
			if not want.has(k):
				if cells[k]:
					cells[k].queue_free()
				cells.erase(k)
		for k in want:
			if not cells.has(k):
				cells[k] = null
				_queue.append(k)
		_queue.sort_custom(func(a, b): return (a - c).length_squared() < (b - c).length_squared())
	# build a few cells per frame
	var n := 0
	while not _queue.is_empty() and n < 3:
		var k: Vector2i = _queue.pop_front()
		if cells.has(k) and cells[k] == null:
			cells[k] = _build_cell(k)
		n += 1


func _build_cell(k: Vector2i) -> MultiMeshInstance3D:
	var ox := k.x * CELL
	var oz := k.y * CELL
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(k)
	var xf := []
	var step := CELL / density
	for iz in density:
		for ix in density:
			var x := ox + (ix + rng.randf()) * step
			var z := oz + (iz + rng.randf()) * step
			var w := _grass_weight(x, z)
			if w < 0.25 or rng.randf() > w * 1.2:
				continue
			var y := WorldData.height_at(x, z)
			if y < 0.3:
				continue
			var s := rng.randf_range(0.6, 1.3) * (0.6 + w * 0.6)
			xf.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.4), s)), Vector3(x, y - 0.05, z)))
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mmi
