extends SceneTree
## Renders flora meshes on a ground plane: godot --path . -s res://tests/visual/flora_lineup.gd -- out_prefix id1 id2 ...

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var ids: Array = args.slice(1)
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.6, 0.72, 0.85)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.66, 0.75)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, -40, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.4
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.32, 0.36, 0.2)
	ground.material_override = gm
	root.add_child(ground)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 40
	await process_frame
	var x := 0.0
	for id in ids:
		var m := FloraLibrary.mesh(id, int(OS.get_environment("LOD")) if OS.get_environment("LOD") != "" else 0)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		root.add_child(mi)
		mi.position = Vector3(x, 0, 0)
		var ab := m.get_aabb()
		var size := ab.size.length()
		var c := mi.position + ab.get_center()
		cam.position = c + Vector3(0.9, 0.25, 1.0).normalized() * size * 1.05
		cam.look_at(c)
		for i in 30:
			await process_frame
		get_root().get_texture().get_image().save_png("%s_%s.png" % [out, id])
		mi.visible = false
		x += 100.0
	print("done")
	quit()
