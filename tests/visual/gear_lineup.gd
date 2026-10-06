extends Node
## Renders a human with different gear in several poses (visual clipping check).
## godot --path . -- --visual=gear_lineup --out=<prefix>

const SETUPS := [
	["speer", "spear_stone", "", "spear"],
	["keule_schild", "club_wood", "shield_wood", "melee"],
	["bogen", "bow_wood", "", "bow"],
	["fackel", "torch", "", "torch"],
]
const POSES := [["idle", "", 0.0], ["lauf", "", 3.5], ["angriff", "thrust", 0.0], ["schlag", "overhead", 0.0]]


func _ready() -> void:
	var out := "/tmp/gear"
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
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, -35, 0)
	sun.light_energy = 1.2
	root.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 30
	root.add_child(cam)
	await get_tree().process_frame
	for su in SETUPS:
		for po in POSES:
			var vis := CreatureVisual.new()
			root.add_child(vis)
			vis.setup({"rig": "human_m", "scale": 1.0, "parts": [], "colors": {"color_main": [0.62, 0.48, 0.38], "color_belly": [0.62, 0.48, 0.38], "eye_color": [0.12, 0.09, 0.07]},
				"pattern_type": 0, "use_wrinkle": 1.0, "tex_scale": 6.0, "bump_height": 0.002})
			vis.set_gear("hand_R" if su[3] != "bow" else "hand_L", GearFactory.make_weapon({"id": su[1], "n": 1}))
			if su[2] != "":
				vis.set_gear("hand_L", GearFactory.make_weapon({"id": su[2], "n": 1}))
			vis.animator.hold_pose = su[3]
			vis.animator.speed = po[2]
			vis.animator.state = "move" if po[2] > 0.0 else "idle"
			if po[1] != "":
				vis.animator.play(po[1], 100.0)
				vis.animator.action_t = 0.45
			for i in 20:
				await get_tree().process_frame
			for view in 2:
				var dir := Vector3(0.15, 0.1, -1.0).normalized() if view == 0 else Vector3(1.0, 0.1, -0.2).normalized()
				cam.position = Vector3(0, 1.0, 0) + dir * 4.6
				cam.look_at(Vector3(0, 0.95, 0))
				for i in 4:
					await get_tree().process_frame
				get_tree().root.get_texture().get_image().save_png("%s_%s_%s_%d.png" % [out, su[0], po[0], view])
			vis.queue_free()
			await get_tree().process_frame
	print("done")
	get_tree().quit()
