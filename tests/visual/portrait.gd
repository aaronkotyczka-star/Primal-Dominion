extends SceneTree
## Close-up portraits of one rig (front, 3/4, profile, back) with 3-point lighting.
## godot --path . -s res://tests/visual/portrait.gd -- out_prefix rig_id [bone] [zoom]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0]
	var id: String = args[1]
	var focus: String = args[2] if args.size() > 2 else "head"
	var zoom: float = float(args[3]) if args.size() > 3 else 1.0
	var root := Node3D.new()
	get_root().add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.45, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.6, 0.68)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	env.environment = e
	root.add_child(env)
	for l in [[Vector3(-35, -40, 0), 1.6, Color(1.0, 0.95, 0.88), true], [Vector3(-15, 140, 0), 0.45, Color(0.7, 0.8, 1.0), false], [Vector3(-10, 170, 0), 0.8, Color(1, 1, 1), false]]:
		var sun := DirectionalLight3D.new()
		sun.rotation_degrees = l[0]
		sun.light_energy = l[1]
		sun.light_color = l[2]
		sun.shadow_enabled = l[3]
		root.add_child(sun)
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.fov = 30
	await process_frame
	var fs := FileAccess.open("res://data/species.json", FileAccess.READ)
	var species: Dictionary = JSON.parse_string(fs.get_as_text())
	var sp: Dictionary = species.get(id, {"rig": id, "parts": [], "colors": [{}]})
	var c: Dictionary = sp["colors"][0] if sp.has("colors") else {}
	var human: bool = String(sp["rig"]).begins_with("human") or sp["rig"] in ["goblin", "demon"]
	var cols := {"color_main": c.get("main", [0.4, 0.35, 0.3]), "color_belly": c.get("belly", [0.6, 0.55, 0.5]), "color_pattern": c.get("pattern", [0.2, 0.15, 0.1])}
	if human:
		cols = {"color_main": [0.66, 0.5, 0.4], "color_belly": [0.68, 0.53, 0.43], "color_pattern": [0.6, 0.45, 0.36],
			"top_color": [0.42, 0.36, 0.26], "bottom_color": [0.24, 0.22, 0.2], "boots_color": [0.24, 0.16, 0.1],
			"hair_color": [0.2, 0.13, 0.08], "eye_color": [0.25, 0.4, 0.5]}
	if sp["rig"] == "goblin":
		cols["color_main"] = [0.33, 0.43, 0.25]
		cols["color_belly"] = [0.36, 0.45, 0.28]
		cols["eye_color"] = [0.9, 0.75, 0.2]
	elif sp["rig"] == "demon":
		cols["color_main"] = [0.25, 0.08, 0.07]
		cols["color_belly"] = [0.3, 0.1, 0.08]
		cols["eye_color"] = [1.0, 0.5, 0.1]
	var vis := CreatureVisual.new()
	root.add_child(vis)
	var ph := {"rig": sp["rig"], "scale": 1.0, "parts": sp.get("parts", []), "colors": cols,
		"pattern_type": c.get("pt", 0 if human else 1), "use_wrinkle": 1.0 if sp.get("tex", "") == "fur" or human else 0.0}
	if human:
		ph["tex_scale"] = 6.0
		ph["bump_height"] = 0.002
	vis.setup(ph)
	if OS.get_environment("NOFUR") != "":
		for n in vis.find_children("Fur", "MeshInstance3D", true, false):
			n.visible = false
	if OS.get_environment("NOEXTRA") != "":
		pass
	var meta := RigLibrary.load_meta(sp["rig"])
	var hpos := Vector3.ZERO
	var hsize := 0.3
	for b in meta["bones"]:
		if b["name"] == focus:
			var h0: Array = b["head"]
			var t0: Array = b["tail"]
			hpos = (Vector3(h0[0], h0[1], h0[2]) + Vector3(t0[0], t0[1], t0[2])) * 0.5
			hsize = maxf(Vector3(h0[0], h0[1], h0[2]).distance_to(Vector3(t0[0], t0[1], t0[2])), 0.1)
	if focus == "body":
		var aabb: Array = meta["aabb"]
		hpos = (Vector3(aabb[0][0], aabb[0][1], aabb[0][2]) + Vector3(aabb[1][0], aabb[1][1], aabb[1][2])) * 0.5
		hsize = Vector3(aabb[1][0] - aabb[0][0], aabb[1][1] - aabb[0][1], aabb[1][2] - aabb[0][2]).length() * 0.62
	if OS.get_environment("MARK") != "":
		var mk := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.02
		sm.height = 0.04
		mk.mesh = sm
		var mm := StandardMaterial3D.new()
		mm.albedo_color = Color(1, 0, 0)
		mk.material_override = mm
		root.add_child(mk)
		mk.position = hpos + Vector3(0.08, 0, -0.25)
	var dirs := [Vector3(0, 0.05, -1), Vector3(0.7, 0.12, -0.75), Vector3(1, 0.05, 0), Vector3(0.3, 0.2, 1)]
	for i in dirs.size():
		cam.position = hpos + (dirs[i] as Vector3).normalized() * hsize * 3.2 / zoom
		cam.look_at(hpos)
		for k in (40 if i == 0 else 8):
			await process_frame
		get_root().get_texture().get_image().save_png("%s_%d.png" % [out, i])
	print("done")
	quit()
