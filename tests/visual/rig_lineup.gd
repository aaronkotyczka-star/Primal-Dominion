extends SceneTree
## Renders each generated rig (side + 3/4 view) for visual inspection.
## godot --path . -s res://tests/visual/rig_lineup.gd -- out_prefix id1 id2 ...

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "user://lineup"
	var ids: Array = args.slice(1) if args.size() > 1 else ["trex", "raptor", "triceratops", "human_m"]
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.3
	root.add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.3, 0.28, 0.22)
	ground.material_override = gm
	root.add_child(ground)
	var cam := Camera3D.new()
	root.add_child(cam)
	await process_frame
	cam.fov = 35
	var x := 0.0
	var fs := FileAccess.open("res://data/species.json", FileAccess.READ)
	var species: Dictionary = JSON.parse_string(fs.get_as_text())
	var walk := OS.get_environment("WALK") != ""
	for id in ids:
		var sp: Dictionary = species.get(id, {"rig": id, "parts": [], "colors": [{}]})
		var meta := RigLibrary.load_meta(sp["rig"])
		var aabb: Array = meta["aabb"]
		var vis := CreatureVisual.new()
		root.add_child(vis)
		var c: Dictionary = sp["colors"][0] if sp.has("colors") else {}
		var ph := {"rig": sp["rig"], "scale": 1.0, "parts": sp.get("parts", []),
			"colors": {"color_main": c.get("main", [0.4, 0.35, 0.3]), "color_belly": c.get("belly", [0.6, 0.55, 0.5]), "color_pattern": c.get("pattern", [0.2, 0.15, 0.1])},
			"pattern_type": c.get("pt", 1), "corruption": sp.get("corruption", 0.0), "glow": sp.get("glow", 0.0),
			"glow_color": sp.get("glow_color", [1, 0.3, 0.1]), "use_wrinkle": 1.0 if sp.get("tex", "") == "fur" or sp["rig"].begins_with("human") or sp["rig"] in ["goblin", "demon"] else 0.0}
		vis.setup(ph)
		var hh: float = aabb[1][1] - aabb[0][1]
		var ln: float = aabb[1][2] - aabb[0][2]
		var wd: float = aabb[1][0] - aabb[0][0]
		var gy: float = 0.0
		if meta["family"] in ["marine", "fish", "serpent"] or aabb[0][1] < -0.05:
			gy = -aabb[0][1] + 0.05
		vis.position = Vector3(x, gy, 0)
		if walk:
			vis.animator.speed = 3.0 * float(meta.get("hip_height", 1.0))
			vis.animator.run_speed = 6.0 * float(meta.get("hip_height", 1.0))
			vis.animator.phase = 0.2
		else:
			vis.animator.play("roar", 100.0)
			vis.animator.action_t = 0.5
		var size := maxf(maxf(hh, ln), wd)
		var center := Vector3(x, gy + (aabb[0][1] + aabb[1][1]) * 0.5, (aabb[0][2] + aabb[1][2]) * 0.5)
		for view in 2:
			var dir := Vector3(1, 0.25, 0).normalized() if view == 0 else Vector3(0.8, 0.45, -0.9).normalized()
			cam.position = center + dir * size * 1.9
			cam.look_at(center)
			for i in (30 if x == 0.0 and view == 0 else 6):
				await process_frame
			get_root().get_texture().get_image().save_png("%s_%s_%d.png" % [out, id, view])
		x += 200.0
	print("done")
	quit()
