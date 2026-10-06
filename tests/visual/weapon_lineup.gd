extends Node
## Close-up of all weapon meshes side by side: godot --path . -- --visual=weapon_lineup --out=<file.png>

const IDS := ["spear_stone", "club_wood", "axe_stone", "pick_stone", "sword_metal", "bow_wood", "crossbow", "donnerrohr", "staff_crystal", "shield_wood", "torch", "javelin"]


func _ready() -> void:
	var out := "/tmp/weapons.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.42, 0.45, 0.5)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.62, 0.66)
	e.ambient_light_energy = 0.6
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.5
	add_child(sun)
	var x := 0.0
	for id in IDS:
		var w := GearFactory.make_weapon({"id": id, "n": 1})
		add_child(w)
		w.position = Vector3(x, 0, 0)
		x += 0.45
	var cam := Camera3D.new()
	add_child(cam)
	cam.fov = 40
	cam.position = Vector3(x * 0.5 - 0.2, 1.0, 3.4)
	cam.look_at(Vector3(x * 0.5 - 0.2, 0.75, 0))
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()
