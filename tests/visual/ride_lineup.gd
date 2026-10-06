extends Node
## Renders a rider straddling several mounts (visual clipping check of legs vs. body).
## godot --path . -- --visual=ride_lineup --out=<prefix>

const MOUNTS := ["raptor", "parasaurolophus", "trex", "triceratops"]


func _ready() -> void:
	var out := "/tmp/ride"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var root := Node3D.new()
	add_child(root)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.55, 0.6, 0.65)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	e.ambient_light_energy = 0.8
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	await get_tree().process_frame
	var species: Dictionary = DB.t("species")
	for id in MOUNTS:
		var sp: Dictionary = species[id]
		var m := CreatureVisual.new()
		root.add_child(m)
		var c: Dictionary = sp["colors"][0]
		m.setup({"rig": sp["rig"], "scale": 1.0, "parts": sp.get("parts", []) + [{"id": "saddle", "socket": "saddle", "size": 0.55}],
			"colors": {"color_main": c.get("main", [0.4, 0.35, 0.3]), "color_belly": c.get("belly", [0.6, 0.55, 0.5]), "color_pattern": c.get("pattern", [0.2, 0.15, 0.1])},
			"pattern_type": c.get("pt", 1)})
		var r := CreatureVisual.new()
		root.add_child(r)
		r.setup({"rig": "human_m", "scale": 1.0, "parts": [], "colors": {"color_main": [0.62, 0.48, 0.38], "color_belly": [0.62, 0.48, 0.38], "eye_color": [0.12, 0.09, 0.07]},
			"pattern_type": 0, "use_wrinkle": 1.0, "tex_scale": 6.0, "bump_height": 0.002})
		r.animator.state = "sit"
		r.animator.straddle = float(m.meta.get("saddle_half_width", 0.0))
		for i in 10:
			await get_tree().process_frame
		var sp_pos: Vector3 = m.get_socket_global("saddle")
		r.global_position = sp_pos - Vector3(0, float(r.meta.get("hip_height", 0.95)) * 0.95 - 0.09, 0)
		for i in 20:
			await get_tree().process_frame
		var size: float = maxf(2.5, sp_pos.y * 1.6)
		for view in 2:
			var dir := Vector3(0.2, 0.25, -1.0).normalized() if view == 0 else Vector3(1.0, 0.3, -0.25).normalized()
			cam.position = sp_pos + dir * size * 2.0
			cam.look_at(sp_pos + Vector3(0, -sp_pos.y * 0.25, 0))
			for i in 4:
				await get_tree().process_frame
			get_tree().root.get_texture().get_image().save_png("%s_%s_%d.png" % [out, id, view])
		m.queue_free()
		r.queue_free()
		await get_tree().process_frame
	print("done")
	get_tree().quit()
