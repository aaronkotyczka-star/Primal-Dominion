class_name Terrain
extends Node3D
## GPU-displaced chunked terrain with LOD via visibility ranges + heightmap collision.

const CHUNK := 128.0
var material: ShaderMaterial
var lod_meshes: Array = []
var lod_ranges := [0.0, 180.0, 420.0, 900.0, 3200.0]
var body: StaticBody3D


func build(quality: int = 2) -> void:
	WorldData.ensure_loaded()
	var n := WorldData.n
	var ext := WorldData.extent
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RF, WorldData.heights.to_byte_array())
	var htex := ImageTexture.create_from_image(img)
	material = ShaderMaterial.new()
	material.shader = load("res://shaders/terrain.gdshader")
	material.set_shader_parameter("heightmap", htex)
	material.set_shader_parameter("splat0", load("res://assets/world/splat0.png"))
	material.set_shader_parameter("splat1", load("res://assets/world/splat1.png"))
	material.set_shader_parameter("albedo_arr", load("res://assets/textures/terrain_albedo_array.png"))
	material.set_shader_parameter("normal_arr", load("res://assets/textures/terrain_nrm_array.png"))
	material.set_shader_parameter("extent", ext)
	material.set_shader_parameter("hm_size", float(n))
	var base_res := 64 if quality >= 2 else 32
	lod_meshes = []
	for l in 4:
		lod_meshes.append(_grid_mesh(CHUNK, maxi(4, base_res >> l)))
	if quality <= 0:
		lod_ranges = [0.0, 140.0, 320.0, 700.0, 3200.0]
	var count := int(2.0 * ext / CHUNK)
	for cz in count:
		for cx in count:
			var ox := -ext + cx * CHUNK
			var oz := -ext + cz * CHUNK
			var hmin := 1e9
			var hmax := -1e9
			for sz in 9:
				for sx in 9:
					var h := WorldData.height_at(ox + sx * CHUNK / 8.0, oz + sz * CHUNK / 8.0)
					hmin = minf(hmin, h)
					hmax = maxf(hmax, h)
			# skip deep ocean chunks for the finest LODs
			for l in 4:
				var mi := MeshInstance3D.new()
				mi.mesh = lod_meshes[l]
				mi.material_override = material
				mi.position = Vector3(ox, 0, oz)
				mi.custom_aabb = AABB(Vector3(0, hmin - 8.0, 0), Vector3(CHUNK, hmax - hmin + 16.0, CHUNK))
				mi.visibility_range_begin = lod_ranges[l]
				mi.visibility_range_end = lod_ranges[l + 1]
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if l < 2 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if hmax < -40.0 and l < 2:
					mi.visibility_range_end = lod_ranges[l + 1] * 0.5
				add_child(mi)
	_build_collision()


func _grid_mesh(size: float, res: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	var step := size / res
	for z in res + 1:
		for x in res + 1:
			verts.append(Vector3(x * step, 0, z * step))
			uv2.append(Vector2.ZERO)
	for z in res:
		for x in res:
			var a := z * (res + 1) + x
			var b := a + 1
			var c := a + res + 1
			var d := c + 1
			idx.append_array([a, b, c, b, d, c])
	# skirts along 4 edges (hide LOD cracks)
	var edges := []
	for i in res + 1:
		edges.append([i, 0])
	for i in res + 1:
		edges.append([res, i])
	for i in range(res, -1, -1):
		edges.append([i, res])
	for i in range(res, -1, -1):
		edges.append([0, i])
	var base := verts.size()
	for e in edges:
		verts.append(Vector3(e[0] * step, 0, e[1] * step))
		uv2.append(Vector2(1, 0))
	for i in edges.size() - 1:
		var e0: Array = edges[i]
		var e1: Array = edges[i + 1]
		var t0: int = e0[1] * (res + 1) + e0[0]
		var t1: int = e1[1] * (res + 1) + e1[0]
		var s0 := base + i
		var s1 := base + i + 1
		idx.append_array([t0, s0, t1, t1, s0, s1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	normals.fill(Vector3.UP)
	arr[Mesh.ARRAY_NORMAL] = normals
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


func _build_collision() -> void:
	body = StaticBody3D.new()
	body.name = "TerrainBody"
	body.collision_layer = 1
	body.collision_mask = 0
	add_child(body)
	var shape := HeightMapShape3D.new()
	shape.map_width = WorldData.n
	shape.map_depth = WorldData.n
	shape.map_data = WorldData.heights
	var cs := CollisionShape3D.new()
	cs.shape = shape
	# HeightMapShape3D is centered; spacing scaled by cell size
	cs.scale = Vector3(WorldData.cell, 1.0, WorldData.cell)
	body.add_child(cs)
